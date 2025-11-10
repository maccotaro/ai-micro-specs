# Sparse層設計（全文検索・BM25）

## 概要

Sparse層は、Stage 3Aとして機能するキーワードベースの全文検索層です。PostgreSQL標準FTS（Full-Text Search）とBM25スコアリングを用いて、語彙マッチングによる高精度な検索を実現します。Dense層（ベクトル検索）と組み合わせることで、ハイブリッド検索の精度を大幅に向上させます。

## 設計目標

### 1. 高精度キーワード検索

- **目的**: 固有名詞、専門用語、数値など語彙マッチングが有効なクエリに対応
- **手法**: PostgreSQL標準FTS + BM25スコアリング
- **目標精度**: キーワードクエリで90%+ Precision@10

### 2. 日本語対応

- **課題**: PostgreSQL標準FTSは日本語トークン化に弱い
- **対応**: PGroonga導入を推奨（未インストール環境では標準FTSで代替）
- **トークナイザー**: simple（標準FTS）/ TokenMecab（PGroonga）

### 3. スケーラビリティ

- **処理速度**: <200ms（100万チャンク環境）
- **インデックス**: GIN（標準FTS）/ PGroongaインデックス
- **テナント分離**: tenant_id フィルタで複数テナント対応

## データベーススキーマ

### document_fulltext テーブル

```sql
CREATE TABLE document_fulltext (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    content_length INTEGER GENERATED ALWAYS AS (LENGTH(content)) STORED,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    knowledge_base_id UUID NOT NULL,
    collection_id UUID NOT NULL,
    term_frequency JSONB,
    bm25_score_cache NUMERIC(10,4),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_doc_chunk UNIQUE (document_id, chunk_index)
);

-- GINインデックス（PostgreSQL標準FTS）
CREATE INDEX idx_document_fulltext_gin
ON document_fulltext
USING gin(to_tsvector('simple', content));

-- PGroongaインデックス（日本語形態素解析）
-- PGroonga未インストール環境ではスキップ
CREATE INDEX idx_document_fulltext_pgroonga
ON document_fulltext
USING pgroonga(content)
WITH (tokenizer='TokenMecab');

-- 複合インデックス（テナント・KB・Collection フィルタ）
CREATE INDEX idx_document_fulltext_filters
ON document_fulltext (tenant_id, knowledge_base_id, collection_id);

-- パーシャルインデックス（content_length > 0）
CREATE INDEX idx_document_fulltext_nonempty
ON document_fulltext (document_id, chunk_index)
WHERE content_length > 0;
```

### langchain_pg_embedding.document_tsv カラム追加

標準FTS用のtsvectorカラムを追加します。

```sql
ALTER TABLE langchain_pg_embedding
ADD COLUMN document_tsv tsvector
GENERATED ALWAYS AS (to_tsvector('simple', document)) STORED;

-- GINインデックス
CREATE INDEX idx_langchain_emb_tsv
ON langchain_pg_embedding
USING gin(document_tsv);
```

## BM25スコアリング

### BM25アルゴリズム

```
BM25(D, Q) = Σ [IDF(qi) × (f(qi, D) × (k1 + 1)) / (f(qi, D) + k1 × (1 - b + b × |D| / avgdl))]

D: ドキュメント
Q: クエリ
qi: クエリ内のi番目の単語
f(qi, D): ドキュメントD内の単語qiの出現頻度
|D|: ドキュメントの長さ
avgdl: コーパス全体の平均ドキュメント長
k1: タームフリーケンシー飽和パラメータ（デフォルト: 1.5）
b: 文書長正規化パラメータ（デフォルト: 0.75）
IDF(qi): 逆文書頻度
```

### IDF計算関数

