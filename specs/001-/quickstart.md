# クイックスタート: ナレッジベースのコレクション階層構造

**目的**: この機能の動作を検証するための手動テストシナリオ

**注意**: 以下のシナリオはPlaywright E2Eテストで自動化されています:
- シナリオ1: タスクT020c (collection-create.spec.ts)
- シナリオ2: タスクT020d (document-move.spec.ts)
- シナリオ3: タスクT020e (collection-delete.spec.ts)

自動テスト実行方法: `docker exec ai-micro-front-admin npx playwright test`

## 前提条件

### 環境セットアップ

1. **インフラストラクチャ起動**:
   ```bash
   cd ai-micro-postgres && docker compose up -d
   cd ../ai-micro-redis && docker compose up -d
   ```

2. **バックエンドサービス起動**:
   ```bash
   cd ai-micro-api-auth && docker compose up -d
   cd ../ai-micro-api-admin && docker compose up -d
   ```

3. **フロントエンド起動**:
   ```bash
   cd ai-micro-front-admin && docker compose up -d
   ```

4. **データベース移行適用**:
   ```bash
   cd ai-micro-api-admin
   poetry run alembic upgrade head
   ```

### テストユーザー (既存管理者を使用)

**注意**: データベースに既に存在している管理ユーザーを使用します。

```bash
# 既存の管理者でログイン
# (メールアドレスとパスワードは環境に合わせて変更してください)
curl -X POST http://localhost:8002/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "your_existing_password"
  }'

# レスポンスからaccess_tokenを保存
export ACCESS_TOKEN="<your_access_token>"
```

**ユーザーが存在しない場合**:
```bash
# 新規管理者ユーザーを作成
curl -X POST http://localhost:8002/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "SecurePassword123!",
    "roles": ["admin"]
  }'
```

## シナリオ1: コレクション作成とドキュメント追加

### 目的
受け入れシナリオ1-2の検証: ユーザーがコレクションを作成し、ドキュメントを追加できる

### ステップ

1. **ナレッジベースを作成**:
   ```bash
   # ナレッジベースを作成してUUIDを抽出 (jqが必要)
   RESPONSE=$(curl -s -X POST http://localhost:8003/api/knowledgebase \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "製品ドキュメント",
       "description": "製品に関するドキュメント"
     }')

   # レスポンスからknowledge_base_idを抽出して環境変数に保存
   export KB_ID=$(echo $RESPONSE | jq -r '.id')
   echo "Knowledge Base ID: $KB_ID"

   # jqがインストールされていない場合:
   # macOS: brew install jq
   # Ubuntu: sudo apt-get install jq
   ```

2. **デフォルトコレクションが自動作成されていることを確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/collections?knowledge_base_id=$KB_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: is_default=true のコレクションが1つ存在
   ```

3. **新しいコレクション「技術仕様書」を作成**:
   ```bash
   # コレクションを作成してUUIDを抽出
   COLLECTION_RESPONSE=$(curl -s -X POST http://localhost:8003/api/collections \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "knowledge_base_id": "'"$KB_ID"'",
       "name": "技術仕様書",
       "description": "製品の技術仕様に関するドキュメント"
     }')

   # レスポンスからcollection_idを抽出して環境変数に保存
   export COLLECTION_ID=$(echo $COLLECTION_RESPONSE | jq -r '.id')
   echo "Collection ID: $COLLECTION_ID"
   ```

4. **コレクション一覧を取得して確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/collections?knowledge_base_id=$KB_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 2つのコレクション (デフォルト + 技術仕様書)
   ```

5. **ドキュメントをアップロード**:
   ```bash
   curl -X POST http://localhost:8003/api/documents/upload \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -F "file=@sample.pdf" \
     -F "knowledge_base_id=$KB_ID" \
     -F "collection_id=$COLLECTION_ID"

   # レスポンスからdocument_idを保存
   export DOC_ID="<ドキュメントID>"
   ```

