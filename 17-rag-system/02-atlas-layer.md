# Atlas層設計

## 概要

Atlas層は、エンタープライズRAGシステムの第1段階（Stage 1）として機能する事前フィルタリング層です。ナレッジベース/コレクション全体の要約ベクトルを用いて、クエリと関連性の高いKB/Collectionを高速に選別することで、後続のSparse/Dense検索の効率を大幅に向上させます。

## 設計目標

### 1. 検索効率の向上

- **問題**: 数百個のKB、数千個のCollectionから全チャンク検索は非効率
- **解決策**: KB/Collection要約ベクトルでトップ2-3件に事前絞り込み
- **効果**: 検索対象チャンク数を1/10～1/100に削減

### 2. 検索精度の維持

- **課題**: 事前フィルタリングで関連KBを見逃すリスク
- **対策**: 要約ベクトルの精度向上、閾値調整、複数KBの選択
- **目標精度**: 95%+（関連KBを見逃さない）

### 3. スケーラビリティ

- **処理速度**: <50ms（10,000KB環境）
- **インデックス**: HNSW（m=16, ef_construction=64）
- **バージョン管理**: 古いembeddingを無効化せずにバージョン管理

## データベーススキーマ

### knowledge_bases_summary_embedding

KB全体の要約embeddingを管理します。

```sql
CREATE TABLE knowledge_bases_summary_embedding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_base_id UUID NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    summary_text TEXT NOT NULL,
    summary_embedding vector(1024) NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    total_documents INTEGER NOT NULL DEFAULT 0,
    total_chunks INTEGER NOT NULL DEFAULT 0,
    avg_document_length INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_kb_active_version UNIQUE (knowledge_base_id, is_active)
        WHERE is_active = true
);

-- HNSWインデックス（高速ベクトル検索）
CREATE INDEX idx_kb_summary_emb_hnsw
ON knowledge_bases_summary_embedding
USING hnsw (summary_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- IVFFlatインデックス（フォールバック）
CREATE INDEX idx_kb_summary_emb_ivfflat
ON knowledge_bases_summary_embedding
USING ivfflat (summary_embedding vector_cosine_ops)
WITH (lists = 100);

-- 検索高速化用インデックス
CREATE INDEX idx_kb_summary_emb_active
ON knowledge_bases_summary_embedding (knowledge_base_id, is_active)
WHERE is_active = true;
```

### collections_summary_embedding

Collection単位の要約embeddingを管理します。

```sql
CREATE TABLE collections_summary_embedding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    summary_text TEXT NOT NULL,
    summary_embedding vector(1024) NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    total_documents INTEGER NOT NULL DEFAULT 0,
    total_chunks INTEGER NOT NULL DEFAULT 0,
    avg_chunk_length INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_coll_active_version UNIQUE (collection_id, is_active)
        WHERE is_active = true
);

-- HNSWインデックス
CREATE INDEX idx_coll_summary_emb_hnsw
ON collections_summary_embedding
USING hnsw (summary_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- IVFFlatインデックス
CREATE INDEX idx_coll_summary_emb_ivfflat
ON collections_summary_embedding
USING ivfflat (summary_embedding vector_cosine_ops)
WITH (lists = 100);

-- 検索高速化用インデックス
CREATE INDEX idx_coll_summary_emb_active
ON collections_summary_embedding (collection_id, is_active)
WHERE is_active = true;
```

### documents.centroid_embedding

ドキュメント単位の重心embeddingを管理します（documentsテーブルのカラムとして追加）。

```sql
ALTER TABLE documents
ADD COLUMN centroid_embedding vector(1024);

-- HNSWインデックス
CREATE INDEX idx_documents_centroid_hnsw
ON documents
USING hnsw (centroid_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
WHERE centroid_embedding IS NOT NULL;

-- IVFFlatインデックス
CREATE INDEX idx_documents_centroid_ivfflat
ON documents
USING ivfflat (centroid_embedding vector_cosine_ops)
WITH (lists = 100)
WHERE centroid_embedding IS NOT NULL;
```

## 更新タイミング

### 1. KB要約の生成・更新

