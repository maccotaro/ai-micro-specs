# トークンセキュリティ

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [JWTトークン構造](#jwtトークン構造)
- [トークン有効期限](#トークン有効期限)
- [トークンブラックリスト](#トークンブラックリスト)
- [リフレッシュトークンローテーション](#リフレッシュトークンローテーション)
- [トークン無効化](#トークン無効化)

---

## 概要

### トークンベース認証の利点

JWT（JSON Web Token）ベースの認証は、マイクロサービスアーキテクチャにおいて以下の利点があります:

1. **ステートレス**: サーバー側でセッション情報を保持不要
2. **分散システム対応**: 複数のサービスで独立して検証可能
3. **スケーラブル**: 水平スケールが容易
4. **標準規格**: RFC 7519に準拠

### トークンの種類

| トークン種類 | 有効期限 | 用途 | 保存場所 |
|------------|---------|------|---------|
| **Access Token** | 15分 | APIアクセス | httpOnly Cookie / メモリ |
| **Refresh Token** | 30日 | Access Token更新 | httpOnly Cookie |

---

## JWTトークン構造

### トークンフォーマット

```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0xIn0.
eyJzdWIiOiI1NTBlODQwMC1lMjliLTQxZDQtYTcxNi00NDY2NTU0NDAwMDAiLCJpc3MiOiJodHRwczovL2F1dGguZXhhbXBsZS5jb20iLCJhdWQiOiJmYXN0YXBpLWFwaSIsImlhdCI6MTcyNzY1NDQwMCwiZXhwIjoxNzI3NjU1MzAwLCJqdGkiOiJhYmMxMjM0NS02Nzg5LTEyMzQtNTY3OC0xMjM0NTY3ODkwYWIiLCJzY29wZSI6ImFjY2VzcyIsInJvbGVzIjpbInVzZXIiXX0.
<signature>
  ↓           ↓          ↓
Header      Payload   Signature
```

### Header（ヘッダー）

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "key-1"
}
```

| フィールド | 説明 | 値 |
|----------|------|-----|
| `alg` | 署名アルゴリズム | RS256（RSA + SHA256） |
| `typ` | トークンタイプ | JWT |
| `kid` | 鍵ID | JWKS識別用 |

### Payload（ペイロード）

**Access Token**:
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "iss": "https://auth.example.com",
  "aud": "fastapi-api",
  "iat": 1727654400,
  "exp": 1727655300,
  "jti": "abc12345-6789-1234-5678-1234567890ab",
  "scope": "access",
  "roles": ["user", "admin"]
}
```

**Refresh Token**:
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "iss": "https://auth.example.com",
  "aud": "fastapi-api",
  "iat": 1727654400,
  "exp": 1730246400,
  "jti": "def67890-1234-5678-9012-3456789012cd",
  "scope": "refresh",
  "session_id": "session-uuid-here"
}
```

### Signature（署名）

RS256アルゴリズムによる署名:

```
RSASHA256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  privateKey
)
```

---

## トークン有効期限

### 有効期限設定

**設定ファイル**: `ai-micro-api-auth/app/core/config.py`

```python
class Settings(BaseSettings):
    ACCESS_TOKEN_TTL_SEC: int = 900       # 15分
    REFRESH_TOKEN_TTL_SEC: int = 2592000  # 30日
```

### 有効期限の理由

#### Access Token（15分）

**短い理由**:
- ✅ 窃取された場合の被害を最小化
- ✅ ロール変更の即時反映（15分以内）
- ✅ ログアウト後の不正利用防止

**デメリット**:
- ⚠️ 頻繁なトークンリフレッシュが必要

#### Refresh Token（30日）

**長い理由**:
- ✅ ユーザー体験向上（頻繁なログイン不要）
- ✅ モバイルアプリでの長期セッション

**セキュリティ対策**:
- ✅ トークンローテーション
- ✅ ログアウト時の即時無効化
- ✅ ブラックリスト管理

### トークン更新フロー

```
┌──────────┐                              ┌──────────┐
│ Client   │                              │  Server  │
└────┬─────┘                              └────┬─────┘
     │                                         │
     │  1. GET /api/profile                   │
     │     Authorization: Bearer <expired>    │
     ├────────────────────────────────────────→│
     │                                         │
     │  2. 401 Unauthorized                   │
     │     {"detail": "Token expired"}        │
     │←────────────────────────────────────────┤
     │                                         │
     │  3. POST /auth/refresh                 │
     │     {refresh_token: "xxx"}             │
     ├────────────────────────────────────────→│
     │                                         │
     │  4. Validate Refresh Token             │
     │     - Signature check                  │
     │     - Expiration check                 │
     │     - Blacklist check                  │
     │                                         │
     │  5. Issue New Tokens                   │
     │     - New Access Token (15min)         │
     │     - New Refresh Token (30days)       │
     │                                         │
     │  6. 200 OK                             │
     │     {access_token, refresh_token}      │
     │←────────────────────────────────────────┤
     │                                         │
     │  7. Retry Original Request             │
     │     Authorization: Bearer <new_token>  │
     ├────────────────────────────────────────→│
     │                                         │
     │  8. 200 OK                             │
     │     {profile data}                     │
     │←────────────────────────────────────────┤
     │                                         │
```

---

## トークンブラックリスト

### ブラックリストの必要性

JWT はステートレスですが、以下の場合にトークンを無効化する必要があります:

1. **ログアウト**: ユーザーが明示的にログアウト
2. **セキュリティ侵害**: トークン漏洩の疑い
3. **権限変更**: ロール変更・アカウント無効化

### Redis実装

**キーパターン**:
```
blacklist:access:<jti>  = "1"  (TTL: 15分)
blacklist:refresh:<jti> = "1"  (TTL: 30日)
```

**実装**: `ai-micro-api-auth/app/core/redis_manager.py`

```python
class RedisManager:
    """Redis operations manager"""

    @staticmethod
    async def blacklist_access_token(jti: str):
        """Blacklist access token"""
        await redis.setex(
            f"blacklist:access:{jti}",
            settings.ACCESS_TOKEN_TTL_SEC,
            "1"
        )

    @staticmethod
    async def blacklist_refresh_token(jti: str):
        """Blacklist refresh token"""
        await redis.setex(
            f"blacklist:refresh:{jti}",
            settings.REFRESH_TOKEN_TTL_SEC,
            "1"
        )

    @staticmethod
    async def is_access_token_blacklisted(jti: str) -> bool:
        """Check if access token is blacklisted"""
        return await redis.exists(f"blacklist:access:{jti}") > 0

    @staticmethod
    async def is_refresh_token_blacklisted(jti: str) -> bool:
        """Check if refresh token is blacklisted"""
        return await redis.exists(f"blacklist:refresh:{jti}") > 0
```

### トークン検証時のブラックリスト確認

```python
async def get_current_user(
    credentials = Depends(security),
    db: AsyncSession = Depends(get_db)
) -> User:
    """Get current user from access token"""
    try:
        # JWT検証
        payload = decode_token(credentials.credentials)

        # JTI取得
        access_jti = payload.get("jti")

        # ブラックリスト確認
        if await RedisManager.is_access_token_blacklisted(access_jti):
            raise ValueError("Token has been revoked")

        # ユーザー取得
        user_id = payload.get("sub")
        result = await db.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        return user

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid access token"
        )
```

---

## リフレッシュトークンローテーション

### ローテーションの重要性

**脅威**: リフレッシュトークンの盗難

**対策**: トークン使用時に新しいトークンを発行し、古いトークンを無効化

### 実装

**ファイル**: `ai-micro-api-auth/app/routers/auth.py`

```python
@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    request: RefreshRequest,
    db: AsyncSession = Depends(get_db)
) -> TokenResponse:
    """Token refresh with rotation"""
    try:
        # リフレッシュトークン検証
        payload = decode_token(request.refresh_token)

        if payload.get("scope") != "refresh":
            raise ValueError("Invalid token scope")

        refresh_jti = payload.get("jti")
        session_id = payload.get("session_id")
        user_id = payload.get("sub")

        # ブラックリスト確認
        if await RedisManager.is_refresh_token_blacklisted(refresh_jti):
            raise ValueError("Token has been revoked")

        # ユーザー取得
        result = await db.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        # 新しいトークン生成
        new_access_token, new_access_jti = create_access_token(
            user_id=str(user.id),
            roles=user.roles
        )
        new_refresh_token, new_refresh_jti, _ = create_refresh_token(
            user_id=str(user.id),
            session_id=session_id  # 同じセッションID
        )

        # 古いリフレッシュトークンをブラックリスト登録
        await RedisManager.blacklist_refresh_token(refresh_jti)

        # セッション更新
        await RedisManager.save_session(
            user_id=str(user.id),
            session_id=session_id,
            access_jti=new_access_jti,
            refresh_jti=new_refresh_jti
        )

        return TokenResponse(
            access_token=new_access_token,
            refresh_token=new_refresh_token,
            expires_in=settings.ACCESS_TOKEN_TTL_SEC
        )

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )
```

### リプレイ攻撃の検出

```python
# 古いリフレッシュトークンが再利用された場合
if await RedisManager.is_refresh_token_blacklisted(refresh_jti):
    # セキュリティ違反として検出
    logger.warning(f"Replay attack detected for user {user_id}")

    # セッション全体を無効化
    await invalidate_all_user_sessions(user_id)

    raise HTTPException(
        status_code=401,
        detail="Security violation: Token already used"
    )
