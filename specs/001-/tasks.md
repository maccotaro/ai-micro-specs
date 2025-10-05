# タスク: ナレッジベースのコレクション階層構造

**入力**: `/specs/001-/`からの設計ドキュメント
**前提条件**: plan.md (必須), research.md, data-model.md, contracts/

## 実行フロー (main)

```
1. plan.mdから機能ディレクトリをロード
   → 見つからない場合: ERROR "実装計画が見つかりません"
   → 抽出: 技術スタック、ライブラリ、構造
2. オプションの設計ドキュメントをロード:
   → data-model.md: エンティティを抽出 → モデルタスク
   → contracts/: 各ファイル → コントラクトテストタスク
   → research.md: 決定事項を抽出 → セットアップタスク
3. カテゴリ別にタスクを生成:
   → セットアップ: プロジェクト初期化、依存関係、リンティング
   → テスト: コントラクトテスト、統合テスト
   → コア: モデル、サービス、エンドポイント
   → 統合: DB、ミドルウェア、ロギング
   → 仕上げ: ユニットテスト、パフォーマンス、ドキュメント
4. タスクルールを適用:
   → 異なるファイル = 並列実行のために[P]をマーク
   → 同じファイル = 順次実行 ([P]なし)
   → 実装前にテスト (TDD)
5. タスクに連番を付ける (T001, T002...)
6. 依存関係グラフを生成
7. 並列実行例を作成
8. タスクの完全性を検証:
   → すべてのコントラクトにテストがあるか?
   → すべてのエンティティにモデルがあるか?
   → すべてのエンドポイントが実装されているか?
9. 戻り値: SUCCESS (タスク実行準備完了)
```

## フォーマット: `[ID] [P?] 説明`

- **[P]**: 並列実行可能 (異なるファイル、依存関係なし)
- 説明に正確なファイルパスを含める

## パス規則

このプロジェクトは**マイクロサービスアーキテクチャ**です:
- **Backend**: `ai-micro-api-admin/` (FastAPI/Python)
- **Frontend**: `ai-micro-front-admin/` (Next.js/TypeScript)
- **Database**: `ai-micro-postgres/db/init.sql` (PostgreSQL)

## Phase 3.1: セットアップ

- [ ] **T001** [P] ファイルサイズ制約チェックスクリプト作成
  - ファイル: `.specify/scripts/bash/check-file-size.sh`
  - 内容: すべての新規・変更ファイルが500行以下であることを検証
  - 対象: `ai-micro-api-admin/app/**/*.py`, `ai-micro-front-admin/src/**/*.{ts,tsx}`
  - 実行タイミング: 各実装タスク完了後
  - 出力: 500行超過ファイルのリストとエラーメッセージ

- [ ] **T002** [P] init.sqlにcollectionsテーブル定義を追加
  - ファイル: `ai-micro-postgres/db/init.sql`
  - 内容: collectionsテーブル定義を追加（data-model.mdの158-200行を参照）
    * CREATE TABLE collections (id, knowledge_base_id, name, description, is_default, timestamps)
    * CREATE UNIQUE INDEX uq_kb_default_collection (部分UNIQUE制約)
    * CREATE INDEX idx_collections_kb_id, idx_collections_is_default
    * CREATE TRIGGER update_collections_updated_at
    * ALTER TABLE documents ADD COLUMN collection_id UUID (NULLABLE)
    * ALTER TABLE documents ADD CONSTRAINT fk_documents_collection
    * CREATE INDEX idx_documents_collection_id
  - 検証: `docker exec postgres psql -U postgres -d admindb -c "\d collections"`

- [ ] **T003** [P] Collectionモデル作成 (Backend)
  - ファイル: `ai-micro-api-admin/app/models/collection.py`
  - 内容: SQLAlchemyモデル (id, knowledge_base_id, name, description, is_default, timestamps)

