# PostgreSQL スキーマ設計 - 全体概要

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [設計思想](#設計思想)
- [3データベースアーキテクチャ](#3データベースアーキテクチャ)
- [マイクロサービス分離の理由](#マイクロサービス分離の理由)
- [共通設計パターン](#共通設計パターン)
- [UUID使用戦略](#uuid使用戦略)
- [タイムスタンプ管理](#タイムスタンプ管理)
- [データ型標準化](#データ型標準化)
- [インデックス戦略](#インデックス戦略)

---

## 設計思想

### Database per Service パターン

本システムは、マイクロサービスアーキテクチャの基本原則である「Database per Service」パターンを採用しています。

**基本原則**:
1. 各マイクロサービスは専用のデータベースを持つ
2. サービス間でデータベースを直接共有しない
3. データ連携はAPIまたはイベント経由で行う
4. 各サービスが独立してスケール・デプロイ可能

**本システムの実装**:
```
┌─────────────────────────────────────────────────────────┐
│  Single PostgreSQL Instance                             │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   authdb     │  │    apidb     │  │   admindb    │ │
│  │              │  │              │  │              │ │
│  │ (Auth       │  │ (User API   │  │ (Admin API  │ │
│  │  Service)   │  │  Service)   │  │  Service)   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 論理分離 vs 物理分離

**現在の実装**: 論理分離（1つのPostgreSQLインスタンス内で3つのデータベース）

**メリット**:
- インフラ管理の簡素化
- リソース効率（共有メモリ、接続プール）
- バックアップ・リストアの一元管理
- 開発環境での容易なセットアップ

**将来の拡張性**: 物理分離（各データベースを別インスタンスに）

**移行パス**:
1. スキーマは既に完全分離されている
2. 物理的な外部キー制約なし
3. サービスの接続文字列変更のみで移行可能
4. 負荷に応じて段階的に分離可能

---

## 3データベースアーキテクチャ

### authdb - 認証データベース

**責務**: ユーザー認証とアクセス制御

**主要エンティティ**:
```
users
├─ id (UUID, PK)
├─ email (TEXT, UNIQUE)
├─ password_hash (TEXT)
├─ roles (TEXT[])
├─ is_active (BOOLEAN)
├─ login_attempts (INTEGER)
├─ last_login_at (TIMESTAMP)
├─ locked_until (TIMESTAMP)
├─ created_at (TIMESTAMP)
└─ updated_at (TIMESTAMP)
```

**使用サービス**: ai-micro-api-auth (Port 8002)

**データ特性**:
- 読み取り頻度: 高（全リクエストで認証）
- 書き込み頻度: 中（ログイン、パスワード変更）
- データ量: 小〜中（ユーザー数に比例）
- 機密性: 最高（パスワードハッシュ）

**詳細**: [authdb スキーマ詳細](./04-authdb-schema.md)

### apidb - ユーザープロファイルデータベース

**責務**: ユーザーの個人情報とプロファイル管理

**主要エンティティ**:
```
profiles
├─ id (UUID, PK)
├─ user_id (UUID, UNIQUE) → authdb.users.id (論理FK)
├─ first_name (TEXT)
├─ last_name (TEXT)
├─ name (TEXT)
├─ address (TEXT)
├─ phone (TEXT)
├─ created_at (TIMESTAMP)
└─ updated_at (TIMESTAMP)
```

**使用サービス**: ai-micro-api-user (Port 8001)

**データ特性**:
- 読み取り頻度: 高（プロファイル表示）
- 書き込み頻度: 低（プロファイル更新は稀）
- データ量: 中（ユーザー数に比例）
- 機密性: 高（個人情報）

**詳細**: [apidb スキーマ詳細](./05-apidb-schema.md)

### admindb - 管理・ドキュメント・RAGデータベース

**責務**: システム管理、ドキュメント処理、ベクトル検索（RAG）

**主要エンティティ**:
```
system_logs
├─ id (UUID, PK)
├─ service_name (VARCHAR)
├─ level (VARCHAR)
├─ message (TEXT)
├─ log_metadata (JSON)
└─ created_at (TIMESTAMP)

login_logs
├─ id (UUID, PK)
├─ user_id (UUID) → authdb.users.id (論理FK)
├─ ip_address (VARCHAR)
├─ success (BOOLEAN)
└─ created_at (TIMESTAMP)

system_settings
├─ id (UUID, PK)
├─ key (VARCHAR, UNIQUE)
├─ value (JSON)
├─ created_at (TIMESTAMP)
└─ updated_at (TIMESTAMP)

knowledge_bases
├─ id (UUID, PK)
├─ name (VARCHAR)
├─ description (TEXT)
├─ user_id (UUID) → authdb.users.id (論理FK)
├─ document_count (INTEGER)
├─ storage_size (BIGINT)
└─ ... (詳細は別ドキュメント)

documents
├─ id (UUID, PK)
├─ knowledge_base_id (UUID, FK → knowledge_bases)
├─ filename (VARCHAR)
├─ file_path (VARCHAR)
├─ status (VARCHAR)
├─ original_metadata (JSONB)  ← OCR元データ
├─ edited_metadata (JSONB)    ← 編集後データ
└─ ... (詳細は別ドキュメント)

langchain_pg_collection
├─ uuid (UUID, PK)
├─ name (VARCHAR, UNIQUE)
├─ cmetadata (JSONB)
└─ ...

langchain_pg_embedding
├─ uuid (UUID, PK)
├─ collection_id (UUID, FK)
├─ embedding (VECTOR(768))    ← pgvector
├─ document (TEXT)
├─ document_id (UUID, FK → documents)
└─ ...
```

**使用サービス**: ai-micro-api-admin (Port 8003)

**データ特性**:
- 読み取り頻度: 高（ログ閲覧、RAG検索）
- 書き込み頻度: 高（ログ記録、ドキュメントアップロード）
- データ量: 大（ログ、ドキュメント、ベクトル）
- 機密性: 中〜高（ドキュメント内容による）

**特殊機能**:
- pgvector による768次元ベクトル検索
- JSONB によるOCRメタデータ管理
- 物理的な外部キー制約あり（documents ← langchain_pg_embedding）

**詳細**: [admindb スキーマ詳細](./06-admindb-schema.md)

---

## マイクロサービス分離の理由

### データベース分離のメリット

#### 1. 独立したスケーリング

各サービスの負荷特性に応じて個別にスケール可能:

```
authdb (認証)
└─ 読み取り: 超高頻度 → リードレプリカ追加
└─ 書き込み: 中頻度

apidb (プロファイル)
└─ 読み取り: 高頻度 → Redisキャッシュ併用
└─ 書き込み: 低頻度

admindb (管理・RAG)
└─ 読み取り: 高頻度（ベクトル検索重い） → 専用ハードウェア
└─ 書き込み: 高頻度（ログ記録）
```

#### 2. 障害の影響範囲限定

```
[シナリオ] admindb のベクトル検索で負荷急増

authdb への影響: なし → ログインは正常動作
apidb への影響: なし → プロファイル取得は正常動作
admindb への影響: あり → 管理機能のみ遅延
```

#### 3. 独立したデプロイとマイグレーション

```bash
# User API のスキーマ変更
# → apidb のみマイグレーション
# → Auth Service、Admin API は無影響

docker exec ai-micro-postgres psql -U postgres -d apidb -c \
  "ALTER TABLE profiles ADD COLUMN birth_date DATE;"
```

#### 4. セキュリティ境界の明確化

```
authdb: 最高セキュリティ（パスワードハッシュ）
└─ auth_service ロールのみアクセス許可

apidb: 高セキュリティ（個人情報）
└─ user_api_service ロールのみアクセス許可

admindb: 中〜高セキュリティ（ドキュメント）
└─ admin_api_service ロールのみアクセス許可
```

### データベース統合しない理由

**統合した場合の問題点**:

1. **スキーマ変更のリスク**
   - 1つのテーブル変更が全サービスに影響
   - マイグレーション時の調整コストが高い

2. **権限管理の複雑化**
   - 1つのデータベース内で細かい権限制御が必要
   - ロールとテーブルの組み合わせが複雑に

3. **スケーリングの制約**
   - 全テーブルが同じリソースを共有
   - 特定のテーブル（例: ログ）が肥大化すると全体に影響

4. **将来の分離コスト**
   - 後から分離する場合、外部キー制約の削除が必要
   - データ移行とアプリケーション修正のコストが高い

---

## 共通設計パターン

### 主キー設計

**すべてのテーブルで UUID 型の主キーを使用**:

```sql
-- 共通パターン
id UUID PRIMARY KEY DEFAULT uuid_generate_v4()
```

**理由**:
- グローバルに一意（分散システムで衝突なし）
- セキュリティ（連番でないため推測困難）
- マイクロサービス間での ID 参照が容易
- データベース分離しても ID 衝突なし

### タイムスタンプカラム

**すべてのテーブルに作成日時・更新日時を含める**:

```sql
-- 共通パターン
created_at TIMESTAMP NOT NULL DEFAULT NOW(),
updated_at TIMESTAMP NOT NULL DEFAULT NOW()
```

**理由**:
- 監査証跡（いつ作成・更新されたか）
- デバッグ・トラブルシューティングに有用
- データ分析（時系列分析）に必須

**ベストプラクティス**:
```sql
-- TIMESTAMP WITH TIME ZONE の使用を推奨（将来のグローバル展開）
created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
```

### NULL許容の判断基準

**NOT NULL 制約を設定する項目**:
1. 主キー（必須）
2. 外部キー（論理的に必須な場合）
3. ビジネスロジックで必須の項目
4. タイムスタンプ（created_at、updated_at）

**NULL を許容する項目**:
1. オプション項目（name、address、phone など）
2. 後から追加されるカラム（既存データと互換性）
3. 条件付きで必要な項目

**例**:
```sql
-- users テーブル
email TEXT NOT NULL          -- ログインに必須
password_hash TEXT NOT NULL  -- 認証に必須
roles TEXT[] NOT NULL        -- デフォルト値あり
last_login_at TIMESTAMP      -- NULL許容（初回ログイン前）

-- profiles テーブル
user_id UUID NOT NULL        -- ユーザーとの紐付け必須
name TEXT                    -- オプション（NULL許容）
address TEXT                 -- オプション（NULL許容）
```

---

## UUID使用戦略

### UUID v4 の採用

**生成方法**:
```sql
-- PostgreSQL 拡張機能使用
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- UUID 生成
SELECT uuid_generate_v4();
-- => 550e8400-e29b-41d4-a716-446655440000
```

### UUID の利点

#### 1. グローバル一意性

```
authdb.users.id:     123e4567-e89b-12d3-a456-426614174000
apidb.profiles.user_id: 123e4567-e89b-12d3-a456-426614174000
                      ↑ 同じUUIDで異なるデータベース間の連携
```

#### 2. セキュリティ

```
連番ID（推測可能）:
https://api.example.com/users/1
https://api.example.com/users/2    ← 簡単に推測可能
https://api.example.com/users/3

UUID（推測不可）:
https://api.example.com/users/123e4567-e89b-12d3-a456-426614174000
https://api.example.com/users/???  ← 推測不可能
```

#### 3. 分散システムでの衝突回避

```
[シナリオ] 複数のAPIサーバーが同時にユーザー登録

SERIAL ID:
Server A → ID: 1 ┐
Server B → ID: 1 ┘→ 衝突！

UUID:
Server A → ID: 123e4567-...
Server B → ID: 789abcde-...  → 衝突なし
```

### UUID のデメリットと対策

#### デメリット1: サイズが大きい（16バイト vs 4バイト）

**対策**: PostgreSQL の UUID 型はインデックスで最適化されている

```sql
-- サイズ確認
SELECT pg_column_size('550e8400-e29b-41d4-a716-446655440000'::uuid);
-- => 16 bytes

SELECT pg_column_size(1234567890::integer);
-- => 4 bytes
```

**影響**:
- 小〜中規模システムでは無視できる
- 大規模（数億レコード）では考慮が必要

#### デメリット2: インデックスの断片化

**原因**: UUID v4 はランダムなため、挿入順序がバラバラ

**対策**: 定期的な VACUUM と REINDEX

```sql
-- 定期メンテナンス
VACUUM ANALYZE users;
REINDEX TABLE users;
```

**代替案**: ULID（時系列ソート可能なUUID代替）
- 現時点では未採用（PostgreSQL ネイティブサポートなし）
- 将来的な検討課題

---

## タイムスタンプ管理

### TIMESTAMP WITH TIME ZONE の使用

**すべてのタイムスタンプカラムで使用**:

```sql
created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
```

**理由**:
- グローバル展開への対応
- UTC で統一保存、表示時にクライアントのタイムゾーンに変換
- 夏時間（DST）問題の回避

### 動作例

```sql
-- 挿入時（日本時間）
INSERT INTO users (email, password_hash, created_at)
VALUES ('user@example.com', 'hash', '2025-09-30 10:00:00+09:00');

-- 内部保存（UTC に変換）
-- created_at = '2025-09-30 01:00:00+00:00'

-- 取得時（アプリケーションのタイムゾーンで表示）
SELECT created_at FROM users;
-- => 2025-09-30 10:00:00+09:00 (日本時間)
-- => 2025-09-30 01:00:00+00:00 (UTC)
```

### updated_at の自動更新

**SQLAlchemy ORM での実装**:

```python
from sqlalchemy import Column, DateTime, func

class BaseModel:
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now()  # ← 更新時に自動更新
    )
```

**PostgreSQL トリガーでの実装**（代替案）:

```sql
-- 更新関数作成
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- トリガー適用
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

---

## データ型標準化

### 文字列型

| 用途 | データ型 | 理由 |
|-----|---------|------|
| メールアドレス | TEXT | 可変長、長さ制限なし |
| 名前 | TEXT / VARCHAR | 多言語対応 |
| パスワードハッシュ | TEXT | ハッシュアルゴリズムにより長さ変動 |
| 住所 | TEXT | 日本語住所は長くなる可能性 |
| ファイルパス | VARCHAR | 一般的に255文字以内 |

**TEXT vs VARCHAR の選択基準**:
- TEXT: 長さ制限が不明確な項目
- VARCHAR: 一般的な最大長がある項目（ファイル名、IPアドレスなど）

### 数値型

| 用途 | データ型 | 理由 |
|-----|---------|------|
| ID | UUID | グローバル一意性 |
| カウンター | INTEGER | -2億〜+2億で十分 |
| ファイルサイズ | BIGINT | 大容量ファイル対応 |
| ログイン試行回数 | INTEGER | 小さい数値 |

### 真偽値型

```sql
is_active BOOLEAN DEFAULT true
success BOOLEAN NOT NULL
is_public BOOLEAN DEFAULT false
```

**デフォルト値の設定ルール**:
- セキュリティ関連: デフォルトで安全側（is_active: false、is_public: false）
- 利便性重視: デフォルトで有効（is_active: true）

### JSON型

| データ型 | 用途 | 特徴 |
|---------|------|------|
| JSON | シンプルな構造 | テキスト保存、インデックス不可 |
| JSONB | 複雑な構造、検索必要 | バイナリ保存、インデックス可 |

**本システムでの使用**:

```sql
-- JSON（system_logs、system_settings）
log_metadata JSON

-- JSONB（documents - OCRメタデータ）
original_metadata JSONB
edited_metadata JSONB
```

**理由**:
- OCRメタデータは階層構造が深い → JSONB でインデックス作成可能
- ログメタデータはシンプル → JSON で十分

### 配列型

```sql
-- TEXT 配列（roles）
roles TEXT[] NOT NULL DEFAULT ARRAY['user']

-- TEXT 配列（tags）
tags TEXT[] DEFAULT '{}'
```

**使用場面**:
- 少数の値のリスト（ロール: user, admin, superadmin）
- タグ（検索用キーワード）

**インデックス**:
```sql
-- GIN インデックスで配列検索を高速化
CREATE INDEX idx_knowledge_bases_tags ON knowledge_bases USING gin(tags);
CREATE INDEX idx_documents_tags ON documents USING gin(tags);
```

### ベクトル型（pgvector）

```sql
-- embeddinggemma の768次元埋め込み
embedding vector(768)
```

**コサイン類似度検索**:
```sql
SELECT document, 1 - (embedding <=> query_embedding) AS similarity
FROM langchain_pg_embedding
ORDER BY embedding <=> query_embedding
LIMIT 10;
```

---

## インデックス戦略

### 基本方針

1. **主キー**: 自動的に B-Tree インデックス作成
2. **外部キー**: 参照先テーブルとの結合で使用 → インデックス必須
3. **UNIQUE制約**: 自動的に B-Tree インデックス作成
4. **頻繁に検索されるカラム**: 明示的にインデックス作成

### インデックスタイプ

| タイプ | 用途 | 例 |
|-------|------|-----|
| B-Tree | 等価検索、範囲検索 | email, user_id |
| GIN | 配列、JSONB、全文検索 | tags, metadata |
| GiST | 地理情報、範囲型 | （本システムでは未使用） |

### authdb のインデックス

```sql
-- 主キー（自動）
CREATE UNIQUE INDEX users_pkey ON users (id);

-- メールアドレス検索（ログイン時）
CREATE INDEX idx_users_email ON users(email);
```

### apidb のインデックス

```sql
-- 主キー（自動）
CREATE UNIQUE INDEX profiles_pkey ON profiles (id);

-- user_id 検索（プロファイル取得時）
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
```

### admindb のインデックス

```sql
-- system_logs
CREATE INDEX idx_system_logs_service ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(level);
CREATE INDEX idx_system_logs_created_at ON system_logs(created_at);

-- documents（複数インデックス）
CREATE INDEX idx_documents_kb_id ON documents(knowledge_base_id);
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_tags ON documents USING gin(tags);

-- langchain_pg_embedding（ベクトル検索用の準備）
-- pgvector は将来的に IVFFlat や HNSW インデックス対応
```

### インデックスのメンテナンス

```sql
-- インデックス使用状況の確認
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 未使用インデックスの検出
SELECT
    schemaname,
    tablename,
    indexname
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%_pkey';

-- インデックスの再構築
REINDEX INDEX idx_users_email;
REINDEX TABLE users;
```

---

## データ整合性保証

### データベース内の整合性

**物理的な外部キー制約は限定的に使用**:

```sql
-- admindb 内のみ物理FK使用
documents.knowledge_base_id → knowledge_bases.id (ON DELETE CASCADE)
langchain_pg_embedding.collection_id → langchain_pg_collection.uuid (ON DELETE CASCADE)
langchain_pg_embedding.document_id → documents.id (ON DELETE CASCADE)
```

**理由**:
- 同じデータベース内の強い結合
- ナレッジベース削除時にドキュメントも削除（カスケード）
- ドキュメント削除時にベクトル埋め込みも削除（カスケード）

### データベース間の整合性

**論理的な外部キー（物理制約なし）**:

```
authdb.users.id ←(論理)← apidb.profiles.user_id
authdb.users.id ←(論理)← admindb.login_logs.user_id
authdb.users.id ←(論理)← admindb.knowledge_bases.user_id
```

**整合性の保証方法**:
1. JWT トークンの `sub` クレームから user_id 取得
2. Auth Service で認証済みユーザーのみ他サービスにアクセス可能
3. 存在しない user_id での登録はアプリケーションレベルで防止

**詳細**: [データベース間連携](./08-cross-database-relations.md)

---

## スキーマ進化戦略

### バージョン管理

現在は init.sql による初回作成のみ。将来的には Alembic 等のマイグレーションツール導入を検討。

### 後方互換性の維持

**原則**:
1. カラム追加は互換性あり（NULL許容またはデフォルト値）
2. カラム削除は互換性なし（慎重に）
3. カラム名変更は互換性なし（ビュー経由の移行期間設定）

**例**:
```sql
-- 安全なカラム追加
ALTER TABLE profiles ADD COLUMN birth_date DATE;

-- 安全（デフォルト値あり）
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT false;

-- 危険（既存コードがエラー）
ALTER TABLE profiles DROP COLUMN name;
```

---

## 関連ドキュメント

### 個別データベーススキーマ
- [authdb スキーマ詳細](./04-authdb-schema.md)
- [apidb スキーマ詳細](./05-apidb-schema.md)
- [admindb スキーマ詳細](./06-admindb-schema.md)

### データベース管理
- [データベース概要](./01-overview.md)
- [データベース設定](./02-database-configuration.md)
- [ER図](./07-er-diagram.md)
- [データベース間連携](./08-cross-database-relations.md)
- [マイグレーション管理](./09-migration-management.md)

### サービス統合
- [Auth Service データベース設計](/01-auth-service/03-database-design.md)
- [User API データベース設計](/02-user-api/03-database-design.md)

---

**次のステップ**: 各データベースの詳細スキーマを確認してください:
- [authdb スキーマ詳細](./04-authdb-schema.md)
- [apidb スキーマ詳細](./05-apidb-schema.md)
- [admindb スキーマ詳細](./06-admindb-schema.md)