#### トリガー: ドキュメント追加/削除時

```sql
CREATE OR REPLACE FUNCTION mark_kb_summary_for_regeneration()
RETURNS TRIGGER AS $$
BEGIN
    -- 関連するKB要約を非アクティブ化
    UPDATE knowledge_bases_summary_embedding
    SET is_active = false
    WHERE knowledge_base_id = COALESCE(NEW.knowledge_base_id, OLD.knowledge_base_id)
      AND is_active = true;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mark_kb_summary_for_regen
AFTER INSERT OR DELETE ON documents
FOR EACH ROW
EXECUTE FUNCTION mark_kb_summary_for_regeneration();
```

#### バックグラウンドジョブ: 要約生成

**実行タイミング**: 5分ごと（cron）

**処理フロー**:

```python
async def regenerate_kb_summaries():
    # 非アクティブなKBを取得
    kbs_to_update = await db.execute("""
        SELECT DISTINCT kb.id, kb.name, kb.description
        FROM knowledge_bases kb
        LEFT JOIN knowledge_bases_summary_embedding kbse
            ON kb.id = kbse.knowledge_base_id AND kbse.is_active = true
        WHERE kbse.id IS NULL  -- is_active=trueの要約が存在しない
    """)

    for kb in kbs_to_update:
        # 1. KB内の全ドキュメント情報を取得
        docs = await db.execute("""
            SELECT filename, original_metadata->>'title' AS title,
                   original_metadata->>'summary' AS summary
            FROM documents
            WHERE knowledge_base_id = :kb_id
              AND status = 'processed'
            LIMIT 100
        """, {"kb_id": kb.id})

        # 2. LLMで要約テキスト生成（300-500文字）
        summary_text = await llm.generate_summary(
            kb_name=kb.name,
            kb_description=kb.description,
            documents=docs
        )

        # 3. 要約テキストをベクトル化（bge-m3:567m）
        summary_vector = await embedding_model.encode(summary_text)

        # 4. 統計情報計算
        stats = await db.execute("""
            SELECT COUNT(*) AS total_docs,
                   SUM(chunk_count) AS total_chunks,
                   AVG(LENGTH(original_metadata->>'text')) AS avg_length
            FROM documents
            WHERE knowledge_base_id = :kb_id
              AND status = 'processed'
        """, {"kb_id": kb.id})

        # 5. 新しいバージョンとして挿入
        await db.execute("""
            INSERT INTO knowledge_bases_summary_embedding
            (knowledge_base_id, summary_text, summary_embedding,
             version, is_active, total_documents, total_chunks, avg_document_length)
            VALUES (:kb_id, :summary_text, :summary_vector,
                    COALESCE((SELECT MAX(version) FROM knowledge_bases_summary_embedding
                              WHERE knowledge_base_id = :kb_id), 0) + 1,
                    true, :total_docs, :total_chunks, :avg_length)
        """, {
            "kb_id": kb.id,
            "summary_text": summary_text,
            "summary_vector": summary_vector,
            "total_docs": stats.total_docs,
            "total_chunks": stats.total_chunks,
            "avg_length": stats.avg_length
        })
```

### 2. Collection要約の生成・更新

**実行タイミング**: Collection作成時、ドキュメント追加/削除時

**処理フロー**:

