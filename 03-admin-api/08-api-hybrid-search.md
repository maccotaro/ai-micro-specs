# ハイブリッド検索API

**最終更新**: 2025-11-08

## 概要

7段階RAGパイプラインを活用したエンタープライズ向けハイブリッド検索APIです。Atlas層フィルタリング、スパース検索（BM25）、Dense検索（ベクトル類似度）、Re-rankerを組み合わせて高精度な検索を実現します。

## エンドポイント

```
POST /admin/search/hybrid
```

**認証**: JWT（admin_access_token）必須

## リクエスト

```json
{
  "query": "マイナビのサービスは？",
  "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
  "threshold": 0.6,
  "top_k": 10,
  "user_context": {
    "department": "営業部",
    "clearance_level": "internal"
  }
}
```

**パラメータ**:
- `query` (required): 検索クエリ
- `knowledge_base_id` (required): ナレッジベースUUID
- `threshold` (optional, default: 0.6): 類似度閾値（0.0〜1.0）
- `top_k` (optional, default: 10): 最大返却件数
- `user_context` (optional): ユーザーフィルタ（部署、機密レベル等）

## レスポンス

```json
{
  "query": "マイナビのサービスは？",
  "results": [
    {
      "content": "マイナビバイトは、アルバイト・パート求人情報サイトです...",
      "score": 0.92,
      "metadata": {
        "chunk_id": "chunk-abc-123",
        "document_id": "doc-456",
        "chunk_index": 3,
        "collection_id": "coll-789",
        "sparse_score": 0.85,
        "dense_score": 0.91,
        "rrf_score": 0.88,
        "bm25_score": 0.89,
        "cross_encoder_score": 0.92
      }
    }
  ],
  "count": 10,
  "execution_time_ms": 2500
}
```

## 7段階RAGパイプライン

### Stage 0: MCPツール選択（オプション）
- LLMが適切なツール選択（search_documents等）

### Stage 1: Atlas層フィルタリング
- KB/Collection要約ベクトルで事前フィルタ
- 関連性の高いKB/Collectionを選別

### Stage 2: メタデータフィルタ
- テナント分離
- 部署フィルタ（user_context.department）
- 機密レベルフィルタ（user_context.clearance_level）

### Stage 3A: Sparse検索（BM25）
- PGroonga全文検索（日本語形態素解析）
- BM25スコアリング（k1=1.5, b=0.75）
- 結果: 約500件

### Stage 3B: Dense検索（ベクトル類似度）
- PGVector HNSW インデックス
- コサイン類似度計算
- embedding: bge-m3:567m (1024次元)
- 結果: 約500件

### Stage 4: ハイブリッド統合（RRF）
- Reciprocal Rank Fusion
- スパース+Dense結果をマージ
- 結果: 約600件

### Stage 5: BM25 Re-ranker
- 600件→100件に絞り込み
- MeCab トークナイザー + rank-bm25

### Stage 6: Cross-Encoder Re-ranker
- 100件→10件に絞り込み
- モデル: intfloat/multilingual-e5-large-instruct
- 最終スコア計算

### Stage 7: LLM生成（オプション）
- gemma2:9b で応答生成
- ストリーミング対応

## 処理時間

| ステージ | 処理時間 |
|---------|---------|
| Atlas層 | ~50ms |
| メタデータフィルタ | ~10ms |
| Sparse検索 | ~200ms |
| Dense検索 | ~300ms |
| RRF統合 | ~50ms |
| BM25 Re-ranker | ~150ms |
| Cross-Encoder | ~800ms (CPU) / ~200ms (GPU) |
| **合計** | **~2.5秒** |

## 関連ドキュメント

- [../17-rag-system/README.md](../17-rag-system/README.md) - エンタープライズRAGシステム
- [../17-rag-system/05-hybrid-search.md](../17-rag-system/05-hybrid-search.md) - RRF詳細
- [../17-rag-system/06-reranker.md](../17-rag-system/06-reranker.md) - Re-ranker詳細
- [../04-mcp-server/03-integration-api-admin.md](../04-mcp-server/03-integration-api-admin.md) - MCP統合