```

---

## トークン無効化

### ログアウト時の無効化

```python
@router.post("/logout")
async def logout(request: LogoutRequest):
    """User logout with token invalidation"""
    try:
        # リフレッシュトークン検証
        payload = decode_token(request.refresh_token)
        refresh_jti = payload.get("jti")
        session_id = payload.get("session_id")
        user_id = payload.get("sub")

        # セッション取得
        session = await RedisManager.get_session(user_id, session_id)

        if session:
            # アクセストークン無効化
            await RedisManager.blacklist_access_token(session["access_jti"])

            # リフレッシュトークン無効化
            await RedisManager.blacklist_refresh_token(refresh_jti)

            # セッション削除
            await RedisManager.delete_session(user_id, session_id)

        return {"message": "Logged out successfully"}

    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Invalid refresh token"
        )
```

### 全セッション無効化

```python
async def invalidate_all_user_sessions(user_id: str):
    """Invalidate all sessions for a user"""
    # セッション一覧取得
    session_keys = await redis.keys(f"session:{user_id}:*")

    for key in session_keys:
        session = await redis.hgetall(key)

        # トークンをブラックリスト登録
        if session.get("access_jti"):
            await RedisManager.blacklist_access_token(session["access_jti"])

        if session.get("refresh_jti"):
            await RedisManager.blacklist_refresh_token(session["refresh_jti"])

        # セッション削除
        await redis.delete(key)

