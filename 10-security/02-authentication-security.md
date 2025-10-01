# 認証セキュリティ

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [RS256 JWT実装](#rs256-jwt実装)
- [JWKS公開鍵配布](#jwks公開鍵配布)
- [パスワードハッシング](#パスワードハッシング)
- [ブルートフォース攻撃保護](#ブルートフォース攻撃保護)
- [トークンライフサイクル管理](#トークンライフサイクル管理)
- [セキュリティベストプラクティス](#セキュリティベストプラクティス)

---

## 概要

### 認証アーキテクチャ

ai-micro-service システムは、JWT（JSON Web Token）ベースの認証を採用しています。Auth Service が中央認証局として機能し、すべてのサービスが JWT を検証してユーザーを認証します。

### 認証フロー

```
┌─────────┐                ┌─────────┐               ┌──────────┐
│ User    │                │   BFF   │               │   Auth   │
│ Browser │                │ (Next.js│               │  Service │
└────┬────┘                └────┬────┘               └────┬─────┘
     │                          │                         │
     │  1. POST /api/login      │                         │
     │  {email, password}       │                         │
     ├─────────────────────────→│                         │
     │                          │  2. POST /auth/login    │
     │                          │  {email, password}      │
     │                          ├────────────────────────→│
     │                          │                         │
     │                          │  3. Password Verify     │
     │                          │     (bcrypt)            │
     │                          │  4. JWT Generate        │
     │                          │     (RS256 Sign)        │
     │                          │                         │
     │                          │  5. {access_token,      │
     │                          │      refresh_token}     │
     │                          │←────────────────────────┤
     │                          │                         │
     │  6. Set-Cookie:          │  7. Save Session        │
     │     token=xxx; HttpOnly  │     to Redis            │
     │←─────────────────────────┤                         │
     │                          │                         │
     │  8. Subsequent Request   │                         │
     │     Cookie: token=xxx    │                         │
     ├─────────────────────────→│  9. JWT Validation      │
     │                          │    (JWKS Public Key)    │
     │                          │                         │
     │ 10. Protected Resource   │                         │
     │←─────────────────────────┤                         │
     │                          │                         │
```

---

## RS256 JWT実装

### RS256 アルゴリズム

**RS256** = RSA Signature with SHA-256

**特徴**:
- **非対称鍵暗号**: 秘密鍵で署名、公開鍵で検証
- **鍵の分離**: Auth Service のみが秘密鍵を保持
- **検証の分散**: すべてのサービスが公開鍵で独立に検証可能
- **改ざん検出**: 署名により JWT の改ざんを検出

### 鍵ペア生成

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/security.py`

```python
def generate_key_pair() -> tuple[str, str]:
    """Generate RSA key pair"""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )

    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption()
    )

    public_key = private_key.public_key()
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )

    return private_pem.decode(), public_pem.decode()
```

**鍵サイズ**: 2048ビット（推奨: 本番環境では4096ビット）

**保存場所**:
- 秘密鍵: `ai-micro-api-auth/keys/private.pem`
- 公開鍵: `ai-micro-api-auth/keys/public.pem`

### JWT 生成

**アクセストークン生成**:

```python
def create_access_token(
    user_id: str,
    roles: List[str] = None,
    scope: str = "access"
) -> tuple[str, str]:
    """Create access token with JTI"""
    if roles is None:
        roles = ["user"]

    jti = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    payload = {
        "sub": user_id,              # Subject: ユーザーID
        "iss": settings.JWT_ISS,     # Issuer: 発行者
        "aud": settings.JWT_AUD,     # Audience: 対象者
        "iat": now,                  # Issued At: 発行時刻
        "exp": now + timedelta(seconds=settings.ACCESS_TOKEN_TTL_SEC),
        "jti": jti,                  # JWT ID: トークン識別子
        "scope": scope,              # スコープ: access
        "roles": roles               # ロール: user, admin, super_admin
    }

    headers = {
        "kid": "key-1"  # Key ID for JWKS
    }

    private_key = load_private_key()
    token = jwt.encode(payload, private_key, algorithm=settings.JWT_ALGORITHM, headers=headers)

    return token, jti
```

**トークン例**:
```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0xIn0.
eyJzdWIiOiI1NTBlODQwMC1lMjliLTQxZDQtYTcxNi00NDY2NTU0NDAwMDAiLCJpc3MiOiJodHRwczovL2F1dGguZXhhbXBsZS5jb20iLCJhdWQiOiJmYXN0YXBpLWFwaSIsImlhdCI6MTcyNzY1NDQwMCwiZXhwIjoxNzI3NjU1MzAwLCJqdGkiOiJhYmMxMjM0NS02Nzg5LTEyMzQtNTY3OC0xMjM0NTY3ODkwYWIiLCJzY29wZSI6ImFjY2VzcyIsInJvbGVzIjpbInVzZXIiXX0.
<signature>
```

### JWT クレーム詳細

| クレーム | 型 | 必須 | 説明 |
|---------|---|------|------|
| `sub` | string (UUID) | ✅ | ユーザーID（Subject） |
| `iss` | string (URL) | ✅ | 発行者（https://auth.example.com） |
| `aud` | string | ✅ | 対象者（fastapi-api） |
| `iat` | number (timestamp) | ✅ | 発行時刻（Issued At） |
| `exp` | number (timestamp) | ✅ | 有効期限（Expiration） |
| `jti` | string (UUID) | ✅ | JWT ID（トークン識別子） |
| `scope` | string | ✅ | スコープ（access / refresh） |
| `roles` | array of strings | ✅ | ロール（user, admin, super_admin） |
| `session_id` | string (UUID) | refresh のみ | セッションID |

### JWT 検証

**検証プロセス**:

```python
def decode_token(token: str) -> Dict[str, Any]:
    """Decode and validate JWT token"""
    public_key = load_public_key()

    try:
        payload = jwt.decode(
            token,
            public_key,
            algorithms=[settings.JWT_ALGORITHM],  # RS256
            issuer=settings.JWT_ISS,              # 発行者検証
            audience=settings.JWT_AUD             # 対象者検証
        )
        return payload
    except JWTError:
        raise ValueError("Invalid token")
```

**検証項目**:
1. ✅ 署名検証（RS256 公開鍵）
2. ✅ 発行者検証（`iss` クレーム）
3. ✅ 対象者検証（`aud` クレーム）
4. ✅ 有効期限検証（`exp` クレーム）
5. ✅ ブラックリスト確認（Redis）

---

## JWKS公開鍵配布

### JWKS（JSON Web Key Set）

**エンドポイント**: `GET /.well-known/jwks.json`

**目的**: 公開鍵を標準化されたフォーマットで配布

**JWKS レスポンス例**:

```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "kid": "key-1",
      "alg": "RS256",
      "n": "xGOr-H7A...(公開鍵のmodulus、base64url)",
      "e": "AQAB"
    }
  ]
}
```

### JWKS 実装

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/security.py`

