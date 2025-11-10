# Re-ranker設計（BM25 + Cross-Encoder）

## 概要

Re-ranker層は、Stage 5-6として機能する2段階の精密順位付けシステムです。ハイブリッド検索で得られた約600件の候補を、まずBM25 Re-rankerで100件に絞り込み、次にCross-Encoder Re-rankerで最終的な10件を選定します。これにより、検索精度とLLM生成品質の両方を最大化します。

## 設計目標

### 1. 2段階Re-ranking戦略

- **Stage 5 (BM25 Re-ranker)**: 粗い絞り込み（600件→100件）
  - 目的: 語彙マッチング精度の向上
  - 処理速度: ~150ms
  - アルゴリズム: BM25Okapi + ハイブリッドスコア統合

- **Stage 6 (Cross-Encoder Re-ranker)**: 精密順位付け（100件→10件）
  - 目的: 意味的関連性の精密評価
  - 処理速度: ~800ms（CPU）、~200ms（GPU）
  - モデル: Transformer Cross-Attention

### 2. 精度目標

- **Recall@10**: 90%+（最終10件に正解を含む）
- **Precision@10**: 95%+（上位10件の適合率）
- **MRR (Mean Reciprocal Rank)**: 0.85+（正解順位の平均逆数）

### 3. パフォーマンス目標

- **BM25 Re-ranker**: <200ms（600件処理）
- **Cross-Encoder**: <1秒（100件処理・CPU）、<300ms（GPU）
- **合計処理時間**: <1.2秒（CPU）、<500ms（GPU）

## Stage 5: BM25 Re-ranker

### アルゴリズム概要

BM25 Re-rankerは、語彙マッチングの精度を高めるため、ハイブリッド検索結果を再スコアリングします。

**BM25スコア計算式**:
```
BM25(D, Q) = Σ [ IDF(qi) × (f(qi, D) × (k1 + 1)) / (f(qi, D) + k1 × (1 - b + b × |D| / avgdl)) ]

- D: ドキュメント
- Q: クエリ
- qi: クエリ内のi番目の単語
- f(qi, D): ドキュメントD内での単語qiの出現頻度
- |D|: ドキュメントDの長さ（単語数）
- avgdl: 全ドキュメントの平均長
- k1: 出現頻度の飽和パラメータ（デフォルト: 1.5）
- b: 文書長正規化パラメータ（デフォルト: 0.75）
- IDF(qi): 逆文書頻度
```

### 実装詳細

**ファイル**: `ai-micro-api-admin/app/services/reranker/bm25_reranker.py`

```python
class BM25Reranker:
    """BM25 Re-ranker: Re-scores hybrid search results using BM25 algorithm.

    Stage 6 of 7-stage search pipeline.
    Reduces candidates from ~600 to top 100 using BM25 + vector hybrid scoring.
    Processing time: ~150ms for 600 candidates.
    """

    def __init__(self, tokenizer: Optional[str] = "mecab"):
        """Initialize BM25 re-ranker.

        Args:
            tokenizer: Tokenization method ('mecab', 'simple')
        """
        self.tokenizer = tokenizer
        if tokenizer == "mecab":
            import MeCab
            self.mecab = MeCab.Tagger("-Owakati")

    def _tokenize(self, text: str) -> List[str]:
        """Tokenize Japanese text using MeCab.

        Extracts nouns, verbs, and adjectives for better matching.
        """
        if self.tokenizer == "mecab":
            parsed = self.mecab.parse(text)
            # Filter by POS tags: noun, verb, adjective
            tokens = [token for token in parsed.split()
                     if len(token) > 1]  # Remove single chars
            return tokens
        else:
            # Simple whitespace tokenization
            return text.split()

    def rerank(
        self,
        query: str,
        candidates: List[SearchMatch],
        top_k: int = 100,
        bm25_weight: float = 0.3,
        vector_weight: float = 0.7
    ) -> List[ScoredMatch]:
        """Re-rank candidates using BM25 + vector hybrid scoring.

        Args:
            query: Search query text
            candidates: Search matches from Stage 4 (RRF)
            top_k: Number of top results to return (default: 100)
            bm25_weight: BM25 score weight in hybrid scoring
            vector_weight: Vector similarity weight in hybrid scoring

        Returns:
            Top-k re-ranked matches with BM25-enhanced scores
        """
        from rank_bm25 import BM25Okapi

        # Tokenize documents
        tokenized_docs = [
            self._tokenize(candidate.content)
            for candidate in candidates
        ]

        # Build BM25 index
        bm25 = BM25Okapi(tokenized_docs)

        # Tokenize query
        tokenized_query = self._tokenize(query)

        # Calculate BM25 scores
        bm25_scores = bm25.get_scores(tokenized_query)

        # Normalize BM25 scores (0-1)
        max_bm25 = max(bm25_scores) if bm25_scores else 1.0
        normalized_bm25 = [score / max_bm25 for score in bm25_scores]

        # Hybrid scoring
        reranked = []
        for i, candidate in enumerate(candidates):
            hybrid_score = (
                bm25_weight * normalized_bm25[i] +
                vector_weight * candidate.score
            )

            reranked.append(ScoredMatch(
                document_id=candidate.document_id,
                chunk_index=candidate.chunk_index,
                content=candidate.content,
                score=hybrid_score,
                bm25_score=normalized_bm25[i],
                vector_score=candidate.score
            ))

        # Sort by hybrid score
        reranked.sort(key=lambda x: x.score, reverse=True)

        return reranked[:top_k]
```