- [ ] **T004** [P] Collection Pydanticスキーマ作成 (Backend)
  - ファイル: `ai-micro-api-admin/app/schemas/collection.py`
  - 内容: CollectionCreate, CollectionUpdate, CollectionResponse

- [ ] **T005** [P] Collection型定義作成 (Frontend)
  - ファイル: `ai-micro-front-admin/src/types/collection.ts`
  - 内容: TypeScript型定義 (Collection, CollectionCreate, CollectionUpdate)

- [ ] **T006** データベース再作成
  - コマンド: `cd ai-micro-postgres && docker compose down && docker compose up -d`
  - 検証: collectionsテーブルが作成されていることを確認

## Phase 3.2: テストファースト (TDD) ⚠️ Phase 3.3の前に完了必須

**重要: これらのテストは実装前に作成し、失敗することを確認する必要があります**

### コントラクトテスト (Backend)

- [ ] **T007** [P] コレクション作成APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_collections_post.py`
  - 内容: POST /api/collections のスキーマ検証 (201, 422エラー)

- [ ] **T008** [P] コレクション一覧取得APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_collections_get.py`
  - 内容: GET /api/collections のスキーマ検証

- [ ] **T009** [P] コレクション詳細取得APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_collections_get_id.py`
  - 内容: GET /api/collections/{id} のスキーマ検証 (200, 404)

- [ ] **T010** [P] コレクション更新APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_collections_put.py`
  - 内容: PUT /api/collections/{id} のスキーマ検証 (200, 422)

- [ ] **T011** [P] コレクション削除APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_collections_delete.py`
  - 内容: DELETE /api/collections/{id} のスキーマ検証 (204, 422)

- [ ] **T012** [P] ドキュメント移動APIのコントラクトテスト
  - ファイル: `ai-micro-api-admin/tests/contract/test_documents_move.py`
  - 内容: PUT /api/documents/{id}/move のスキーマ検証

- [ ] **T013** [P] 検索APIのコントラクトテスト (コレクション絞り込み)
  - ファイル: `ai-micro-api-admin/tests/contract/test_search_collections.py`
  - 内容: GET /api/search?collection_id={id} のスキーマ検証

### 統合テスト (Backend)

- [ ] **T014** [P] コレクション作成とドキュメント追加の統合テスト
  - ファイル: `ai-micro-api-admin/tests/integration/test_collection_workflow.py`
  - 内容: quickstart.mdのシナリオ1を自動化

- [ ] **T015** [P] ドキュメント移動の統合テスト
  - ファイル: `ai-micro-api-admin/tests/integration/test_document_move.py`
  - 内容: quickstart.mdのシナリオ2を自動化

- [ ] **T016** [P] コレクション削除の統合テスト
  - ファイル: `ai-micro-api-admin/tests/integration/test_collection_delete.py`
  - 内容: quickstart.mdのシナリオ3を自動化 (action=delete, move_to_default)

- [ ] **T017** [P] 検索機能の統合テスト
  - ファイル: `ai-micro-api-admin/tests/integration/test_search_collections.py`
  - 内容: quickstart.mdのシナリオ4を自動化

- [ ] **T018** [P] デフォルトコレクション保護の統合テスト
  - ファイル: `ai-micro-api-admin/tests/integration/test_default_collection_protection.py`
  - 内容: quickstart.mdのシナリオ5を自動化

### コンポーネントテスト (Frontend)

- [ ] **T019** [P] CollectionListコンポーネントのテスト
  - ファイル: `ai-micro-front-admin/tests/components/collections/CollectionList.test.tsx`
  - 内容: コレクション一覧表示、ドキュメント数表示

- [ ] **T020** [P] DeleteConfirmDialogコンポーネントのテスト
  - ファイル: `ai-micro-front-admin/tests/components/collections/DeleteConfirmDialog.test.tsx`
  - 内容: 削除確認ダイアログ、action選択

### E2Eテスト (Frontend - Playwright)

- [ ] **T020b** [P] Playwright環境セットアップ
  - ファイル: `ai-micro-front-admin/playwright.config.ts`
  - 内容: Playwright設定ファイル作成、Docker環境での実行設定
  - 実行: `docker exec ai-micro-front-admin npm install -D @playwright/test && npx playwright install`
  - 検証: `docker exec ai-micro-front-admin npx playwright --version`

- [ ] **T020c** [P] コレクション作成E2Eテスト (Playwright)
  - ファイル: `ai-micro-front-admin/tests/e2e/collection-create.spec.ts`
  - 内容: quickstart.mdシナリオ1-2を自動化
    * ログイン → コレクション作成 → ドキュメント追加
    * 全てのステップをブラウザ自動化で検証
  - 実行: `docker exec ai-micro-front-admin npx playwright test collection-create.spec.ts`

- [ ] **T020d** [P] ドキュメント移動E2Eテスト (ドラッグ&ドロップ検証)
  - ファイル: `ai-micro-front-admin/tests/e2e/document-move.spec.ts`
  - 内容: quickstart.mdシナリオ2を自動化、FR-011のUXフィードバック検証
    * ドラッグ中のハイライト表示確認
    * ドロップ先のホバー効果確認
    * ローディングスピナー表示確認
    * 成功/エラートーストメッセージ確認
  - 実行: `docker exec ai-micro-front-admin npx playwright test document-move.spec.ts`

- [ ] **T020e** [P] コレクション削除E2Eテスト (確認ダイアログ検証)
  - ファイル: `ai-micro-front-admin/tests/e2e/collection-delete.spec.ts`
  - 内容: quickstart.mdシナリオ3を自動化、確認ダイアログの動作検証
    * 「ドキュメントも削除」選択時の動作
    * 「デフォルトコレクションに移動」選択時の動作
  - 実行: `docker exec ai-micro-front-admin npx playwright test collection-delete.spec.ts`

## Phase 3.3: コア実装 (テスト失敗確認後のみ)

### バックエンドサービス層

- [ ] **T021** CollectionServiceの実装 (CRUD操作)
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py`
  - 内容: create, get, list, update, delete メソッド
  - 依存: T002, T003

