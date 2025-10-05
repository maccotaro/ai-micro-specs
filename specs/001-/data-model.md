# データモデル: ナレッジベースのコレクション階層構造

**作成日**: 2025-10-05
**バージョン**: 1.0

## エンティティ概要

このデータモデルは、ナレッジベース→コレクション→ドキュメントの階層構造を定義します。

```
KnowledgeBase (既存)
    ↓ 1対多
Collection (新規)
    ↓ 1対多
Document (既存、変更)
```

## 1. Collection (新規エンティティ)

### 説明

ナレッジベース内のドキュメントを整理するための中間コンテナ。各コレクションは1つのナレッジベースに属し、複数のドキュメントを含む。

### 属性

| 属性名 | 型 | 制約 | デフォルト | 説明 |
|--------|-----|------|-----------|------|
| `id` | UUID | PRIMARY KEY | gen_random_uuid() | コレクション一意識別子 |
| `knowledge_base_id` | UUID | NOT NULL, FK → knowledge_bases.id | - | 親ナレッジベースID |
| `name` | VARCHAR(255) | NOT NULL | - | コレクション名 (ナレッジベース内で一意) |
| `description` | TEXT | NULL, CHECK (char_length <= 10000) | NULL | コレクションの説明 (オプショナル、最大10000文字) |
| `is_default` | BOOLEAN | NOT NULL | FALSE | デフォルトコレクションフラグ |
| `created_at` | TIMESTAMP | NOT NULL | NOW() | 作成日時 |
| `updated_at` | TIMESTAMP | NOT NULL | NOW() | 更新日時 (自動更新) |

### インデックス

```sql
CREATE INDEX idx_collections_kb_id ON collections(knowledge_base_id);
CREATE INDEX idx_collections_is_default ON collections(knowledge_base_id, is_default);
```

### 制約

```sql
-- ナレッジベース内でコレクション名は一意
CONSTRAINT uq_kb_collection_name UNIQUE (knowledge_base_id, name)

-- ナレッジベースごとに1つのデフォルトコレクションのみ
CONSTRAINT uq_kb_default_collection UNIQUE (knowledge_base_id, is_default)
WHERE is_default = TRUE

-- ナレッジベース削除時にカスケード削除
FOREIGN KEY (knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE CASCADE
```

### 関係

- **knowledge_base**: 多対1 (Collection → KnowledgeBase)
  - 各コレクションは1つのナレッジベースに属する
  - ナレッジベース削除時、すべてのコレクションも削除される

- **documents**: 1対多 (Collection → Document)
  - 各コレクションは複数のドキュメントを含む
  - コレクション削除時の動作はユーザーの選択に依存 (アプリケーションレイヤーで処理)

### 検証ルール

1. **名前の一意性**: 同じナレッジベース内で重複するコレクション名は許可しない
2. **デフォルトコレクションの一意性**: 各ナレッジベースには必ず1つのデフォルトコレクションが存在する
3. **デフォルトコレクションの保護**:
   - デフォルトコレクション(`is_default = TRUE`)は削除不可
   - デフォルトコレクションの名前変更は不可
4. **名前の長さ**: 1文字以上255文字以下
5. **説明の長さ**: 10,000文字以下 (オプショナル)

### 状態遷移

```
[作成] → [アクティブ]
         ↓
      [更新] (名前、説明の変更)
         ↓
      [削除] (is_default = FALSE のみ)
```

**削除時の動作**:
- ユーザーが選択 (アプリケーションレイヤーで処理):
  - **オプション1**: ドキュメントも一緒に削除
  - **オプション2**: ドキュメントをデフォルトコレクションに移動

### 計算フィールド (非永続化)

| フィールド名 | 型 | 計算方法 |
|-------------|-----|---------|
| `document_count` | INTEGER | `SELECT COUNT(*) FROM documents WHERE collection_id = collections.id` |

**パフォーマンス最適化**: Redisでキャッシュ (TTL: 60秒)

## 2. Document (既存、変更)

### 説明

アップロードされたファイルを表すエンティティ。1つのコレクションに必ず属する。

### 追加属性

| 属性名 | 型 | 制約 | デフォルト | 説明 |
|--------|-----|------|-----------|------|
| `collection_id` | UUID | NOT NULL, FK → collections.id | デフォルトコレクションID | 所属コレクションID |

### 新しいインデックス

```sql
CREATE INDEX idx_documents_collection_id ON documents(collection_id);
```

### 新しい制約

```sql
-- コレクション削除時はRESTRICT (アプリケーションレイヤーで処理)
FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE RESTRICT
```

### 検証ルール (追加)

1. **collection_idは必須**: すべてのドキュメントは必ずコレクションに属する
2. **デフォルトコレクションへのフォールバック**: collection_idがNULLまたは無効な場合、デフォルトコレクションに自動割り当て (移行時のみ)
3. **コレクション存在チェック**: collection_idは有効なcollections.idを参照しなければならない

### 既存属性 (変更なし)

