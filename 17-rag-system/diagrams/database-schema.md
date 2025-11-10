# RAGシステム統合データベーススキーマ

## 概要

このドキュメントは、エンタープライズRAGシステムで使用される全テーブルのER図と関係性を示します。

## 全体ER図

```
┌─────────────────────────────────────────────────────────────────┐
│                        テナント管理層                            │
└─────────────────────────────────────────────────────────────────┘

tenants (マルチテナント管理)
├─ id: UUID PRIMARY KEY
├─ name: VARCHAR(255) NOT NULL
├─ domain: VARCHAR(255) UNIQUE
├─ settings: JSONB
├─ is_active: BOOLEAN DEFAULT true
├─ created_at: TIMESTAMP
└─ updated_at: TIMESTAMP

         │ 1:N (tenant_id)
         ├──────────────────────────────────────┐
         │                                      │
         ▼                                      ▼

┌──────────────────────────────┐    ┌──────────────────────────────┐
│    ナレッジベース層          │    │      監査ログ層              │
└──────────────────────────────┘    └──────────────────────────────┘

knowledge_bases                     rag_audit_logs (Phase 3)
├─ id: UUID PRIMARY KEY            ├─ id: UUID PRIMARY KEY
├─ tenant_id: UUID → tenants       ├─ tenant_id: UUID → tenants
├─ name: VARCHAR(255)              ├─ user_id: UUID
├─ description: TEXT               ├─ query: TEXT
├─ prompt_template_id: UUID        ├─ filters: JSONB
├─ document_count: INTEGER         ├─ atlas_stage: JSONB
├─ storage_size: BIGINT            ├─ sparse_stage: JSONB
├─ meta_summary: JSONB             ├─ dense_stage: JSONB
├─ created_at: TIMESTAMP           ├─ rrf_stage: JSONB
└─ updated_at: TIMESTAMP           ├─ final_results: JSONB
                                   ├─ total_execution_time_ms: INT
         │ 1:1 (is_active=true)    ├─ success: BOOLEAN
         ▼                          ├─ error_message: TEXT
                                   └─ created_at: TIMESTAMP
knowledge_bases_summary_embedding
(Atlas層: KB要約ベクトル)
├─ id: UUID PRIMARY KEY
├─ knowledge_base_id: UUID → knowledge_bases (CASCADE)
├─ summary_text: TEXT NOT NULL
├─ summary_embedding: vector(1024) NOT NULL
├─ version: INTEGER DEFAULT 1
├─ is_active: BOOLEAN DEFAULT true
├─ total_documents: INTEGER DEFAULT 0
├─ total_chunks: INTEGER DEFAULT 0
├─ avg_document_length: INTEGER DEFAULT 0
├─ created_at: TIMESTAMP
└─ updated_at: TIMESTAMP

    UNIQUE (knowledge_base_id, is_active) WHERE is_active = true
    INDEX: idx_kb_summary_emb_hnsw (HNSW)
    INDEX: idx_kb_summary_emb_ivfflat (IVFFlat)

         │ 1:N (knowledge_base_id)
         ▼

┌─────────────────────────────────────────────────────────────────┐
│                      コレクション層                              │
└─────────────────────────────────────────────────────────────────┘

collections (ドキュメントグループ化)
├─ id: UUID PRIMARY KEY
├─ knowledge_base_id: UUID → knowledge_bases (CASCADE)
├─ name: VARCHAR(255) NOT NULL
├─ description: TEXT
├─ is_default: BOOLEAN DEFAULT false
├─ created_at: TIMESTAMP
└─ updated_at: TIMESTAMP

    UNIQUE (knowledge_base_id, name)

         │ 1:1 (is_active=true)
         ▼

collections_summary_embedding
(Atlas層: Collection要約ベクトル)
├─ id: UUID PRIMARY KEY
├─ collection_id: UUID → collections (CASCADE)
├─ summary_text: TEXT NOT NULL
├─ summary_embedding: vector(1024) NOT NULL
├─ version: INTEGER DEFAULT 1
├─ is_active: BOOLEAN DEFAULT true
├─ total_documents: INTEGER DEFAULT 0
├─ total_chunks: INTEGER DEFAULT 0
├─ avg_chunk_length: INTEGER DEFAULT 0
├─ created_at: TIMESTAMP
└─ updated_at: TIMESTAMP

    UNIQUE (collection_id, is_active) WHERE is_active = true
    INDEX: idx_coll_summary_emb_hnsw (HNSW)
    INDEX: idx_coll_summary_emb_ivfflat (IVFFlat)

         │ 1:N (collection_id)
         ▼

┌─────────────────────────────────────────────────────────────────┐
│                       ドキュメント層                             │
└─────────────────────────────────────────────────────────────────┘

documents (ドキュメント本体)
├─ id: UUID PRIMARY KEY
├─ knowledge_base_id: UUID → knowledge_bases (CASCADE)
├─ collection_id: UUID → collections (CASCADE)
├─ tenant_id: UUID → tenants
├─ filename: VARCHAR(255) NOT NULL
├─ file_path: VARCHAR(512)
├─ file_type: VARCHAR(50)
├─ file_size: BIGINT
├─ status: VARCHAR(50) (uploaded, processing, processed, failed)
├─ department: VARCHAR(100) ← Phase 1追加
├─ confidentiality: VARCHAR(50) ← Phase 1追加
├─ version: VARCHAR(50) ← Phase 1追加
├─ centroid_embedding: vector(1024) ← Phase 2追加
├─ chunk_count: INTEGER
├─ original_metadata: JSONB
├─ edited_metadata: JSONB
├─ processing_started_at: TIMESTAMP
├─ processing_completed_at: TIMESTAMP
├─ error_message: TEXT
├─ created_at: TIMESTAMP
└─ updated_at: TIMESTAMP

    INDEX: idx_documents_tenant_kb (tenant_id, knowledge_base_id)
    INDEX: idx_documents_tenant_dept_conf (tenant_id, department, confidentiality)
    INDEX: idx_documents_centroid_hnsw (HNSW on centroid_embedding)
    INDEX: idx_documents_centroid_ivfflat (IVFFlat on centroid_embedding)

         │ 1:N (document_id)
         ├──────────────────────────────┬──────────────────────────────┐
         ▼                              ▼                              ▼

┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐
│      Sparse層            │  │      Dense層             │  │   チャット履歴層         │
└──────────────────────────┘  └──────────────────────────┘  └──────────────────────────┘

document_fulltext             langchain_pg_embedding        chat_sessions
(全文検索・BM25)              (ベクトル検索)                ├─ id: UUID PRIMARY KEY
├─ id: UUID PRIMARY KEY      ├─ uuid: UUID PRIMARY KEY     ├─ knowledge_base_id: UUID
├─ document_id: UUID →       ├─ collection_id: UUID →      ├─ title: VARCHAR(255)
│  documents (CASCADE)       │  langchain_pg_collection    ├─ is_favorite: BOOLEAN
├─ chunk_index: INTEGER      ├─ embedding: vector(1024)    ├─ message_count: INTEGER
├─ content: TEXT NOT NULL    ├─ document: TEXT NOT NULL    ├─ created_at: TIMESTAMP
├─ content_length: INTEGER   ├─ cmetadata: JSONB           └─ updated_at: TIMESTAMP
│  GENERATED STORED          ├─ document_id: UUID →
├─ tenant_id: UUID →         │  documents (CASCADE)               │ 1:N (session_id)
│  tenants                   ├─ tenant_id: UUID → tenants        ▼
├─ knowledge_base_id: UUID   ├─ chunk_index: INTEGER
├─ collection_id: UUID       ├─ created_at: TIMESTAMP      chat_messages
├─ term_frequency: JSONB     │                              ├─ id: UUID PRIMARY KEY
├─ bm25_score_cache:         UNIQUE (document_id,          ├─ session_id: UUID →
│  NUMERIC(10,4)             │  chunk_index)               │  chat_sessions (CASCADE)
└─ created_at: TIMESTAMP     │                              ├─ role: VARCHAR(50)
                             INDEX: idx_langchain_emb_     ├─ content: TEXT
    UNIQUE (document_id,     │  hnsw (HNSW)               ├─ sources: JSONB
    │  chunk_index)          INDEX: idx_langchain_emb_     ├─ tokens_used: INTEGER
    │                        │  ivfflat (IVFFlat)          ├─ created_at: TIMESTAMP
    INDEX:                   INDEX: idx_langchain_emb_     └─ updated_at: TIMESTAMP
    │  idx_document_         │  tenant_kb
    │  fulltext_gin (GIN)    │  (tenant_id, cmetadata)
    INDEX:                   INDEX: idx_langchain_emb_
    │  idx_document_         │  doc_chunk
    │  fulltext_pgroonga     │  (document_id, chunk_index)
    │  (PGroonga)
    INDEX:
    │  idx_document_
    │  fulltext_filters
    │  (tenant_id, kb_id,
    │   collection_id)

┌─────────────────────────────────────────────────────────────────┐
│                         統計ビュー                               │
└─────────────────────────────────────────────────────────────────┘

atlas_layer_statistics (MATERIALIZED VIEW)
├─ knowledge_base_id: UUID
├─ knowledge_base_name: VARCHAR
├─ summary_version: INTEGER
├─ total_documents: INTEGER
├─ total_chunks: INTEGER
├─ avg_document_length: INTEGER
├─ summary_created_at: TIMESTAMP
├─ collection_count: INTEGER
└─ total_collection_documents: INTEGER

    SOURCE: knowledge_bases + knowledge_bases_summary_embedding
           + collections + collections_summary_embedding

sparse_search_statistics (MATERIALIZED VIEW)
├─ tenant_id: UUID
├─ knowledge_base_id: UUID
├─ total_chunks: INTEGER
├─ avg_chunk_length: INTEGER
├─ max_chunk_length: INTEGER
├─ min_chunk_length: INTEGER
└─ total_content_length: BIGINT

    SOURCE: document_fulltext

dense_search_statistics (MATERIALIZED VIEW)
├─ tenant_id: UUID
├─ knowledge_base_id: UUID
├─ total_embeddings: INTEGER
├─ avg_chunk_length: INTEGER
├─ max_chunk_length: INTEGER
├─ min_chunk_length: INTEGER
└─ total_documents: INTEGER

    SOURCE: langchain_pg_embedding
```

