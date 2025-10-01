# User API Service - データベース設計

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [データベース概要](#データベース概要)
- [テーブル定義](#テーブル定義)
- [インデックス設計](#インデックス設計)
- [制約とルール](#制約とルール)
- [データ型の選択理由](#データ型の選択理由)
- [マイグレーション](#マイグレーション)

---

## データベース概要

### 接続情報

| 項目 | 値 |
|------|------|
| データベース名 | `apidb` |
| ホスト | `host.docker.internal` |
| ポート | `5432` |
| ユーザー | `postgres` |
| 接続URL | `postgresql://postgres:password@host.docker.internal:5432/apidb` |

### 使用RDBMS

- **製品**: PostgreSQL 15
- **理由**:
  - UUID型のネイティブサポート
  - タイムゾーン対応のDateTime型
  - トランザクションの堅牢性
  - SQLAlchemy ORM との高い互換性

---

## テーブル定義

### profiles テーブル

ユーザープロファイル情報を格納するメインテーブル。

#### テーブル構造

```sql
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL,
    first_name VARCHAR,
    last_name VARCHAR,
    name VARCHAR,
    address VARCHAR,
    phone VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

#### カラム詳細

| カラム名 | データ型 | NULL | デフォルト | 説明 |
|---------|---------|------|----------|------|
| `id` | UUID | 不可 | `gen_random_uuid()` | プロファイルID（主キー） |
| `user_id` | UUID | 不可 | - | ユーザーID（Auth Serviceと連携） |
| `first_name` | VARCHAR | 可 | NULL | 名前 |
| `last_name` | VARCHAR | 可 | NULL | 姓 |
| `name` | VARCHAR | 可 | NULL | フルネーム |
| `address` | VARCHAR | 可 | NULL | 住所 |
| `phone` | VARCHAR | 可 | NULL | 電話番号 |
| `created_at` | TIMESTAMP WITH TIME ZONE | 不可 | `CURRENT_TIMESTAMP` | 作成日時 |
| `updated_at` | TIMESTAMP WITH TIME ZONE | 不可 | `CURRENT_TIMESTAMP` | 更新日時 |

#### SQLAlchemyモデル定義

```python
from sqlalchemy import Column, String, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
import uuid
from ..db.session import Base


class Profile(Base):
    __tablename__ = "profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), unique=True, nullable=False)
    first_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    name = Column(String, nullable=True)
    address = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

---

## インデックス設計

### 主キー（自動作成）

```sql
-- id カラムにPRIMARY KEY制約により自動作成
CREATE UNIQUE INDEX profiles_pkey ON profiles (id);
```

### ユニーク制約（自動インデックス作成）

```sql
-- user_id カラムにUNIQUE制約により自動作成
CREATE UNIQUE INDEX profiles_user_id_key ON profiles (user_id);
```

### インデックスの役割

| インデックス名 | カラム | 型 | 用途 |
|------------|-------|----|----|
| `profiles_pkey` | `id` | PRIMARY KEY | プロファイルIDによる一意検索 |
| `profiles_user_id_key` | `user_id` | UNIQUE | ユーザーIDによる高速検索・重複防止 |

### パフォーマンス考慮事項

- **user_id インデックス**:
  - 最も頻繁に使用されるクエリ: `SELECT * FROM profiles WHERE user_id = ?`
  - UNIQUE制約により B-Tree インデックスが自動作成
  - O(log n) の検索性能

- **created_at / updated_at**:
  - 現時点ではインデックス不要（範囲検索が少ない）
  - 将来的に管理機能で「最近更新されたプロファイル」検索が必要な場合は追加検討

---

## 制約とルール

### 主キー制約

```sql
PRIMARY KEY (id)
```

- プロファイルの一意識別
- UUID v4 によりグローバルに一意
- クラスタリングキーとして使用

### ユニーク制約

```sql
UNIQUE (user_id)
```

- 1ユーザーにつき1プロファイル
- Auth Service の `users.id` と対応
- 重複登録防止

### NOT NULL 制約

```sql
user_id UUID NOT NULL
created_at TIMESTAMP WITH TIME ZONE NOT NULL
updated_at TIMESTAMP WITH TIME ZONE NOT NULL
```

- `user_id`: プロファイルは必ずユーザーに紐付く
- `created_at`, `updated_at`: 監査証跡として必須

### CHECK 制約

現時点では未設定。将来的な拡張候補:

```sql
-- 電話番号フォーマット検証（将来の拡張）
ALTER TABLE profiles ADD CONSTRAINT phone_format_check
  CHECK (phone ~ '^\d{2,4}-\d{2,4}-\d{4}$' OR phone IS NULL);

-- 名前の長さ制限（将来の拡張）
ALTER TABLE profiles ADD CONSTRAINT name_length_check
  CHECK (char_length(name) <= 100);
```

---

## データ型の選択理由

### UUID型

**使用箇所**: `id`, `user_id`

**選択理由**:
- グローバルに一意な識別子
- 分散システムでの衝突リスク最小化
- Auth Service との連携で `user_id` を直接使用可能
- セキュリティ: 連番でないため推測困難

**代替案との比較**:
- SERIAL/BIGSERIAL: 順序性があるが分散環境で衝突リスク、推測可能
- ULID: 時系列ソート可能だが PostgreSQL ネイティブサポートなし

### VARCHAR型（可変長文字列）

**使用箇所**: `first_name`, `last_name`, `name`, `address`, `phone`

**選択理由**:
- 日本語対応（UTF-8）
- 可変長でストレージ効率が良い
- 長さ制限なし（将来の柔軟性）

**代替案との比較**:
- CHAR: 固定長で無駄なスペース
- TEXT: VARCHARと内部的に同じだがセマンティクスが不明確

### TIMESTAMP WITH TIME ZONE

**使用箇所**: `created_at`, `updated_at`

**選択理由**:
- タイムゾーン情報を保持
- グローバル展開時の時刻管理が容易
- PostgreSQL の推奨型

**動作**:
```sql
-- UTC で保存、クライアントのタイムゾーンで表示
INSERT INTO profiles (user_id, created_at)
VALUES ('uuid-here', '2025-09-30 10:00:00+09:00');

-- 内部的に UTC に変換されて保存
SELECT created_at FROM profiles;
-- => 2025-09-30 01:00:00+00:00
```

---

## マイグレーション

### 初期テーブル作成

User API Service は SQLAlchemy の `create_all()` を使用して自動作成します。

```python
# app/main.py の lifespan イベント
@asynccontextmanager
async def lifespan(app: FastAPI):
    await cache_manager.connect()
    Profile.metadata.create_all(bind=engine)  # ← ここでテーブル作成
    logger.info("Application startup complete")
    yield
    await cache_manager.disconnect()
```

### テーブル存在確認

```bash
# PostgreSQLコンテナに接続
docker exec postgres psql -U postgres -d apidb

# テーブル一覧表示
\dt

# profiles テーブル構造確認
\d profiles

# サンプルクエリ
SELECT * FROM profiles LIMIT 10;
```

### スキーマ変更手順

新しいカラムを追加する場合:

```sql
-- 1. カラム追加（本番環境では NOT NULL を後から設定）
ALTER TABLE profiles ADD COLUMN profile_image_url VARCHAR;

-- 2. 既存データにデフォルト値設定（必要に応じて）
UPDATE profiles SET profile_image_url = 'https://example.com/default.png'
WHERE profile_image_url IS NULL;

-- 3. NOT NULL 制約追加（必要に応じて）
ALTER TABLE profiles ALTER COLUMN profile_image_url SET NOT NULL;
```

**注意**: 本番環境では Alembic 等のマイグレーションツール使用を推奨。

---

## データ整合性保証

### Auth Service との連携

`profiles.user_id` は `authdb.users.id` と論理的に対応しますが、物理的な外部キー制約は設定していません。

**理由**:
- マイクロサービスアーキテクチャではデータベース分離
- 疎結合により各サービスが独立して動作可能
- Auth Service 障害時も User API は既存データに対して動作可能

**整合性確保方法**:
1. JWT トークンの `sub` クレームから `user_id` 取得
2. プロファイル作成時に Auth Service で認証済みユーザーのみ許可
3. 存在しないユーザーのプロファイルは作成不可（JWT検証で防止）

### updated_at の自動更新

```python
# SQLAlchemy の onupdate 引数により自動更新
updated_at = Column(
    DateTime(timezone=True),
    server_default=func.now(),
    onupdate=func.now()  # ← レコード更新時に自動的に現在時刻を設定
)
```

**動作**:
```python
# プロファイル更新
profile.phone = "090-9999-9999"
db.commit()
# → updated_at が自動的に現在時刻に更新される
```

---

## バックアップとリストア

### バックアップ

```bash
# profiles テーブルのみバックアップ
docker exec postgres pg_dump -U postgres -d apidb -t profiles > profiles_backup.sql

# apidb 全体をバックアップ
docker exec postgres pg_dump -U postgres -d apidb > apidb_backup.sql
```

### リストア

```bash
# バックアップからリストア
cat profiles_backup.sql | docker exec -i postgres psql -U postgres -d apidb

# または
docker exec -i postgres psql -U postgres -d apidb < apidb_backup.sql
```

---

## トラブルシューティング

### テーブルが作成されない

```bash
# 原因: SQLAlchemy のメタデータが読み込まれていない
# 解決策: app/main.py で Profile モデルをインポート

from .models import Profile  # ← これがないとテーブル作成されない
```

### user_id の重複エラー

```sql
-- エラー: duplicate key value violates unique constraint "profiles_user_id_key"
-- 原因: 同じユーザーで複数回プロファイル作成を試行

-- 確認
SELECT * FROM profiles WHERE user_id = 'uuid-here';

-- 解決: POST /profile は既存プロファイルがあれば更新する（Upsert）
```

### タイムスタンプがUTCで保存されない

```sql
-- 確認
SHOW timezone;  -- => UTC であることを確認

-- PostgreSQL のタイムゾーン設定
ALTER DATABASE apidb SET timezone TO 'UTC';
```

---

## パフォーマンスチューニング

### EXPLAIN ANALYZE

```sql
-- user_id 検索のクエリプラン確認
EXPLAIN ANALYZE
SELECT * FROM profiles WHERE user_id = 'uuid-here';

-- 期待される結果:
-- Index Scan using profiles_user_id_key on profiles (cost=0.15..8.17 rows=1 width=...)
-- Planning Time: 0.123 ms
-- Execution Time: 0.456 ms
```

### 接続プーリング

SQLAlchemy のコネクションプール設定:

```python
# app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=20,          # プールサイズ
    max_overflow=10,       # 最大オーバーフロー
    pool_pre_ping=True,    # 接続の事前確認
    echo=False             # SQLログ出力（開発時のみTrue）
)
```

---

## セキュリティ考慮事項

### SQL インジェクション対策

SQLAlchemy ORM を使用することで自動的にパラメータバインディングが適用されます。

```python
# 安全（SQLAlchemy ORM）
profile = db.query(Profile).filter(Profile.user_id == user_id).first()

# 危険（生SQLは使用しない）
db.execute(f"SELECT * FROM profiles WHERE user_id = '{user_id}'")  # NG
```

### 機密情報の非保存

- パスワード: Auth Service で管理
- クレジットカード情報: User API では管理しない
- 個人情報: 最小限の項目のみ保存（名前、住所、電話番号）

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [API仕様書](./02-api-specification.md)
- [データ整合性](./04-data-consistency.md)
- [データベースインフラ](/06-database/01-overview.md)
- [apidb スキーマ設計](/06-database/05-apidb-schema.md)