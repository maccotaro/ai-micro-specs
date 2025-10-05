
# Implementation Plan: ナレッジベースのコレクション階層構造

**Branch**: `001-` | **Date**: 2025-10-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-specs/specs/001-/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code, or `AGENTS.md` for all other agents).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary

ナレッジベースの構造を**フラット型**(ナレッジベース→ドキュメント)から**階層型**(ナレッジベース→コレクション→ドキュメント)に変更します。

**主要な変更点**:
- 新規エンティティ「Collection」を導入（中間コンテナ）
- 各ナレッジベースには自動的にデフォルトコレクション("未分類")が作成される
- ドキュメントは必ず1つのコレクションに所属
- コレクション間でのドキュメント移動（ドラッグ&ドロップUI）をサポート
- 既存ドキュメントはデフォルトコレクションに自動移行

**技術アプローチ**:
- PostgreSQL admindb に `collections` テーブルを追加
- `documents` テーブルに `collection_id` 外部キーを追加
- Redis でコレクション一覧とドキュメント数をキャッシュ
- 3段階の移行戦略（スキーマ追加 → データ移行 → 制約追加）

## Technical Context

**Language/Version**:
- Backend: Python 3.11+
- Frontend: TypeScript 5.x, Node.js 20.x

**Primary Dependencies**:
- Backend: FastAPI, SQLAlchemy, Alembic, Redis
- Frontend: Next.js 14, React 18, TailwindCSS

