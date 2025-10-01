# セキュリティ実装

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [パスワードセキュリティ](#パスワードセキュリティ)
- [トークンセキュリティ](#トークンセキュリティ)
- [通信セキュリティ](#通信セキュリティ)
- [アクセス制御](#アクセス制御)
- [攻撃対策](#攻撃対策)
- [監査とロギング](#監査とロギング)

---

## 概要

認証サービスは、システム全体のセキュリティの要となる重要なコンポーネントです。本ドキュメントでは、実装されている各種セキュリティ対策について詳述します。

### セキュリティ設計原則

1. **多層防御（Defense in Depth）**
   - 複数のセキュリティレイヤーを実装
   - 一つの対策が破られても他の対策でカバー

2. **最小権限の原則（Principle of Least Privilege）**
   - 必要最小限の権限のみ付与
   - デフォルトで拒否、明示的に許可

3. **セキュアデフォルト（Secure by Default）**
   - 安全な設定をデフォルトに
   - セキュリティ設定の明示的な無効化を必須に

4. **Fail Secure**
   - エラー発生時は安全側に倒す
   - 認証失敗時は必ずアクセス拒否

---

## パスワードセキュリティ

### パスワードハッシュ化

bcryptアルゴリズムを使用して、ソルト付きハッシュを生成します。

#### 実装例

```python
from passlib.context import CryptContext

# パスワードコンテキスト設定
pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto",
    bcrypt__rounds=12  # コストファクター（処理時間）
)

def hash_password(password: str) -> str:
    """パスワードをハッシュ化"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """パスワードを検証"""
    return pwd_context.verify(plain_password, hashed_password)
```

#### bcrypt特性

- **コストファクター**: 12（推奨値）
  - 2^12回の内部反復処理
  - ハッシュ化に約100-300msかかる（ブルートフォース攻撃対策）

- **自動ソルト生成**: ユーザーごとに異なるソルト
- **レインボーテーブル攻撃対策**: ソルトにより無効化

#### パスワードハッシュ例

```
入力: SecurePass123!
出力: $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyK.T3lQ.Dz2

構造:
$2b$      → bcryptバージョン
12$       → コストファクター
LQv...kCO → ソルト（22文字）
Yz6...Dz2 → ハッシュ値（31文字）
```

### パスワードポリシー

```python
import re
from typing import List

def validate_password_strength(password: str) -> tuple[bool, List[str]]:
    """パスワード強度検証"""
    errors = []

    # 最小文字数
    if len(password) < 8:
        errors.append("Password must be at least 8 characters")

    # 最大文字数
    if len(password) > 128:
        errors.append("Password must be at most 128 characters")

    # 大文字を含む
    if not re.search(r'[A-Z]', password):
        errors.append("Password must contain at least one uppercase letter")

    # 小文字を含む
    if not re.search(r'[a-z]', password):
        errors.append("Password must contain at least one lowercase letter")

    # 数字を含む
    if not re.search(r'\d', password):
        errors.append("Password must contain at least one digit")

    # 特殊文字を含む（推奨）
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        errors.append("Password should contain at least one special character")

    # 一般的なパスワードチェック
    common_passwords = ["password", "12345678", "qwerty"]
    if password.lower() in common_passwords:
        errors.append("Password is too common")

    return len(errors) == 0, errors
```

### パスワードリセット

```python
import secrets
from datetime import datetime, timedelta

def generate_reset_token() -> tuple[str, datetime]:
    """パスワードリセットトークン生成"""
    # 安全なランダムトークン生成（32バイト=256ビット）
    token = secrets.token_urlsafe(32)

    # 有効期限: 1時間
    expires_at = datetime.utcnow() + timedelta(hours=1)

    return token, expires_at

async def send_reset_email(email: str, token: str):
    """リセットメール送信"""
    reset_url = f"https://example.com/reset-password?token={token}"

    # TODO: メール送信実装
    # - トークンをRedisに保存（有効期限付き）
    # - メール送信（SMTP or サードパーティサービス）
    pass
```

---

## トークンセキュリティ

### JWT署名

RS256（RSA + SHA-256）による非対称鍵署名を実装。

```python
from jose import jwt
from datetime import datetime, timedelta
import uuid

# RSA秘密鍵読み込み
with open("keys/private_key.pem", "r") as f:
    PRIVATE_KEY = f.read()

def create_jwt(
    user_id: str,
    email: str,
    role: str,
    token_type: str = "access",
    expires_delta: timedelta = timedelta(minutes=15)
) -> str:
    """JWT生成"""
    now = datetime.utcnow()

    payload = {
        "sub": user_id,
        "email": email,
        "role": role,
        "iss": "https://auth.example.com",
        "aud": "fastapi-api",
        "iat": int(now.timestamp()),
        "exp": int((now + expires_delta).timestamp()),
        "token_type": token_type,
        "jti": str(uuid.uuid4()) if token_type == "refresh" else None
    }

    # None値を除去
    payload = {k: v for k, v in payload.items() if v is not None}

    return jwt.encode(
        payload,
        PRIVATE_KEY,
        algorithm="RS256",
        headers={"kid": "auth-service-key-1"}
    )
```

### トークンブラックリスト

Redisを使用してログアウト済みトークンを管理。

```python
import redis.asyncio as redis
from jose import jwt, JWTError

redis_client = redis.from_url("redis://localhost:6379")

async def blacklist_token(token: str):
    """トークンをブラックリスト登録"""
    try:
        # トークンデコード（検証なし）
        payload = jwt.get_unverified_claims(token)

        jti = payload.get("jti")
        exp = payload.get("exp")

        if not jti:
            # アクセストークンの場合、トークン全体をキーにする
            jti = token[:50]  # トークンの一部をキーに

        # 有効期限まで保存
        ttl = exp - int(datetime.utcnow().timestamp())
        if ttl > 0:
            await redis_client.setex(
                f"blacklist:{jti}",
                ttl,
                "1"
            )

    except JWTError:
        pass

async def is_token_blacklisted(token: str) -> bool:
    """トークンがブラックリストに登録されているか確認"""
    try:
        payload = jwt.get_unverified_claims(token)
        jti = payload.get("jti") or token[:50]

        exists = await redis_client.exists(f"blacklist:{jti}")
        return bool(exists)

    except JWTError:
        return True  # デコード失敗 = 無効なトークン
```

### トークンローテーション

リフレッシュトークン使用時に新トークンを発行し、旧トークンを無効化。

```python
async def refresh_access_token(refresh_token: str) -> dict:
    """アクセストークンをリフレッシュ"""
    # 1. リフレッシュトークン検証
    payload = verify_jwt(refresh_token)

    if payload.get("token_type") != "refresh":
        raise ValueError("Invalid token type")

    # 2. ブラックリストチェック
    if await is_token_blacklisted(refresh_token):
        raise ValueError("Token has been revoked")

    # 3. 新トークン生成
    new_access_token = create_jwt(
        user_id=payload["sub"],
        email=payload["email"],
        role=payload["role"],
        token_type="access",
        expires_delta=timedelta(minutes=15)
    )

    new_refresh_token = create_jwt(
        user_id=payload["sub"],
        email=payload["email"],
        role=payload["role"],
        token_type="refresh",
        expires_delta=timedelta(days=7)
    )

    # 4. 旧リフレッシュトークンを無効化
    await blacklist_token(refresh_token)

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "Bearer",
        "expires_in": 900
    }
```

---

## 通信セキュリティ

### HTTPS/TLS設定

本番環境では必ずHTTPSを使用します。

```python
# Nginxリバースプロキシ設定例
"""
server {
    listen 443 ssl http2;
    server_name auth.example.com;

    ssl_certificate /etc/ssl/certs/cert.pem;
    ssl_certificate_key /etc/ssl/private/key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://localhost:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
"""
```

### CORS設定

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# CORS設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3002",  # User Frontend
        "http://localhost:3003",  # Admin Frontend
        "https://app.example.com",  # 本番環境
    ],
    allow_credentials=True,  # Cookie送信を許可
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
    expose_headers=["X-RateLimit-Limit", "X-RateLimit-Remaining"],
)
```

### セキュリティヘッダー

```python
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        # セキュリティヘッダー追加
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        response.headers["Referrer-Policy"] = "no-referrer"

        return response

app.add_middleware(SecurityHeadersMiddleware)
```

---

## アクセス制御

### ロールベースアクセス制御（RBAC）

```python
from fastapi import Depends, HTTPException, status
from jose import jwt

def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """現在のユーザー取得"""
    try:
        payload = verify_jwt(token)
        return payload
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def require_role(required_role: str):
    """ロール検証デコレーター"""
    def role_checker(current_user: dict = Depends(get_current_user)):
        if current_user.get("role") != required_role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions"
            )
        return current_user
    return role_checker

# 使用例
@app.get("/admin/users")
async def list_users(current_user: dict = Depends(require_role("admin"))):
    """管理者のみアクセス可能"""
    # ユーザー一覧取得処理
    pass
```

### 権限ベースアクセス制御（ABAC）

```python
from enum import Enum
from typing import List

class Permission(str, Enum):
    READ_PROFILE = "read:profile"
    WRITE_PROFILE = "write:profile"
    DELETE_USER = "delete:user"
    MANAGE_USERS = "manage:users"

# ロールごとの権限定義
ROLE_PERMISSIONS = {
    "user": [
        Permission.READ_PROFILE,
        Permission.WRITE_PROFILE,
    ],
    "admin": [
        Permission.READ_PROFILE,
        Permission.WRITE_PROFILE,
        Permission.DELETE_USER,
        Permission.MANAGE_USERS,
    ]
}

def require_permission(required_permission: Permission):
    """権限検証デコレーター"""
    def permission_checker(current_user: dict = Depends(get_current_user)):
        user_role = current_user.get("role")
        permissions = ROLE_PERMISSIONS.get(user_role, [])

        if required_permission not in permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission '{required_permission}' required"
            )
        return current_user
    return permission_checker
```

---

## 攻撃対策

### ブルートフォース攻撃対策

```python
async def handle_failed_login(user_id: str):
    """ログイン失敗処理"""
    # 失敗回数をインクリメント
    await db.execute(
        """
        UPDATE users
        SET failed_login_attempts = failed_login_attempts + 1,
            locked_until = CASE
                WHEN failed_login_attempts + 1 >= 5
                THEN CURRENT_TIMESTAMP + INTERVAL '15 minutes'
                ELSE locked_until
            END
        WHERE id = $1
        """,
        user_id
    )

async def check_account_lock(user_id: str) -> bool:
    """アカウントロック確認"""
    result = await db.fetchrow(
        """
        SELECT locked_until, failed_login_attempts
        FROM users
        WHERE id = $1
        """,
        user_id
    )

    if result["locked_until"] and result["locked_until"] > datetime.utcnow():
        return True  # ロック中

    return False

async def reset_failed_attempts(user_id: str):
    """ログイン成功時、失敗回数リセット"""
    await db.execute(
        """
        UPDATE users
        SET failed_login_attempts = 0,
            locked_until = NULL,
            last_login_at = CURRENT_TIMESTAMP
        WHERE id = $1
        """,
        user_id
    )
```

### レート制限

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# エンドポイントごとのレート制限
@app.post("/api/v1/auth/login")
@limiter.limit("5/minute")
async def login(request: Request, credentials: LoginRequest):
    """ログイン（5回/分まで）"""
    pass

@app.post("/api/v1/auth/register")
@limiter.limit("3/hour")
async def register(request: Request, user_data: UserCreate):
    """ユーザー登録（3回/時間まで）"""
    pass
```

### SQL インジェクション対策

```python
# ✅ 正しい実装（パラメータ化クエリ）
async def get_user_by_email(email: str):
    query = "SELECT * FROM users WHERE email = $1"
    result = await db.fetchrow(query, email)
    return result

# ❌ 危険な実装（SQLインジェクション脆弱性）
async def get_user_by_email_unsafe(email: str):
    query = f"SELECT * FROM users WHERE email = '{email}'"
    result = await db.fetchrow(query)
    return result
```

### XSS対策

```python
from fastapi.responses import JSONResponse
import html

def sanitize_output(data: dict) -> dict:
    """出力データのサニタイズ"""
    if isinstance(data, dict):
        return {k: sanitize_output(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_output(item) for item in data]
    elif isinstance(data, str):
        return html.escape(data)
    else:
        return data

# JSONレスポンスは自動的にエスケープされる
@app.get("/api/v1/users/{user_id}")
async def get_user(user_id: str):
    user = await get_user_from_db(user_id)
    # FastAPIが自動的に安全なJSON変換を行う
    return user
```

---

## 監査とロギング

### セキュリティイベントのロギング

```python
import logging
from datetime import datetime

# ロガー設定
security_logger = logging.getLogger("security")
security_logger.setLevel(logging.INFO)

# ファイルハンドラ
handler = logging.FileHandler("logs/security.log")
formatter = logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
handler.setFormatter(formatter)
security_logger.addHandler(handler)

def log_security_event(event_type: str, user_id: str, details: dict):
    """セキュリティイベント記録"""
    security_logger.info(
        f"Event: {event_type} | User: {user_id} | Details: {details}"
    )

# 使用例
async def login(credentials: LoginRequest):
    user = await authenticate_user(credentials.email, credentials.password)

    if user:
        log_security_event(
            "LOGIN_SUCCESS",
            user.id,
            {"email": credentials.email, "ip": request.client.host}
        )
    else:
        log_security_event(
            "LOGIN_FAILED",
            "unknown",
            {"email": credentials.email, "ip": request.client.host}
        )
```

### 監査証跡

重要な操作を記録するテーブル設計：

```sql
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    action VARCHAR(50) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
```

---

## 関連ドキュメント

- [認証サービス概要](./01-overview.md)
- [JWT設計](./03-jwt-design.md)
- [authdbデータベース設計](./04-database-design.md)
- [セキュリティ全体方針](../10-security/01-security-overview.md)
- [認証フロー](../08-integration/02-authentication-flow.md)