```python
async def regenerate_collection_summary(collection_id: UUID):
    # Collection情報取得
    collection = await db.get_collection(collection_id)

    # Collection内のドキュメント取得
    docs = await db.execute("""
        SELECT filename, original_metadata
        FROM documents
        WHERE collection_id = :coll_id
          AND status = 'processed'
        LIMIT 100
    """, {"coll_id": collection_id})

    # LLMで要約生成
    summary_text = await llm.generate_summary(
        collection_name=collection.name,
        collection_description=collection.description,
        documents=docs
    )

    # ベクトル化（bge-m3:567m）
    summary_vector = await embedding_model.encode(summary_text)

    # 統計情報
    stats = await db.execute("""
        SELECT COUNT(*) AS total_docs,
               SUM(chunk_count) AS total_chunks,
               AVG(LENGTH(original_metadata->>'text')) AS avg_length
        FROM documents
        WHERE collection_id = :coll_id
          AND status = 'processed'
    """, {"coll_id": collection_id})

    # 既存の要約を非アクティブ化
    await db.execute("""
        UPDATE collections_summary_embedding
        SET is_active = false
        WHERE collection_id = :coll_id
          AND is_active = true
    """, {"coll_id": collection_id})

    # 新しいバージョン挿入
    await db.execute("""
        INSERT INTO collections_summary_embedding
        (collection_id, summary_text, summary_embedding,
         version, is_active, total_documents, total_chunks, avg_chunk_length)
        VALUES (:coll_id, :summary_text, :summary_vector,
                COALESCE((SELECT MAX(version) FROM collections_summary_embedding
                          WHERE collection_id = :coll_id), 0) + 1,
                true, :total_docs, :total_chunks, :avg_length)
    """, {
        "coll_id": collection_id,
        "summary_text": summary_text,
        "summary_vector": summary_vector,
        "total_docs": stats.total_docs,
        "total_chunks": stats.total_chunks,
        "avg_length": stats.avg_length
    })
```

### 3. Document Centroid（重心）の生成・更新

**実行タイミング**: ドキュメント処理完了時（RAG変換後）

**処理フロー**:

```python
async def calculate_document_centroid(document_id: UUID):
    # ドキュメントの全チャンクembedding取得
    embeddings = await db.execute("""
        SELECT embedding
        FROM langchain_pg_embedding
        WHERE document_id = :doc_id
    """, {"doc_id": document_id})

    if not embeddings:
        return

    # 平均ベクトル計算（重心）
    centroid = np.mean([emb for emb in embeddings], axis=0)

    # documentsテーブルに保存
    await db.execute("""
        UPDATE documents
        SET centroid_embedding = :centroid
        WHERE id = :doc_id
    """, {"doc_id": document_id, "centroid": centroid.tolist()})
```

## 検索処理

### Stage 1: KB選択

```python
async def filter_knowledge_bases(
    query_vector: np.ndarray,
    tenant_id: UUID,
    top_k: int = 3,
    threshold: float = 0.7
) -> List[UUID]:
    results = await db.execute("""
        SELECT kb.id, kb.name,
               1 - (kbse.summary_embedding <=> :query_vector) AS similarity
        FROM knowledge_bases kb
        JOIN knowledge_bases_summary_embedding kbse
            ON kb.id = kbse.knowledge_base_id
        WHERE kbse.is_active = true
          AND kb.tenant_id = :tenant_id
          AND 1 - (kbse.summary_embedding <=> :query_vector) >= :threshold
        ORDER BY kbse.summary_embedding <=> :query_vector
        LIMIT :top_k
    """, {
        "query_vector": query_vector.tolist(),
        "tenant_id": tenant_id,
        "threshold": threshold,
        "top_k": top_k
    })

    return [row.id for row in results]
```

### Stage 1.5: Collection選択

```python
async def filter_collections(
    query_vector: np.ndarray,
    kb_ids: List[UUID],
    top_k: int = 5,
    threshold: float = 0.6
) -> List[UUID]:
    results = await db.execute("""
        SELECT c.id, c.name,
               1 - (cse.summary_embedding <=> :query_vector) AS similarity
        FROM collections c
        JOIN collections_summary_embedding cse
            ON c.id = cse.collection_id
        WHERE cse.is_active = true
          AND c.knowledge_base_id = ANY(:kb_ids)
          AND 1 - (cse.summary_embedding <=> :query_vector) >= :threshold
        ORDER BY cse.summary_embedding <=> :query_vector
        LIMIT :top_k
    """, {
        "query_vector": query_vector.tolist(),
        "kb_ids": kb_ids,
        "threshold": threshold,
        "top_k": top_k
    })

    return [row.id for row in results]
```

## パフォーマンスチューニング

### HNSWパラメータ調整

**m（最大接続数）**:

- デフォルト: 16
- 大規模環境（10,000+ KB）: 32
- トレードオフ: 精度↑、メモリ使用量↑

