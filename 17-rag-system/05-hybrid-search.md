# ハイブリッド検索設計（RRF統合）

## 概要

ハイブリッド検索は、Stage 4として機能するSparse層（キーワード検索）とDense層（ベクトル検索）の結果を統合する層です。RRF（Reciprocal Rank Fusion）アルゴリズムにより、両検索の長所を活かした高精度なランキングを実現します。

## 設計目標

### 1. 検索精度の向上

- **Sparse層の強み**: 固有名詞、専門用語、数値の正確なマッチング
- **Dense層の強み**: 言い換え、類義語、概念的類似性
- **ハイブリッドの効果**: 両方の長所を活かし、Recall/Precisionを向上

### 2. ランキングの最適化

- **RRFアルゴリズム**: 順位ベースの統合で安定したスコアリング
- **重み調整**: Sparse/Denseの重要度を調整可能
- **目標精度**: Recall@10: 85-90%, Precision@10: 90%+

### 3. 処理速度

- **レイテンシ**: <50ms（RRF計算のみ）
- **並列処理**: Sparse/Dense検索を並列実行
- **合計レイテンシ**: <600ms（Stage 1-4合計）

## RRFアルゴリズム

### 基本式

```
RRF_score(d) = Σ_r∈R [ 1 / (k + rank_r(d)) ]

d: ドキュメント
R: 検索手法の集合 {Sparse, Dense}
rank_r(d): 検索手法rにおけるドキュメントdの順位（1-indexed）
k: 定数（デフォルト: 60）
```

### 重み付きRRF

```
Weighted_RRF_score(d) = w_sparse × [1 / (k + rank_sparse(d))]
                      + w_dense × [1 / (k + rank_dense(d))]

w_sparse: Sparse層の重み（デフォルト: 0.5）
w_dense: Dense層の重み（デフォルト: 0.5）
```

## 実装

### Python実装