6. **コレクション詳細でドキュメントが表示されることを確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/collections/$COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: documentsフィールドにアップロードしたドキュメントが含まれる
   # document_count が 1 になっている
   ```

### 期待結果

- ✅ コレクションが正常に作成される
- ✅ ドキュメントがコレクションに追加される
- ✅ コレクション詳細にドキュメントが表示される
- ✅ ドキュメント数が正確にカウントされる

## シナリオ2: ドキュメント移動

### 目的
受け入れシナリオ3の検証: ユーザーがドキュメントをコレクション間で移動できる

### ステップ

1. **新しいコレクション「アーカイブ」を作成**:
   ```bash
   curl -X POST http://localhost:8003/api/collections \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "knowledge_base_id": "'"$KB_ID"'",
       "name": "アーカイブ",
       "description": "古いドキュメント"
     }'

   export ARCHIVE_COLLECTION_ID="<アーカイブコレクションID>"
   ```

2. **ドキュメントをアーカイブに移動**:
   ```bash
   curl -X PUT "http://localhost:8003/api/documents/$DOC_ID/move" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "collection_id": "'"$ARCHIVE_COLLECTION_ID"'"
     }'
   ```

3. **元のコレクションからドキュメントが消えたことを確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/collections/$COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: documents配列が空、document_count が 0
   ```

