# JWT認証・認可フロー

## 概要

ai-micro-mcp-adminは、RS256署名のJWTトークンによる認証と、ロールベースアクセス制御(RBAC)による認可を実装しています。本ドキュメントでは、認証フロー、JWKS統合、権限チェックの詳細を説明します。

## JWT認証フロー

### 1. 全体フロー

```
┌──────────────────────────────────────────────────────────┐
│ Step 1: User Login                                        │
│ Frontend → api-auth (8002)                               │
│ POST /auth/login                                          │
│ Body: {email, password}                                   │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 2: Token Issuance                                    │
│ api-auth generates JWT tokens                            │
│ ├─ access_token (15 minutes expiry)                      │
│ │   - Signature: RS256 (RSA private key)                 │
│ │   - Claims: {sub, roles, aud, iss, exp, kid}           │
│ ├─ refresh_token (30 days expiry)                        │
│ └─ Response: {access_token, refresh_token, token_type}   │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 3: Client Stores Tokens                             │
│ Frontend stores in httpOnly cookies or localStorage      │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 4: Request with Authorization Header                │
│ Client → mcp-admin (8004)                                │
│ GET /mcp/tools                                            │
│ Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5...        │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 5: Token Verification (mcp-admin)                   │
│ ├─ Extract token from Authorization header               │
│ ├─ Dependency: get_current_user()                        │
│ │   └─ Call: verify_token(token)                         │
│ │       ├─ Extract 'kid' from JWT header                 │
│ │       ├─ Fetch JWKS from auth service (cached 10min)   │
│ │       ├─ Find matching public key by 'kid'             │
│ │       ├─ Reconstruct RSA public key                    │
│ │       ├─ Verify RS256 signature                        │
│ │       ├─ Validate claims: aud, iss, exp                │
│ │       └─ Return payload: {sub, roles, ...}             │
│ └─ If verification fails → 401 Unauthorized              │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 6: Authorization (RBAC)                             │
│ ├─ Extract user_id, roles from JWT payload               │
│ ├─ Check: super_admin or admin → bypass                  │
│ ├─ Else: Check KB access                                 │
│ │   └─ Query: created_by = user_id OR is_public = true   │
│ └─ If access denied → 403 Forbidden                      │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│ Step 7: Execute Request                                   │
│ └─ MCP tool execution with authorized context            │
└──────────────────────────────────────────────────────────┘
```

## JWT構造

### Header

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "key-1"
}
```

- `alg`: 署名アルゴリズム（RS256 = RSA + SHA256）
- `typ`: トークンタイプ（JWT）
- `kid`: 公開鍵ID（JWKS内で鍵を特定）

### Payload

```json
{
  "sub": "user-uuid-1234-5678",
  "roles": ["user"],
  "aud": "fastapi-api",
  "iss": "https://auth.example.com",
  "exp": 1699876543,
  "iat": 1699875643,
  "email": "user@example.com"
}
```

- `sub`: Subject（ユーザーID）
- `roles`: ユーザーロール配列（`super_admin`, `admin`, `user`）
- `aud`: Audience（対象サービス）
- `iss`: Issuer（発行元）
- `exp`: Expiration time（有効期限、Unix timestamp）
- `iat`: Issued at（発行時刻、Unix timestamp）

### Signature

```
RS256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  private_key
)
```

## JWKS (JSON Web Key Set) 統合

### JWKS エンドポイント

**URL**: `http://host.docker.internal:8002/.well-known/jwks.json`

**レスポンス例**:
```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "kid": "key-1",
      "n": "xGOr1YyLpj3U...（公開鍵のn値）",
      "e": "AQAB"
    }
  ]
}
```

- `kty`: 鍵タイプ（RSA）
- `use`: 使用目的（sig = 署名）
- `kid`: 鍵ID（JWTヘッダーのkidと一致）
- `n`, `e`: RSA公開鍵のパラメータ

### JWKS取得とキャッシュ

**ファイル**: `app/core/auth.py`

```python
from datetime import datetime
import httpx

_jwks_cache: Optional[Dict[str, Any]] = None
_jwks_cache_time: Optional[datetime] = None

async def get_jwks() -> Dict[str, Any]:
    """Fetch JWKS from auth service with 10-minute cache"""
    global _jwks_cache, _jwks_cache_time

    # Check cache validity
    if _jwks_cache and _jwks_cache_time:
        elapsed = (datetime.utcnow() - _jwks_cache_time).total_seconds()
        if elapsed < 600:  # 10 minutes
            logger.debug("Using cached JWKS")
            return _jwks_cache

    # Fetch from auth service
    logger.info("Fetching JWKS from auth service")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(settings.JWKS_URL)
            response.raise_for_status()

            _jwks_cache = response.json()
            _jwks_cache_time = datetime.utcnow()

            return _jwks_cache

    except httpx.RequestError as e:
        logger.error(f"Failed to fetch JWKS: {e}")
        raise HTTPException(
            status_code=503,
            detail="Authentication service unavailable"
        )
```

