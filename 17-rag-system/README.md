# エンタープライズRAGシステム

## 概要

このディレクトリは、ai-micro-serviceプロジェクトのエンタープライズRAG（Retrieval Augmented Generation）システムの設計・実装・運用に関する包括的なドキュメントを提供します。

## システム構成

エンタープライズRAGシステムは、MCPサーバー経由でアクセス可能な7段階パイプライン構成です：

```
Stage 0: MCPツール選択 (LLM判断、ai-micro-mcp-admin)
    ↓
Stage 1: Atlas層フィルタリング (KB/Collection要約ベクトル)
Stage 2: メタデータフィルタ (テナント・部署・機密レベル)
Stage 3A: Sparse検索 (PGroonga全文検索 + BM25)
Stage 3B: Dense検索 (PGVector類似度検索)
Stage 4: ハイブリッド統合 (RRF: Reciprocal Rank Fusion)
Stage 5: BM25 Re-ranker (600件 → 100件)
Stage 6: Cross-Encoder Re-ranker (100件 → 10件)
Stage 7: LLM生成 (gemma2:9b)
```

### MCP (Model Context Protocol) サーバー統合

ai-micro-mcp-admin (Port 8004) は、MCPプロトコルを実装し、Claude DesktopやMCPクライアントに以下のツールを提供します：

- **search_documents**: 7段階RAGパイプラインによるハイブリッド検索
- **get_knowledge_base_summary**: KB統計・要約情報取得
- **normalize_ocr_text**: OCRテキスト正規化（文脈考慮型）

詳細は[../04-mcp-server/README.md](../04-mcp-server/README.md)を参照してください。

## ドキュメント構成

### アーキテクチャ設計

| ファイル | 内容 |
|---------|------|
| [01-architecture.md](./01-architecture.md) | 7段階パイプライン全体像とフロー |
| [02-atlas-layer.md](./02-atlas-layer.md) | Atlas層詳細設計（KB/Collection要約ベクトル） |
| [03-sparse-layer.md](./03-sparse-layer.md) | スパース層詳細設計（PGroonga全文検索・BM25） |
| [04-dense-layer.md](./04-dense-layer.md) | Dense層詳細設計（PGVectorベクトル検索） |
| [05-hybrid-search.md](./05-hybrid-search.md) | ハイブリッド検索設計（RRF統合） |
| [06-reranker.md](./06-reranker.md) | Re-ranker詳細設計（BM25 + Cross-Encoder） |

### データベース設計

| ファイル | 内容 |
|---------|------|
| [diagrams/database-schema.md](./diagrams/database-schema.md) | 統合ER図（全テーブル関係性） |
| [diagrams/update-triggers.md](./diagrams/update-triggers.md) | 更新タイミングフロー図 |

## 主要コンポーネント

### 1. Atlas層（事前フィルタリング）

**目的**: ナレッジベース/コレクション全体の要約ベクトルでクエリと関連性の高いKB/Collectionを事前選別

**テーブル**:
- `knowledge_bases_summary_embedding` - KB要約ベクトル（1024次元）
- `collections_summary_embedding` - Collection要約ベクトル（1024次元）
- `documents.centroid_embedding` - ドキュメント重心ベクトル

**更新タイミング**:
- ドキュメント追加/削除時: PostgreSQLトリガーでKB要約を非アクティブ化
- バックグラウンドジョブ: LLMで要約生成 → ベクトル化 → バージョン管理

### 2. Sparse層（キーワード検索）

**目的**: 語彙マッチングによる高精度な全文検索

**テーブル**:
- `document_fulltext` - PGroonga全文検索インデックス（標準FTS代替）

**特徴**:
- BM25スコアリング（k1=1.5, b=0.75）
- 日本語形態素解析（TokenMecab想定、標準FTSで代替）
- テナント・KB・Collectionフィルタ対応

### 3. Dense層（意味検索）

**目的**: 埋め込みベクトル類似度による意味的検索

**テーブル**:
- `langchain_pg_embedding` - チャンク埋め込みベクトル（1024次元）

**特徴**:
- HNSWインデックス（m=16, ef_construction=64）
- コサイン類似度計算
- embeddinggemma:500m-768次元モデル使用