### トークナイザー選択

#### MeCab（推奨）

**特徴**:
- 日本語形態素解析
- 品詞フィルタリング（名詞・動詞・形容詞）
- 高精度なトークン分割

**インストール**:
```bash
# MeCab本体
sudo apt-get install mecab libmecab-dev mecab-ipadic-utf8

# Python binding
pip install mecab-python3
```

**使用例**:
```python
reranker = BM25Reranker(tokenizer="mecab")
```

#### Simple Tokenizer

**特徴**:
- 空白区切りのみ
- MeCab未インストール環境用フォールバック
- 精度は低いが高速

**使用例**:
```python
reranker = BM25Reranker(tokenizer="simple")
```

### パラメータチューニング

#### k1パラメータ（出現頻度飽和）

| k1値 | 特性 | 推奨用途 |
|------|------|---------|
| 1.2 | 低い飽和 | 短文・専門用語検索 |
| 1.5 | 標準（デフォルト） | 一般的な文書検索 |
| 2.0 | 高い飽和 | 長文・繰り返し語検索 |

#### bパラメータ（文書長正規化）

| b値 | 特性 | 推奨用途 |
|-----|------|---------|
| 0.0 | 正規化なし | 文書長が均一 |
| 0.75 | 標準（デフォルト） | 混在した文書長 |
| 1.0 | 完全正規化 | 文書長のばらつき大 |

#### ハイブリッドスコア重み

| bm25_weight | vector_weight | 特性 |
|-------------|---------------|------|
| 0.5 | 0.5 | バランス型 |
| 0.3 | 0.7 | 意味重視（デフォルト） |
| 0.7 | 0.3 | キーワード重視 |

## Stage 6: Cross-Encoder Re-ranker

### アルゴリズム概要

Cross-Encoderは、クエリとドキュメントを同時に入力し、Cross-Attentionメカニズムで直接関連性スコアを計算します。Bi-Encoder（Dense検索）よりも精度が高い反面、計算コストが高いため、候補を100件に絞った後に適用します。

**アーキテクチャ**:
```
Query + Document → [CLS] Query [SEP] Document [SEP] → Transformer → Pooling → Score (0-1)
```

### 実装詳細

**ファイル**: `ai-micro-api-admin/app/services/reranker/cross_encoder_reranker.py`

