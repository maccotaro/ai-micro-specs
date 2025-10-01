# Auth Service の Redis 使用法

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [セッション管理](#セッション管理)
- [トークンブラックリスト](#トークンブラックリスト)
- [ログイン試行回数制限](#ログイン試行回数制限)
- [実装詳細](#実装詳細)
- [エラーハンドリング](#エラーハンドリング)

---

## 概要

### Auth Service における Redis の役割

Auth Service (`ai-micro-api-auth`) は、ユーザー認証とトークン管理を担当するマイクロサービスです。Redis は以下の3つの主要機能で利用されます：

1. **セッション管理**: ユーザーのログイン状態を保持
2. **トークンブラックリスト**: ログアウト時のトークン無効化
3. **ログイン試行回数制限**: ブルートフォース攻撃の防止

### 接続情報

**サービス**: ai-micro-api-auth (Port 8002)
**Redis URL**: `redis://:<password>@host.docker.internal:6379`
**クライアント**: redis-py

---

## セッション管理

### セッションの作成

ユーザーがログインすると、Auth Service は以下の情報を Redis に保存します：

**キーパターン**:
```
session:<user_id>:<session_id>
```

**データ構造**:
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "session_id": "sess-7f3d9a1b",
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "created_at": "2025-09-30T10:00:00Z",
  "expires_at": "2025-09-30T11:00:00Z",
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)..."
}
```

**TTL**: 3600秒（1時間）

### 実装例: ログイン処理

```python
# app/routers/auth.py

from fastapi import APIRouter, Depends, HTTPException, status
from datetime import datetime, timedelta
import uuid
import json

router = APIRouter()

@router.post("/login")
async def login(
    credentials: LoginRequest,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db)
):
    # 1. ユーザー認証
    user = authenticate_user(db, credentials.email, credentials.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )

    # 2. JWT トークン生成
    access_token = create_access_token(user.id, user.email, user.role)
    refresh_token = create_refresh_token(user.id)

    # 3. セッション ID 生成
    session_id = f"sess-{uuid.uuid4().hex[:8]}"

    # 4. セッションデータ作成
    session_data = {
        "user_id": str(user.id),
        "session_id": session_id,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "created_at": datetime.utcnow().isoformat(),
        "expires_at": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "ip_address": request.client.host,
        "user_agent": request.headers.get("user-agent", "")
    }

    # 5. Redis にセッション保存（TTL: 3600秒）
    session_key = f"session:{user.id}:{session_id}"
    redis_client.setex(
        session_key,
        3600,
        json.dumps(session_data)
    )

    # 6. レスポンス返却
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": 3600
    }
```

### セッションの検証

```python
# app/core/security.py

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db)
):
    access_token = credentials.credentials

    # 1. JWT トークンをデコード
    try:
        payload = jwt.decode(
            access_token,
            public_key,
            algorithms=["RS256"],
            audience="fastapi-api"
        )
        user_id = payload.get("sub")
        jti = payload.get("jti")
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )

    # 2. ブラックリストチェック
    if redis_client.exists(f"blacklist:access:{jti}"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked"
        )

    # 3. データベースからユーザー取得
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )

    return user
```

### セッションの削除（ログアウト）

```python
# app/routers/auth.py

@router.post("/logout")
async def logout(
    current_user: User = Depends(get_current_user),
    redis_client: Redis = Depends(get_redis_client)
):
    # 1. アクセストークンと全セッションを取得
    session_pattern = f"session:{current_user.id}:*"
    session_keys = []

    # SCAN コマンドでパターンマッチング
    cursor = 0
    while True:
        cursor, keys = redis_client.scan(cursor, match=session_pattern, count=100)
        session_keys.extend(keys)
        if cursor == 0:
            break

    # 2. すべてのセッションを削除
    if session_keys:
        redis_client.delete(*session_keys)

    # 3. トークンをブラックリストに追加（後述）

    return {"message": "Logged out successfully"}
```

### セッション一覧の取得

```python
# 管理者機能: ユーザーの全セッション取得

