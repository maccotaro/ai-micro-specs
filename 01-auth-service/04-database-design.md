# authdbデータベース設計

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [データベース構成](#データベース構成)
- [テーブル定義](#テーブル定義)
- [インデックス設計](#インデックス設計)
- [制約とバリデーション](#制約とバリデーション)
- [マイグレーション管理](#マイグレーション管理)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## 概要

authdbは認証サービス専用のPostgreSQLデータベースです。ユーザー認証情報（メールアドレス、パスワードハッシュ、ロール）を安全に管理します。

### 設計方針

1. **セキュリティ第一**
   - パスワードは必ずハッシュ化して保存
   - 個人情報の暗号化（必要に応じて）
   - アクセス制御の厳格化

2. **シンプル設計**
   - 認証に必要な最小限の情報のみ
   - 詳細プロフィールはapidb.profilesで管理

3. **パフォーマンス**
   - 頻繁なクエリにインデックス設定
   - UUID主キーの採用

4. **監査証跡**
   - created_at, updated_atの自動記録
   - ユーザー操作履歴の保持

---

## データベース構成

### 接続情報

```bash
# 開発環境
DATABASE_URL=postgresql://postgres:password@localhost:5432/authdb

# Docker環境
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/authdb

# 本番環境（例）
DATABASE_URL=postgresql://auth_user:secure_password@postgres.example.com:5432/authdb
```

### データベース作成

```sql
-- データベース作成
CREATE DATABASE authdb
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

-- UUID拡張有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

## テーブル定義

### users テーブル

ユーザー認証情報を管理するメインテーブル。

#### テーブル構造

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE
);
```

#### フィールド説明

| カラム名 | データ型 | NULL | デフォルト | 説明 |
|---------|---------|------|-----------|------|
| id | UUID | NO | uuid_generate_v4() | ユーザーID（主キー） |
| email | VARCHAR(255) | NO | - | メールアドレス（一意） |
| hashed_password | VARCHAR(255) | NO | - | bcryptハッシュ化されたパスワード |
| role | VARCHAR(50) | NO | 'user' | ユーザーロール（user, admin） |
| is_active | BOOLEAN | NO | TRUE | アカウント有効フラグ |
| is_verified | BOOLEAN | NO | FALSE | メール認証済みフラグ |
| created_at | TIMESTAMP WITH TIME ZONE | NO | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | TIMESTAMP WITH TIME ZONE | NO | CURRENT_TIMESTAMP | 更新日時 |
| last_login_at | TIMESTAMP WITH TIME ZONE | YES | NULL | 最終ログイン日時 |
| failed_login_attempts | INTEGER | NO | 0 | ログイン失敗回数 |
| locked_until | TIMESTAMP WITH TIME ZONE | YES | NULL | アカウントロック解除時刻 |

#### ロール種別

| ロール値 | 説明 | 権限 |
|---------|------|------|
| user | 一般ユーザー | 基本機能のみアクセス可能 |
| admin | 管理者 | 全機能アクセス可能、管理画面利用可 |

#### データ例

```sql
INSERT INTO users (id, email, hashed_password, role, is_active, is_verified)
VALUES
(
    '550e8400-e29b-41d4-a716-446655440000',
    'user@example.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyK.T3lQ.Dz2',
    'user',
    TRUE,
    TRUE
),
(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
    'admin@example.com',
    '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW',
    'admin',
    TRUE,
    TRUE
);
```

#### 制約

```sql
-- メールアドレスの一意制約
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);

-- メールアドレスの形式チェック
ALTER TABLE users ADD CONSTRAINT users_email_check
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- ロールの値チェック
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('user', 'admin'));

-- failed_login_attemptsの範囲チェック
ALTER TABLE users ADD CONSTRAINT users_failed_attempts_check
    CHECK (failed_login_attempts >= 0);
```

---

### refresh_tokens テーブル（オプション）

リフレッシュトークンを管理するテーブル（Redisで管理する代替案もあり）。

#### テーブル構造

```sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_jti VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP WITH TIME ZONE,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE
);
```

#### フィールド説明

| カラム名 | データ型 | NULL | デフォルト | 説明 |
|---------|---------|------|-----------|------|
| id | UUID | NO | uuid_generate_v4() | トークンレコードID |
| user_id | UUID | NO | - | ユーザーID（外部キー） |
| token_jti | VARCHAR(255) | NO | - | JWT ID（一意識別子） |
| expires_at | TIMESTAMP WITH TIME ZONE | NO | - | 有効期限 |
| created_at | TIMESTAMP WITH TIME ZONE | NO | CURRENT_TIMESTAMP | 作成日時 |
| revoked_at | TIMESTAMP WITH TIME ZONE | YES | NULL | 無効化日時 |
| is_revoked | BOOLEAN | NO | FALSE | 無効化フラグ |

#### データ例

```sql
INSERT INTO refresh_tokens (user_id, token_jti, expires_at)
VALUES
(
    '550e8400-e29b-41d4-a716-446655440000',
    'abc123def456ghi789',
    CURRENT_TIMESTAMP + INTERVAL '7 days'
);
```

---

## インデックス設計

### users テーブルのインデックス

```sql
-- 主キーインデックス（自動作成）
-- PRIMARY KEY (id)

-- メールアドレス検索用（ログイン時）
CREATE INDEX idx_users_email ON users(email);

-- ロール検索用
CREATE INDEX idx_users_role ON users(role);

-- アクティブユーザー検索用
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = TRUE;

-- 最終ログイン日時検索用
CREATE INDEX idx_users_last_login ON users(last_login_at DESC);

-- 複合インデックス（メール + アクティブ）
CREATE INDEX idx_users_email_active ON users(email, is_active);
```

### refresh_tokens テーブルのインデックス

```sql
-- 主キーインデックス（自動作成）
-- PRIMARY KEY (id)

-- JTI検索用（トークン検証時）
CREATE UNIQUE INDEX idx_refresh_tokens_jti ON refresh_tokens(token_jti);

-- ユーザーIDによる検索用
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);

-- 有効期限検索用（期限切れトークン削除時）
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

-- 無効化されていない有効なトークン検索用
CREATE INDEX idx_refresh_tokens_active
    ON refresh_tokens(user_id, is_revoked, expires_at)
    WHERE is_revoked = FALSE;
```

### インデックス効果測定

```sql
-- インデックスの使用状況確認
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- テーブルサイズとインデックスサイズ確認
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) -
                   pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public';
```

---

## 制約とバリデーション

### データ整合性制約

```sql
-- updated_at自動更新トリガー
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- アカウントロック自動解除トリガー
CREATE OR REPLACE FUNCTION check_account_lock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.locked_until IS NOT NULL AND NEW.locked_until < CURRENT_TIMESTAMP THEN
        NEW.failed_login_attempts = 0;
        NEW.locked_until = NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_user_login
    BEFORE UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.last_login_at IS DISTINCT FROM NEW.last_login_at)
    EXECUTE FUNCTION check_account_lock();
```

### アプリケーションレベルのバリデーション

```python
from pydantic import BaseModel, EmailStr, field_validator

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    role: str = "user"

    @field_validator('password')
    def validate_password(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if not any(c.isupper() for c in v):
            raise ValueError('Password must contain at least one uppercase letter')
        if not any(c.islower() for c in v):
            raise ValueError('Password must contain at least one lowercase letter')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain at least one digit')
        return v

    @field_validator('role')
    def validate_role(cls, v):
        if v not in ['user', 'admin']:
            raise ValueError('Role must be either "user" or "admin"')
        return v
```

---

## マイグレーション管理

### Alembic設定

```python
# alembic.ini
[alembic]
script_location = alembic
sqlalchemy.url = postgresql://postgres:password@localhost:5432/authdb
```

### マイグレーション作成

```bash
# 新規マイグレーション作成
alembic revision -m "create_users_table"

# 自動マイグレーション生成
alembic revision --autogenerate -m "add_email_verification"

# マイグレーション適用
alembic upgrade head

# マイグレーション履歴確認
alembic history

# ロールバック
alembic downgrade -1
```

### 初期マイグレーション例

```python
"""create users table

Revision ID: 001
Revises:
Create Date: 2025-09-30 10:00:00
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '001'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('uuid_generate_v4()')),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('hashed_password', sa.String(255), nullable=False),
        sa.Column('role', sa.String(50), nullable=False, server_default='user'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('is_verified', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('last_login_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('failed_login_attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('locked_until', sa.TIMESTAMP(timezone=True), nullable=True),
    )

    op.create_unique_constraint('users_email_unique', 'users', ['email'])
    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_role', 'users', ['role'])

def downgrade():
    op.drop_index('idx_users_role', table_name='users')
    op.drop_index('idx_users_email', table_name='users')
    op.drop_constraint('users_email_unique', 'users', type_='unique')
    op.drop_table('users')
```

---

## パフォーマンス最適化

### コネクションプール設定

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

engine = create_engine(
    "postgresql://postgres:password@localhost:5432/authdb",
    poolclass=QueuePool,
    pool_size=10,           # 常時保持する接続数
    max_overflow=20,        # 追加で作成できる接続数
    pool_timeout=30,        # 接続待機タイムアウト（秒）
    pool_recycle=3600,      # 接続リサイクル時間（秒）
    pool_pre_ping=True,     # 接続の有効性確認
)
```

### クエリ最適化

```sql
-- ログイン時のクエリ（最適化版）
EXPLAIN ANALYZE
SELECT id, email, hashed_password, role, is_active, failed_login_attempts, locked_until
FROM users
WHERE email = 'user@example.com'
  AND is_active = TRUE;

-- インデックスが使用されていることを確認
-- Index Scan using idx_users_email_active on users ...
```

### 定期メンテナンス

```sql
-- 統計情報更新
ANALYZE users;
ANALYZE refresh_tokens;

-- バキューム処理
VACUUM ANALYZE users;
VACUUM ANALYZE refresh_tokens;

-- 期限切れトークンの削除（定期実行）
DELETE FROM refresh_tokens
WHERE expires_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
```

### モニタリングクエリ

```sql
-- 長時間実行中のクエリ確認
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - pg_stat_activity.query_start > interval '5 seconds'
ORDER BY duration DESC;

-- テーブルサイズ確認
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- インデックスの肥大化確認
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

---

## 関連ドキュメント

- [認証サービス概要](./01-overview.md)
- [認証API仕様](./02-api-specification.md)
- [セキュリティ実装](./05-security-implementation.md)
- [データベースインフラ設計](../06-database/01-overview.md)
- [データ整合性管理](../08-integration/05-data-consistency.md)