```sql
CREATE OR REPLACE FUNCTION calculate_bm25_idf(
    term TEXT,
    tenant_id UUID
) RETURNS NUMERIC AS $$
DECLARE
    total_docs BIGINT;
    docs_with_term BIGINT;
    idf NUMERIC;
BEGIN
    -- 総ドキュメント数
    SELECT COUNT(DISTINCT document_id)
    INTO total_docs
    FROM document_fulltext
    WHERE tenant_id = $2;

    -- termを含むドキュメント数
    SELECT COUNT(DISTINCT document_id)
    INTO docs_with_term
    FROM document_fulltext
    WHERE tenant_id = $2
      AND to_tsvector('simple', content) @@ plainto_tsquery('simple', term);

    -- IDF = log((N - n + 0.5) / (n + 0.5) + 1)
    idf := LN((total_docs - docs_with_term + 0.5) / (docs_with_term + 0.5) + 1.0);

    RETURN idf;
END;
$$ LANGUAGE plpgsql;
```

### BM25スコア計算関数

```sql
CREATE OR REPLACE FUNCTION calculate_bm25_score(
    doc_content TEXT,
    query_text TEXT,
    k1 NUMERIC DEFAULT 1.5,
    b NUMERIC DEFAULT 0.75,
    avgdl NUMERIC DEFAULT 500.0
) RETURNS NUMERIC AS $$
DECLARE
    doc_length INTEGER;
    term TEXT;
    term_freq INTEGER;
    idf NUMERIC;
    bm25_score NUMERIC := 0.0;
BEGIN
    doc_length := LENGTH(doc_content);

    -- クエリを単語に分割（簡易実装）
    FOR term IN SELECT unnest(string_to_array(query_text, ' '))
    LOOP
        -- ドキュメント内のterm出現回数
        term_freq := (SELECT COUNT(*)
                      FROM regexp_matches(doc_content, term, 'gi'));

        -- IDF計算（簡易: log(1 + 1) = 0.693）
        idf := LN(2.0);

        -- BM25スコア加算
        bm25_score := bm25_score +
            (idf * (term_freq * (k1 + 1.0)) /
             (term_freq + k1 * (1.0 - b + b * doc_length / avgdl)));
    END LOOP;

    RETURN bm25_score;
END;
$$ LANGUAGE plpgsql;
```

## 検索処理

### PostgreSQL標準FTS検索

```python
async def sparse_search_fts(
    query: str,
    tenant_id: UUID,
    kb_ids: List[UUID],
    collection_ids: List[UUID],
    top_k: int = 500
) -> List[Tuple[UUID, int, float]]:
    """PostgreSQL標準FTSで全文検索"""
    results = await db.execute("""
        SELECT df.document_id,
               df.chunk_index,
               ts_rank(to_tsvector('simple', df.content),
                       plainto_tsquery('simple', :query)) AS bm25_score
        FROM document_fulltext df
        WHERE df.tenant_id = :tenant_id
          AND df.knowledge_base_id = ANY(:kb_ids)
          AND df.collection_id = ANY(:collection_ids)
          AND to_tsvector('simple', df.content) @@ plainto_tsquery('simple', :query)
        ORDER BY bm25_score DESC
        LIMIT :top_k
    """, {
        "query": query,
        "tenant_id": tenant_id,
        "kb_ids": kb_ids,
        "collection_ids": collection_ids,
        "top_k": top_k
    })

    return [(row.document_id, row.chunk_index, float(row.bm25_score))
            for row in results]
```

### PGroonga検索（推奨）

```python
async def sparse_search_pgroonga(
    query: str,
    tenant_id: UUID,
    kb_ids: List[UUID],
    collection_ids: List[UUID],
    top_k: int = 500
) -> List[Tuple[UUID, int, float]]:
    """PGroonga全文検索（日本語形態素解析対応）"""
    results = await db.execute("""
        SELECT df.document_id,
               df.chunk_index,
               pgroonga_score(tableoid, ctid) AS relevance_score
        FROM document_fulltext df
        WHERE df.tenant_id = :tenant_id
          AND df.knowledge_base_id = ANY(:kb_ids)
          AND df.collection_id = ANY(:collection_ids)
          AND df.content &@~ :query
        ORDER BY pgroonga_score(tableoid, ctid) DESC
        LIMIT :top_k
    """, {
        "query": query,
        "tenant_id": tenant_id,
        "kb_ids": kb_ids,
        "collection_ids": collection_ids,
        "top_k": top_k
    })

    return [(row.document_id, row.chunk_index, float(row.relevance_score))
            for row in results]
```

