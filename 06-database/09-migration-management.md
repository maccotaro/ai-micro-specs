# データベースマイグレーション管理

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [マイグレーション概要](#マイグレーション概要)
- [init.sql による初期化](#initsql-による初期化)
- [スキーマ変更の手順](#スキーマ変更の手順)
- [バージョン管理戦略](#バージョン管理戦略)
- [Alembic 導入の検討](#alembic-導入の検討)
- [ロールバック手順](#ロールバック手順)
- [マイグレーションのテスト](#マイグレーションのテスト)

---

## マイグレーション概要

### 現在の実装

本システムは現在、シンプルな init.sql スクリプトによる初期化を採用しています。

**ファイルパス**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/db/init.sql`

**特徴**:
- PostgreSQL コンテナ初回起動時に自動実行
- 3つのデータベース（authdb、apidb、admindb）とすべてのテーブルを作成
- 拡張機能（uuid-ossp、vector）の有効化
- インデックスとデフォルトデータの作成

**制限事項**:
- 初回のみ実行（2回目以降は実行されない）
- スキーマ変更の履歴管理なし
- ロールバック機能なし
- 本番環境への段階的な適用が困難

---

## init.sql による初期化

### 実行タイミング

```bash
# 初回起動時
docker compose up -d

# PostgreSQL コンテナ起動
# └─> /docker-entrypoint-initdb.d/init.sql を自動実行
#     └─> データベースとテーブルを作成

# 2回目以降の起動
docker compose up -d

# PostgreSQL コンテナ起動
# └─> データボリュームが既に存在
#     └─> init.sql は実行されない
```

### init.sql の構造

```sql
-- ============================================
-- データベース作成
-- ============================================
CREATE DATABASE authdb;
CREATE DATABASE apidb;
CREATE DATABASE admindb;

-- ============================================
-- authdb スキーマ
-- ============================================
\c authdb;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  roles TEXT[] NOT NULL DEFAULT ARRAY['user'],
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,
  login_attempts INTEGER DEFAULT 0,
  last_login_at TIMESTAMP,
  locked_until TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ============================================
-- apidb スキーマ
-- ============================================
\c apidb;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL,
  name TEXT,
  address TEXT,
  phone TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  first_name TEXT,
  last_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);

-- ============================================
-- admindb スキーマ
-- ============================================
\c admindb;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;

-- system_logs, login_logs, system_settings, ...
-- (詳細は init.sql を参照)
```

### 初期化のリセット

**注意**: データがすべて削除されます！

```bash
# 方法1: ボリュームを削除して再作成
docker compose down -v
docker compose up -d

# 方法2: ボリュームを保持してコンテナのみ再作成
docker compose down
docker volume rm ai-micro-postgres_postgres_data
docker compose up -d
```

---

## スキーマ変更の手順

### 開発環境でのスキーマ変更

#### ケース1: 新しいカラムを追加

**シナリオ**: apidb.profiles に `birth_date` カラムを追加

**手順**:

1. **init.sql を更新**:
```sql
-- db/init.sql
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL,
  name TEXT,
  address TEXT,
  phone TEXT,
  birth_date DATE,  -- ← 追加
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  first_name TEXT,
  last_name TEXT
);
```

2. **開発環境で手動適用**:
```bash
# 既存の開発環境に手動でカラム追加
docker exec ai-micro-postgres psql -U postgres -d apidb -c \
  "ALTER TABLE profiles ADD COLUMN birth_date DATE;"
```

3. **SQLAlchemy モデルを更新**:
```python
# ai-micro-api-user/app/models/profile.py
class Profile(Base):
    __tablename__ = "profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), unique=True, nullable=False)
    name = Column(String, nullable=True)
    birth_date = Column(Date, nullable=True)  # ← 追加
    ...
```

4. **動作確認**:
```bash
# アプリケーション再起動
docker compose restart user-api

# テスト実行
pytest tests/test_profile.py
```

5. **Git にコミット**:
```bash
git add db/init.sql
git add ai-micro-api-user/app/models/profile.py
git commit -m "Add birth_date column to profiles table"
```

#### ケース2: インデックスを追加

**シナリオ**: admindb.documents の `status` にインデックスを追加

**手順**:

1. **init.sql を更新**:
```sql
-- db/init.sql
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
```

2. **既存データベースに適用**:
```bash
docker exec ai-micro-postgres psql -U postgres -d admindb -c \
  "CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);"
```

3. **パフォーマンス確認**:
```sql
-- インデックスが使用されているか確認
EXPLAIN ANALYZE SELECT * FROM documents WHERE status = 'completed';
-- Index Scan using idx_documents_status on documents ...
```

### 本番環境でのスキーマ変更

**推奨手順**:

1. **ステージング環境でテスト**:
```bash
# ステージング DB にマイグレーション適用
psql -h staging-db.example.com -U postgres -d apidb -c \
  "ALTER TABLE profiles ADD COLUMN birth_date DATE;"

# アプリケーションデプロイ
# 動作確認
# 負荷テスト
```

2. **メンテナンスウィンドウを設定**:
```bash
# システム設定でメンテナンスモード有効化
docker exec ai-micro-postgres psql -U postgres -d admindb -c \
  "UPDATE system_settings SET value = '{\"enabled\": true}' WHERE key = 'maintenance_mode';"
```

3. **本番データベースのバックアップ**:
```bash
# 全データベースをバックアップ
docker exec ai-micro-postgres pg_dumpall -U postgres > \
  backup_before_migration_$(date +%Y%m%d_%H%M%S).sql
```

4. **マイグレーション実行**:
```bash
# 本番 DB にマイグレーション適用
docker exec ai-micro-postgres psql -U postgres -d apidb -c \
  "ALTER TABLE profiles ADD COLUMN birth_date DATE;"
```

5. **アプリケーションデプロイ**:
```bash
# 新しいバージョンのアプリケーションをデプロイ
docker compose pull user-api
docker compose up -d user-api
```

6. **動作確認とメンテナンスモード解除**:
```bash
# 動作確認
curl https://api.example.com/health

# メンテナンスモード解除
docker exec ai-micro-postgres psql -U postgres -d admindb -c \
  "UPDATE system_settings SET value = '{\"enabled\": false}' WHERE key = 'maintenance_mode';"
```

---

## バージョン管理戦略

### 現在の課題

- **履歴管理なし**: どのスキーマ変更がいつ適用されたか不明
- **ロールバック困難**: 変更を戻す手順が明確でない
- **複数環境の管理**: 開発・ステージング・本番で状態が異なる可能性

### 簡易バージョン管理

**system_settings テーブルを活用**:

```sql
-- スキーマバージョンを記録
INSERT INTO admindb.system_settings (key, value)
VALUES ('schema_version', '{"version": "1.0.0", "updated_at": "2025-09-30"}');

-- バージョン確認
SELECT value FROM admindb.system_settings WHERE key = 'schema_version';
-- => {"version": "1.0.0", "updated_at": "2025-09-30"}
```

**バージョン更新時**:
```sql
-- スキーマ変更後にバージョン更新
UPDATE admindb.system_settings
SET value = '{"version": "1.1.0", "updated_at": "2025-10-15", "changes": "Added birth_date column"}'
WHERE key = 'schema_version';
```

### マイグレーションスクリプトの管理

**ディレクトリ構成例**:
```
ai-micro-postgres/
├── db/
│   ├── init.sql                    # 初期スキーマ
│   └── migrations/
│       ├── 001_add_birth_date.sql
│       ├── 002_add_document_index.sql
│       └── 003_add_ocr_metadata.sql
```

**マイグレーションスクリプト例**:
```sql
-- migrations/001_add_birth_date.sql
-- Migration: Add birth_date column to profiles
-- Version: 1.1.0
-- Date: 2025-10-15

BEGIN;

-- Add column
ALTER TABLE apidb.profiles ADD COLUMN IF NOT EXISTS birth_date DATE;

-- Update version
UPDATE admindb.system_settings
SET value = '{"version": "1.1.0", "migration": "001_add_birth_date", "date": "2025-10-15"}'
WHERE key = 'schema_version';

COMMIT;
```

**適用方法**:
```bash
# マイグレーション適用
docker exec -i ai-micro-postgres psql -U postgres < \
  db/migrations/001_add_birth_date.sql
```

---

## Alembic 導入の検討

### Alembic とは

Alembic は SQLAlchemy のマイグレーションツールで、以下の機能を提供:
- スキーマ変更の履歴管理
- 自動的なマイグレーションスクリプト生成
- アップグレード・ダウングレード機能
- 複数環境の状態管理

### 導入手順

**1. Alembic のインストール**:
```bash
cd ai-micro-api-user
poetry add alembic
```

**2. Alembic 初期化**:
```bash
alembic init alembic
```

**3. alembic.ini を設定**:
```ini
# alembic.ini
sqlalchemy.url = postgresql://postgres:password@localhost:5432/apidb
```

**4. env.py を設定**:
```python
# alembic/env.py
from app.models import Base  # SQLAlchemy Base
target_metadata = Base.metadata
```

**5. 初回マイグレーション生成**:
```bash
alembic revision --autogenerate -m "Initial migration"
```

**6. マイグレーション適用**:
```bash
alembic upgrade head
```

### Alembic のメリット

1. **履歴管理**: すべての変更が `alembic_version` テーブルに記録
2. **ロールバック**: `alembic downgrade` でバージョンを戻せる
3. **自動生成**: モデル変更から自動的にマイグレーションスクリプト生成
4. **複数環境**: 各環境のバージョンを独立管理

### Alembic のデメリット

1. **複雑性**: 小規模システムには過剰
2. **学習コスト**: チームメンバーが理解する必要あり
3. **3データベース対応**: 各データベースで個別に管理が必要

### 導入の判断基準

**Alembic を導入すべき場合**:
- チームメンバーが3人以上
- 頻繁なスキーマ変更が予想される
- 複数環境（開発・ステージング・本番）の管理が複雑
- ロールバックが必要なケースが多い

**現状のまま（init.sql + 手動マイグレーション）で十分な場合**:
- 小規模チーム（1〜2人）
- スキーマ変更が稀
- 開発環境のみ、または本番環境が1つのみ
- システムが安定している

---

## ロールバック手順

### カラム追加のロールバック

**追加したカラム**:
```sql
ALTER TABLE profiles ADD COLUMN birth_date DATE;
```

**ロールバック**:
```sql
-- カラム削除
ALTER TABLE profiles DROP COLUMN birth_date;

-- アプリケーション再起動（古いバージョンにロールバック）
docker compose down user-api
docker compose up -d user-api
```

**注意**: カラムを削除するとデータも失われます！

### インデックス追加のロールバック

**追加したインデックス**:
```sql
CREATE INDEX idx_documents_status ON documents(status);
```

**ロールバック**:
```sql
-- インデックス削除
DROP INDEX idx_documents_status;
```

**影響**: パフォーマンスが低下する可能性（データは保持）

### テーブル追加のロールバック

**追加したテーブル**:
```sql
CREATE TABLE new_feature (
  id UUID PRIMARY KEY,
  ...
);
```

**ロールバック**:
```sql
-- テーブル削除
DROP TABLE new_feature;
```

**注意**: すべてのデータが削除されます！

### バックアップからの復元

**最も安全なロールバック方法**:
```bash
# 1. 現在のデータをバックアップ（念のため）
docker exec ai-micro-postgres pg_dumpall -U postgres > current_state.sql

# 2. マイグレーション前のバックアップから復元
cat backup_before_migration_20250930.sql | \
  docker exec -i ai-micro-postgres psql -U postgres

# 3. アプリケーションを古いバージョンにロールバック
git checkout v1.0.0
docker compose up -d --build
```

---

## マイグレーションのテスト

### ローカル環境でのテスト

**1. テスト用データベースを作成**:
```bash
# テスト用コンテナ起動
docker run --name postgres-test -e POSTGRES_PASSWORD=test -d postgres:15

# init.sql 適用
cat db/init.sql | docker exec -i postgres-test psql -U postgres
```

**2. マイグレーションスクリプトを適用**:
```bash
cat db/migrations/001_add_birth_date.sql | \
  docker exec -i postgres-test psql -U postgres
```

**3. スキーマを確認**:
```bash
docker exec postgres-test psql -U postgres -d apidb -c "\d profiles"

# 出力に birth_date カラムが含まれているか確認
```

**4. テストデータで動作確認**:
```bash
docker exec postgres-test psql -U postgres -d apidb -c \
  "INSERT INTO profiles (user_id, name, birth_date) VALUES (uuid_generate_v4(), 'Test User', '1990-01-01');"

docker exec postgres-test psql -U postgres -d apidb -c \
  "SELECT * FROM profiles;"
```

**5. クリーンアップ**:
```bash
docker stop postgres-test
docker rm postgres-test
```

### CI/CD パイプラインでのテスト

**.github/workflows/migration-test.yml**:
```yaml
name: Migration Test

on:
  pull_request:
    paths:
      - 'db/**'

jobs:
  test-migration:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Apply init.sql
        run: |
          psql -h localhost -U postgres < db/init.sql

      - name: Apply migrations
        run: |
          for migration in db/migrations/*.sql; do
            psql -h localhost -U postgres < $migration
          done

      - name: Verify schema
        run: |
          psql -h localhost -U postgres -d apidb -c "\d profiles"
```

---

## ベストプラクティス

### スキーマ変更の原則

1. **後方互換性を維持**:
   - カラム追加は OK（NULL許容またはデフォルト値）
   - カラム削除は慎重に（既存コードが影響を受ける）

2. **段階的な変更**:
   - 大きな変更は複数のマイグレーションに分割
   - 各マイグレーションは独立してテスト可能

3. **ロールバック計画**:
   - すべてのマイグレーションにロールバック手順を用意
   - 本番適用前にバックアップ必須

4. **ドキュメント化**:
   - マイグレーションスクリプトにコメントを記載
   - 変更理由と影響範囲を明記

### チェックリスト

マイグレーション前:
- [ ] バックアップ取得済み
- [ ] ステージング環境でテスト済み
- [ ] ロールバック手順を準備
- [ ] メンテナンスウィンドウを確保
- [ ] チームに通知済み

マイグレーション後:
- [ ] スキーマ変更が正しく適用された
- [ ] アプリケーションが正常動作
- [ ] パフォーマンスに問題なし
- [ ] バージョン情報を更新
- [ ] ドキュメントを更新

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [データベース設定](./02-database-configuration.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [バックアップとリストア](./10-backup-restore.md)

---

**次のステップ**: [バックアップとリストア](./10-backup-restore.md) を参照して、データ保護の手順を確認してください。