**Storage**:
- PostgreSQL (admindb) - Collections, Documents
- Redis - キャッシング (collection list, document count)
- **重要**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/db/init.sql` の更新が必要

**Testing**:
- Backend: pytest (contract, integration, unit) - Docker環境で実行
- Frontend: Jest + React Testing Library (component) - Docker環境で実行
- E2E: Playwright (browser automation) - Docker環境で実行
- **実行環境**: すべてのテストはDocker内で実行
  - `docker exec ai-micro-api-admin poetry run pytest`
  - `docker exec ai-micro-front-admin npm test`
  - `docker exec ai-micro-front-admin npx playwright test`

**Target Platform**:
- Backend: Linux/Docker container
- Frontend: Web browser (Chrome, Firefox, Safari)

**Project Type**: web (マイクロサービスアーキテクチャ)

**Performance Goals**:
- API応答時間: <200ms (p95)
- ドキュメント検索: <500ms
- コレクション一覧取得: <100ms (Redisキャッシュ利用)

**Constraints**:
- ドキュメント移動操作: <1秒
- ドラッグ&ドロップUI: 60fps維持
- Redisキャッシュ無効化: O(1)操作

**Scale/Scope**:
- 想定ユーザー数: 100-1000ユーザー
- ナレッジベースあたりコレクション数: ~100
- コレクションあたりドキュメント数: ~1000

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**✅ Specification-First Development**: spec.mdが技術詳細なしでWHATとWHYを記述 ✓
**✅ Test-Driven Development**: tasks.mdでテストファースト実装を計画（Phase 3.2 → 3.3） ✓
**✅ Template-Driven Consistency**: spec-template.md, plan-template.md, tasks-template.mdに準拠 ✓
**✅ Phased Implementation Workflow**: Phase 0 (research.md) → Phase 1 (contracts, data-model) → Phase 2 (tasks.md) ✓
**✅ Parallel Execution Optimization**: tasks.mdで[P]マーク付与、ファイルパス明記 ✓
**✅ File Size Limit**: 新規ファイルは500行制限遵守、既存ファイルは段階的移行 ✓

### Microservices Integration Check
*For microservices projects only - refer to `.specify/memory/project-context-core.md` (details: `services/*.md`)*

**Service Scope**:
- [x] 既存サービスを特定: `ai-micro-api-admin` (Backend), `ai-micro-front-admin` (Frontend BFF)
- [x] 新規サービス不要（既存adminサービスの機能拡張）
- [x] サービス境界は明確（Admin API のみが collections テーブルを所有）

**API Contracts**:
- [x] API契約を定義: `contracts/collection-api.yml` (OpenAPI 3.0)
- [x] 全エンドポイントにコントラクトテストを計画（T007-T013）
- [x] 認証/認可アプローチ: 既存JWTトークン検証を継続使用

**Data Flow**:
- [x] データベース割り当て明確: admindb.collections, admindb.documents
- [x] クロスデータベースJOINなし（単一admindb内で完結）
- [x] Redis共有状態: コレクション一覧、ドキュメント数キャッシュ（TTL: 60-300秒）

**Impact Assessment**:
- [x] 後方互換性: ドキュメントAPIは既存機能を維持、collection_idは追加のみ
- [x] 破壊的変更なし: 3段階移行戦略（スキーマ追加 → データ移行 → 制約追加）
- [x] パフォーマンス影響: Redisキャッシングでコレクション取得を最適化、他サービスへの影響なし

**追加考慮事項**:
- [x] `init.sql` 更新が必要（collectionsテーブル定義追加）
- [x] 既存管理ユーザーを使用（quickstart.mdで新規作成不要）
- [x] Docker環境でのテスト実行を確保

## Project Structure

### Documentation (this feature)
```
/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-specs/specs/001-/
├── spec.md              # Feature specification ✅
├── plan.md              # This file (Implementation plan) ✅
├── research.md          # Phase 0 output ✅
├── data-model.md        # Phase 1 output ✅
├── quickstart.md        # Phase 1 output ✅
├── contracts/           # Phase 1 output ✅
│   └── collection-api.yml
└── tasks.md             # Phase 2 output ✅
```

### Source Code (microservices architecture)

```
ai-micro-api-admin/                                    # Backend Service
├── app/
│   ├── models/
│   │   └── collection.py                             # T021 (新規)
│   ├── routers/
│   │   ├── collections.py                            # T022-T027 (新規)
│   │   └── documents.py                              # T028 (更新)
│   ├── services/
│   │   ├── collection_service.py                     # T029 (新規)
│   │   └── document_service.py                       # T030 (更新)
│   └── core/
│       └── cache.py                                   # T031 (更新)
├── alembic/
│   └── versions/
│       ├── YYYYMMDD_add_collections_table.py         # T046 (新規)
│       └── YYYYMMDD_add_collection_id_to_docs.py     # T047 (新規)
└── tests/
    ├── contract/                                      # T007-T013
    ├── integration/                                   # T014-T018
    └── unit/                                          # (必要に応じて)

ai-micro-front-admin/                                  # Frontend BFF
├── src/
│   ├── components/
│   │   ├── CollectionList.tsx                        # T032 (新規)
│   │   ├── CollectionCreateModal.tsx                 # T033 (新規)
│   │   ├── CollectionDeleteDialog.tsx                # T034 (新規)
│   │   └── DocumentDragDrop.tsx                      # T035 (新規)
│   └── pages/
│       ├── knowledgebase/
│       │   └── [id]/
│       │       └── collections.tsx                   # T036 (新規)
│       └── collections/
│           └── [id].tsx                              # T039b (新規)
└── tests/
    ├── components/                                    # T019-T020 (Jest)
    └── e2e/                                           # T020b-T020e (Playwright)

ai-micro-postgres/
└── db/
    └── init.sql                                       # T047b (更新) - collectionsテーブル追加
```

**Structure Decision**: マイクロサービスアーキテクチャ（Web application）を採用。
- Backend: `ai-micro-api-admin` (FastAPI) - コレクション管理APIを提供
- Frontend: `ai-micro-front-admin` (Next.js) - コレクション管理UIを提供
- Database: `ai-micro-postgres` - admindb に collections テーブルを追加
- Cache: `ai-micro-redis` - コレクション一覧とドキュメント数をキャッシュ

## Phase 0: Outline & Research

**Status**: ✅ 完了

**成果物**: `research.md` (20,754 bytes)

**主要な調査結果**:
1. **データベース設計**: PostgreSQL部分UNIQUE制約でデフォルトコレクション一意性を保証
2. **Redisキャッシング戦略**: コレクション一覧(TTL:300s)、ドキュメント数(TTL:60s)
3. **ドラッグ&ドロップ実装**: react-beautiful-dnd または HTML5 Drag and Drop API
4. **API設計**: RESTful API（GET, POST, PUT, DELETE） + OpenAPI 3.0契約
5. **移行戦略**: 3段階（スキーマ追加 → データ移行 → 制約追加）でゼロダウンタイム移行

**すべてのNEEDS CLARIFICATIONを解決**: ✅

## Phase 1: Design & Contracts

**Status**: ✅ 完了

**成果物**:
1. ✅ `data-model.md` (11,066 bytes) - Collection, Document エンティティ定義
2. ✅ `contracts/collection-api.yml` - OpenAPI 3.0 契約（全7エンドポイント）
3. ✅ `quickstart.md` (14,101 bytes) - 5シナリオの手動テスト手順
4. ✅ Agent file updates準備完了（後述）

**エンティティ設計**:
- **Collection**: id, knowledge_base_id, name, description, is_default, timestamps
- **Document**: 既存フィールド + collection_id (新規FK)
- **関係**: KnowledgeBase (1) → Collection (many) → Document (many)

**API契約** (7エンドポイント):
1. `GET /api/collections` - コレクション一覧取得
2. `POST /api/collections` - コレクション作成
3. `GET /api/collections/{id}` - コレクション詳細取得
4. `PUT /api/collections/{id}` - コレクション更新
5. `DELETE /api/collections/{id}` - コレクション削除
6. `PUT /api/documents/{id}/move` - ドキュメント移動
7. `GET /api/search` - 検索（コレクション絞り込みオプション）

**コントラクトテスト準備**:
- tasks.md T007-T013 で各エンドポイントのコントラクトテストを定義
- すべてのテストは実装前に失敗する（TDD準拠）

**Agent File更新**:
```bash
.specify/scripts/bash/update-agent-context.sh claude
```
実行は実装フェーズで行う（Phase 1では準備のみ）

## Phase 2: Task Planning Approach

**Status**: ✅ 完了（/tasks コマンドで既に実行済み）

**成果物**: `tasks.md` (22,050 bytes, **62タスク**)

**タスク構成**:
- **Phase 3.1** セットアップ: 6タスク (T001-T006)
- **Phase 3.2** テストファースト: 18タスク (T007-T020e)
  - コントラクトテスト: 7タスク (T007-T013)
  - 統合テスト: 5タスク (T014-T018)
  - コンポーネントテスト: 2タスク (T019-T020)
  - **E2Eテスト (Playwright)**: 4タスク (T020b-T020e) ← **追加**
- **Phase 3.3** コア実装: 25タスク (T021-T045)
- **Phase 3.4** データ移行: 4タスク (T046-T047b)
  - **T047b**: `init.sql` 更新タスク ← **追加**
- **Phase 3.5** 統合: 3タスク (T049-T051)
- **Phase 3.6** 仕上げ: 7タスク (T052-T058)

**並列実行最適化**:
- [P]マーク付きタスク: 独立したファイル操作で並列実行可能
- 例: T007-T013 (コントラクトテスト), T021-T025 (モデル・ルーター)

**TDD順序**:
- Phase 3.2 (テスト) → Phase 3.3 (実装)
- すべてのテストは最初に失敗することを確認

**Docker環境でのテスト実行**:
- Backend: `docker exec ai-micro-api-admin poetry run pytest`
- Frontend: `docker exec ai-micro-front-admin npm test`
- E2E: `docker exec ai-micro-front-admin npx playwright test`

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: タスク実行 (tasks.mdに記載された62タスクを実行)
- Phase 3.1: 環境セットアップ（Alembic、Playwright等）
- Phase 3.2: テストファースト実装（コントラクト、統合、E2E）
- Phase 3.3: コア実装（モデル、API、フロントエンド）
- Phase 3.4: データ移行（Alembic migrations + init.sql更新）
- Phase 3.5: 統合テスト
- Phase 3.6: ドキュメント整備

**Phase 4**: 検証
- すべてのテストが成功することを確認
- quickstart.mdの手動シナリオを実行
- パフォーマンス検証（API応答時間、キャッシュ効率）

**Phase 5**: デプロイ準備
- Docker環境での最終動作確認
- CLAUDE.md更新（新規API、環境変数）
- コミット＆プッシュ

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

**Constitution違反なし** - すべてのチェック項目が合格しています。


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] **Phase 0**: Research complete (/plan command) ✅
  - 成果物: research.md (20,754 bytes)
  - すべてのNEEDS CLARIFICATION解決済み
- [x] **Phase 1**: Design complete (/plan command) ✅
  - 成果物: data-model.md, contracts/collection-api.yml, quickstart.md
  - エンティティ設計、API契約、テストシナリオ完成
- [x] **Phase 2**: Task planning complete (/tasks command) ✅
  - 成果物: tasks.md (62タスク)
  - Playwrightタスク追加、init.sql更新タスク追加
- [ ] **Phase 3**: Implementation in progress
  - 次のステップ: /implement コマンドでtasks.mdを実行
- [ ] **Phase 4**: Validation pending
- [ ] **Phase 5**: Deployment preparation pending

**Gate Status**:
- [x] **Initial Constitution Check**: PASS ✅
  - すべての原則に準拠（Specification-First, TDD, Template-Driven等）
- [x] **Post-Design Constitution Check**: PASS ✅
  - Microservices Integration Check完了
  - File Size Limit遵守計画
  - Docker環境でのテスト実行確保
- [x] **All NEEDS CLARIFICATION resolved**: ✅
  - Clarificationsセクション（5質問）すべて回答済み
- [x] **Complexity deviations documented**: N/A (違反なし) ✅

**重要な追加対応**:
- [x] init.sql更新をタスクに追加 (T047b)
- [x] 既存管理ユーザー使用をquickstart.mdに記載
- [x] Dockerテスト戦略をTechnical Contextに明記
- [x] Playwrightタスク追加 (T020b-T020e)

---
*Based on Constitution v1.2.0 - See `.specify/memory/constitution.md`*
*Plan completed on 2025-10-05 | Branch: 001- | Ready for /implement*
