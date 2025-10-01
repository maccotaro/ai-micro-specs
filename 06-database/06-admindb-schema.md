# admindb - 管理・ドキュメント・RAGデータベーススキーマ詳細

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [データベース概要](#データベース概要)
- [テーブル一覧](#テーブル一覧)
- [system_logsテーブル](#system_logsテーブル)
- [login_logsテーブル](#login_logsテーブル)
- [system_settingsテーブル](#system_settingsテーブル)
- [knowledge_basesテーブル](#knowledge_basesテーブル)
- [documentsテーブル](#documentsテーブル)
- [langchain_pg_collectionテーブル](#langchain_pg_collectionテーブル)
- [langchain_pg_embeddingテーブル](#langchain_pg_embeddingテーブル)
- [インデックス設計](#インデックス設計)
- [pgvector による RAG 機能](#pgvector-による-rag-機能)
- [OCR メタデータ管理](#ocr-メタデータ管理)

---

## データベース概要

### 基本情報

| 項目 | 値 |
|-----|-----|
| データベース名 | `admindb` |
| 使用サービス | ai-micro-api-admin (Port 8003) |
| 責務 | システム管理、ドキュメント処理、ベクトル検索（RAG） |
| 接続URL | `postgresql://postgres:password@host.docker.internal:5432/admindb` |

### 拡張機能

```sql
-- UUID生成機能
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ベクトル検索機能（pgvector）
CREATE EXTENSION IF NOT EXISTS vector;
```

---

## テーブル一覧

| テーブル名 | 説明 | 主要用途 |
|---------|------|---------|
| `system_logs` | システムログ | サービスログ記録 |
| `login_logs` | ログイン履歴 | 監査証跡 |
| `system_settings` | システム設定 | 動的設定管理 |
| `knowledge_bases` | ナレッジベース | ドキュメント管理の親 |
| `documents` | ドキュメント | ファイル管理・OCRメタデータ |
| `langchain_pg_collection` | RAGコレクション | ベクトル検索のコレクション管理 |
| `langchain_pg_embedding` | ベクトル埋め込み | 768次元ベクトルとドキュメントチャンク |

---

## system_logsテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS system_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_name VARCHAR NOT NULL,
  level VARCHAR NOT NULL,
  message TEXT NOT NULL,
  log_metadata JSON,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_logs_service ON system_logs(service_name);
CREATE INDEX IF NOT EXISTS idx_system_logs_level ON system_logs(level);
CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON system_logs(created_at);
```

### カラム詳細

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `id` | UUID | PK | ログID |
| `service_name` | VARCHAR | NOT NULL | サービス名（auth, user-api, admin-api） |
| `level` | VARCHAR | NOT NULL | ログレベル（INFO, WARNING, ERROR, CRITICAL） |
| `message` | TEXT | NOT NULL | ログメッセージ |
| `log_metadata` | JSON | NULL許容 | 追加メタデータ（スタックトレース等） |
| `created_at` | TIMESTAMP | NOT NULL | ログ記録日時 |

### 使用例

```python
# ログ記録
log_entry = SystemLog(
    service_name="admin-api",
    level="ERROR",
    message="Document processing failed",
    log_metadata={"document_id": str(doc_id), "error": str(e)}
)
db.add(log_entry)
db.commit()
```

### ログ検索クエリ

```sql
-- エラーログのみ抽出
SELECT service_name, message, created_at
FROM system_logs
WHERE level = 'ERROR'
ORDER BY created_at DESC
LIMIT 100;

-- 特定サービスの直近ログ
SELECT level, message, created_at
FROM system_logs
WHERE service_name = 'admin-api'
  AND created_at >= NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC;
```

---

## login_logsテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS login_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  ip_address VARCHAR,
  success BOOLEAN NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_logs_user_id ON login_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_login_logs_created_at ON login_logs(created_at);
```

### カラム詳細

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `id` | UUID | PK | ログID |
| `user_id` | UUID | NOT NULL | ユーザーID（authdb.users.id への論理FK） |
| `ip_address` | VARCHAR | NULL許容 | 接続元IPアドレス |
| `success` | BOOLEAN | NOT NULL | ログイン成功/失敗 |
| `created_at` | TIMESTAMP | NOT NULL | ログイン試行日時 |

### 使用例

```python
# ログイン成功ログ
login_log = LoginLog(
    user_id=user.id,
    ip_address=request.client.host,
    success=True
)
db.add(login_log)
db.commit()
```

### 監査クエリ

```sql
-- 特定ユーザーのログイン履歴
SELECT ip_address, success, created_at
FROM login_logs
WHERE user_id = 'user-uuid'
ORDER BY created_at DESC
LIMIT 50;

-- 失敗ログインの検出（ブルートフォース攻撃の兆候）
SELECT ip_address, count(*) AS failed_attempts
FROM login_logs
WHERE success = false
  AND created_at >= NOW() - INTERVAL '1 hour'
GROUP BY ip_address
HAVING count(*) >= 10
ORDER BY failed_attempts DESC;
```

---

## system_settingsテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS system_settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  key VARCHAR UNIQUE NOT NULL,
  value JSON NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_settings_key ON system_settings(key);
```

### カラム詳細

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `id` | UUID | PK | 設定ID |
| `key` | VARCHAR | UNIQUE, NOT NULL | 設定キー |
| `value` | JSON | NOT NULL | 設定値（JSON形式） |
| `created_at` | TIMESTAMP | NOT NULL | 作成日時 |
| `updated_at` | TIMESTAMP | NOT NULL | 更新日時 |

### 使用例

```sql
-- メンテナンスモード設定
INSERT INTO system_settings (key, value)
VALUES ('maintenance_mode', '{"enabled": false, "message": ""}');

-- 設定取得
SELECT value FROM system_settings WHERE key = 'maintenance_mode';
-- => {"enabled": false, "message": ""}

-- 設定更新
UPDATE system_settings
SET value = '{"enabled": true, "message": "System maintenance in progress"}'
WHERE key = 'maintenance_mode';
```

---

## knowledge_basesテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS knowledge_bases (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR NOT NULL,
  description TEXT,
  permissions JSON NOT NULL DEFAULT '[]',
  prompt TEXT,
  user_id uuid NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'active',
  is_public BOOLEAN NOT NULL DEFAULT false,
  document_count INTEGER NOT NULL DEFAULT 0,
  storage_size BIGINT NOT NULL DEFAULT 0,
  last_accessed_at TIMESTAMP,
  processing_settings JSON DEFAULT '{}',
  search_settings JSON DEFAULT '{}',
  tags TEXT[] DEFAULT '{}',
  category VARCHAR,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_bases_user_id ON knowledge_bases(user_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_bases_status ON knowledge_bases(status);
CREATE INDEX IF NOT EXISTS idx_knowledge_bases_category ON knowledge_bases(category);
CREATE INDEX IF NOT EXISTS idx_knowledge_bases_tags ON knowledge_bases USING gin(tags);
```

### カラム詳細（主要項目）

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `id` | UUID | PK | ナレッジベースID |
| `name` | VARCHAR | NOT NULL | 名前 |
| `description` | TEXT | NULL許容 | 説明 |
| `user_id` | UUID | NOT NULL | 所有者（authdb.users.id への論理FK） |
| `status` | VARCHAR | NOT NULL, DEFAULT 'active' | ステータス（active, archived） |
| `is_public` | BOOLEAN | NOT NULL, DEFAULT false | 公開/非公開 |
| `document_count` | INTEGER | NOT NULL, DEFAULT 0 | 含まれるドキュメント数 |
| `storage_size` | BIGINT | NOT NULL, DEFAULT 0 | 合計ストレージサイズ（バイト） |
| `tags` | TEXT[] | DEFAULT '{}' | タグ配列 |

---

## documentsテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS documents (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  knowledge_base_id uuid REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  filename VARCHAR NOT NULL,
  original_filename VARCHAR NOT NULL,
  file_path VARCHAR NOT NULL,
  processing_path VARCHAR,
  mime_type VARCHAR NOT NULL,
  file_size BIGINT NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'uploaded',
  processing_metadata JSON,
  text_content TEXT,
  user_id uuid,
  is_public BOOLEAN DEFAULT false,
  tags TEXT[] DEFAULT '{}',
  category VARCHAR,
  -- OCRメタデータ管理カラム
  original_metadata JSONB,
  edited_metadata JSONB,
  editing_status VARCHAR DEFAULT 'unedited',
  last_edited_at TIMESTAMP,
  edited_by uuid,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT check_owner CHECK (knowledge_base_id IS NOT NULL OR user_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_documents_kb_id ON documents(knowledge_base_id);
CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_documents_filename ON documents(filename);
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(category);
CREATE INDEX IF NOT EXISTS idx_documents_tags ON documents USING gin(tags);
CREATE INDEX IF NOT EXISTS idx_documents_is_public ON documents(is_public);
-- OCRメタデータ関連のインデックス
CREATE INDEX IF NOT EXISTS idx_documents_editing_status ON documents(editing_status);
CREATE INDEX IF NOT EXISTS idx_documents_last_edited_at ON documents(last_edited_at);
CREATE INDEX IF NOT EXISTS idx_documents_edited_by ON documents(edited_by);
```

### カラム詳細（OCR重点）

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `id` | UUID | PK | ドキュメントID |
| `knowledge_base_id` | UUID | FK, NULL許容 | 所属するナレッジベース |
| `filename` | VARCHAR | NOT NULL | 保存ファイル名 |
| `original_filename` | VARCHAR | NOT NULL | 元のファイル名 |
| `file_path` | VARCHAR | NOT NULL | ファイルパス |
| `status` | VARCHAR | NOT NULL, DEFAULT 'uploaded' | ステータス（uploaded, processing, completed, failed） |
| `original_metadata` | JSONB | NULL許容 | **OCR処理時の元メタデータ** |
| `edited_metadata` | JSONB | NULL許容 | **編集後のメタデータ** |
| `editing_status` | VARCHAR | DEFAULT 'unedited' | 編集状態（unedited, editing, edited） |
| `last_edited_at` | TIMESTAMP | NULL許容 | 最終編集日時 |
| `edited_by` | UUID | NULL許容 | 編集者のユーザーID |

### OCRメタデータの構造

```json
// original_metadata / edited_metadata の例
{
  "pages": [
    {
      "page_number": 1,
      "elements": [
        {
          "id": "ID-1",
          "type": "heading",
          "level": 1,
          "content": "タイトル",
          "bbox": [100, 200, 500, 250]
        },
        {
          "id": "ID-2",
          "type": "paragraph",
          "content": "本文テキスト...",
          "bbox": [100, 300, 500, 400]
        }
      ]
    }
  ]
}
```

### OCR編集フロー

```python
# 1. OCR処理後に original_metadata を保存
document.original_metadata = ocr_result
document.editing_status = 'unedited'
db.commit()

# 2. ユーザーが編集開始
document.editing_status = 'editing'
db.commit()

# 3. 編集内容を edited_metadata に保存
document.edited_metadata = edited_ocr_data
document.editing_status = 'edited'
document.last_edited_at = datetime.utcnow()
document.edited_by = current_user_id
db.commit()
```

### 重要な設計: ID生成の一貫性

**2025-09-02 に修正された重要な仕様**:

**問題**: 以前はページごとに `HierarchyConverter` を作成していたため、各ページで ID が `ID-1` から始まっていた

**修正**: ドキュメント全体で単一の `HierarchyConverter` インスタンスを使用

**結果**:
- **修正前**: Page 1: ID-1,2,3... | Page 2: ID-1,2,3... ❌
- **修正後**: Page 1: ID-1,2,3... | Page 2: ID-4,5,6... ✅

**実装**（backend）:
```python
# ai-micro-api-admin/app/core/document_processing/base.py
converter = HierarchyConverter()  # ドキュメント全体で1つ

for page_data in pages:
    hierarchical = converter.convert_to_hierarchy(page_data)
    # ID が連続して採番される
```

**フロントエンドでの使用**:
```typescript
// ai-micro-front-admin/src/pages/documents/ocr/[id].tsx
// backend から受け取った ID をそのまま使用（ページ番号を掛けない）
const elementId = element.id;  // "ID-4", "ID-5" など
```

---

## langchain_pg_collectionテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS langchain_pg_collection (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    cmetadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### カラム詳細

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `uuid` | UUID | PK | コレクションID |
| `name` | VARCHAR(255) | UNIQUE, NOT NULL | コレクション名 |
| `cmetadata` | JSONB | DEFAULT '{}' | メタデータ（埋め込みモデル情報等） |
| `created_at` | TIMESTAMP TZ | DEFAULT NOW() | 作成日時 |
| `updated_at` | TIMESTAMP TZ | DEFAULT NOW() | 更新日時 |

### デフォルトコレクション

```sql
-- 初期化時に作成されるデフォルトコレクション
INSERT INTO langchain_pg_collection (name, cmetadata)
VALUES (
    'admin_documents',
    '{"description": "Admin document embeddings collection", "model": "nomic-embed-text"}'::jsonb
)
ON CONFLICT (name) DO NOTHING;
```

---

## langchain_pg_embeddingテーブル

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS langchain_pg_embedding (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID REFERENCES langchain_pg_collection(uuid) ON DELETE CASCADE,
    embedding vector(768), -- nomic-embed-text produces 768-dimensional embeddings
    document TEXT NOT NULL,
    cmetadata JSONB DEFAULT '{}'::jsonb,
    custom_id VARCHAR(255),
    document_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS langchain_pg_embedding_collection_id_idx ON langchain_pg_embedding(collection_id);
CREATE INDEX IF NOT EXISTS langchain_pg_embedding_custom_id_idx ON langchain_pg_embedding(custom_id);
CREATE INDEX IF NOT EXISTS langchain_pg_embedding_document_id_idx ON langchain_pg_embedding(document_id);
```

### カラム詳細

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| `uuid` | UUID | PK | 埋め込みID |
| `collection_id` | UUID | FK | 所属するコレクション |
| `embedding` | VECTOR(768) | NULL許容 | **768次元ベクトル（nomic-embed-text）** |
| `document` | TEXT | NOT NULL | テキストチャンク |
| `cmetadata` | JSONB | DEFAULT '{}' | メタデータ |
| `custom_id` | VARCHAR(255) | NULL許容 | カスタムID |
| `document_id` | UUID | FK | 元のドキュメント（documents.id） |
| `chunk_index` | INTEGER | DEFAULT 0 | チャンクのインデックス |

### pgvector の使用例

```python
from langchain_postgres import PGVector

# ベクトルストア初期化
vector_store = PGVector(
    embeddings=embeddings,
    collection_name="admin_documents",
    connection_string="postgresql://...",
    use_jsonb=True,
)

# ドキュメントの追加
vector_store.add_documents(
    documents=docs,
    ids=[str(uuid.uuid4()) for _ in docs]
)

# 類似度検索
results = vector_store.similarity_search(
    query="検索クエリ",
    k=5  # 上位5件
)
```

### コサイン類似度検索

```sql
-- クエリベクトルとの類似度検索
SELECT
    uuid,
    document,
    1 - (embedding <=> '[0.1, 0.2, ...]'::vector) AS similarity
FROM langchain_pg_embedding
WHERE collection_id = 'collection-uuid'
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

---

## インデックス設計

### B-Tree インデックス

```sql
-- 頻出検索カラム
CREATE INDEX idx_system_logs_service ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(level);
CREATE INDEX idx_login_logs_user_id ON login_logs(user_id);
CREATE INDEX idx_documents_kb_id ON documents(knowledge_base_id);
CREATE INDEX idx_documents_status ON documents(status);
```

### GIN インデックス（配列・JSONB）

```sql
-- 配列型カラム
CREATE INDEX idx_knowledge_bases_tags ON knowledge_bases USING gin(tags);
CREATE INDEX idx_documents_tags ON documents USING gin(tags);

-- JSONB型カラム（将来的な検索用）
-- CREATE INDEX idx_documents_original_metadata ON documents USING gin(original_metadata);
```

### パフォーマンス確認

```sql
-- インデックス使用状況
SELECT
    schemaname,
    tablename,
    indexrelname,
    idx_scan,
    idx_tup_read
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

---

## pgvector による RAG 機能

### 埋め込みモデル

**使用モデル**: nomic-embed-text
**次元数**: 768
**特徴**: 高精度な英語・日本語対応

### ベクトル検索の仕組み

```
1. ドキュメントアップロード
   └─> テキスト抽出
       └─> チャンク分割（512トークン）
           └─> 埋め込み生成（768次元ベクトル）
               └─> langchain_pg_embedding に保存

2. RAG検索
   └─> クエリを埋め込み化（768次元ベクトル）
       └─> コサイン類似度で類似ドキュメント検索
           └─> 上位K件を取得
               └─> LLMにコンテキストとして渡す
```

### 距離演算子

pgvector は以下の演算子をサポート:

| 演算子 | 説明 | 用途 |
|-------|------|------|
| `<->` | ユークリッド距離 | L2ノルム |
| `<=>` | コサイン距離 | コサイン類似度（RAGで一般的） |
| `<#>` | 内積の負数 | ドット積類似度 |

**推奨**: コサイン距離（`<=>`）をRAGで使用

---

## OCR メタデータ管理

### JSONB 型の利点

1. **柔軟な構造**: 階層的なOCR結果を保存
2. **インデックス作成可能**: GINインデックスで高速検索
3. **部分更新可能**: 特定要素のみ更新

### 編集履歴の管理

```sql
-- 編集前後の比較
SELECT
    id,
    filename,
    original_metadata->'pages'->0->'elements'->0->>'content' AS original_content,
    edited_metadata->'pages'->0->'elements'->0->>'content' AS edited_content
FROM documents
WHERE editing_status = 'edited';
```

### JSONB クエリ例

```sql
-- 特定のページ数を持つドキュメント
SELECT filename
FROM documents
WHERE jsonb_array_length(original_metadata->'pages') > 10;

-- 特定要素タイプの検索
SELECT filename
FROM documents
WHERE original_metadata @> '{"pages": [{"elements": [{"type": "heading"}]}]}';
```

---

## トラブルシューティング

### pgvector 関連

```sql
-- 拡張機能の確認
SELECT * FROM pg_extension WHERE extname = 'vector';

-- ベクトル次元の確認
SELECT
    column_name,
    data_type,
    udt_name
FROM information_schema.columns
WHERE table_name = 'langchain_pg_embedding'
  AND column_name = 'embedding';
```

### パフォーマンス問題

```sql
-- テーブルサイズ確認（ベクトルテーブルは巨大になる）
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- VACUUM実行（ベクトルテーブルは頻繁に必要）
VACUUM ANALYZE langchain_pg_embedding;
```

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [authdb スキーマ](./04-authdb-schema.md)
- [apidb スキーマ](./05-apidb-schema.md)
- [データベース間連携](./08-cross-database-relations.md)
- [Admin API Service 概要](/03-admin-api/01-overview.md)

---

**次のステップ**: [ER図](./07-er-diagram.md) を参照して、テーブル間の関係性を視覚的に理解してください。