@router.get("/admin/sessions/{user_id}")
async def get_user_sessions(
    user_id: str,
    current_user: User = Depends(require_admin),
    redis_client: Redis = Depends(get_redis_client)
):
    session_pattern = f"session:{user_id}:*"
    sessions = []

    # SCAN でセッションキーを検索
    cursor = 0
    while True:
        cursor, keys = redis_client.scan(cursor, match=session_pattern, count=100)

        for key in keys:
            session_data = redis_client.get(key)
            if session_data:
                session = json.loads(session_data)
                # TTL も取得
                session["ttl"] = redis_client.ttl(key)
                sessions.append(session)

        if cursor == 0:
            break

    return {"sessions": sessions, "count": len(sessions)}
```

---

## トークンブラックリスト

### ブラックリストの目的

JWT トークンはステートレスであり、サーバー側で無効化できません。ログアウト時にトークンを無効化するため、Redis ブラックリストを使用します。

### アクセストークンのブラックリスト化

**キーパターン**:
```
blacklist:access:<jti>
```

**実装例**:
```python
# app/routers/auth.py

@router.post("/logout")
async def logout(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    redis_client: Redis = Depends(get_redis_client)
):
    access_token = credentials.credentials

    # 1. JWT をデコード
    payload = jwt.decode(
        access_token,
        public_key,
        algorithms=["RS256"],
        options={"verify_exp": False}  # 期限切れでもデコード
    )

    user_id = payload.get("sub")
    jti = payload.get("jti")
    exp = payload.get("exp")

    # 2. TTL を計算（トークンの残り有効期限）
    current_time = int(datetime.utcnow().timestamp())
    ttl = max(exp - current_time, 0)

    # 3. ブラックリストに追加
    if ttl > 0:
        blacklist_key = f"blacklist:access:{jti}"
        redis_client.setex(blacklist_key, ttl, "true")

    # 4. セッション削除
    session_pattern = f"session:{user_id}:*"
    cursor = 0
    while True:
        cursor, keys = redis_client.scan(cursor, match=session_pattern, count=100)
        if keys:
            redis_client.delete(*keys)
        if cursor == 0:
            break

    return {"message": "Logged out successfully"}
```

### リフレッシュトークンのブラックリスト化

**キーパターン**:
```
blacklist:refresh:<jti>
```

**実装例**:
```python
# app/routers/auth.py

@router.post("/logout")
async def logout(
    request: LogoutRequest,  # access_token と refresh_token を含む
    redis_client: Redis = Depends(get_redis_client)
):
    # アクセストークンのブラックリスト化（前述）

    # リフレッシュトークンのブラックリスト化
    if request.refresh_token:
        refresh_payload = jwt.decode(
            request.refresh_token,
            public_key,
            algorithms=["RS256"],
            options={"verify_exp": False}
        )

        refresh_jti = refresh_payload.get("jti")
        refresh_exp = refresh_payload.get("exp")

        current_time = int(datetime.utcnow().timestamp())
        refresh_ttl = max(refresh_exp - current_time, 0)

        if refresh_ttl > 0:
            blacklist_key = f"blacklist:refresh:{refresh_jti}"
            redis_client.setex(blacklist_key, refresh_ttl, "true")

    return {"message": "Logged out successfully"}
```

### ブラックリストの検証

```python
# app/core/security.py

def verify_token_not_blacklisted(token: str, token_type: str = "access"):
    """
    トークンがブラックリストに含まれていないか検証

    Args:
        token: JWT トークン
        token_type: "access" または "refresh"

    Raises:
        HTTPException: ブラックリストに含まれている場合
    """
    payload = jwt.decode(
        token,
        public_key,
        algorithms=["RS256"],
        options={"verify_exp": False}
    )

    jti = payload.get("jti")
    blacklist_key = f"blacklist:{token_type}:{jti}"

    if redis_client.exists(blacklist_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token has been revoked"
        )

# トークンリフレッシュ時に使用
@router.post("/refresh")
async def refresh_token(
    request: RefreshTokenRequest,
    redis_client: Redis = Depends(get_redis_client)
):
    # 1. リフレッシュトークンのブラックリストチェック
    verify_token_not_blacklisted(request.refresh_token, token_type="refresh")

    # 2. リフレッシュトークンを検証
    payload = jwt.decode(
        request.refresh_token,
        public_key,
        algorithms=["RS256"]
    )

    user_id = payload.get("sub")

    # 3. 新しいアクセストークンを生成
    new_access_token = create_access_token(user_id)

    return {
        "access_token": new_access_token,
        "token_type": "bearer",
        "expires_in": 900
    }
