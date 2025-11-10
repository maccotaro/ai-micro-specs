# MCP Admin Service

## 概要

**ai-micro-mcp-admin**は、MCP (Model Context Protocol) サーバーとして機能し、Claude Desktopやその他のMCPクライアントに対して、ナレッジベース検索・要約・OCRテキスト正規化の機能を提供します。api-adminの7段階RAGパイプラインを活用し、高精度な情報検索とAI応答生成を実現します。

## 主要機能

### 1. MCP (Model Context Protocol) サーバー

MCPプロトコルを実装し、以下の3つのツールを公開します：

- **search_documents**: ハイブリッド検索（7段階RAGパイプライン）によるドキュメント検索
- **get_knowledge_base_summary**: ナレッジベース全体の統計情報・要約取得
- **normalize_ocr_text**: OCRテキストの文脈考慮型正規化（ハイフン→長音符変換）

### 2. エンタープライズRAG統合

api-adminの7段階RAGパイプラインを活用：

```
Stage 0: MCPツール選択（LLM判断）
    ↓
Stage 1: Atlas層フィルタリング（KB/Collection要約ベクトル）
Stage 2: メタデータフィルタ（テナント・部署・機密レベル）
Stage 3A: Sparse検索（PGroonga全文検索 + BM25）
Stage 3B: Dense検索（PGVector HNSW ベクトル検索）
Stage 4: ハイブリッド統合（RRF: Reciprocal Rank Fusion）
Stage 5: BM25 Re-ranker（600件→100件）
Stage 6: Cross-Encoder Re-ranker（100件→10件）
    ↓
Stage 7: LLM応答生成（gemma2:9b、ストリーミング）
```

### 3. 安全な認証・認可

- **JWT認証**: RS256署名検証、JWKS統合（10分キャッシュ）
- **ロールベースアクセス制御 (RBAC)**: super_admin、admin、通常ユーザーの権限管理
- **ナレッジベースアクセス制御**: 作成者または公開KB

のみアクセス可能

### 4. 高性能・並行処理最適化

- **非同期ベクトル検索**: `asyncio.to_thread`によるブロッキング処理の分離
- **接続プール最適化**: 20基本接続 + 30オーバーフロー = 50並行接続
- **接続リーク防止**: finally句での確実なDB接続クローズ
- **処理時間**: 平均2.7秒（JWT検証〜RAG検索〜結果返却）

## サービス構成

### ネットワーク構成

```
┌─────────────────────────────────────────────────────────────┐
│ Claude Desktop / MCPクライアント                             │
└────────────────────┬────────────────────────────────────────┘
                     │ MCP Protocol
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ ai-micro-mcp-admin (Port 8004)                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ HTTP Endpoints                                          │ │
│ │ - GET /health                                           │ │
│ │ - GET /mcp/tools (JWT認証必須)                          │ │
│ │ - POST /mcp/call_tool (JWT認証必須)                     │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ MCP Server                                              │ │
│ │ - KnowledgeBaseMCPServer (singleton)                    │ │
│ │   ├─ search_documents()                                 │ │
│ │   ├─ get_knowledge_base_summary()                       │ │
│ │   └─ normalize_ocr_text()                               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Services                                                │ │
│ │ - VectorSearchService → api-admin ハイブリッド検索      │ │
│ │ - KBSummaryService → admindb 直接クエリ                │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP POST
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ ai-micro-api-admin (Port 8003)                              │
│ - POST /admin/search/hybrid (7段階RAGパイプライン)          │
│ - MCPClient → mcp-admin 呼び出し                            │
│ - MCPChatService → LLMツール選択＋応答生成                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         PostgreSQL admindb / Ollama / Auth Service
```

### ポート割り当て

| サービス | ポート | 役割 |
|---------|--------|------|
| ai-micro-mcp-admin | 8004 | MCPサーバー（ツール提供） |
| ai-micro-api-admin | 8003 | 7段階RAGパイプライン実行 |
| ai-micro-api-auth | 8002 | JWT発行・JWKS公開 |
| PostgreSQL | 5432 | admindb（ナレッジベース・ドキュメント・ベクトル） |
| Ollama | 11434 | LLM（ツール選択・応答生成・embedding） |
| Redis | 6379 | セッション・キャッシュ（任意） |

## 技術スタック

### フレームワーク

- **FastAPI**: 0.110.0+（Python 3.11+）
- **MCP SDK**: `mcp` パッケージ（Model Context Protocol実装）
- **Uvicorn**: ASGI Webサーバー

### データベース・ストレージ

- **PostgreSQL**: 16.x（admindb）
  - pgvector 0.5.0+（HNSWベクトルインデックス）
  - PGroonga（日本語全文検索、標準FTSフォールバック対応）
- **SQLAlchemy**: 2.0+（ORM・接続プール管理）

### AI・機械学習

- **Ollama**: LLMホスティング
  - `pakachan/elyza-llama3-8b:latest`（ツール選択・応答生成）
  - `bge-m3:567m`（embedding生成、api-admin経由）
- **sentence-transformers**: Cross-Encoder Re-ranker（api-admin）
- **rank-bm25**: BM25スコアリング（api-admin）