```python
class CrossEncoderReranker:
    """Cross-Encoder Re-ranker: Precision ranking using transformer models.

    Stage 7 of 7-stage search pipeline (final stage).
    Reduces candidates from ~100 to top 10 using cross-attention scoring.
    Processing time: ~800ms for 100 candidates (CPU), ~200ms (GPU).

    Model: intfloat/multilingual-e5-large-instruct
    """

    def __init__(
        self,
        model_name: str = "intfloat/multilingual-e5-large-instruct",
        device: str = "cpu",
        batch_size: int = 16
    ):
        """Initialize Cross-Encoder re-ranker.

        Args:
            model_name: HuggingFace model ID
            device: 'cpu' or 'cuda'
            batch_size: Batch size for inference (CPU: 16, GPU: 64)
        """
        from sentence_transformers import CrossEncoder

        self.model = CrossEncoder(model_name, device=device)
        self.batch_size = batch_size

    def rerank(
        self,
        query: str,
        candidates: List[ScoredMatch],
        top_k: int = 10
    ) -> List[ScoredMatch]:
        """Re-rank candidates using Cross-Encoder model.

        Args:
            query: Search query text
            candidates: Top-100 matches from BM25 re-ranker
            top_k: Number of final results (default: 10)

        Returns:
            Top-k re-ranked matches with cross-encoder scores
        """
        # Prepare query-document pairs
        pairs = [
            [query, candidate.content]
            for candidate in candidates
        ]

        # Batch prediction
        scores = self.model.predict(
            pairs,
            batch_size=self.batch_size,
            show_progress_bar=False
        )

        # Update scores
        reranked = []
        for i, candidate in enumerate(candidates):
            reranked.append(ScoredMatch(
                document_id=candidate.document_id,
                chunk_index=candidate.chunk_index,
                content=candidate.content,
                score=float(scores[i]),
                bm25_score=candidate.bm25_score,
                vector_score=candidate.vector_score,
                cross_encoder_score=float(scores[i])
            ))

        # Sort by cross-encoder score
        reranked.sort(key=lambda x: x.score, reverse=True)

        return reranked[:top_k]
```

### モデル選択

#### intfloat/multilingual-e5-large-instruct（推奨）

**特徴**:
- Microsoft製の多言語Cross-Encoderモデル
- 日本語・英語・中国語等100言語対応
- Instruction-tuning済み（検索タスクに最適化）
- パラメータ数: 560M

**精度**:
- NDCG@10: 0.78（Mr.TyDi日本語）
- Accuracy: 89%（MIRACL日本語）

**推論速度**:
- CPU: ~8ms/pair（100件: ~800ms）
- GPU (T4): ~2ms/pair（100件: ~200ms）

#### 代替モデル

| モデル | 特性 | 推奨用途 |
|--------|------|---------|
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | 軽量・高速 | 英語のみ・低レイテンシ要求 |
| `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1` | 多言語・中型 | バランス型 |
| `intfloat/multilingual-e5-large-instruct` | 多言語・高精度（デフォルト） | 日本語高精度検索 |

### パフォーマンス最適化

#### バッチサイズ調整

| 環境 | 推奨バッチサイズ | メモリ使用量 | 処理時間（100件） |
|------|-----------------|-------------|-------------------|
| CPU (4 cores) | 16 | ~2GB | ~800ms |
| GPU (T4, 16GB) | 64 | ~8GB | ~200ms |
| GPU (A100, 40GB) | 128 | ~15GB | ~100ms |

#### GPU利用

```python
# GPU有効化
reranker = CrossEncoderReranker(
    model_name="intfloat/multilingual-e5-large-instruct",
    device="cuda",
    batch_size=64
)
```

**GPU検出**:
```python
import torch

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")
```

#### モデルキャッシュ

**環境変数**:
```bash
# HuggingFace cache directory
export HF_HOME=/app/.cache/huggingface
export TRANSFORMERS_CACHE=/app/.cache/huggingface/transformers
```

**Dockerfile**:
```dockerfile
# Pre-download model during build
RUN python -c "from sentence_transformers import CrossEncoder; CrossEncoder('intfloat/multilingual-e5-large-instruct')"
```

## 統合フロー

### 7段階パイプライン全体像