4. **アーカイブコレクションにドキュメントが表示されることを確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/collections/$ARCHIVE_COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: documentsフィールドに移動したドキュメントが含まれる
   # document_count が 1
   ```

### 期待結果

- ✅ ドキュメントが元のコレクションから削除される
- ✅ ドキュメントが新しいコレクションに追加される
- ✅ 両コレクションのドキュメント数が正確に更新される

## シナリオ3: コレクション削除の確認ダイアログ

### 目的
受け入れシナリオ6の検証: コレクション削除時にユーザーが選択できる

### ステップ (オプション1: ドキュメントも削除)

1. **テスト用コレクションとドキュメントを作成**:
   ```bash
   # コレクション作成
   curl -X POST http://localhost:8003/api/collections \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "knowledge_base_id": "'"$KB_ID"'",
       "name": "一時フォルダ",
       "description": "削除予定"
     }'

   export TEMP_COLLECTION_ID="<一時コレクションID>"

   # ドキュメントをアップロード
   curl -X POST http://localhost:8003/api/documents/upload \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -F "file=@test.pdf" \
     -F "knowledge_base_id=$KB_ID" \
     -F "collection_id=$TEMP_COLLECTION_ID"
   ```

2. **コレクションを削除 (ドキュメントも削除)**:
   ```bash
   curl -X DELETE "http://localhost:8003/api/collections/$TEMP_COLLECTION_ID?action=delete" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 204 No Content
   ```

3. **ドキュメントも削除されたことを確認**:
   ```bash
   curl -X GET "http://localhost:8003/api/documents/$DOC_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 404 Not Found
   ```

### ステップ (オプション2: デフォルトコレクションに移動)

1. **別のテスト用コレクションとドキュメントを作成**:
   ```bash
   # (上記と同じ手順でコレクションとドキュメントを作成)
   export TEMP_COLLECTION_ID_2="<一時コレクションID2>"
   export DOC_ID_2="<ドキュメントID2>"
   ```

2. **コレクションを削除 (デフォルトに移動)**:
   ```bash
   curl -X DELETE "http://localhost:8003/api/collections/$TEMP_COLLECTION_ID_2?action=move_to_default" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 204 No Content
   ```

3. **ドキュメントがデフォルトコレクションに移動したことを確認**:
   ```bash
   # デフォルトコレクションIDを取得
   export DEFAULT_COLLECTION_ID=$(curl -s -X GET "http://localhost:8003/api/collections?knowledge_base_id=$KB_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.collections[] | select(.is_default==true) | .id')

   curl -X GET "http://localhost:8003/api/collections/$DEFAULT_COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: documentsフィールドに移動したドキュメントが含まれる
   ```

### 期待結果

- ✅ action=delete でドキュメントも削除される
- ✅ action=move_to_default でドキュメントがデフォルトコレクションに移動
- ✅ actionパラメータがない場合は422エラー

## シナリオ4: 全体検索とコレクション絞り込み検索

### 目的
受け入れシナリオ7-8の検証: ナレッジベース全体検索とコレクション絞り込み検索

### ステップ

1. **複数のコレクションにドキュメントを追加**:
   ```bash
   # (シナリオ1-2で既に追加済み)
   ```

2. **ナレッジベース全体を検索**:
   ```bash
   curl -X GET "http://localhost:8003/api/search?q=仕様&knowledge_base_id=$KB_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: すべてのコレクションからマッチするドキュメントが表示される
   ```

3. **特定のコレクションを絞り込んで検索**:
   ```bash
   curl -X GET "http://localhost:8003/api/search?q=仕様&knowledge_base_id=$KB_ID&collection_id=$COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 指定したコレクション内のみからマッチするドキュメントが表示される
   ```

### 期待結果

- ✅ collection_idなしで全体検索が動作
- ✅ collection_idありで絞り込み検索が動作
- ✅ 検索結果にcollection_nameが含まれる

## シナリオ5: デフォルトコレクションの保護

### 目的
デフォルトコレクションは削除・名前変更できないことを確認

### ステップ

1. **デフォルトコレクションIDを取得**:
   ```bash
   export DEFAULT_COLLECTION_ID=$(curl -s -X GET "http://localhost:8003/api/collections?knowledge_base_id=$KB_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.collections[] | select(.is_default==true) | .id')
   ```

2. **デフォルトコレクションの削除を試行**:
   ```bash
   curl -X DELETE "http://localhost:8003/api/collections/$DEFAULT_COLLECTION_ID?action=delete" \
     -H "Authorization: Bearer $ACCESS_TOKEN"

   # 期待結果: 422 Validation Error "Cannot delete default collection"
   ```

3. **デフォルトコレクションの名前変更を試行**:
   ```bash
   curl -X PUT "http://localhost:8003/api/collections/$DEFAULT_COLLECTION_ID" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "新しい名前"
     }'

   # 期待結果: 422 Validation Error "Cannot rename default collection"
   ```

### 期待結果

- ✅ デフォルトコレクションの削除が拒否される
- ✅ デフォルトコレクションの名前変更が拒否される

## フロントエンドでの検証

### ブラウザアクセス

1. **Admin Frontendにアクセス**:
   ```
   http://localhost:3003
   ```

2. **ログイン**:
   - Email: admin@example.com
   - Password: SecurePassword123!

3. **ナレッジベース詳細ページに移動**:
   - 作成したナレッジベース「製品ドキュメント」をクリック

4. **コレクション管理タブに移動**:
   - 「コレクション」タブをクリック

5. **UIでの検証項目**:
   - ✅ コレクション一覧が表示される
   - ✅ 各コレクションにドキュメント数が表示される
   - ✅ 「新しいコレクション」ボタンでモーダルが開く
   - ✅ コレクション作成フォームが動作する
   - ✅ デフォルトコレクションには削除・名前変更ボタンがない
   - ✅ コレクション削除時に確認ダイアログが表示される
   - ✅ ダイアログで「ドキュメントも削除」「デフォルトに移動」を選択できる
   - ✅ ドキュメントをドラッグ&ドロップで別のコレクションに移動できる

## クリーンアップ

```bash
# ナレッジベースを削除 (カスケード削除でコレクションとドキュメントも削除)
curl -X DELETE "http://localhost:8003/api/knowledgebase/$KB_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# サービス停止
cd ai-micro-front-admin && docker compose down
cd ../ai-micro-api-admin && docker compose down
cd ../ai-micro-api-auth && docker compose down
cd ../ai-micro-redis && docker compose down
cd ../ai-micro-postgres && docker compose down
```

---
**ステータス**: クイックスタート完了 ✅