**キャッシュ戦略**:
- 有効期限: 10分間
- 目的: Auth Serviceへの過度なリクエスト回避
- 更新: 10分経過後に次回リクエストで自動更新

## JWT検証プロセス

### verify_token() 実装

**ファイル**: `app/core/auth.py`

```python
import jwt
from jwt.algorithms import RSAAlgorithm
import json

async def verify_token(token: str) -> Dict[str, Any]:
    """Verify JWT token with RS256 signature"""

    try:
        # 1. Extract 'kid' from unverified header
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        if not kid:
            raise ValueError("Missing 'kid' in JWT header")

        # 2. Fetch JWKS (with cache)
        jwks = await get_jwks()

        # 3. Find matching key by 'kid'
        key_data = next(
            (k for k in jwks["keys"] if k["kid"] == kid),
            None
        )

        if not key_data:
            raise ValueError(f"Public key not found for kid: {kid}")

        # 4. Reconstruct RSA public key
        public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))

        # 5. Verify signature and decode
        payload = jwt.decode(
            token,
            public_key,
            algorithms=[settings.JWT_ALGORITHM],
            audience=settings.JWT_AUDIENCE,
            issuer=settings.JWT_ISSUER
        )

        logger.debug(f"JWT verified for user: {payload.get('sub')}")
        return payload

    except jwt.ExpiredSignatureError:
        logger.warning("JWT token expired")
        raise HTTPException(status_code=401, detail="Token expired")

    except jwt.InvalidAudienceError:
        logger.warning("Invalid JWT audience")
        raise HTTPException(status_code=401, detail="Invalid token audience")

    except jwt.InvalidIssuerError:
        logger.warning("Invalid JWT issuer")
        raise HTTPException(status_code=401, detail="Invalid token issuer")

    except (jwt.InvalidTokenError, ValueError) as e:
        logger.warning(f"JWT verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid authentication credentials")

    except Exception as e:
        logger.error(f"Unexpected error during JWT verification: {e}")
        raise HTTPException(status_code=500, detail="Authentication error")
```

### 検証ステップ詳細

1. **Header解析**: `jwt.get_unverified_header()` でkidを抽出
2. **JWKS取得**: auth serviceからJWKS取得（10分キャッシュ）
3. **公開鍵特定**: kidでJWKS内の鍵を検索
4. **鍵再構築**: `RSAAlgorithm.from_jwk()` でRSA公開鍵を再構築
5. **署名検証**: `jwt.decode()` でRS256署名を検証
6. **クレーム検証**:
   - `audience`: "fastapi-api"
   - `issuer`: "https://auth.example.com"
   - `exp`: 有効期限チェック
7. **ペイロード返却**: {sub, roles, email, ...}

## 認可（Authorization）

### ロールベースアクセス制御 (RBAC)

**ロール階層**:
```
super_admin (最高権限)
    ├─ すべてのKBアクセス可
    ├─ すべてのユーザー管理可
    └─ システム設定変更可

admin
    ├─ すべてのKBアクセス可
    └─ ユーザー管理可（一部制限）

user
    ├─ 自分が作成したKBのみアクセス可
    └─ 公開KB（is_public=true）アクセス可
```

### KB アクセス制御

**ファイル**: `app/core/permissions.py`

```python
async def check_knowledge_base_access(
    user_id: str,
    knowledge_base_id: UUID,
    user_roles: list,
    db: Session
) -> bool:
    """Check if user has access to knowledge base"""

    # Admin bypass
    if "super_admin" in user_roles or "admin" in user_roles:
        logger.debug(f"Admin access granted for KB {knowledge_base_id}")
        return True

    # Query: created_by or is_public
    kb = db.query(KnowledgeBase).filter(
        KnowledgeBase.id == knowledge_base_id,
        or_(
            KnowledgeBase.created_by == user_id,
            KnowledgeBase.is_public == True
        )
    ).first()

    if kb:
        logger.debug(f"User {user_id} has access to KB {knowledge_base_id}")
        return True
    else:
        logger.warning(f"User {user_id} denied access to KB {knowledge_base_id}")
        return False
```

### デコレータパターン

