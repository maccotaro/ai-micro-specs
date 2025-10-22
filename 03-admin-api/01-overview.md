# Admin API Service 概要

**カテゴリ**: Backend Service
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [サービス概要](#サービス概要)
- [責務と役割](#責務と役割)
- [アーキテクチャ](#アーキテクチャ)
- [技術スタック](#技術スタック)
- [主要機能](#主要機能)
- [関連サービス](#関連サービス)

---

## サービス概要

Admin API Service (`ai-micro-api-admin`) は、システム管理、ドキュメント処理、ナレッジベース管理を担う統合管理マイクロサービスです。Doclingベースの高度なPDF処理エンジン、ハイブリッドOCR、pgvectorによるベクトル検索機能を提供します。

### 基本情報

| 項目 | 内容 |
|------|------|
| サービス名 | Admin API Service |
| リポジトリ | `ai-micro-api-admin/` |
| コンテナ名 | `ai-micro-admin-api` |
| ポート | 8003 |
| フレームワーク | FastAPI |
| 言語 | Python 3.11+ |
| データベース | PostgreSQL (`admindb`) + pgvector |
| キャッシュ | Redis |
| ドキュメントエンジン | Docling v2.0+ |
| OCRエンジン | EasyOCR + Docling Hybrid |

---

## 責務と役割

### 主要責務

1. **システム管理**
   - ダッシュボード統計情報の提供
   - システムログ管理（収集・検索・分析）
   - サービスヘルスチェックと監視
   - メンテナンスモード制御

2. **ドキュメント処理**
   - Doclingによる高度なPDF解析
   - 7段階処理パイプライン実行
   - 自動レイアウト解析（図表・テキスト・表の認識）
   - ハイブリッドOCR処理（Docling + EasyOCR）
   - 画像クロッピングと保存

3. **階層構造解析**
   - 論理的読み順序（LOGICAL_ORDERING）
   - 空間的階層構造（SPATIAL_HIERARCHY）
   - 意味的階層構造（SEMANTIC_HIERARCHY）
   - 文書全体での通し番号ID生成

4. **ナレッジベース管理**
   - ドキュメントコレクション管理
   - ベクトル埋め込み生成（embeddinggemma 768次元）
   - pgvectorによる類似度検索
   - RAG（Retrieval Augmented Generation）対応

5. **認証・認可**
   - JWT トークンの検証（JWKS経由）
   - ロールベースアクセス制御（admin / super_admin）
   - ドキュメントアクセス制御

### 責務範囲外

- ユーザー認証処理（Auth Serviceの責務）
- ユーザープロファイル管理（User API Serviceの責務）
- フロントエンドレンダリング（Frontend BFFの責務）

---

## アーキテクチャ

### サービス位置付け

```
┌─────────────────┐      ┌─────────────────┐
│ User Frontend   │      │ Admin Frontend  │
│   (Port 3002)   │      │   (Port 3003)   │
└────────┬────────┘      └────────┬────────┘
         │                        │
         └────────────────────────┘
                  │ HTTP/REST
         ┌────────▼────────┐
         │  Admin API      │
         │  (Port 8003)    │ ← このサービス
         └────────┬────────┘
                  │
      ┌───────────┼───────────────┬───────────┐
      │           │               │           │
┌─────▼─────┐ ┌──▼──────┐ ┌─────▼──────┐ ┌──▼───────────┐
│PostgreSQL │ │  Redis  │ │Auth Service│ │ User API     │
│(admindb)  │ │(Cache)  │ │  (JWKS)    │ │ (Profiles)   │
│+pgvector  │ └─────────┘ └────────────┘ └──────────────┘
└───────────┘
```

### ディレクトリ構造

```
ai-micro-api-admin/
├── app/
│   ├── main.py                          # FastAPIエントリーポイント
│   ├── core/                            # コア機能
│   │   ├── config.py                   # 設定管理
│   │   ├── security.py                 # JWT認証
│   │   ├── job_manager.py              # ジョブ管理
│   │   ├── document_processor.py       # ドキュメントプロセッサ統合
│   │   ├── vector_store.py             # ベクトルストア管理
│   │   └── document_processing/        # ドキュメント処理エンジン
│   │       ├── base.py                 # DocumentProcessor (メインオーケストレータ)
│   │       ├── docling_processor.py    # Docling統合
│   │       ├── custom_ocr_processor.py # カスタムOCR処理
│   │       ├── region_ocr_processor.py # 領域別OCR処理
│   │       ├── hierarchy_converter.py  # 階層構造変換
│   │       ├── hierarchical_extractor.py # 階層抽出
│   │       ├── layout_extractor.py     # レイアウト抽出
│   │       ├── text_extractor.py       # テキスト抽出
│   │       ├── image_cropper.py        # 画像切り出し
│   │       ├── image_processor.py      # 画像生成（144 DPI）
│   │       ├── pdf_preprocessor.py     # PDF前処理
│   │       ├── document_structure_analyzer.py # 構造解析
│   │       ├── structure_visualizer.py # 構造可視化
│   │       ├── file_manager.py         # ファイル管理
│   │       └── utils.py                # ユーティリティ
│   ├── models/                          # データモデル
│   │   └── logs.py                     # SystemLog, LoginLog, Document, KnowledgeBase,
│   │                                   # SystemSettings, PromptTemplate
│   ├── routers/                         # APIエンドポイント
│   │   ├── dashboard.py                # ダッシュボード
│   │   ├── logs.py                     # ログ管理
│   │   ├── system.py                   # システム管理
│   │   ├── documents.py                # ドキュメント処理
│   │   ├── documents_maintenance.py    # ドキュメントメンテナンス
│   │   ├── knowledge_bases.py          # ナレッジベース管理
│   │   ├── knowledge_bases_chat.py     # チャット機能
│   │   ├── prompt_templates.py         # プロンプトテンプレート管理
│   │   └── jobs.py                     # ジョブ管理
│   ├── services/                        # ビジネスロジック
│   │   ├── common/                     # 共通サービス
│   │   │   ├── document_security.py    # ドキュメントセキュリティ
│   │   │   └── image_path_resolver.py  # 画像パス解決
│   │   ├── crud/                       # CRUD操作
│   │   │   ├── document_crud.py        # ドキュメントCRUD
│   │   │   ├── document_stats.py       # ドキュメント統計
│   │   │   └── document_upload.py      # アップロード処理
│   │   ├── document_processing/        # ドキュメント処理
│   │   │   ├── background_processor.py # バックグラウンド処理
│   │   │   └── ocr_region_service.py   # OCR領域サービス
│   │   ├── image_processing/           # 画像処理
│   │   │   ├── cropped_image_service.py # 切り出し画像サービス
│   │   │   ├── image_cropping_service.py # クロッピング処理
│   │   │   ├── image_serving_service.py # 画像配信サービス
│   │   │   └── ocr_region_service.py   # OCR領域サービス
│   │   ├── metadata_service.py         # メタデータ管理
│   │   └── vector_service.py           # ベクトル検索
│   ├── utils/                           # ユーティリティ
│   │   ├── text_processor.py           # テキスト処理
│   │   └── file_utils.py               # ファイルユーティリティ
│   ├── db/                             # データベース
│   │   └── session.py                  # DB接続管理
│   └── schemas/                        # Pydanticスキーマ
│       ├── admin.py                    # 管理者スキーマ
│       ├── documents.py                # ドキュメントスキーマ
│       ├── chat.py                     # チャットスキーマ
│       └── prompt_templates.py         # プロンプトスキーマ
├── Dockerfile
├── docker-compose.yml
├── pyproject.toml                       # Poetry依存関係
└── init.sql                            # pgvector初期化スクリプト
```

---

## 技術スタック

### コア技術

| カテゴリ | 技術 | バージョン | 用途 |
|---------|------|-----------|------|
| Framework | FastAPI | 0.109+ | Webフレームワーク |
| Language | Python | 3.11+ | 実装言語 |
| ORM | SQLAlchemy | 2.x | データベースORM |
| Validation | Pydantic | 2.x | データバリデーション |
| Container | Docker | - | コンテナ化 |
| Dependency Mgmt | Poetry | Latest | パッケージ管理 |

### ドキュメント処理技術

| 技術 | バージョン | 用途 |
|------|-----------|------|
| Docling | 2.0+ | PDF解析・レイアウト抽出 |
| EasyOCR | Latest | OCR補完（日英中韓対応） |
| pypdfium2 | Latest | 高品質画像生成（144 DPI） |
| PIL/Pillow | Latest | 画像処理・クロッピング |

### データストア

| 種類 | 製品 | 用途 |
|------|------|------|
| Primary DB | PostgreSQL 15 | ログ・ドキュメント・ナレッジベース |
| Vector DB | pgvector | 埋め込みベクトル検索 |
| Cache | Redis 7 | セッション・キャッシュ |

### 認証・セキュリティ

| 技術 | 用途 |
|------|------|
| JWT (RS256) | トークンベース認証 |
| JWKS | 公開鍵検証 |
| RBAC | ロールベースアクセス制御 (admin/super_admin) |
| CORS | クロスオリジン制御 |
| Path Validation | パストラバーサル保護 |

### 主要依存ライブラリ

```toml
[tool.poetry.dependencies]
python = "^3.11"
fastapi = "*"
uvicorn = "*"
sqlalchemy = "*"
psycopg2-binary = "*"
redis = "*"
pyjwt = {extras = ["crypto"], version = "*"}
docling = "^2.0"
easyocr = "*"
pypdfium2 = "*"
pillow = "*"
pgvector = "*"
langchain = "*"
langchain-postgres = "*"
```

---

## 主要機能

### 1. ダッシュボード管理

#### GET /admin/dashboard/stats
- **機能**: システム統計情報の取得
- **認証**: admin必須
- **提供データ**:
  - ユーザー統計（総数、アクティブ、新規）
  - ログ統計（総数、エラー数）
  - サービス稼働状況
  - システムアラート

### 2. ログ管理

#### GET /admin/logs
- **機能**: システムログの検索・フィルタリング
- **認証**: admin必須
- **フィルター**: service, level, page, limit
- **ページネーション**: 対応（デフォルト50件）

#### GET /admin/logs/{service}
- **機能**: サービス固有のログ取得
- **認証**: admin必須

#### POST /admin/logs/create
- **機能**: ログエントリの作成（テスト用）
- **認証**: admin必須

### 3. システム管理

#### GET /admin/system/status
- **機能**: 全体システムステータス確認
- **認証**: admin必須
- **チェック項目**:
  - 各サービスの稼働状態
  - PostgreSQL接続・パフォーマンス
  - Redis接続・メモリ使用量

#### POST /admin/system/maintenance
- **機能**: メンテナンスモード切り替え
- **認証**: super_admin必須

#### POST /admin/system/cache/clear
- **機能**: Redisキャッシュクリア
- **認証**: super_admin必須

### 4. ドキュメント処理

#### POST /admin/documents/upload
- **機能**: PDFアップロードと処理開始
- **認証**: admin必須
- **処理内容**:
  1. Doclingによるレイアウト解析
  2. 階層構造変換（3種類）
  3. ハイブリッドOCR実行
  4. 画像切り出しと保存
  5. メタデータ生成（metadata_hierarchy.json）
- **対応形式**: PDF, DOCX, PPTX

#### GET /admin/documents/{document_id}/metadata
- **機能**: 処理済みドキュメントのメタデータ取得
- **認証**: admin必須
- **返却内容**: metadata_hierarchy.json の全内容

#### GET /admin/documents/{document_id}/images/{image_name}
- **機能**: 切り出し画像の取得
- **認証**: admin必須
- **対応形式**: PNG, JPG
- **セキュリティ**: パストラバーサル保護

### 5. ナレッジベース管理

#### POST /admin/knowledge-bases
- **機能**: ナレッジベース作成
- **認証**: admin必須

#### GET /admin/knowledge-bases
- **機能**: ナレッジベース一覧取得
- **認証**: admin必須

#### POST /admin/knowledge-bases/{kb_id}/documents/{doc_id}/vectorize
- **機能**: ドキュメントのベクトル化
- **認証**: admin必須
- **処理**: embeddinggemma による768次元埋め込み生成

---

## 関連サービス

### 依存サービス

| サービス | 依存理由 | 接続先 |
|---------|---------|-------|
| Auth Service | JWT検証（JWKS）、認可情報 | `http://host.docker.internal:8002` |
| User API | ユーザー情報取得 | `http://host.docker.internal:8001` |
| PostgreSQL | データ永続化 | `postgresql://host.docker.internal:5432/admindb` |
| Redis | キャッシュ・セッション | `redis://host.docker.internal:6379` |

### 利用サービス

| サービス | 利用方法 |
|---------|---------|
| Admin Frontend | 全機能で使用 |
| User Frontend | ドキュメント検索で使用 |

### サービス間通信

1. **Admin Frontend → Admin API**
   - ダッシュボード情報取得
   - ドキュメント処理リクエスト
   - システム管理操作

2. **Admin API → Auth Service**
   - JWKS取得（JWT検証用）
   - ユーザーロール確認

3. **Admin API → PostgreSQL (admindb)**
   - ログ・ドキュメント・ナレッジベースのCRUD
   - pgvectorベクトル検索

4. **Admin API → Redis**
   - セッション管理
   - 処理結果キャッシュ

---

## 環境変数

### 必須設定

```env
# Database
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/admindb

# Redis
REDIS_URL=redis://:password@host.docker.internal:6379

# Auth Service Integration
AUTH_SERVICE_URL=http://host.docker.internal:8002
API_SERVICE_URL=http://host.docker.internal:8001
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
JWT_ISSUER=https://auth.example.com
JWT_AUDIENCE=fastapi-api
JWT_SECRET_KEY=admin-service-secret-key

# Document Processing
EASYOCR_MODULE_PATH=/tmp/.easyocr_models
DOCLING_CACHE_DIR=/tmp/.docling_cache

# Logging
LOG_LEVEL=INFO
```

---

## 起動方法

### Docker Compose使用

```bash
cd ai-micro-api-admin
docker compose up -d

# ログ確認
docker compose logs -f ai-micro-admin-api

# サービス確認
curl http://localhost:8003/healthz
```

### ローカル開発

```bash
cd ai-micro-api-admin

# 依存関係インストール
poetry install

# 開発サーバー起動
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8003 --reload
```

### コンテナ再起動の重要性

**コード変更後は必ずDockerコンテナを再起動**:

```bash
cd ai-micro-api-admin
docker compose restart
```

理由:
- Pythonモジュールのインポートキャッシュ
- 新しい依存関係の反映
- FastAPIの自動リロード限界

---

## パフォーマンス特性

### ドキュメント処理時間

| ドキュメントサイズ | 処理時間目安 |
|------------------|------------|
| 1-5ページ | 30-60秒 |
| 6-20ページ | 1-3分 |
| 21-50ページ | 3-7分 |
| 51ページ以上 | 7分以上 |

### メモリ使用量

- 通常動作: 2-4GB
- ドキュメント処理中: 4-8GB
- 最大制限: 12GB（コンテナ制限）
- GC閾値: 4GB（自動ガベージコレクション実行）

### ベクトル検索パフォーマンス

- 1000件以下: < 100ms
- 10000件以下: < 500ms
- 100000件以上: IVFFlat/HNSWインデックス推奨

---

## セキュリティ

### 認証・認可

- 全エンドポイントでJWT必須（health除く）
- RS256署名検証（JWKS経由）
- ロールベースアクセス制御（RBAC）
  - `admin`: 基本管理操作
  - `super_admin`: システム全体制御

### データ保護

- ドキュメントアクセス制御（所有者・管理者のみ）
- パストラバーサル保護（正規表現検証）
- CORS設定で許可オリジン制御
- 機密データの環境変数管理

---

## 監視・ロギング

### ログ出力

```python
# リクエストログ
Request started - request_id: {uuid}, method: POST, url: /admin/documents/upload

# 処理進捗ログ（ドキュメント処理）
📈 DOCUMENT_PROGRESS: {"step": 3, "total": 10, "description": "Docling変換開始..."}

# 完了ログ
Request completed - request_id: {uuid}, endpoint: /admin/documents/upload,
  status: 200, process_time: 45.1234s

# エラーログ
Unhandled exception - request_id: {uuid}, error: {message}, traceback: ...
```

### ヘルスチェック

```bash
# 正常時
$ curl http://localhost:8003/healthz
{"status":"healthy","database":"ok","redis":"ok"}

# 異常時（503エラー）
{"status":"unhealthy","database":"ok","redis":"error"}
```

---

## トラブルシューティング

### よくある問題

1. **401 Unauthorized**
   - JWKSエンドポイントが到達不可
   - トークンのissuer/audienceミスマッチ

2. **Docling処理失敗**
   - メモリ不足（12GB制限超過）
   - Doclingキャッシュディレクトリ権限エラー
   - PDF形式非対応（破損ファイル）

3. **画像404エラー**
   - パスマッピング不一致
   - Dockerボリュームマウント問題
   - 処理中断による未生成

4. **ベクトル検索遅延**
   - pgvectorインデックス未作成
   - 埋め込み次元数ミスマッチ（768次元確認）

---

## 今後の拡張予定

- [ ] リアルタイムOCR編集機能
- [ ] マルチモーダル埋め込み対応
- [ ] ドキュメント差分検出機能
- [ ] バッチ処理ジョブスケジューラ
- [ ] プロンプトテンプレート管理強化

---

## 関連ドキュメント

- [API仕様詳細](./02-api-specification.md)
- [ドキュメント処理パイプライン](./03-document-processing.md)
- [OCR設計](./04-ocr-design.md)
- [階層構造変換](./05-hierarchy-converter.md)
- [データベース設計](./06-database-design.md)
- [認証フロー統合](/08-integration/02-authentication-flow.md)
- [システム全体アーキテクチャ](/00-overview/01-system-architecture.md)