### 認証・セキュリティ

- **PyJWT**: JWT検証（RS256署名）
- **cryptography**: RSA公開鍵再構築（JWKS）
- **httpx**: 非同期HTTPクライアント（JWKS取得、api-admin通信）

## クイックスタート

### 前提条件

- Docker & Docker Compose
- PostgreSQL（admindb）が稼働中
- ai-micro-api-admin が稼働中（Port 8003）
- ai-micro-api-auth が稼働中（Port 8002、JWKS公開）
- Ollama が稼働中（Port 11434）

### 起動手順

```bash
# 1. リポジトリに移動
cd /Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-mcp-admin

# 2. 環境変数設定（.envファイル確認）
cat .env
# DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/admindb
# JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
# OLLAMA_BASE_URL=http://host.docker.internal:11434
# など

# 3. Dockerコンテナ起動
docker compose up -d

# 4. ヘルスチェック
curl http://localhost:8004/health
# {"status": "healthy"}

# 5. ログ確認
docker compose logs -f ai-micro-mcp-admin
```

### 動作確認

#### 1. ツール一覧取得

```bash
# JWT トークン取得（api-authでログイン）
TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0xIn0..."

# MCP ツール一覧取得
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8004/mcp/tools
```

**期待レスポンス**:
```json
[
  {
    "name": "search_documents",
    "description": "Search for specific information in knowledge base documents",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": {"type": "string"},
        "knowledge_base_id": {"type": "string", "format": "uuid"},
        "threshold": {"type": "number", "default": 0.6},
        "max_results": {"type": "integer", "default": 10}
      },
      "required": ["query", "knowledge_base_id"]
    }
  },
  {
    "name": "get_knowledge_base_summary",
    "description": "Get overview and statistics of entire knowledge base",
    ...
  },
  {
    "name": "normalize_ocr_text",
    "description": "Normalize OCR text by converting hyphens to Japanese long vowel marks",
    ...
  }
]
```

#### 2. ツール実行（search_documents）

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  http://localhost:8004/mcp/call_tool \
  -d '{
    "name": "search_documents",
    "arguments": {
      "query": "マイナビのサービスは？",
      "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
      "threshold": 0.6,
      "max_results": 10
    }
  }'
```

**期待レスポンス**:
```json
{
  "query": "マイナビのサービスは？",
  "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
  "threshold": 0.6,
  "results": [
    {
      "content": "マイナビバイトは、アルバイト・パート求人情報サイトです...",
      "score": 0.92,
      "metadata": {
        "chunk_id": "abc-123",
        "document_id": "doc-456",
        "chunk_index": 3,
        "sparse_score": 0.85,
        "dense_score": 0.91,
        "bm25_score": 0.88,
        "cross_encoder_score": 0.92
      }
    },
    ...
  ],
  "count": 10
}
```

## ディレクトリ構造

```
ai-micro-mcp-admin/
├── app/
│   ├── main.py                      # FastAPIアプリケーション（86行）
│   ├── core/
│   │   ├── config.py                # 設定管理（57行）
│   │   ├── database.py              # DB接続プール（34行）
│   │   ├── auth.py                  # JWT検証（111行）
│   │   └── permissions.py           # KB アクセス制御（86行）
│   ├── dependencies/
│   │   └── auth.py                  # get_current_user() 依存（28行）
│   ├── routers/
│   │   └── mcp.py                   # /mcp エンドポイント（79行）
│   └── services/
│       ├── mcp_server.py            # MCP サーバー実装（371行）
│       ├── vector_search.py         # ハイブリッド検索クライアント（216行）
│       └── kb_summary.py            # KB 要約サービス（61行）
├── Dockerfile                       # コンテナイメージ定義
├── docker-compose.yml               # ローカル開発用（44行）
├── requirements.txt                 # Python依存パッケージ
├── .env                             # 環境変数（ローカル）
└── CLAUDE.md                        # 開発ガイドライン
```

## 環境変数

### 必須環境変数

```bash
# アプリケーション
APP_NAME=AI Micro MCP Admin
APP_VERSION=1.0.0
DEBUG=False
HOST=0.0.0.0
PORT=8004

# データベース
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/admindb

# 認証
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
JWT_ALGORITHM=RS256
JWT_AUDIENCE=fastapi-api
JWT_ISSUER=https://auth.example.com

# Ollama（LLM）
OLLAMA_BASE_URL=http://host.docker.internal:11434
CHAT_MODEL=pakachan/elyza-llama3-8b:latest

