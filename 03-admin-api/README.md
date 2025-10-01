# 03. 管理API（ai-micro-api-admin）

管理機能、ドキュメント処理・OCR、ナレッジベース、RAGチャットを担当するバックエンドサービスの設計ドキュメント。

## 📄 ドキュメント一覧

### サービス概要
- `01-overview.md` - サービス概要・アーキテクチャ

### API仕様書（実装コード基準）
- `02-api-specification.md` - **メインAPI仕様**（認証・共通仕様・目次）
  - `02-api-documents.md` - **ドキュメント処理API**（23エンドポイント）
  - `02-api-jobs.md` - **ジョブ管理API**（8エンドポイント）
  - `02-api-knowledge-bases.md` - **ナレッジベースAPI**（9エンドポイント）
  - `02-api-prompt-templates.md` - **プロンプトテンプレートAPI**（6エンドポイント）
  - `02-api-system-logs.md` - **システム管理・ログAPI**（12エンドポイント）

### 技術設計
- `03-document-processing.md` - ドキュメント処理パイプライン設計
- `04-ocr-design.md` - OCR機能設計（Docling + EasyOCR）
- `05-hierarchy-converter.md` - 階層構造変換（ID生成含む）
- `06-database-design.md` - admindb データベース設計

### フロー図
- `diagrams/document-processing-flow.md` - ドキュメント処理フロー図

## 🎯 主要機能

### ドキュメント処理
- PDFアップロード・処理（Docling統合）
- OCRメタデータ管理（編集可能）
- 画像切り出し・保存
- 階層構造解析（論理的・空間的・意味的）
- ベクトル化・RAG処理

### ナレッジベース・RAG
- ナレッジベースCRUD
- ベクトル検索（類似度ベース）
- ストリーミングチャット（RAG）
- カスタムプロンプト管理

### システム管理
- マイクロサービス全体の監視
- データベース・Redisステータス
- メンテナンスモード管理
- ログフィルタリング・検索

### ジョブ管理
- バックグラウンドジョブの進捗監視
- ジョブクリーンアップ
- デバッグ機能

## 🔗 連携

- **PostgreSQL** (admindb) - ドキュメント、ナレッジベース、ログ、テンプレート管理
- **Redis** - キャッシング、セッション管理
- **Auth Service (JWKS)** - JWT検証（RS256）
- **Vector Store** - ベクトル検索（pgvector）
- **LLM API** - RAGチャット生成

## 🌐 エンドポイント

**Port**: 8003
**Base URL**: `http://localhost:8003/admin`

## 📊 API統計

- **総エンドポイント数**: 58（実装: 59）
- **ドキュメント処理**: 23エンドポイント
- **ジョブ管理**: 8エンドポイント
- **ナレッジベース**: 9エンドポイント
- **プロンプトテンプレート**: 6エンドポイント
- **システム・ログ**: 12エンドポイント

## 🔧 技術スタック

- **Framework**: FastAPI 0.109.x
- **Language**: Python 3.11
- **OCR**: Docling + EasyOCR
- **Vector DB**: pgvector (PostgreSQL拡張)
- **Database**: PostgreSQL 15
- **Cache**: Redis 7
- **Document Processing**: pypdfium2, Pillow

## 📚 関連ドキュメント

- [Auth Service](../01-auth-service/) - JWT認証・JWKS
- [User API](../02-user-api/) - ユーザー情報連携
- [Database](../06-database/) - データベース設計全体
- [Integration](../08-integration/) - マイクロサービス連携