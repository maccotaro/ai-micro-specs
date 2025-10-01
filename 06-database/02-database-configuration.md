# PostgreSQL データベース - 設定詳細

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [Docker Compose 設定](#docker-compose-設定)
- [環境変数](#環境変数)
- [接続文字列](#接続文字列)
- [PostgreSQL 設定](#postgresql-設定)
- [パフォーマンスチューニング](#パフォーマンスチューニング)
- [セキュリティ設定](#セキュリティ設定)
- [ログ設定](#ログ設定)

---

## Docker Compose 設定

### docker-compose.yml

**ファイルパス**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/docker-compose.yml`

```yaml
version: '3.9'
services:
  postgres:
    build:
      context: .
      dockerfile: Dockerfile
    image: ai-micro-postgres:pgvector-15
    container_name: ai-micro-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### 設定項目の説明

#### サービス設定

| 項目 | 値 | 説明 |
|-----|-----|------|
| `build.context` | `.` | Dockerfile のビルドコンテキスト |
| `build.dockerfile` | `Dockerfile` | 使用する Dockerfile 名 |
| `image` | `ai-micro-postgres:pgvector-15` | ビルド後のイメージ名とタグ |
| `container_name` | `ai-micro-postgres` | 起動するコンテナ名 |

#### 環境変数

| 項目 | 説明 | デフォルト |
|-----|------|---------|
| `POSTGRES_USER` | PostgreSQL のスーパーユーザー名 | `.env` から読み込み |
| `POSTGRES_PASSWORD` | PostgreSQL のパスワード | `.env` から読み込み |

#### ポートマッピング

| ホスト | コンテナ | 説明 |
|-------|---------|------|
| 5432 | 5432 | PostgreSQL 標準ポート |

#### ボリュームマウント

| ホストパス | コンテナパス | 説明 |
|---------|----------|------|
| `./db/init.sql` | `/docker-entrypoint-initdb.d/init.sql` | 初期化スクリプト |
| `postgres_data` | `/var/lib/postgresql/data` | データ永続化ボリューム |

### Dockerfile

**ファイルパス**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/Dockerfile`

PostgreSQL 15 ベースイメージに pgvector 拡張を追加したカスタムイメージ:

```dockerfile
FROM postgres:15

# pgvector拡張のインストール
# （実際の内容は Dockerfile を参照）
```

**ビルド理由**:
- pgvector 拡張を含めるため
- 将来的な拡張機能追加の柔軟性
- 一貫性のあるイメージ名（ai-micro-postgres:pgvector-15）

---

## 環境変数

### .env ファイル

**ファイルパス**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/.env`

```bash
# PostgreSQL設定
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-secure-password-here
```

### 環境変数詳細

#### POSTGRES_USER

**用途**: PostgreSQL のスーパーユーザー名

**デフォルト**: `postgres`

**注意事項**:
- すべてのデータベースへのフルアクセス権限
- 本番環境では管理用途にのみ使用
- 各サービスには専用ロールの作成を推奨

#### POSTGRES_PASSWORD

**用途**: PostgreSQL のスーパーユーザーパスワード

**セキュリティ要件**:
```bash
# 開発環境の例
POSTGRES_PASSWORD=dev-password-123

# 本番環境の要件
# - 最小12文字以上
# - 大文字、小文字、数字、記号を含む
# - 辞書に載っていない文字列
POSTGRES_PASSWORD=P@ssw0rd!2025#SecureDB
```

**セキュリティベストプラクティス**:
1. `.env` ファイルを `.gitignore` に追加（済み）
2. 環境ごとに異なるパスワードを使用
3. パスワードマネージャーで管理
4. 定期的なローテーション（90日ごと推奨）
5. AWS Secrets Manager / HashiCorp Vault などのシークレット管理ツール使用

### 環境変数の読み込み確認

```bash
# Docker Compose が環境変数を読み込んでいるか確認
docker compose config

# コンテナ内の環境変数確認
docker exec ai-micro-postgres env | grep POSTGRES
```

---

## 接続文字列

### 基本フォーマット

```
postgresql://[ユーザー名]:[パスワード]@[ホスト]:[ポート]/[データベース名]
```

### 各サービスの接続文字列

#### Auth Service → authdb

**環境**: Docker コンテナ内
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/authdb
```

**環境**: ホストマシン（開発時）
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/authdb
```

#### User API Service → apidb

**環境**: Docker コンテナ内
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/apidb
```

**環境**: ホストマシン（開発時）
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/apidb
```

#### Admin API Service → admindb

**環境**: Docker コンテナ内
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/admindb
```

**環境**: ホストマシン（開発時）
```bash
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/admindb
```

### 接続オプション

#### タイムアウト設定

```bash
postgresql://postgres:password@host.docker.internal:5432/authdb?connect_timeout=10
```

#### SSL接続（本番環境）

```bash
postgresql://postgres:password@db.example.com:5432/authdb?sslmode=require
```

**sslmode オプション**:
- `disable`: SSL接続を使用しない（開発環境のみ）
- `require`: SSL接続を要求（証明書検証なし）
- `verify-ca`: SSL接続 + CA証明書検証
- `verify-full`: SSL接続 + CA証明書 + ホスト名検証（最も安全）

#### コネクションプール設定

```bash
# SQLAlchemy での設定例
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/authdb
POOL_SIZE=20
MAX_OVERFLOW=10
POOL_PRE_PING=true
```

### 接続テスト

#### psql での接続テスト

```bash
# authdb に接続
psql postgresql://postgres:password@localhost:5432/authdb

# 接続成功時の出力
# psql (15.x)
# Type "help" for help.
# authdb=#
```

#### Python での接続テスト

```python
from sqlalchemy import create_engine, text

# 接続文字列
database_url = "postgresql://postgres:password@localhost:5432/authdb"

# エンジン作成
engine = create_engine(database_url)

# 接続テスト
with engine.connect() as conn:
    result = conn.execute(text("SELECT version()"))
    print(result.fetchone())
```

---

## PostgreSQL 設定

### デフォルト設定

PostgreSQL 15 の公式イメージはデフォルトで以下の設定を使用:

```conf
# 基本設定
listen_addresses = '*'
port = 5432
max_connections = 100

# メモリ設定
shared_buffers = 128MB
work_mem = 4MB
maintenance_work_mem = 64MB

# WAL設定
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB

# ロギング
log_destination = 'stderr'
logging_collector = off
log_statement = 'none'
```

### カスタム設定の適用方法

#### 方法1: 環境変数でコマンドオプション指定

```yaml
# docker-compose.yml
services:
  postgres:
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    command:
      - "postgres"
      - "-c"
      - "shared_buffers=256MB"
      - "-c"
      - "max_connections=200"
```

#### 方法2: postgresql.conf ファイルをマウント

```yaml
# docker-compose.yml
services:
  postgres:
    volumes:
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
      - ./config/postgresql.conf:/etc/postgresql/postgresql.conf
      - postgres_data:/var/lib/postgresql/data
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
```

**postgresql.conf 例**:
```conf
# 接続設定
max_connections = 200
superuser_reserved_connections = 3

# メモリ設定
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 8MB
maintenance_work_mem = 128MB

# チェックポイント設定
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100

# ロギング
log_destination = 'stderr'
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'all'
log_duration = on
log_min_duration_statement = 1000
```

### 設定の確認

```bash
# コンテナ内で設定確認
docker exec ai-micro-postgres psql -U postgres -c "SHOW shared_buffers;"
docker exec ai-micro-postgres psql -U postgres -c "SHOW max_connections;"

# すべての設定を表示
docker exec ai-micro-postgres psql -U postgres -c "SHOW ALL;"
```

---

## パフォーマンスチューニング

### システムリソースに基づく推奨値

#### 小規模環境（メモリ 4GB 以下）

```conf
shared_buffers = 128MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
max_connections = 50
```

#### 中規模環境（メモリ 8GB）

```conf
shared_buffers = 256MB
effective_cache_size = 2GB
work_mem = 8MB
maintenance_work_mem = 128MB
max_connections = 100
```

#### 大規模環境（メモリ 16GB 以上）

```conf
shared_buffers = 512MB
effective_cache_size = 4GB
work_mem = 16MB
maintenance_work_mem = 256MB
max_connections = 200
```

### コネクションプール設定（SQLAlchemy）

#### Auth Service の設定例

```python
# ai-micro-api-auth/app/db/session.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

engine = create_engine(
    settings.database_url,

    # プールサイズ（同時接続数）
    pool_size=20,

    # プールがフルの場合の追加接続数
    max_overflow=10,

    # 接続前にpingして確認（推奨）
    pool_pre_ping=True,

    # アイドル接続のリサイクル時間（秒）
    pool_recycle=3600,

    # アイドル接続のタイムアウト（秒）
    pool_timeout=30,

    # SQLエコー（開発時のみ）
    echo=False
)
```

#### User API Service の設定例

```python
# ai-micro-api-user/app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=15,           # Authより少なめ（負荷が低い）
    max_overflow=5,
    pool_pre_ping=True,
    pool_recycle=3600,
    echo=False
)
```

#### Admin API Service の設定例

```python
# ai-micro-api-admin/app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=25,           # RAG処理で負荷が高い
    max_overflow=15,
    pool_pre_ping=True,
    pool_recycle=3600,
    echo=False
)
```

### インデックス最適化

各データベースのインデックス戦略については個別ドキュメントを参照:
- [authdb インデックス](./04-authdb-schema.md#インデックス設計)
- [apidb インデックス](./05-apidb-schema.md#インデックス設計)
- [admindb インデックス](./06-admindb-schema.md#インデックス設計)

### VACUUM と ANALYZE

定期的なメンテナンスコマンド:

```sql
-- 自動バキューム設定確認
SHOW autovacuum;

-- 手動VACUUM（データベース単位）
VACUUM ANALYZE authdb;
VACUUM ANALYZE apidb;
VACUUM ANALYZE admindb;

-- テーブル単位
VACUUM ANALYZE users;
VACUUM ANALYZE profiles;
VACUUM ANALYZE documents;
```

**スケジュール例**:
```bash
# cron で毎週日曜 3:00 AM に実行
0 3 * * 0 docker exec ai-micro-postgres psql -U postgres -c "VACUUM ANALYZE;"
```

---

## セキュリティ設定

### ロール管理

#### サービス専用ロールの作成

本番環境では各サービス専用のデータベースロールを作成することを推奨:

```sql
-- Auth Service 専用ロール
CREATE ROLE auth_service WITH LOGIN PASSWORD 'auth-secure-password';
GRANT CONNECT ON DATABASE authdb TO auth_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO auth_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO auth_service;

-- User API Service 専用ロール
CREATE ROLE user_api_service WITH LOGIN PASSWORD 'user-secure-password';
GRANT CONNECT ON DATABASE apidb TO user_api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO user_api_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO user_api_service;

-- Admin API Service 専用ロール
CREATE ROLE admin_api_service WITH LOGIN PASSWORD 'admin-secure-password';
GRANT CONNECT ON DATABASE admindb TO admin_api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO admin_api_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO admin_api_service;
```

#### 最小権限の原則

```sql
-- 読み取り専用ロール（レポート用など）
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'readonly-password';
GRANT CONNECT ON DATABASE authdb TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
```

### pg_hba.conf 設定

**ファイルパス**: `/var/lib/postgresql/data/pg_hba.conf`

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# ローカル接続（Dockerコンテナ内）
local   all             all                                     trust

# Docker ネットワーク内からの接続
host    all             all             172.0.0.0/8             md5

# 外部からの接続（本番環境では制限）
host    all             all             0.0.0.0/0               md5
```

**本番環境の推奨設定**:
```conf
# 特定IPアドレスのみ許可
host    authdb          auth_service    10.0.1.0/24             md5
host    apidb           user_api_service 10.0.2.0/24            md5
host    admindb         admin_api_service 10.0.3.0/24           md5

# SSL接続を強制
hostssl all             all             0.0.0.0/0               md5
```

### SSL/TLS 設定

本番環境では SSL 接続を有効化:

```bash
# 証明書生成
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt \
  -keyout server.key \
  -subj "/CN=postgres.example.com"

# 権限設定
chmod 600 server.key
chown postgres:postgres server.key server.crt
```

```yaml
# docker-compose.yml
services:
  postgres:
    volumes:
      - ./certs/server.crt:/var/lib/postgresql/server.crt
      - ./certs/server.key:/var/lib/postgresql/server.key
    command:
      - "postgres"
      - "-c"
      - "ssl=on"
      - "-c"
      - "ssl_cert_file=/var/lib/postgresql/server.crt"
      - "-c"
      - "ssl_key_file=/var/lib/postgresql/server.key"
```

---

## ログ設定

### ログレベル設定

```conf
# postgresql.conf
log_min_messages = warning         # サーバーログレベル
log_min_error_statement = error    # エラーとして記録する最小レベル
log_min_duration_statement = 1000  # 1秒以上かかるクエリをログ
```

### ログフォーマット設定

```conf
# ログ出力形式
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# 出力例:
# 2025-09-30 10:15:23 JST [1234]: [1-1] user=postgres,db=authdb,app=psql,client=172.17.0.1
```

### スロークエリログ

```conf
# 1秒以上かかるクエリをログに記録
log_min_duration_statement = 1000

# 実行計画も記録（開発環境のみ）
log_statement = 'all'
log_duration = on
```

**スロークエリの確認**:
```bash
# コンテナログから確認
docker compose logs postgres | grep "duration:"

# 出力例:
# LOG:  duration: 1234.567 ms  statement: SELECT * FROM users WHERE ...
```

### ログローテーション

Docker の標準出力ログローテーション:

```yaml
# docker-compose.yml
services:
  postgres:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"      # ログファイル最大サイズ
        max-file: "3"        # 保持するファイル数
```

---

## 監視とメトリクス

### 接続数の監視

```sql
-- 現在の接続数
SELECT count(*) FROM pg_stat_activity;

-- データベース別接続数
SELECT datname, count(*)
FROM pg_stat_activity
GROUP BY datname;

-- 詳細情報
SELECT pid, usename, datname, state, query
FROM pg_stat_activity
WHERE state != 'idle';
```

### データベースサイズの監視

```sql
-- データベース別サイズ
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- テーブル別サイズ（authdb例）
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### パフォーマンス統計

```sql
-- キャッシュヒット率（95%以上が理想）
SELECT
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- インデックス使用率
SELECT
    schemaname,
    tablename,
    indexrelname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

---

## トラブルシューティング

### 接続エラー

**症状**: `could not connect to server`

**確認事項**:
```bash
# PostgreSQL が起動しているか
docker ps | grep ai-micro-postgres

# ポートがリッスンしているか
docker exec ai-micro-postgres netstat -tln | grep 5432

# pg_isready で確認
docker exec ai-micro-postgres pg_isready -U postgres
```

### 接続数上限エラー

**症状**: `FATAL: sorry, too many clients already`

**原因**: `max_connections` を超えた

**解決策**:
```bash
# 現在の接続数確認
docker exec ai-micro-postgres psql -U postgres -c \
  "SELECT count(*) FROM pg_stat_activity;"

# max_connections を増やす
# docker-compose.yml に追加:
command:
  - "postgres"
  - "-c"
  - "max_connections=200"
```

### パスワード認証失敗

**症状**: `FATAL: password authentication failed`

**確認事項**:
```bash
# .env ファイルの内容確認
cat .env

# コンテナの環境変数確認
docker exec ai-micro-postgres env | grep POSTGRES_PASSWORD

# 環境変数の再読み込み
docker compose down
docker compose up -d
```

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [バックアップとリストア](./10-backup-restore.md)
- [Auth Service 設定](/01-auth-service/02-api-specification.md)
- [User API Service 設定](/02-user-api/02-api-specification.md)
- [Admin API Service 設定](/03-admin-api/02-api-specification.md)

---

**次のステップ**: [スキーマ設計概要](./03-schema-design-overview.md) を参照して、3つのデータベースの設計思想と構造を理解してください。