```python
def get_jwks() -> Dict[str, Any]:
    """Generate JWKS for public key distribution"""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.backends import default_backend
    import base64

    public_key_str = load_public_key()
    public_key = serialization.load_pem_public_key(
        public_key_str.encode(),
        backend=default_backend()
    )

    # Get public key numbers for JWKS
    public_numbers = public_key.public_numbers()

    # Convert to base64url encoding
    def int_to_base64url(n: int) -> str:
        b = n.to_bytes((n.bit_length() + 7) // 8, byteorder='big')
        return base64.urlsafe_b64encode(b).decode().rstrip('=')

    return {
        "keys": [
            {
                "kty": "RSA",
                "use": "sig",
                "kid": "key-1",
                "alg": settings.JWT_ALGORITHM,
                "n": int_to_base64url(public_numbers.n),
                "e": int_to_base64url(public_numbers.e)
            }
        ]
    }
```

### 他サービスでのJWKS利用

**User API Service / Admin API Service**:

```python
import requests
from jose import jwt

# JWKS取得
jwks_url = "http://host.docker.internal:8002/.well-known/jwks.json"
jwks = requests.get(jwks_url).json()

# JWT検証
payload = jwt.decode(
    token,
    jwks,
    algorithms=["RS256"],
    issuer="https://auth.example.com",
    audience="fastapi-api"
)
```

**環境変数**:
```bash
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
```

---

## パスワードハッシング

### bcrypt アルゴリズム

**特徴**:
- **ソルト自動生成**: レインボーテーブル攻撃耐性
- **調整可能なコスト**: 将来の計算能力向上に対応
- **スローハッシュ**: ブルートフォース攻撃を困難にする