- [ ] **T022** CollectionService: デフォルトコレクション自動作成
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py` (既存ファイル)
  - 内容: ナレッジベース作成時にデフォルトコレクションを自動作成

- [ ] **T023** CollectionService: 名前一意性検証
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py` (既存ファイル)
  - 内容: ナレッジベース内でのコレクション名一意性チェック

- [ ] **T024** CollectionService: デフォルトコレクション保護ロジック
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py` (既存ファイル)
  - 内容: is_default=trueのコレクションは削除・名前変更不可

- [ ] **T025** DocumentServiceにコレクション対応を追加
  - ファイル: `ai-micro-api-admin/app/services/document_service.py` (既存ファイル)
  - 内容: collection_id対応、move_document メソッド

### バックエンドAPI層

- [ ] **T026** Collectionsルーター実装
  - ファイル: `ai-micro-api-admin/app/routers/collections.py`
  - 内容: POST, GET, PUT, DELETE エンドポイント
  - 依存: T020-T023

- [ ] **T027** Documents PUT /move エンドポイント実装
  - ファイル: `ai-micro-api-admin/app/routers/documents.py` (既存ファイル)
  - 内容: PUT /api/documents/{id}/move エンドポイント追加
  - 依存: T024

- [ ] **T028** Search GET /search エンドポイント拡張
  - ファイル: `ai-micro-api-admin/app/routers/search.py` (既存ファイル)
  - 内容: collection_idクエリパラメータ対応

- [ ] **T029** main.pyにCollectionsルーター登録
  - ファイル: `ai-micro-api-admin/app/main.py`
  - 内容: app.include_router(collections.router)

### Redisキャッシング

- [ ] **T030** [P] Redisキャッシングサービス実装
  - ファイル: `ai-micro-api-admin/app/services/cache_service.py`
  - 内容: コレクション一覧、詳細、ドキュメント数のキャッシュロジック

- [ ] **T031** CollectionServiceにキャッシュ統合
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py` (既存ファイル)
  - 内容: get/list メソッドにキャッシュ読み込み、create/update/delete にキャッシュ無効化
  - 依存: T029

