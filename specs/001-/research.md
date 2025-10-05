# 調査レポート: ナレッジベースのコレクション階層構造

**作成日**: 2025-10-05
**機能**: ナレッジベース→コレクション→ドキュメントの階層構造導入

## 調査概要

この調査では、コレクション階層機能を実装するための技術的な決定事項とベストプラクティスを文書化します。

## 1. PostgreSQLスキーマ設計のベストプラクティス

### 決定: is_defaultフラグとUNIQUE制約を使用

**選択した設計**:
```sql
CREATE TABLE collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_base_id UUID NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_kb_collection_name UNIQUE (knowledge_base_id, name),
    CONSTRAINT uq_kb_default_collection UNIQUE (knowledge_base_id, is_default) WHERE is_default = TRUE
);

CREATE INDEX idx_collections_kb_id ON collections(knowledge_base_id);
CREATE INDEX idx_collections_is_default ON collections(knowledge_base_id, is_default);

ALTER TABLE documents ADD COLUMN collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE RESTRICT;
CREATE INDEX idx_documents_collection_id ON documents(collection_id);
```

**根拠**:
- **is_defaultフラグ**: 特別なUUIDよりも明示的で、クエリが簡単
- **UNIQUE制約 (WHERE is_default = TRUE)**: PostgreSQLの部分インデックスで、ナレッジベースごとに1つのデフォルトコレクションのみを保証
- **ON DELETE CASCADE (knowledge_bases → collections)**: ナレッジベース削除時に自動的にコレクションを削除
- **ON DELETE RESTRICT (collections → documents)**: 意図しないドキュメント削除を防ぐ。アプリケーションレイヤーでユーザーの選択を処理
- **複合インデックス**: `(knowledge_base_id, name)`で名前の一意性チェックとコレクション一覧取得を高速化
- **インデックス戦略**: `documents.collection_id`にインデックスを追加して、コレクション内のドキュメント一覧取得を高速化

**検討した代替案**:
1. **特別なデフォルトコレクションID (例: 00000000-0000-0000-0000-000000000001)**
   - 却下理由: マジックナンバーは保守性が低く、複数ナレッジベースでの管理が複雑
2. **ソフトデリート (deleted_atカラム)**
   - 却下理由: 現時点で監査ログやアンドゥ機能の要件なし。必要に応じて将来追加可能
3. **ON DELETE CASCADE (collections → documents)**
   - 却下理由: ユーザーが明示的に選択できるようにする必要がある (仕様要件)

## 2. FastAPIでのCRUD操作パターン

### 決定: Repositoryパターン + Pydanticスキーマ分離

**選択したパターン**:
```python
# app/models/collection.py (SQLAlchemyモデル)
class Collection(Base):
    __tablename__ = "collections"
    id = Column(UUID, primary_key=True, default=uuid4)
    knowledge_base_id = Column(UUID, ForeignKey("knowledge_bases.id"), nullable=False)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    is_default = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

# app/schemas/collection.py (Pydanticスキーマ)
class CollectionCreate(BaseModel):
    knowledge_base_id: UUID
    name: str
    description: Optional[str] = None

class CollectionResponse(BaseModel):
    id: UUID
    knowledge_base_id: UUID
    name: str
    description: Optional[str]
    is_default: bool
    document_count: int
    created_at: datetime
    updated_at: datetime

# app/services/collection_service.py (ビジネスロジック)
class CollectionService:
    async def create_collection(self, db: Session, data: CollectionCreate) -> Collection:
        # 名前の一意性チェック
        # デフォルトコレクションの自動作成ロジック
        # トランザクション管理
        pass
```

**根拠**:
- **Repositoryパターン**: データアクセスロジックをサービスレイヤーから分離し、テストを容易に
- **Pydanticスキーマ分離**: API入出力とDBモデルを分離し、柔軟性を向上 (例: `document_count`は計算フィールド)
- **トランザクション管理**: SQLAlchemyのセッションコンテキストマネージャーで自動コミット/ロールバック
- **エラーハンドリング**: カスタム例外クラス (`DuplicateCollectionNameError`, `DefaultCollectionOperationError`) でHTTPステータスコードにマッピング

**コレクション削除時のトランザクション管理**:
```python
async def delete_collection(
    self,
    db: Session,
    collection_id: UUID,
    action: Literal["delete", "move_to_default"]
) -> None:
    async with db.begin():  # トランザクション開始
        collection = await self.get_collection(db, collection_id)
        if collection.is_default:
            raise DefaultCollectionOperationError("Cannot delete default collection")

        if action == "delete":
            # カスケード削除 (ON DELETE RESTRICTを解除)
            await db.execute(delete(Document).where(Document.collection_id == collection_id))
        elif action == "move_to_default":
            # デフォルトコレクションに移動
            default_collection = await self.get_default_collection(db, collection.knowledge_base_id)
            await db.execute(
                update(Document)
                .where(Document.collection_id == collection_id)
                .values(collection_id=default_collection.id)
            )

        await db.delete(collection)
    # トランザクション終了 (成功時コミット、エラー時ロールバック)
```

