# 認証フロー統合

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [ログインフロー](#ログインフロー)
- [トークンリフレッシュフロー](#トークンリフレッシュフロー)
- [ログアウトフロー](#ログアウトフロー)
- [ユーザー登録フロー](#ユーザー登録フロー)
- [シーケンス図](#シーケンス図)

---

## 概要

本システムの認証フローは、BFF（Backend for Frontend）パターンを採用し、JWT方式による stateless な認証を実装しています。

### 認証フロー全体像

```
┌──────────┐
│ Browser  │
└────┬─────┘
     │ 1. Login Request
     ▼
┌─────────────────┐
│ Frontend BFF    │
│ (Next.js)       │
└────┬────────────┘
     │ 2. POST /api/v1/auth/login
     ▼
┌─────────────────┐
│ Auth Service    │
│ (Port: 8002)    │
└────┬────────────┘
     │ 3. Validate & Generate JWT
     │
     ├─→ PostgreSQL (authdb): ユーザー検証
     └─→ Redis: セッション保存
     │
     │ 4. Return JWT tokens
     ▼
┌─────────────────┐
│ Frontend BFF    │ ──→ Set httpOnly cookies
└────┬────────────┘
     │ 5. Success response
     ▼
┌──────────┐
│ Browser  │
└──────────┘
```

---

## ログインフロー

### ステップバイステップ

#### 1. ユーザーがログインフォーム送信

```typescript
// Frontend Component (React)
const handleLogin = async (email: string, password: string) => {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });

  if (response.ok) {
    // トークンはhttpOnly cookieに自動保存される
    router.push('/dashboard');
  }
};
```

#### 2. BFFがAuth Serviceへプロキシ

```typescript
// pages/api/auth/login.ts
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const { email, password } = req.body;

  try {
    // Auth Serviceへログインリクエスト
    const response = await fetch(
      `${process.env.AUTH_SERVER_URL}/api/v1/auth/login`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      }
    );

    if (!response.ok) {
      return res.status(response.status).json({ error: 'Login failed' });
    }

    const data = await response.json();

    // トークンをhttpOnly cookieに保存
    res.setHeader('Set-Cookie', [
      `access_token=${data.data.access_token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900`,
      `refresh_token=${data.data.refresh_token}; HttpOnly; Secure; SameSite=Strict; Path=/api/auth; Max-Age=604800`,
    ]);

    res.status(200).json({ user: data.data.user });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

#### 3. Auth Serviceでの認証処理

```python
# Auth Service: app/api/v1/endpoints/auth.py
@router.post("/login")
async def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    # 1. ユーザー検索
    user = await db.execute(
        select(User).where(User.email == credentials.email)
    )
    user = user.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # 2. アカウントロック確認
    if user.locked_until and user.locked_until > datetime.utcnow():
        raise HTTPException(status_code=403, detail="Account is locked")

    # 3. パスワード検証
    if not verify_password(credentials.password, user.hashed_password):
        await handle_failed_login(user.id)
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # 4. JWT生成
    access_token = create_access_token(
        user_id=str(user.id),
        email=user.email,
        role=user.role
    )
    refresh_token = create_refresh_token(user_id=str(user.id))

    # 5. セッション保存（Redis）
    await save_session(user.id, {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "login_at": datetime.utcnow().isoformat()
    })

    # 6. ログイン成功処理
    await reset_failed_attempts(user.id)

    return {
        "status": "success",
        "data": {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "Bearer",
            "expires_in": 900,
            "user": {
                "user_id": str(user.id),
                "email": user.email,
                "role": user.role
            }
        }
    }
```

---

## トークンリフレッシュフロー

### 自動リフレッシュ機能

```typescript
// lib/auth.ts
export async function refreshAccessToken() {
  const response = await fetch('/api/auth/refresh', {
    method: 'POST',
    credentials: 'include', // Cookie送信
  });

  if (!response.ok) {
    // リフレッシュ失敗 → ログイン画面へ
    window.location.href = '/login';
    return null;
  }

  return response.json();
}

// APIコール時の自動リフレッシュ
export async function fetchWithAuth(url: string, options: RequestInit = {}) {
  let response = await fetch(url, {
    ...options,
    credentials: 'include',
  });

  // 401エラー → トークンリフレッシュ後リトライ
  if (response.status === 401) {
    await refreshAccessToken();
    response = await fetch(url, {
      ...options,
      credentials: 'include',
    });
  }

  return response;
}
```

### BFFリフレッシュエンドポイント

```typescript
// pages/api/auth/refresh.ts
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const refreshToken = req.cookies.refresh_token;

  if (!refreshToken) {
    return res.status(401).json({ error: 'No refresh token' });
  }

  try {
    const response = await fetch(
      `${process.env.AUTH_SERVER_URL}/api/v1/auth/refresh`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      }
    );

    if (!response.ok) {
      return res.status(401).json({ error: 'Token refresh failed' });
    }

    const data = await response.json();

    // 新トークンをCookieに保存
    res.setHeader('Set-Cookie', [
      `access_token=${data.data.access_token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900`,
      `refresh_token=${data.data.refresh_token}; HttpOnly; Secure; SameSite=Strict; Path=/api/auth; Max-Age=604800`,
    ]);

    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

---

## ログアウトフロー

### クライアント側

```typescript
// lib/auth.ts
export async function logout() {
  await fetch('/api/auth/logout', {
    method: 'POST',
    credentials: 'include',
  });

  // ローカルストレージクリア
  localStorage.clear();
  sessionStorage.clear();

  // ログイン画面へリダイレクト
  window.location.href = '/login';
}
```

### BFFログアウト処理

```typescript
// pages/api/auth/logout.ts
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const accessToken = req.cookies.access_token;
  const refreshToken = req.cookies.refresh_token;

  if (accessToken) {
    try {
      // Auth Serviceへログアウトリクエスト
      await fetch(`${process.env.AUTH_SERVER_URL}/api/v1/auth/logout`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });
    } catch (error) {
      console.error('Logout error:', error);
    }
  }

  // Cookieクリア
  res.setHeader('Set-Cookie', [
    'access_token=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0',
    'refresh_token=; HttpOnly; Secure; SameSite=Strict; Path=/api/auth; Max-Age=0',
  ]);

  res.status(200).json({ success: true });
}
```

### Auth Serviceログアウト処理

```python
@router.post("/logout")
async def logout(
    current_user: dict = Depends(get_current_user),
    body: LogoutRequest = None
):
    # 1. アクセストークンをブラックリスト登録
    await blacklist_token(current_user["access_token"])

    # 2. リフレッシュトークンをブラックリスト登録
    if body and body.refresh_token:
        await blacklist_token(body.refresh_token)

    # 3. Redisセッション削除
    await redis_client.delete(f"session:{current_user['sub']}")

    return {"status": "success", "message": "Logout successful"}
```

---

## ユーザー登録フロー

### 登録処理

```python
@router.post("/register", status_code=201)
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    # 1. メールアドレス重複チェック
    existing_user = await db.execute(
        select(User).where(User.email == user_data.email)
    )
    if existing_user.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Email already registered")

    # 2. パスワードバリデーション
    is_valid, errors = validate_password_strength(user_data.password)
    if not is_valid:
        raise HTTPException(status_code=422, detail={"password": errors})

    # 3. パスワードハッシュ化
    hashed_password = hash_password(user_data.password)

    # 4. ユーザー作成
    new_user = User(
        id=uuid.uuid4(),
        email=user_data.email,
        hashed_password=hashed_password,
        role=user_data.role or "user",
        is_active=True,
        is_verified=False
    )
    db.add(new_user)
    await db.commit()

    # 5. プロフィール作成（User APIへ通知 or イベント発行）
    await create_user_profile(new_user.id, user_data.email)

    return {
        "status": "success",
        "data": {
            "user_id": str(new_user.id),
            "email": new_user.email,
            "role": new_user.role
        }
    }
```

---

## シーケンス図

### ログインシーケンス

```
Browser          BFF            Auth Service     PostgreSQL    Redis
  │               │                   │               │           │
  │──Login Form──>│                   │               │           │
  │               │                   │               │           │
  │               │──POST /login─────>│               │           │
  │               │                   │               │           │
  │               │                   │──Query User──>│           │
  │               │                   │<──User Data───│           │
  │               │                   │               │           │
  │               │                   │──Verify Password          │
  │               │                   │               │           │
  │               │                   │──Generate JWT             │
  │               │                   │               │           │
  │               │                   │──Save Session────────────>│
  │               │                   │<──OK──────────────────────│
  │               │                   │               │           │
  │               │<──JWT Tokens──────│               │           │
  │               │                   │               │           │
  │               │──Set Cookies──    │               │           │
  │<──Success─────│                   │               │           │
  │               │                   │               │           │
```

---

## 関連ドキュメント

- [認証サービスAPI仕様](../01-auth-service/02-api-specification.md)
- [JWT設計](../01-auth-service/03-jwt-design.md)
- [BFFパターン](./07-bff-pattern.md)
- [JWT検証フロー](./04-jwt-verification.md)