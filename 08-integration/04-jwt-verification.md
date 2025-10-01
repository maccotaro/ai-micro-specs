# JWT検証フロー

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [検証プロセス](#検証プロセス)
- [JWKS統合](#jwks統合)
- [キャッシング戦略](#キャッシング戦略)
- [エラーハンドリング](#エラーハンドリング)
- [実装例](#実装例)

---

## 概要

各バックエンドサービス（User API, Admin API）は、Auth Serviceが発行したJWTを独立して検証します。RS256（RSA署名）を使用することで、公開鍵のみで署名検証が可能です。

### 検証フロー概要

```
1. リクエスト受信（Authorization: Bearer {token}）
2. JWKSから公開鍵取得（キャッシュ優先）
3. JWT署名検証
4. クレーム検証（exp, iss, aud）
5. ブラックリスト確認（Redis）
6. ユーザー情報抽出
```

---

## 検証プロセス

### ステップ1: トークン抽出

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def extract_token(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> str:
    """Authorizationヘッダーからトークン抽出"""
    return credentials.credentials
```

### ステップ2: 公開鍵取得

```python
import httpx
from functools import lru_cache
import time

@lru_cache(maxsize=1)
def get_jwks_cache():
    """JWKSキャッシュストレージ"""
    return {}

async def fetch_jwks() -> dict:
    """Auth ServiceからJWKS取得（1時間キャッシュ）"""
    cache = get_jwks_cache()
    current_time = time.time()

    # キャッシュが有効な場合
    if "keys" in cache and cache.get("expires_at", 0) > current_time:
        return cache["keys"]

    # JWKSを取得
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(
            "http://host.docker.internal:8002/.well-known/jwks.json"
        )
        response.raise_for_status()

        jwks = response.json()
        cache["keys"] = jwks
        cache["expires_at"] = current_time + 3600  # 1時間

        return jwks
```

### ステップ3: JWT検証

```python
from jose import jwt, JWTError

async def verify_jwt(token: str) -> dict:
    """JWT検証"""
    try:
        # 1. ヘッダー取得（検証なし）
        header = jwt.get_unverified_header(token)

        # 2. JWKS取得
        jwks = await fetch_jwks()

        # 3. kidに対応する公開鍵を検索
        key = next(
            (k for k in jwks["keys"] if k["kid"] == header["kid"]),
            None
        )

        if not key:
            raise ValueError("Public key not found")

        # 4. JWT検証
        payload = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience="fastapi-api",
            issuer="https://auth.example.com"
        )

        return payload

    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )
```

### ステップ4: クレーム検証

```python
from datetime import datetime

def validate_claims(payload: dict) -> None:
    """クレームバリデーション"""

    # exp（有効期限）チェック
    exp = payload.get("exp")
    if not exp or datetime.utcfromtimestamp(exp) < datetime.utcnow():
        raise ValueError("Token has expired")

    # iss（発行者）チェック
    if payload.get("iss") != "https://auth.example.com":
        raise ValueError("Invalid issuer")

    # aud（対象者）チェック
    if payload.get("aud") != "fastapi-api":
        raise ValueError("Invalid audience")

    # sub（主体）チェック
    if not payload.get("sub"):
        raise ValueError("Missing subject")

    # token_typeチェック
    if payload.get("token_type") != "access":
        raise ValueError("Invalid token type")
```

### ステップ5: ブラックリスト確認

```python
import redis.asyncio as redis

redis_client = redis.from_url("redis://localhost:6379")

async def is_token_blacklisted(token: str) -> bool:
    """トークンブラックリスト確認"""
    try:
        payload = jwt.get_unverified_claims(token)
        jti = payload.get("jti") or token[:50]

        exists = await redis_client.exists(f"blacklist:{jti}")
        return bool(exists)

    except Exception:
        return True  # エラー時は安全側に倒す
```

---

## JWKS統合

### JWKS取得エンドポイント

```python
# Auth Service: .well-known/jwks.json
@app.get("/.well-known/jwks.json")
async def get_jwks():
    """公開鍵をJWKS形式で提供"""
    with open("keys/public_key.pem", "r") as f:
        public_key = f.read()

    # PEMをJWK形式に変換
    jwk = RSAAlgorithm.from_jwk(public_key)

    return {
        "keys": [
            {
                "kty": "RSA",
                "use": "sig",
                "kid": "auth-service-key-1",
                "alg": "RS256",
                "n": jwk.n,  # モジュラス
                "e": jwk.e   # 指数
            }
        ]
    }
```

### マルチキー対応（キーローテーション）

```python
async def fetch_jwks_multikey() -> dict:
    """複数公開鍵対応JWKS取得"""
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "http://host.docker.internal:8002/.well-known/jwks.json"
        )
        return response.json()

async def get_public_key_by_kid(kid: str) -> dict:
    """kidに対応する公開鍵取得"""
    jwks = await fetch_jwks_multikey()

    for key in jwks["keys"]:
        if key["kid"] == kid:
            return key

    raise ValueError(f"Public key with kid '{kid}' not found")
```

---

## キャッシング戦略

### 3層キャッシング

```python
# レベル1: メモリキャッシュ（アプリケーションレベル）
from functools import lru_cache

@lru_cache(maxsize=10)
def memory_cache_jwks(cache_key: str):
    return get_jwks_cache()

# レベル2: Redisキャッシュ
async def redis_cache_jwks():
    """RedisからJWKS取得"""
    cached = await redis_client.get("jwks:auth-service")
    if cached:
        return json.loads(cached)
    return None

async def set_redis_cache_jwks(jwks: dict):
    """RedisにJWKSキャッシュ"""
    await redis_client.setex(
        "jwks:auth-service",
        3600,  # 1時間
        json.dumps(jwks)
    )

# レベル3: Auth Serviceから取得
async def fetch_jwks_with_cache() -> dict:
    """キャッシュ優先JWKS取得"""

    # メモリキャッシュチェック
    cache = get_jwks_cache()
    if "keys" in cache and cache.get("expires_at", 0) > time.time():
        return cache["keys"]

    # Redisキャッシュチェック
    redis_cached = await redis_cache_jwks()
    if redis_cached:
        cache["keys"] = redis_cached
        cache["expires_at"] = time.time() + 3600
        return redis_cached

    # Auth Serviceから取得
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(
            "http://host.docker.internal:8002/.well-known/jwks.json"
        )
        jwks = response.json()

        # キャッシュ保存
        cache["keys"] = jwks
        cache["expires_at"] = time.time() + 3600
        await set_redis_cache_jwks(jwks)

        return jwks
```

---

## エラーハンドリング

### エラーケースと対応

```python
from jose import JWTError, ExpiredSignatureError, JWTClaimsError

async def verify_token_with_error_handling(token: str) -> dict:
    """包括的エラーハンドリング付きトークン検証"""
    try:
        # JWT検証
        payload = await verify_jwt(token)

        # ブラックリスト確認
        if await is_token_blacklisted(token):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )

        return payload

    except ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
            headers={"WWW-Authenticate": "Bearer"},
        )

    except JWTClaimsError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token claims: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    except httpx.HTTPError:
        # JWKS取得失敗 → Auth Service問題
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unavailable",
        )

    except Exception as e:
        # 予期しないエラー
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error during token verification",
        )
