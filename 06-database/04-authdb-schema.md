# authdb - 認証データベーススキーマ詳細

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [データベース概要](#データベース概要)
- [usersテーブル](#usersテーブル)
- [インデックス設計](#インデックス設計)
- [制約とルール](#制約とルール)
- [Auth Service との統合](#auth-service-との統合)
- [セキュリティ考慮事項](#セキュリティ考慮事項)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## データベース概要

### 基本情報

| 項目 | 値 |
|-----|-----|
| データベース名 | `authdb` |
| 使用サービス | ai-micro-api-auth (Port 8002) |
| 責務 | ユーザー認証、アクセス制御、ロール管理 |
| 接続URL | `postgresql://postgres:password@host.docker.internal:5432/authdb` |

### テーブル一覧

| テーブル名 | 説明 | レコード例 |
|---------|------|---------|
| `users` | ユーザー認証情報 | ユーザー数に比例（小〜中規模） |

### 拡張機能

```sql
-- UUID生成機能
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

## usersテーブル

### テーブル概要

**目的**: ユーザーの認証情報とアカウント状態の管理

**主要機能**:
- メール/パスワード認証
- ロールベースアクセス制御（RBAC）
- アカウントロック機能（ブルートフォース攻撃対策）
- ログイン履歴追跡

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  roles TEXT[] NOT NULL DEFAULT ARRAY['user'],
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,
  login_attempts INTEGER DEFAULT 0,
  last_login_at TIMESTAMP,
  locked_until TIMESTAMP
);
```

### カラム詳細

#### id (UUID)

**型**: `uuid`
**制約**: PRIMARY KEY, DEFAULT uuid_generate_v4()

**説明**: ユーザーの一意識別子

**生成方法**:
```sql
-- 自動生成（デフォルト）
INSERT INTO users (email, password_hash) VALUES ('user@example.com', 'hash');
-- id は自動的に UUID が生成される

-- 明示的に指定（通常は不要）
INSERT INTO users (id, email, password_hash)
VALUES ('550e8400-e29b-41d4-a716-446655440000', 'user@example.com', 'hash');
```

**他テーブルとの連携**:
- `apidb.profiles.user_id` → `authdb.users.id` (論理FK)
- `admindb.login_logs.user_id` → `authdb.users.id` (論理FK)
- `admindb.knowledge_bases.user_id` → `authdb.users.id` (論理FK)

#### email (TEXT)

**型**: `TEXT`
**制約**: UNIQUE, NOT NULL

**説明**: ユーザーのメールアドレス（ログインID）

**バリデーション**:
```python
# アプリケーション側でバリデーション
from pydantic import EmailStr

class UserCreate(BaseModel):
    email: EmailStr  # RFC 5322 準拠のメールアドレス
    password: str
```

**データ例**:
```sql
-- 有効な例
'user@example.com'
'test.user+tag@example.co.jp'
'admin@subdomain.example.com'

-- 無効な例（アプリケーション側で拒否）
'invalid-email'
'@example.com'
'user@'
```

**ユニーク制約**:
```sql
-- 重複登録の試行
INSERT INTO users (email, password_hash) VALUES ('user@example.com', 'hash1');
-- OK

INSERT INTO users (email, password_hash) VALUES ('user@example.com', 'hash2');
-- ERROR: duplicate key value violates unique constraint "users_email_key"
```

#### password_hash (TEXT)

**型**: `TEXT`
**制約**: NOT NULL

**説明**: パスワードのハッシュ値（bcrypt）

**ハッシュアルゴリズム**: bcrypt（cost factor 12）

**生成例**:
```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# パスワードハッシュ化
plain_password = "SecurePassword123!"
password_hash = pwd_context.hash(plain_password)
# => '$2b$12$abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJ'

# ハッシュ値の長さ: 約60文字
```

**検証例**:
```python
# パスワード検証
is_valid = pwd_context.verify("SecurePassword123!", password_hash)
# => True or False
```

**セキュリティ注意**:
- 平文パスワードは絶対に保存しない
- bcrypt は意図的に遅い（ブルートフォース攻撃対策）
- cost factor を上げると処理時間が増加（現在: 12）

#### roles (TEXT[])

**型**: `TEXT[]` (配列)
**制約**: NOT NULL, DEFAULT ARRAY['user']

**説明**: ユーザーのロール（複数指定可能）

**ロール一覧**:
| ロール | 説明 | 権限 |
|-------|------|------|
| `user` | 一般ユーザー | 基本機能のみ |
| `admin` | 管理者 | 管理機能アクセス可 |
| `superadmin` | スーパー管理者 | すべての機能 |

**データ例**:
```sql
-- 一般ユーザー（デフォルト）
roles = ARRAY['user']

-- 管理者権限あり
roles = ARRAY['user', 'admin']

-- スーパー管理者
roles = ARRAY['user', 'admin', 'superadmin']
```

**ロール確認クエリ**:
```sql
-- admin ロールを持つユーザー検索
SELECT * FROM users WHERE 'admin' = ANY(roles);

-- 複数ロールのいずれかを持つユーザー
SELECT * FROM users WHERE roles && ARRAY['admin', 'superadmin'];
```

**JWT クレームへの組み込み**:
```python
# Auth Service での JWT 生成
payload = {
    "sub": str(user.id),  # UUID
    "email": user.email,
    "roles": user.roles,  # ['user', 'admin']
    "iat": datetime.utcnow(),
    "exp": datetime.utcnow() + timedelta(minutes=30)
}
```

#### created_at (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NOT NULL, DEFAULT NOW()

**説明**: アカウント作成日時

**データ例**:
```sql
-- 自動設定（デフォルト）
created_at = '2025-09-30 10:15:30'

-- タイムゾーン考慮版（推奨）
created_at TIMESTAMP WITH TIME ZONE = '2025-09-30 10:15:30+09:00'
```

**使用例**:
```sql
-- 本日登録されたユーザー
SELECT * FROM users
WHERE created_at::date = CURRENT_DATE;

-- 過去30日間の新規登録数
SELECT count(*) FROM users
WHERE created_at >= NOW() - INTERVAL '30 days';
```

#### updated_at (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NOT NULL, DEFAULT NOW()

**説明**: 最終更新日時

**自動更新**:
```python
# SQLAlchemy ORM での自動更新
from sqlalchemy import Column, DateTime, func

class User(Base):
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now()  # ← UPDATE時に自動更新
    )
```

**使用例**:
```sql
-- 最近更新されたアカウント
SELECT email, updated_at FROM users
ORDER BY updated_at DESC
LIMIT 10;
```

#### is_active (BOOLEAN)

**型**: `BOOLEAN`
**制約**: DEFAULT true

**説明**: アカウントの有効/無効状態

**状態**:
- `true`: アクティブ（ログイン可能）
- `false`: 無効化（ログイン不可）

**使用シナリオ**:
1. 管理者によるアカウント停止
2. 利用規約違反による凍結
3. 退会処理（論理削除）

**ログインチェック**:
```python
# Auth Service でのログイン処理
if not user.is_active:
    raise HTTPException(
        status_code=403,
        detail="Account is inactive"
    )
```

**論理削除**:
```sql
-- 物理削除の代わりに無効化
UPDATE users SET is_active = false WHERE id = 'user-id';

-- 無効化されたユーザーを除外
SELECT * FROM users WHERE is_active = true;
```

#### login_attempts (INTEGER)

**型**: `INTEGER`
**制約**: DEFAULT 0

**説明**: 連続ログイン失敗回数

**ブルートフォース攻撃対策**:
```python
# ログイン失敗時
user.login_attempts += 1
if user.login_attempts >= 5:
    user.locked_until = datetime.utcnow() + timedelta(minutes=30)
db.commit()

# ログイン成功時
user.login_attempts = 0
user.last_login_at = datetime.utcnow()
user.locked_until = None
db.commit()
```

**管理クエリ**:
```sql
-- ロックされたアカウント数
SELECT count(*) FROM users WHERE login_attempts >= 5;

-- ロック解除（管理者操作）
UPDATE users SET login_attempts = 0, locked_until = NULL WHERE id = 'user-id';
```

#### last_login_at (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NULL許容

**説明**: 最終ログイン日時

**初期値**: NULL（初回ログイン前）

**更新タイミング**:
```python
# ログイン成功時
user.last_login_at = datetime.utcnow()
db.commit()
```

**使用例**:
```sql
-- 90日間ログインがないユーザー（休眠アカウント）
SELECT email, last_login_at FROM users
WHERE last_login_at < NOW() - INTERVAL '90 days'
   OR last_login_at IS NULL;

-- ログイン頻度の分析
SELECT
    CASE
        WHEN last_login_at > NOW() - INTERVAL '7 days' THEN 'Active'
        WHEN last_login_at > NOW() - INTERVAL '30 days' THEN 'Inactive'
        ELSE 'Dormant'
    END AS status,
    count(*)
FROM users
GROUP BY status;
```

#### locked_until (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NULL許容

**説明**: アカウントロックの解除予定時刻

**動作**:
- `NULL`: ロックされていない
- 未来の時刻: ロック中（その時刻まで）
- 過去の時刻: ロック期間終了（ログイン可能）

**ロック処理**:
```python
# 5回失敗で30分ロック
if user.login_attempts >= 5:
    user.locked_until = datetime.utcnow() + timedelta(minutes=30)

# ロック確認
if user.locked_until and user.locked_until > datetime.utcnow():
    raise HTTPException(
        status_code=403,
        detail=f"Account locked until {user.locked_until}"
    )
```

**管理クエリ**:
```sql
-- 現在ロック中のアカウント
SELECT email, locked_until FROM users
WHERE locked_until > NOW();

-- ロック解除（時間経過）
UPDATE users SET locked_until = NULL, login_attempts = 0
WHERE locked_until <= NOW();
```

---

## インデックス設計

### 主キーインデックス（自動作成）

```sql
-- id カラムの主キー制約により自動作成
CREATE UNIQUE INDEX users_pkey ON users (id);
```

**用途**: ID による直接検索（頻度: 低）

**パフォーマンス**: O(log n)

### メールアドレスインデックス

```sql
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
```

**用途**: ログイン時のメールアドレス検索（頻度: 超高）

**クエリ例**:
```sql
SELECT * FROM users WHERE email = 'user@example.com';
```

**EXPLAIN ANALYZE**:
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user@example.com';

-- 結果:
-- Index Scan using idx_users_email on users (cost=0.15..8.17 rows=1)
-- Execution Time: 0.123 ms
```

### インデックス使用状況の確認

```sql
-- インデックスの使用回数
SELECT
    indexrelname AS index_name,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND tablename = 'users';

-- 期待される結果:
-- idx_users_email: 非常に多いスキャン回数
-- users_pkey: 中程度のスキャン回数
```

### 追加インデックスの検討

現時点では不要だが、将来的に検討すべきインデックス:

```sql
-- is_active による検索が増えた場合
CREATE INDEX idx_users_is_active ON users(is_active) WHERE is_active = true;

-- last_login_at による範囲検索が増えた場合
CREATE INDEX idx_users_last_login_at ON users(last_login_at);

-- ロールによる検索が増えた場合（GINインデックス）
CREATE INDEX idx_users_roles ON users USING gin(roles);
```

---

## 制約とルール

### 主キー制約

```sql
id uuid PRIMARY KEY DEFAULT uuid_generate_v4()
```

**保証内容**:
- ユーザーIDの一意性
- NULL不可
- 自動的にインデックス作成

### ユニーク制約

```sql
email TEXT UNIQUE NOT NULL
```

**保証内容**:
- メールアドレスの一意性（重複登録防止）
- NULL不可
- 自動的にインデックス作成

**エラー例**:
```sql
INSERT INTO users (email, password_hash) VALUES ('duplicate@example.com', 'hash');
-- ERROR: duplicate key value violates unique constraint "users_email_key"
```

### NOT NULL 制約

```sql
email TEXT NOT NULL
password_hash TEXT NOT NULL
roles TEXT[] NOT NULL
created_at TIMESTAMP NOT NULL
updated_at TIMESTAMP NOT NULL
```

**理由**:
- `email`: ログインに必須
- `password_hash`: 認証に必須
- `roles`: ロール判定に必須（空配列も不可）
- タイムスタンプ: 監査証跡として必須

### CHECK 制約（将来の拡張候補）

現在は未実装。将来的に以下を検討:

```sql
-- メールアドレス形式検証
ALTER TABLE users ADD CONSTRAINT email_format_check
  CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$');

-- ロールの値検証
ALTER TABLE users ADD CONSTRAINT roles_check
  CHECK (roles <@ ARRAY['user', 'admin', 'superadmin']::TEXT[]);

-- login_attempts の範囲検証
ALTER TABLE users ADD CONSTRAINT login_attempts_check
  CHECK (login_attempts >= 0 AND login_attempts <= 100);
```

---

## Auth Service との統合

### FastAPI + SQLAlchemy ORM

**モデル定義**:
```python
# ai-micro-api-auth/app/models/user.py
from sqlalchemy import Column, String, Boolean, Integer, DateTime, ARRAY
from sqlalchemy.dialects.postgresql import UUID
import uuid
from ..db.session import Base

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True, nullable=False, index=True)
    password_hash = Column(String, nullable=False)
    roles = Column(ARRAY(String), nullable=False, default=['user'])
    created_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=False, server_default=func.now(), onupdate=func.now())
    is_active = Column(Boolean, default=True)
    login_attempts = Column(Integer, default=0)
    last_login_at = Column(DateTime, nullable=True)
    locked_until = Column(DateTime, nullable=True)
```

### ユーザー登録フロー

```python
# POST /auth/register
@router.post("/register")
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    # メールアドレス重複チェック
    existing = db.query(User).filter(User.email == user_data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    # パスワードハッシュ化
    password_hash = pwd_context.hash(user_data.password)

    # ユーザー作成
    user = User(
        email=user_data.email,
        password_hash=password_hash,
        roles=['user']  # デフォルトロール
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return {"id": str(user.id), "email": user.email}
```

### ログインフロー

```python
# POST /auth/login
@router.post("/login")
async def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    # メールアドレスでユーザー検索
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # アカウント状態確認
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account inactive")

    # ロック確認
    if user.locked_until and user.locked_until > datetime.utcnow():
        raise HTTPException(status_code=403, detail="Account locked")

    # パスワード検証
    if not pwd_context.verify(credentials.password, user.password_hash):
        # ログイン失敗
        user.login_attempts += 1
        if user.login_attempts >= 5:
            user.locked_until = datetime.utcnow() + timedelta(minutes=30)
        db.commit()
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # ログイン成功
    user.login_attempts = 0
    user.last_login_at = datetime.utcnow()
    user.locked_until = None
    db.commit()

    # JWT トークン生成
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }
```

### JWT トークン生成

```python
def create_access_token(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "roles": user.roles,
        "iat": datetime.utcnow(),
        "exp": datetime.utcnow() + timedelta(minutes=30)
    }
    return jwt.encode(payload, private_key, algorithm="RS256")
```

---

## セキュリティ考慮事項

### パスワードハッシュ

**アルゴリズム**: bcrypt
**cost factor**: 12（2^12 = 4096回のハッシュ処理）

**セキュリティ特性**:
- レインボーテーブル攻撃耐性（ソルト自動付与）
- ブルートフォース攻撃耐性（意図的に遅い処理）
- 将来の計算能力向上に対応（cost factor 調整可能）

**パスワードポリシー**:
```python
# アプリケーション側で実装
import re

def validate_password(password: str) -> bool:
    # 最小8文字
    if len(password) < 8:
        return False

    # 大文字、小文字、数字、記号を含む
    if not re.search(r'[A-Z]', password):
        return False
    if not re.search(r'[a-z]', password):
        return False
    if not re.search(r'[0-9]', password):
        return False
    if not re.search(r'[^A-Za-z0-9]', password):
        return False

    return True
```

### ブルートフォース攻撃対策

**実装済み機能**:
1. ログイン失敗回数の記録（`login_attempts`）
2. 5回失敗で30分間ロック（`locked_until`）
3. 成功時にカウンターリセット

**追加検討事項**:
- IPアドレスベースのレート制限（Redis + Nginx）
- CAPTCHA導入（5回失敗後）
- 多要素認証（MFA）

### アカウント列挙攻撃対策

**問題**: メールアドレスの存在確認による情報漏洩

**対策**:
```python
# 存在しないメールアドレスも同じエラーメッセージ
if not user or not pwd_context.verify(password, user.password_hash):
    raise HTTPException(status_code=401, detail="Invalid credentials")
    # "Email not found" や "Wrong password" のような区別をしない
```

### SQL インジェクション対策

**SQLAlchemy ORM によるパラメータバインディング**:
```python
# 安全（自動的にパラメータバインディング）
user = db.query(User).filter(User.email == email).first()

# 危険（使用禁止）
db.execute(f"SELECT * FROM users WHERE email = '{email}'")
```

### タイミング攻撃対策

**パスワード検証の一定時間処理**:
```python
# bcrypt は自動的にタイミング攻撃耐性あり
pwd_context.verify(password, password_hash)
```

---

## パフォーマンス最適化

### クエリ最適化

**頻出クエリ**:
```sql
-- ログイン時（最も頻繁）
SELECT * FROM users WHERE email = 'user@example.com';
-- インデックス使用: idx_users_email

-- プロファイル取得時（User API から参照）
SELECT id, email, roles FROM users WHERE id = 'uuid-here';
-- インデックス使用: users_pkey
```

**スロークエリの監視**:
```sql
-- 1秒以上かかるクエリをログに記録
-- postgresql.conf
log_min_duration_statement = 1000
```

### コネクションプール

**SQLAlchemy 設定**:
```python
# ai-micro-api-auth/app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=20,          # 基本プール数
    max_overflow=10,       # 追加接続数
    pool_pre_ping=True,    # 接続確認
    pool_recycle=3600      # 1時間でリサイクル
)
```

### キャッシュ戦略

**Redis によるユーザー情報キャッシュ**:
```python
# ユーザー情報をRedisにキャッシュ（TTL: 5分）
async def get_user_cached(user_id: str, db: Session) -> User:
    cache_key = f"user:{user_id}"
    cached = await redis.get(cache_key)

    if cached:
        return User(**json.loads(cached))

    user = db.query(User).filter(User.id == user_id).first()
    if user:
        await redis.setex(cache_key, 300, json.dumps(user.dict()))

    return user
```

---

## トラブルシューティング

### ログイン失敗の原因調査

```sql
-- ロックされたアカウント
SELECT email, login_attempts, locked_until FROM users
WHERE locked_until > NOW();

-- 無効化されたアカウント
SELECT email, is_active, updated_at FROM users
WHERE is_active = false;

-- パスワードハッシュの確認（管理者のみ）
SELECT email, substring(password_hash, 1, 20) || '...' AS hash_preview
FROM users WHERE email = 'user@example.com';
```

### メールアドレス重複エラー

```sql
-- 既存アカウントの確認
SELECT id, email, created_at FROM users WHERE email = 'user@example.com';

-- 重複削除（古いアカウントを削除）
DELETE FROM users WHERE email = 'user@example.com' AND created_at < '2025-01-01';
```

### パフォーマンス問題

```sql
-- テーブルサイズ確認
SELECT pg_size_pretty(pg_total_relation_size('users')) AS size;

-- インデックスサイズ確認
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE tablename = 'users';

-- VACUUM とANALYZE
VACUUM ANALYZE users;
```

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [apidb スキーマ](./05-apidb-schema.md) - profiles.user_id との連携
- [admindb スキーマ](./06-admindb-schema.md) - login_logs.user_id との連携
- [データベース間連携](./08-cross-database-relations.md)
- [Auth Service 概要](/01-auth-service/01-overview.md)
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)

---

**次のステップ**: [apidb スキーマ詳細](./05-apidb-schema.md) を参照して、ユーザープロファイル管理の実装を確認してください。