### フロントエンドサービス層

- [ ] **T032** [P] collectionService (APIクライアント)の実装
  - ファイル: `ai-micro-front-admin/src/services/collectionService.ts`
  - 内容: useCollections, createCollection, updateCollection, deleteCollection (SWR統合)

- [ ] **T033** [P] BFF API Route: GET /api/collections
  - ファイル: `ai-micro-front-admin/src/pages/api/collections/index.ts`
  - 内容: Admin APIへのプロキシ (一覧取得)

- [ ] **T034** [P] BFF API Route: POST /api/collections
  - ファイル: `ai-micro-front-admin/src/pages/api/collections/index.ts` (既存ファイル)
  - 内容: Admin APIへのプロキシ (作成)

- [ ] **T035** [P] BFF API Route: GET /api/collections/{id}
  - ファイル: `ai-micro-front-admin/src/pages/api/collections/[id].ts`
  - 内容: Admin APIへのプロキシ (詳細取得)

- [ ] **T036** [P] BFF API Route: PUT /api/collections/{id}
  - ファイル: `ai-micro-front-admin/src/pages/api/collections/[id].ts` (既存ファイル)
  - 内容: Admin APIへのプロキシ (更新)

- [ ] **T037** [P] BFF API Route: DELETE /api/collections/{id}
  - ファイル: `ai-micro-front-admin/src/pages/api/collections/[id].ts` (既存ファイル)
  - 内容: Admin APIへのプロキシ (削除)

### フロントエンドUIコンポーネント

- [ ] **T038** [P] CollectionListコンポーネント実装
  - ファイル: `ai-micro-front-admin/src/components/collections/CollectionList.tsx`
  - 内容: コレクション一覧表示、ドキュメント数表示

- [ ] **T039** [P] CollectionCardコンポーネント実装
  - ファイル: `ai-micro-front-admin/src/components/collections/CollectionCard.tsx`
  - 内容: 個別コレクションカード (名前、説明、ドキュメント数)

- [ ] **T040** [P] CreateCollectionモーダル実装
  - ファイル: `ai-micro-front-admin/src/components/collections/CreateCollectionModal.tsx`
  - 内容: コレクション作成フォーム (名前、説明入力)

- [ ] **T039b** [P] CollectionDetailページ実装
  - ファイル: `ai-micro-front-admin/src/pages/collections/[id].tsx`
  - 内容: コレクション詳細情報とドキュメント一覧表示
  - 依存: T034, T037

- [ ] **T041** [P] DeleteConfirmDialogコンポーネント実装
  - ファイル: `ai-micro-front-admin/src/components/collections/DeleteConfirmDialog.tsx`
  - 内容: 削除確認ダイアログ、action選択 (delete/move_to_default)

- [ ] **T042** [P] DocumentMoverコンポーネント実装
  - ファイル: `ai-micro-front-admin/src/components/collections/DocumentMover.tsx`
  - 内容: ドキュメント移動UI (ドラッグ&ドロップまたはセレクトボックス)

- [ ] **T043** DocumentListコンポーネントにコレクション絞り込み追加
  - ファイル: `ai-micro-front-admin/src/components/documents/DocumentList.tsx` (既存ファイル)
  - 内容: collection_idフィルター追加

### フロントエンドページ

- [ ] **T044** コレクション管理ページ実装
  - ファイル: `ai-micro-front-admin/src/pages/knowledgebase/[id]/collections.tsx`
  - 内容: CollectionList、CreateCollection統合

