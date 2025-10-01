# データベース間連携 - Cross-Database Relations

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [マイクロサービスとデータベース分離](#マイクロサービスとデータベース分離)
- [論理的な外部キー関係](#論理的な外部キー関係)
- [物理FK制約を設定しない理由](#物理fk制約を設定しない理由)
- [データ整合性の保証方法](#データ整合性の保証方法)
- [JWT トークンによる連携](#jwt-トークンによる連携)
- [運用上の考慮事項](#運用上の考慮事項)
- [トラブルシューティング](#トラブルシューティング)

---

## マイクロサービスとデータベース分離

### Database per Service パターン

本システムは「Database per Service」パターンを採用し、各マイクロサービスが専用のデータベースを持ちます。

```
┌─────────────────────────────────────────────────────────┐
│              Microservices Architecture                 │
└─────────────────────────────────────────────────────────┘

[Auth Service]          [User API]          [Admin API]
     ↓                      ↓                     ↓
┌─────────┐           ┌─────────┐          ┌─────────┐
│ authdb  │           │  apidb  │          │ admindb │
│         │           │         │          │         │
│ users   │           │profiles │          │ logs    │
└─────────┘           └─────────┘          │ kb      │
                                           │ docs    │
                                           └─────────┘
```

### 分離の利点

1. **独立したデプロイ**: 各サービスを個別にデプロイ可能
2. **障害の局所化**: 1つのDBの障害が他に影響しない
3. **スケーリングの柔軟性**: 負荷に応じて個別にスケール
4. **技術選択の自由**: 各サービスで異なるDB技術を選択可能（将来）

---

## 論理的な外部キー関係

### データベース間の関連

現在のシステムでは、以下の論理的な関連が存在します（物理FK制約なし）:

```
authdb.users.id  ←(論理)→  apidb.profiles.user_id
authdb.users.id  ←(論理)→  admindb.login_logs.user_id
authdb.users.id  ←(論理)→  admindb.knowledge_bases.user_id
authdb.users.id  ←(論理)→  admindb.documents.user_id
```

### 関係1: authdb.users ← apidb.profiles

**カーディナリティ**: 1:1

**実装**:
```sql
-- authdb.users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    ...
);

-- apidb.profiles
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL,  -- ← 論理FK、UNIQUE で 1:1 保証
    name TEXT,
    ...
);
```

**データフロー**:
```
1. ユーザー登録（Auth Service）
   └─> authdb.users にレコード作成
       └─> id = '123e4567-...'

2. プロファイル作成（User API）
   └─> JWT から user_id 取得
       └─> apidb.profiles にレコード作成
           └─> user_id = '123e4567-...'
```

### 関係2: authdb.users ← admindb.login_logs

**カーディナリティ**: 1:N

**実装**:
```sql
-- admindb.login_logs
CREATE TABLE login_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,  -- ← 論理FK、UNIQUE制約なし（1:N）
    ip_address VARCHAR,
    success BOOLEAN NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

**データフロー**:
```
ログイン試行（Auth Service）
└─> 認証処理
    └─> admindb.login_logs にログ記録
        └─> user_id = ログイン試行したユーザーのID
```

### 関係3: authdb.users ← admindb.knowledge_bases

**カーディナリティ**: 1:N

**実装**:
```sql
-- admindb.knowledge_bases
CREATE TABLE knowledge_bases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR NOT NULL,
    user_id UUID NOT NULL,  -- ← 論理FK、ナレッジベースの所有者
    ...
);
```

**データフロー**:
```
ナレッジベース作成（Admin API）
└─> JWT から user_id 取得
    └─> admindb.knowledge_bases にレコード作成
        └─> user_id = 現在のユーザーID
```

### 関係4: authdb.users ← admindb.documents

**カーディナリティ**: 1:N

**実装**:
```sql
-- admindb.documents
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    knowledge_base_id UUID,  -- ← knowledge_bases への物理FK
    user_id UUID,            -- ← authdb.users への論理FK（スタンドアロン）
    ...
    CONSTRAINT check_owner CHECK (knowledge_base_id IS NOT NULL OR user_id IS NOT NULL)
);
```

**データフロー**:
```
ドキュメントアップロード（Admin API）
├─> ナレッジベースに紐付け
│   └─> knowledge_base_id = 'kb-uuid'
│
└─> スタンドアロンドキュメント
    └─> user_id = 現在のユーザーID
```

---

## 物理FK制約を設定しない理由

### 1. マイクロサービスの独立性

**問題**: 物理FK制約はデータベース間で設定できない

```sql
-- これはできない（データベースを跨ぐFK）
ALTER TABLE apidb.profiles
  ADD CONSTRAINT fk_profiles_user
  FOREIGN KEY (user_id) REFERENCES authdb.users(id);
-- ERROR: cross-database foreign keys are not supported
```

**解決策**: 論理的な関連のみ維持

### 2. 障害の影響範囲限定

**シナリオ**: authdb が一時的にダウンした場合

**物理FK制約あり**:
```
authdb ダウン
  └─> apidb の profiles テーブルも参照チェックできない
      └─> User API のすべての操作が失敗
```

**物理FK制約なし（現在の実装）**:
```
authdb ダウン
  └─> Auth Service のみ影響
      ├─> 新規ログインは不可
      └─> 既存の JWT トークンは有効
          └─> User API は既存プロファイルにアクセス可能（読み取り）
```

### 3. 将来的な物理分離への対応

**現在**: 1つの PostgreSQL インスタンス内で3つのデータベース

**将来**: 各データベースを別の PostgreSQL インスタンスに分離

```
現在:
┌─────────────────────────────┐
│  PostgreSQL Instance        │
│  ├─ authdb                  │
│  ├─ apidb                   │
│  └─ admindb                 │
└─────────────────────────────┘

将来:
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ PostgreSQL   │  │ PostgreSQL   │  │ PostgreSQL   │
│   Instance   │  │   Instance   │  │   Instance   │
│              │  │              │  │              │
│ authdb       │  │ apidb        │  │ admindb      │
└──────────────┘  └──────────────┘  └──────────────┘
```

**移行時の作業**:
- 物理FK制約なし → 接続文字列の変更のみ
- 物理FK制約あり → FK制約の削除、データ整合性の再設計が必要

### 4. サービス間の疎結合

**設計原則**: 各サービスは独立して動作すべき

**例**: User API のスキーマ変更

```
apidb.profiles テーブルにカラム追加
  └─> User API のみ影響
      └─> Auth Service、Admin API は無影響
```

---

## データ整合性の保証方法

### JWT トークンによる整合性保証

**仕組み**:
1. Auth Service で認証 → JWT トークン発行
2. JWT の `sub` クレームに `authdb.users.id` を含める
3. 他のサービスは JWT を検証 → `sub` から `user_id` 取得
4. 存在しないユーザーは JWT 検証で弾かれる

**JWT トークンの例**:
```json
{
  "sub": "123e4567-e89b-12d3-a456-426614174000",  // authdb.users.id
  "email": "user@example.com",
  "roles": ["user"],
  "iat": 1696000000,
  "exp": 1696001800
}
```

**User API での使用**:
```python
@router.post("/profile")
async def create_profile(
    profile_data: ProfileCreate,
    current_user: dict = Depends(get_current_user),  # JWT検証
    db: Session = Depends(get_db)
):
    # JWT から user_id 取得（authdb で認証済み）
    user_id = current_user["sub"]

    # user_id は必ず存在するユーザー（JWT検証済み）
    profile = Profile(
        user_id=user_id,
        name=profile_data.name,
        ...
    )
    db.add(profile)
    db.commit()

    return profile
```

### アプリケーションレベルでの整合性チェック

**存在確認が必要な場合**:
```python
# Admin API で知識ベース作成時
@router.post("/knowledge-bases")
async def create_knowledge_base(
    kb_data: KnowledgeBaseCreate,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = current_user["sub"]

    # オプション: Auth Service に user_id の存在確認リクエスト
    # （通常は JWT 検証で十分）
    # auth_service.verify_user_exists(user_id)

    kb = KnowledgeBase(
        name=kb_data.name,
        user_id=user_id,
        ...
    )
    db.add(kb)
    db.commit()

    return kb
```

### ユニーク制約による整合性

**apidb.profiles の 1:1 関係保証**:
```sql
-- user_id の UNIQUE制約
CREATE TABLE profiles (
    id UUID PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL,  -- ← 重複不可
    ...
);
```

**動作**:
```python
# 同じユーザーで2回プロファイル作成を試行
profile1 = Profile(user_id="123e4567-...", name="Profile 1")
db.add(profile1)
db.commit()  # OK

profile2 = Profile(user_id="123e4567-...", name="Profile 2")
db.add(profile2)
db.commit()  # ERROR: duplicate key value violates unique constraint
```

---

## JWT トークンによる連携

### JWT フロー

```
┌────────────┐
│   Client   │
└─────┬──────┘
      │ 1. POST /auth/login (email, password)
      ↓
┌────────────────┐
│  Auth Service  │
│   (authdb)     │
└────────┬───────┘
         │ 2. ユーザー認証
         │    SELECT * FROM users WHERE email = ?
         ↓
┌────────────────┐
│    authdb      │
│    users       │
└────────┬───────┘
         │ 3. ユーザー情報取得
         ↓
┌────────────────┐
│  Auth Service  │
│  JWT 生成      │
└────────┬───────┘
         │ 4. JWT トークン返却
         │    {"sub": "user-id", "email": "...", "roles": [...]}
         ↓
┌────────────────┐
│    Client      │
└────────┬───────┘
         │ 5. GET /profile (Authorization: Bearer <JWT>)
         ↓
┌────────────────┐
│  User API      │
│  JWT 検証      │
└────────┬───────┘
         │ 6. JWT から user_id 取得
         │    user_id = jwt_payload["sub"]
         ↓
┌────────────────┐
│    apidb       │
│   profiles     │
└────────┬───────┘
         │ 7. プロファイル取得
         │    SELECT * FROM profiles WHERE user_id = ?
         ↓
┌────────────────┐
│    Client      │
│   (Profile)    │
└────────────────┘
```

### JWT ペイロードの設計

**含めるべき情報**:
```json
{
  "sub": "user-id",         // 必須: ユーザーID（authdb.users.id）
  "email": "user@example.com",  // オプション: 表示用
  "roles": ["user", "admin"],   // 必須: 権限チェック用
  "iat": 1696000000,        // 必須: 発行時刻
  "exp": 1696001800         // 必須: 有効期限
}
```

**含めるべきでない情報**:
- パスワード（絶対に含めない）
- 機密情報（クレジットカード番号等）
- 変更頻度が高い情報（JWT はキャッシュされるため）

---

## 運用上の考慮事項

### 孤児レコードの検出

**問題**: ユーザーが authdb から削除されても、apidb や admindb にデータが残る

**検出クエリ**（管理ツール用）:
```python
# 両方のDBに接続して比較
auth_db = create_engine("postgresql://...authdb")
api_db = create_engine("postgresql://...apidb")

# authdb からすべてのユーザーID取得
with auth_db.connect() as conn:
    result = conn.execute("SELECT id FROM users")
    valid_user_ids = [row[0] for row in result]

# apidb で孤児レコード検出
with api_db.connect() as conn:
    result = conn.execute(
        "SELECT user_id, name FROM profiles WHERE user_id != ALL(%s)",
        (valid_user_ids,)
    )
    orphan_profiles = result.fetchall()

print(f"孤児プロファイル: {len(orphan_profiles)}件")
```

**対策**:
1. 定期的な監視スクリプトの実行
2. ユーザー削除時の明示的なクリーンアップ処理
3. 論理削除の採用（`is_active = false` で無効化）

### ユーザー削除のベストプラクティス

**推奨**: 論理削除（物理削除しない）

```sql
-- authdb.users
UPDATE users SET is_active = false WHERE id = 'user-id';

-- apidb.profiles は残す（監査証跡）
-- admindb.knowledge_bases も残す（所有者情報として）
```

**物理削除が必要な場合**（GDPR等）:
```python
# 1. authdb でユーザー削除
auth_db.execute("DELETE FROM users WHERE id = ?", user_id)

# 2. apidb でプロファイル削除
api_db.execute("DELETE FROM profiles WHERE user_id = ?", user_id)

# 3. admindb でデータ削除
admin_db.execute("DELETE FROM login_logs WHERE user_id = ?", user_id)
admin_db.execute("DELETE FROM knowledge_bases WHERE user_id = ?", user_id)
# knowledge_bases 削除で documents も CASCADE 削除される
```

### データ移行時の注意点

**シナリオ**: authdb のユーザーIDを変更

**問題**: apidb、admindb の user_id も更新が必要

**手順**:
```sql
-- 1. authdb で新しいIDを生成
UPDATE users SET id = uuid_generate_v4() WHERE id = 'old-user-id';
-- => new_id = '789abcde-...'

-- 2. apidb で user_id 更新
UPDATE profiles SET user_id = 'new-user-id' WHERE user_id = 'old-user-id';

-- 3. admindb で user_id 更新
UPDATE login_logs SET user_id = 'new-user-id' WHERE user_id = 'old-user-id';
UPDATE knowledge_bases SET user_id = 'new-user-id' WHERE user_id = 'old-user-id';
```

**推奨**: UUIDは変更しない（初期生成後は固定）

---

## トラブルシューティング

### 問題1: プロファイルが見つからない

**症状**:
```python
profile = db.query(Profile).filter(Profile.user_id == user_id).first()
# => None
```

**原因調査**:
```sql
-- 1. JWT の user_id が正しいか確認
-- JWT ペイロード: {"sub": "123e4567-..."}

-- 2. authdb にユーザーが存在するか確認
SELECT * FROM authdb.users WHERE id = '123e4567-...';

-- 3. apidb にプロファイルが作成されているか確認
SELECT * FROM apidb.profiles WHERE user_id = '123e4567-...';
```

**対策**:
- プロファイル未作成 → 初回作成エンドポイントを呼び出す
- user_id の不一致 → JWT トークンの再発行

### 問題2: 孤児レコードの増加

**症状**: apidb に存在するが authdb に存在しない user_id

**検出**:
```python
# 管理スクリプトで定期的に実行
orphan_count = check_orphan_records()
if orphan_count > threshold:
    alert_admin(f"孤児レコード: {orphan_count}件")
```

**対策**:
1. 論理削除の徹底（物理削除しない）
2. ユーザー削除時のクリーンアップ処理
3. 孤児レコードの定期的なアーカイブ

### 問題3: データ不整合

**症状**: authdb のユーザー数と apidb のプロファイル数が大きく乖離

**確認**:
```sql
-- authdb のアクティブユーザー数
SELECT count(*) FROM authdb.users WHERE is_active = true;
-- => 1000

-- apidb のプロファイル数
SELECT count(*) FROM apidb.profiles;
-- => 800  ← 200件の差異
```

**原因**:
- プロファイル未作成ユーザー（正常）
- システムエラーによるプロファイル作成失敗

**対策**:
- プロファイル作成の自動化（初回ログイン時）
- エラーハンドリングの改善

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [authdb スキーマ](./04-authdb-schema.md)
- [apidb スキーマ](./05-apidb-schema.md)
- [admindb スキーマ](./06-admindb-schema.md)
- [ER図](./07-er-diagram.md)
- [Auth Service 認証フロー](/01-auth-service/02-api-specification.md)
- [User API データ連携](/02-user-api/04-data-consistency.md)

---

**次のステップ**: [マイグレーション管理](./09-migration-management.md) を参照して、スキーマ変更の手順を確認してください。