**検討した代替案**:
1. **Active Recordパターン (モデルにビジネスロジックを含める)**
   - 却下理由: テストが困難で、ビジネスロジックがモデルに密結合
2. **Pydantic v2のComputed Fields (document_countをモデルで計算)**
   - 却下理由: N+1問題のリスク。サービスレイヤーでの明示的なクエリを推奨

## 3. Redisキャッシング戦略

### 決定: レイジーロード + TTLベース無効化

**選択した戦略**:
```python
# キャッシュキーパターン
COLLECTION_LIST_KEY = "collection:{kb_id}:list"  # TTL: 300秒
COLLECTION_DETAILS_KEY = "collection:{id}:details"  # TTL: 300秒
COLLECTION_DOC_COUNT_KEY = "collection:{id}:doc_count"  # TTL: 60秒

# レイジーロードパターン
async def get_collections(self, kb_id: UUID) -> List[CollectionResponse]:
    cache_key = COLLECTION_LIST_KEY.format(kb_id=kb_id)
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    # キャッシュミス → DBクエリ
    collections = await db.query(Collection).filter_by(knowledge_base_id=kb_id).all()
    await redis.setex(cache_key, 300, json.dumps(collections))
    return collections

# 書き込み時の無効化
async def create_collection(self, data: CollectionCreate) -> Collection:
    collection = await db.save(Collection(**data))
    # コレクション一覧キャッシュを無効化
    await redis.delete(COLLECTION_LIST_KEY.format(kb_id=data.knowledge_base_id))
    return collection
```

**根拠**:
- **レイジーロード**: キャッシュウォームアップより実装が簡単で、不要なキャッシュエントリを避ける
- **TTLベース無効化**: 最終的な一貫性を許容し、複雑な無効化ロジックを回避
- **短いTTL (60秒) for document_count**: ドキュメント追加/削除が頻繁な場合でも比較的新鮮な数値
- **長いTTL (300秒) for コレクション一覧**: コレクション作成/削除は稀なため、長めのTTL
- **書き込み時無効化**: 作成/更新/削除時に関連キャッシュを明示的に削除し、即座に反映

**ドキュメント数カウンターキャッシュ**:
```python
async def get_document_count(self, collection_id: UUID) -> int:
    cache_key = COLLECTION_DOC_COUNT_KEY.format(id=collection_id)
    cached = await redis.get(cache_key)
    if cached:
        return int(cached)

    count = await db.query(func.count(Document.id)).filter_by(collection_id=collection_id).scalar()
    await redis.setex(cache_key, 60, str(count))
    return count
```

**検討した代替案**:
1. **キャッシュウォームアップ (サーバー起動時に全コレクションをキャッシュ)**
   - 却下理由: ナレッジベース数が多い場合、メモリとCPUを大量消費
2. **イベントベース無効化 (PubSubでキャッシュ無効化通知)**
   - 却下理由: 過剰な複雑性。TTLベースで十分
3. **データベース内カウンターカラム (collections.document_count)**
   - 却下理由: トランザクション管理が複雑で、不整合のリスク。Redisキャッシュで十分

## 4. Next.jsでのBFFパターン実装

### 決定: API Routes + SWR (stale-while-revalidate)

**選択したパターン**:
```typescript
// pages/api/collections/index.ts (BFF API Route)
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const session = await getSession(req, res);
  if (!session) return res.status(401).json({ error: 'Unauthorized' });

  const { knowledge_base_id } = req.query;

  // バックエンドAPIにプロキシ
  const response = await fetch(
    `${process.env.ADMIN_API_URL}/api/collections?knowledge_base_id=${knowledge_base_id}`,
    {
      headers: {
        Authorization: `Bearer ${session.accessToken}`,
      },
    }
  );

  const data = await response.json();
  return res.status(response.status).json(data);
}

// services/collectionService.ts (クライアント側)
import useSWR from 'swr';

export function useCollections(knowledgeBaseId: string) {
  const { data, error, mutate } = useSWR(
    `/api/collections?knowledge_base_id=${knowledgeBaseId}`,
    fetcher,
    {
      revalidateOnFocus: false,
      dedupingInterval: 5000, // 5秒以内の重複リクエストを避ける
    }
  );

  return {
    collections: data?.collections ?? [],
    isLoading: !error && !data,
    isError: error,
    mutate, // 楽観的更新用
  };
}
```