## データ投入処理

### ドキュメント処理完了時のインデックス

```python
async def index_document_chunks(document_id: UUID):
    """ドキュメント処理完了後にSparse層にインデックス"""
    # 1. ドキュメント情報取得
    doc = await db.get_document(document_id)

    # 2. チャンク取得
    chunks = await db.execute("""
        SELECT uuid, document, cmetadata
        FROM langchain_pg_embedding
        WHERE document_id = :doc_id
        ORDER BY (cmetadata->>'chunk_index')::integer
    """, {"doc_id": document_id})

    # 3. document_fulltextに挿入
    for chunk in chunks:
        chunk_index = chunk.cmetadata.get('chunk_index', 0)

        await db.execute("""
            INSERT INTO document_fulltext
            (document_id, chunk_index, content, tenant_id,
             knowledge_base_id, collection_id)
            VALUES (:doc_id, :chunk_idx, :content, :tenant_id,
                    :kb_id, :coll_id)
            ON CONFLICT (document_id, chunk_index) DO UPDATE
            SET content = EXCLUDED.content
        """, {
            "doc_id": document_id,
            "chunk_idx": chunk_index,
            "content": chunk.document,
            "tenant_id": doc.tenant_id,
            "kb_id": doc.knowledge_base_id,
            "coll_id": doc.collection_id
        })
```

## パフォーマンスチューニング

### GINインデックス最適化

```sql
-- メンテナンス作業設定の調整
ALTER INDEX idx_document_fulltext_gin SET (fastupdate = off);

-- インデックス再構築
REINDEX INDEX CONCURRENTLY idx_document_fulltext_gin;

-- 統計情報更新
ANALYZE document_fulltext;
```

### PGroongaパラメータ調整

```sql
-- TokenMecabオプション設定
CREATE INDEX idx_document_fulltext_pgroonga_optimized
ON document_fulltext
USING pgroonga(content)
WITH (tokenizer='TokenMecab',
      normalizer='NormalizerNFKC130("unify_kana", true)');
```

## 統計ビュー

```sql
CREATE MATERIALIZED VIEW sparse_search_statistics AS
SELECT
    tenant_id,
    knowledge_base_id,
    COUNT(*) AS total_chunks,
    AVG(content_length) AS avg_chunk_length,
    MAX(content_length) AS max_chunk_length,
    MIN(content_length) AS min_chunk_length,
    SUM(content_length) AS total_content_length
FROM document_fulltext
GROUP BY tenant_id, knowledge_base_id;

-- 定期更新
REFRESH MATERIALIZED VIEW sparse_search_statistics;
```

## トラブルシューティング

### 問題1: 日本語検索が不正確

**原因**: PostgreSQL標準FTSは日本語トークン化に弱い

**解決策**: PGroonga導入

```bash
# PGroongaインストール（Debian/Ubuntu）
sudo apt-get install postgresql-16-pgroonga

# PostgreSQLでPGroonga拡張を有効化
psql -U postgres -d admindb -c "CREATE EXTENSION pgroonga;"
```

### 問題2: 検索速度が遅い

**原因**: GINインデックスが未構築、またはインデックスが肥大化

**確認**:

```sql
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename = 'document_fulltext';
```

**解決策**: インデックス再構築、VACUUM FULL実行

### 問題3: BM25スコアが低すぎる

**原因**: クエリトークン化の失敗、またはk1/bパラメータ不適切

**解決策**: トークナイザー変更、パラメータ調整（k1: 1.2-2.0, b: 0.5-0.9）

## 関連ドキュメント

- [01-architecture.md](./01-architecture.md) - 7段階パイプライン全体像
- [02-atlas-layer.md](./02-atlas-layer.md) - Atlas層詳細設計
- [04-dense-layer.md](./04-dense-layer.md) - Dense層詳細設計
- [05-hybrid-search.md](./05-hybrid-search.md) - ハイブリッド検索（RRF統合）
