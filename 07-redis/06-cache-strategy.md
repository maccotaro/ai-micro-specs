# Redis キャッシュ戦略

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [キャッシュ戦略の概要](#キャッシュ戦略の概要)
- [Cache-Aside パターン](#cache-aside-パターン)
- [Write-Through パターン](#write-through-パターン)
- [Write-Behind パターン](#write-behind-パターン)
- [TTL ポリシー](#ttl-ポリシー)
- [キャッシュ無効化戦略](#キャッシュ無効化戦略)
- [キャッシュウォーミング](#キャッシュウォーミング)
- [ベストプラクティス](#ベストプラクティス)

---

## キャッシュ戦略の概要

### キャッシュの目的

Redis キャッシュは以下の目的で使用されます：

1. **パフォーマンス向上**
   - データベースアクセスの削減
   - API レスポンス時間の短縮
   - システム全体のスループット向上

2. **データベース負荷の軽減**
   - 読み取りクエリの削減
   - データベースのスケーラビリティ向上
   - コスト削減

3. **ユーザーエクスペリエンスの改善**
   - 高速なレスポンス
   - 安定したパフォーマンス
   - スムーズなユーザー体験

### ai-micro-service でのキャッシュ対象

| データ種別 | キャッシュの適性 | 理由 | 現在の使用 |
|----------|--------------|------|----------|
| ユーザープロファイル | ✅ 高 | 頻繁に読まれ、更新は少ない | ✅ 実装済み |
| セッション情報 | ✅ 高 | 高速アクセスが必要 | ✅ 実装済み |
| ドキュメントメタデータ | ✅ 中 | 読み取り頻度が高い | ⚠️ 将来的に実装 |
| OCR 結果 | ✅ 中 | 再計算コストが高い | ⚠️ 将来的に実装 |
| ナレッジベース一覧 | ✅ 中 | 更新頻度が低い | ⚠️ 将来的に実装 |
| RAG 埋め込みベクトル | ❌ 低 | サイズが大きく、専用DB推奨 | ❌ PostgreSQL使用 |

---

## Cache-Aside パターン

### 概要

**Cache-Aside**（別名: Lazy Loading）は、最も一般的なキャッシュパターンです。アプリケーションがキャッシュとデータベースの両方を管理します。

### フロー

```
1. アプリケーション → キャッシュをチェック
2. キャッシュヒット → キャッシュから返却
3. キャッシュミス → データベースから取得
4. データベース → データ返却
5. アプリケーション → キャッシュに保存（TTL付き）
6. アプリケーション → クライアントに返却
```

### 実装例

```python
# app/services/profile_service.py

from typing import Optional
import json

class ProfileService:
    def __init__(self, redis_client: Redis, db: Session):
        self.redis = redis_client
        self.db = db

    def get_profile(self, user_id: str) -> Optional[dict]:
        """
        Cache-Aside パターンでプロファイル取得
        """

        # 1. キャッシュをチェック
        cache_key = f"cache:profile:{user_id}"
        cached_data = self.redis.get(cache_key)

        if cached_data:
            # キャッシュヒット
            logger.info(f"Cache hit for user: {user_id}")
            return json.loads(cached_data)

        # 2. キャッシュミス: データベースから取得
        logger.info(f"Cache miss for user: {user_id}")

        profile = self.db.query(Profile).filter(
            Profile.user_id == user_id
        ).first()

        if not profile:
            return None

        # 3. データを辞書に変換
        profile_data = {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "phone": profile.phone,
            "cached_at": datetime.utcnow().isoformat()
        }

        # 4. キャッシュに保存（TTL: 300秒）
        try:
            self.redis.setex(
                cache_key,
                300,
                json.dumps(profile_data, ensure_ascii=False)
            )
            logger.info(f"Profile cached for user: {user_id}")
        except redis.RedisError as e:
            logger.warning(f"Failed to cache profile: {e}")

        return profile_data
```

### メリット

- **シンプル**: 実装が簡単
- **柔軟性**: キャッシュ戦略を細かく制御可能
- **障害耐性**: Redis 障害時もデータベースにフォールバック可能

### デメリット

- **初回アクセスが遅い**: キャッシュミス時はデータベースアクセスが必要
- **キャッシュウォーミングが必要**: アプリケーション起動時にキャッシュが空

### 適用場面

- ✅ ユーザープロファイル
- ✅ 設定情報
- ✅ 参照データ

---

## Write-Through パターン

### 概要

**Write-Through** は、データを書き込む際に、データベースとキャッシュの両方を同期的に更新するパターンです。

### フロー

```
1. アプリケーション → データ更新リクエスト
2. データベースを更新
3. キャッシュを更新（または削除）
4. クライアントに成功を返却
```

### 実装例: キャッシュ更新

```python
# app/services/profile_service.py

class ProfileService:
    def update_profile(self, user_id: str, update_data: dict) -> dict:
        """
        Write-Through パターンでプロファイル更新
        """

        # 1. データベースを更新
        profile = self.db.query(Profile).filter(
            Profile.user_id == user_id
        ).first()

        if not profile:
            raise ValueError(f"Profile not found: {user_id}")

        # 更新
        for key, value in update_data.items():
            setattr(profile, key, value)

        profile.updated_at = datetime.utcnow()

        try:
            self.db.commit()
            self.db.refresh(profile)
        except Exception as e:
            self.db.rollback()
            raise

        # 2. キャッシュを更新
        cache_key = f"cache:profile:{user_id}"

        profile_data = {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "phone": profile.phone,
            "cached_at": datetime.utcnow().isoformat()
        }

        try:
            # キャッシュを即座に更新
            self.redis.setex(
                cache_key,
                300,
                json.dumps(profile_data, ensure_ascii=False)
            )
            logger.info(f"Cache updated for user: {user_id}")
        except redis.RedisError as e:
            logger.warning(f"Failed to update cache: {e}")

        return profile_data
```

### 実装例: キャッシュ削除（推奨）

```python
class ProfileService:
    def update_profile_invalidate(self, user_id: str, update_data: dict) -> dict:
        """
        Write-Through パターン（キャッシュ削除版）
        """

        # 1. データベースを更新
        profile = self.db.query(Profile).filter(
            Profile.user_id == user_id
        ).first()

        if not profile:
            raise ValueError(f"Profile not found: {user_id}")

        for key, value in update_data.items():
            setattr(profile, key, value)

        profile.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(profile)

        # 2. キャッシュを削除（次回アクセス時に再キャッシュ）
        cache_key = f"cache:profile:{user_id}"

        try:
            self.redis.delete(cache_key)
            logger.info(f"Cache invalidated for user: {user_id}")
        except redis.RedisError as e:
            logger.warning(f"Failed to invalidate cache: {e}")

        # 3. 更新後のデータを返却
        return {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "phone": profile.phone,
            "updated_at": profile.updated_at.isoformat()
        }
```

### メリット

- **データ整合性**: キャッシュとデータベースが常に同期
- **読み取りパフォーマンス**: 更新後もキャッシュから高速読み取り

### デメリット

- **書き込みレイテンシ**: キャッシュ更新分だけ書き込みが遅くなる
- **複雑性**: エラーハンドリングが複雑

### 適用場面

- ✅ ユーザープロファイル更新
- ✅ 設定変更
- ⚠️ 高頻度更新データには不向き

---

## Write-Behind パターン

### 概要

**Write-Behind**（別名: Write-Back）は、キャッシュを先に更新し、データベース更新を非同期で行うパターンです。

### フロー

```
1. アプリケーション → キャッシュを更新
2. クライアントに即座に成功を返却
3. バックグラウンドでデータベースを更新
```

### 実装例

```python
# app/services/profile_service.py

from fastapi import BackgroundTasks

class ProfileService:
    def update_profile_async(
        self,
        user_id: str,
        update_data: dict,
        background_tasks: BackgroundTasks
    ) -> dict:
        """
        Write-Behind パターンでプロファイル更新
        """

        # 1. キャッシュを即座に更新
        cache_key = f"cache:profile:{user_id}"

        # 既存データ取得（または新規作成）
        cached_data = self.redis.get(cache_key)

        if cached_data:
            profile_data = json.loads(cached_data)
        else:
            profile_data = {"user_id": user_id}

        # データを更新
        profile_data.update(update_data)
        profile_data["cached_at"] = datetime.utcnow().isoformat()

        # キャッシュに保存
        self.redis.setex(
            cache_key,
            300,
            json.dumps(profile_data, ensure_ascii=False)
        )

        # 2. データベース更新をバックグラウンドタスクに追加
        background_tasks.add_task(
            self._update_database,
            user_id,
            update_data
        )

        # 3. 即座に返却
        return profile_data

    def _update_database(self, user_id: str, update_data: dict):
        """
        データベース更新（バックグラウンド実行）
        """

        try:
            profile = self.db.query(Profile).filter(
                Profile.user_id == user_id
            ).first()

            if profile:
                for key, value in update_data.items():
                    setattr(profile, key, value)

                profile.updated_at = datetime.utcnow()
                self.db.commit()

                logger.info(f"Database updated for user: {user_id}")
            else:
                logger.warning(f"Profile not found in database: {user_id}")

        except Exception as e:
            logger.error(f"Failed to update database: {e}")
            # エラー時の処理（リトライ、アラートなど）
```

### メリット

- **高速な書き込み**: キャッシュ更新のみで即座に返却
- **書き込みバッチ化**: 複数の更新をまとめて実行可能

### デメリット

- **データ損失リスク**: Redis 障害時にデータが失われる可能性
- **整合性の遅延**: キャッシュとデータベースに一時的な不整合
- **実装の複雑さ**: エラーハンドリングとリトライロジックが必要

### 適用場面

- ⚠️ セッション情報（短命データ）
- ⚠️ 一時的な状態管理
- ❌ 重要なビジネスデータには不向き

---

## TTL ポリシー

### TTL の設計原則

TTL（Time To Live）は、データの性質に応じて適切に設定する必要があります。

### TTL 設定ガイドライン

| データ種別 | 推奨TTL | 理由 |
|----------|--------|------|
| ユーザープロファイル | 300秒（5分） | 更新頻度が低く、5分の遅延は許容可能 |
| セッション | 3600秒（1時間） | JWT アクセストークンの有効期限に合わせる |
| トークンブラックリスト | トークン有効期限 | トークン期限切れ後は不要 |
| レート制限 | 3600秒（1時間） | 時間ウィンドウに合わせる |
| ドキュメントメタデータ | 600秒（10分） | 中程度の更新頻度 |
| 設定情報 | 1800秒（30分） | 更新が少ない |

### 動的TTLの実装

```python
# app/services/cache_service.py

class CacheService:
    def get_ttl_for_data_type(self, data_type: str) -> int:
        """
        データ種別に応じた TTL を返す
        """

        ttl_config = {
            "profile": 300,        # 5分
            "session": 3600,       # 1時間
            "blacklist": None,     # 動的に計算
            "rate_limit": 3600,    # 1時間
            "document_meta": 600,  # 10分
            "settings": 1800       # 30分
        }

        return ttl_config.get(data_type, 300)  # デフォルト5分

    def cache_with_dynamic_ttl(
        self,
        key: str,
        value: str,
        data_type: str
    ):
        """
        データ種別に応じた TTL でキャッシュ
        """

        ttl = self.get_ttl_for_data_type(data_type)

        if ttl:
            self.redis.setex(key, ttl, value)
        else:
            self.redis.set(key, value)
```

### アクセス頻度に基づく TTL

```python
# 頻繁にアクセスされるデータは TTL を延長

def get_profile_with_adaptive_ttl(self, user_id: str) -> dict:
    """
    アクセス頻度に基づいて TTL を動的調整
    """

    cache_key = f"cache:profile:{user_id}"
    access_count_key = f"access:count:profile:{user_id}"

    # アクセス回数をカウント
    access_count = self.redis.incr(access_count_key)

    # 初回アクセス時に TTL 設定
    if access_count == 1:
        self.redis.expire(access_count_key, 3600)

    # キャッシュ取得
    cached_data = self.redis.get(cache_key)

    if cached_data:
        # アクセス頻度に応じて TTL を調整
        if access_count > 10:
            # 頻繁にアクセスされる: TTL を延長（10分）
            self.redis.expire(cache_key, 600)
        else:
            # 通常: デフォルト TTL（5分）
            self.redis.expire(cache_key, 300)

        return json.loads(cached_data)

    # キャッシュミス時の処理
    # ...
```

---

## キャッシュ無効化戦略

### 無効化のタイミング

1. **即座に無効化**: データ更新時にキャッシュ削除
2. **TTL ベース**: TTL 期限切れを待つ
3. **手動無効化**: 管理者が明示的に削除

### 実装パターン

#### 1. 単一キャッシュの無効化

```python
def invalidate_profile_cache(self, user_id: str):
    """プロファイルキャッシュを無効化"""

    cache_key = f"cache:profile:{user_id}"
    self.redis.delete(cache_key)
```

#### 2. パターンマッチによる一括無効化

```python
def invalidate_user_caches(self, user_id: str):
    """ユーザー関連のすべてのキャッシュを無効化"""

    patterns = [
        f"cache:profile:{user_id}",
        f"cache:settings:{user_id}",
        f"cache:preferences:{user_id}"
    ]

    pipeline = self.redis.pipeline()

    for key in patterns:
        pipeline.delete(key)

    pipeline.execute()
```

#### 3. SCAN を使った安全な一括削除

```python
def invalidate_all_profile_caches(self):
    """すべてのプロファイルキャッシュを無効化（管理者機能）"""

    cursor = 0
    deleted_count = 0

    while True:
        cursor, keys = self.redis.scan(
            cursor,
            match="cache:profile:*",
            count=100
        )

        if keys:
            self.redis.delete(*keys)
            deleted_count += len(keys)

        if cursor == 0:
            break

    logger.info(f"Invalidated {deleted_count} profile caches")
    return deleted_count
```

---

## キャッシュウォーミング

### 目的

アプリケーション起動時に頻繁にアクセスされるデータをキャッシュに事前ロードします。

### 実装例

```python
# app/services/cache_warming.py

async def warm_profile_cache(
    redis_client: Redis,
    db: Session,
    limit: int = 1000
):
    """
    アクティブユーザーのプロファイルをキャッシュウォーミング
    """

    logger.info("Starting cache warming...")

    # 最近ログインしたユーザーを取得
    recent_users = db.query(Profile).filter(
        Profile.last_login > datetime.utcnow() - timedelta(days=7)
    ).limit(limit).all()

    pipeline = redis_client.pipeline()
    cached_count = 0

    for profile in recent_users:
        profile_data = {
            "user_id": str(profile.user_id),
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "cached_at": datetime.utcnow().isoformat()
        }

        cache_key = f"cache:profile:{profile.user_id}"
        pipeline.setex(
            cache_key,
            300,
            json.dumps(profile_data, ensure_ascii=False)
        )
        cached_count += 1

    # 一括実行
    pipeline.execute()

    logger.info(f"Cache warming completed: {cached_count} profiles cached")
    return cached_count

# アプリケーション起動時に実行
@app.on_event("startup")
async def startup_cache_warming():
    await warm_profile_cache(redis_client, db)
```

---

## ベストプラクティス

### 1. キャッシュキーの命名規則

```python
# 良い例
cache:profile:<user_id>
cache:document:<document_id>:metadata
cache:settings:<user_id>:preferences

# 悪い例
profile_<user_id>  # カテゴリが不明確
cache_<random>     # 構造化されていない
```

### 2. TTL は常に設定する

```python
# 良い例
redis_client.setex(key, 300, value)

# 悪い例（TTL なし、メモリリークの原因）
redis_client.set(key, value)
```

### 3. Redis エラーのハンドリング

```python
try:
    cached_data = redis_client.get(key)
except redis.RedisError as e:
    logger.warning(f"Redis error: {e}")
    # データベースにフォールバック
    cached_data = None
```

### 4. キャッシュヒット率の監視

```python
# メトリクス収集
def track_cache_metrics(cache_hit: bool):
    if cache_hit:
        redis_client.incr("metrics:cache:hits")
    else:
        redis_client.incr("metrics:cache:misses")
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [データ構造概要](./02-data-structure-overview.md)
- [User API の Redis 使用法](./04-user-api-usage.md)
- [パフォーマンスチューニング](./09-performance-tuning.md)

---

**次のステップ**: [セッション管理詳細](./07-session-management.md) を参照して、セッション管理の実装パターンを確認してください。