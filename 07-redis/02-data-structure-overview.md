# Redis データ構造 - 概要

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [データ構造の概要](#データ構造の概要)
- [キー命名規則](#キー命名規則)
- [セッションデータ](#セッションデータ)
- [ブラックリストデータ](#ブラックリストデータ)
- [キャッシュデータ](#キャッシュデータ)
- [レート制限データ](#レート制限データ)
- [TTL 管理](#ttl-管理)
- [データ型の選択](#データ型の選択)

---

## データ構造の概要

### 全体像

ai-micro-service システムの Redis インスタンスは、以下の4つの主要なデータカテゴリを管理します：

```
ai-micro-redis
├── セッション管理
│   └── session:<user_id>:<sid>           (JSON, TTL: セッションライフタイム)
├── トークンブラックリスト
│   ├── blacklist:access:<jti>            (String, TTL: トークン有効期限)
│   └── blacklist:refresh:<jti>           (String, TTL: トークン有効期限)
├── キャッシュ
│   └── cache:profile:<user_id>           (JSON, TTL: 300秒)
└── レート制限
    └── rate:<user_id>:<endpoint>:<time>  (Counter, TTL: 3600秒)
```

### データ統計（典型的な本番環境）

| カテゴリ | 推定キー数 | メモリ使用量 | 平均 TTL |
|---------|-----------|------------|---------|
| セッション | 1,000 - 10,000 | 5-50 MB | 1-4時間 |
| ブラックリスト | 100 - 1,000 | 0.1-1 MB | 15分-1日 |
| キャッシュ | 1,000 - 50,000 | 10-100 MB | 5分 |
| レート制限 | 100 - 10,000 | 0.5-5 MB | 1時間 |
| **合計** | **2,200 - 71,000** | **15-156 MB** | - |

---

## キー命名規則

### 命名パターン

Redis のキー命名は、以下の規則に従います：

```
<category>:<entity>:<identifier>[:<sub-identifier>]
```

**構成要素**:
1. **category**: データのカテゴリ（session, blacklist, cache, rate）
2. **entity**: エンティティ種別（user_id, access, refresh, profile）
3. **identifier**: 一意識別子（UUID, JTI など）
4. **sub-identifier**: サブ識別子（オプション、session ID など）

### 命名例

```bash
# セッション
session:550e8400-e29b-41d4-a716-446655440000:sess-abc123

# ブラックリスト
blacklist:access:jti-xyz789
blacklist:refresh:jti-def456

# キャッシュ
cache:profile:550e8400-e29b-41d4-a716-446655440000

# レート制限
rate:550e8400-e29b-41d4-a716-446655440000:/api/profiles:2025093010
```

### 命名のベストプラクティス

1. **小文字を使用**: すべて小文字で統一（例外: UUID は元の形式）
2. **コロン区切り**: 階層構造を`:` で表現
3. **意味のある名前**: キーから内容が推測できる
4. **一貫性**: 同じカテゴリは同じパターンを使用
5. **短すぎず長すぎず**: メモリ効率と可読性のバランス

---

## セッションデータ

### キーパターン

```
session:<user_id>:<sid>
```

**例**:
```
session:550e8400-e29b-41d4-a716-446655440000:sess-7f3d9a1b
```

### データ構造

**データ型**: String（JSON 文字列）

**JSON スキーマ**:
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "session_id": "sess-7f3d9a1b",
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "created_at": "2025-09-30T10:00:00Z",
  "expires_at": "2025-09-30T11:00:00Z",
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0..."
}
```

### TTL 設定

**設定値**: セッションライフタイム（通常 3600秒 = 1時間）

**Python コード例**:
```python
import redis
import json
from datetime import datetime, timedelta

# セッションの保存
def save_session(user_id: str, session_id: str, access_token: str, refresh_token: str):
    key = f"session:{user_id}:{session_id}"

    session_data = {
        "user_id": user_id,
        "session_id": session_id,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "created_at": datetime.utcnow().isoformat(),
        "expires_at": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
    }

    # JSON として保存、TTL は 3600秒
    redis_client.setex(
        key,
        3600,
        json.dumps(session_data)
    )

# セッションの取得
def get_session(user_id: str, session_id: str):
    key = f"session:{user_id}:{session_id}"
    data = redis_client.get(key)

    if data:
        return json.loads(data)
    return None
```

### 削除タイミング

1. **自動削除**: TTL 期限切れ時（1時間後）
2. **手動削除**: ユーザーがログアウト時
3. **強制削除**: 管理者による全セッション削除時

---

## ブラックリストデータ

### アクセストークンブラックリスト

**キーパターン**:
```
blacklist:access:<jti>
```

**例**:
```
blacklist:access:7f3d9a1b-2c8e-4f5a-9b1d-6e8c7a3f2d1b
```

**データ型**: String ("true")

**値**: `"true"` （存在するかどうかが重要）

**TTL**: アクセストークンの有効期限まで（通常 15分）

### リフレッシュトークンブラックリスト

**キーパターン**:
```
blacklist:refresh:<jti>
```

**例**:
```
blacklist:refresh:9b1d6e8c-7a3f-2d1b-7f3d-9a1b2c8e4f5a
```

**データ型**: String ("true")

**TTL**: リフレッシュトークンの有効期限まで（通常 7日）

### 使用フロー

```python
# ログアウト時: トークンをブラックリストに追加
def logout_user(access_token: str, refresh_token: str):
    # JWT をデコードして JTI を取得
    access_jti = decode_token(access_token)["jti"]
    refresh_jti = decode_token(refresh_token)["jti"]

    # アクセストークンの有効期限を取得
    access_exp = decode_token(access_token)["exp"]
    access_ttl = access_exp - int(datetime.utcnow().timestamp())

    # ブラックリストに追加
    redis_client.setex(f"blacklist:access:{access_jti}", access_ttl, "true")

    # リフレッシュトークンも同様に
    refresh_exp = decode_token(refresh_token)["exp"]
    refresh_ttl = refresh_exp - int(datetime.utcnow().timestamp())
    redis_client.setex(f"blacklist:refresh:{refresh_jti}", refresh_ttl, "true")

# リクエスト検証時: ブラックリストをチェック
def is_token_blacklisted(token: str, token_type: str = "access") -> bool:
    jti = decode_token(token)["jti"]
    key = f"blacklist:{token_type}:{jti}"

    return redis_client.exists(key) > 0
```

### メモリ効率

- 値は常に `"true"` （4バイト）
- キー名のみでメモリを消費
- TTL により自動削除されるため、メモリリークなし

---

## キャッシュデータ

### プロファイルキャッシュ

**キーパターン**:
```
cache:profile:<user_id>
```

**例**:
```
cache:profile:550e8400-e29b-41d4-a716-446655440000
```

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
  "cached_at": "2025-09-30T10:00:00Z"
}
```

**TTL**: 300秒（5分）

### Cache-Aside パターン

```python
def get_user_profile(user_id: str):
    # 1. キャッシュをチェック
    cache_key = f"cache:profile:{user_id}"
    cached_data = redis_client.get(cache_key)

    if cached_data:
        # キャッシュヒット
        return json.loads(cached_data)

    # 2. キャッシュミス: データベースから取得
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    if profile:
        # 3. キャッシュに保存（TTL: 300秒）
        profile_data = {
            "user_id": profile.user_id,
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "email": profile.email,
            "phone": profile.phone,
            "cached_at": datetime.utcnow().isoformat()
        }
        redis_client.setex(cache_key, 300, json.dumps(profile_data))

        return profile_data

    return None

def update_user_profile(user_id: str, profile_data: dict):
    # 1. データベースを更新
    db.query(Profile).filter(Profile.user_id == user_id).update(profile_data)
    db.commit()

    # 2. キャッシュを無効化
    cache_key = f"cache:profile:{user_id}"
    redis_client.delete(cache_key)
```

### キャッシュ無効化戦略

1. **TTL ベース**: 5分後に自動削除（デフォルト）
2. **更新時削除**: プロファイル更新時にキャッシュ削除
3. **明示的削除**: 管理者による強制削除

---

## レート制限データ

### キーパターン

```
rate:<user_id>:<endpoint>:<yyyyMMddHH>
```

**例**:
```
rate:550e8400-e29b-41d4-a716-446655440000:/api/profiles:2025093010
```

**構成要素**:
- `user_id`: ユーザーの UUID
- `endpoint`: API エンドポイント（例: `/api/profiles`）
- `yyyyMMddHH`: 時刻（年月日時）

**データ型**: String (整数カウント)

**TTL**: 3600秒（1時間）

### レート制限の実装

```python
from datetime import datetime

def check_rate_limit(user_id: str, endpoint: str, limit: int = 100) -> bool:
    """
    レート制限チェック

    Args:
        user_id: ユーザーID
        endpoint: APIエンドポイント
        limit: 時間あたりの制限数（デフォルト: 100）

    Returns:
        True: リクエスト許可
        False: レート制限超過
    """
    # 現在時刻（時間単位）
    current_hour = datetime.utcnow().strftime("%Y%m%d%H")

    # キー生成
    key = f"rate:{user_id}:{endpoint}:{current_hour}"

    # カウントをインクリメント
    count = redis_client.incr(key)

    # 初回アクセス時に TTL を設定
    if count == 1:
        redis_client.expire(key, 3600)

    # 制限をチェック
    return count <= limit

# FastAPI ミドルウェアでの使用例
@app.get("/api/profiles/{user_id}")
async def get_profile(user_id: str, current_user: User = Depends(get_current_user)):
    # レート制限チェック
    if not check_rate_limit(current_user.id, "/api/profiles", limit=100):
        raise HTTPException(status_code=429, detail="Too Many Requests")

    # 通常の処理
    profile = get_user_profile(user_id)
    return profile
```

### レート制限の種類

| エンドポイント | 時間制限 | 制限回数 | キーパターン例 |
|------------|---------|---------|-------------|
| プロファイル取得 | 1時間 | 100回 | `rate:<uid>:/api/profiles:2025093010` |
| プロファイル更新 | 1時間 | 10回 | `rate:<uid>:/api/profiles/update:2025093010` |
| ログイン | 1時間 | 5回 | `rate:<ip>:/auth/login:2025093010` |
| ドキュメントアップロード | 1時間 | 20回 | `rate:<uid>:/api/documents/upload:2025093010` |

### 時間ウィンドウの自動管理

```python
# 例: 2025-09-30 10:00 - 10:59 の期間
# キー: rate:user-123:/api/profiles:2025093010
# TTL: 3600秒（1時間）

# 11:00 になると新しいキーが自動生成される
# キー: rate:user-123:/api/profiles:2025093011
# 前の時間のキーは TTL により自動削除
```

---

## TTL 管理

### TTL 設計の原則

1. **データの性質に応じた TTL**
   - 短命データ（キャッシュ）: 短い TTL（5分）
   - 中期データ（セッション）: 中程度の TTL（1時間）
   - 長期データ（ブラックリスト）: トークン有効期限まで

2. **メモリ効率の最適化**
   - TTL を設定することで自動削除
   - メモリリークの防止
   - 手動削除の必要性を削減

3. **ビジネスロジックとの整合性**
   - セッション TTL = JWT アクセストークンの有効期限
   - ブラックリスト TTL = JWT トークンの有効期限
   - キャッシュ TTL = データの鮮度要件

### TTL の確認と設定

```python
# TTL の確認（秒単位）
ttl = redis_client.ttl(key)
# 戻り値:
#   正の整数: 残り秒数
#   -1: キーは存在するが TTL なし
#   -2: キーが存在しない

# TTL の設定
redis_client.expire(key, 3600)  # 3600秒後に削除

# データ保存時に TTL を同時設定（推奨）
redis_client.setex(key, 3600, value)

# TTL の延長
redis_client.expire(key, 7200)  # 2時間に延長

# TTL の削除（永続化）
redis_client.persist(key)
```

### TTL 一覧表

| データカテゴリ | TTL（秒） | TTL（時間） | 理由 |
|------------|---------|----------|------|
| セッション | 3600 | 1時間 | アクセストークンの有効期限 |
| アクセストークンブラックリスト | 900 | 15分 | アクセストークンの有効期限 |
| リフレッシュトークンブラックリスト | 604800 | 7日 | リフレッシュトークンの有効期限 |
| プロファイルキャッシュ | 300 | 5分 | データの鮮度バランス |
| レート制限 | 3600 | 1時間 | 時間ウィンドウ |

---

## データ型の選択

### Redis データ型の概要

Redis は複数のデータ型をサポートしていますが、ai-micro-service では主に **String** を使用しています。

| Redis データ型 | 用途 | ai-micro-service での使用 |
|--------------|------|------------------------|
| String | シンプルなキー・バリュー | ✅ セッション（JSON）、ブラックリスト、キャッシュ（JSON）、レート制限（カウント） |
| Hash | フィールド・バリューのマップ | ❌ 現在未使用（将来的に検討） |
| List | 順序付きリスト | ❌ 現在未使用 |
| Set | ユニークな値の集合 | ❌ 現在未使用 |
| Sorted Set | スコア付き順序集合 | ❌ 現在未使用 |

### String データ型を選択した理由

1. **シンプルさ**: 最も基本的で理解しやすい
2. **JSON との親和性**: JSON 文字列として保存が容易
3. **TTL サポート**: すべての String キーに TTL を設定可能
4. **アトミック操作**: INCR など原子性のある操作が可能
5. **互換性**: すべての Redis クライアントでサポート

### JSON vs Hash の比較

**String (JSON) を使用する場合**:
```python
# 保存
redis_client.setex(
    "session:user-123:sess-abc",
    3600,
    json.dumps({"user_id": "123", "email": "test@example.com"})
)

# 取得（全体）
data = json.loads(redis_client.get("session:user-123:sess-abc"))
```

**Hash を使用する場合**（現在未使用）:
```python
# 保存
redis_client.hset("session:user-123:sess-abc", mapping={
    "user_id": "123",
    "email": "test@example.com"
})

# 取得（フィールド単位）
user_id = redis_client.hget("session:user-123:sess-abc", "user_id")
email = redis_client.hget("session:user-123:sess-abc", "email")
```

**String (JSON) を選択した理由**:
- セッションデータは常に全体を取得する
- 部分的な取得・更新の必要性が低い
- JSON としての可読性と互換性
- TTL 管理のシンプルさ

---

## データ操作の実装例

### 基本操作

```python
import redis
import json
from typing import Optional

class RedisClient:
    def __init__(self, host: str, port: int, password: str):
        self.client = redis.Redis(
            host=host,
            port=port,
            password=password,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5
        )

    # セッション操作
    def save_session(self, user_id: str, session_id: str, data: dict, ttl: int = 3600):
        key = f"session:{user_id}:{session_id}"
        self.client.setex(key, ttl, json.dumps(data))

    def get_session(self, user_id: str, session_id: str) -> Optional[dict]:
        key = f"session:{user_id}:{session_id}"
        data = self.client.get(key)
        return json.loads(data) if data else None

    def delete_session(self, user_id: str, session_id: str):
        key = f"session:{user_id}:{session_id}"
        self.client.delete(key)

    # ブラックリスト操作
    def add_to_blacklist(self, jti: str, token_type: str = "access", ttl: int = 900):
        key = f"blacklist:{token_type}:{jti}"
        self.client.setex(key, ttl, "true")

    def is_blacklisted(self, jti: str, token_type: str = "access") -> bool:
        key = f"blacklist:{token_type}:{jti}"
        return self.client.exists(key) > 0

    # キャッシュ操作
    def cache_profile(self, user_id: str, profile_data: dict, ttl: int = 300):
        key = f"cache:profile:{user_id}"
        self.client.setex(key, ttl, json.dumps(profile_data))

    def get_cached_profile(self, user_id: str) -> Optional[dict]:
        key = f"cache:profile:{user_id}"
        data = self.client.get(key)
        return json.loads(data) if data else None

    def invalidate_cache(self, user_id: str):
        key = f"cache:profile:{user_id}"
        self.client.delete(key)

    # レート制限操作
    def check_rate_limit(self, user_id: str, endpoint: str, limit: int = 100) -> bool:
        from datetime import datetime
        current_hour = datetime.utcnow().strftime("%Y%m%d%H")
        key = f"rate:{user_id}:{endpoint}:{current_hour}"

        count = self.client.incr(key)
        if count == 1:
            self.client.expire(key, 3600)

        return count <= limit
```

---

## データの監視

### キー数の確認

```bash
# すべてのキー数
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} dbsize

# パターンマッチングでキー検索
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "session:*" | wc -l
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "blacklist:*" | wc -l
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "cache:*" | wc -l
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "rate:*" | wc -l
```

### メモリ使用量の確認

```bash
# 全体のメモリ使用量
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info memory

# 特定キーのメモリサイズ
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} memory usage "session:user-123:sess-abc"
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [Auth Service の Redis 使用法](./03-auth-service-usage.md)
- [User API の Redis 使用法](./04-user-api-usage.md)
- [Admin API の Redis 使用法](./05-admin-api-usage.md)
- [キャッシュ戦略](./06-cache-strategy.md)
- [セッション管理](./07-session-management.md)

---

**次のステップ**: [Auth Service の Redis 使用法](./03-auth-service-usage.md) を参照して、認証サービスにおける具体的な実装を確認してください。