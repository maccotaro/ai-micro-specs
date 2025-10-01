# Redis キャッシュインフラ - 概要

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [システム概要](#システム概要)
- [アーキテクチャ](#アーキテクチャ)
- [技術スタック](#技術スタック)
- [主要機能](#主要機能)
- [コンテナ構成](#コンテナ構成)
- [ポート構成](#ポート構成)
- [サービス統合](#サービス統合)
- [データ構造概要](#データ構造概要)

---

## システム概要

### 役割

Redis キャッシュインフラは、ai-micro-service マイクロサービスアーキテクチャにおける高速キャッシュおよびセッション管理層です。認証サービス、ユーザーAPI、管理APIに対して、インメモリデータストアとしての機能を提供し、システム全体のパフォーマンスとスケーラビリティを向上させます。

### 主要機能

1. **セッション管理**
   - ユーザーセッション情報の保存
   - JWT トークン情報の一時保存
   - セッションライフタイム管理

2. **トークンブラックリスト**
   - ログアウト時のアクセストークン無効化
   - リフレッシュトークンの無効化
   - トークン有効期限に基づく自動削除（TTL）

3. **プロファイルキャッシュ**
   - ユーザープロファイル情報のキャッシュ
   - データベースアクセス削減
   - 300秒（5分）のTTL設定

4. **レート制限**
   - APIエンドポイント単位のレート制限
   - 時間単位のリクエスト数カウント
   - DDoS攻撃の緩和

---

## アーキテクチャ

### システム構成図

```
┌─────────────────────────────────────────────────────────────┐
│  ai-micro-redis (Container)                                  │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Redis 7                                             │   │
│  │                                                       │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │   │
│  │  │   Sessions   │  │  Blacklists  │  │  Caches   │ │   │
│  │  ├──────────────┤  ├──────────────┤  ├───────────┤ │   │
│  │  │ session:     │  │ blacklist:   │  │ cache:    │ │   │
│  │  │ <user_id>:   │  │ access:<jti> │  │ profile:  │ │   │
│  │  │ <sid>        │  │              │  │ <user_id> │ │   │
│  │  │              │  │ blacklist:   │  │           │ │   │
│  │  │              │  │ refresh:     │  │ rate:     │ │   │
│  │  │              │  │ <jti>        │  │ <pattern> │ │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘ │   │
│  │                                                       │   │
│  │  Port: 6379                                          │   │
│  │  Auth: requirepass (password protection)            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  Config: /usr/local/etc/redis/redis.conf                    │
└─────────────────────────────────────────────────────────────┘
         ↑                   ↑                   ↑
         │                   │                   │
    ┌────┴────┐         ┌───┴────┐         ┌────┴────┐
    │  Auth   │         │  User  │         │  Admin  │
    │ Service │         │   API  │         │   API   │
    └─────────┘         └────────┘         └─────────┘
   Port 8002           Port 8001           Port 8003
```

### マイクロサービスとの統合

Redis は以下の3つのマイクロサービスから利用されます：

1. **Auth Service (ai-micro-api-auth)**
   - セッション管理
   - トークンブラックリスト
   - ログイン試行回数制限

2. **User API Service (ai-micro-api-user)**
   - プロファイルキャッシュ
   - APIレート制限

3. **Admin API Service (ai-micro-api-admin)**
   - ジョブステータス管理
   - ドキュメント処理キュー
   - 管理操作のレート制限

---

## 技術スタック

### Redis 7

**選定理由**:
- **高速性**: インメモリデータストアによる超高速アクセス
- **データ型の豊富さ**: String、Hash、List、Set、Sorted Set など
- **TTL サポート**: キーの自動有効期限管理
- **原子性**: アトミックな操作による並行処理の安全性
- **永続化オプション**: RDB および AOF による耐障害性

**技術仕様**:
```bash
# Redis バージョン
Redis server v=7.0.x

# プロトコル
RESP (Redis Serialization Protocol)

# データ永続化
- RDB: スナップショット方式
- AOF: Append-Only File（オプション）

# 認証
requirepass による password 認証
```

### Python Redis Client (redis-py)

**用途**:
- Python マイクロサービスから Redis への接続
- 高レベル API による簡単なデータ操作
- コネクションプーリングによる効率的な接続管理

**接続例**:
```python
import redis

# Redis クライアント作成
client = redis.Redis(
    host='host.docker.internal',
    port=6379,
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True,  # 文字列として取得
    socket_connect_timeout=5,
    socket_timeout=5
)

# 接続確認
client.ping()  # => True
```

---

## 主要機能

### 1. セッション管理

**目的**: ユーザーの認証状態を保持

**キーパターン**: `session:<user_id>:<sid>`

**データ型**: String (JSON)

**TTL**: セッションライフタイム（例: 3600秒 = 1時間）

**格納データ**:
```json
{
  "user_id": "uuid-v4",
  "session_id": "session-uuid",
  "access_token": "jwt-token",
  "refresh_token": "jwt-token",
  "created_at": "2025-09-30T10:00:00Z",
  "expires_at": "2025-09-30T11:00:00Z"
}
```

### 2. トークンブラックリスト

**目的**: ログアウト時のトークン無効化

**キーパターン**:
- `blacklist:access:<jti>` - アクセストークン
- `blacklist:refresh:<jti>` - リフレッシュトークン

**データ型**: String ("true")

**TTL**: トークンの有効期限まで

**動作フロー**:
```
1. ユーザーがログアウト
2. アクセストークンの JTI を抽出
3. blacklist:access:<jti> = "true" を保存（TTL付き）
4. 以降のリクエストで JTI をチェック
5. ブラックリストに存在すれば 401 Unauthorized
```

### 3. プロファイルキャッシュ

**目的**: データベースアクセスの削減

**キーパターン**: `cache:profile:<user_id>`

**データ型**: String (JSON)

**TTL**: 300秒（5分）

**格納データ**:
```json
{
  "user_id": "uuid-v4",
  "first_name": "太郎",
  "last_name": "山田",
  "email": "taro@example.com",
  "phone": "090-1234-5678",
  "cached_at": "2025-09-30T10:00:00Z"
}
```

**キャッシュ戦略**: Cache-Aside (Lazy Loading)

### 4. レート制限

**目的**: API の過剰利用防止

**キーパターン**: `rate:<user_id>:<endpoint>:<yyyyMMddHH>`

**データ型**: String (カウント)

**TTL**: 3600秒（1時間）

**動作例**:
```python
# キー例: rate:user-123:/api/profiles:2025093010
# 値: "45"  （この時間帯のリクエスト数）

# 時間単位でキーが自動生成され、1時間後に自動削除
```

---

## コンテナ構成

### Docker Compose 設定

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-redis/docker-compose.yml`

```yaml
version: '3.9'
services:
  redis:
    build:
      context: .
      dockerfile: Dockerfile
    image: ai-micro-redis:7
    container_name: ai-micro-redis
    command: redis-server /usr/local/etc/redis/redis.conf --requirepass ${REDIS_PASSWORD}
    ports:
      - "6379:6379"
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
      - redis_data:/data
    restart: unless-stopped

volumes:
  redis_data:
```

### Dockerfile

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-redis/Dockerfile`

```dockerfile
FROM redis:7

# カスタム設定ファイルのコピー
COPY redis.conf /usr/local/etc/redis/redis.conf

# データディレクトリの作成
RUN mkdir -p /data

EXPOSE 6379

# デフォルトコマンド（docker-compose.yml で上書き）
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]
```

### 環境変数

**.env ファイル**:
```bash
REDIS_PASSWORD=your-secure-redis-password-here
```

**生成方法**:
```bash
# 安全なパスワード生成
openssl rand -hex 32
```

**セキュリティ注意**:
- `.env` ファイルは `.gitignore` に追加済み
- 本番環境では強固なパスワードを設定
- パスワードは環境変数またはシークレット管理ツールで管理

---

## ポート構成

### ポートマッピング

| ホストポート | コンテナポート | プロトコル | 用途 |
|----------|------------|--------|------|
| 6379 | 6379 | TCP | Redis 接続 |

### 接続方法

**Docker コンテナから接続**:
```bash
# 他のコンテナから
redis://:<password>@host.docker.internal:6379
```

**ホストマシンから接続**:
```bash
# redis-cli（パスワード付き）
redis-cli -h localhost -p 6379 -a ${REDIS_PASSWORD}

# Docker exec 経由（推奨）
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD}
```

**Python からの接続**:
```python
import redis
import os

client = redis.Redis(
    host='host.docker.internal',
    port=6379,
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True
)
```

---

## サービス統合

### Auth Service との統合

**サービス**: ai-micro-api-auth (Port 8002)
**接続**: redis-py

**使用機能**:
- セッション管理（`session:<user_id>:<sid>`）
- トークンブラックリスト（`blacklist:access:<jti>`, `blacklist:refresh:<jti>`）
- ログイン試行回数制限（`rate:<ip>:login:<yyyyMMddHH>`）

**関連ドキュメント**:
- [Auth Service の Redis 使用法](./03-auth-service-usage.md)
- [セッション管理詳細](./07-session-management.md)

### User API Service との統合

**サービス**: ai-micro-api-user (Port 8001)
**接続**: redis-py

**使用機能**:
- プロファイルキャッシュ（`cache:profile:<user_id>`）
- APIレート制限（`rate:<user_id>:<endpoint>:<yyyyMMddHH>`）

**関連ドキュメント**:
- [User API の Redis 使用法](./04-user-api-usage.md)
- [キャッシュ戦略](./06-cache-strategy.md)

### Admin API Service との統合

**サービス**: ai-micro-api-admin (Port 8003)
**接続**: redis-py

**使用機能**:
- ジョブステータス管理（`job:status:<job_id>`）
- ドキュメント処理キュー（`queue:document:processing`）
- 管理APIレート制限（`rate:<user_id>:<admin_endpoint>:<yyyyMMddHH>`）

**関連ドキュメント**:
- [Admin API の Redis 使用法](./05-admin-api-usage.md)

---

## データ構造概要

### 主要なキーパターン一覧

| 用途 | キーパターン | データ型 | TTL | 使用サービス |
|------|-------------|---------|-----|-----------|
| ユーザーセッション | `session:<user_id>:<sid>` | String (JSON) | セッションライフタイム | Auth Service |
| アクセストークンブラックリスト | `blacklist:access:<jti>` | String ("true") | トークン有効期限 | Auth Service |
| リフレッシュトークンブラックリスト | `blacklist:refresh:<jti>` | String ("true") | トークン有効期限 | Auth Service |
| プロファイルキャッシュ | `cache:profile:<user_id>` | String (JSON) | 300秒 | User API |
| レート制限 | `rate:<user_id>:<endpoint>:<yyyyMMddHH>` | String (count) | 3600秒 | 全サービス |

**詳細**: [データ構造概要](./02-data-structure-overview.md) を参照

---

## 起動・停止手順

### 起動

```bash
cd /Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-redis

# コンテナ起動
docker compose up -d

# ログ確認
docker compose logs -f redis
```

**起動確認**:
```bash
# PING コマンドでヘルスチェック
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} ping
# => PONG
```

### 停止

```bash
# コンテナ停止
docker compose stop

# コンテナ削除
docker compose down

# データ削除（注意！）
docker compose down -v
```

### ヘルスチェック

```bash
# Redis が起動しているか確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} ping

# Redis 情報確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info server

# 接続クライアント数確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} client list
```

---

## 監視とメンテナンス

### リアルタイム監視

```bash
# メモリ使用状況
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info memory

# キースペース統計
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info keyspace

# スロークエリログ（10ms以上）
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} slowlog get 10
```

### パフォーマンス確認

```bash
# Redis の統計情報
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info stats

# 接続数確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} info clients

# レイテンシ監視
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --latency
```

---

## トラブルシューティング

### コンテナが起動しない

**症状**: `docker compose up` でエラー

**確認事項**:
```bash
# ポート 6379 が使用中か確認
lsof -i :6379

# 既存の Redis プロセスを停止
brew services stop redis  # macOS
sudo systemctl stop redis # Linux
```

### 認証エラー

**症状**: `NOAUTH Authentication required`

**解決策**:
```bash
# .env ファイルの REDIS_PASSWORD を確認
cat .env

# パスワード付きで接続
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD}
```

### メモリ不足

**症状**: `OOM command not allowed when used memory > 'maxmemory'`

**解決策**:
```bash
# redis.conf の maxmemory を確認
# 現在: 512mb

# maxmemory-policy を確認
# 推奨: volatile-ttl（TTL付きキーから削除）
```

---

## パフォーマンスチューニング

### メモリ管理

**設定**: `redis.conf`

```conf
# 最大メモリ（512MB）
maxmemory 512mb

# メモリ削除ポリシー（TTL付きキーから削除）
maxmemory-policy volatile-ttl
```

**メモリ削除ポリシーの種類**:
- `volatile-ttl`: TTL が短いキーから削除（推奨）
- `volatile-lru`: TTL 付きキーのうち最も使われていないものを削除
- `allkeys-lru`: すべてのキーから最も使われていないものを削除

### 永続化設定

**RDB スナップショット**:
```conf
# 900秒間に1回以上の変更があれば保存
save 900 1

# 300秒間に10回以上の変更があれば保存
save 300 10

# 60秒間に10000回以上の変更があれば保存
save 60 10000
```

**AOF（Append-Only File）**:
```conf
# AOF 無効（現在の設定）
appendonly no

# 本番環境では有効化を推奨
appendonly yes
appendfsync everysec
```

---

## セキュリティ

### パスワード認証

**設定**: `docker-compose.yml`

```yaml
command: redis-server /usr/local/etc/redis/redis.conf --requirepass ${REDIS_PASSWORD}
```

**接続時の認証**:
```bash
# パスワード付きで接続
redis-cli -a ${REDIS_PASSWORD}

# または接続後に認証
redis-cli
127.0.0.1:6379> AUTH ${REDIS_PASSWORD}
OK
```

### ネットワーク保護

**設定**: `redis.conf`

```conf
# すべてのインターフェースでリッスン
bind 0.0.0.0

# 保護モード有効（パスワード必須）
protected-mode yes
```

**本番環境の推奨設定**:
- Docker ネットワーク内での通信に限定
- TLS/SSL 接続の使用
- ファイアウォールによるアクセス制限

---

## 関連ドキュメント

### Redis データ構造
- [データ構造概要](./02-data-structure-overview.md)
- [セッション管理](./07-session-management.md)
- [キャッシュ戦略](./06-cache-strategy.md)

### サービス統合
- [Auth Service の Redis 使用法](./03-auth-service-usage.md)
- [User API の Redis 使用法](./04-user-api-usage.md)
- [Admin API の Redis 使用法](./05-admin-api-usage.md)

### 運用管理
- [永続化設定](./08-persistence.md)
- [パフォーマンスチューニング](./09-performance-tuning.md)
- [高可用性戦略](./10-high-availability.md)

---

**次のステップ**: [データ構造概要](./02-data-structure-overview.md) を参照して、Redis で使用されるキーパターンとデータ型の詳細を確認してください。