- `id`: UUID (主キー)
- `title`: VARCHAR(255)
- `file_name`: VARCHAR(255)
- `file_path`: TEXT
- `ocr_result`: JSONB
- `hierarchical_elements`: JSONB
- `knowledge_base_id`: UUID (FK → knowledge_bases.id) ※変更なし
- `created_at`: TIMESTAMP
- `updated_at`: TIMESTAMP

## 3. KnowledgeBase (既存、変更なし)

### 説明

ナレッジベースのルートエンティティ。コレクションとドキュメントを所有する。

### 追加の保証

- **デフォルトコレクションの自動作成**: ナレッジベース作成時、自動的にデフォルトコレクション("未分類")を作成
- **最小1コレクション**: 各ナレッジベースには最低1つのコレクション(デフォルト)が常に存在する

## データベーススキーマ (DDL)

### 新規テーブル作成

```sql
CREATE TABLE collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_base_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT CHECK (char_length(description) <= 10000),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- 外部キー制約
    CONSTRAINT fk_collections_kb
        FOREIGN KEY (knowledge_base_id)
        REFERENCES knowledge_bases(id)
        ON DELETE CASCADE,

    -- 一意制約
    CONSTRAINT uq_kb_collection_name
        UNIQUE (knowledge_base_id, name)
);

-- 部分UNIQUE制約 (PostgreSQL 15+)
CREATE UNIQUE INDEX uq_kb_default_collection
    ON collections(knowledge_base_id, is_default)
    WHERE is_default = TRUE;

-- インデックス
CREATE INDEX idx_collections_kb_id ON collections(knowledge_base_id);
CREATE INDEX idx_collections_is_default ON collections(knowledge_base_id, is_default);

-- 更新日時の自動更新トリガー
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_collections_updated_at
    BEFORE UPDATE ON collections
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

### 既存テーブルの変更

```sql
-- documentsテーブルにcollection_idカラムを追加
ALTER TABLE documents
    ADD COLUMN collection_id UUID;

-- 外部キー制約 (まだNOT NULLではない、移行後に追加)
ALTER TABLE documents
    ADD CONSTRAINT fk_documents_collection
        FOREIGN KEY (collection_id)
        REFERENCES collections(id)
        ON DELETE RESTRICT;

-- インデックス
CREATE INDEX idx_documents_collection_id ON documents(collection_id);
```

### 移行後のスキーマ変更

```sql
-- すべてのドキュメントがcollection_idを持つことを確認してから実行
ALTER TABLE documents
    ALTER COLUMN collection_id SET NOT NULL;
```

## Redisキャッシング

### キャッシュキーパターン

| キー | TTL | 値の型 | 説明 |
|------|-----|--------|------|
| `collection:{kb_id}:list` | 300秒 | JSON配列 | ナレッジベース内のコレクション一覧 |
| `collection:{id}:details` | 300秒 | JSON | コレクション詳細 (ドキュメント一覧含む) |
| `collection:{id}:doc_count` | 60秒 | 整数 | コレクション内のドキュメント数 |

### キャッシュ無効化タイミング

| 操作 | 無効化するキー |
|------|---------------|
| コレクション作成 | `collection:{kb_id}:list` |
| コレクション更新 | `collection:{kb_id}:list`, `collection:{id}:details` |
| コレクション削除 | `collection:{kb_id}:list`, `collection:{id}:details`, `collection:{id}:doc_count` |
| ドキュメント追加 | `collection:{id}:doc_count` |
| ドキュメント削除 | `collection:{id}:doc_count` |
| ドキュメント移動 | 旧コレクションと新コレクションの`doc_count` |

## エンティティ関係図 (ERD)

```
┌─────────────────────┐
│  KnowledgeBase      │
│                     │
│ - id (PK)           │
│ - name              │
│ - description       │
│ - user_id           │
│ - created_at        │
│ - updated_at        │
└──────────┬──────────┘
           │ 1
           │
           │ many
┌──────────▼──────────┐
│  Collection         │
│                     │
│ - id (PK)           │
│ - knowledge_base_id │ (FK)
│ - name              │
│ - description       │
│ - is_default        │
│ - created_at        │
│ - updated_at        │
└──────────┬──────────┘
           │ 1
           │
           │ many
┌──────────▼──────────┐
│  Document           │
│                     │
│ - id (PK)           │
│ - collection_id     │ (FK, NEW)
│ - title             │
│ - file_name         │
│ - file_path         │
│ - ocr_result        │
│ - hierarchical_     │
│   elements          │
│ - created_at        │
│ - updated_at        │
└─────────────────────┘
```

## 移行戦略

### フェーズ1: スキーマ追加 (後方互換性あり)

```sql
-- collectionsテーブル作成
CREATE TABLE collections (...);

-- documentsテーブルにNULLABLEなcollection_idを追加
ALTER TABLE documents ADD COLUMN collection_id UUID;
```

### フェーズ2: データ移行

```python
# 各ナレッジベースにデフォルトコレクションを作成
# 既存ドキュメントをデフォルトコレクションに割り当て
```

### フェーズ3: 制約追加

```sql
-- NOT NULL制約を追加
ALTER TABLE documents ALTER COLUMN collection_id SET NOT NULL;
```

詳細は `research.md` の「5. データベース移行戦略」を参照。

---
**ステータス**: データモデル設計完了 ✅
