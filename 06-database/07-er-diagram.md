# PostgreSQL データベース - ER図（Entity-Relationship Diagram）

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [全体アーキテクチャ](#全体アーキテクチャ)
- [authdb ER図](#authdb-er図)
- [apidb ER図](#apidb-er図)
- [admindb ER図](#admindb-er図)
- [データベース間の論理関係](#データベース間の論理関係)
- [外部キー制約の詳細](#外部キー制約の詳細)
- [カーディナリティ](#カーディナリティ)

---

## 全体アーキテクチャ

### 3データベース構成

```
┌─────────────────────────────────────────────────────────────────────┐
│  PostgreSQL Instance (ai-micro-postgres)                            │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│  │    authdb        │  │     apidb        │  │    admindb       │ │
│  │                  │  │                  │  │                  │ │
│  │  ┌────────────┐  │  │  ┌────────────┐ │  │  ┌────────────┐ │ │
│  │  │   users    │──┼──┼─→│  profiles  │ │  │  │system_logs │ │ │
│  │  └────────────┘  │  │  └────────────┘ │  │  └────────────┘ │ │
│  │        │         │  │                  │  │  ┌────────────┐ │ │
│  │        │         │  │                  │  │  │login_logs  │←┼─┤
│  │        │         │  │                  │  │  └────────────┘ │ │
│  │        │         │  │                  │  │  ┌────────────┐ │ │
│  │        │         │  │                  │  │  │system_     │ │ │
│  │        │         │  │                  │  │  │  settings  │ │ │
│  │        │         │  │                  │  │  └────────────┘ │ │
│  │        │         │  │                  │  │  ┌────────────┐ │ │
│  │        └─────────┼──┼──────────────────┼──┼─→│knowledge_  │ │ │
│  │                  │  │                  │  │  │  bases     │ │ │
│  │                  │  │                  │  │  └─────┬──────┘ │ │
│  │                  │  │                  │  │        │ FK     │ │
│  │                  │  │                  │  │        ↓        │ │
│  │                  │  │                  │  │  ┌────────────┐ │ │
│  │                  │  │                  │  │  │documents   │ │ │
│  │                  │  │                  │  │  └─────┬──────┘ │ │
│  │                  │  │                  │  │        │ FK     │ │
│  │                  │  │                  │  │        ↓        │ │
│  │                  │  │                  │  │  ┌────────────┐ │ │
│  │                  │  │                  │  │  │langchain_  │ │ │
│  │                  │  │                  │  │  │pg_embedding│ │ │
│  │                  │  │                  │  │  └────────────┘ │ │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘

凡例:
  ─→  論理的な関係（物理FK制約なし）
  ↓   物理的な外部キー制約
```

---

## authdb ER図

### テーブル: users

```
┌─────────────────────────────────────────────────────────┐
│                        users                            │
├─────────────────────────────────────────────────────────┤
│ PK  id                    UUID                          │
│ U   email                 TEXT                          │
│     password_hash         TEXT                          │
│     roles                 TEXT[]                        │
│     created_at            TIMESTAMP                     │
│     updated_at            TIMESTAMP                     │
│     is_active             BOOLEAN                       │
│     login_attempts        INTEGER                       │
│     last_login_at         TIMESTAMP                     │
│     locked_until          TIMESTAMP                     │
└─────────────────────────────────────────────────────────┘
         │
         │ 論理FK（物理制約なし）
         │
         ├──────────────────→ apidb.profiles.user_id
         │
         ├──────────────────→ admindb.login_logs.user_id
         │
         └──────────────────→ admindb.knowledge_bases.user_id

凡例:
  PK  = Primary Key
  U   = Unique
  FK  = Foreign Key
```

### インデックス

```sql
-- 主キー（自動）
users_pkey ON users(id)

-- 明示的インデックス
idx_users_email ON users(email)
```

---

## apidb ER図

### テーブル: profiles

```
┌─────────────────────────────────────────────────────────┐
│                      profiles                           │
├─────────────────────────────────────────────────────────┤
│ PK  id                    UUID                          │
│ U   user_id               UUID  ←─────────┐            │
│     name                  TEXT            │            │
│     first_name            TEXT            │ 論理FK     │
│     last_name             TEXT            │ (物理制約  │
│     address               TEXT            │  なし)     │
│     phone                 TEXT            │            │
│     created_at            TIMESTAMP       │            │
│     updated_at            TIMESTAMP       │            │
└─────────────────────────────────────────────────────────┘
                                            │
                                            │
                             authdb.users.id

凡例:
  ←─────  論理的な関連（データベースを跨ぐ）
```

### インデックス

```sql
-- 主キー（自動）
profiles_pkey ON profiles(id)

-- ユニーク制約（自動インデックス）
profiles_user_id_key ON profiles(user_id)

-- 明示的インデックス
idx_profiles_user_id ON profiles(user_id)
```

---

## admindb ER図

### テーブル関係図

```
authdb.users.id
      │
      │ 論理FK
      ↓
┌────────────────────┐
│   login_logs       │
│                    │
│ PK  id             │
│     user_id  ──────┼───→ (論理FK)
│     ip_address     │
│     success        │
│     created_at     │
└────────────────────┘


authdb.users.id
      │
      │ 論理FK
      ↓
┌────────────────────────────────────────────────────────┐
│              knowledge_bases                           │
│                                                         │
│ PK  id                                                 │
│     name                                               │
│     description                                        │
│     user_id  ──────────────────→ (論理FK)              │
│     status                                             │
│     is_public                                          │
│     document_count                                     │
│     storage_size                                       │
│     ... (その他のカラム)                                │
└─────────────┬──────────────────────────────────────────┘
              │
              │ 物理FK (ON DELETE CASCADE)
              ↓
┌────────────────────────────────────────────────────────┐
│                    documents                           │
│                                                         │
│ PK  id                                                 │
│ FK  knowledge_base_id  ───→ knowledge_bases.id        │
│     filename                                           │
│     original_filename                                  │
│     file_path                                          │
│     status                                             │
│     original_metadata      JSONB                       │
│     edited_metadata        JSONB                       │
│     editing_status                                     │
│     ... (その他のカラム)                                │
└─────────────┬──────────────────────────────────────────┘
              │
              │ 物理FK (ON DELETE CASCADE)
              ↓
┌────────────────────────────────────────────────────────┐
│            langchain_pg_embedding                      │
│                                                         │
│ PK  uuid                                               │
│ FK  collection_id      ───→ langchain_pg_collection   │
│ FK  document_id        ───→ documents.id              │
│     embedding          VECTOR(768)                     │
│     document           TEXT                            │
│     chunk_index                                        │
│     ... (その他のカラム)                                │
└────────────────────────────────────────────────────────┘
              ↑
              │ 物理FK (ON DELETE CASCADE)
              │
┌────────────────────────────────────────────────────────┐
│           langchain_pg_collection                      │
│                                                         │
│ PK  uuid                                               │
│ U   name                                               │
│     cmetadata          JSONB                           │
│     created_at                                         │
│     updated_at                                         │
└────────────────────────────────────────────────────────┘


独立テーブル:
┌────────────────────┐   ┌────────────────────┐
│   system_logs      │   │  system_settings   │
│                    │   │                    │
│ PK  id             │   │ PK  id             │
│     service_name   │   │ U   key            │
│     level          │   │     value (JSON)   │
│     message        │   │     created_at     │
│     log_metadata   │   │     updated_at     │
│     created_at     │   │                    │
└────────────────────┘   └────────────────────┘
```

### admindb 内の外部キー制約

```sql
-- documents.knowledge_base_id → knowledge_bases.id
ALTER TABLE documents
  ADD CONSTRAINT fk_documents_kb
  FOREIGN KEY (knowledge_base_id)
  REFERENCES knowledge_bases(id)
  ON DELETE CASCADE;

-- langchain_pg_embedding.collection_id → langchain_pg_collection.uuid
ALTER TABLE langchain_pg_embedding
  ADD CONSTRAINT fk_embedding_collection
  FOREIGN KEY (collection_id)
  REFERENCES langchain_pg_collection(uuid)
  ON DELETE CASCADE;

-- langchain_pg_embedding.document_id → documents.id
ALTER TABLE langchain_pg_embedding
  ADD CONSTRAINT fk_embedding_document
  FOREIGN KEY (document_id)
  REFERENCES documents(id)
  ON DELETE CASCADE;
```

---

## データベース間の論理関係

### 論理的な外部キー（物理制約なし）

```
┌──────────────────────────────────────────────────────────────┐
│  マイクロサービス間のデータ連携                               │
└──────────────────────────────────────────────────────────────┘

authdb.users (1) ─────論理────→ (1) apidb.profiles
  │                                    │
  │ users.id  ←─────→  profiles.user_id
  │
  │ カーディナリティ: 1:1
  │ - 1ユーザーにつき1プロファイル
  │ - UNIQUE制約で保証


authdb.users (1) ─────論理────→ (N) admindb.login_logs
  │                                    │
  │ users.id  ←─────→  login_logs.user_id
  │
  │ カーディナリティ: 1:N
  │ - 1ユーザーは複数のログイン履歴を持つ


authdb.users (1) ─────論理────→ (N) admindb.knowledge_bases
  │                                    │
  │ users.id  ←─────→  knowledge_bases.user_id
  │
  │ カーディナリティ: 1:N
  │ - 1ユーザーは複数のナレッジベースを所有可能
```

### 整合性保証の仕組み

**物理FK制約がない理由**:
1. データベース分離（マイクロサービスの独立性）
2. 障害時の影響範囲限定
3. 将来的な物理分離への対応

**整合性の保証方法**:
```python
# JWT トークンによる認証済みユーザーIDの取得
@router.post("/profile")
async def create_profile(
    profile_data: ProfileCreate,
    current_user: dict = Depends(get_current_user)  # JWT検証
):
    user_id = current_user["sub"]  # authdb.users.id から取得済み

    # user_id は必ず存在するユーザー（JWT検証済み）
    profile = Profile(user_id=user_id, ...)
    db.add(profile)
    db.commit()
```

---

## 外部キー制約の詳細

### admindb 内の物理FK（カスケード削除）

#### knowledge_bases → documents

```sql
documents.knowledge_base_id → knowledge_bases.id (ON DELETE CASCADE)
```

**動作**:
```sql
-- ナレッジベース削除時
DELETE FROM knowledge_bases WHERE id = 'kb-uuid';

-- 関連ドキュメントも自動削除される（CASCADE）
-- SELECT * FROM documents WHERE knowledge_base_id = 'kb-uuid';
-- => 0 rows
```

**理由**:
- ナレッジベースが削除されたらドキュメントも不要
- 孤児レコードの防止
- ストレージクリーンアップの自動化

#### documents → langchain_pg_embedding

```sql
langchain_pg_embedding.document_id → documents.id (ON DELETE CASCADE)
```

**動作**:
```sql
-- ドキュメント削除時
DELETE FROM documents WHERE id = 'doc-uuid';

-- 関連するベクトル埋め込みも自動削除される（CASCADE）
-- SELECT * FROM langchain_pg_embedding WHERE document_id = 'doc-uuid';
-- => 0 rows
```

**理由**:
- ドキュメントが削除されたらベクトル埋め込みも不要
- ストレージ節約（ベクトルは大容量）

#### langchain_pg_collection → langchain_pg_embedding

```sql
langchain_pg_embedding.collection_id → langchain_pg_collection.uuid (ON DELETE CASCADE)
```

**動作**:
```sql
-- コレクション削除時
DELETE FROM langchain_pg_collection WHERE uuid = 'collection-uuid';

-- 関連する全ベクトル埋め込みも自動削除される（CASCADE）
```

---

## カーディナリティ

### 1:1 関係

```
authdb.users (1) ←───→ (1) apidb.profiles

実装:
- profiles.user_id UNIQUE制約
- 1ユーザーにつき1プロファイルのみ
```

### 1:N 関係

```
authdb.users (1) ←───→ (N) admindb.login_logs

実装:
- login_logs.user_id（UNIQUE制約なし）
- 1ユーザーは複数のログイン履歴を持つ


authdb.users (1) ←───→ (N) admindb.knowledge_bases

実装:
- knowledge_bases.user_id（UNIQUE制約なし）
- 1ユーザーは複数のナレッジベースを所有可能


knowledge_bases (1) ←───→ (N) documents

実装:
- documents.knowledge_base_id（外部キー）
- 1ナレッジベースは複数のドキュメントを含む


documents (1) ←───→ (N) langchain_pg_embedding

実装:
- langchain_pg_embedding.document_id（外部キー）
- 1ドキュメントは複数のベクトル埋め込みを持つ（チャンク分割）


langchain_pg_collection (1) ←───→ (N) langchain_pg_embedding

実装:
- langchain_pg_embedding.collection_id（外部キー）
- 1コレクションは複数のベクトル埋め込みを含む
```

---

## テーブル関係のまとめ

### データベース内の関係（物理FK）

| 親テーブル | 子テーブル | FK カラム | ON DELETE |
|----------|----------|----------|-----------|
| knowledge_bases | documents | knowledge_base_id | CASCADE |
| documents | langchain_pg_embedding | document_id | CASCADE |
| langchain_pg_collection | langchain_pg_embedding | collection_id | CASCADE |

### データベース間の関係（論理FK）

| 親テーブル | 子テーブル | 関連カラム | カーディナリティ |
|----------|----------|----------|---------------|
| authdb.users | apidb.profiles | user_id | 1:1 |
| authdb.users | admindb.login_logs | user_id | 1:N |
| authdb.users | admindb.knowledge_bases | user_id | 1:N |
| authdb.users | admindb.documents | user_id | 1:N |

---

## 視覚的な全体像

```
[Auth Service]                [User API]              [Admin API]
     ↓                            ↓                        ↓
┌─────────┐                 ┌─────────┐            ┌─────────────┐
│  users  │─────論理────────→│profiles │            │ login_logs  │
│         │                 └─────────┘            └──────┬──────┘
│  - id   │                                               │ 論理FK
│  - email│                                               ↓
│  - pwd  │                                        ┌─────────────┐
│  - roles│────────論理────────────────────────────→│knowledge_   │
└─────────┘                                        │  bases      │
                                                   └──────┬──────┘
                                                          │ 物理FK
                                                          │ CASCADE
                                                          ↓
                                                   ┌─────────────┐
                                                   │ documents   │
                                                   └──────┬──────┘
                                                          │ 物理FK
                                                          │ CASCADE
                                                          ↓
┌──────────────────────────────────────────────┐  ┌─────────────┐
│        langchain_pg_collection               │←─┤ langchain_  │
│                                              │FK│ pg_embedding│
│  - uuid (PK)                                 │  └─────────────┘
│  - name (UNIQUE)                             │
│  - cmetadata (JSONB)                         │
└──────────────────────────────────────────────┘

┌─────────────┐
│system_logs  │  独立テーブル（他テーブルとの関連なし）
└─────────────┘

┌─────────────┐
│system_      │  独立テーブル（キー・バリューストア）
│ settings    │
└─────────────┘
```

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [authdb スキーマ](./04-authdb-schema.md)
- [apidb スキーマ](./05-apidb-schema.md)
- [admindb スキーマ](./06-admindb-schema.md)
- [データベース間連携](./08-cross-database-relations.md)

---

**次のステップ**: [データベース間連携](./08-cross-database-relations.md) を参照して、論理的な外部キー関係の実装詳細を確認してください。