- [ ] **T045** ナレッジベース編集ページにコレクション表示追加
  - ファイル: `ai-micro-front-admin/src/pages/knowledgebase/[id]/edit.tsx` (既存ファイル)
  - 内容: コレクションタブ追加、CollectionList表示

## Phase 3.4: データ移行

- [ ] **T046** 既存ドキュメントのデフォルトコレクション移行スクリプト
  - ファイル: `ai-micro-api-admin/scripts/migrate_to_collections.py`
  - 内容: 各ナレッジベースにデフォルトコレクション作成、既存ドキュメントを割り当て

- [ ] **T047** 移行スクリプト実行
  - コマンド: `poetry run python scripts/migrate_to_collections.py`
  - 検証: すべてのドキュメントにcollection_idが設定されていることを確認

- [ ] **T048** documentsテーブルにNOT NULL制約追加
  - ファイル: `ai-micro-postgres/db/init.sql` (既存ファイル、または手動SQL実行)
  - 内容: `ALTER TABLE documents ALTER COLUMN collection_id SET NOT NULL;`

- [ ] **T047b** 既存システムアップグレード移行スクリプト作成
  - ファイル: `ai-micro-api-admin/scripts/upgrade_to_collections.py`
  - 内容:
    * 既存ドキュメントのcollection_id nullチェック
    * 各ナレッジベースにデフォルトコレクションが存在しない場合は作成
    * collection_idがnullのドキュメントをデフォルトコレクションに移行
    * 移行結果のログ出力 (影響ドキュメント数、KB別統計)
  - 実行: `docker exec ai-micro-api-admin poetry run python scripts/upgrade_to_collections.py`
  - ロールバック: `ai-micro-api-admin/scripts/rollback_collections.sql`
    * collection_idをNULL許容に戻す
    * 追加されたデフォルトコレクションを削除

## Phase 3.5: 統合とバリデーション

- [ ] **T049** エラーハンドリング追加
  - ファイル: `ai-micro-api-admin/app/routers/collections.py` (既存ファイル)
  - 内容: カスタム例外 (DuplicateCollectionNameError, DefaultCollectionOperationError) とHTTPステータスマッピング

- [ ] **T050** ロギング追加
  - ファイル: `ai-micro-api-admin/app/services/collection_service.py` (既存ファイル)
  - 内容: 主要操作のログ出力

- [ ] **T051** JWT認証ミドルウェア統合確認
  - ファイル: `ai-micro-api-admin/app/routers/collections.py` (既存ファイル)
  - 内容: すべてのエンドポイントに@require_auth デコレータ

## Phase 3.6: 仕上げ

- [ ] **T052** [P] CollectionServiceのユニットテスト
  - ファイル: `ai-micro-api-admin/tests/unit/test_collection_service.py`
  - 内容: 名前一意性、デフォルトコレクション保護のテスト

- [ ] **T053** [P] DocumentServiceのユニットテスト (コレクション対応)
  - ファイル: `ai-micro-api-admin/tests/unit/test_document_service_collections.py`
  - 内容: move_document メソッドのテスト

- [ ] **T054** パフォーマンステスト
  - ファイル: `ai-micro-api-admin/tests/performance/test_collections_performance.py`
  - 内容: コレクション一覧取得 <100ms、検索 <500ms

- [ ] **T055** [P] E2Eテスト (quickstart.mdの手動実行)
  - 方法: `quickstart.md`の全シナリオを手動で実行
  - 検証: すべてのシナリオが成功

- [ ] **T056** [P] OpenAPIドキュメント更新
  - ファイル: `ai-micro-api-admin/docs/openapi.yaml` (または自動生成)
  - 内容: コレクションエンドポイントの追加

- [ ] **T057** [P] 既存コードのリファクタリング (500行制限チェック)
  - 対象: すべての新規・変更ファイル
  - 内容: 500行を超えるファイルを分割