**楽観的UI更新パターン**:
```typescript
// components/collections/CreateCollection.tsx
async function createCollection(data: CollectionCreate) {
  const optimisticCollection = {
    id: crypto.randomUUID(), // 一時ID
    ...data,
    is_default: false,
    document_count: 0,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  // 楽観的更新 (即座にUIを更新)
  mutate(
    async (currentData) => ({
      collections: [...(currentData?.collections ?? []), optimisticCollection],
    }),
    false // サーバーへの再検証をスキップ
  );

  try {
    // サーバーにリクエスト送信
    const response = await fetch('/api/collections', {
      method: 'POST',
      body: JSON.stringify(data),
    });
    const newCollection = await response.json();

    // 成功したら正しいデータで再検証
    mutate();
  } catch (error) {
    // エラー時はロールバック
    mutate();
    throw error;
  }
}
```

**根拠**:
- **SWR**: React Queryより軽量で、Vercelによる公式サポート。Next.jsとの相性が良い
- **BFF API Routes**: トークン管理をサーバー側で行い、クライアント側のセキュリティリスクを軽減
- **楽観的UI更新**: UXを向上させ、レスポンシブな感覚を提供
- **dedupingInterval**: 短時間の重複リクエストを避け、サーバー負荷を軽減

**検討した代替案**:
1. **React Query (TanStack Query)**
   - 却下理由: SWRより重く、Next.jsでの標準的な選択肢ではない
2. **Redux Toolkit + RTK Query**
   - 却下理由: グローバル状態管理が不要。SWRのローカル状態管理で十分
3. **直接バックエンドAPI呼び出し (BFF不使用)**
   - 却下理由: JWT管理をクライアント側で行うセキュリティリスク

## 5. データベース移行戦略

### 決定: Blue-Green移行 + バックフィル移行スクリプト

**選択したアプローチ**:

**ステップ1: スキーマ追加 (後方互換性あり)**
```sql
-- migrations/001_add_collections_schema.sql
-- NULLABLEなcollection_idを追加
ALTER TABLE documents ADD COLUMN collection_id UUID REFERENCES collections(id) ON DELETE RESTRICT;
CREATE INDEX idx_documents_collection_id ON documents(collection_id);

-- collectionsテーブルを作成
CREATE TABLE collections (...);
```

**ステップ2: バックフィル移行スクリプト**
```python
# scripts/migrate_to_collections.py
async def migrate_documents_to_default_collection():
    """既存ドキュメントをデフォルトコレクションに移行"""
    async with db.begin():
        # 各ナレッジベースにデフォルトコレクションを作成
        knowledge_bases = await db.query(KnowledgeBase).all()
        for kb in knowledge_bases:
            default_collection = Collection(
                knowledge_base_id=kb.id,
                name="未分類",
                description="自動作成されたデフォルトコレクション",
                is_default=True
            )
            db.add(default_collection)
            await db.flush()  # IDを取得

            # ドキュメントを移行 (collection_id = NULLのもの)
            await db.execute(
                update(Document)
                .where(Document.knowledge_base_id == kb.id)
                .where(Document.collection_id.is_(None))
                .values(collection_id=default_collection.id)
            )
```

**ステップ3: NOT NULL制約を追加**
```sql
-- migrations/002_make_collection_id_not_null.sql
-- すべてのドキュメントがcollection_idを持つことを確認してから実行
ALTER TABLE documents ALTER COLUMN collection_id SET NOT NULL;
```

**ロールバック戦略**:
```sql
-- rollback/001_rollback_collections.sql
-- ステップ1: NOT NULL制約を削除 (ステップ3のロールバック)
ALTER TABLE documents ALTER COLUMN collection_id DROP NOT NULL;

-- ステップ2: collection_idをNULLに設定 (データ削除警告)
UPDATE documents SET collection_id = NULL;

-- ステップ3: 外部キー制約を削除してからcollection_idカラムを削除
ALTER TABLE documents DROP CONSTRAINT IF EXISTS documents_collection_id_fkey;
ALTER TABLE documents DROP COLUMN collection_id;

-- ステップ4: collectionsテーブルを削除
DROP TABLE IF EXISTS collections CASCADE;
```

**リカバリー手順** (移行失敗時):
1. **移行途中で失敗した場合** (ステップ2中):
   - トランザクションが自動ロールバックされるため、再実行可能
   - エラーログを確認し、問題を修正してから`poetry run python scripts/migrate_to_collections.py`を再実行