## 主要なインデックス

### ベクトル検索インデックス（HNSW）

| テーブル | インデックス名 | カラム | パラメータ |
|---------|--------------|--------|-----------|
| knowledge_bases_summary_embedding | idx_kb_summary_emb_hnsw | summary_embedding | m=16, ef_construction=64 |
| collections_summary_embedding | idx_coll_summary_emb_hnsw | summary_embedding | m=16, ef_construction=64 |
| documents | idx_documents_centroid_hnsw | centroid_embedding | m=16, ef_construction=64 |
| langchain_pg_embedding | idx_langchain_pg_embedding_hnsw | embedding | m=16, ef_construction=64 |

### 全文検索インデックス（GIN/PGroonga）

| テーブル | インデックス名 | タイプ | カラム |
|---------|--------------|--------|--------|
| document_fulltext | idx_document_fulltext_gin | GIN | to_tsvector('simple', content) |
| document_fulltext | idx_document_fulltext_pgroonga | PGroonga | content (TokenMecab) |
| langchain_pg_embedding | idx_langchain_emb_tsv | GIN | document_tsv |

### 複合インデックス

| テーブル | インデックス名 | カラム | 用途 |
|---------|--------------|--------|------|
| documents | idx_documents_tenant_kb | tenant_id, knowledge_base_id | テナント別KB検索 |
| documents | idx_documents_tenant_dept_conf | tenant_id, department, confidentiality | アクセス制御フィルタ |
| langchain_pg_embedding | idx_langchain_emb_tenant_kb | tenant_id, (cmetadata->>'knowledge_base_id') | テナント別ベクトル検索 |
| document_fulltext | idx_document_fulltext_filters | tenant_id, knowledge_base_id, collection_id | 全文検索フィルタ |

