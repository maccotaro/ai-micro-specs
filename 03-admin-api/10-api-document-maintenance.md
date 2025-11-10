# ドキュメントメンテナンス・移動API

**最終更新**: 2025-11-08

## 概要

ドキュメントのメンテナンス操作（孤立ドキュメント管理、処理状態リセット）とCollection間移動機能を提供するAPIです。管理者向けのトラブルシューティングとデータ整合性維持を目的としています。

## エンドポイント一覧

| メソッド | エンドポイント | 説明 |
|---------|---------------|------|
| GET | `/admin/documents/maintenance/cleanup/orphaned` | 孤立ドキュメント検索 |
| POST | `/admin/documents/maintenance/cleanup/reset-processing` | 処理中状態リセット |
| DELETE | `/admin/documents/maintenance/cleanup/orphaned/{document_id}` | 孤立ドキュメント削除 |
| PUT | `/admin/documents/{document_id}/move` | ドキュメント移動（Collection間） |

**認証**: 全エンドポイントでJWT（admin_access_token）必須

**権限**: admin権限が必要

---

## メンテナンスAPI

### 1. 孤立ドキュメント検索

```
GET /admin/documents/maintenance/cleanup/orphaned
```

**認証**: JWT + Admin権限

**用途**: DBレコードは存在するが物理ファイルが欠損しているドキュメントを検出

#### レスポンス

```json
{
  "orphaned_documents": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "filename": "report.pdf",
      "reason": "File not found: /data/uploads/report.pdf",
      "status": "processed"
    },
    {
      "id": "987fbc97-4bed-5078-9f07-9141ba07c9f3",
      "filename": "document.docx",
      "reason": "No file path configured",
      "status": "uploaded"
    }
  ],
  "total_found": 2
}
```

**孤立判定条件**:
1. `file_path`カラムがNULL
2. `file_path`が設定されているが、物理ファイルが存在しない

**使用例**:
```typescript
const orphaned = await fetch('/api/admin/documents/maintenance/cleanup/orphaned', {
  headers: { 'Authorization': `Bearer ${adminToken}` }
}).then(r => r.json());

console.log(`Found ${orphaned.total_found} orphaned documents`);
orphaned.orphaned_documents.forEach(doc => {
  console.log(`${doc.filename}: ${doc.reason}`);
});
```

**ユースケース**:
- ストレージクリーンアップ後のDB整合性確認
- 手動ファイル削除後のDB同期確認
- ディスク障害後のデータ検証

---

### 2. 処理中状態リセット

```
POST /admin/documents/maintenance/cleanup/reset-processing
```

**認証**: JWT + Admin権限

**用途**: 処理がハングしたドキュメント（status="processing"）を初期状態（"uploaded"）にリセット

#### レスポンス

```json
{
  "message": "Reset 5 documents from processing to uploaded state",
  "reset_count": 5
}
```

**処理内容**:
1. `status = "processing"`のドキュメントを全て検索
2. ステータスを`"uploaded"`に更新
3. 更新件数を返却

**使用例**:
```typescript
const result = await fetch('/api/admin/documents/maintenance/cleanup/reset-processing', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${adminToken}` }
}).then(r => r.json());

