# CORS とセキュリティヘッダー

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [CORS設定](#cors設定)
- [セキュリティヘッダー](#セキュリティヘッダー)
- [Cookieセキュリティ](#cookieセキュリティ)
- [XSS保護](#xss保護)
- [CSRF保護](#csrf保護)

---

## 概要

### CORS とセキュリティヘッダーの重要性

Web アプリケーションのセキュリティにおいて、適切な CORS（Cross-Origin Resource Sharing）設定とセキュリティヘッダーの実装は不可欠です。これらは以下の攻撃から保護します:

- **XSS（Cross-Site Scripting）**: 悪意のあるスクリプトの実行
- **CSRF（Cross-Site Request Forgery）**: 不正なリクエストの送信
- **Clickjacking**: 透明なiframeによる誘導
- **MIME Type Sniffing**: コンテンツタイプの誤判定攻撃

---

## CORS設定

### CORS の仕組み

CORS は、異なるオリジン間でのリソース共有を制御するメカニズムです。

**オリジンの定義**:
```
https://example.com:443
  ↓      ↓           ↓
scheme  host      port
```

**同一オリジン例**:
- ✅ `https://api.example.com` → `https://api.example.com/users`
- ❌ `https://api.example.com` → `https://app.example.com` (異なるホスト)
- ❌ `https://api.example.com` → `http://api.example.com` (異なるスキーム)
- ❌ `https://api.example.com:443` → `https://api.example.com:8080` (異なるポート)

### Auth Service の CORS 設定

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-auth/app/main.py`

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Auth Service")

# CORS設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # 開発環境: すべて許可
    allow_credentials=True,     # Cookie送信を許可
    allow_methods=["*"],        # すべてのHTTPメソッド許可
    allow_headers=["*"],        # すべてのヘッダー許可
)
```

### 本番環境の CORS 設定

**推奨設定**:

```python
from app.core.config import settings

# 環境変数から許可オリジンを取得
allowed_origins = settings.ALLOWED_ORIGINS.split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,  # 具体的なオリジンのみ許可
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Request-ID",
        "X-CSRF-Token"
    ],
    expose_headers=["X-Request-ID"],
    max_age=3600  # プリフライトリクエストのキャッシュ時間（秒）
)
```

**.env 設定**:
```bash
# 本番環境
ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com

# 開発環境
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001,http://localhost:3002,http://localhost:3003
```

### CORS プリフライトリクエスト

**プリフライトの流れ**:

```
┌──────────┐                              ┌──────────┐
│ Browser  │                              │  Server  │
└────┬─────┘                              └────┬─────┘
     │                                         │
     │  1. OPTIONS /api/login                 │
     │     Origin: https://app.example.com    │
     │────────────────────────────────────────→│
     │                                         │
     │  2. 200 OK                             │
     │     Access-Control-Allow-Origin: *     │
     │     Access-Control-Allow-Methods: POST │
     │     Access-Control-Allow-Headers: ...  │
     │←────────────────────────────────────────│
     │                                         │
     │  3. POST /api/login                    │
     │     Origin: https://app.example.com    │
     │     Authorization: Bearer xxx          │
     │────────────────────────────────────────→│
     │                                         │
     │  4. 200 OK                             │
     │     Access-Control-Allow-Origin: *     │
     │     {access_token, refresh_token}      │
     │←────────────────────────────────────────│
     │                                         │
```

### CORS エラーのトラブルシューティング

**よくあるエラー**:

```
Access to fetch at 'https://api.example.com/auth/login' from origin
'https://app.example.com' has been blocked by CORS policy:
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

**原因と対策**:

1. **オリジンが許可されていない**:
   ```python
   # ダメな例
   allow_origins=["https://app.example.com"]

   # リクエストオリジン: https://app.example.org
   # → CORS エラー

   # 対策: 正しいオリジンを追加
   allow_origins=["https://app.example.com", "https://app.example.org"]
   ```

2. **Credentials 設定の不一致**:
   ```python
   # サーバー側
   allow_credentials=True

   # クライアント側（JavaScript）
   fetch(url, {
     credentials: 'include'  # 必須
   })
   ```

3. **カスタムヘッダーが許可されていない**:
   ```python
   # Authorization ヘッダーを使用する場合
   allow_headers=["Authorization", "Content-Type"]
   ```

---

## セキュリティヘッダー

### 必須セキュリティヘッダー

**推奨実装**:

```python
from fastapi import FastAPI
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add security headers to all responses"""
    async def dispatch(self, request, call_next):
        response = await call_next(request)

        # セキュリティヘッダーの追加
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: https:; "
            "font-src 'self'; "
            "connect-src 'self'; "
            "frame-ancestors 'none';"
        )
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = (
            "geolocation=(), "
            "microphone=(), "
            "camera=(), "
            "payment=()"
        )

        return response

app = FastAPI()
app.add_middleware(SecurityHeadersMiddleware)
```

### セキュリティヘッダー詳細

#### 1. X-Content-Type-Options

**目的**: MIME Type Sniffing攻撃を防止

**設定**:
```python
response.headers["X-Content-Type-Options"] = "nosniff"
```

**効果**:
- ブラウザがContent-Typeヘッダーを尊重
- MIMEタイプの自動判定を無効化

#### 2. X-Frame-Options

**目的**: Clickjacking攻撃を防止

**設定**:
```python
response.headers["X-Frame-Options"] = "DENY"
# または
response.headers["X-Frame-Options"] = "SAMEORIGIN"
```

**オプション**:
- `DENY`: すべてのフレーム埋め込みを禁止
- `SAMEORIGIN`: 同一オリジンのみ許可
- `ALLOW-FROM uri`: 特定のオリジンのみ許可（非推奨）

#### 3. Content-Security-Policy (CSP)

**目的**: XSS攻撃を防止

**基本設定**:
```python
response.headers["Content-Security-Policy"] = (
    "default-src 'self'; "
    "script-src 'self'; "
    "style-src 'self'; "
    "img-src 'self' data: https:; "
    "font-src 'self'; "
    "connect-src 'self'; "
    "frame-ancestors 'none';"
)
```

**ディレクティブ詳細**:

| ディレクティブ | 説明 | 推奨設定 |
|-------------|------|---------|
| `default-src` | デフォルトポリシー | `'self'` |
| `script-src` | JavaScript読み込み | `'self'` |
| `style-src` | CSS読み込み | `'self'` |
| `img-src` | 画像読み込み | `'self' data: https:` |
| `connect-src` | XHR, WebSocket | `'self'` |
| `frame-ancestors` | フレーム埋め込み | `'none'` |
| `form-action` | フォーム送信先 | `'self'` |

**開発環境での緩和**:
```python
# 開発環境のみ unsafe-inline / unsafe-eval を許可
if settings.ENV == "development":
    csp = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
        "style-src 'self' 'unsafe-inline';"
    )
```

#### 4. Strict-Transport-Security (HSTS)

**目的**: HTTPS接続を強制

**設定**:
```python
response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
```

**パラメータ**:
- `max-age=31536000`: 1年間HSTSを記憶
- `includeSubDomains`: サブドメインにも適用
- `preload`: HSTSプリロードリストに登録可能

**注意**: HTTPS環境でのみ有効

#### 5. X-XSS-Protection

**目的**: ブラウザ組み込みのXSS防止機能を有効化

**設定**:
```python
response.headers["X-XSS-Protection"] = "1; mode=block"
```

**パラメータ**:
- `1`: XSS Protection 有効
- `mode=block`: XSS検出時にページレンダリングをブロック

**注意**: 現代のブラウザでは CSP が推奨

#### 6. Referrer-Policy

**目的**: Refererヘッダーの送信を制御

**設定**:
```python
response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
```

**ポリシー**:
- `no-referrer`: Refererを送信しない
- `strict-origin`: オリジンのみ送信
- `strict-origin-when-cross-origin`: 同一オリジンでは完全なURL、クロスオリジンではオリジンのみ

#### 7. Permissions-Policy

**目的**: ブラウザAPIの使用を制限

**設定**:
```python
response.headers["Permissions-Policy"] = (
    "geolocation=(), "
    "microphone=(), "
    "camera=(), "
    "payment=(), "
    "usb=(), "
    "fullscreen=(self)"
)
```

---

## Cookieセキュリティ

### Cookie属性

**セキュアなCookie設定**:

```typescript
// Next.js BFF での設定例
res.setHeader('Set-Cookie', [
  `access_token=${accessToken}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900`,
  `refresh_token=${refreshToken}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=2592000`
]);
```

### Cookie属性詳細

#### 1. HttpOnly

**目的**: JavaScriptからのアクセスを防止

**効果**:
- ✅ XSS攻撃によるトークン窃取を防止
- ❌ `document.cookie` でアクセス不可

#### 2. Secure

**目的**: HTTPS接続でのみCookieを送信

**効果**:
- ✅ 中間者攻撃（MITM）を防止
- ❌ HTTP接続ではCookieが送信されない

#### 3. SameSite

**目的**: CSRF攻撃を防止

**オプション**:

| 値 | 説明 | 使用ケース |
|----|------|----------|
| `Strict` | クロスサイトリクエストでCookieを送信しない | 最も厳格 |
| `Lax` | トップレベルナビゲーションのみCookieを送信 | デフォルト |
| `None` | すべてのリクエストでCookieを送信（Secure必須） | サードパーティAPI |

**推奨設定**:
```typescript
// 認証Cookie
SameSite=Strict  // CSRF完全防止

// トラッキングCookie
SameSite=None; Secure  // クロスサイト許可
```

#### 4. Path

**目的**: Cookieの有効範囲を制限

**例**:
```typescript
Path=/  // すべてのパスで有効
Path=/api  // /api 配下でのみ有効
```

#### 5. Domain

**目的**: Cookieの有効ドメインを指定

**例**:
```typescript
Domain=example.com  // example.com と *.example.com で有効
// Domain 未指定: 設定したドメインのみで有効
```

---

## XSS保護

### XSS の種類

1. **Stored XSS（格納型）**:
   - データベースに保存された悪意のあるスクリプト
   - 例: ユーザープロファイルに `<script>alert('XSS')</script>` を保存

2. **Reflected XSS（反射型）**:
   - URLパラメータからの悪意のあるスクリプト
   - 例: `?search=<script>alert('XSS')</script>`

3. **DOM-based XSS（DOM型）**:
   - クライアント側JavaScriptでの不適切なDOM操作

### XSS 対策

#### 1. 入力検証

**FastAPI バリデーション**:

```python
from pydantic import BaseModel, validator, Field
import re

class ProfileUpdate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    address: str = Field(..., max_length=200)

    @validator('name', 'address')
    def sanitize_html(cls, value):
        """Remove HTML tags"""
        # HTMLタグを除去
        clean = re.sub(r'<[^>]*>', '', value)
        # スクリプトタグを除去
        clean = re.sub(r'<script.*?</script>', '', clean, flags=re.DOTALL | re.IGNORECASE)
        return clean
```

#### 2. 出力エスケープ

**React での自動エスケープ**:

```tsx
// ✅ 自動エスケープ（安全）
<div>{userData.name}</div>

// ❌ dangerouslySetInnerHTML（危険）
<div dangerouslySetInnerHTML={{__html: userData.name}} />

// ✅ サニタイズライブラリ使用
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{__html: DOMPurify.sanitize(userData.name)}} />
```

#### 3. Content Security Policy

**厳格なCSP設定**:

```python
response.headers["Content-Security-Policy"] = (
    "default-src 'self'; "
    "script-src 'self'; "  # インラインスクリプト禁止
    "object-src 'none'; "  # プラグイン禁止
    "base-uri 'self'; "    # <base> タグ制限
)
```

---

## CSRF保護

### CSRF攻撃の仕組み

```
1. ユーザーが正規サイト（bank.com）にログイン
2. Cookieに認証情報が保存される
3. ユーザーが悪意のあるサイト（evil.com）を訪問
4. evil.com が bank.com へのリクエストを送信
   <form action="https://bank.com/transfer" method="POST">
     <input name="to" value="attacker@evil.com" />
     <input name="amount" value="10000" />
   </form>
   <script>document.forms[0].submit();</script>
5. ブラウザが自動的にCookieを送信
6. 不正送金が実行される
```

### CSRF 対策

#### 1. SameSite Cookie

**最も効果的な対策**:

```typescript
res.setHeader('Set-Cookie',
  `token=${token}; SameSite=Strict; HttpOnly; Secure`
);
```

#### 2. CSRFトークン

**実装例**:

```python
from fastapi import Depends, HTTPException, Header
import secrets

# CSRF トークン生成
def generate_csrf_token() -> str:
    return secrets.token_urlsafe(32)

# CSRF トークン検証
async def verify_csrf_token(
    x_csrf_token: str = Header(...)
) -> bool:
    # Redis からトークン取得
    stored_token = await redis.get(f"csrf:{x_csrf_token}")

    if not stored_token:
        raise HTTPException(status_code=403, detail="Invalid CSRF token")

    return True

# エンドポイント
@router.post("/transfer")
async def transfer(
    request: TransferRequest,
    csrf_valid: bool = Depends(verify_csrf_token)
):
    # 処理
    pass
```

#### 3. Referer / Origin ヘッダー検証

**実装例**:

```python
from fastapi import Request, HTTPException

async def verify_origin(request: Request):
    """Verify Origin or Referer header"""
    origin = request.headers.get("Origin")
    referer = request.headers.get("Referer")

    allowed_origins = [
        "https://app.example.com",
        "https://admin.example.com"
    ]

    if origin and origin not in allowed_origins:
        raise HTTPException(status_code=403, detail="Forbidden")

    if referer:
        referer_origin = "/".join(referer.split("/")[:3])
        if referer_origin not in allowed_origins:
            raise HTTPException(status_code=403, detail="Forbidden")

    return True
```

---

## セキュリティベストプラクティス

### 1. 開発環境と本番環境の分離

**開発環境**:
```python
if settings.ENV == "development":
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
```

**本番環境**:
```python
if settings.ENV == "production":
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS.split(","),
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
```

### 2. セキュリティヘッダーのテスト

**ツール**:
- [Mozilla Observatory](https://observatory.mozilla.org/)
- [Security Headers](https://securityheaders.com/)
- [OWASP ZAP](https://www.zaproxy.org/)

### 3. 定期的なレビュー

**チェック項目**:
- [ ] CORS設定が適切か
- [ ] すべてのセキュリティヘッダーが設定されているか
- [ ] Cookie属性が正しく設定されているか
- [ ] CSP違反がログに記録されているか

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [04-data-protection.md](./04-data-protection.md) - データ保護
- [05-network-security.md](./05-network-security.md) - ネットワークセキュリティ

---

**次のステップ**: [07-password-policy.md](./07-password-policy.md) を参照して、パスワードポリシーの詳細を確認してください。