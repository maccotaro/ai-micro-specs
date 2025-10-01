# 認可セキュリティ

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [ロールベースアクセス制御（RBAC）](#ロールベースアクセス制御rbac)
- [ロール定義](#ロール定義)
- [JWTクレーム検証](#jwtクレーム検証)
- [サービス間認可](#サービス間認可)
- [リソースレベルアクセス制御](#リソースレベルアクセス制御)

---

## 概要

### 認証vs認可

**認証（Authentication）**: ユーザーが誰であるかを確認
**認可（Authorization）**: ユーザーが何をできるかを決定

```
┌──────────────────────────────────────────────────────────┐
│  認証（Authentication）                                    │
│  "あなたは誰ですか？"                                       │
│                                                          │
│  ユーザーID: user@example.com                             │
│  パスワード: ********                                     │
│                                                          │
│  ✅ 認証成功 → JWT発行                                     │
└──────────────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────────────┐
│  認可（Authorization）                                     │
│  "あなたは何ができますか？"                                 │
│                                                          │
│  ロール: ["user"]                                         │
│  リソース: /admin/users                                   │
│                                                          │
│  ❌ 認可失敗 → 403 Forbidden                              │
└──────────────────────────────────────────────────────────┘
```

### 認可アーキテクチャ

ai-micro-service システムは、JWT に埋め込まれたロール情報に基づいて RBAC（Role-Based Access Control）を実装しています。

---

## ロールベースアクセス制御（RBAC）

### RBAC概要

**ロールベースアクセス制御**は、ユーザーにロール（役割）を割り当て、ロールごとに権限を定義する手法です。

### RBACモデル図

```
┌────────────────────────────────────────────────────────────┐
│  User                    Role              Permission      │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  john@example.com  ───→  user  ───→  ・自分のプロファイル編集│
│                                      ・自分のドキュメント閲覧│
│                                                            │
│  admin@example.com ───→  admin ───→  ・全ユーザー閲覧      │
│                                      ・ドキュメント管理      │
│                                      ・システムログ閲覧      │
│                                                            │
│  root@example.com  ───→  super_    ───→  ・全権限         │
│                          admin          ・ユーザー管理      │
│                                      ・ロール変更          │
│                                      ・システム設定        │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### ロール階層

```
super_admin
    │
    ├─ すべてのadmin権限
    ├─ ユーザー管理（ロール変更、削除）
    └─ システム設定
    ↓
admin
    │
    ├─ すべてのuser権限
    ├─ ドキュメント管理
    ├─ システムログ閲覧
    └─ ログイン履歴閲覧
    ↓
user
    │
    ├─ 自分のプロファイル閲覧・編集
    ├─ 自分のドキュメント閲覧・アップロード
    └─ 基本的なAPI利用
```

---

## ロール定義

### データベーススキーマ

**テーブル**: `authdb.users`

```sql
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  roles TEXT[] NOT NULL DEFAULT ARRAY['user'],  -- ロール配列
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,
  login_attempts INTEGER DEFAULT 0,
  last_login_at TIMESTAMP,
  locked_until TIMESTAMP
);
```

### ロール詳細

#### 1. user（一般ユーザー）

**付与タイミング**: サインアップ時にデフォルトで付与

**権限**:
- ✅ 自分のプロファイル閲覧・編集（`GET/PUT /api/profiles/me`）
- ✅ 自分のドキュメントアップロード（`POST /api/documents`）
- ✅ 自分のドキュメント閲覧（`GET /api/documents?user_id=<own_id>`）
- ❌ 他ユーザーのデータへのアクセス
- ❌ 管理機能へのアクセス

**JWT クレーム例**:
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "roles": ["user"],
  "scope": "access"
}
```

#### 2. admin（管理者）

**付与タイミング**: super_admin が手動で付与

**権限**:
- ✅ user の全権限
- ✅ 全ユーザーのプロファイル閲覧（`GET /api/profiles`）
- ✅ 全ドキュメント管理（`GET/PUT/DELETE /api/admin/documents`）
- ✅ システムログ閲覧（`GET /api/admin/logs`）
- ✅ ログイン履歴閲覧（`GET /api/admin/login-logs`）
- ❌ ユーザーロール変更
- ❌ ユーザー削除

**JWT クレーム例**:
```json
{
  "sub": "660e8400-e29b-41d4-a716-446655440001",
  "roles": ["user", "admin"],
  "scope": "access"
}
```

#### 3. super_admin（スーパー管理者）

**付与タイミング**: データベース直接操作 or 初回セットアップ

**権限**:
- ✅ admin の全権限
- ✅ ユーザーロール変更（`PUT /api/admin/users/{user_id}/roles`）
- ✅ ユーザー削除（`DELETE /api/admin/users/{user_id}`）
- ✅ システム設定変更（`PUT /api/admin/settings`）
- ✅ すべての管理機能

**JWT クレーム例**:
```json
{
  "sub": "770e8400-e29b-41d4-a716-446655440002",
  "roles": ["user", "admin", "super_admin"],
  "scope": "access"
}
```

### ロール割り当て

**新規ユーザー登録時**:

```python
# app/routers/auth.py
@router.post("/signup", response_model=SignUpResponse)
async def signup(
    request: SignUpRequest,
    db: AsyncSession = Depends(get_db)
) -> SignUpResponse:
    user = User(
        email=request.email,
        password_hash=create_password_hash(request.password),
        roles=["user"]  # デフォルトロール
    )
    db.add(user)
    await db.commit()
    return SignUpResponse(user_id=user.id)
```

**管理者によるロール変更**:

```python
# app/routers/admin.py
@router.put("/users/{user_id}/roles")
async def update_user_roles(
    user_id: str,
    roles: List[str],
    current_user: User = Depends(require_super_admin),
    db: AsyncSession = Depends(get_db)
):
    """Update user roles (super_admin only)"""
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 有効なロールかチェック
    valid_roles = ["user", "admin", "super_admin"]
    if not all(role in valid_roles for role in roles):
        raise HTTPException(status_code=400, detail="Invalid roles")

    user.roles = roles
    await db.commit()
    return {"message": "Roles updated successfully"}
```

---

## JWTクレーム検証

### クレーム検証フロー

```
┌─────────────────────────────────────────────────────────┐
│  JWT Validation & Authorization Flow                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. Extract JWT from Authorization Header              │
│     Authorization: Bearer eyJ...                        │
│                                                         │
│  2. Verify JWT Signature (RS256)                       │
│     ✅ Signature valid?                                 │
│                                                         │
│  3. Verify Standard Claims                             │
│     ✅ iss == "https://auth.example.com"?               │
│     ✅ aud == "fastapi-api"?                            │
│     ✅ exp > now?                                       │
│                                                         │
│  4. Check Token Blacklist (Redis)                      │
│     ✅ Not blacklisted?                                 │
│                                                         │
│  5. Extract User ID & Roles                            │
│     sub: "550e8400-..."                                │
│     roles: ["user", "admin"]                           │
│                                                         │
│  6. Check Required Roles for Endpoint                  │
│     Required: ["admin"]                                │
│     User has: ["user", "admin"]                        │
│     ✅ Authorization granted                            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### ロールチェック実装

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/security.py`

```python
def require_roles(allowed_roles: List[str]):
    """Dependency to check if user has required roles"""
    def role_checker(current_user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        user_roles = current_user.get("roles", [])
        if not any(role in user_roles for role in allowed_roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions"
            )
        return current_user
    return role_checker
```

### エンドポイントでの使用例

```python
from fastapi import APIRouter, Depends
from app.core.security import require_roles

router = APIRouter()

# 一般ユーザーのみアクセス可能
@router.get("/profile/me")
async def get_my_profile(
    current_user = Depends(require_roles(["user"]))
):
    return {"user_id": current_user["sub"]}

# 管理者のみアクセス可能
@router.get("/admin/logs")
async def get_system_logs(
    current_user = Depends(require_roles(["admin"]))
):
    return {"logs": [...]}

# スーパー管理者のみアクセス可能
@router.delete("/admin/users/{user_id}")
async def delete_user(
    user_id: str,
    current_user = Depends(require_roles(["super_admin"]))
):
    return {"message": "User deleted"}
```

---

## サービス間認可

### マイクロサービス間のJWT検証

各サービスは独立して JWT を検証します。

### User API Service での検証

**ファイル**: `ai-micro-api-user/app/core/security.py`

```python
import requests
from jose import jwt
from functools import lru_cache

@lru_cache(maxsize=1)
def get_jwks():
    """Fetch JWKS from Auth Service (cached)"""
    jwks_url = settings.JWKS_URL
    response = requests.get(jwks_url)
    response.raise_for_status()
    return response.json()

def verify_token(token: str) -> dict:
    """Verify JWT token using JWKS"""
    jwks = get_jwks()

    payload = jwt.decode(
        token,
        jwks,
        algorithms=["RS256"],
        issuer=settings.JWT_ISS,
        audience=settings.JWT_AUD
    )

    return payload
```

### Admin API Service での検証

**ファイル**: `ai-micro-api-admin/app/core/security.py`

```python
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer

security = HTTPBearer()

async def get_current_admin(
    credentials = Depends(security)
) -> dict:
    """Get current admin user from JWT"""
    try:
        payload = verify_token(credentials.credentials)

        # Check if user has admin role
        roles = payload.get("roles", [])
        if "admin" not in roles and "super_admin" not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin access required"
            )

        return payload

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )
```

---

## リソースレベルアクセス制御

### オーナーシップベースのアクセス制御

ユーザーは自分が所有するリソースのみにアクセスできます。

### プロファイルアクセス制御

```python
@router.get("/profiles/me")
async def get_my_profile(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get current user's profile"""
    user_id = current_user["sub"]

    profile = await db.get(Profile, user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    return profile

@router.get("/profiles/{user_id}")
async def get_user_profile(
    user_id: str,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get specific user's profile (admin only or own profile)"""
    requester_id = current_user["sub"]
    requester_roles = current_user.get("roles", [])

    # Check if user is accessing own profile or is admin
    if user_id != requester_id and "admin" not in requester_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    profile = await db.get(Profile, user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    return profile
```

### ドキュメントアクセス制御

```python
@router.get("/documents/{document_id}")
async def get_document(
    document_id: str,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get document (owner or admin only)"""
    user_id = current_user["sub"]
    roles = current_user.get("roles", [])

    document = await db.get(Document, document_id)
    if not document:
        raise HTTPException(status_code=404, detail="Document not found")

    # Check access permissions
    is_owner = document.user_id == user_id
    is_admin = "admin" in roles or "super_admin" in roles
    is_public = document.is_public

    if not (is_owner or is_admin or is_public):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    return document
```

### Knowledge Base アクセス制御

```python
@router.get("/knowledge-bases/{kb_id}")
async def get_knowledge_base(
    kb_id: str,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get knowledge base (with permission check)"""
    user_id = current_user["sub"]
    roles = current_user.get("roles", [])

    kb = await db.get(KnowledgeBase, kb_id)
    if not kb:
        raise HTTPException(status_code=404, detail="Knowledge base not found")

    # Check permissions
    permissions = kb.permissions or []

    is_owner = kb.user_id == user_id
    is_admin = "admin" in roles or "super_admin" in roles
    is_public = kb.is_public
    has_permission = user_id in permissions

    if not (is_owner or is_admin or is_public or has_permission):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    return kb
```

---

## セキュリティベストプラクティス

### 1. 最小権限の原則

**原則**: ユーザーに必要最小限の権限のみを付与

**実装**:
- デフォルトロール: `user`
- 必要に応じて `admin`, `super_admin` を付与
- 定期的な権限レビュー

### 2. 職務分離

**原則**: 重要な操作には複数の承認が必要

**実装例**:
- ユーザー削除: `super_admin` のみ
- ロール変更: `super_admin` のみ
- システム設定: `super_admin` のみ

### 3. 監査ログ

**記録すべきイベント**:
- ✅ ロール変更
- ✅ 権限エラー（403 Forbidden）
- ✅ 管理者操作
- ✅ 機密データアクセス

**実装例**:
```python
async def log_role_change(
    user_id: str,
    old_roles: List[str],
    new_roles: List[str],
    changed_by: str
):
    """Log role change event"""
    log_entry = SystemLog(
        service_name="auth-service",
        level="INFO",
        message=f"Roles changed for user {user_id}",
        log_metadata={
            "user_id": user_id,
            "old_roles": old_roles,
            "new_roles": new_roles,
            "changed_by": changed_by,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    )
    await save_log(log_entry)
```

### 4. エラーメッセージ

**推奨**:
- ❌ "User with email user@example.com does not have admin role"
- ✅ "Access denied"

**理由**: 詳細なエラーメッセージは情報漏えいのリスク

---

## トラブルシューティング

### 問題: 403 Forbidden エラー

**原因**:
1. 必要なロールを持っていない
2. JWT に roles クレームが含まれていない
3. リソースのオーナーではない

**確認方法**:
```bash
# JWT デコード
echo "eyJ..." | base64 -d | jq .

# 出力例
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "roles": ["user"],  # admin が必要なエンドポイントなら403
  "iss": "https://auth.example.com",
  "aud": "fastapi-api",
  "exp": 1727655300
}
```

### 問題: ロール変更が反映されない

**原因**: JWT はステートレスなため、既存トークンには反映されない

**解決策**:
1. ユーザーに再ログインを促す
2. リフレッシュトークンで新しいアクセストークンを取得
3. 強制ログアウト（セッション削除 + ブラックリスト登録）

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [08-token-security.md](./08-token-security.md) - トークンセキュリティ

### サービス詳細
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)
- [User API Service](/02-user-api/01-overview.md)
- [Admin API Service](/03-admin-api/01-overview.md)

---

**次のステップ**: [04-data-protection.md](./04-data-protection.md) を参照して、データ保護の実装を確認してください。