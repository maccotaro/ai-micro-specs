# Dense層設計（ベクトル検索）

## 概要

Dense層は、Stage 3Bとして機能する意味ベースのベクトル検索層です。PGVectorとHNSWインデックスを用いた高速なコサイン類似度検索により、クエリと意味的に類似したチャンクを検索します。Sparse層（キーワード検索）と組み合わせることで、ハイブリッド検索の精度を実現します。

## 設計目標

### 1. 高精度意味検索

- **目的**: 言い換え、類義語、概念的な類似性に対応
- **手法**: bge-m3:567m（1024次元ベクトル） + コサイン類似度
- **目標精度**: 意味検索で85%+ Recall@10

### 2. 高速ベクトル検索

- **処理速度**: <300ms（100万チャンク環境）
- **インデックス**: HNSW（m=16, ef_construction=64）
- **スケーラビリティ**: 1000万チャンクまで対応

### 3. ベクトル次元の統一

- **次元数**: 1024次元（全テーブル統一）
- **モデル**: bge-m3:567m（1024次元出力）
- **データ型**: PGVector vector(1024)

## データベーススキーマ

### langchain_pg_embedding テーブル

LangChainのPGVectorインテグレーションで使用されるテーブルです。

```sql
CREATE TABLE langchain_pg_embedding (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID REFERENCES langchain_pg_collection(uuid) ON DELETE CASCADE,
    embedding vector(1024) NOT NULL,
    document TEXT NOT NULL,
    cmetadata JSONB,

    -- Phase 1追加カラム
    document_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id),
    chunk_index INTEGER,

    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- HNSWインデックス（高速ベクトル検索）
CREATE INDEX idx_langchain_pg_embedding_hnsw
ON langchain_pg_embedding
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- IVFFlatインデックス（フォールバック）
CREATE INDEX idx_langchain_pg_embedding_ivfflat
ON langchain_pg_embedding
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 1000);

-- 複合インデックス（テナント + KB フィルタ）
CREATE INDEX idx_langchain_emb_tenant_kb
ON langchain_pg_embedding (tenant_id, (cmetadata->>'knowledge_base_id'));

-- 複合インデックス（ドキュメント + チャンク）
CREATE INDEX idx_langchain_emb_doc_chunk
ON langchain_pg_embedding (document_id, chunk_index);
```

### cmetadata JSONBフィールド構造

```json
{
  "document_id": "uuid",
  "knowledge_base_id": "uuid",
  "collection_id": "uuid",
  "chunk_index": 0,
  "page_number": 1,
  "element_id": "ID-1",
  "element_type": "text",
  "parent_id": null,
  "source_file": "document.pdf"
}
```

## ベクトル化処理

### bge-m3モデル

**モデル**: `bge-m3:567m`

- 入力: テキスト（最大512トークン）
- 出力: 1024次元ベクトル
- 実行環境: Ollama（CPU/GPU）
- 推論速度: ~50ms/chunk（GPU）、~200ms/chunk（CPU）
- 特徴: 多言語対応（日本語・英語・中国語等）、高精度Retrieval

### ドキュメント処理完了時のベクトル化

```python
async def vectorize_document_chunks(document_id: UUID):
    """ドキュメント処理完了後にチャンクをベクトル化"""
    # 1. ドキュメント情報取得
    doc = await db.get_document(document_id)

    # 2. 階層構造からチャンク取得
    hierarchical_elements = doc.original_metadata.get('hierarchical_elements', [])
    chunks = extract_chunks_from_hierarchy(hierarchical_elements)

    # 3. LangChain PGVectorに追加
    from langchain.vectorstores import PGVector

    embeddings = OllamaEmbeddings(
        model="bge-m3:567m",
        base_url="http://ollama:11434"
    )

    vectorstore = PGVector(
        collection_name=str(doc.collection_id),
        connection_string=settings.DATABASE_URL,
        embedding_function=embeddings
    )

    # 4. メタデータ付きでベクトル追加
    texts = [chunk['content'] for chunk in chunks]
    metadatas = [{
        'document_id': str(document_id),
        'knowledge_base_id': str(doc.knowledge_base_id),
        'collection_id': str(doc.collection_id),
        'chunk_index': i,
        'page_number': chunk.get('page_number', 1),
        'element_id': chunk.get('element_id'),
        'element_type': chunk.get('element_type', 'text')
    } for i, chunk in enumerate(chunks)]

    await vectorstore.aadd_texts(texts=texts, metadatas=metadatas)

    # 5. document_idカラムの同期（トリガーで自動実行）
    # トリガー: sync_embedding_document_id()
```

