# 認可フロー

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [ロールベース認可](#ロールベース認可)
- [リソースベース認可](#リソースベース認可)
- [認可チェックポイント](#認可チェックポイント)
- [実装パターン](#実装パターン)

---

## 概要

認可（Authorization）は、認証済みユーザーが特定のリソースやアクションにアクセスする権限を持っているかを判定するプロセスです。

### 認可方式

本システムでは以下の認可方式を組み合わせて使用します：

1. **ロールベース認可（RBAC）**: ユーザーロールに基づく権限管理
2. **リソースベース認可**: リソース所有者のみアクセス可能
3. **属性ベース認可（ABAC）**: 複数条件の組み合わせ（将来実装）

---

## ロールベース認可

### ロール定義

```python
from enum import Enum

class UserRole(str, Enum):
    USER = "user"        # 一般ユーザー
    ADMIN = "admin"      # 管理者
```

### ロール権限マトリクス

| リソース/アクション | user | admin |
|-------------------|------|-------|
| プロフィール閲覧（自分） | ✓ | ✓ |
| プロフィール編集（自分） | ✓ | ✓ |
| プロフィール閲覧（他人） | ✗ | ✓ |
| プロフィール編集（他人） | ✗ | ✓ |
| ユーザー一覧表示 | ✗ | ✓ |
| ユーザー削除 | ✗ | ✓ |
| ドキュメント処理 | ✗ | ✓ |
| システム設定変更 | ✗ | ✓ |

### FastAPI実装

```python
from fastapi import Depends, HTTPException, status

def require_role(*allowed_roles: str):
    """ロール検証デコレーター"""
    async def role_checker(current_user: dict = Depends(get_current_user)):
        if current_user.get("role") not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions"
            )
        return current_user
    return role_checker

# 使用例
@app.get("/api/v1/admin/users")
async def list_all_users(
    current_user: dict = Depends(require_role("admin"))
):
    """管理者のみアクセス可能"""
    users = await get_all_users()
    return {"users": users}
```

---

## リソースベース認可

### 所有者チェック

```python
@app.get("/api/v1/profiles/{user_id}")
async def get_profile(
    user_id: str,
    current_user: dict = Depends(get_current_user)
):
    """プロフィール取得（自分or管理者）"""

    # 自分のプロフィールまたは管理者のみアクセス可能
    if current_user["sub"] != user_id and current_user["role"] != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    profile = await get_user_profile(user_id)
    return {"profile": profile}
```

### リソース所有権検証

```python
async def verify_resource_ownership(
    resource_id: str,
    resource_type: str,
    current_user: dict
) -> bool:
    """リソース所有権検証"""

    # 管理者は全リソースアクセス可能
    if current_user["role"] == "admin":
        return True

    # リソース取得
    resource = await get_resource(resource_type, resource_id)

    # 所有者チェック
    return resource.user_id == current_user["sub"]
```

---

## 認可チェックポイント

### 1. BFF層での認可

```typescript
// middleware.ts
export function middleware(req: NextRequest) {
  const accessToken = req.cookies.get('access_token');

  if (!accessToken) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // JWT検証
  const decoded = verifyJWT(accessToken);

  // 管理者専用ページへのアクセス制御
  if (req.nextUrl.pathname.startsWith('/admin') && decoded.role !== 'admin') {
    return NextResponse.redirect(new URL('/forbidden', req.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*', '/admin/:path*'],
};
```

### 2. API Gateway層での認可（将来実装）

```yaml
# Kong Gateway設定例
routes:
  - name: admin-api
    paths:
      - /admin
    plugins:
      - name: jwt
        config:
          claims_to_verify:
            - exp
            - role
      - name: request-termination
        config:
          status_code: 403
          message: "Admin role required"
        enabled: false  # roleがadminでない場合に有効化
```

### 3. バックエンドサービス層での認可

```python
@app.delete("/api/v1/users/{user_id}")
async def delete_user(
    user_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ユーザー削除（管理者のみ）"""

    # 1. ロールチェック
    if current_user["role"] != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required"
        )

    # 2. 自己削除防止
    if user_id == current_user["sub"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete own account"
        )

    # 3. 削除処理
    await delete_user_from_db(user_id)

    return {"status": "success"}
```

---

## 実装パターン

### デコレーターベースの認可

```python
from functools import wraps

def authorize(
    roles: list[str] = None,
    require_ownership: bool = False,
    resource_param: str = None
):
    """汎用認可デコレーター"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # 依存性注入から current_user 取得
            current_user = kwargs.get("current_user")

            # ロールチェック
            if roles and current_user["role"] not in roles:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Insufficient role"
                )

            # 所有権チェック
            if require_ownership and resource_param:
                resource_id = kwargs.get(resource_param)
                if not await verify_ownership(resource_id, current_user):
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Resource access denied"
                    )

            return await func(*args, **kwargs)
        return wrapper
    return decorator

# 使用例
@app.put("/api/v1/documents/{document_id}")
@authorize(roles=["admin"], require_ownership=True, resource_param="document_id")
async def update_document(
    document_id: str,
    data: DocumentUpdate,
    current_user: dict = Depends(get_current_user)
):
    """ドキュメント更新（管理者かつ所有者のみ）"""
    return await update_document_in_db(document_id, data)
```

### ポリシーベースの認可

```python
from typing import Protocol

class AuthorizationPolicy(Protocol):
    async def is_authorized(self, user: dict, resource: any) -> bool:
        ...

class AdminOnlyPolicy:
    async def is_authorized(self, user: dict, resource: any) -> bool:
        return user.get("role") == "admin"

class OwnerOrAdminPolicy:
    async def is_authorized(self, user: dict, resource: any) -> bool:
        if user.get("role") == "admin":
            return True
        return resource.user_id == user.get("sub")

# ポリシー適用
async def check_authorization(
    policy: AuthorizationPolicy,
    user: dict,
    resource: any
) -> None:
    if not await policy.is_authorized(user, resource):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Authorization failed"
        )

# 使用例
@app.get("/api/v1/documents/{document_id}")
async def get_document(
    document_id: str,
    current_user: dict = Depends(get_current_user)
):
    document = await get_document_from_db(document_id)
    await check_authorization(
        OwnerOrAdminPolicy(),
        current_user,
        document
    )
    return {"document": document}
```

---

## 関連ドキュメント

- [認証フロー統合](./02-authentication-flow.md)
- [JWT検証フロー](./04-jwt-verification.md)
- [セキュリティ実装](../01-auth-service/05-security-implementation.md)