2. **データ不整合が発生した場合**:
   ```bash
   # 孤立したcollection_id (存在しないコレクションを参照) を検出
   SELECT d.id, d.collection_id
   FROM documents d
   LEFT JOIN collections c ON d.collection_id = c.id
   WHERE d.collection_id IS NOT NULL AND c.id IS NULL;

   # 検出された場合、デフォルトコレクションに再割り当て
   UPDATE documents d
   SET collection_id = (
     SELECT c.id FROM collections c
     WHERE c.knowledge_base_id = d.knowledge_base_id
     AND c.is_default = TRUE
   )
   WHERE d.collection_id NOT IN (SELECT id FROM collections);
   ```

3. **完全ロールバック** (機能を削除):
   - 上記のrollback SQLを実行
   - アプリケーションコードを以前のバージョンに戻す

**根拠**:
- **Blue-Green移行**: ダウンタイムなし。NULLABLEなカラムを追加し、バックフィル後にNOT NULLに変更
- **バッチ処理**: 大量ドキュメントの場合、バッチサイズを制限してロックを最小化
- **トランザクション**: ナレッジベースごとにトランザクションを分割し、大規模ロックを避ける
- **ロールバック可能**: 移行失敗時にロールバックスクリプトで元に戻せる

**検討した代替案**:
1. **即座にNOT NULL制約を追加**
   - 却下理由: 既存ドキュメントがNULL値を持つため、移行が失敗
2. **アプリケーションレベルでのデフォルト値設定**
   - 却下理由: データベース整合性が保証されない
3. **メンテナンスモード + 一括移行**
   - 却下理由: ダウンタイムが発生し、ユーザー体験が悪化

## 実装の推奨事項

### データベーススキーマ更新 (最優先)

**重要**: PostgreSQLのinit.sqlファイルを更新する必要があります:

**ファイルパス**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-postgres/db/init.sql`

**追加するSQL** (line 280以降、`-- FEATURE-2025-001: ナレッジベースサマリー機能`の後に追加):

```sql
-- ===============================================
-- FEATURE-001: ナレッジベースのコレクション階層構造
-- ===============================================

-- コレクションテーブル
CREATE TABLE IF NOT EXISTS collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    knowledge_base_id UUID NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT CHECK (char_length(description) <= 10000),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_kb_collection_name UNIQUE (knowledge_base_id, name)
);

-- 部分UNIQUE制約 (デフォルトコレクションは1つのみ)
CREATE UNIQUE INDEX IF NOT EXISTS uq_kb_default_collection
    ON collections(knowledge_base_id, is_default)
    WHERE is_default = TRUE;

-- インデックス
CREATE INDEX IF NOT EXISTS idx_collections_kb_id ON collections(knowledge_base_id);
CREATE INDEX IF NOT EXISTS idx_collections_is_default ON collections(knowledge_base_id, is_default);

-- documentsテーブルにcollection_id追加
ALTER TABLE documents ADD COLUMN IF NOT EXISTS collection_id UUID;
ALTER TABLE documents ADD CONSTRAINT IF NOT EXISTS fk_documents_collection
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_documents_collection_id ON documents(collection_id);

-- updated_atトリガー (collectionsテーブル用)
CREATE TRIGGER update_collections_updated_at
    BEFORE UPDATE ON collections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

**適用方法**:
```bash
# PostgreSQLコンテナを再作成
cd ai-micro-postgres
docker compose down
docker compose up -d

# または、既存DBに手動適用
docker exec -i postgres psql -U postgres -d admindb < migration.sql
```

### バックエンド実装順序
1. **init.sql更新**: 上記のSQLをai-micro-postgresのinit.sqlに追加
2. データベース再作成または移行スクリプト適用
3. Collectionモデルとスキーマ作成
4. CollectionServiceにビジネスロジック実装
5. CollectionRouterにエンドポイント実装
6. DocumentServiceにコレクション対応を追加
7. Redisキャッシング統合

### フロントエンド実装順序
1. Collection型定義作成
2. BFF API Routes作成
3. collectionService (SWR統合) 作成
4. コレクション一覧・詳細コンポーネント作成
5. コレクション作成・編集・削除UI作成
6. ドキュメント移動UI作成
7. 削除確認ダイアログ作成

### テスト戦略
1. **単体テスト**: CollectionService、ビジネスロジックの検証
2. **コントラクトテスト**: APIエンドポイントのリクエスト/レスポンススキーマ検証
3. **統合テスト**: データベース操作とトランザクション検証
4. **E2Eテスト**: ユーザーストーリー全体のワークフロー検証

## まとめ

すべての技術的決定が完了し、実装の準備が整いました。次のステップは Phase 1 (設計 & コントラクト) で、具体的なデータモデル、APIコントラクト、テストを生成します。

---
**ステータス**: Phase 0 完了 ✅