```python
def require_knowledge_base_access(knowledge_base_id_param: str = "knowledge_base_id"):
    """Decorator to enforce KB access control"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            kb_id = kwargs.get(knowledge_base_id_param)
            current_user = kwargs.get("current_user")
            db = kwargs.get("db")

            if not kb_id:
                raise HTTPException(status_code=400, detail="Missing knowledge_base_id")

            # Check access
            has_access = await check_knowledge_base_access(
                user_id=current_user["sub"],
                knowledge_base_id=kb_id,
                user_roles=current_user.get("roles", []),
                db=db
            )

            if not has_access:
                raise HTTPException(
                    status_code=403,
                    detail="Access denied to this knowledge base"
                )

            return await func(*args, **kwargs)
        return wrapper
    return decorator

# Usage
@require_knowledge_base_access()
async def _search_documents(
    query: str,
    knowledge_base_id: UUID,
    current_user: dict,
    db: Session,
    ...
):
    # Function body (access already verified)
    pass
```

## 依存性注入

### get_current_user() 依存

**ファイル**: `app/dependencies/auth.py`

```python
from fastapi import Depends, HTTPException, Header
from typing import Optional

async def get_current_user(
    authorization: Optional[str] = Header(None)
) -> dict:
    """FastAPI dependency: Extract and verify JWT token"""

    # Check Authorization header
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header"
        )

    # Extract token
    token = authorization.replace("Bearer ", "")

    # Verify token
    try:
        payload = await verify_token(token)
        return payload

    except HTTPException:
        raise  # Re-raise HTTP exceptions from verify_token

    except Exception as e:
        logger.error(f"Unexpected error in get_current_user: {e}")
        raise HTTPException(status_code=500, detail="Authentication error")
```

### エンドポイントでの使用

```python
from fastapi import Depends

@router.get("/mcp/tools")
async def list_tools(
    current_user: dict = Depends(get_current_user)
):
    """List available MCP tools (JWT required)"""
    logger.info(f"Tools listed by user: {current_user['sub']}")
    mcp_server = get_mcp_server()
    return mcp_server.tools_list
```

## セキュリティベストプラクティス

### 1. トークン有効期限

| トークン | 有効期限 | 用途 |
|---------|---------|------|
| access_token | 15分 | API呼び出し認証 |
| refresh_token | 30日 | アクセストークン更新 |

**理由**:
- 短い有効期限: トークン漏洩時の被害最小化
- Refresh Token: ユーザー体験向上（再ログイン不要）

### 2. httpOnly Cookies

フロントエンドでのトークン保存:
```javascript
// ❌ ローカルストレージ（XSS脆弱）
localStorage.setItem('token', access_token);

// ✅ httpOnly Cookie（XSS対策）
document.cookie = `access_token=${token}; HttpOnly; Secure; SameSite=Strict`;
```

### 3. HTTPS必須

**本番環境**:
- すべての通信をHTTPS化
- Authorization headerの暗号化
- 中間者攻撃（MITM）対策

### 4. トークンブラックリスト（検討中）

**ログアウト時の対策**:
- Redisにブラックリストを保存
- `token_jti`をキーに有効期限まで保持
- 検証時にブラックリスト確認

### 5. レート制限

**認証エンドポイント**:
- ログイン: 10回/分（IP単位）
- JWT検証: 100回/分（ユーザー単位）

## トラブルシューティング

### 問題1: 401 Unauthorized

**症状**: `{"detail": "Invalid authentication credentials"}`

**原因**:
- JWTトークン期限切れ
- 署名検証失敗
- aud/iss不一致

**解決策**:
1. 新しいトークンを取得（再ログイン）
2. JWKS_URL設定確認
3. JWT_AUDIENCE/JWT_ISSUER設定確認

### 問題2: 503 Service Unavailable

**症状**: `{"detail": "Authentication service unavailable"}`

**原因**:
- Auth Service停止
- JWKS取得失敗

**解決策**:
1. Auth Service起動確認: `curl http://localhost:8002/health`
2. JWKS エンドポイント確認: `curl http://localhost:8002/.well-known/jwks.json`

### 問題3: 403 Forbidden

**症状**: `{"detail": "Access denied to this knowledge base"}`

**原因**:
- KBアクセス権限なし
- ユーザーロールが不適切

**解決策**:
1. KB作成者確認: `SELECT created_by FROM knowledge_bases WHERE id = 'kb-id'`
2. KB公開設定確認: `SELECT is_public FROM knowledge_bases WHERE id = 'kb-id'`
3. ユーザーロール確認: JWTペイロードの`roles`

## 関連ドキュメント

- [README.md](./README.md) - MCP Admin Service概要
- [01-architecture.md](./01-architecture.md) - 詳細アーキテクチャ（認証レイヤー）
- [02-mcp-tools.md](./02-mcp-tools.md) - MCPツール詳細
- [03-integration-api-admin.md](./03-integration-api-admin.md) - api-admin連携（JWT転送）
