# apidb - ユーザープロファイルデータベーススキーマ詳細

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [データベース概要](#データベース概要)
- [profilesテーブル](#profilesテーブル)
- [インデックス設計](#インデックス設計)
- [制約とルール](#制約とルール)
- [User API Service との統合](#user-api-service-との統合)
- [authdb との連携](#authdb-との連携)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## データベース概要

### 基本情報

| 項目 | 値 |
|-----|-----|
| データベース名 | `apidb` |
| 使用サービス | ai-micro-api-user (Port 8001) |
| 責務 | ユーザープロファイル情報の管理 |
| 接続URL | `postgresql://postgres:password@host.docker.internal:5432/apidb` |

### テーブル一覧

| テーブル名 | 説明 | レコード例 |
|---------|------|---------|
| `profiles` | ユーザープロファイル | ユーザー数に比例（小〜中規模） |

### 拡張機能

```sql
-- UUID生成機能
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

## profilesテーブル

### テーブル概要

**目的**: ユーザーの個人情報とプロファイルデータの管理

**主要機能**:
- ユーザーの基本情報（名前、住所、電話番号）
- authdb.users との論理的な連携
- プロファイルの作成・更新・取得

### テーブル構造

```sql
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL,
  name TEXT,
  address TEXT,
  phone TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  first_name TEXT,
  last_name TEXT
);
```

### カラム詳細

#### id (UUID)

**型**: `uuid`
**制約**: PRIMARY KEY, DEFAULT uuid_generate_v4()

**説明**: プロファイルの一意識別子

**生成方法**:
```sql
-- 自動生成（デフォルト）
INSERT INTO profiles (user_id, name) VALUES ('user-uuid', 'John Doe');
-- id は自動的に UUID が生成される
```

**使用シーン**:
- プロファイルの直接参照（稀）
- 通常は user_id で検索

#### user_id (UUID)

**型**: `uuid`
**制約**: UNIQUE, NOT NULL

**説明**: authdb.users.id との論理的な外部キー

**重要な特徴**:
- 物理的な外部キー制約は設定しない（マイクロサービス独立性）
- 1ユーザーにつき1プロファイル（UNIQUE制約）
- authdb.users.id と同じ UUID 値

**データ整合性の保証方法**:
```python
# JWT トークンから user_id 取得
user_id = get_current_user_id(token)  # authdb で認証済み

# プロファイル作成（存在しないユーザーは JWT 検証で弾かれる）
profile = Profile(user_id=user_id, name="John Doe")
db.add(profile)
db.commit()
```

**連携図**:
```
authdb.users                    apidb.profiles
┌─────────────────┐            ┌─────────────────┐
│ id (UUID, PK)   │────論理────│ user_id (UUID)  │
│ email           │            │ name            │
│ password_hash   │            │ address         │
└─────────────────┘            └─────────────────┘
```

**重複登録の防止**:
```sql
-- 同じユーザーで複数プロファイル作成は不可
INSERT INTO profiles (user_id, name) VALUES ('same-uuid', 'Profile 1');
-- OK

INSERT INTO profiles (user_id, name) VALUES ('same-uuid', 'Profile 2');
-- ERROR: duplicate key value violates unique constraint "profiles_user_id_key"
```

#### name (TEXT)

**型**: `TEXT`
**制約**: NULL許容

**説明**: ユーザーのフルネーム

**データ例**:
```sql
name = '山田 太郎'
name = 'John Doe'
name = '佐藤 花子'
name = NULL  -- 未設定も許容
```

**使用シーン**:
- ユーザー表示名
- 挨拶メッセージ（"こんにちは、山田 太郎さん"）

#### first_name (TEXT)

**型**: `TEXT`
**制約**: NULL許容

**説明**: 名前（下の名前）

**データ例**:
```sql
first_name = '太郎'
first_name = 'John'
first_name = NULL
```

**name との使い分け**:
- `name`: フルネームを一括管理（日本語名に適している）
- `first_name` + `last_name`: 分割管理（英語名に適している）

#### last_name (TEXT)

**型**: `TEXT`
**制約**: NULL許容

**説明**: 姓（名字）

**データ例**:
```sql
last_name = '山田'
last_name = 'Doe'
last_name = NULL
```

**フルネームの構築**:
```sql
-- 日本語名
SELECT last_name || ' ' || first_name AS full_name FROM profiles;
-- => '山田 太郎'

-- 英語名
SELECT first_name || ' ' || last_name AS full_name FROM profiles;
-- => 'John Doe'
```

#### address (TEXT)

**型**: `TEXT`
**制約**: NULL許容

**説明**: 住所

**データ例**:
```sql
address = '東京都渋谷区1-2-3'
address = '123 Main St, San Francisco, CA 94102, USA'
address = NULL
```

**使用シーン**:
- 配送先住所
- 請求先住所
- 地域分析

**プライバシー考慮**:
- 機密情報として扱う
- GDPR 対応（削除リクエスト対応）

#### phone (TEXT)

**型**: `TEXT`
**制約**: NULL許容

**説明**: 電話番号

**データ例**:
```sql
phone = '090-1234-5678'
phone = '+81-90-1234-5678'
phone = '03-1234-5678'
phone = NULL
```

**バリデーション**（アプリケーション側）:
```python
import re

def validate_phone(phone: str) -> bool:
    # 日本の電話番号形式
    pattern = r'^(\d{2,4}-\d{2,4}-\d{4}|0\d{9,10})$'
    return bool(re.match(pattern, phone))
```

**使用シーン**:
- 連絡先
- 二要素認証（SMS）
- 緊急連絡先

#### created_at (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NOT NULL, DEFAULT NOW()

**説明**: プロファイル作成日時

**自動設定**: レコード挿入時に自動的に現在時刻が設定

**使用例**:
```sql
-- 最近作成されたプロファイル
SELECT user_id, name, created_at FROM profiles
ORDER BY created_at DESC
LIMIT 10;
```

#### updated_at (TIMESTAMP)

**型**: `TIMESTAMP`
**制約**: NOT NULL, DEFAULT NOW()

**説明**: プロファイル最終更新日時

**自動更新**: レコード更新時に自動的に現在時刻が設定

**SQLAlchemy での実装**:
```python
from sqlalchemy import Column, DateTime, func

class Profile(Base):
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now()  # ← UPDATE時に自動更新
    )
```

---

## インデックス設計

### 主キーインデックス（自動作成）

```sql
-- id カラムの主キー制約により自動作成
CREATE UNIQUE INDEX profiles_pkey ON profiles (id);
```

**用途**: ID による直接検索（頻度: 低）

### user_id インデックス

```sql
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);
```

**用途**: ユーザーIDによるプロファイル検索（頻度: 超高）

**最頻出クエリ**:
```sql
SELECT * FROM profiles WHERE user_id = 'user-uuid';
```

**パフォーマンス**:
```sql
EXPLAIN ANALYZE SELECT * FROM profiles WHERE user_id = 'user-uuid';

-- 結果:
-- Index Scan using idx_profiles_user_id on profiles (cost=0.15..8.17 rows=1)
-- Execution Time: 0.089 ms
```

**UNIQUE 制約による自動インデックス**:
```sql
-- user_id は UNIQUE 制約があるため、自動的にインデックス作成
-- idx_profiles_user_id と重複するが、UNIQUE制約用として別に作成される
```

### インデックス使用状況の確認

```sql
SELECT
    indexrelname AS index_name,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND tablename = 'profiles';
```

---

## 制約とルール

### 主キー制約

```sql
id uuid PRIMARY KEY DEFAULT uuid_generate_v4()
```

**保証内容**:
- プロファイルIDの一意性
- NULL不可

### ユニーク制約

```sql
user_id uuid UNIQUE NOT NULL
```

**保証内容**:
- 1ユーザーにつき1プロファイル
- 重複登録防止

**ビジネスルール**:
- 新規ユーザーは初回ログイン時にプロファイル作成
- プロファイル削除はアカウント削除時のみ

### NOT NULL 制約

```sql
user_id uuid NOT NULL
created_at TIMESTAMP NOT NULL
updated_at TIMESTAMP NOT NULL
```

**理由**:
- `user_id`: プロファイルは必ずユーザーに紐付く
- タイムスタンプ: 監査証跡として必須

### NULL 許容カラム

```sql
name TEXT
first_name TEXT
last_name TEXT
address TEXT
phone TEXT
```

**理由**: すべてオプション項目（ユーザーが入力しない場合もある）

---

## User API Service との統合

### FastAPI + SQLAlchemy ORM

**モデル定義**:
```python
# ai-micro-api-user/app/models/profile.py
from sqlalchemy import Column, String, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
import uuid
from ..db.session import Base

class Profile(Base):
    __tablename__ = "profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), unique=True, nullable=False, index=True)
    name = Column(String, nullable=True)
    first_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    address = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

### プロファイル取得

```python
# GET /profile
@router.get("/profile")
async def get_profile(
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = current_user["sub"]  # JWT の sub クレームから取得

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    return profile
```

### プロファイル作成・更新（Upsert）

```python
# POST /profile
@router.post("/profile")
async def create_or_update_profile(
    profile_data: ProfileUpdate,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = current_user["sub"]

    # 既存プロファイル確認
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    if profile:
        # 更新
        for key, value in profile_data.dict(exclude_unset=True).items():
            setattr(profile, key, value)
    else:
        # 新規作成
        profile = Profile(user_id=user_id, **profile_data.dict(exclude_unset=True))
        db.add(profile)

    db.commit()
    db.refresh(profile)

    return profile
```

### Redis キャッシュ統合

```python
# キャッシュ付きプロファイル取得
async def get_profile_cached(user_id: str, db: Session) -> Profile:
    cache_key = f"profile:{user_id}"

    # Redis から取得
    cached = await redis.get(cache_key)
    if cached:
        return Profile(**json.loads(cached))

    # DB から取得
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    if profile:
        # Redis に保存（TTL: 5分）
        await redis.setex(cache_key, 300, json.dumps(profile.dict()))

    return profile
```

---

## authdb との連携

### データ連携フロー

```
1. ユーザー登録（Auth Service）
   └─> authdb.users にレコード作成
       └─> id = '123e4567-e89b-12d3-a456-426614174000'

2. 初回ログイン後（User Frontend）
   └─> User API にプロファイル作成リクエスト
       └─> JWT の sub クレームから user_id 取得
           └─> apidb.profiles にレコード作成
               └─> user_id = '123e4567-e89b-12d3-a456-426614174000'
```

### JWT トークンを介した連携

```python
# JWT トークン例
{
  "sub": "123e4567-e89b-12d3-a456-426614174000",  # authdb.users.id
  "email": "user@example.com",
  "roles": ["user"],
  "iat": 1696000000,
  "exp": 1696001800
}

# User API でのトークン検証
user_id = jwt_payload["sub"]  # => authdb.users.id
profile = db.query(Profile).filter(Profile.user_id == user_id).first()
```

### データ整合性の保証

**物理的な外部キー制約は設定しない理由**:
1. データベース分離（マイクロサービス独立性）
2. Auth Service 障害時も User API は既存データにアクセス可能
3. 将来的な物理分離（別 PostgreSQL インスタンス）への移行が容易

**整合性保証の仕組み**:
1. JWT トークンで認証済みユーザーのみアクセス可能
2. 存在しないユーザーのプロファイル作成は JWT 検証で防止
3. アプリケーションレベルでの整合性チェック

**孤児レコードの検出**（運用監視）:
```sql
-- authdb と apidb を結合して確認（管理ツール用）
-- 実運用では両方のDBに接続して比較

-- apidb 側で孤児レコード検出
SELECT user_id, name FROM profiles
WHERE user_id NOT IN (
    SELECT id FROM authdb.users  -- 実際は別クエリで取得したリスト
);
```

---

## パフォーマンス最適化

### クエリ最適化

**最頻出クエリ**:
```sql
-- プロファイル取得（全リクエストで実行）
SELECT * FROM profiles WHERE user_id = 'user-uuid';

-- インデックス使用確認
EXPLAIN ANALYZE SELECT * FROM profiles WHERE user_id = 'user-uuid';
-- Index Scan using idx_profiles_user_id
```

### Redis キャッシュ戦略

**キャッシュ対象**:
- プロファイル情報（変更頻度: 低）
- TTL: 5分

**キャッシュ無効化タイミング**:
```python
# プロファイル更新時にキャッシュ削除
@router.put("/profile")
async def update_profile(profile_data: ProfileUpdate, user_id: str):
    # DB更新
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    # ... 更新処理 ...
    db.commit()

    # Redis キャッシュ削除
    cache_key = f"profile:{user_id}"
    await redis.delete(cache_key)

    return profile
```

### コネクションプール

```python
# ai-micro-api-user/app/db/session.py
engine = create_engine(
    settings.database_url,
    pool_size=15,          # Auth より少なめ（負荷が低い）
    max_overflow=5,
    pool_pre_ping=True,
    pool_recycle=3600
)
```

### VACUUM と ANALYZE

```sql
-- 定期メンテナンス
VACUUM ANALYZE profiles;

-- 統計情報の更新
ANALYZE profiles;
```

---

## トラブルシューティング

### プロファイルが見つからない

```sql
-- ユーザーIDの確認
SELECT * FROM profiles WHERE user_id = 'user-uuid';

-- 全プロファイル確認
SELECT user_id, name, created_at FROM profiles ORDER BY created_at DESC LIMIT 10;
```

**原因と対策**:
1. プロファイル未作成 → 初回作成エンドポイントを呼び出す
2. user_id の不一致 → JWT トークンの sub クレーム確認

### user_id 重複エラー

```sql
-- ERROR: duplicate key value violates unique constraint "profiles_user_id_key"

-- 既存プロファイル確認
SELECT * FROM profiles WHERE user_id = 'user-uuid';

-- 対策: Upsert パターンの実装（作成・更新の統合）
```

### パフォーマンス問題

```sql
-- テーブルサイズ確認
SELECT pg_size_pretty(pg_total_relation_size('profiles')) AS size;

-- インデックス使用状況
SELECT * FROM pg_stat_user_indexes WHERE tablename = 'profiles';

-- スロークエリの検出
-- postgresql.conf: log_min_duration_statement = 1000
```

---

## データマイグレーション例

### カラム追加

```sql
-- プロフィール画像URL追加
ALTER TABLE profiles ADD COLUMN profile_image_url TEXT;

-- デフォルト値設定（既存レコード用）
UPDATE profiles SET profile_image_url = 'https://example.com/default.png'
WHERE profile_image_url IS NULL;
```

### データ型変更

```sql
-- phone カラムに VARCHAR(20) の長さ制限を追加
ALTER TABLE profiles ALTER COLUMN phone TYPE VARCHAR(20);

-- 既存データの検証
SELECT phone FROM profiles WHERE length(phone) > 20;
```

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [スキーマ設計概要](./03-schema-design-overview.md)
- [authdb スキーマ](./04-authdb-schema.md) - users.id との連携
- [データベース間連携](./08-cross-database-relations.md)
- [User API Service 概要](/02-user-api/01-overview.md)
- [User API データベース設計](/02-user-api/03-database-design.md)

---

**次のステップ**: [admindb スキーマ詳細](./06-admindb-schema.md) を参照して、管理機能とRAGシステムのデータベース設計を確認してください。