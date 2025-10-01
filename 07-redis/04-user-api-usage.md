# User API の Redis 使用法

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [プロファイルキャッシュ](#プロファイルキャッシュ)
- [APIレート制限](#apiレート制限)
- [実装詳細](#実装詳細)
- [キャッシュ無効化戦略](#キャッシュ無効化戦略)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## 概要

### User API Service における Redis の役割

User API Service (`ai-micro-api-user`) は、ユーザープロファイル情報の管理を担当するマイクロサービスです。Redis は以下の2つの主要機能で利用されます：

1. **プロファイルキャッシュ**: データベースアクセスを削減し、レスポンス時間を短縮
2. **APIレート制限**: 過剰なリクエストを防止し、システムを保護

### 接続情報

**サービス**: ai-micro-api-user (Port 8001)
**Redis URL**: `redis://:<password>@host.docker.internal:6379`
**クライアント**: redis-py
**主要データ**: プロファイルキャッシュ、レート制限カウンタ

---

## プロファイルキャッシュ

### キャッシュの目的

ユーザープロファイル情報は頻繁にアクセスされますが、更新頻度は低いため、Redis キャッシュによるパフォーマンス向上が効果的です。

**効果**:
- データベースアクセスの削減（約70-80%）
- API レスポンス時間の短縮（約50-60%削減）
- データベース負荷の軽減

### キーパターン

```
cache:profile:<user_id>
```

**例**:
```
cache:profile:550e8400-e29b-41d4-a716-446655440000
```

### データ構造

**データ型**: String (JSON)

**JSON スキーマ**:
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "first_name": "太郎",
  "last_name": "山田",
  "email": "taro@example.com",
  "phone": "090-1234-5678",
  "address": "東京都渋谷区...",
  "date_of_birth": "1990-01-01",
  "created_at": "2025-09-01T10:00:00Z",
  "updated_at": "2025-09-30T10:00:00Z",
  "cached_at": "2025-09-30T10:05:00Z"
}
```

**TTL**: 300秒（5分）

### Cache-Aside パターンの実装

```python
# app/routers/profiles.py

from fastapi import APIRouter, Depends, HTTPException, status
from datetime import datetime
import json

router = APIRouter()

@router.get("/profiles/{user_id}")
async def get_profile(
    user_id: str,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    ユーザープロファイル取得（Cache-Aside パターン）

    フロー:
    1. Redis キャッシュをチェック
    2. キャッシュヒット → キャッシュから返却
    3. キャッシュミス → データベースから取得 → キャッシュに保存 → 返却
    """

    # 1. キャッシュキー生成
    cache_key = f"cache:profile:{user_id}"

    # 2. キャッシュチェック
    try:
        cached_data = redis_client.get(cache_key)
        if cached_data:
            # キャッシュヒット
            profile_data = json.loads(cached_data)
            return {
                "profile": profile_data,
                "cached": True,
                "cached_at": profile_data.get("cached_at")
            }
    except redis.RedisError as e:
        # Redis エラー時はログに記録してデータベースにフォールバック
        logger.warning(f"Redis error in get_profile: {e}")

    # 3. キャッシュミス: データベースから取得
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # 4. プロファイルデータを辞書に変換
    profile_data = {
        "user_id": str(profile.user_id),
        "first_name": profile.first_name,
        "last_name": profile.last_name,
        "email": profile.email,
        "phone": profile.phone,
        "address": profile.address,
        "date_of_birth": profile.date_of_birth.isoformat() if profile.date_of_birth else None,
        "created_at": profile.created_at.isoformat(),
        "updated_at": profile.updated_at.isoformat(),
        "cached_at": datetime.utcnow().isoformat()
    }

    # 5. Redis にキャッシュ（TTL: 300秒）
    try:
        redis_client.setex(
            cache_key,
            300,  # 5分
            json.dumps(profile_data, ensure_ascii=False)
        )
    except redis.RedisError as e:
        # キャッシュ保存失敗はログのみ（処理は継続）
        logger.warning(f"Failed to cache profile: {e}")

    return {
        "profile": profile_data,
        "cached": False
    }
```

### プロファイル更新時のキャッシュ無効化

```python
# app/routers/profiles.py

@router.put("/profiles/{user_id}")
async def update_profile(
    user_id: str,
    profile_update: ProfileUpdateRequest,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    プロファイル更新（Write-Through パターン）

    フロー:
    1. データベースを更新
    2. キャッシュを削除（次回アクセス時に再キャッシュ）
    """

    # 1. 権限チェック
    if str(current_user.id) != user_id and current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to update this profile"
        )

    # 2. データベースから既存プロファイルを取得
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # 3. データベース更新
    update_data = profile_update.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(profile, key, value)

    profile.updated_at = datetime.utcnow()

    try:
        db.commit()
        db.refresh(profile)
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )

    # 4. キャッシュ無効化
    cache_key = f"cache:profile:{user_id}"
    try:
        redis_client.delete(cache_key)
        logger.info(f"Cache invalidated for user: {user_id}")
    except redis.RedisError as e:
        # キャッシュ削除失敗はログのみ（処理は継続）
        logger.warning(f"Failed to invalidate cache: {e}")

    return {
        "message": "Profile updated successfully",
        "profile": {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "phone": profile.phone,
            "updated_at": profile.updated_at.isoformat()
        }
    }
```

### バッチキャッシュ取得

```python
# 複数ユーザーのプロファイルを効率的に取得

@router.post("/profiles/batch")
async def get_profiles_batch(
    user_ids: List[str],
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    """
    複数プロファイルの一括取得（キャッシュ活用）
    """

    profiles = []
    cache_misses = []

    # 1. Redis から一括取得（MGET）
    cache_keys = [f"cache:profile:{uid}" for uid in user_ids]

    try:
        cached_values = redis_client.mget(cache_keys)

        for i, cached_value in enumerate(cached_values):
            if cached_value:
                # キャッシュヒット
                profiles.append(json.loads(cached_value))
            else:
                # キャッシュミス
                cache_misses.append(user_ids[i])

    except redis.RedisError as e:
        logger.warning(f"Redis batch get error: {e}")
        cache_misses = user_ids  # すべてデータベースから取得

    # 2. キャッシュミスの分をデータベースから取得
    if cache_misses:
        db_profiles = db.query(Profile).filter(
            Profile.user_id.in_(cache_misses)
        ).all()

        # パイプラインでキャッシュに一括保存
        pipeline = redis_client.pipeline()

        for profile in db_profiles:
            profile_data = {
                "user_id": str(profile.user_id),
                "first_name": profile.first_name,
                "last_name": profile.last_name,
                "email": profile.email,
                "phone": profile.phone,
                "cached_at": datetime.utcnow().isoformat()
            }

            profiles.append(profile_data)

            # キャッシュに追加
            cache_key = f"cache:profile:{profile.user_id}"
            pipeline.setex(cache_key, 300, json.dumps(profile_data, ensure_ascii=False))

        # 一括実行
        try:
            pipeline.execute()
        except redis.RedisError as e:
            logger.warning(f"Failed to cache batch profiles: {e}")

    return {
        "profiles": profiles,
        "count": len(profiles),
        "cache_hits": len(user_ids) - len(cache_misses),
        "cache_misses": len(cache_misses)
    }
```

---

## APIレート制限

### レート制限の目的

User API への過剰なリクエストを防止し、システムの安定性を保ちます。

**制限対象**:
- プロファイル取得: 100回/時間
- プロファイル更新: 10回/時間
- バッチ取得: 20回/時間

### キーパターン

```
rate:<user_id>:<endpoint>:<yyyyMMddHH>
```

**例**:
```
rate:550e8400-e29b-41d4-a716-446655440000:/api/profiles:2025093010
```

### レート制限の実装

```python
# app/middleware/rate_limit.py

from fastapi import Request, HTTPException, status
from datetime import datetime
import redis

class RateLimiter:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client

    async def check_rate_limit(
        self,
        user_id: str,
        endpoint: str,
        limit: int = 100,
        window: int = 3600
    ) -> dict:
        """
        レート制限チェック

        Args:
            user_id: ユーザーID
            endpoint: エンドポイントパス
            limit: 制限回数
            window: 時間ウィンドウ（秒）

        Returns:
            dict: レート制限情報

        Raises:
            HTTPException: 制限超過時
        """

        # 現在時刻（時間単位）
        current_hour = datetime.utcnow().strftime("%Y%m%d%H")

        # キー生成
        rate_key = f"rate:{user_id}:{endpoint}:{current_hour}"

        try:
            # カウントをインクリメント
            count = self.redis.incr(rate_key)

            # 初回アクセス時に TTL を設定
            if count == 1:
                self.redis.expire(rate_key, window)

            # 残り回数を計算
            remaining = max(limit - count, 0)

            # 制限超過チェック
            if count > limit:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Rate limit exceeded. Try again in {window} seconds.",
                    headers={
                        "X-RateLimit-Limit": str(limit),
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": str(window)
                    }
                )

            return {
                "limit": limit,
                "remaining": remaining,
                "reset": window
            }

        except redis.RedisError as e:
            # Redis エラー時はレート制限をスキップ（ログに記録）
            logger.warning(f"Rate limit check failed: {e}")
            return {
                "limit": limit,
                "remaining": limit,
                "reset": window
            }

# 依存性注入
def get_rate_limiter(redis_client: Redis = Depends(get_redis_client)):
    return RateLimiter(redis_client)
```

### エンドポイントでの使用

```python
# app/routers/profiles.py

@router.get("/profiles/{user_id}")
async def get_profile(
    user_id: str,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    rate_limiter: RateLimiter = Depends(get_rate_limiter)
):
    # レート制限チェック（100回/時間）
    rate_info = await rate_limiter.check_rate_limit(
        user_id=str(current_user.id),
        endpoint="/api/profiles",
        limit=100
    )

    # プロファイル取得処理（前述の実装）
    # ...

    # レスポンスヘッダーにレート制限情報を追加
    return Response(
        content=json.dumps({"profile": profile_data}),
        media_type="application/json",
        headers={
            "X-RateLimit-Limit": str(rate_info["limit"]),
            "X-RateLimit-Remaining": str(rate_info["remaining"]),
            "X-RateLimit-Reset": str(rate_info["reset"])
        }
    )

@router.put("/profiles/{user_id}")
async def update_profile(
    user_id: str,
    profile_update: ProfileUpdateRequest,
    redis_client: Redis = Depends(get_redis_client),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    rate_limiter: RateLimiter = Depends(get_rate_limiter)
):
    # 更新エンドポイントは厳格なレート制限（10回/時間）
    await rate_limiter.check_rate_limit(
        user_id=str(current_user.id),
        endpoint="/api/profiles/update",
        limit=10
    )

    # プロファイル更新処理
    # ...
```

### グローバルレート制限ミドルウェア

```python
# app/middleware/global_rate_limit.py

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class GlobalRateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, redis_client: redis.Redis):
        super().__init__(app)
        self.redis = redis_client
        self.limiter = RateLimiter(redis_client)

    async def dispatch(self, request: Request, call_next):
        # 認証情報取得
        auth_header = request.headers.get("authorization")

        if auth_header:
            try:
                # JWT からユーザーID取得
                token = auth_header.split(" ")[1]
                payload = jwt.decode(token, public_key, algorithms=["RS256"])
                user_id = payload.get("sub")

                # レート制限チェック
                endpoint = request.url.path
                await self.limiter.check_rate_limit(
                    user_id=user_id,
                    endpoint=endpoint,
                    limit=100  # デフォルト制限
                )

            except Exception as e:
                logger.warning(f"Rate limit middleware error: {e}")

        response = await call_next(request)
        return response

# アプリケーションに追加
app.add_middleware(GlobalRateLimitMiddleware, redis_client=redis_client)
```

---

## 実装詳細

### Redis クライアントの初期化

```python
# app/db/redis_client.py

import redis
from app.core.config import settings
from typing import Optional

class RedisClient:
    def __init__(self):
        self.pool = redis.ConnectionPool(
            host=settings.redis_host,
            port=settings.redis_port,
            password=settings.redis_password,
            decode_responses=True,
            max_connections=20,
            socket_connect_timeout=5,
            socket_timeout=5
        )
        self.client = redis.Redis(connection_pool=self.pool)

    def ping(self) -> bool:
        """Redis 接続確認"""
        try:
            return self.client.ping()
        except redis.RedisError:
            return False

    def get_profile_cache(self, user_id: str) -> Optional[dict]:
        """プロファイルキャッシュ取得"""
        import json
        key = f"cache:profile:{user_id}"
        try:
            data = self.client.get(key)
            return json.loads(data) if data else None
        except redis.RedisError:
            return None

    def set_profile_cache(self, user_id: str, profile_data: dict, ttl: int = 300):
        """プロファイルキャッシュ設定"""
        import json
        key = f"cache:profile:{user_id}"
        try:
            self.client.setex(key, ttl, json.dumps(profile_data, ensure_ascii=False))
        except redis.RedisError as e:
            logger.warning(f"Failed to set profile cache: {e}")

    def delete_profile_cache(self, user_id: str):
        """プロファイルキャッシュ削除"""
        key = f"cache:profile:{user_id}"
        try:
            self.client.delete(key)
        except redis.RedisError as e:
            logger.warning(f"Failed to delete profile cache: {e}")

# シングルトンインスタンス
redis_client = RedisClient()

def get_redis_client():
    return redis_client.client
```

---

## キャッシュ無効化戦略

### 戦略の種類

1. **TTL ベース無効化**（デフォルト）
   - 5分後に自動削除
   - 最もシンプル

2. **更新時無効化**（Write-Through）
   - プロファイル更新時にキャッシュ削除
   - データ整合性が重要な場合

3. **バックグラウンド更新**（Refresh-Ahead）
   - TTL 前にバックグラウンドで更新
   - 高頻度アクセスの場合

### 複数キャッシュの無効化

```python
# 関連するすべてのキャッシュを削除

def invalidate_all_user_caches(user_id: str, redis_client: Redis):
    """
    ユーザー関連のすべてのキャッシュを無効化
    """

    patterns = [
        f"cache:profile:{user_id}",
        f"cache:settings:{user_id}",
        f"cache:preferences:{user_id}"
    ]

    pipeline = redis_client.pipeline()

    for pattern in patterns:
        pipeline.delete(pattern)

    try:
        pipeline.execute()
        logger.info(f"All caches invalidated for user: {user_id}")
    except redis.RedisError as e:
        logger.warning(f"Failed to invalidate caches: {e}")
```

---

## パフォーマンス最適化

### キャッシュヒット率の監視

```python
# キャッシュヒット率を記録

class CacheMetrics:
    def __init__(self, redis_client: Redis):
        self.redis = redis_client

    def record_hit(self):
        """キャッシュヒットを記録"""
        self.redis.incr("metrics:cache:hits")

    def record_miss(self):
        """キャッシュミスを記録"""
        self.redis.incr("metrics:cache:misses")

    def get_hit_rate(self) -> dict:
        """ヒット率を取得"""
        hits = int(self.redis.get("metrics:cache:hits") or 0)
        misses = int(self.redis.get("metrics:cache:misses") or 0)
        total = hits + misses

        hit_rate = (hits / total * 100) if total > 0 else 0

        return {
            "hits": hits,
            "misses": misses,
            "total": total,
            "hit_rate": round(hit_rate, 2)
        }

    def reset_metrics(self):
        """メトリクスをリセット"""
        self.redis.delete("metrics:cache:hits", "metrics:cache:misses")
```

### プリウォーミング

```python
# アプリケーション起動時にキャッシュをプリウォーム

async def prewarm_cache(redis_client: Redis, db: Session):
    """
    頻繁にアクセスされるプロファイルをキャッシュ
    """

    # アクティブユーザーのプロファイルを取得
    active_users = db.query(Profile).filter(
        Profile.last_login > datetime.utcnow() - timedelta(days=7)
    ).limit(1000).all()

    pipeline = redis_client.pipeline()

    for profile in active_users:
        profile_data = {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "cached_at": datetime.utcnow().isoformat()
        }

        cache_key = f"cache:profile:{profile.user_id}"
        pipeline.setex(cache_key, 300, json.dumps(profile_data, ensure_ascii=False))

    try:
        pipeline.execute()
        logger.info(f"Cache prewarmed with {len(active_users)} profiles")
    except redis.RedisError as e:
        logger.warning(f"Cache prewarm failed: {e}")
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [データ構造概要](./02-data-structure-overview.md)
- [キャッシュ戦略](./06-cache-strategy.md)
- [User API Service 概要](/02-user-api/01-overview.md)

---

**次のステップ**: [Admin API の Redis 使用法](./05-admin-api-usage.md) を参照して、Admin API サービスにおける Redis の活用方法を確認してください。