```

---

## ログイン試行回数制限

### 目的

ブルートフォース攻撃を防止するため、IP アドレスごとのログイン試行回数を制限します。

### キーパターン

```
rate:login:<ip_address>:<yyyyMMddHH>
```

**例**:
```
rate:login:192.168.1.100:2025093010
```

### 実装例

```python
# app/routers/auth.py

from datetime import datetime
from fastapi import Request, HTTPException

@router.post("/login")
async def login(
    request: Request,
    credentials: LoginRequest,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db)
):
    # 1. IP アドレス取得
    ip_address = request.client.host

    # 2. レート制限キー生成
    current_hour = datetime.utcnow().strftime("%Y%m%d%H")
    rate_key = f"rate:login:{ip_address}:{current_hour}"

    # 3. 現在の試行回数を取得
    attempts = redis_client.get(rate_key)
    if attempts and int(attempts) >= 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Please try again later."
        )

    # 4. ログイン試行（ユーザー認証）
    user = authenticate_user(db, credentials.email, credentials.password)

    if not user:
        # 失敗した場合: カウントをインクリメント
        count = redis_client.incr(rate_key)
        if count == 1:
            # 初回失敗時に TTL 設定
            redis_client.expire(rate_key, 3600)

        # 残り試行回数を計算
        remaining_attempts = max(5 - count, 0)

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid credentials. {remaining_attempts} attempts remaining."
        )

    # 5. 成功した場合: カウントをリセット
    redis_client.delete(rate_key)

    # 6. セッション作成とトークン返却（前述の処理）
    # ...

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }
```

### より厳格なレート制限

```python
# ユーザーアカウント単位のロック機能

@router.post("/login")
async def login(
    credentials: LoginRequest,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db)
):
    # 1. アカウントロックチェック
    lock_key = f"account:locked:{credentials.email}"
    if redis_client.exists(lock_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is temporarily locked due to multiple failed login attempts."
        )

    # 2. アカウント単位の失敗回数チェック
    attempt_key = f"login:attempts:{credentials.email}"
    attempts = redis_client.get(attempt_key)

    if attempts and int(attempts) >= 5:
        # アカウントをロック（30分）
        redis_client.setex(lock_key, 1800, "true")
        redis_client.delete(attempt_key)

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Too many failed attempts. Account locked for 30 minutes."
        )

    # 3. 認証処理
    user = authenticate_user(db, credentials.email, credentials.password)

    if not user:
        # 失敗カウントをインクリメント
        count = redis_client.incr(attempt_key)
        if count == 1:
            redis_client.expire(attempt_key, 3600)

        remaining = max(5 - count, 0)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid credentials. {remaining} attempts remaining."
        )

    # 4. 成功時: 失敗カウントをリセット
    redis_client.delete(attempt_key)

    # 5. トークン生成とセッション作成
    # ...

    return {"access_token": access_token, "refresh_token": refresh_token}
```

---

## 実装詳細

### Redis クライアントの初期化

```python
# app/db/redis_client.py

import redis
from app.core.config import settings

class RedisClient:
    def __init__(self):
        self.client = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            password=settings.redis_password,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            max_connections=20
        )

    def ping(self) -> bool:
        """Redis 接続確認"""
        try:
            return self.client.ping()
        except redis.ConnectionError:
            return False

# シングルトンインスタンス
redis_client = RedisClient().client

def get_redis_client():
    """FastAPI 依存性注入用"""
    return redis_client
```

### 設定ファイル

```python
# app/core/config.py

from pydantic_settings import BaseSettings
import os

class Settings(BaseSettings):
    # Redis 設定
    redis_host: str = os.getenv("REDIS_HOST", "host.docker.internal")
    redis_port: int = int(os.getenv("REDIS_PORT", "6379"))
    redis_password: str = os.getenv("REDIS_PASSWORD", "")

    # セッション設定
    session_ttl: int = 3600  # 1時間
    access_token_ttl: int = 900  # 15分
    refresh_token_ttl: int = 604800  # 7日

    # レート制限設定
    login_rate_limit: int = 5  # 1時間あたり
    login_rate_window: int = 3600  # 1時間

    class Config:
        env_file = ".env"