### パーシャルインデックス

| テーブル | インデックス名 | 条件 | 用途 |
|---------|--------------|------|------|
| tenants | idx_tenants_active | WHERE is_active = true | アクティブテナントのみ |
| documents | idx_documents_processed | WHERE status = 'processed' | 処理済みドキュメント |
| documents | idx_documents_edited | WHERE edited_metadata IS NOT NULL | 編集済みメタデータ |
| document_fulltext | idx_document_fulltext_nonempty | WHERE content_length > 0 | 空でないチャンク |

### JSONB GINインデックス

| テーブル | インデックス名 | カラム | 用途 |
|---------|--------------|--------|------|
| documents | idx_documents_edited_metadata_gin | edited_metadata | メタデータ検索 |
| knowledge_bases | idx_kb_search_settings_gin | meta_summary | KB設定検索 |
| tenants | idx_tenants_settings_gin | settings | テナント設定検索 |

## 外部キー制約

### CASCADE削除チェーン

```
tenants (削除)
  ↓ CASCADE
knowledge_bases (削除)
  ↓ CASCADE
├─ knowledge_bases_summary_embedding (削除)
├─ collections (削除)
│    ↓ CASCADE
│    ├─ collections_summary_embedding (削除)
│    └─ documents (削除)
│         ↓ CASCADE
│         ├─ document_fulltext (削除)
│         └─ langchain_pg_embedding (削除)
└─ documents (削除)
```

