# 認証API仕様

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [ベースURL](#ベースurl)
- [共通仕様](#共通仕様)
- [認証エンドポイント](#認証エンドポイント)
- [JWKSエンドポイント](#jwksエンドポイント)
- [エラーレスポンス](#エラーレスポンス)
- [レート制限](#レート制限)

---

## 概要

認証サービスは、JWT方式による認証機能を提供するRESTful APIです。全てのエンドポイントはJSON形式でデータをやり取りします。

### API バージョニング

- 現行バージョン: `v1`
- パス: `/api/v1`
- バージョニング戦略: URLパスベース

---

## ベースURL

### 開発環境
```
http://localhost:8002
```

### Docker環境（サービス間通信）
```
http://host.docker.internal:8002
```

### 本番環境（例）
```
https://auth.example.com
```

---

## 共通仕様

### リクエストヘッダー

```http
Content-Type: application/json
Accept: application/json
```

認証が必要なエンドポイント:
```http
Authorization: Bearer {access_token}
```

### レスポンス形式

成功レスポンス:
```json
{
  "status": "success",
  "data": { ... },
  "message": "Operation completed successfully"
}
```

エラーレスポンス:
```json
{
  "status": "error",
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": { ... }
  }
}
```

### HTTPステータスコード

| コード | 意味 | 使用例 |
|-------|------|--------|
| 200 | OK | 成功 |
| 201 | Created | ユーザー登録成功 |
| 400 | Bad Request | バリデーションエラー |
| 401 | Unauthorized | 認証失敗 |
| 403 | Forbidden | 権限不足 |
| 404 | Not Found | リソース不存在 |
| 409 | Conflict | メールアドレス重複 |
| 422 | Unprocessable Entity | バリデーションエラー |
| 429 | Too Many Requests | レート制限超過 |
| 500 | Internal Server Error | サーバーエラー |

---

## 認証エンドポイント

### 1. ユーザー登録

新規ユーザーアカウントを作成します。

#### エンドポイント
```
POST /api/v1/auth/register
```

#### リクエストボディ

```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "role": "user"
}
```

**フィールド説明**:
- `email` (string, required): メールアドレス（一意制約）
- `password` (string, required): パスワード（最低8文字、英数字記号混在推奨）
- `role` (string, optional): ユーザーロール（デフォルト: "user"）
  - 使用可能な値: "user", "admin"

#### レスポンス

**成功時（201 Created）**:
```json
{
  "status": "success",
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "role": "user",
    "created_at": "2025-09-30T10:00:00Z"
  },
  "message": "User registered successfully"
}
```

**エラー時（409 Conflict）**:
```json
{
  "status": "error",
  "error": {
    "code": "EMAIL_ALREADY_EXISTS",
    "message": "Email address is already registered",
    "details": {
      "email": "user@example.com"
    }
  }
}
```

**エラー時（422 Unprocessable Entity）**:
```json
{
  "status": "error",
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": {
      "password": ["Password must be at least 8 characters"]
    }
  }
}
```

#### 実装例（Python）

```python
import httpx

async def register_user(email: str, password: str, role: str = "user"):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://localhost:8002/api/v1/auth/register",
            json={
                "email": email,
                "password": password,
                "role": role
            }
        )
        return response.json()
```

---

### 2. ログイン

認証情報を検証し、JWTトークンペアを発行します。

#### エンドポイント
```
POST /api/v1/auth/login
```

#### リクエストボディ

```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**フィールド説明**:
- `email` (string, required): メールアドレス
- `password` (string, required): パスワード

#### レスポンス

**成功時（200 OK）**:
```json
{
  "status": "success",
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 900,
    "user": {
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@example.com",
      "role": "user"
    }
  },
  "message": "Login successful"
}
```

**フィールド説明**:
- `access_token`: アクセストークン（有効期限: 15分）
- `refresh_token`: リフレッシュトークン（有効期限: 7日）
- `token_type`: トークンタイプ（常に "Bearer"）
- `expires_in`: アクセストークンの有効期限（秒）
- `user`: ユーザー基本情報

**エラー時（401 Unauthorized）**:
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Invalid email or password",
    "details": {}
  }
}
```

#### 実装例（TypeScript）

```typescript
interface LoginResponse {
  status: string;
  data: {
    access_token: string;
    refresh_token: string;
    token_type: string;
    expires_in: number;
    user: {
      user_id: string;
      email: string;
      role: string;
    };
  };
  message: string;
}

async function login(email: string, password: string): Promise<LoginResponse> {
  const response = await fetch('http://localhost:8002/api/v1/auth/login', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });

  return response.json();
}
```

---

### 3. トークンリフレッシュ

有効なリフレッシュトークンを使用して、新しいアクセストークンを取得します。

#### エンドポイント
```
POST /api/v1/auth/refresh
```

#### リクエストボディ

```json
{
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**フィールド説明**:
- `refresh_token` (string, required): 有効なリフレッシュトークン

#### レスポンス

**成功時（200 OK）**:
```json
{
  "status": "success",
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 900
  },
  "message": "Token refreshed successfully"
}
```

**エラー時（401 Unauthorized）**:
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_REFRESH_TOKEN",
    "message": "Refresh token is invalid or expired",
    "details": {}
  }
}
```

**エラー時（403 Forbidden）**:
```json
{
  "status": "error",
  "error": {
    "code": "TOKEN_BLACKLISTED",
    "message": "Token has been revoked",
    "details": {}
  }
}
```

#### 実装例（Python）

```python
async def refresh_access_token(refresh_token: str):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://localhost:8002/api/v1/auth/refresh",
            json={"refresh_token": refresh_token}
        )
        return response.json()
```

---

### 4. ログアウト

トークンを無効化し、セッションを破棄します。

#### エンドポイント
```
POST /api/v1/auth/logout
```

#### リクエストヘッダー

```http
Authorization: Bearer {access_token}
```

#### リクエストボディ

```json
{
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**フィールド説明**:
- `refresh_token` (string, optional): 無効化するリフレッシュトークン

#### レスポンス

**成功時（200 OK）**:
```json
{
  "status": "success",
  "data": {},
  "message": "Logout successful"
}
```

**エラー時（401 Unauthorized）**:
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_TOKEN",
    "message": "Invalid or expired access token",
    "details": {}
  }
}
```

#### 実装例（TypeScript）

```typescript
async function logout(accessToken: string, refreshToken?: string): Promise<void> {
  await fetch('http://localhost:8002/api/v1/auth/logout', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
}
```

---

### 5. トークン検証（内部用）

トークンの有効性を検証します（主にサービス間通信で使用）。

#### エンドポイント
```
POST /api/v1/auth/verify
```

#### リクエストボディ

```json
{
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

#### レスポンス

**成功時（200 OK）**:
```json
{
  "status": "success",
  "data": {
    "valid": true,
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "role": "user",
    "exp": 1727694000
  },
  "message": "Token is valid"
}
```

**エラー時（401 Unauthorized）**:
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_TOKEN",
    "message": "Token is invalid or expired",
    "details": {
      "valid": false
    }
  }
}
```

---

## JWKSエンドポイント

### JWT検証用公開鍵取得

JWT検証に使用する公開鍵をJSON Web Key Set形式で提供します。

#### エンドポイント
```
GET /.well-known/jwks.json
```

#### リクエストパラメータ

なし（認証不要）

#### レスポンス

**成功時（200 OK）**:
```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "kid": "auth-service-key-1",
      "alg": "RS256",
      "n": "xGOr-H7A-PWmZHFqRyh9nWuHQGl7...",
      "e": "AQAB"
    }
  ]
}
```

**フィールド説明**:
- `kty`: 鍵タイプ（"RSA"）
- `use`: 使用用途（"sig" = 署名）
- `kid`: キーID（識別子）
- `alg`: アルゴリズム（"RS256"）
- `n`: RSA公開鍵の係数（Base64URL）
- `e`: RSA公開鍵の指数（Base64URL）

#### キャッシング

- ブラウザキャッシュ: 1時間
- CDNキャッシュ: 1時間
- サービス側キャッシュ: 永続（キーローテーション時にのみ更新）

#### 実装例（Python）

```python
from jose import jwt, jwk
import httpx

async def get_jwks() -> dict:
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "http://localhost:8002/.well-known/jwks.json"
        )
        return response.json()

async def verify_token(token: str) -> dict:
    jwks = await get_jwks()
    # トークン検証処理
    header = jwt.get_unverified_header(token)
    key = next(k for k in jwks["keys"] if k["kid"] == header["kid"])

    return jwt.decode(
        token,
        key,
        algorithms=["RS256"],
        audience="fastapi-api"
    )
```

---

## エラーレスポンス

### エラーコード一覧

| コード | HTTPステータス | 説明 |
|--------|---------------|------|
| VALIDATION_ERROR | 422 | 入力データのバリデーションエラー |
| EMAIL_ALREADY_EXISTS | 409 | メールアドレスが既に登録済み |
| INVALID_CREDENTIALS | 401 | メールアドレスまたはパスワードが不正 |
| INVALID_TOKEN | 401 | トークンが無効または期限切れ |
| INVALID_REFRESH_TOKEN | 401 | リフレッシュトークンが無効 |
| TOKEN_BLACKLISTED | 403 | トークンが無効化済み |
| USER_NOT_FOUND | 404 | ユーザーが存在しない |
| RATE_LIMIT_EXCEEDED | 429 | レート制限超過 |
| INTERNAL_SERVER_ERROR | 500 | サーバー内部エラー |

### エラー処理の推奨パターン

```typescript
async function handleApiCall<T>(apiCall: () => Promise<T>): Promise<T> {
  try {
    return await apiCall();
  } catch (error) {
    if (error.response) {
      const { status, data } = error.response;

      switch (status) {
        case 401:
          // トークンリフレッシュまたは再ログイン
          break;
        case 429:
          // リトライ処理（指数バックオフ）
          break;
        case 500:
          // エラーログ送信、フォールバック処理
          break;
        default:
          // その他のエラーハンドリング
      }
    }
    throw error;
  }
}
```

---

## レート制限

### 制限内容（計画中）

| エンドポイント | 制限 | ウィンドウ |
|--------------|------|----------|
| POST /login | 5回 | 5分 |
| POST /register | 3回 | 1時間 |
| POST /refresh | 10回 | 1分 |
| POST /logout | 10回 | 1分 |

### レート制限ヘッダー

レスポンスに以下のヘッダーが含まれます：

```http
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 3
X-RateLimit-Reset: 1727694000
```

### レート制限超過時のレスポンス

```json
{
  "status": "error",
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please try again later.",
    "details": {
      "retry_after": 180
    }
  }
}
```

---

## 関連ドキュメント

- [認証サービス概要](./01-overview.md)
- [JWT設計](./03-jwt-design.md)
- [セキュリティ実装](./05-security-implementation.md)
- [APIコントラクト一覧](../09-api-contracts/02-interface-matrix.md)
- [OpenAPI統合](../09-api-contracts/04-openapi-integration.md)