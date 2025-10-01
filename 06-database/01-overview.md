# PostgreSQL データベースインフラ - 概要

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [システム概要](#システム概要)
- [アーキテクチャ](#アーキテクチャ)
- [データベース構成](#データベース構成)
- [技術スタック](#技術スタック)
- [コンテナ構成](#コンテナ構成)
- [ボリューム管理](#ボリューム管理)
- [ポート構成](#ポート構成)
- [サービス統合](#サービス統合)

---

## システム概要

### 役割

PostgreSQL データベースインフラは、ai-micro-service マイクロサービスアーキテクチャの中核となるデータ永続化層です。3つの独立したデータベース（authdb、apidb、admindb）を単一の PostgreSQL インスタンス内で管理し、各マイクロサービスに対して専用のデータストレージを提供します。

### 主要機能

1. **マルチデータベース構成**
   - 認証データベース（authdb）: ユーザー認証情報
   - APIデータベース（apidb）: ユーザープロファイル情報
   - 管理データベース（admindb）: 管理機能、ドキュメント、RAG

2. **PostgreSQL 15 + pgvector**
   - 最新の PostgreSQL 15 を使用
   - pgvector 拡張によるベクトル検索（RAG対応）
   - UUID 拡張（uuid-ossp）による分散ID生成

3. **データ永続化**
   - Docker ボリュームによる永続化（postgres_data）
   - コンテナ再起動後もデータ保持
   - バックアップ・リストア機能

4. **自動初期化**
   - init.sql による自動スキーマ作成
   - 初回起動時にすべてのテーブル・インデックス作成
   - pgvector コレクションの初期設定

---

## アーキテクチャ

### システム構成図

```
┌─────────────────────────────────────────────────────────────┐
│  ai-micro-postgres (Container)                              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  PostgreSQL 15 + pgvector                            │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │  │
│  │  │   authdb    │  │   apidb     │  │  admindb    │ │  │
│  │  ├─────────────┤  ├─────────────┤  ├─────────────┤ │  │
│  │  │ - users     │  │ - profiles  │  │ - system_   │ │  │
│  │  │             │  │             │  │   logs      │ │  │
│  │  │             │  │             │  │ - login_    │ │  │
│  │  │             │  │             │  │   logs      │ │  │
│  │  │             │  │             │  │ - knowledge_│ │  │
│  │  │             │  │             │  │   bases     │ │  │
│  │  │             │  │             │  │ - documents │ │  │
│  │  │             │  │             │  │ - langchain_│ │  │
│  │  │             │  │             │  │   pg_*      │ │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  Volume: postgres_data → /var/lib/postgresql/data          │
└─────────────────────────────────────────────────────────────┘
         ↑                   ↑                   ↑
         │                   │                   │
    ┌────┴────┐         ┌───┴────┐         ┌────┴────┐
    │  Auth   │         │  User  │         │  Admin  │
    │ Service │         │   API  │         │   API   │
    └─────────┘         └────────┘         └─────────┘
   Port 8002           Port 8001           Port 8003
```

### マイクロサービス分離原則

各データベースは、マイクロサービスアーキテクチャの「Database per Service」パターンに従い、論理的に分離されています。

**分離の利点**:
- 各サービスが独立して開発・デプロイ可能
- データスキーマ変更の影響範囲が限定的
- サービス間の疎結合を維持
- 将来的な物理分離（別PostgreSQLインスタンス化）が容易

**物理的な実装**:
- 現在は1つの PostgreSQL インスタンス内で3つのデータベースとして実装
- データベース間の物理的な外部キー制約は設定しない
- サービス間のデータ整合性はアプリケーションロジックで保証

---

## データベース構成

### 3つのデータベース

| データベース名 | 用途 | 主要テーブル | 使用サービス |
|------------|------|----------|----------|
| **authdb** | 認証情報 | users | ai-micro-api-auth |
| **apidb** | ユーザープロファイル | profiles | ai-micro-api-user |
| **admindb** | 管理機能・ドキュメント・RAG | system_logs, login_logs, system_settings, knowledge_bases, documents, langchain_pg_collection, langchain_pg_embedding | ai-micro-api-admin |

### データベース接続情報

```bash
# authdb 接続URL
postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/authdb

# apidb 接続URL
postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/apidb

# admindb 接続URL
postgresql://postgres:${POSTGRES_PASSWORD}@host.docker.internal:5432/admindb
```

### 共通拡張機能

すべてのデータベースで以下の拡張が有効化されています:

```sql
-- UUID生成機能
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ベクトル検索機能（admindbのみ）
CREATE EXTENSION IF NOT EXISTS vector;
```

---

## 技術スタック

### PostgreSQL 15

**選定理由**:
- **安定性**: エンタープライズグレードの信頼性
- **拡張性**: pgvector などの豊富な拡張エコシステム
- **トランザクション**: ACID特性による堅牢なデータ整合性
- **UUID型サポート**: マイクロサービスに適した分散ID
- **JSON/JSONB**: メタデータ管理に適した柔軟なデータ型

### pgvector 拡張

**用途**:
- RAG（Retrieval-Augmented Generation）システムの実装
- ドキュメント埋め込みベクトルの保存と検索
- nomic-embed-text モデル（768次元）との統合

**技術仕様**:
```sql
-- ベクトルカラムの定義
embedding vector(768)

-- コサイン類似度検索
SELECT * FROM langchain_pg_embedding
ORDER BY embedding <=> '[0.1, 0.2, ...]'
LIMIT 10;
```

### UUID-OSSP 拡張

**用途**:
- グローバルに一意なIDの生成
- マイクロサービス間でのID衝突回避
- セキュリティ向上（連番IDによる推測攻撃防止）

**生成例**:
```sql
-- UUID v4 生成
SELECT uuid_generate_v4();
-- => 550e8400-e29b-41d4-a716-446655440000
```

---

## コンテナ構成

### Docker Compose 設定

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/docker-compose.yml`

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

### Dockerfile

カスタムイメージに pgvector 拡張を含めるための Dockerfile を使用:

```dockerfile
FROM postgres:15

# pgvector 拡張のインストールなど
# （実際のファイル内容は ai-micro-postgres/Dockerfile を参照）
```

### 環境変数

**.env ファイル**:
```bash
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-secure-password-here
```

**セキュリティ注意**:
- `.env` ファイルは `.gitignore` に追加済み
- 本番環境では強固なパスワードを設定
- シークレット管理ツール（AWS Secrets Manager等）の使用を推奨

---

## ボリューム管理

### postgres_data ボリューム

**目的**: PostgreSQL のデータディレクトリを永続化

**マウントポイント**: `/var/lib/postgresql/data`

**特徴**:
- コンテナ削除後もデータ保持
- `docker compose down` では削除されない
- `docker compose down -v` で削除可能（注意が必要）

### init.sql マウント

**目的**: 初回起動時の自動スキーマ作成

**マウントポイント**: `/docker-entrypoint-initdb.d/init.sql`

**動作**:
1. PostgreSQL コンテナ初回起動時に自動実行
2. authdb、apidb、admindb を作成
3. 各データベースにテーブル・インデックスを作成
4. 2回目以降の起動では実行されない（データが存在するため）

### データ永続化の確認

```bash
# ボリュームの確認
docker volume ls | grep postgres

# ボリュームの詳細情報
docker volume inspect ai-micro-postgres_postgres_data

# データディレクトリの内容確認
docker exec ai-micro-postgres ls -la /var/lib/postgresql/data
```

---

## ポート構成

### ポートマッピング

| ホストポート | コンテナポート | プロトコル | 用途 |
|----------|------------|--------|------|
| 5432 | 5432 | TCP | PostgreSQL 接続 |

### 接続方法

**Docker コンテナから接続**:
```bash
# 他のコンテナから
postgresql://postgres:password@host.docker.internal:5432/authdb
```

**ホストマシンから接続**:
```bash
# psql コマンド
psql -h localhost -p 5432 -U postgres -d authdb

# Docker exec 経由（推奨）
docker exec ai-micro-postgres psql -U postgres -d authdb
```

**ポート競合の解決**:
```bash
# 既存の PostgreSQL が 5432 を使用している場合
# docker-compose.yml を編集
ports:
  - "15432:5432"  # ホスト側を別ポートに変更
```

---

## サービス統合

### Auth Service との統合

**データベース**: authdb
**サービス**: ai-micro-api-auth（Port 8002）
**接続**: FastAPI + SQLAlchemy ORM

**主要テーブル**:
- `users`: 認証情報、ロール、ログイン試行回数

**関連ドキュメント**:
- [Auth Service 概要](/01-auth-service/01-overview.md)
- [Auth Service データベース設計](/01-auth-service/03-database-design.md)
- [authdb スキーマ詳細](./04-authdb-schema.md)

### User API Service との統合

**データベース**: apidb
**サービス**: ai-micro-api-user（Port 8001）
**接続**: FastAPI + SQLAlchemy ORM

**主要テーブル**:
- `profiles`: ユーザープロファイル情報

**データ連携**:
- `profiles.user_id` は `authdb.users.id` と論理的に対応
- 物理的な外部キー制約は設定しない（マイクロサービス独立性）

**関連ドキュメント**:
- [User API Service 概要](/02-user-api/01-overview.md)
- [User API Service データベース設計](/02-user-api/03-database-design.md)
- [apidb スキーマ詳細](./05-apidb-schema.md)

### Admin API Service との統合

**データベース**: admindb
**サービス**: ai-micro-api-admin（Port 8003）
**接続**: FastAPI + SQLAlchemy ORM + LangChain PGVector

**主要テーブル**:
- `system_logs`: システムログ
- `login_logs`: ログイン履歴
- `system_settings`: システム設定
- `knowledge_bases`: ナレッジベース管理
- `documents`: ドキュメント管理（OCRメタデータ含む）
- `langchain_pg_collection`: RAG コレクション
- `langchain_pg_embedding`: ベクトル埋め込み（768次元）

**特殊機能**:
- pgvector によるベクトル類似度検索
- OCR メタデータの編集管理（JSONB）
- ドキュメント階層構造の保存

**関連ドキュメント**:
- [Admin API Service 概要](/03-admin-api/01-overview.md)
- [admindb スキーマ詳細](./06-admindb-schema.md)

---

## 起動・停止手順

### 起動

```bash
cd /Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres

# コンテナ起動
docker compose up -d

# ログ確認
docker compose logs -f postgres
```

**初回起動時の出力例**:
```
ai-micro-postgres | CREATE DATABASE
ai-micro-postgres | CREATE EXTENSION
ai-micro-postgres | CREATE TABLE
ai-micro-postgres | CREATE INDEX
ai-micro-postgres | database system is ready to accept connections
```

### 停止

```bash
# コンテナ停止（データは保持）
docker compose stop

# コンテナ削除（データは保持）
docker compose down

# コンテナ + データ削除（注意！）
docker compose down -v
```

### ヘルスチェック

```bash
# PostgreSQL が起動しているか確認
docker exec ai-micro-postgres pg_isready -U postgres

# 出力例: /var/run/postgresql:5432 - accepting connections

# データベース一覧確認
docker exec ai-micro-postgres psql -U postgres -c "\l"
```

---

## 監視とメンテナンス

### ログ確認

```bash
# リアルタイムログ
docker compose logs -f postgres

# 直近100行
docker compose logs --tail=100 postgres

# タイムスタンプ付き
docker compose logs -t postgres
```

### リソース使用状況

```bash
# コンテナのリソース使用状況
docker stats ai-micro-postgres

# データベースサイズ確認
docker exec ai-micro-postgres psql -U postgres -c "
  SELECT pg_database.datname,
         pg_size_pretty(pg_database_size(pg_database.datname)) AS size
  FROM pg_database
  ORDER BY pg_database_size(pg_database.datname) DESC;
"
```

### 接続数確認

```bash
docker exec ai-micro-postgres psql -U postgres -c "
  SELECT datname, count(*)
  FROM pg_stat_activity
  GROUP BY datname;
"
```

---

## トラブルシューティング

### コンテナが起動しない

**症状**: `docker compose up` でエラー

**確認事項**:
```bash
# ポート 5432 が使用中か確認
lsof -i :5432

# 既存の PostgreSQL プロセスを停止
sudo systemctl stop postgresql  # Linux
brew services stop postgresql   # macOS
```

### init.sql が実行されない

**症状**: テーブルが作成されない

**原因**: データボリュームが既に存在する

**解決策**:
```bash
# データボリュームを削除して再作成
docker compose down -v
docker compose up -d
```

### 接続エラー: "role does not exist"

**症状**: `FATAL: role "user" does not exist`

**解決策**:
```bash
# .env ファイルの POSTGRES_USER を確認
cat .env

# 環境変数が反映されているか確認
docker exec ai-micro-postgres env | grep POSTGRES
```

### データが消えた

**原因**: `docker compose down -v` でボリューム削除

**解決策**: バックアップからリストア（[10-backup-restore.md](./10-backup-restore.md) 参照）

---

## パフォーマンスチューニング

### 接続プーリング

各サービスは SQLAlchemy のコネクションプールを使用:

```python
# app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=20,          # 基本プールサイズ
    max_overflow=10,       # 追加接続数
    pool_pre_ping=True,    # 接続確認
    pool_recycle=3600      # 1時間でリサイクル
)
```

### PostgreSQL 設定最適化

本番環境では `postgresql.conf` のチューニングを推奨:

```conf
# 同時接続数
max_connections = 100

# 共有バッファ（システムメモリの25%が目安）
shared_buffers = 256MB

# ワークメモリ（複雑なクエリ用）
work_mem = 4MB

# 書き込みバッファ
wal_buffers = 8MB
```

---

## セキュリティ

### アクセス制御

- デフォルトでは `postgres` ユーザーのみ使用
- 本番環境では各サービス専用のロールを作成推奨

```sql
-- Auth Service 専用ロール作成例
CREATE ROLE auth_service WITH LOGIN PASSWORD 'secure-password';
GRANT CONNECT ON DATABASE authdb TO auth_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO auth_service;
```

### SSL/TLS 接続

本番環境では SSL 接続を有効化:

```bash
# postgresql.conf
ssl = on
ssl_cert_file = '/path/to/server.crt'
ssl_key_file = '/path/to/server.key'
```

---

## 関連ドキュメント

### データベース設計
- [データベース設定詳細](./02-database-configuration.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [authdb スキーマ](./04-authdb-schema.md)
- [apidb スキーマ](./05-apidb-schema.md)
- [admindb スキーマ](./06-admindb-schema.md)
- [ER図](./07-er-diagram.md)

### データ管理
- [データベース間連携](./08-cross-database-relations.md)
- [マイグレーション管理](./09-migration-management.md)
- [バックアップとリストア](./10-backup-restore.md)

### サービス統合
- [Auth Service](/01-auth-service/01-overview.md)
- [User API Service](/02-user-api/01-overview.md)
- [Admin API Service](/03-admin-api/01-overview.md)

---

**次のステップ**: [データベース設定詳細](./02-database-configuration.md) を参照して、環境変数やパフォーマンスチューニングの詳細を確認してください。