# 使用例: パスワード変更時
@router.post("/password/change")
async def change_password(request: PasswordChangeRequest, current_user = Depends(get_current_user)):
    user_id = current_user["sub"]

    # パスワード更新
    # ...

    # すべてのセッションを無効化
    await invalidate_all_user_sessions(user_id)

    return {"message": "Password changed. Please log in again."}
```

---

## セキュリティベストプラクティス

### 1. トークン保存

**推奨**:
- ✅ httpOnly Cookie（XSS攻撃耐性）
- ✅ メモリ内（React state）

**非推奨**:
- ❌ LocalStorage（XSS攻撃リスク）
- ❌ SessionStorage（XSS攻撃リスク）

### 2. トークン送信

**推奨**:
```typescript
// httpOnly Cookie（自動送信）
fetch('/api/profile', {
  credentials: 'include'
});

// Authorization ヘッダー
fetch('/api/profile', {
  headers: {
    'Authorization': `Bearer ${accessToken}`
  }
});
```

### 3. トークン更新

**自動更新実装**:
```typescript
// axios インターセプター
axios.interceptors.response.use(
  response => response,
  async error => {
    if (error.response?.status === 401) {
      try {
        // トークン更新
        const { data } = await axios.post('/auth/refresh', {
          refresh_token: getRefreshToken()
        });

        // 新しいトークンを保存
        setAccessToken(data.access_token);
        setRefreshToken(data.refresh_token);

        // 元のリクエストをリトライ
        error.config.headers['Authorization'] = `Bearer ${data.access_token}`;
        return axios(error.config);
      } catch (refreshError) {
        // リフレッシュ失敗 → ログアウト
        logout();
        return Promise.reject(refreshError);
      }
    }
    return Promise.reject(error);
  }
);
```

---

## トラブルシューティング

### 問題: トークンが即座に無効化される

**原因**: ブラックリスト登録の問題

**確認**:
```bash
# Redis確認
redis-cli
> GET blacklist:access:<jti>
> TTL blacklist:access:<jti>
```

### 問題: リフレッシュトークンが動作しない

**原因**: スコープ検証の失敗

**確認**:
```python
# トークンデコード
payload = decode_token(refresh_token)
print(payload.get("scope"))  # "refresh" であるべき
```

---

## 関連ドキュメント

- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [03-authorization-security.md](./03-authorization-security.md) - 認可セキュリティ
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)

---

**次のステップ**: [09-vulnerability-management.md](./09-vulnerability-management.md) を参照して、脆弱性管理を確認してください。
