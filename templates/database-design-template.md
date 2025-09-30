# [データベース名] - データベース設計書

**更新日**: YYYY-MM-DD
**バージョン**: 1.0
**DBMS**: PostgreSQL [バージョン]

## 概要

このドキュメントは、[データベース名]のスキーマ設計を説明します。

## データベース情報

- **データベース名**: `database_name`
- **文字コード**: UTF-8
- **タイムゾーン**: UTC
- **接続ポート**: 5432

## テーブル一覧

| テーブル名 | 説明 | 主な用途 |
|----------|------|---------|
| `users` | ユーザー情報 | ユーザー管理 |
| `profiles` | プロフィール | ユーザー詳細情報 |

---

## テーブル定義

### テーブル名: `table_name`

**説明**: [テーブルの説明]

#### カラム定義

| カラム名 | 型 | NULL許可 | デフォルト値 | 説明 |
|---------|-------|---------|------------|------|
| `id` | UUID | NO | uuid_generate_v4() | 主キー |
| `name` | VARCHAR(255) | NO | - | 名前 |
| `email` | VARCHAR(255) | NO | - | メールアドレス |
| `age` | INTEGER | YES | NULL | 年齢 |
| `is_active` | BOOLEAN | NO | true | アクティブフラグ |
| `created_at` | TIMESTAMP | NO | NOW() | 作成日時 |
| `updated_at` | TIMESTAMP | NO | NOW() | 更新日時 |

#### 制約

##### 主キー
```sql
PRIMARY KEY (id)
```

##### 外部キー
```sql
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
```

##### ユニーク制約
```sql
UNIQUE (email)
```

##### チェック制約
```sql
CHECK (age >= 0 AND age <= 150)
```

#### インデックス

| インデックス名 | 種類 | カラム | 説明 |
|--------------|------|--------|------|
| `idx_table_name_email` | UNIQUE | email | メールアドレス検索用 |
| `idx_table_name_created_at` | BTREE | created_at | 作成日時での検索用 |

```sql
CREATE INDEX idx_table_name_email ON table_name(email);
CREATE INDEX idx_table_name_created_at ON table_name(created_at);
```

#### DDL

```sql
CREATE TABLE table_name (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    age INTEGER CHECK (age >= 0 AND age <= 150),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_table_name_email ON table_name(email);
CREATE INDEX idx_table_name_created_at ON table_name(created_at);
```

---

## ER図

```
[users] 1 ---- * [profiles]
  |
  | 1
  |
  * [documents]
```

### リレーションシップ

| 親テーブル | 子テーブル | 関係 | 説明 |
|----------|----------|------|------|
| users | profiles | 1:1 | ユーザーとプロフィール |
| users | documents | 1:N | ユーザーとドキュメント |

---

## データ型の選定理由

### UUID vs SERIAL
- **選定**: UUID
- **理由**: 分散システムでの一意性確保、セキュリティ向上

### TIMESTAMP vs TIMESTAMPTZ
- **選定**: TIMESTAMP
- **理由**: アプリケーション側でタイムゾーン管理、UTC統一

---

## インデックス戦略

### B-Tree インデックス
- **用途**: 等価検索、範囲検索
- **対象カラム**: created_at, updated_at

### ハッシュインデックス
- **用途**: 等価検索のみ
- **対象カラム**: email

### 複合インデックス
```sql
CREATE INDEX idx_composite ON table_name(column1, column2);
```

---

## パーティショニング

### 時系列パーティショニング（将来拡張時）
```sql
CREATE TABLE table_name (
    ...
) PARTITION BY RANGE (created_at);

CREATE TABLE table_name_2025_01 PARTITION OF table_name
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

---

## マイグレーション管理

### ツール
- Alembic / Flyway / 手動SQL

### マイグレーションファイル命名規則
```
V{バージョン}__{説明}.sql
例: V001__create_users_table.sql
```

### ロールバック方針
- 各マイグレーションにロールバックSQLを用意
- 本番環境では慎重にロールバック実行

---

## バックアップ戦略

### フルバックアップ
- **頻度**: 毎日
- **コマンド**: `pg_dump database_name > backup.sql`

### 増分バックアップ
- **頻度**: 1時間ごと
- **方式**: WAL（Write-Ahead Log）アーカイブ

### リストア手順
```bash
psql database_name < backup.sql
```

---

## パフォーマンスチューニング

### クエリ最適化
```sql
EXPLAIN ANALYZE SELECT * FROM table_name WHERE email = 'test@example.com';
```

### 統計情報更新
```sql
ANALYZE table_name;
```

### バキューム
```sql
VACUUM ANALYZE table_name;
```

---

## セキュリティ

### アクセス制御
```sql
GRANT SELECT, INSERT, UPDATE ON table_name TO app_user;
REVOKE DELETE ON table_name FROM app_user;
```

### データ暗号化
- **at rest**: ディスク暗号化
- **in transit**: SSL/TLS接続

---

## サンプルクエリ

### データ挿入
```sql
INSERT INTO table_name (name, email, age)
VALUES ('太郎', 'taro@example.com', 25);
```

### データ取得
```sql
SELECT * FROM table_name WHERE email = 'taro@example.com';
```

### データ更新
```sql
UPDATE table_name
SET age = 26, updated_at = NOW()
WHERE id = '123e4567-e89b-12d3-a456-426614174000';
```

### データ削除
```sql
DELETE FROM table_name WHERE id = '123e4567-e89b-12d3-a456-426614174000';
```

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [ER図](./diagrams/er-diagram.png)
- [マイグレーション管理](./09-migration-management.md)

---

**作成者**: [名前]
**最終更新**: YYYY-MM-DD