**ef_construction（構築時探索深さ）**:

- デフォルト: 64
- 高精度環境: 128
- トレードオフ: 精度↑、インデックス構築時間↑

**ef_search（検索時探索深さ）**:

```sql
SET hnsw.ef_search = 128;  -- デフォルト: 40
```

### インデックス再構築

```sql
-- HNSWインデックス再構築
REINDEX INDEX CONCURRENTLY idx_kb_summary_emb_hnsw;
REINDEX INDEX CONCURRENTLY idx_coll_summary_emb_hnsw;
REINDEX INDEX CONCURRENTLY idx_documents_centroid_hnsw;
```

## 監視・メトリクス

### 主要メトリクス

```sql
-- Atlas層統計ビュー
CREATE MATERIALIZED VIEW atlas_layer_statistics AS
SELECT
    kb.id AS knowledge_base_id,
    kb.name AS knowledge_base_name,
    kbse.version AS summary_version,
    kbse.total_documents,
    kbse.total_chunks,
    kbse.avg_document_length,
    kbse.created_at AS summary_created_at,
    COUNT(cse.id) AS collection_count,
    SUM(cse.total_documents) AS total_collection_documents
FROM knowledge_bases kb
LEFT JOIN knowledge_bases_summary_embedding kbse
    ON kb.id = kbse.knowledge_base_id AND kbse.is_active = true
LEFT JOIN collections c
    ON kb.id = c.knowledge_base_id
LEFT JOIN collections_summary_embedding cse
    ON c.id = cse.collection_id AND cse.is_active = true
GROUP BY kb.id, kb.name, kbse.version, kbse.total_documents,
         kbse.total_chunks, kbse.avg_document_length, kbse.created_at;

-- 手動更新
REFRESH MATERIALIZED VIEW atlas_layer_statistics;
```

### パフォーマンス分析

```sql
-- KB要約検索の平均レイテンシ
SELECT AVG(execution_time_ms) AS avg_latency_ms
FROM rag_audit_logs
WHERE atlas_stage->>'status' = 'success'
  AND created_at >= NOW() - INTERVAL '1 day';

-- Atlas層フィルタ精度（関連KBの見逃し率）
SELECT
    COUNT(*) FILTER (WHERE atlas_stage->>'filtered_kb_count' = '0') AS no_match_count,
    COUNT(*) AS total_queries,
    ROUND(100.0 * COUNT(*) FILTER (WHERE atlas_stage->>'filtered_kb_count' = '0') / COUNT(*), 2) AS miss_rate_pct
FROM rag_audit_logs
WHERE created_at >= NOW() - INTERVAL '7 days';
```

## トラブルシューティング

### 問題1: 要約が生成されない

**原因**: トリガーが無効化されている、またはバックグラウンドジョブが停止

**確認方法**:

```sql
SELECT * FROM pg_trigger WHERE tgname = 'trg_mark_kb_summary_for_regen';
```

**解決策**: トリガー再作成、ジョブ再起動

### 問題2: 検索精度が低い

**原因**: 要約テキストの品質が低い、閾値が高すぎる

**確認方法**:

```sql
SELECT kb.name, kbse.summary_text
FROM knowledge_bases kb
JOIN knowledge_bases_summary_embedding kbse ON kb.id = kbse.knowledge_base_id
WHERE kbse.is_active = true
LIMIT 10;
```

**解決策**: LLMプロンプト改善、閾値調整（0.7 → 0.6）

### 問題3: 検索速度が遅い

**原因**: HNSWインデックスが未構築、またはef_searchが小さすぎる

**確認方法**:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'knowledge_bases_summary_embedding';
```

**解決策**: HNSWインデックス構築、ef_search増加

## 関連ドキュメント

- [01-architecture.md](./01-architecture.md) - 7段階パイプライン全体像
- [03-sparse-layer.md](./03-sparse-layer.md) - スパース層詳細設計
- [04-dense-layer.md](./04-dense-layer.md) - Dense層詳細設計
- [diagrams/update-triggers.md](./diagrams/update-triggers.md) - 更新タイミングフロー図