### 実装

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/security.py`

```python
from passlib.context import CryptContext

# bcrypt コンテキスト作成（デフォルト: 10 rounds）
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def create_password_hash(password: str) -> str:
    """Create password hash using bcrypt"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against hash"""
    return pwd_context.verify(plain_password, hashed_password)
```

### ハッシュ例

**平文パスワード**: `MySecureP@ssw0rd`

**bcryptハッシュ**:
```
$2b$10$N9qo8uLOickgx2ZMRZoMye.IjxPq/YVN9l2hKjqHbW8K5VR1Gs9jO
```

**フォーマット**:
- `$2b$`: bcryptアルゴリズム識別子
- `10`: コストファクター（2^10 = 1024 ラウンド）
- `N9qo8uLOickgx2ZMRZoMye`: ソルト（22文字、base64）
- `IjxPq/YVN9l2hKjqHbW8K5VR1Gs9jO`: ハッシュ値（31文字、base64）

### コストファクター調整

**現在**: 10 rounds（約100ms）

**推奨**:
- 本番環境: 12 rounds（約400ms）
- 高セキュリティ: 14 rounds（約1600ms）

**設定変更**:
```python
pwd_context = CryptContext(
    schemes=["bcrypt"],
    bcrypt__rounds=12  # コストファクター変更
)
```

---

## ブルートフォース攻撃保護

### アカウントロックアウト機能

**データベーステーブル**: `authdb.users`

```sql
CREATE TABLE users (
  id uuid PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  roles TEXT[] NOT NULL DEFAULT ARRAY['user'],
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,
  login_attempts INTEGER DEFAULT 0,        -- ログイン試行回数
  last_login_at TIMESTAMP,                 -- 最終ログイン時刻
  locked_until TIMESTAMP                   -- ロック解除時刻
);
```

### ロックアウトロジック

**ポリシー**:
- 5回連続失敗でアカウントロック
- ロック期間: 30分
- ロック中のログイン試行は403エラー

**実装例**:

```python
@router.post("/login", response_model=TokenResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db)
) -> TokenResponse:
    """User login endpoint"""
    # Find user
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password"
        )

    # Check if account is locked
    if user.locked_until and user.locked_until > datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Account locked until {user.locked_until.isoformat()}"
        )

    # Verify password
    if not verify_password(request.password, user.password_hash):
        # Increment login attempts
        user.login_attempts += 1

        # Lock account after 5 failed attempts
        if user.login_attempts >= 5:
            user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=30)
            await db.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account locked due to too many failed login attempts"
            )

        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password"
        )

    # Reset login attempts on successful login
    user.login_attempts = 0
    user.last_login_at = datetime.now(timezone.utc)
    user.locked_until = None
    await db.commit()

    # Create tokens...
```

### レート制限（推奨実装）

**Redis ベースのレート制限**:

```python
async def check_rate_limit(email: str) -> bool:
    """Check if login rate limit exceeded"""
    key = f"rate_limit:login:{email}"

    # Increment counter
    count = await redis.incr(key)

    # Set expiration on first attempt
    if count == 1:
        await redis.expire(key, 60)  # 1分間

    # Allow 5 attempts per minute
    if count > 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Please try again later."
        )

    return True
```

---

## トークンライフサイクル管理

### トークン有効期限

**設定ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/config.py`

```python
class Settings(BaseSettings):
    ACCESS_TOKEN_TTL_SEC: int = 900       # 15分 (900秒)
    REFRESH_TOKEN_TTL_SEC: int = 2592000  # 30日 (2,592,000秒)
```

### トークンライフサイクル図