```python
from typing import List, Tuple, Dict
from collections import defaultdict
import numpy as np

class HybridRetriever:
    def __init__(
        self,
        k: int = 60,
        w_sparse: float = 0.5,
        w_dense: float = 0.5
    ):
        self.k = k
        self.w_sparse = w_sparse
        self.w_dense = w_dense

    def reciprocal_rank_fusion(
        self,
        sparse_results: List[Tuple[str, int, float]],
        dense_results: List[Tuple[str, int, float]]
    ) -> List[Tuple[str, int, float]]:
        """
        RRFアルゴリズムでSparse/Dense結果を統合

        Args:
            sparse_results: [(document_id, chunk_index, bm25_score), ...]
            dense_results: [(document_id, chunk_index, cosine_similarity), ...]

        Returns:
            [(document_id, chunk_index, rrf_score), ...] (降順ソート済み)
        """
        rrf_scores = defaultdict(float)
        doc_chunk_pairs = set()

        # Sparse結果のRRFスコア計算
        for rank, (doc_id, chunk_idx, score) in enumerate(sparse_results, start=1):
            key = f"{doc_id}:{chunk_idx}"
            rrf_scores[key] += self.w_sparse / (self.k + rank)
            doc_chunk_pairs.add((doc_id, chunk_idx))

        # Dense結果のRRFスコア計算
        for rank, (doc_id, chunk_idx, score) in enumerate(dense_results, start=1):
            key = f"{doc_id}:{chunk_idx}"
            rrf_scores[key] += self.w_dense / (self.k + rank)
            doc_chunk_pairs.add((doc_id, chunk_idx))

        # RRFスコア降順でソート
        sorted_results = sorted(
            rrf_scores.items(),
            key=lambda x: x[1],
            reverse=True
        )

        # (document_id, chunk_index, rrf_score)形式に変換
        output = []
        for key, rrf_score in sorted_results:
            doc_id, chunk_idx = key.split(':')
            output.append((doc_id, int(chunk_idx), rrf_score))

        return output

    async def hybrid_search(
        self,
        query: str,
        query_vector: np.ndarray,
        tenant_id: str,
        kb_ids: List[str],
        collection_ids: List[str],
        top_k: int = 10,
        threshold: float = 0.01
    ) -> List[Dict]:
        """
        ハイブリッド検索実行

        Args:
            query: クエリテキスト
            query_vector: クエリベクトル
            tenant_id: テナントID
            kb_ids: ナレッジベースIDリスト
            collection_ids: コレクションIDリスト
            top_k: 最終返却件数
            threshold: 最小RRFスコア閾値

        Returns:
            [{"document_id": "...", "chunk_index": 0, "score": 0.5, "content": "..."}, ...]
        """
        # Stage 3A: Sparse検索（並列実行）
        sparse_task = self.sparse_service.search(
            query=query,
            tenant_id=tenant_id,
            kb_ids=kb_ids,
            collection_ids=collection_ids,
            top_k=500
        )

        # Stage 3B: Dense検索（並列実行）
        dense_task = self.dense_service.search(
            query_vector=query_vector,
            tenant_id=tenant_id,
            kb_ids=kb_ids,
            collection_ids=collection_ids,
            top_k=500
        )

        # 並列実行
        sparse_results, dense_results = await asyncio.gather(
            sparse_task, dense_task
        )

        # Stage 4: RRF統合
        rrf_results = self.reciprocal_rank_fusion(
            sparse_results=sparse_results,
            dense_results=dense_results
        )

        # 閾値フィルタ + top_k選択
        filtered_results = [
            r for r in rrf_results
            if r[2] >= threshold
        ][:top_k]

        # チャンク内容取得
        enriched_results = await self._enrich_results(filtered_results)

        return enriched_results

    async def _enrich_results(
        self,
        results: List[Tuple[str, int, float]]
    ) -> List[Dict]:
        """
        検索結果にチャンク内容・メタデータを付加

        Args:
            results: [(document_id, chunk_index, rrf_score), ...]

        Returns:
            [{"document_id": "...", "chunk_index": 0, "score": 0.5, "content": "...", "metadata": {...}}, ...]
        """
        enriched = []

        for doc_id, chunk_idx, rrf_score in results:
            # チャンク内容・メタデータ取得
            chunk_data = await self.db.execute("""
                SELECT lpe.document, lpe.cmetadata,
                       d.filename, d.original_metadata
                FROM langchain_pg_embedding lpe
                JOIN documents d ON lpe.document_id = d.id
                WHERE lpe.document_id = :doc_id
                  AND lpe.chunk_index = :chunk_idx
            """, {"doc_id": doc_id, "chunk_idx": chunk_idx})

            if chunk_data:
                enriched.append({
                    "document_id": doc_id,
                    "chunk_index": chunk_idx,
                    "score": rrf_score,
                    "content": chunk_data.document,
                    "metadata": chunk_data.cmetadata,
                    "filename": chunk_data.filename,
                    "page_number": chunk_data.cmetadata.get('page_number', 1)
                })

        return enriched
```

## パラメータチューニング

### kパラメータの調整

| k値 | 効果 | 適用シーン |
|-----|------|-----------|
| 30 | 上位結果を重視 | 高品質なSparse/Dense結果 |
| 60（デフォルト） | バランス | 一般的なユースケース |
| 100 | 下位結果も考慮 | 多様性を重視 |

### 重み調整

**Sparse重視（固有名詞・専門用語が多い）**:

```python
retriever = HybridRetriever(
    k=60,
    w_sparse=0.7,  # Sparse重視
    w_dense=0.3
)
```

**Dense重視（概念的な質問が多い）**:

```python
retriever = HybridRetriever(
    k=60,
    w_sparse=0.3,
    w_dense=0.7   # Dense重視
)
```

**均等配分（デフォルト）**:

```python
retriever = HybridRetriever(
    k=60,
    w_sparse=0.5,
    w_dense=0.5
)
```

## API仕様

### POST /api/knowledge-bases/{id}/chat/hybrid-search

#### リクエスト

```json
{
  "query": "マイナビバイトにはどんなプランがありますか？",
  "top_k": 10,
  "threshold": 0.6,
  "rrf_k": 60,
  "sparse_weight": 0.5,
  "dense_weight": 0.5,
  "filters": {
    "department": "営業部",
    "confidentiality": "internal"
  }
}
```

#### レスポンス