### document_id同期トリガー

```sql
CREATE OR REPLACE FUNCTION sync_embedding_document_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.cmetadata ? 'document_id' THEN
        BEGIN
            NEW.document_id := (NEW.cmetadata->>'document_id')::uuid;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to sync document_id: %', SQLERRM;
            NEW.document_id := NULL;
        END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_embedding_document_id
    BEFORE INSERT OR UPDATE ON langchain_pg_embedding
    FOR EACH ROW
    EXECUTE FUNCTION sync_embedding_document_id();
```

## 検索処理

### ベクトル類似度検索

```python
async def dense_search(
    query_vector: np.ndarray,
    tenant_id: UUID,
    kb_ids: List[UUID],
    collection_ids: List[UUID],
    top_k: int = 500
) -> List[Tuple[UUID, int, float]]:
    """PGVector HNSWインデックスで高速ベクトル検索"""
    # ef_search動的調整
    await db.execute("SET hnsw.ef_search = 128")

    results = await db.execute("""
        SELECT lpe.document_id,
               COALESCE(lpe.chunk_index, (lpe.cmetadata->>'chunk_index')::integer, 0) AS chunk_index,
               1 - (lpe.embedding <=> :query_vector) AS cosine_similarity
        FROM langchain_pg_embedding lpe
        WHERE lpe.tenant_id = :tenant_id
          AND lpe.document_id IN (
              SELECT d.id FROM documents d
              WHERE d.knowledge_base_id = ANY(:kb_ids)
                AND d.collection_id = ANY(:collection_ids)
          )
        ORDER BY lpe.embedding <=> :query_vector
        LIMIT :top_k
    """, {
        "query_vector": query_vector.tolist(),
        "tenant_id": tenant_id,
        "kb_ids": kb_ids,
        "collection_ids": collection_ids,
        "top_k": top_k
    })

    return [(row.document_id, row.chunk_index, float(row.cosine_similarity))
            for row in results]
```

### クエリベクトル生成

```python
async def generate_query_vector(query: str) -> np.ndarray:
    """クエリテキストをベクトル化"""
    embeddings = OllamaEmbeddings(
        model="bge-m3:567m",
        base_url="http://ollama:11434"
    )

    # LangChainのembed_queryメソッド使用
    query_vector = await embeddings.aembed_query(query)
    return np.array(query_vector)
```

## HNSWパラメータ最適化

### mパラメータ（最大接続数）

| 環境規模 | 推奨m | メモリ使用量 | 検索精度 |
|---------|------|-------------|---------|
| 小規模（~10万） | 16 | 低 | 標準 |
| 中規模（~100万） | 24 | 中 | 高 |
| 大規模（~1000万） | 32 | 高 | 最高 |

### ef_constructionパラメータ（構築時探索深さ）

| 環境 | 推奨ef_construction | 構築時間 | 検索精度 |
|------|---------------------|---------|---------|
| 開発 | 64 | 短 | 標準 |
| ステージング | 100 | 中 | 高 |
| 本番 | 128 | 長 | 最高 |

### ef_searchパラメータ（検索時探索深さ）

```sql
-- セッション単位で動的調整
SET hnsw.ef_search = 128;  -- デフォルト: 40

-- 高精度検索
SET hnsw.ef_search = 256;

-- 高速検索
SET hnsw.ef_search = 64;
```

## パフォーマンスチューニング

### インデックス再構築

```sql
-- HNSWインデックス再構築（CONCURRENTLY推奨）
REINDEX INDEX CONCURRENTLY idx_langchain_pg_embedding_hnsw;

-- IVFFlatインデックス再構築
REINDEX INDEX CONCURRENTLY idx_langchain_pg_embedding_ivfflat;

-- 統計情報更新
ANALYZE langchain_pg_embedding;
```

### PostgreSQL設定最適化

```ini
# postgresql.conf

# メモリ設定
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 2GB
work_mem = 256MB

# PGVector設定
max_parallel_workers_per_gather = 4
```

