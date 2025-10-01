# データ保護

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [保管データの暗号化](#保管データの暗号化)
- [転送データの暗号化](#転送データの暗号化)
- [機密データハンドリング](#機密データハンドリング)
- [データベースセキュリティ](#データベースセキュリティ)
- [Redis認証](#redis認証)
- [データマスキング](#データマスキング)

---

## 概要

### データ保護の重要性

ai-micro-service システムは、以下の機密情報を扱います:

1. **認証情報**: パスワードハッシュ、JWTトークン
2. **個人情報（PII）**: メールアドレス、氏名、住所、電話番号
3. **セッション情報**: アクティブセッション、ログイン履歴
4. **ドキュメント**: ユーザーがアップロードしたファイル
5. **システム設定**: 認証情報、APIキー

これらのデータは、保管時（at rest）と転送時（in transit）の両方で適切に保護される必要があります。

### データ分類

```
┌─────────────────────────────────────────────────────────┐
│  データ分類                                               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  機密度: 高                                              │
│  ├─ パスワードハッシュ                                   │
│  ├─ JWTトークン                                         │
│  ├─ セッション情報                                       │
│  └─ APIキー・シークレット                                │
│                                                         │
│  機密度: 中                                              │
│  ├─ メールアドレス                                       │
│  ├─ 氏名                                                │
│  ├─ 住所                                                │
│  ├─ 電話番号                                             │
│  └─ ユーザーID（UUID）                                   │
│                                                         │
│  機密度: 低                                              │
│  ├─ ログイン時刻                                         │
│  ├─ 作成日時                                             │
│  └─ システムログ                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 保管データの暗号化

### パスワードハッシング

**アルゴリズム**: bcrypt（cost factor: 10）

**実装**:
```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def create_password_hash(password: str) -> str:
    """Create password hash using bcrypt"""
    return pwd_context.hash(password)
```

**特徴**:
- ✅ ソルト自動生成（レインボーテーブル攻撃耐性）
- ✅ スローハッシュ（ブルートフォース攻撃耐性）
- ✅ 調整可能なコスト（将来の計算能力向上に対応）
- ✅ 平文パスワードは保存しない

**ハッシュ例**:
```
平文: MySecureP@ssw0rd
ハッシュ: $2b$10$N9qo8uLOickgx2ZMRZoMye.IjxPq/YVN9l2hKjqHbW8K5VR1Gs9jO
```

### データベース暗号化（推奨）

**PostgreSQL TDE（Transparent Data Encryption）**:

本番環境では、データベースレベルでの暗号化を推奨します。

**オプション**:
1. **PostgreSQL pgcrypto 拡張**:
   ```sql
   CREATE EXTENSION pgcrypto;

   -- 暗号化カラム
   ALTER TABLE profiles ADD COLUMN address_encrypted BYTEA;

   -- 暗号化挿入
   INSERT INTO profiles (address_encrypted)
   VALUES (pgp_sym_encrypt('123 Main St', 'encryption_key'));

   -- 復号化取得
   SELECT pgp_sym_decrypt(address_encrypted, 'encryption_key') FROM profiles;
   ```

2. **ファイルシステムレベル暗号化**:
   - LUKS（Linux）
   - dm-crypt
   - AWS EBS暗号化

3. **クラウドプロバイダー管理暗号化**:
   - AWS RDS 暗号化
   - Azure SQL Database TDE
   - Google Cloud SQL 暗号化

### Redisデータ保護

**保存データ**:
- セッション情報（TTL: 30日）
- トークンブラックリスト（TTL: 各トークン有効期限）
- レート制限カウンター（TTL: 1分〜1時間）

**セキュリティ対策**:
- ✅ パスワード認証（`requirepass`）
- ⚠️ TLS接続（推奨、未実装）
- ⚠️ Redis暗号化（推奨、未実装）

**Redis設定**:
```conf
# redis.conf
requirepass your-strong-redis-password
```

---

## 転送データの暗号化

### HTTPS/TLS

**本番環境要件**: 必須

**設定例（Nginx）**:
```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/ssl/certs/example.com.crt;
    ssl_certificate_key /etc/ssl/private/example.com.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://localhost:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**証明書取得**:
- Let's Encrypt（無料、自動更新）
- AWS Certificate Manager
- 商用証明書（DigiCert, GlobalSign等）

### データベース接続暗号化

**PostgreSQL SSL接続**:

```python
# database_url with SSL
DATABASE_URL = "postgresql://user:password@host:5432/dbname?sslmode=require"
```

**SSL モード**:
- `disable`: SSL無効（開発環境のみ）
- `require`: SSL必須（証明書検証なし）
- `verify-ca`: CA証明書検証
- `verify-full`: CA証明書 + ホスト名検証（推奨）

**設定例**:
```python
from sqlalchemy import create_engine

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={
        "sslmode": "verify-full",
        "sslrootcert": "/path/to/ca-cert.pem"
    }
)
```

### Redis接続暗号化

**Redis TLS設定**:

```python
# redis_url with TLS
REDIS_URL = "rediss://:<password>@host:6380"  # rediss:// = TLS
```

**Redis設定**:
```conf
# redis.conf
port 0
tls-port 6380
tls-cert-file /path/to/redis.crt
tls-key-file /path/to/redis.key
tls-ca-cert-file /path/to/ca.crt
```

---

## 機密データハンドリング

### 環境変数管理

**原則**:
- ❌ ハードコードされた認証情報
- ❌ Git リポジトリに `.env` をコミット
- ✅ 環境変数で管理
- ✅ シークレット管理サービス利用（本番環境）

**開発環境**:
```bash
# .env
DATABASE_URL=postgresql://postgres:devpassword@localhost:5432/authdb
REDIS_URL=redis://:devpassword@localhost:6379
JWT_SECRET=dev-secret-key-change-in-production
```

**本番環境（推奨）**:
- AWS Secrets Manager
- HashiCorp Vault
- Azure Key Vault
- Google Cloud Secret Manager

**AWS Secrets Manager 例**:
```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager', region_name='us-east-1')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# 使用例
secrets = get_secret('prod/database/credentials')
DATABASE_URL = secrets['DATABASE_URL']
```

### ログ記録の注意

**禁止事項**:
- ❌ パスワード平文のログ記録
- ❌ JWTトークン全体のログ記録
- ❌ クレジットカード番号
- ❌ 個人情報の詳細

**推奨**:
```python
import logging

logger = logging.getLogger(__name__)

# ❌ ダメな例
logger.info(f"User logged in with password: {password}")

# ✅ 良い例
logger.info(f"User logged in: {user_id}")

# ❌ ダメな例
logger.debug(f"JWT token: {token}")

# ✅ 良い例
logger.debug(f"JWT token issued for user: {user_id}, jti: {jti[:8]}...")
```

### エラーメッセージ

**原則**: 詳細な内部情報を外部に漏らさない

**ダメな例**:
```python
# ❌ データベース詳細を露出
raise HTTPException(
    status_code=500,
    detail="Database error: psycopg2.OperationalError: FATAL: password authentication failed for user 'postgres'"
)
```

**良い例**:
```python
# ✅ 一般的なエラーメッセージ
logger.error(f"Database connection failed: {str(e)}")  # 内部ログ
raise HTTPException(
    status_code=500,
    detail="Internal server error"  # 外部メッセージ
)
```

---

## データベースセキュリティ

### 接続プール設定

**SQLAlchemy設定**:

```python
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=20,              # 基本プールサイズ
    max_overflow=10,           # 追加接続数
    pool_pre_ping=True,        # 接続確認
    pool_recycle=3600,         # 1時間でリサイクル
    echo=False,                # SQL ログ（本番環境では False）
    connect_args={
        "command_timeout": 60,  # コマンドタイムアウト
        "server_settings": {
            "application_name": "auth-service"
        }
    }
)
```

### SQLインジェクション対策

**原則**: ORM使用 & パラメータ化クエリ

**ダメな例**:
```python
# ❌ SQLインジェクション脆弱性
email = request.email
query = f"SELECT * FROM users WHERE email = '{email}'"
result = await db.execute(query)
```

**良い例**:
```python
# ✅ ORM使用
from sqlalchemy import select
result = await db.execute(
    select(User).where(User.email == request.email)
)

# ✅ パラメータ化クエリ
from sqlalchemy import text
result = await db.execute(
    text("SELECT * FROM users WHERE email = :email"),
    {"email": request.email}
)
```

### データベースユーザー権限

**原則**: 最小権限の原則

**推奨設定**:
```sql
-- Auth Service 専用ユーザー
CREATE ROLE auth_service WITH LOGIN PASSWORD 'secure-password';

-- authdb へのアクセス権限
GRANT CONNECT ON DATABASE authdb TO auth_service;

-- users テーブルへの権限（SELECT, INSERT, UPDATE のみ）
GRANT SELECT, INSERT, UPDATE ON TABLE users TO auth_service;

-- DELETE 権限は付与しない（論理削除を推奨）
REVOKE DELETE ON TABLE users FROM auth_service;
```

### バックアップと暗号化

**バックアップ戦略**:
```bash
# 暗号化バックアップ
pg_dump -U postgres authdb | \
  gpg --symmetric --cipher-algo AES256 -o authdb_backup_$(date +%Y%m%d).sql.gpg

# 復号化とリストア
gpg --decrypt authdb_backup_20250930.sql.gpg | \
  psql -U postgres authdb
```

---

## Redis認証

### パスワード認証

**Redis設定**:
```conf
# redis.conf
requirepass your-strong-redis-password-here
```

**接続URL**:
```bash
REDIS_URL=redis://:your-strong-redis-password-here@host.docker.internal:6379
```

**Python接続**:
```python
import redis.asyncio as redis

redis_client = await redis.from_url(
    settings.REDIS_URL,
    decode_responses=True,
    encoding="utf-8"
)
```

### Redis ACL（Access Control List）

**Redis 6.0+ 推奨**:

```bash
# ACL設定
ACL SETUSER auth_service on >strong-password ~session:* ~blacklist:* +get +set +del +expire

# 確認
ACL LIST
```

**接続URL**:
```bash
REDIS_URL=redis://auth_service:strong-password@host:6379
```

### Redis設定のベストプラクティス

```conf
# redis.conf

# パスワード認証
requirepass your-strong-password

# 保護モード有効
protected-mode yes

# バインドアドレス制限
bind 127.0.0.1 ::1

# 危険なコマンド無効化
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command KEYS ""
rename-command CONFIG ""

# 永続化設定
save 900 1
save 300 10
save 60 10000

# AOF有効化
appendonly yes
```

---

## データマスキング

### ログ出力時のマスキング

**実装例**:
```python
import re

def mask_sensitive_data(data: str) -> str:
    """Mask sensitive data in logs"""
    # メールアドレスマスキング
    data = re.sub(
        r'([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
        r'\1***@***.\2',
        data
    )

    # クレジットカード番号マスキング
    data = re.sub(
        r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b',
        '****-****-****-****',
        data
    )

    # パスワードフィールドマスキング
    data = re.sub(
        r'"password"\s*:\s*"[^"]*"',
        '"password": "********"',
        data
    )

    return data

# 使用例
logger.info(mask_sensitive_data(f"Request: {json.dumps(request_data)}"))
```

### APIレスポンスのマスキング

**実装例**:
```python
from pydantic import BaseModel

class UserResponse(BaseModel):
    user_id: str
    email: str
    # password_hash は含めない
    roles: List[str]
    created_at: datetime

    class Config:
        # パスワードハッシュを除外
        exclude = {"password_hash"}
```

### データベースクエリ結果のマスキング

**管理画面での表示**:
```python
def mask_email(email: str) -> str:
    """Mask email for display"""
    local, domain = email.split('@')
    if len(local) <= 2:
        return f"{'*' * len(local)}@{domain}"
    return f"{local[0]}{'*' * (len(local) - 2)}{local[-1]}@{domain}"

# 例: john.doe@example.com → j******e@example.com
```

---

## データ削除とプライバシー

### 論理削除vs物理削除

**論理削除（推奨）**:
```sql
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;
ALTER TABLE users ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;

-- 削除
UPDATE users SET deleted_at = NOW(), is_deleted = TRUE WHERE id = '...';

-- クエリ時に除外
SELECT * FROM users WHERE is_deleted = FALSE;
```

**物理削除（GDPR削除権対応）**:
```sql
-- 完全削除
DELETE FROM users WHERE id = '...';
```

### GDPR削除権対応

**実装例**:
```python
@router.delete("/users/me")
async def delete_my_account(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete user account (GDPR right to erasure)"""
    user_id = current_user["sub"]

    # 1. プロファイル削除
    await db.execute(delete(Profile).where(Profile.user_id == user_id))

    # 2. ドキュメント削除
    await db.execute(delete(Document).where(Document.user_id == user_id))

    # 3. ユーザー削除
    await db.execute(delete(User).where(User.id == user_id))

    # 4. Redis セッション削除
    await redis.delete(f"session:{user_id}:*")

    await db.commit()

    return {"message": "Account deleted successfully"}
```

---

## セキュリティチェックリスト

### 開発環境

- [ ] `.env` ファイルを `.gitignore` に追加
- [ ] パスワードをハッシュ化して保存
- [ ] SQLインジェクション対策（ORM使用）
- [ ] ログに機密情報を含めない

### 本番環境

- [ ] HTTPS/TLS 有効化
- [ ] データベースSSL接続
- [ ] Redis TLS接続
- [ ] シークレット管理サービス使用
- [ ] データベース暗号化（TDE）
- [ ] 定期バックアップ（暗号化）
- [ ] 監査ログ有効化

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [05-network-security.md](./05-network-security.md) - ネットワークセキュリティ
- [07-password-policy.md](./07-password-policy.md) - パスワードポリシー

### インフラ関連
- [PostgreSQL Overview](/06-database/01-overview.md)
- [Redis Overview](/07-redis/01-overview.md)

---

**次のステップ**: [05-network-security.md](./05-network-security.md) を参照して、ネットワークレベルのセキュリティを確認してください。