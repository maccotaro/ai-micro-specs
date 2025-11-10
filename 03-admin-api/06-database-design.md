# Admin API Service - データベース設計

**カテゴリ**: Database Design
**バージョン**: 1.0.0
**最終更新**: 2025-11-08

## 目次
- [概要](#概要)
- [データベーススキーマ](#データベーススキーマ)
- [テーブル詳細](#テーブル詳細)
- [pgvector統合](#pgvector統合)
- [インデックス戦略](#インデックス戦略)
- [データライフサイクル](#データライフサイクル)

---

## 概要

Admin API Serviceは、**PostgreSQL 15 + pgvector拡張**を使用して、システムログ、ドキュメント、ナレッジベース、ベクトル埋め込みを管理します。

### データベース情報

| 項目 | 内容 |
|------|------|
| データベース名 | `admindb` |
| PostgreSQLバージョン | 15+ |
| 拡張機能 | pgvector |
| 接続URL | `postgresql://postgres:password@host.docker.internal:5432/admindb` |
| ORM | SQLAlchemy 2.x |

### 主要テーブル

| テーブル | 用途 | 主要カラム |
|---------|------|-----------|
| `system_logs` | システムログ管理 | service_name, level, message |
| `login_logs` | ログイン履歴 | user_id, ip_address, success |
| `system_settings` | システム設定 | key, value (JSON) |
| `tenants` | テナント管理 | name, display_name, is_active, settings |
| `documents` | ドキュメント管理 | filename, processing_metadata (JSONB), tenant_id |
| `knowledge_bases` | ナレッジベース | name, document_count, storage_size, tenant_id |
| `collections` | コレクション | name, knowledge_base_id, is_default |
| `langchain_pg_collection` | ベクトルコレクション | name, cmetadata (JSONB) |
| `langchain_pg_embedding` | ベクトル埋め込み | embedding (vector 1024), document_id |
| `knowledge_bases_summary_embedding` | KB要約ベクトル（Atlas層） | summary_text, summary_embedding (vector 1024) |
| `collections_summary_embedding` | Collection要約ベクトル（Atlas層） | summary_text, summary_embedding (vector 1024) |
| `document_fulltext` | 全文検索（スパース層） | content, term_frequency, bm25_score_cache |
| `chat_sessions` | チャットセッション | title, is_favorite, message_count |
| `chat_messages` | チャットメッセージ | role, content, metadata (JSONB) |
| `rag_audit_logs` | RAG監査ログ | event_type, user_id, execution_time_ms |
| `prompt_templates` | プロンプトテンプレート | name, template_content |

---

## データベーススキーマ

### ER図

```
┌─────────────────┐
│ knowledge_bases │
│ (ナレッジベース)│
└────────┬────────┘
         │ 1
         │
         │ N
    ┌────▼────────┐         ┌──────────────────────┐
    │  documents  │◄────────│langchain_pg_embedding│
    │(ドキュメント)│         │  (ベクトル埋め込み)   │
    └─────────────┘         └──────────┬───────────┘
                                       │ N
                                       │
                                       │ 1
                            ┌──────────▼──────────────┐
                            │langchain_pg_collection  │
                            │ (ベクトルコレクション)   │
                            └─────────────────────────┘

┌─────────────┐
│ system_logs │
│(システムログ)│
└─────────────┘

┌─────────────┐
│ login_logs  │
│(ログイン履歴)│
└─────────────┘

┌─────────────────┐
│ system_settings │
│ (システム設定)   │
└─────────────────┘

┌──────────────────┐
│ prompt_templates │
│(プロンプト管理)  │
└──────────────────┘
```

---

## テーブル詳細

### system_logs

**用途**: 全サービスのログを集約管理

**ファイル**: `app/models/logs.py:10-18`

```python
class SystemLog(Base):
    __tablename__ = "system_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    service_name = Column(String(50), nullable=False, index=True)
    level = Column(String(10), nullable=False, index=True)
    message = Column(Text, nullable=False)
    log_metadata = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
```

#### カラム詳細

| カラム | 型 | NULL | 説明 | 例 |
|-------|---|------|------|---|
| `id` | UUID | NO | プライマリキー | `123e4567-e89b-12d3-a456-426614174000` |
| `service_name` | VARCHAR(50) | NO | サービス名（インデックス） | "auth", "user", "admin" |
| `level` | VARCHAR(10) | NO | ログレベル（インデックス） | "DEBUG", "INFO", "WARN", "ERROR" |
| `message` | TEXT | NO | ログメッセージ | "User login successful" |
| `log_metadata` | JSON | YES | 追加メタデータ | `{"user_id": "...", "ip": "192.168.1.1"}` |
| `created_at` | TIMESTAMP | NO | 作成日時（インデックス） | `2025-09-30T14:35:00Z` |

#### インデックス

```sql
CREATE INDEX idx_system_logs_service_name ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(level);
CREATE INDEX idx_system_logs_created_at ON system_logs(created_at);
```

#### 使用例

```python
# ログ作成
log = SystemLog(
    service_name="admin",
    level="INFO",
    message="Document processed successfully",
    log_metadata={"document_id": "...", "pages": 15}
)
db.add(log)
db.commit()

# エラーログ検索
error_logs = db.query(SystemLog).filter(
    SystemLog.level == "ERROR",
    SystemLog.created_at >= datetime.now() - timedelta(days=1)
).order_by(SystemLog.created_at.desc()).all()
```

---

### login_logs

**用途**: ユーザーログイン履歴の記録

**ファイル**: `app/models/logs.py:21-30`

```python
class LoginLog(Base):
    __tablename__ = "login_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    ip_address = Column(String(45), nullable=True)  # IPv6対応
    user_agent = Column(Text, nullable=True)
    success = Column(String(10), nullable=False, default="true")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
```

#### カラム詳細

| カラム | 型 | NULL | 説明 |
|-------|---|------|------|
| `id` | UUID | NO | プライマリキー |
| `user_id` | UUID | NO | ユーザーID（インデックス） |
| `ip_address` | VARCHAR(45) | YES | クライアントIP（IPv6対応） |
| `user_agent` | TEXT | YES | ブラウザ情報 |
| `success` | VARCHAR(10) | NO | "true" or "false" |
| `error_message` | TEXT | YES | 失敗時のエラー内容 |
| `created_at` | TIMESTAMP | NO | ログイン日時（インデックス） |

---

### system_settings

**用途**: システム全体の設定管理

**ファイル**: `app/models/logs.py:33-40`

```python
class SystemSetting(Base):
    __tablename__ = "system_settings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    key = Column(String(100), unique=True, nullable=False, index=True)
    value = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

#### カラム詳細

| カラム | 型 | NULL | 説明 | 例 |
|-------|---|------|------|---|
| `id` | UUID | NO | プライマリキー | - |
| `key` | VARCHAR(100) | NO | 設定キー（ユニーク、インデックス） | "maintenance_mode", "max_upload_size" |
| `value` | JSON | NO | 設定値（JSON） | `{"enabled": true, "message": "メンテナンス中"}` |
| `created_at` | TIMESTAMP | NO | 作成日時 | - |
| `updated_at` | TIMESTAMP | NO | 更新日時（自動更新） | - |

#### 使用例

```python
# メンテナンスモード設定
setting = SystemSetting(
    key="maintenance_mode",
    value={"enabled": True, "message": "システムメンテナンス中です"}
)
db.add(setting)
db.commit()

# 設定取得
maintenance = db.query(SystemSetting).filter(
    SystemSetting.key == "maintenance_mode"
).first()
is_maintenance = maintenance.value.get("enabled", False)
```

---

### documents

**用途**: ドキュメント管理とOCRメタデータ保存

**ファイル**: `app/models/logs.py:69-97`

```python
class Document(Base):
    __tablename__ = "documents"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    knowledge_base_id = Column(UUID(as_uuid=True), ForeignKey("knowledge_bases.id", ondelete="CASCADE"), nullable=True, index=True)
    filename = Column(String(255), nullable=False, index=True)
    original_filename = Column(String(255), nullable=False)
    file_path = Column(String(500), nullable=False)
    processing_path = Column(String(500), nullable=True)
    mime_type = Column(String(100), nullable=False)
    file_size = Column(BigInteger, nullable=False)
    status = Column(String(20), nullable=False, default="uploaded", index=True)
    processing_metadata = Column(JSON, nullable=True)
    text_content = Column(Text, nullable=True)
    user_id = Column(UUID(as_uuid=True), nullable=True, index=True)
    is_public = Column(Boolean, default=False, index=True)
    tags = Column(ARRAY(String), default=list)
    category = Column(String(100), nullable=True, index=True)
    # OCRメタデータ管理カラム
    original_metadata = Column(JSONB, nullable=True)
    edited_metadata = Column(JSONB, nullable=True)
    editing_status = Column(String(20), default='unedited', index=True)
    last_edited_at = Column(DateTime(timezone=True), nullable=True)
    edited_by = Column(UUID(as_uuid=True), nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    # リレーションシップ
    knowledge_base = relationship("KnowledgeBase", back_populates="documents")
```

#### 主要カラム

| カラム | 型 | NULL | 説明 |
|-------|---|------|------|
| `id` | UUID | NO | プライマリキー |
| `knowledge_base_id` | UUID | YES | 所属ナレッジベースID（外部キー） |
| `filename` | VARCHAR(255) | NO | 保存ファイル名 |
| `original_filename` | VARCHAR(255) | NO | 元のファイル名 |
| `file_path` | VARCHAR(500) | NO | ファイル保存パス |
| `processing_path` | VARCHAR(500) | YES | 処理結果ディレクトリパス |
| `status` | VARCHAR(20) | NO | "uploaded", "processing", "completed", "failed" |
| `processing_metadata` | JSON | YES | 基本処理メタデータ（output_directory等） |
| `original_metadata` | JSONB | YES | **Docling処理結果（読み取り専用）** |
| `edited_metadata` | JSONB | YES | **手動修正後メタデータ（フロント表示用）** |
| `editing_status` | VARCHAR(20) | NO | "unedited", "editing", "edited" |
| `last_edited_at` | TIMESTAMP | YES | 最終編集日時 |
| `edited_by` | UUID | YES | 編集者ID |

#### OCRメタデータJSONB構造

**original_metadata / edited_metadata**:
```json
{
  "document_name": "report.pdf",
  "total_pages": 15,
  "dimensions": {
    "pdf_page": {"width": 595.2, "height": 842.4},
    "image_page": {"width": 1190, "height": 1684}
  },
  "pages": [
    {
      "page_number": 1,
      "hierarchical_elements": [
        {
          "id": "ID-1",
          "type": "title",
          "text": "Introduction",
          "bbox": {"x1": 100, "y1": 150, "x2": 500, "y2": 200},
          "reading_order": 1,
          "spatial_level": 0,
          "semantic_level": 1,
          "importance_score": 0.95,
          "cropped_image_path": "figures/ID-1.png"
        }
      ]
    }
  ]
}
```

#### インデックス

```sql
CREATE INDEX idx_documents_knowledge_base_id ON documents(knowledge_base_id);
CREATE INDEX idx_documents_user_id ON documents(user_id);
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_editing_status ON documents(editing_status);
CREATE INDEX idx_documents_edited_by ON documents(edited_by);
```

---

### knowledge_bases

**用途**: ドキュメントコレクション（ナレッジベース）管理

**ファイル**: `app/models/logs.py:43-66`

```python
class KnowledgeBase(Base):
    __tablename__ = "knowledge_bases"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    permissions = Column(JSON, nullable=False, default=list)
    prompt = Column(Text, nullable=True)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    status = Column(String(20), nullable=False, default="active", index=True)
    is_public = Column(Boolean, nullable=False, default=False)
    document_count = Column(Integer, nullable=False, default=0)
    storage_size = Column(BigInteger, nullable=False, default=0)
    last_accessed_at = Column(DateTime(timezone=True), nullable=True)
    processing_settings = Column(JSON, default=dict)
    search_settings = Column(JSON, default=dict)
    tags = Column(ARRAY(String), default=list)
    category = Column(String(100), nullable=True, index=True)
    version = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    # リレーションシップ
    documents = relationship("Document", back_populates="knowledge_base", cascade="all, delete-orphan")
```

#### 主要カラム

| カラム | 型 | NULL | 説明 |
|-------|---|------|------|
| `id` | UUID | NO | プライマリキー |
| `name` | VARCHAR(255) | NO | ナレッジベース名 |
| `description` | TEXT | YES | 説明 |
| `user_id` | UUID | NO | 作成者ID |
| `document_count` | INTEGER | NO | 含まれるドキュメント数（自動計算） |
| `storage_size` | BIGINT | NO | 総ストレージサイズ（バイト） |
| `processing_settings` | JSON | YES | 処理設定（OCR言語等） |
| `search_settings` | JSON | YES | 検索設定（類似度閾値等） |

---

## pgvector統合

### 概要

**pgvector**は、PostgreSQLでベクトル類似度検索を可能にする拡張機能です。RAG（Retrieval Augmented Generation）での文書検索に使用します。

### 初期化スクリプト

**ファイル**: `init.sql`

```sql
-- pgvector拡張有効化
CREATE EXTENSION IF NOT EXISTS vector;

-- LangChain PGVectorコレクションテーブル
CREATE TABLE IF NOT EXISTS langchain_pg_collection (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    cmetadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- LangChain PGVector埋め込みテーブル
CREATE TABLE IF NOT EXISTS langchain_pg_embedding (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID REFERENCES langchain_pg_collection(uuid) ON DELETE CASCADE,
    embedding vector(1024), -- bge-m3:567m: 1024次元
    document TEXT NOT NULL,
    cmetadata JSONB DEFAULT '{}'::jsonb,
    custom_id VARCHAR(255),
    document_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### langchain_pg_collection

**用途**: ベクトルコレクション管理

| カラム | 型 | 説明 |
|-------|---|------|
| `uuid` | UUID | プライマリキー |
| `name` | VARCHAR(255) | コレクション名（ユニーク） |
| `cmetadata` | JSONB | メタデータ（モデル情報等） |

**デフォルトコレクション**:
```sql
INSERT INTO langchain_pg_collection (name, cmetadata)
VALUES ('admin_documents', '{"description": "Admin document embeddings", "model": "bge-m3:567m"}'::jsonb);
```

### langchain_pg_embedding

**用途**: ベクトル埋め込み保存と類似度検索

| カラム | 型 | 説明 |
|-------|---|------|
| `uuid` | UUID | プライマリキー |
| `collection_id` | UUID | 所属コレクション（外部キー） |
| `embedding` | vector(1024) | **1024次元ベクトル（bge-m3:567m）** |
| `document` | TEXT | チャンクテキスト |
| `cmetadata` | JSONB | チャンクメタデータ（ページ番号、要素ID等） |
| `document_id` | UUID | 元ドキュメントID（外部キー） |
| `chunk_index` | INTEGER | チャンク番号 |

### ベクトルインデックス

**IVFFlat インデックス**（データ挿入後に作成推奨）:
```sql
CREATE INDEX langchain_pg_embedding_embedding_idx ON langchain_pg_embedding
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

**HNSW インデックス**（高次元データに最適、メモリ消費大）:
```sql
CREATE INDEX langchain_pg_embedding_embedding_hnsw_idx ON langchain_pg_embedding
USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
```

### 類似度検索クエリ

```sql
-- コサイン類似度検索（上位5件）
SELECT
    document,
    1 - (embedding <=> :query_embedding::vector) AS similarity
FROM langchain_pg_embedding
WHERE collection_id = :collection_id
ORDER BY embedding <=> :query_embedding::vector
LIMIT 5;
```

**Python使用例**:
```python
from langchain_postgres import PGVector
from langchain_ollama import OllamaEmbeddings

# ベクトルストア初期化
embeddings = OllamaEmbeddings(
    model="bge-m3:567m",
    base_url="http://localhost:11434"
)
vector_store = PGVector(
    connection_string="postgresql://postgres:password@localhost:5432/admindb",
    collection_name="admin_documents",
    embedding_function=embeddings
)

# 類似度検索
results = vector_store.similarity_search_with_score(
    "機械学習の応用事例",
    k=5
)

for doc, score in results:
    print(f"Similarity: {score:.3f}")
    print(f"Text: {doc.page_content}")
    print(f"Metadata: {doc.metadata}")
```

---

## インデックス戦略

### 主要インデックス一覧

```sql
-- system_logs
CREATE INDEX idx_system_logs_service_name ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(level);
CREATE INDEX idx_system_logs_created_at ON system_logs(created_at);

-- documents
CREATE INDEX idx_documents_knowledge_base_id ON documents(knowledge_base_id);
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_user_id ON documents(user_id);

-- langchain_pg_embedding
CREATE INDEX langchain_pg_embedding_collection_id_idx ON langchain_pg_embedding(collection_id);
CREATE INDEX langchain_pg_embedding_document_id_idx ON langchain_pg_embedding(document_id);

-- ベクトル類似度検索用
CREATE INDEX langchain_pg_embedding_embedding_idx ON langchain_pg_embedding
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

### インデックス選択基準

| インデックスタイプ | 用途 | 適用カラム |
|-----------------|------|-----------|
| B-tree | 等価検索・範囲検索 | service_name, level, created_at |
| IVFFlat | ベクトル類似度検索（大規模） | embedding（10万件以上） |
| HNSW | ベクトル類似度検索（高精度） | embedding（高次元・高速検索） |

---

## データライフサイクル

### ドキュメント処理フロー

```
1. ドキュメントアップロード
   ↓ status: "uploaded"
   INSERT INTO documents (filename, file_path, status, ...)

2. Docling処理開始
   ↓ status: "processing"
   UPDATE documents SET status='processing'

3. 処理完了
   ↓ status: "completed"
   UPDATE documents SET
     status='completed',
     processing_path='...',
     original_metadata='metadata_hierarchy.json'

4. ベクトル化
   ↓
   INSERT INTO langchain_pg_embedding (embedding, document_id, ...)

5. OCR編集（オプション）
   ↓ editing_status: "edited"
   UPDATE documents SET
     edited_metadata='...',
     editing_status='edited',
     last_edited_at=NOW()
```

### データ削除ポリシー

**カスケード削除**:
```sql
-- ナレッジベース削除 → 関連ドキュメント削除
DELETE FROM knowledge_bases WHERE id = :kb_id;
-- → documents (ON DELETE CASCADE)
-- → langchain_pg_embedding (ON DELETE CASCADE)

-- ドキュメント削除 → ベクトル埋め込み削除
DELETE FROM documents WHERE id = :doc_id;
-- → langchain_pg_embedding (ON DELETE CASCADE)
```

### バックアップ戦略

```bash
# データベース全体バックアップ
pg_dump -U postgres -d admindb > admindb_backup.sql

# テーブル個別バックアップ
pg_dump -U postgres -d admindb -t documents > documents_backup.sql

# ベクトルデータのみバックアップ
pg_dump -U postgres -d admindb -t langchain_pg_embedding > vectors_backup.sql
```

---

## パフォーマンス最適化

### JSONB vs JSON

**JSONB使用箇所**:
- `documents.original_metadata`
- `documents.edited_metadata`
- `langchain_pg_embedding.cmetadata`

**理由**:
- インデックス作成可能
- クエリ実行速度向上
- ストレージ効率

**JSONBインデックス例**:
```sql
-- GINインデックス（JSONBフィールド検索高速化）
CREATE INDEX idx_documents_original_metadata ON documents USING GIN (original_metadata);

-- 特定パス検索
SELECT * FROM documents
WHERE original_metadata @> '{"document_name": "report.pdf"}'::jsonb;
```

### パーティショニング

大量ログデータの管理:
```sql
-- 月別パーティショニング（system_logs）
CREATE TABLE system_logs_2025_09 PARTITION OF system_logs
FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');

CREATE TABLE system_logs_2025_10 PARTITION OF system_logs
FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
```

---

## トラブルシューティング

### よくある問題

**問題1: pgvector拡張が見つからない**
```bash
# 解決: pgvectorインストール
apt-get install postgresql-15-pgvector
# または
brew install pgvector
```

**問題2: ベクトル検索が遅い**
```sql
-- インデックス確認
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'langchain_pg_embedding';

-- インデックス作成（未作成の場合）
CREATE INDEX langchain_pg_embedding_embedding_idx ON langchain_pg_embedding
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

**問題3: JSONBクエリが遅い**
```sql
-- GINインデックス作成
CREATE INDEX idx_documents_metadata_gin ON documents USING GIN (original_metadata);

-- EXPLAIN ANALYZEで確認
EXPLAIN ANALYZE
SELECT * FROM documents WHERE original_metadata @> '{"total_pages": 15}'::jsonb;
```

---

## エンタープライズRAG関連テーブル

### tenants

**用途**: マルチテナント対応のテナント管理

**ファイル**: `app/models/tenant.py`

```python
class Tenant(Base):
    __tablename__ = "tenants"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False, unique=True, index=True)
    display_name = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    settings = Column(JSONB, default=dict)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

**主要カラム**:
| カラム | 型 | 説明 |
|-------|---|------|
| `id` | UUID | テナントID |
| `name` | VARCHAR(255) | テナント識別子（英数字_のみ、ユニーク） |
| `display_name` | VARCHAR(255) | 表示名 |
| `is_active` | BOOLEAN | アクティブ状態 |
| `settings` | JSONB | 設定（max_storage_gb、max_users等） |

**インデックス**:
```sql
CREATE INDEX idx_tenants_active ON tenants(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_tenants_name ON tenants(name);
CREATE INDEX idx_tenants_settings_gin ON tenants USING GIN (settings);
```

---

### knowledge_bases_summary_embedding (Atlas層)

**用途**: ナレッジベース要約ベクトルによる事前フィルタリング

**ファイル**: `app/models/atlas.py`

```python
class KnowledgeBaseSummaryEmbedding(Base):
    __tablename__ = "knowledge_bases_summary_embedding"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    knowledge_base_id = Column(UUID(as_uuid=True), ForeignKey("knowledge_bases.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    summary_text = Column(Text, nullable=True)
    summary_embedding = Column(Vector(1024), nullable=True)  # bge-m3:567m
    version = Column(Integer, nullable=False, default=1)
    is_active = Column(Boolean, default=True, nullable=False)
    total_documents = Column(Integer, default=0)
    total_chunks = Column(Integer, default=0)
    avg_document_length = Column(Float, default=0.0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

**主要カラム**:
| カラム | 型 | 説明 |
|-------|---|------|
| `knowledge_base_id` | UUID | KB外部キー（ユニーク） |
| `summary_text` | TEXT | KB要約テキスト（LLM生成） |
| `summary_embedding` | vector(1024) | 要約ベクトル（bge-m3） |
| `version` | INTEGER | バージョン番号 |
| `is_active` | BOOLEAN | 有効フラグ（非アクティブ時は再生成対象） |

**インデックス**:
```sql
CREATE INDEX idx_kb_summary_emb_ivfflat ON knowledge_bases_summary_embedding
USING ivfflat (summary_embedding vector_cosine_ops) WITH (lists = 10);

CREATE INDEX idx_kb_summary_emb_hnsw ON knowledge_bases_summary_embedding
USING hnsw (summary_embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
```

---

### collections_summary_embedding (Atlas層)

**用途**: コレクション要約ベクトルによる事前フィルタリング

**ファイル**: `app/models/atlas.py`

```python
class CollectionSummaryEmbedding(Base):
    __tablename__ = "collections_summary_embedding"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    collection_id = Column(UUID(as_uuid=True), ForeignKey("collections.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    summary_text = Column(Text, nullable=True)
    summary_embedding = Column(Vector(1024), nullable=True)  # bge-m3:567m
    version = Column(Integer, nullable=False, default=1)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

---

### document_fulltext (スパース層)

**用途**: PGroonga全文検索とBM25スコアリング

```sql
CREATE TABLE document_fulltext (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    content_pgroonga TEXT,  -- PGroonga全文検索用
    term_frequency JSONB DEFAULT '{}'::jsonb,
    bm25_score_cache FLOAT DEFAULT 0.0,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    knowledge_base_id UUID REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    collection_id UUID REFERENCES collections(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**主要カラム**:
| カラム | 型 | 説明 |
|-------|---|------|
| `document_id` | UUID | ドキュメント外部キー |
| `chunk_index` | INTEGER | チャンク番号 |
| `content` | TEXT | チャンクテキスト |
| `content_pgroonga` | TEXT | PGroonga検索用（TokenMecab対応） |
| `term_frequency` | JSONB | BM25計算用タームフリークエンシー |
| `bm25_score_cache` | FLOAT | BM25スコアキャッシュ |

**インデックス**:
```sql
-- PGroonga全文検索インデックス（日本語形態素解析）
CREATE INDEX idx_document_fulltext_pgroonga ON document_fulltext
USING pgroonga (content_pgroonga);

-- PostgreSQL標準FTS（PGroongaフォールバック）
ALTER TABLE langchain_pg_embedding ADD COLUMN document_tsv tsvector;
CREATE INDEX idx_langchain_emb_document_tsv ON langchain_pg_embedding USING GIN (document_tsv);
```

---

### chat_sessions

**用途**: チャットセッション管理

**ファイル**: `app/models/chat.py`

```python
class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    knowledge_base_id = Column(UUID(as_uuid=True), ForeignKey("knowledge_bases.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    title = Column(String(50), nullable=False)
    is_favorite = Column(Boolean, default=False, nullable=False)
    message_count = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

**主要カラム**:
| カラム | 型 | 説明 |
|-------|---|------|
| `knowledge_base_id` | UUID | KB外部キー |
| `user_id` | UUID | ユーザーID |
| `title` | VARCHAR(50) | セッションタイトル（自動生成） |
| `is_favorite` | BOOLEAN | お気に入りフラグ |
| `message_count` | INTEGER | メッセージ数（トリガーで自動更新） |

**インデックス**:
```sql
CREATE INDEX idx_chat_sessions_kb_user ON chat_sessions(knowledge_base_id, user_id);
CREATE INDEX idx_chat_sessions_user ON chat_sessions(user_id);
```

---

### chat_messages

**用途**: チャットメッセージ保存

**ファイル**: `app/models/chat.py`

```python
class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    role = Column(String(20), nullable=False)  # 'user' or 'assistant'
    content = Column(Text, nullable=False)
    metadata = Column(JSONB, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

**メタデータ構造**:
```json
{
  "sources": [
    {
      "chunk_id": "chunk-uuid",
      "document_id": "doc-uuid",
      "score": 0.92
    }
  ],
  "tool_used": "search_documents",
  "execution_time_ms": 2500
}
```

---

### rag_audit_logs

**用途**: RAG操作の監査ログ

```sql
CREATE TABLE rag_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50) NOT NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE RESTRICT,
    user_id UUID,
    knowledge_base_id UUID REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    query TEXT,
    execution_time_ms INTEGER,
    result_count INTEGER,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**イベントタイプ**:
- `search_executed`: 検索実行
- `chat_session_created`: チャットセッション作成
- `kb_summary_regenerated`: KB要約再生成
- `cross_tenant_access`: クロステナントアクセス

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [API仕様](./02-api-specification.md)
- [ナレッジベースAPI](./02-api-knowledge-bases.md) - MCPチャット統合
- [チャット履歴管理API](./07-api-chat-sessions.md)
- [ハイブリッド検索API](./08-api-hybrid-search.md)
- [テナント管理API](./09-api-tenants.md)
- [ドキュメント処理パイプライン](./03-document-processing.md)
- [OCR設計](./04-ocr-design.md)
- [階層構造変換](./05-hierarchy-converter.md)
- [エンタープライズRAGシステム](../17-rag-system/README.md) - Atlas層、スパース層、Dense層の詳細設計
- [RAGデータベーススキーマ](../17-rag-system/diagrams/database-schema.md) - 統合ER図とインデックス戦略
- [MCPサーバー](../04-mcp-server/README.md) - Model Context Protocol統合