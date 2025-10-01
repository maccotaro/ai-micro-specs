# パスワードポリシー

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [パスワード強度要件](#パスワード強度要件)
- [パスワードハッシング](#パスワードハッシング)
- [パスワードリセットフロー](#パスワードリセットフロー)
- [アカウントロックアウト](#アカウントロックアウト)
- [パスワード変更要件](#パスワード変更要件)

---

## 概要

### パスワードポリシーの重要性

強力なパスワードポリシーは、アカウント乗っ取りやデータ漏洩を防ぐための最前線の防御です。ai-micro-service システムでは、NIST（米国国立標準技術研究所）およびOWASPのガイドラインに基づいたパスワードポリシーを実装しています。

### ポリシー概要

| 項目 | 要件 | 実装状況 |
|-----|------|---------|
| 最小文字数 | 8文字以上 | ✅ 実装済み |
| 複雑さ要件 | 推奨（必須ではない） | ⚠️ 未実装 |
| パスワード有効期限 | 設定可能 | ⚠️ 未実装 |
| パスワード履歴 | 設定可能 | ⚠️ 未実装 |
| アカウントロックアウト | 5回失敗で30分ロック | ✅ 実装済み |

---

## パスワード強度要件

### 現在の実装

**最小要件**:
```python
# app/schemas/auth.py
from pydantic import BaseModel, Field, validator

class SignUpRequest(BaseModel):
    email: str = Field(..., regex=r'^[\w\.-]+@[\w\.-]+\.\w+$')
    password: str = Field(..., min_length=8)

    @validator('password')
    def validate_password(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters long')
        return v
```

### 推奨される強化

**複雑さ要件の追加**:

```python
import re
from typing import List

class PasswordValidator:
    """Password strength validator"""

    @staticmethod
    def validate_strength(password: str) -> tuple[bool, List[str]]:
        """Validate password strength"""
        errors = []

        # 最小文字数チェック
        if len(password) < 8:
            errors.append("Password must be at least 8 characters long")

        # 大文字チェック（推奨）
        if not re.search(r'[A-Z]', password):
            errors.append("Password should contain at least one uppercase letter")

        # 小文字チェック（推奨）
        if not re.search(r'[a-z]', password):
            errors.append("Password should contain at least one lowercase letter")

        # 数字チェック（推奨）
        if not re.search(r'\d', password):
            errors.append("Password should contain at least one digit")

        # 特殊文字チェック（推奨）
        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
            errors.append("Password should contain at least one special character")

        # 一般的なパスワードチェック
        common_passwords = [
            'password', '12345678', 'qwerty', 'abc123', 'password123'
        ]
        if password.lower() in common_passwords:
            errors.append("Password is too common")

        return len(errors) == 0, errors

# 使用例
@router.post("/signup")
async def signup(request: SignUpRequest):
    is_valid, errors = PasswordValidator.validate_strength(request.password)

    if not is_valid:
        raise HTTPException(
            status_code=400,
            detail={"message": "Weak password", "errors": errors}
        )

    # ユーザー登録処理
    ...
```

### パスワード強度メーター

**フロントエンド実装例（React）**:

```tsx
import { useState, useEffect } from 'react';

function PasswordStrengthMeter({ password }: { password: string }) {
  const [strength, setStrength] = useState(0);
  const [feedback, setFeedback] = useState<string[]>([]);

  useEffect(() => {
    const { strength: score, feedback: messages } = calculateStrength(password);
    setStrength(score);
    setFeedback(messages);
  }, [password]);

  const calculateStrength = (pwd: string) => {
    let score = 0;
    const messages: string[] = [];

    if (pwd.length >= 8) score += 20;
    else messages.push('At least 8 characters');

    if (/[a-z]/.test(pwd)) score += 20;
    else messages.push('Lowercase letter');

    if (/[A-Z]/.test(pwd)) score += 20;
    else messages.push('Uppercase letter');

    if (/\d/.test(pwd)) score += 20;
    else messages.push('Number');

    if (/[^a-zA-Z0-9]/.test(pwd)) score += 20;
    else messages.push('Special character');

    return { strength: score, feedback: messages };
  };

  const getColor = () => {
    if (strength < 40) return 'red';
    if (strength < 80) return 'orange';
    return 'green';
  };

  return (
    <div>
      <div className="strength-bar" style={{ width: `${strength}%`, backgroundColor: getColor() }} />
      <ul>
        {feedback.map((msg, i) => <li key={i}>{msg}</li>)}
      </ul>
    </div>
  );
}
```

---

## パスワードハッシング

### bcrypt アルゴリズム

**実装**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/core/security.py`

```python
from passlib.context import CryptContext

# bcrypt コンテキスト（デフォルト: 10 rounds）
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def create_password_hash(password: str) -> str:
    """Create password hash using bcrypt"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against hash"""
    return pwd_context.verify(plain_password, hashed_password)
```

### ハッシュの詳細

**bcrypt ハッシュフォーマット**:
```
$2b$10$N9qo8uLOickgx2ZMRZoMye.IjxPq/YVN9l2hKjqHbW8K5VR1Gs9jO
 │  │  │                      │
 │  │  │                      └─ ハッシュ値（31文字）
 │  │  └─ ソルト（22文字）
 │  └─ コストファクター（2^10 = 1024ラウンド）
 └─ アルゴリズム識別子（bcrypt）
```

**特徴**:
1. **自動ソルト生成**: レインボーテーブル攻撃耐性
2. **調整可能なコスト**: 計算時間を調整可能
3. **バックワード互換**: 古いハッシュも検証可能

### コストファクターの調整

**推奨値**:

| 環境 | コストファクター | 計算時間 | 推奨用途 |
|-----|---------------|---------|---------|
| 開発 | 10 | ~100ms | テスト・開発 |
| 本番（通常） | 12 | ~400ms | 一般的なWebアプリ |
| 高セキュリティ | 14 | ~1600ms | 金融・医療系 |

**設定変更**:
```python
# app/core/security.py
pwd_context = CryptContext(
    schemes=["bcrypt"],
    bcrypt__rounds=12  # 本番環境では12推奨
)
```

### ハッシュのアップグレード

**古いハッシュの自動アップグレード**:

```python
def verify_and_upgrade_password(
    plain_password: str,
    hashed_password: str,
    user: User,
    db: AsyncSession
) -> bool:
    """Verify password and upgrade hash if needed"""

    # パスワード検証
    if not pwd_context.verify(plain_password, hashed_password):
        return False

    # ハッシュが古い場合は再ハッシュ化
    if pwd_context.needs_update(hashed_password):
        user.password_hash = pwd_context.hash(plain_password)
        await db.commit()

    return True
```

---

## パスワードリセットフロー

### リセットトークン生成

**実装例**:

```python
import secrets
from datetime import datetime, timedelta, timezone

class PasswordResetManager:
    """Password reset token manager"""

    @staticmethod
    async def create_reset_token(email: str) -> str:
        """Create password reset token"""
        # トークン生成（32バイト = 256ビット）
        token = secrets.token_urlsafe(32)

        # Redis に保存（有効期限: 1時間）
        await redis.setex(
            f"password_reset:{token}",
            3600,
            email
        )

        return token

    @staticmethod
    async def verify_reset_token(token: str) -> str | None:
        """Verify password reset token and return email"""
        email = await redis.get(f"password_reset:{token}")

        if not email:
            return None

        return email

    @staticmethod
    async def consume_reset_token(token: str):
        """Consume password reset token (single use)"""
        await redis.delete(f"password_reset:{token}")
```

### パスワードリセットAPI

```python
from pydantic import BaseModel, EmailStr

class PasswordResetRequest(BaseModel):
    email: EmailStr

class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str = Field(..., min_length=8)

@router.post("/password-reset/request")
async def request_password_reset(
    request: PasswordResetRequest,
    db: AsyncSession = Depends(get_db)
):
    """Request password reset"""
    # ユーザー検索
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    user = result.scalar_one_or_none()

    # セキュリティのため、ユーザーの有無に関わらず成功レスポンス
    if user:
        # リセットトークン生成
        token = await PasswordResetManager.create_reset_token(user.email)

        # メール送信（実装省略）
        await send_password_reset_email(user.email, token)

    return {"message": "If the email exists, a reset link has been sent"}

@router.post("/password-reset/confirm")
async def confirm_password_reset(
    request: PasswordResetConfirm,
    db: AsyncSession = Depends(get_db)
):
    """Confirm password reset"""
    # トークン検証
    email = await PasswordResetManager.verify_reset_token(request.token)

    if not email:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired reset token"
        )

    # ユーザー取得
    result = await db.execute(
        select(User).where(User.email == email)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # パスワード強度チェック
    is_valid, errors = PasswordValidator.validate_strength(request.new_password)
    if not is_valid:
        raise HTTPException(status_code=400, detail={"errors": errors})

    # パスワード更新
    user.password_hash = create_password_hash(request.new_password)
    user.updated_at = datetime.now(timezone.utc)
    await db.commit()

    # トークン消費
    await PasswordResetManager.consume_reset_token(request.token)

    return {"message": "Password reset successfully"}
```

### メール送信

**SendGrid 実装例**:

```python
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail

async def send_password_reset_email(email: str, token: str):
    """Send password reset email"""
    reset_url = f"https://app.example.com/reset-password?token={token}"

    message = Mail(
        from_email='noreply@example.com',
        to_emails=email,
        subject='Password Reset Request',
        html_content=f'''
        <h1>Password Reset</h1>
        <p>Click the link below to reset your password:</p>
        <a href="{reset_url}">{reset_url}</a>
        <p>This link will expire in 1 hour.</p>
        <p>If you didn't request this, please ignore this email.</p>
        '''
    )

    try:
        sg = SendGridAPIClient(settings.SENDGRID_API_KEY)
        response = sg.send(message)
        logger.info(f"Password reset email sent to {email}")
    except Exception as e:
        logger.error(f"Failed to send email: {str(e)}")
```

---

## アカウントロックアウト

### データベーススキーマ

**テーブル**: `authdb.users`

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

**実装**: `app/routers/auth.py`

```python
from datetime import datetime, timedelta, timezone

@router.post("/login")
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """User login with lockout protection"""
    # ユーザー取得
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # アカウントロック確認
    if user.locked_until and user.locked_until > datetime.now(timezone.utc):
        remaining = (user.locked_until - datetime.now(timezone.utc)).total_seconds()
        raise HTTPException(
            status_code=403,
            detail=f"Account locked. Try again in {int(remaining / 60)} minutes"
        )

    # パスワード検証
    if not verify_password(request.password, user.password_hash):
        # ログイン試行回数を増加
        user.login_attempts += 1

        # 5回失敗でロック（30分）
        if user.login_attempts >= 5:
            user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=30)
            await db.commit()

            # ログ記録
            await log_security_event(
                user_id=str(user.id),
                event="account_locked",
                reason="too_many_failed_attempts"
            )

            raise HTTPException(
                status_code=403,
                detail="Account locked due to too many failed login attempts"
            )

        await db.commit()
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # ログイン成功 - カウンターリセット
    user.login_attempts = 0
    user.locked_until = None
    user.last_login_at = datetime.now(timezone.utc)
    await db.commit()

    # トークン生成
    access_token, access_jti = create_access_token(
        user_id=str(user.id),
        roles=user.roles
    )
    refresh_token, refresh_jti, session_id = create_refresh_token(
        user_id=str(user.id)
    )

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.ACCESS_TOKEN_TTL_SEC
    )
```

### 管理者によるロック解除

```python
@router.post("/admin/users/{user_id}/unlock")
async def unlock_user_account(
    user_id: str,
    current_user = Depends(require_roles(["admin", "super_admin"])),
    db: AsyncSession = Depends(get_db)
):
    """Unlock user account (admin only)"""
    user = await db.get(User, user_id)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.login_attempts = 0
    user.locked_until = None
    await db.commit()

    # ログ記録
    await log_security_event(
        user_id=user_id,
        event="account_unlocked",
        admin_id=current_user["sub"]
    )

    return {"message": "Account unlocked successfully"}
```

---

## パスワード変更要件

### パスワード変更API

```python
class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=8)

@router.post("/password/change")
async def change_password(
    request: PasswordChangeRequest,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Change user password"""
    user_id = current_user["sub"]

    # ユーザー取得
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 現在のパスワード検証
    if not verify_password(request.current_password, user.password_hash):
        raise HTTPException(
            status_code=400,
            detail="Current password is incorrect"
        )

    # 新しいパスワードの強度チェック
    is_valid, errors = PasswordValidator.validate_strength(request.new_password)
    if not is_valid:
        raise HTTPException(status_code=400, detail={"errors": errors})

    # 現在のパスワードと同じかチェック
    if verify_password(request.new_password, user.password_hash):
        raise HTTPException(
            status_code=400,
            detail="New password must be different from current password"
        )

    # パスワード更新
    user.password_hash = create_password_hash(request.new_password)
    user.updated_at = datetime.now(timezone.utc)
    await db.commit()

    # すべてのセッションを無効化
    await invalidate_all_user_sessions(user_id)

    # ログ記録
    await log_security_event(
        user_id=user_id,
        event="password_changed"
    )

    return {"message": "Password changed successfully"}
```

### パスワード履歴管理（推奨実装）

**テーブル作成**:

```sql
CREATE TABLE password_history (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_password_history_user_id ON password_history(user_id);
```

**実装**:

```python
async def check_password_history(
    user_id: str,
    new_password: str,
    history_count: int = 5,
    db: AsyncSession = None
) -> bool:
    """Check if password was used recently"""
    # 過去N個のパスワードを取得
    result = await db.execute(
        select(PasswordHistory)
        .where(PasswordHistory.user_id == user_id)
        .order_by(PasswordHistory.created_at.desc())
        .limit(history_count)
    )
    history = result.scalars().all()

    # 過去のパスワードと照合
    for entry in history:
        if verify_password(new_password, entry.password_hash):
            return False  # 過去に使用済み

    return True  # 未使用

async def save_password_to_history(
    user_id: str,
    password_hash: str,
    db: AsyncSession
):
    """Save password to history"""
    entry = PasswordHistory(
        user_id=user_id,
        password_hash=password_hash
    )
    db.add(entry)
    await db.commit()
```

---

## セキュリティベストプラクティス

### 1. パスワード要件の表示

**フロントエンドで要件を明示**:
```tsx
<ul>
  <li>✓ 8文字以上</li>
  <li>✓ 大文字を含む</li>
  <li>✓ 小文字を含む</li>
  <li>✓ 数字を含む</li>
  <li>✓ 特殊文字を含む</li>
</ul>
```

### 2. エラーメッセージ

**ダメな例**:
```python
# ❌ 情報漏えい
raise HTTPException(detail="User user@example.com does not exist")
```

**良い例**:
```python
# ✅ 一般的なメッセージ
raise HTTPException(detail="Invalid email or password")
```

### 3. レート制限

```python
# ログイン試行のレート制限
@rate_limit(limit=10, window=60)  # 1分あたり10回
@router.post("/login")
async def login(...):
    pass
```

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [04-data-protection.md](./04-data-protection.md) - データ保護

### サービス詳細
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)

---

**次のステップ**: [08-token-security.md](./08-token-security.md) を参照して、トークンセキュリティの詳細を確認してください。