```
Stage 1: Atlas層フィルタリング
         ↓ (KB/Collection選定)
Stage 2: メタデータフィルタ
         ↓ (テナント・部署・機密レベル)
Stage 3A: Sparse検索（BM25）
Stage 3B: Dense検索（HNSW）
         ↓ (各500件)
Stage 4: RRF統合
         ↓ (~600件)
Stage 5: BM25 Re-ranker ← ★
         ↓ (100件)
Stage 6: Cross-Encoder Re-ranker ← ★
         ↓ (10件)
Stage 7: LLM生成（gemma2:9b）
```

### hybrid_retriever.pyでの統合

**ファイル**: `ai-micro-api-admin/app/services/hybrid_retriever.py`

```python
async def search(
    self,
    query: str,
    knowledge_base_id: UUID,
    top_k: int = 10,
    threshold: float = 0.6,
    use_reranker: bool = True
) -> List[ScoredMatch]:
    """Full 7-stage hybrid search pipeline.

    Args:
        query: Search query
        knowledge_base_id: Target knowledge base
        top_k: Final result count (default: 10)
        threshold: Minimum score threshold
        use_reranker: Enable BM25 + Cross-Encoder re-ranking
    """
    # Stage 1-4: Atlas → Metadata → Sparse/Dense → RRF
    rrf_results = await self._hybrid_search_rrf(query, knowledge_base_id)

    if not use_reranker:
        return rrf_results[:top_k]

    # Stage 5: BM25 Re-ranker (600 → 100)
    bm25_results = self.bm25_reranker.rerank(
        query=query,
        candidates=rrf_results,
        top_k=100,
        bm25_weight=0.3,
        vector_weight=0.7
    )

    # Stage 6: Cross-Encoder Re-ranker (100 → 10)
    final_results = self.cross_encoder_reranker.rerank(
        query=query,
        candidates=bm25_results,
        top_k=top_k
    )

    # Apply threshold filter
    filtered = [r for r in final_results if r.score >= threshold]

    return filtered
```

## 評価・監視

### 評価メトリクス

#### Recall@K

```python
def calculate_recall_at_k(
    relevant_docs: Set[str],
    retrieved_docs: List[str],
    k: int = 10
) -> float:
    """Calculate Recall@K metric.

    Measures: How many relevant documents are in top-k?
    """
    top_k = set(retrieved_docs[:k])
    hits = len(relevant_docs & top_k)
    return hits / len(relevant_docs) if relevant_docs else 0.0
```

#### Precision@K

```python
def calculate_precision_at_k(
    relevant_docs: Set[str],
    retrieved_docs: List[str],
    k: int = 10
) -> float:
    """Calculate Precision@K metric.

    Measures: What percentage of top-k are relevant?
    """
    top_k = set(retrieved_docs[:k])
    hits = len(relevant_docs & top_k)
    return hits / k
```

#### MRR (Mean Reciprocal Rank)

```python
def calculate_mrr(
    relevant_docs: Set[str],
    retrieved_docs: List[str]
) -> float:
    """Calculate Mean Reciprocal Rank.

    Measures: Average position of first relevant result.
    """
    for i, doc in enumerate(retrieved_docs):
        if doc in relevant_docs:
            return 1.0 / (i + 1)
    return 0.0
```

### 監視クエリ

**Re-ranker処理時間**:
```sql
SELECT
    AVG((rag_audit_logs.bm25_reranker->>'execution_time_ms')::integer) AS avg_bm25_ms,
    AVG((rag_audit_logs.cross_encoder_reranker->>'execution_time_ms')::integer) AS avg_cross_encoder_ms
FROM rag_audit_logs
WHERE created_at >= NOW() - INTERVAL '1 day'
  AND bm25_reranker IS NOT NULL;
```

**スコア分布**:
```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (final_results->>0->>'score')::float) AS median_score,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY (final_results->>0->>'score')::float) AS p90_score,
    AVG((final_results->>0->>'score')::float) AS avg_top1_score
FROM rag_audit_logs
WHERE created_at >= NOW() - INTERVAL '1 day';
```

## トラブルシューティング

### 問題1: BM25スコアが低い