settings = Settings()
```

### 環境変数

**.env ファイル**:
```bash
# Redis 接続
REDIS_HOST=host.docker.internal
REDIS_PORT=6379
REDIS_PASSWORD=your-secure-redis-password

# セッション設定
SESSION_TTL=3600
ACCESS_TOKEN_TTL=900
REFRESH_TOKEN_TTL=604800

# レート制限
LOGIN_RATE_LIMIT=5
LOGIN_RATE_WINDOW=3600
```

---

## エラーハンドリング

### Redis 接続エラー

```python
# app/core/exceptions.py

from fastapi import HTTPException, status

def handle_redis_error(func):
    """Redis エラーをハンドリングするデコレータ"""
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except redis.ConnectionError:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Cache service unavailable"
            )
        except redis.TimeoutError:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail="Cache service timeout"
            )
        except redis.RedisError as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Cache service error: {str(e)}"
            )
    return wrapper

# 使用例
@router.post("/login")
@handle_redis_error
async def login(
    credentials: LoginRequest,
    redis_client: Redis = Depends(get_redis_client)
):
    # Redis 操作
    ...
```

### フォールバック処理

```python
# Redis 障害時のフォールバック

async def get_current_user_safe(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db)
):
    access_token = credentials.credentials

    # JWT トークン検証
    payload = jwt.decode(access_token, public_key, algorithms=["RS256"])
    user_id = payload.get("sub")
    jti = payload.get("jti")

    # ブラックリストチェック（Redis が利用可能な場合のみ）
    try:
        if redis_client.ping():
            if redis_client.exists(f"blacklist:access:{jti}"):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Token has been revoked"
                )
    except redis.RedisError:
        # Redis エラー時はブラックリストチェックをスキップ
        # ログに記録
        logger.warning(f"Redis unavailable, skipping blacklist check for JTI: {jti}")

    # ユーザー取得
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )

    return user
```

---

## パフォーマンス最適化

### コネクションプーリング

```python
# app/db/redis_client.py

import redis

# コネクションプール作成
pool = redis.ConnectionPool(
    host=settings.redis_host,
    port=settings.redis_port,
    password=settings.redis_password,
    decode_responses=True,
    max_connections=20,
    socket_connect_timeout=5,
    socket_timeout=5
)

# プールからクライアント作成
redis_client = redis.Redis(connection_pool=pool)
```

### バッチ操作

```python
# 複数セッションの一括削除

def delete_user_sessions_batch(user_id: str, redis_client: Redis):
    """ユーザーの全セッションを効率的に削除"""

    pipeline = redis_client.pipeline()
    session_pattern = f"session:{user_id}:*"

    cursor = 0
    while True:
        cursor, keys = redis_client.scan(cursor, match=session_pattern, count=100)

        if keys:
            # パイプラインに削除コマンドを追加
            for key in keys:
                pipeline.delete(key)

        if cursor == 0:
            break

    # 一括実行
    pipeline.execute()
```

---

## 監視とデバッグ

### セッション数の監視

```bash
# アクティブセッション数
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "session:*" | wc -l

# ブラックリストサイズ
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "blacklist:*" | wc -l
```

### デバッグコマンド

```python
# 開発環境用: Redis の内容確認

@router.get("/debug/redis/sessions")
async def debug_redis_sessions(
    redis_client: Redis = Depends(get_redis_client),
    current_user: User = Depends(require_admin)
):
    """すべてのセッションを取得（開発用）"""

    sessions = []
    cursor = 0

    while True:
        cursor, keys = redis_client.scan(cursor, match="session:*", count=100)

        for key in keys:
            data = redis_client.get(key)
            ttl = redis_client.ttl(key)
            if data:
                sessions.append({
                    "key": key,
                    "ttl": ttl,
                    "data": json.loads(data)
                })

        if cursor == 0:
            break

    return {"sessions": sessions, "count": len(sessions)}
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [データ構造概要](./02-data-structure-overview.md)
- [セッション管理詳細](./07-session-management.md)
- [Auth Service 概要](/01-auth-service/01-overview.md)

---

**次のステップ**: [User API の Redis 使用法](./04-user-api-usage.md) を参照して、User API サービスにおける Redis の活用方法を確認してください。