```

---

## 実装例

### FastAPI依存性注入

```python
from fastapi import Depends

async def get_current_user(
    token: str = Depends(extract_token)
) -> dict:
    """現在のユーザー取得（JWT検証）"""
    payload = await verify_token_with_error_handling(token)
    return payload

# エンドポイントでの使用
@app.get("/api/v1/profiles/me")
async def get_my_profile(
    current_user: dict = Depends(get_current_user)
):
    """自分のプロフィール取得"""
    user_id = current_user["sub"]
    profile = await get_profile_from_db(user_id)
    return {"profile": profile}
```

### ミドルウェアによる一括検証

```python
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class JWTAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # 認証不要エンドポイントをスキップ
        if request.url.path in ["/health", "/docs", "/.well-known/jwks.json"]:
            return await call_next(request)

        # Authorizationヘッダー取得
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return JSONResponse(
                status_code=401,
                content={"detail": "Missing or invalid authorization header"}
            )

        token = auth_header.split(" ")[1]

        try:
            # JWT検証
            payload = await verify_token_with_error_handling(token)
            request.state.user = payload

        except HTTPException as e:
            return JSONResponse(
                status_code=e.status_code,
                content={"detail": e.detail}
            )

        return await call_next(request)

# ミドルウェア適用
app.add_middleware(JWTAuthMiddleware)
```

---

## 関連ドキュメント

- [JWT設計](../01-auth-service/03-jwt-design.md)
- [認証フロー統合](./02-authentication-flow.md)
- [サービス間通信](./01-service-communication.md)