```
┌─────────────────────────────────────────────────────────────┐
│  Token Lifecycle                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Login                                                   │
│     ├─ Access Token (15min)                                │
│     └─ Refresh Token (30days)                              │
│                                                             │
│  2. Access Protected Resource                               │
│     ├─ Send Access Token                                   │
│     └─ Validate (signature, exp, blacklist)                │
│                                                             │
│  3. Access Token Expired (after 15min)                     │
│     ├─ 401 Unauthorized                                    │
│     └─ Client refreshes token                              │
│                                                             │
│  4. Token Refresh                                           │
│     ├─ Send Refresh Token                                  │
│     ├─ Validate Refresh Token                              │
│     ├─ Blacklist old Refresh Token                         │
│     ├─ Issue new Access Token (15min)                      │
│     └─ Issue new Refresh Token (30days)                    │
│                                                             │
│  5. Logout                                                  │
│     ├─ Blacklist Access Token                              │
│     ├─ Blacklist Refresh Token                             │
│     └─ Delete Session from Redis                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### セッション管理

**Redisキーパターン**:

```
session:<user_id>:<session_id> = {
  "access_jti": "abc12345-6789-1234-5678-1234567890ab",
  "refresh_jti": "def67890-1234-5678-9012-3456789012cd",
  "created_at": "2025-09-30T10:00:00Z"
}

TTL: 30日 (REFRESH_TOKEN_TTL_SEC)
```

### トークンブラックリスト

**Redisキーパターン**:

```
blacklist:access:<jti> = "1"
TTL: 15分 (ACCESS_TOKEN_TTL_SEC)

blacklist:refresh:<jti> = "1"
TTL: 30日 (REFRESH_TOKEN_TTL_SEC)
```

---

## セキュリティベストプラクティス

### 1. 鍵管理

**推奨事項**:
- ✅ 秘密鍵をコンテナボリュームで管理
- ✅ 秘密鍵を Git リポジトリにコミットしない
- ⚠️ 本番環境では鍵管理サービス（AWS KMS, Vault等）を使用
- ⚠️ 定期的な鍵ローテーション（年1回推奨）

**秘密鍵保護**:
```dockerfile
# Dockerfile
COPY keys/private.pem /keys/private.pem
RUN chmod 600 /keys/private.pem
RUN chown app:app /keys/private.pem
```

### 2. JWT クレーム検証

**必須検証項目**:
- ✅ 署名検証（`verify_signature=True`）
- ✅ 発行者検証（`issuer=settings.JWT_ISS`）
- ✅ 対象者検証（`audience=settings.JWT_AUD`）
- ✅ 有効期限検証（`exp` クレーム）
- ✅ ブラックリスト確認（Redis）

### 3. パスワードセキュリティ

**推奨事項**:
- ✅ bcrypt コストファクター: 10以上
- ✅ パスワード強度要件の実装
- ✅ パスワード履歴管理（再利用防止）
- ✅ 定期的なパスワード変更推奨

### 4. トークンセキュリティ

**推奨事項**:
- ✅ httpOnly Cookie での保存
- ✅ トークンローテーション（refresh時）
- ✅ ログアウト時の即時無効化
- ✅ 短いアクセストークン有効期限

### 5. ログとモニタリング

**記録すべきイベント**:
- ✅ ログイン成功/失敗
- ✅ アカウントロックアウト
- ✅ トークンリフレッシュ
- ✅ ログアウト
- ✅ 認証エラー

---

## トラブルシューティング

### 問題: JWT検証失敗

**原因**:
- 秘密鍵/公開鍵の不一致
- 時刻のずれ（`exp` クレーム検証失敗）
- ブラックリストに登録済み

**確認方法**:
```bash
# JWKS エンドポイント確認
curl http://localhost:8002/.well-known/jwks.json

# JWT デコード（署名検証なし）
echo "eyJ..." | base64 -d
```

### 問題: アカウントロックアウト

**原因**:
- 5回以上のログイン失敗

**解決策**:
```sql
-- ロック解除
UPDATE users
SET login_attempts = 0, locked_until = NULL
WHERE email = 'user@example.com';
```

### 問題: ブルートフォース攻撃

**症状**:
- 大量のログイン失敗
- 複数IPからの攻撃

**対策**:
- レート制限の実装
- IP ブラックリスト
- CAPTCHA 導入

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [03-authorization-security.md](./03-authorization-security.md) - 認可セキュリティ
- [07-password-policy.md](./07-password-policy.md) - パスワードポリシー
- [08-token-security.md](./08-token-security.md) - トークンセキュリティ

### サービス詳細
- [Auth Service 概要](/01-auth-service/01-overview.md)
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)
- [Auth Service データベース設計](/01-auth-service/03-database-design.md)

---

**次のステップ**: [03-authorization-security.md](./03-authorization-security.md) を参照して、RBAC による認可の実装を確認してください。