console.log(result.message);
// Output: "Reset 5 documents from processing to uploaded state"
```

**ユースケース**:
- Docling処理プロセスのクラッシュ後の復旧
- タイムアウトしたジョブの再試行準備
- システム再起動後の状態正規化

**注意事項**:
- リセット後、再度ベクトル化ジョブを実行する必要があります
- 処理途中のデータ（`processing_path`配下）は手動で削除推奨

---

### 3. 孤立ドキュメント削除

```
DELETE /admin/documents/maintenance/cleanup/orphaned/{document_id}
```

**認証**: JWT + Admin権限

**パスパラメータ**:
- `document_id`: UUID

#### レスポンス

```json
{
  "message": "Deleted orphaned document: report.pdf",
  "document_id": "123e4567-e89b-12d3-a456-426614174000"
}
```

**安全性チェック**:
1. `file_path`が存在し、かつ物理ファイルが存在する場合 → **400 Bad Request**
2. 孤立状態のドキュメントのみ削除可能

**エラーレスポンス**:
```json
{
  "detail": "Document is not orphaned. File exists at: /data/uploads/report.pdf"
}
```

**使用例**:
```typescript
try {
  const result = await fetch(
    `/api/admin/documents/maintenance/cleanup/orphaned/${documentId}`,
    {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${adminToken}` }
    }
  ).then(r => r.json());

  console.log(result.message);
} catch (error) {
  console.error('Cannot delete: File still exists');
}
```

**処理フロー**:
```
1. ドキュメント存在確認 (404エラー)
2. 孤立状態検証 (file_pathとファイル存在チェック)
3. 安全性確認 (ファイル存在時は削除拒否)
4. DBレコード削除
5. 成功レスポンス返却
```

**ユースケース**:
- 孤立ドキュメント検索後のクリーンアップ
- DB容量削減
- データ整合性の維持

---

## ドキュメント移動API

### 4. ドキュメント移動（Collection間）

```
PUT /admin/documents/{document_id}/move
```

**認証**: JWT + Admin権限

**パスパラメータ**:
- `document_id`: UUID

#### リクエストボディ

```json
{
  "collection_id": "cf23c222-b024-4533-81aa-52e4f673281e"
}
```

**パラメータ**:
- `collection_id`: 移動先コレクションのUUID

#### レスポンス

`DocumentResponse`オブジェクト（更新後のドキュメント情報）

```json
{
  "id": "doc-uuid",
  "filename": "report.pdf",
  "knowledge_base_id": "kb-uuid",
  "collection_id": "cf23c222-b024-4533-81aa-52e4f673281e",
  "status": "processed",
  "created_at": "2025-11-08T10:00:00Z",
  "updated_at": "2025-11-08T11:30:00Z"
}
```

**整合性チェック**:
1. ドキュメントと移動先コレクションが同一ナレッジベース内にあることを検証
2. 異なるナレッジベース間の移動は **400 Bad Request**

**エラーレスポンス**:
```json
{
  "detail": "Cannot move document to a collection in a different knowledge base"
}
```

**ベクトルストア同期**:
- `langchain_pg_embedding.cmetadata`のJSONBフィールドを自動更新
- PostgreSQLトリガーでFKカラム`collection_id`も自動同期
- ベクトルデータの整合性維持

**使用例**:
```typescript
const updatedDoc = await fetch(
  `/api/admin/documents/${documentId}/move`,
  {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${adminToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      collection_id: targetCollectionId
    })
  }
).then(r => r.json());

console.log(`Moved to collection: ${updatedDoc.collection_id}`);
```

**権限要件**:
- ナレッジベースドキュメント: ナレッジベース所有者または管理者
- 移動元ドキュメントへの書き込み権限が必要

**処理フロー**:
```
1. ドキュメント取得 (404エラー)
2. 移動先コレクション取得 (404エラー)
3. 同一KB検証 (400エラー)
4. アクセス権限チェック (403エラー)
5. document.collection_id 更新
6. DBコミット
7. ベクトルストア自動同期（トリガー）
8. 更新後ドキュメント返却
```

**ユースケース**:
- ドキュメント分類の変更
- コレクション再編成
- データ整理・リファクタリング

---

## アクセス制御

### check_document_access() 関数

ドキュメント操作の権限チェックを統一的に実施します。

**操作タイプ**:
- `"read"`: 読み取り
- `"write"`: 更新
- `"delete"`: 削除

**権限ルール**:

#### 管理者（Admin）
- 全操作可能（read/write/delete）
- 所有者に関係なく全ドキュメントへアクセス可

#### ナレッジベースドキュメント
- **Read**: 所有者 OR 公開ナレッジベース
- **Write/Delete**: 所有者のみ
- ナレッジベース所有者: `knowledge_base.user_id == current_user.id`

#### スタンドアロンドキュメント
- **Read**: 所有者 OR 公開ドキュメント（`is_public=true`）
- **Write/Delete**: 所有者のみ
- ドキュメント所有者: `document.user_id == current_user.id`

**アクセス拒否時**: `403 Forbidden`

```json
{
  "detail": "You don't have permission to access this document"
}
```

---

## カスケード削除フロー

### ドキュメント削除（DELETE /documents/{document_id}）

**削除順序**:
```
1. 物理ファイル削除
   - file_path のファイル削除
   - エラー時: 警告ログ出力（処理続行）

2. 処理ディレクトリ削除
   - processing_path のディレクトリ削除（再帰）
   - エラー時: 警告ログ出力（処理続行）

3. ベクトルデータ削除
   - langchain_pg_embedding テーブルから削除
   - vector_manager.delete_document_vectors(document_id)
   - エラー時: 警告ログ出力（処理続行）

4. ナレッジベースカウンター更新
   - knowledge_base.document_count -= 1
   - knowledge_base.storage_size -= document.file_size

5. DBレコード削除
   - documents テーブルから削除
```

**エラーハンドリング**:
- ファイル削除失敗: 警告ログ + 処理続行
- ベクトル削除失敗: 警告ログ + 処理続行
- DBレコード削除は必ず実行（整合性維持）

**DB制約によるカスケード**:
```sql
-- chat_messages (セッション削除時)
ON DELETE CASCADE

-- langchain_pg_embedding (ドキュメント削除時)
ON DELETE CASCADE

-- rag_audit_logs (ナレッジベース削除時)
ON DELETE CASCADE
```

---

## ベクトルストア同期

### delete_document_vectors()

**用途**: 個別ドキュメント削除時のベクトルデータ削除

```python
# app/services/vector_manager.py
async def delete_document_vectors(self, document_id: UUID):
    """
    指定ドキュメントのベクトルデータを削除

    Args:
        document_id: ドキュメントUUID
    """
    # langchain_pg_embeddingテーブルから削除
    await self.db.execute(
        delete(LangchainPGEmbedding).where(
            LangchainPGEmbedding.document_id == document_id
        )
    )
    await self.db.commit()
```

### delete_knowledge_base_vectors()

**用途**: ナレッジベース削除時のベクトルデータ一括削除（最適化済み）

```python
async def delete_knowledge_base_vectors(self, kb_id: UUID):
    """
    指定ナレッジベースの全ベクトルデータを削除

    最適化:
    - JOINクエリで一括削除（N+1問題回避）
    - インデックス活用で高速化
    """
    await self.db.execute(
        delete(LangchainPGEmbedding).where(
            LangchainPGEmbedding.document_id.in_(
                select(Document.id).where(
                    Document.knowledge_base_id == kb_id
                )
            )
        )
    )
    await self.db.commit()
```

### Collection変更時の自動同期

**トリガー**: `sync_embedding_collection_id()`

```sql
CREATE OR REPLACE FUNCTION sync_embedding_collection_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.cmetadata ? 'collection_id' THEN
        NEW.collection_id := (NEW.cmetadata->>'collection_id')::uuid;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_embedding_collection_id
    BEFORE INSERT OR UPDATE ON langchain_pg_embedding
    FOR EACH ROW
    EXECUTE FUNCTION sync_embedding_collection_id();
```

**動作**:
1. `document.collection_id`を更新
2. アプリケーション側で`langchain_pg_embedding.cmetadata`を更新
3. トリガーが`cmetadata->>'collection_id'`を読み取り、FKカラム`collection_id`に同期

---

## 運用ガイド

### 孤立ドキュメントクリーンアップ手順

```bash
# 1. 孤立ドキュメント検索
curl -X GET "http://localhost:8003/admin/documents/maintenance/cleanup/orphaned" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"

# 2. 各ドキュメントの孤立状態を確認

# 3. 孤立ドキュメント削除（1件ずつ）
curl -X DELETE "http://localhost:8003/admin/documents/maintenance/cleanup/orphaned/${DOC_ID}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"
```

### 処理ハング復旧手順

```bash
# 1. 処理中ドキュメント確認
curl -X GET "http://localhost:8003/admin/documents?status=processing" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"

# 2. 処理状態リセット
curl -X POST "http://localhost:8003/admin/documents/maintenance/cleanup/reset-processing" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"

# 3. 処理ディレクトリクリーンアップ（任意）
# 手動で /data/processing/ 配下の未完了ディレクトリを削除

# 4. ベクトル化ジョブ再実行
curl -X POST "http://localhost:8003/admin/documents/${DOC_ID}/vectorize" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"
```

### Collection再編成手順

```typescript
// 1. ドキュメント一覧取得
const docs = await fetch(`/api/admin/knowledge-bases/${kbId}/documents`)
  .then(r => r.json());

// 2. フィルタリング（例: PDFのみ）
const pdfs = docs.documents.filter(d => d.mime_type === 'application/pdf');

// 3. 移動先コレクション作成
const newCollection = await fetch(`/api/admin/collections`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    knowledge_base_id: kbId,
    name: 'PDF Documents',
    description: 'All PDF files'
  })
}).then(r => r.json());

// 4. ドキュメント一括移動
for (const doc of pdfs) {
  await fetch(`/api/admin/documents/${doc.id}/move`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      collection_id: newCollection.id
    })
  });
}
```

---

## トラブルシューティング

### Q1: 孤立ドキュメント削除が失敗する

**症状**: `DELETE /orphaned/{id}` が400エラー

**原因**: ファイルがまだ存在している

**対処**:
1. ファイルパスを確認: `GET /documents/{id}`
2. 物理ファイルを手動削除
3. 再度削除API実行

### Q2: ドキュメント移動が400エラー

**症状**: `PUT /documents/{id}/move` が400エラー

**原因**: 異なるナレッジベース間の移動を試行

**対処**:
1. 移動元ドキュメントの`knowledge_base_id`を確認
2. 移動先コレクションの`knowledge_base_id`を確認
3. 同一KB内のコレクションを指定

### Q3: ベクトルデータが同期されない

**症状**: Collection変更後もベクトル検索で古いコレクションIDが表示

**原因**: トリガー未実行またはcmetadata更新失敗

**対処**:
```sql
-- 手動同期
UPDATE langchain_pg_embedding
SET collection_id = (cmetadata->>'collection_id')::uuid
WHERE cmetadata ? 'collection_id' AND collection_id IS NULL;
```

---

## 関連ドキュメント

- [ドキュメント処理API](./02-api-documents.md) - ドキュメントCRUD、ベクトル化
- [ナレッジベースAPI](./02-api-knowledge-bases.md) - KB管理、チャット機能
- [コレクション管理](./03-api-collections.md) - コレクションCRUD
- [データベース設計](./06-database-design.md) - カスケード削除制約、トリガー
- [ジョブ管理API](./02-api-jobs.md) - ベクトル化ジョブ監視

---

## セキュリティ考慮事項

### 権限制御
- 全エンドポイントでadmin権限必須
- ドキュメント移動は所有者または管理者のみ
- 孤立ドキュメント削除は慎重に実施（復元不可）

### 監査ログ
- ドキュメント削除操作を`rag_audit_logs`に記録
- 孤立ドキュメント削除も監査対象
- Collection変更履歴も記録推奨

### データ整合性
- カスケード削除でベクトルデータも自動削除
- ナレッジベースカウンター自動更新
- トリガーによるベクトルストア同期

### エラーハンドリング
- ファイル削除失敗時もDBレコードは削除（整合性優先）
- 警告ログで削除失敗を記録
- 孤立ドキュメント削除は安全性チェック実施