# Redis（オプション）
REDIS_URL=redis://:password@host.docker.internal:6379
```

## パフォーマンス特性

### 処理時間内訳

| ステージ | 処理時間 | 説明 |
|---------|---------|------|
| JWT検証 | ~10ms | JWKS取得（キャッシュ）+ 署名検証 |
| HTTP通信（mcp→api） | ~50-100ms | VectorSearchService → ハイブリッド検索API |
| 7段階RAGパイプライン | ~2500ms | Atlas層〜Cross-Encoder Re-ranker |
| 結果整形・返却 | ~50ms | メタデータ追加・JSON serialization |
| **合計** | **~2.7秒** | JWT認証〜検索結果返却 |

### 並行処理性能

| 負荷レベル | 処理速度 | 備考 |
|-----------|---------|------|
| 低（1-2 req/s） | ✅ 最適 | 接続プール余裕あり |
| 中（5-10 req/s） | ✅ 良好 | 非同期処理でキューイング回避 |
| 高（20+ req/s） | ✅ 安定 | 接続プール50＋非同期でスケール |

**2025-10-23 最適化実施**:
- 非同期ベクトル検索導入（`asyncio.to_thread`）
- 接続プール拡張（20+30=50）
- 接続リーク防止強化

## ドキュメント構成

| ドキュメント | 内容 |
|-------------|------|
| [README.md](./README.md) | 本ドキュメント（概要・クイックスタート） |
| [01-architecture.md](./01-architecture.md) | 詳細アーキテクチャ・ファイル構成 |
| [02-mcp-tools.md](./02-mcp-tools.md) | 3つのMCPツール詳細仕様 |
| [03-integration-api-admin.md](./03-integration-api-admin.md) | api-admin連携詳細 |
| [04-authentication.md](./04-authentication.md) | JWT認証・認可フロー |
| [05-performance.md](./05-performance.md) | 並行処理最適化・パフォーマンスチューニング |

## 関連ドキュメント

### システム全体

- [../03-admin-api/README.md](../03-admin-api/README.md) - Admin APIサービス概要
- [../17-rag-system/README.md](../17-rag-system/README.md) - エンタープライズRAGシステム

### api-admin統合

- [../03-admin-api/02-api-knowledge-bases.md](../03-admin-api/02-api-knowledge-bases.md) - ナレッジベースAPI（チャットエンドポイント）
- [../03-admin-api/06-database-design.md](../03-admin-api/06-database-design.md) - データベース設計

### RAGパイプライン

- [../17-rag-system/01-architecture.md](../17-rag-system/01-architecture.md) - 7段階パイプライン詳細
- [../17-rag-system/05-hybrid-search.md](../17-rag-system/05-hybrid-search.md) - ハイブリッド検索（RRF統合）
- [../17-rag-system/06-reranker.md](../17-rag-system/06-reranker.md) - Re-ranker詳細（BM25 + Cross-Encoder）

## トラブルシューティング

### 問題1: JWTエラー（401 Unauthorized）

**症状**: `{"detail": "Invalid authentication credentials"}`

**原因**:
- JWT トークンの有効期限切れ
- JWKS URLへの接続失敗
- 署名検証失敗

**確認**:
```bash
# JWKS エンドポイント確認
curl http://localhost:8002/.well-known/jwks.json

# トークンデコード（jwt.io）
echo "eyJhbGci..." | base64 -d
```

**解決策**:
1. 新しいJWTトークンを取得（api-authで再ログイン）
2. JWKS_URL環境変数を確認
3. auth serviceが稼働中か確認

### 問題2: ハイブリッド検索エラー（503 Service Unavailable）

**症状**: `{"detail": "Failed to connect to api-admin service"}`

**原因**:
- api-admin サービス停止
- ネットワーク接続問題

**確認**:
```bash
# api-admin ヘルスチェック
curl http://localhost:8003/health

# Dockerネットワーク確認
docker network inspect ai-micro-network
```

**解決策**:
1. api-admin コンテナ再起動
2. docker-compose.ymlのnetwork設定確認

### 問題3: 処理速度が遅い（>5秒）

**症状**: search_documentsが5秒以上かかる

**原因**:
- データベース接続プール枯渇
- Ollama応答遅延
- RAGパイプラインのボトルネック

**確認**:
```bash
# 接続プール状態確認（PostgreSQL）
docker exec ai-micro-postgres psql -U postgres -d admindb -c "SELECT count(*) FROM pg_stat_activity WHERE datname='admindb';"

# Ollamaレスポンス時間確認
time curl http://localhost:11434/api/tags
```

**解決策**:
1. 接続プール設定確認（pool_size=20, max_overflow=30）
2. Ollamaモデルロード確認（初回は遅い）
3. データベースインデックス確認（HNSW、GIN）

## 開発・デバッグ

### ローカル開発

```bash
# Poetry仮想環境で起動
cd ai-micro-mcp-admin
poetry install
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8004 --reload
```

### ログレベル設定

```bash
# DEBUG=True で詳細ログ出力
DEBUG=True docker compose up
```

### コンテナ内デバッグ

```bash
# コンテナシェル
docker exec -it ai-micro-mcp-admin bash

# Python REPLでサービステスト
python
>>> from app.services.mcp_server import get_mcp_server
>>> server = get_mcp_server()
>>> server.tools_list
```

## ライセンス

このドキュメントは、ai-micro-serviceプロジェクトのライセンスに従います。

## 変更履歴

| 日付 | 変更内容 | 担当 |
|------|---------|------|
| 2025-11-08 | MCP Serverドキュメント初版作成 | Claude |
| 2025-10-23 | 並行リクエスト最適化実装 | Claude |
| 2025-10-24 | エンタープライズRAG Phase 2統合 | Claude |