### SET NULL参照

| 子テーブル | 親テーブル | 削除時動作 |
|-----------|----------|-----------|
| knowledge_bases | prompt_templates | SET NULL |
| documents | collections | CASCADE |

## ベクトル次元の統一

全ベクトルカラムは**1024次元**で統一されています：

| テーブル | カラム | 次元数 | モデル |
|---------|-------|-------|-------|
| knowledge_bases_summary_embedding | summary_embedding | 1024 | bge-m3:567m |
| collections_summary_embedding | summary_embedding | 1024 | bge-m3:567m |
| documents | centroid_embedding | 1024 | bge-m3:567m |
| langchain_pg_embedding | embedding | 1024 | bge-m3:567m |

**注意**: bge-m3:567mモデルは1024次元ベクトルを出力し、多言語（日本語・英語・中国語等）に対応した高精度Retrievalモデルです。

## ストレージ見積もり

### ベクトルデータサイズ

```
ベクトル1個: 1024次元 × 4バイト（float32） = 4KB
チャンク100万個: 4KB × 1,000,000 = 4GB
KB要約1000個: 4KB × 1,000 = 4MB
Collection要約10,000個: 4KB × 10,000 = 40MB
Document重心100万個: 4KB × 1,000,000 = 4GB

合計: 約8GB（インデックス除く）
```

### HNSWインデックスサイズ

```
HNSW overhead: ベクトルデータの約1.5倍
langchain_pg_embedding: 4GB × 1.5 = 6GB
documents centroid: 4GB × 1.5 = 6GB
KB summary: 4MB × 1.5 = 6MB
Collection summary: 40MB × 1.5 = 60MB

合計: 約12GB
```

## パフォーマンス特性

### クエリパターン別インデックス使用

| クエリパターン | 使用インデックス | 期待レイテンシ |
|--------------|---------------|--------------|
| Atlas層KB選択 | idx_kb_summary_emb_hnsw | <50ms |
| Atlas層Collection選択 | idx_coll_summary_emb_hnsw | <30ms |
| Sparse検索（PGroonga） | idx_document_fulltext_pgroonga | <200ms |
| Dense検索（HNSW） | idx_langchain_pg_embedding_hnsw | <300ms |
| テナントフィルタ | idx_documents_tenant_kb | <10ms |
| 機密レベルフィルタ | idx_documents_tenant_dept_conf | <10ms |

## メンテナンス操作

### インデックス再構築

```sql
-- HNSWインデックス再構築（CONCURRENTLY推奨）
REINDEX INDEX CONCURRENTLY idx_kb_summary_emb_hnsw;
REINDEX INDEX CONCURRENTLY idx_coll_summary_emb_hnsw;
REINDEX INDEX CONCURRENTLY idx_documents_centroid_hnsw;
REINDEX INDEX CONCURRENTLY idx_langchain_pg_embedding_hnsw;

-- GINインデックス再構築
REINDEX INDEX CONCURRENTLY idx_document_fulltext_gin;
REINDEX INDEX CONCURRENTLY idx_langchain_emb_tsv;

-- VACUUM FULL（ディスク領域回収）
VACUUM FULL document_fulltext;
VACUUM FULL langchain_pg_embedding;

-- 統計情報更新
ANALYZE knowledge_bases_summary_embedding;
ANALYZE collections_summary_embedding;
ANALYZE documents;
ANALYZE document_fulltext;
ANALYZE langchain_pg_embedding;

-- マテリアライズドビュー更新
REFRESH MATERIALIZED VIEW atlas_layer_statistics;
REFRESH MATERIALIZED VIEW sparse_search_statistics;
REFRESH MATERIALIZED VIEW dense_search_statistics;
```

## 関連ドキュメント

- [../01-architecture.md](../01-architecture.md) - 7段階パイプライン全体像
- [../02-atlas-layer.md](../02-atlas-layer.md) - Atlas層詳細設計
- [../03-sparse-layer.md](../03-sparse-layer.md) - スパース層詳細設計
- [../04-dense-layer.md](../04-dense-layer.md) - Dense層詳細設計
- [update-triggers.md](./update-triggers.md) - 更新タイミングフロー図