```json
{
  "results": [
    {
      "document_id": "uuid",
      "chunk_index": 0,
      "score": 0.85,
      "content": "マイナビバイトには3つのプランがあります...",
      "metadata": {
        "page_number": 5,
        "element_id": "ID-42",
        "element_type": "text"
      },
      "filename": "mynavi_plan.pdf",
      "stage_scores": {
        "sparse_rank": 1,
        "dense_rank": 3,
        "rrf_score": 0.85
      }
    }
  ],
  "total_results": 10,
  "execution_time_ms": 450,
  "stage_breakdown": {
    "atlas_filter_ms": 35,
    "sparse_search_ms": 180,
    "dense_search_ms": 220,
    "rrf_fusion_ms": 15
  }
}
```

## パフォーマンス最適化

### 並列処理

```python
# Sparse/Dense検索を並列実行
import asyncio

async def parallel_search():
    sparse_task = sparse_service.search(...)
    dense_task = dense_service.search(...)

    # 並列実行（最大レイテンシは max(sparse, dense)）
    sparse_results, dense_results = await asyncio.gather(
        sparse_task,
        dense_task
    )
```

### キャッシング

```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def rrf_fusion_cached(
    sparse_results_tuple: tuple,
    dense_results_tuple: tuple,
    k: int
) -> list:
    """RRF結果をキャッシュ（同一クエリの高速化）"""
    sparse_results = list(sparse_results_tuple)
    dense_results = list(dense_results_tuple)
    return reciprocal_rank_fusion(sparse_results, dense_results, k)
```

## 評価メトリクス

### Recall@k

```python
def calculate_recall_at_k(
    retrieved_docs: List[str],
    relevant_docs: List[str],
    k: int = 10
) -> float:
    """Recall@k計算"""
    retrieved_k = set(retrieved_docs[:k])
    relevant_set = set(relevant_docs)

    if len(relevant_set) == 0:
        return 0.0

    return len(retrieved_k & relevant_set) / len(relevant_set)
```

### Precision@k

```python
def calculate_precision_at_k(
    retrieved_docs: List[str],
    relevant_docs: List[str],
    k: int = 10
) -> float:
    """Precision@k計算"""
    retrieved_k = set(retrieved_docs[:k])
    relevant_set = set(relevant_docs)

    if len(retrieved_k) == 0:
        return 0.0

    return len(retrieved_k & relevant_set) / len(retrieved_k)
```

### MRR（Mean Reciprocal Rank）

```python
def calculate_mrr(
    retrieved_docs: List[str],
    relevant_docs: List[str]
) -> float:
    """MRR計算"""
    for rank, doc in enumerate(retrieved_docs, start=1):
        if doc in relevant_docs:
            return 1.0 / rank
    return 0.0
```

## 監視・ロギング

### 監査ログ

```sql
CREATE TABLE rag_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL,
    user_id UUID,
    tenant_id UUID NOT NULL,
    query TEXT NOT NULL,
    filters JSONB,
    atlas_stage JSONB,
    sparse_stage JSONB,
    dense_stage JSONB,
    rrf_stage JSONB,
    final_results JSONB,
    total_execution_time_ms INTEGER,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 例: rrf_stageの内容
{
  "k": 60,
  "sparse_weight": 0.5,
  "dense_weight": 0.5,
  "sparse_result_count": 500,
  "dense_result_count": 500,
  "merged_result_count": 800,
  "top_k_result_count": 10,
  "execution_time_ms": 15
}
```

## トラブルシューティング

### 問題1: Sparse結果が支配的

**症状**: RRF結果がSparse検索結果とほぼ同じ

**原因**: Dense検索の精度が低い、またはw_sparseが大きすぎる

**解決策**: embeddingモデル改善、重み調整（w_sparse: 0.7 → 0.5）

### 問題2: Dense結果が支配的

**症状**: RRF結果がDense検索結果とほぼ同じ

**原因**: Sparse検索の精度が低い、またはw_denseが大きすぎる

**解決策**: PGroonga導入、重み調整（w_dense: 0.7 → 0.5）

### 問題3: 検索結果が少ない

**症状**: threshold=0.6で結果が0件

**原因**: 閾値が高すぎる、またはk値が小さすぎる

**解決策**: threshold調整（0.6 → 0.3）、k値増加（60 → 100）

## 関連ドキュメント

- [01-architecture.md](./01-architecture.md) - 7段階パイプライン全体像
- [02-atlas-layer.md](./02-atlas-layer.md) - Atlas層詳細設計
- [03-sparse-layer.md](./03-sparse-layer.md) - スパース層詳細設計
- [04-dense-layer.md](./04-dense-layer.md) - Dense層詳細設計