### ベクトル検索実行計画確認

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT lpe.document_id,
       1 - (lpe.embedding <=> '[0.1, 0.2, ..., 0.5]'::vector) AS similarity
FROM langchain_pg_embedding lpe
WHERE lpe.tenant_id = '00000000-0000-0000-0000-000000000000'
ORDER BY lpe.embedding <=> '[0.1, 0.2, ..., 0.5]'::vector
LIMIT 500;
```

## 監視・メトリクス

### Dense層統計ビュー

```sql
CREATE MATERIALIZED VIEW dense_search_statistics AS
SELECT
    tenant_id,
    (cmetadata->>'knowledge_base_id')::uuid AS knowledge_base_id,
    COUNT(*) AS total_embeddings,
    AVG(LENGTH(document)) AS avg_chunk_length,
    MAX(LENGTH(document)) AS max_chunk_length,
    MIN(LENGTH(document)) AS min_chunk_length,
    COUNT(DISTINCT document_id) AS total_documents
FROM langchain_pg_embedding
GROUP BY tenant_id, (cmetadata->>'knowledge_base_id')::uuid;

-- 定期更新
REFRESH MATERIALIZED VIEW dense_search_statistics;
```

### パフォーマンスクエリ

```sql
-- ベクトル検索平均レイテンシ
SELECT AVG((rag_audit_logs.dense_stage->>'execution_time_ms')::integer) AS avg_dense_latency_ms
FROM rag_audit_logs
WHERE dense_stage->>'status' = 'success'
  AND created_at >= NOW() - INTERVAL '1 day';

-- HNSWインデックス使用率
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE tablename = 'langchain_pg_embedding'
  AND indexname LIKE '%hnsw%';
```

## トラブルシューティング

### 問題1: 検索速度が遅い（>500ms）

**原因**: HNSWインデックス未構築、ef_searchが大きすぎる

**確認**:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'langchain_pg_embedding'
  AND indexdef LIKE '%hnsw%';
```

**解決策**: HNSWインデックス構築、ef_search調整（128 → 64）

### 問題2: 検索精度が低い

**原因**: embeddingモデルの品質、ベクトル次元不一致

**確認**:

```sql
SELECT MIN(vector_dims(embedding)) AS min_dims,
       MAX(vector_dims(embedding)) AS max_dims
FROM langchain_pg_embedding;
```

**解決策**: embeddingモデル変更、ベクトル次元統一（1024次元）

### 問題3: document_idがNULL

**原因**: トリガー未適用、cmetadata->>'document_id'不正

**確認**:

```sql
SELECT COUNT(*) AS null_count
FROM langchain_pg_embedding
WHERE cmetadata ? 'document_id' AND document_id IS NULL;
```

**解決策**: トリガー適用、既存データ修正

```sql
UPDATE langchain_pg_embedding
SET document_id = (cmetadata->>'document_id')::uuid
WHERE cmetadata ? 'document_id' AND document_id IS NULL;
```

## ベクトルモデルのアップグレード

### 新しいembeddingモデルへの移行

1. **新しいコレクション作成**

```python
new_collection_name = f"{old_collection_name}_v2"
new_vectorstore = PGVector(
    collection_name=new_collection_name,
    connection_string=settings.DATABASE_URL,
    embedding_function=new_embeddings_model
)
```

2. **既存チャンクの再ベクトル化**

```python
old_chunks = await db.execute("""
    SELECT document_id, chunk_index, document, cmetadata
    FROM langchain_pg_embedding
    WHERE collection_id = :old_collection_id
""", {"old_collection_id": old_collection_id})

for chunk in old_chunks:
    new_vector = await new_embeddings_model.aembed_query(chunk.document)
    await new_vectorstore.aadd_texts([chunk.document], [chunk.cmetadata])
```

3. **A/Bテスト実行**

4. **旧コレクション削除**

## 関連ドキュメント

- [01-architecture.md](./01-architecture.md) - 7段階パイプライン全体像
- [02-atlas-layer.md](./02-atlas-layer.md) - Atlas層詳細設計
- [03-sparse-layer.md](./03-sparse-layer.md) - スパース層詳細設計
- [05-hybrid-search.md](./05-hybrid-search.md) - ハイブリッド検索（RRF統合）