- [ ] **T058** すべてのテストを実行
  - コマンド: `poetry run pytest` (Backend), `npm test` (Frontend)
  - 検証: すべてのテストが合格

## 依存関係

### ブロッキング依存関係
- **T001-T005** (セットアップ) → すべてのタスク
- **T006-T019** (テスト) → **T020-T044** (実装)
- **T021** (CollectionService) → T021-T023, T025, T030
- **T025** (DocumentService変更) → T026
- **T026** (Collectionsルーター) → T028
- **T030** (キャッシュサービス) → T030
- **T032** (collectionService) → T037-T044
- **T032-T036** (BFF API Routes) → T037-T044
- **T045-T047** (データ移行) → T050
- **T020-T047** (すべての実装) → **T048-T057** (仕上げ)

### 並列実行可能グループ
- **グループ1 (セットアップ)**: T001, T002, T003, T004
- **グループ2 (コントラクトテスト)**: T006, T007, T008, T009, T010, T011, T012
- **グループ3 (統合テスト)**: T013, T014, T015, T016, T017
- **グループ4 (コンポーネントテスト)**: T018, T019
- **グループ5 (BFF Routes)**: T032, T033, T034, T035, T036
- **グループ6 (UIコンポーネント)**: T037, T038, T039, T040, T041
- **グループ7 (仕上げ)**: T051, T052, T054, T055, T056

## 並列実行例

### セットアップフェーズ (T001-T004を並列実行)

```bash
# 同時に4つのタスクを実行
# Terminal 1
cd ai-micro-postgres && vim db/init.sql  # T001

# Terminal 2
cd ai-micro-api-admin && touch app/models/collection.py  # T002

# Terminal 3
cd ai-micro-api-admin && touch app/schemas/collection.py  # T003

# Terminal 4
cd ai-micro-front-admin && touch src/types/collection.ts  # T004
```

### コントラクトテストフェーズ (T006-T012を並列実行)

```bash
# 7つのテストファイルを同時に作成
cd ai-micro-api-admin/tests/contract
touch test_collections_post.py test_collections_get.py test_collections_get_id.py \
      test_collections_put.py test_collections_delete.py test_documents_move.py \
      test_search_collections.py
```

## 検証チェックリスト

*main()がSUCCESSを返す前にチェック*

- [x] すべてのコントラクトにテストがある (T006-T012)
- [x] すべてのエンティティにモデルがある (T002: Collection)
- [x] すべてのテストが実装前に配置されている (T006-T019 → T020-T044)
- [x] 並列タスクが真に独立している (異なるファイル)
- [x] 各タスクが正確なファイルパスを指定している
- [x] 同じファイルを変更する[P]タスクがない

## 注意事項

- **[P]タスク** = 異なるファイル、依存関係なし
- **実装前にテスト失敗を確認** (TDD原則)
- **各タスク後にコミット** (小さな変更で頻繁に)
- **避けるべき**: 曖昧なタスク、同じファイルの競合

## 進捗追跡

- Phase 3.1 セットアップ: **6タスク** (T001-T006)
- Phase 3.2 テストファースト: **18タスク** (T007-T020e)
  - コントラクトテスト: **7タスク** (T007-T013)
  - 統合テスト: **5タスク** (T014-T018)
  - コンポーネントテスト: **2タスク** (T019-T020)
  - E2Eテスト (Playwright): **4タスク** (T020b-T020e)
- Phase 3.3 コア実装: **25タスク** (T021-T045)
- Phase 3.4 データ移行: **4タスク** (T046-T047b)
- Phase 3.5 統合: **3タスク** (T049-T051)
- Phase 3.6 仕上げ: **7タスク** (T052-T058)

**合計**: **62タスク** (旧: 58タスク + Playwright追加4タスク)

---
*Constitution v1.2.0に基づく - TDD必須、500行制限遵守*