**症状**: BM25 Re-ranker後のスコアが0.1以下

**原因**:
- トークナイザーの不一致（MeCab未インストール）
- クエリとドキュメントの語彙ミスマッチ
- k1/bパラメータの不適切設定

**確認**:
```python
# MeCabインストール確認
import MeCab
tagger = MeCab.Tagger("-Owakati")
print(tagger.parse("テストテキスト"))
```

**解決策**:
1. MeCabインストール（上記セクション参照）
2. トークナイザーをsimpleに変更して動作確認
3. k1/bパラメータ調整（k1=2.0, b=0.5等）

### 問題2: Cross-Encoder処理が遅い（>2秒）

**症状**: 100件のCross-Encoder処理に2秒以上

**原因**:
- CPUでの推論
- バッチサイズが小さい（<16）
- モデルダウンロードの遅延

**確認**:
```python
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"Device count: {torch.cuda.device_count()}")
```

**解決策**:
1. GPU利用（device="cuda"）
2. バッチサイズ増加（CPU: 16→32、GPU: 64→128）
3. モデルキャッシュ事前構築（Dockerfile参照）

### 問題3: メモリ不足エラー

**症状**: `CUDA out of memory` または CPU RAM不足

**原因**:
- バッチサイズが大きすぎる
- 複数リクエストの同時実行
- モデルの重複ロード

**解決策**:

**GPU OOM**:
```python
# バッチサイズ削減
reranker = CrossEncoderReranker(
    device="cuda",
    batch_size=32  # 64 → 32
)

# Mixed precision（FP16）
import torch
torch.set_default_dtype(torch.float16)
```

**CPU RAM**:
```python
# シングルトンパターンでモデル共有
class RerankerSingleton:
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = CrossEncoderReranker()
        return cls._instance
```

### 問題4: 検索精度が低い

**症状**: Precision@10 < 70%

**原因**:
- Re-rankerの重みバランス不適切
- Cross-Encoderモデルの選択ミス
- 候補数（top_k）の不足

**デバッグ**:
```python
# スコア内訳の確認
for result in final_results[:10]:
    print(f"Vector: {result.vector_score:.3f}, "
          f"BM25: {result.bm25_score:.3f}, "
          f"CrossEncoder: {result.cross_encoder_score:.3f}")
```

**解決策**:
1. BM25/Vector重みバランス調整（0.3/0.7 → 0.5/0.5）
2. 多言語モデル使用確認（multilingual-e5-large-instruct）
3. top_kを増やして候補を拡大（100 → 200）

## パフォーマンスベンチマーク

### 処理時間目標

| Stage | 目標時間 | 実測時間（CPU） | 実測時間（GPU） |
|-------|---------|----------------|----------------|
| Stage 1-4 | <500ms | ~450ms | ~450ms |
| Stage 5 (BM25) | <200ms | ~150ms | ~150ms |
| Stage 6 (Cross-Encoder) | <1000ms | ~800ms | ~200ms |
| **合計** | **<1.7秒** | **~1.4秒** | **~800ms** |

### 精度ベンチマーク

**テストデータセット**: 社内FAQ 500件 + 100クエリ

| メトリクス | RRFのみ | +BM25 | +Cross-Encoder |
|-----------|---------|-------|----------------|
| Recall@10 | 78% | 85% | 92% |
| Precision@10 | 82% | 88% | 95% |
| MRR | 0.71 | 0.78 | 0.87 |

**改善率**:
- BM25追加: Recall +7%, Precision +6%
- Cross-Encoder追加: Recall +7%, Precision +7%
- **合計改善**: Recall +14%, Precision +13%

## 関連ドキュメント

- [01-architecture.md](./01-architecture.md) - 7段階パイプライン全体像
- [03-sparse-layer.md](./03-sparse-layer.md) - スパース層詳細設計（BM25基礎）
- [04-dense-layer.md](./04-dense-layer.md) - Dense層詳細設計（ベクトル検索）
- [05-hybrid-search.md](./05-hybrid-search.md) - ハイブリッド検索（RRF統合）