### 4. ハイブリッド統合

**アルゴリズム**: RRF（Reciprocal Rank Fusion）

```
スコア(doc) = Σ [ 1 / (k + rank_i) ]
k = 60 (定数)
rank_i = Sparse/Dense検索での順位
```

**パラメータ**:
- `top_k`: 最終返却件数（デフォルト: 10）
- `threshold`: 最小スコア閾値（デフォルト: 0.6）

## 実装状況

| Phase | 内容 | 状態 |
|-------|------|------|
| Phase 1 | マルチテナント対応 | ✅ 完了（2025-10-24） |
| Phase 2 | Atlas層・スパース層・インデックス最適化 | ✅ 完了（2025-10-24） |
| Phase 3 | Re-ranker実装（BM25 + Cross-Encoder） | ✅ 完了（2025-11-06） |
| Phase 4 | 統合テスト・本番デプロイ | ⏭️ 未着手 |

## パフォーマンス目標

### 検索精度

| メトリクス | 目標値 | 現状 |
|-----------|-------|------|
| Recall@10 | 85-90% | 測定中 |
| Precision@10 | 90%+ | 測定中 |
| Atlas層フィルタ精度 | 95%+ | 測定中 |

### 応答速度

| Stage | 目標 | 現状 |
|-------|------|------|
| Atlas層 | <50ms | 測定中 |
| Sparse検索 | <200ms | 測定中 |
| Dense検索 | <300ms | 測定中 |
| RRF統合 | <50ms | 測定中 |
| LLM生成（初回トークン） | <2秒 | 測定中 |

## 関連ドキュメント

### Admin API設計書
- [../03-admin-api/02-api-knowledge-bases.md](../03-admin-api/02-api-knowledge-bases.md) - ナレッジベースAPI仕様
- [../03-admin-api/06-database-design.md](../03-admin-api/06-database-design.md) - データベース設計

### データベース設計書
- [../06-database/06-admindb-schema.md](../06-database/06-admindb-schema.md) - admindbスキーマ

### 実装詳細（api-adminリポジトリ）
- `ai-micro-api-admin/plan/enterprise-rag/00-overview.md` - エンタープライズRAG概要
- `ai-micro-api-admin/plan/enterprise-rag/01-phase1-multitenancy.md` - Phase 1詳細
- `ai-micro-api-admin/plan/enterprise-rag/02-phase2-search-layers.md` - Phase 2詳細

## 技術スタック

### ベクトルデータベース
- **PostgreSQL**: 16.x
- **pgvector**: 0.5.0+ (HNSW対応)
- **PGroonga**: 未インストール（標準FTSで代替）

### 埋め込みモデル
- **bge-m3:567m**: 1024次元出力
- **ベクトル次元**: 1024次元（全テーブル統一）

### LLMモデル
- **gemma2:9b**: 会話生成・要約生成

### 検索フレームワーク
- **LangChain**: 0.3.x
- **カスタムハイブリッド検索**: RRF実装

## 開発ガイドライン

### コード品質基準
- ファイルサイズ: 500行以下
- TypeScriptエラー: 0件
- Lintエラー: 0件
- テストカバレッジ: 80%+

### 応急処置的対応の禁止
RAGシステム開発では、以下の応急処置的対応は禁止されています：
- ❌ 根本原因を解決せず症状のみ回避する修正
- ❌ 必要なライブラリ・ツールを導入せず回避策でしのぐ
- ❌ データ前処理で解決すべき問題をクエリ時に対処
- ✅ 業界標準のライブラリ・ツール・フレームワークを使用
- ✅ アーキテクチャレベルでの正しい解決策を提示

詳細は[CLAUDE.md](../../CLAUDE.md)を参照してください。

## 変更履歴

| 日付 | 変更内容 | 担当 |
|------|---------|------|
| 2025-11-06 | RAGシステム設計書ディレクトリ作成 | Claude |
| 2025-10-24 | Phase 2実装完了（Atlas層・スパース層） | Claude |
| 2025-10-24 | Phase 1実装完了（マルチテナント対応） | Claude |

## ライセンス

このドキュメントは、ai-micro-serviceプロジェクトのライセンスに従います。
