# User API Service - API仕様書

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [API概要](#api概要)
- [認証](#認証)
- [エンドポイント一覧](#エンドポイント一覧)
- [データモデル](#データモデル)
- [エラーレスポンス](#エラーレスポンス)
- [使用例](#使用例)

---

## API概要

User API Serviceは、ユーザープロファイル情報のCRUD操作を提供するRESTful APIです。

### ベースURL

```
http://localhost:8001
```

### コンテンツタイプ

```
Content-Type: application/json
```

### 認証方式

JWT Bearer Token認証（RS256）

---

## 認証

### 認証ヘッダー

プロファイル関連の全エンドポイントは、以下の認証ヘッダーが必須です。

```http
Authorization: Bearer <JWT_TOKEN>
```

### JWT検証

- **署名アルゴリズム**: RS256
- **JWKS取得先**: `http://host.docker.internal:8002/.well-known/jwks.json`
- **必須クレーム**:
  - `iss`: `https://auth.example.com`
  - `aud`: `fastapi-api`
  - `sub`: ユーザーID（UUID形式）
  - `exp`: 有効期限（Unix timestamp）

### 認証エラー

| ステータスコード | 理由 |
|--------------|------|
| 401 Unauthorized | トークンが無効または期限切れ |
| 403 Forbidden | 認証ヘッダーが存在しない |

---

## エンドポイント一覧

### サマリー

| メソッド | エンドポイント | 認証 | 説明 |
|---------|--------------|------|------|
| GET | `/` | 不要 | サービス情報 |
| GET | `/healthz` | 不要 | ヘルスチェック |
| GET | `/profile` | 必須 | プロファイル取得 |
| POST | `/profile` | 必須 | プロファイル作成/更新 |
| PUT | `/profile` | 必須 | プロファイル更新 |

---

## エンドポイント詳細

### 1. GET / - サービス情報

サービスの基本情報を返します。

#### リクエスト

```http
GET / HTTP/1.1
Host: localhost:8001
```

#### レスポンス

**200 OK**

```json
{
  "message": "User Profile API is running"
}
```

---

### 2. GET /healthz - ヘルスチェック

サービスの稼働状態とインフラ接続状態を確認します。

#### リクエスト

```http
GET /healthz HTTP/1.1
Host: localhost:8001
```

#### レスポンス

**200 OK（正常時）**

```json
{
  "status": "healthy",
  "database": "ok",
  "redis": "ok"
}
```

**503 Service Unavailable（異常時）**

```json
{
  "status": "unhealthy",
  "database": "error",
  "redis": "ok"
}
```

#### チェック項目

1. **Database**: PostgreSQL接続確認（`SELECT 1`クエリ）
2. **Redis**: Redis接続確認（`PING`コマンド）

---

### 3. GET /profile - プロファイル取得

現在認証されているユーザーのプロファイル情報を取得します。

#### リクエスト

```http
GET /profile HTTP/1.1
Host: localhost:8001
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### レスポンス

**200 OK**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": "東京都渋谷区1-2-3",
  "phone": "090-1234-5678",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T15:30:00Z"
}
```

#### 動作仕様

1. **キャッシュチェック**: Redis キャッシュ `cache:profile:{user_id}` を確認
2. **キャッシュヒット**: キャッシュから即座に返却（TTL: 300秒）
3. **キャッシュミス**: データベースから取得
4. **自動作成**: プロファイルが存在しない場合、空のプロファイルを自動作成
5. **メール取得**: Auth Service の `/auth/me` からメール情報を取得
6. **キャッシュ保存**: 取得したプロファイルをRedisにキャッシュ

#### パフォーマンス

- キャッシュヒット時: ~50ms
- キャッシュミス時: ~200ms
- Auth Service連携含む: ~500ms

---

### 4. POST /profile - プロファイル作成/更新

プロファイルを作成または更新します（Upsert操作）。

#### リクエスト

```http
POST /profile HTTP/1.1
Host: localhost:8001
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": "東京都渋谷区1-2-3",
  "phone": "090-1234-5678"
}
```

#### リクエストボディ（ProfileCreate）

| フィールド | 型 | 必須 | 説明 |
|-----------|----|----|------|
| `first_name` | string | 任意 | 名前 |
| `last_name` | string | 任意 | 姓 |
| `name` | string | 任意 | フルネーム |
| `address` | string | 任意 | 住所 |
| `phone` | string | 任意 | 電話番号 |

**注意**: 全フィールドが任意です。未指定フィールドは更新されません（PATCH的動作）。

#### レスポンス

**200 OK**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": "東京都渋谷区1-2-3",
  "phone": "090-1234-5678",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T16:00:00Z"
}
```

#### 動作仕様

1. **既存プロファイル確認**: `user_id` でプロファイルを検索
2. **更新処理**: 既存プロファイルがあれば、指定フィールドのみ更新
3. **作成処理**: 既存プロファイルがなければ新規作成
4. **タイムスタンプ**: `updated_at` を現在時刻に更新
5. **キャッシュ削除**: `cache:profile:{user_id}` を削除
6. **メール取得**: Auth Service から最新のメール情報を取得

---

### 5. PUT /profile - プロファイル更新

既存のプロファイルを更新します（プロファイルが存在しない場合はエラー）。

#### リクエスト

```http
PUT /profile HTTP/1.1
Host: localhost:8001
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "phone": "090-9876-5432",
  "address": "大阪府大阪市北区4-5-6"
}
```

#### リクエストボディ（ProfileUpdate）

| フィールド | 型 | 必須 | 説明 |
|-----------|----|----|------|
| `first_name` | string | 任意 | 名前 |
| `last_name` | string | 任意 | 姓 |
| `name` | string | 任意 | フルネーム |
| `address` | string | 任意 | 住所 |
| `phone` | string | 任意 | 電話番号 |

**動作**: 指定されたフィールドのみ更新（PATCH的動作）。

#### レスポンス

**200 OK**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": "大阪府大阪市北区4-5-6",
  "phone": "090-9876-5432",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T16:30:00Z"
}
```

**404 Not Found（プロファイルが存在しない）**

```json
{
  "detail": "Profile not found"
}
```

#### 動作仕様

1. **既存プロファイル確認**: `user_id` でプロファイルを検索
2. **404エラー**: プロファイルが存在しない場合はエラー
3. **部分更新**: 指定されたフィールドのみ更新
4. **タイムスタンプ**: `updated_at` を現在時刻に更新
5. **キャッシュ削除**: `cache:profile:{user_id}` を削除
6. **メール取得**: Auth Service から最新のメール情報を取得

---

## データモデル

### ProfileResponse

プロファイル取得時のレスポンス形式。

| フィールド | 型 | NULL可 | 説明 |
|-----------|----|----|------|
| `id` | UUID | 不可 | プロファイルID |
| `user_id` | UUID | 不可 | ユーザーID（Auth Service連携） |
| `email` | string | 不可 | メールアドレス（Auth Serviceから取得） |
| `first_name` | string | 可 | 名前 |
| `last_name` | string | 可 | 姓 |
| `name` | string | 可 | フルネーム |
| `address` | string | 可 | 住所 |
| `phone` | string | 可 | 電話番号 |
| `created_at` | datetime | 不可 | 作成日時（ISO 8601形式） |
| `updated_at` | datetime | 不可 | 更新日時（ISO 8601形式） |

### ProfileCreate / ProfileUpdate

プロファイル作成・更新時のリクエストボディ。

| フィールド | 型 | 必須 | 説明 |
|-----------|----|----|------|
| `first_name` | string | 任意 | 名前 |
| `last_name` | string | 任意 | 姓 |
| `name` | string | 任意 | フルネーム |
| `address` | string | 任意 | 住所 |
| `phone` | string | 任意 | 電話番号 |

**注意**: 全フィールドが任意です。`exclude_unset=True` により、未指定フィールドは更新されません。

---

## エラーレスポンス

### 標準エラー形式

```json
{
  "detail": "エラーメッセージ"
}
```

### エラーコード一覧

| ステータスコード | 理由 | 対処方法 |
|--------------|------|---------|
| 400 Bad Request | リクエストボディが不正 | リクエスト形式を確認 |
| 401 Unauthorized | JWTトークンが無効 | トークンを再取得 |
| 403 Forbidden | 認証ヘッダーなし | Authorizationヘッダーを追加 |
| 404 Not Found | プロファイルが存在しない（PUTのみ） | POSTで作成するか、GETで確認 |
| 500 Internal Server Error | サーバー内部エラー | ログを確認、管理者に連絡 |
| 503 Service Unavailable | インフラ接続失敗 | PostgreSQL/Redis接続確認 |

---

## 使用例

### 1. プロファイル取得（初回アクセス）

```bash
# リクエスト
curl -X GET http://localhost:8001/profile \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

# レスポンス（自動作成された空プロファイル）
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": null,
  "last_name": null,
  "name": null,
  "address": null,
  "phone": null,
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T10:00:00Z"
}
```

### 2. プロファイル作成

```bash
# リクエスト
curl -X POST http://localhost:8001/profile \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "太郎",
    "last_name": "山田",
    "name": "山田 太郎",
    "phone": "090-1234-5678"
  }'

# レスポンス
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": null,
  "phone": "090-1234-5678",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T10:05:00Z"
}
```

### 3. 部分更新（電話番号のみ変更）

```bash
# リクエスト
curl -X PUT http://localhost:8001/profile \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "090-9876-5432"
  }'

# レスポンス（他のフィールドは変更されない）
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": null,
  "phone": "090-9876-5432",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T10:10:00Z"
}
```

### 4. ヘルスチェック

```bash
# リクエスト
curl http://localhost:8001/healthz

# レスポンス（正常時）
{
  "status": "healthy",
  "database": "ok",
  "redis": "ok"
}
```

---

## 統合テスト例

### シーケンステスト

```bash
#!/bin/bash
BASE_URL="http://localhost:8001"
TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

# 1. ヘルスチェック
echo "=== Health Check ==="
curl -s $BASE_URL/healthz | jq

# 2. 初回プロファイル取得（自動作成）
echo "=== Get Profile (First Time) ==="
curl -s -X GET $BASE_URL/profile \
  -H "Authorization: Bearer $TOKEN" | jq

# 3. プロファイル更新
echo "=== Update Profile ==="
curl -s -X POST $BASE_URL/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "太郎",
    "last_name": "山田",
    "phone": "090-1234-5678"
  }' | jq

# 4. プロファイル再取得（キャッシュヒット）
echo "=== Get Profile (Cached) ==="
curl -s -X GET $BASE_URL/profile \
  -H "Authorization: Bearer $TOKEN" | jq

# 5. 部分更新
echo "=== Partial Update ==="
curl -s -X PUT $BASE_URL/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "address": "東京都渋谷区1-2-3"
  }' | jq

# 6. 最終確認
echo "=== Final Check ==="
curl -s -X GET $BASE_URL/profile \
  -H "Authorization: Bearer $TOKEN" | jq
```

---

## パフォーマンス考慮事項

### キャッシュ戦略

1. **GET /profile**: キャッシュファーストで高速化（TTL: 300秒）
2. **POST/PUT /profile**: 更新時にキャッシュを削除して整合性確保
3. **キャッシュキー形式**: `cache:profile:{user_id}`

### レスポンスタイム目標

| シナリオ | 目標レスポンスタイム |
|---------|------------------|
| キャッシュヒット（GET） | < 50ms |
| キャッシュミス（GET） | < 200ms |
| Auth Service連携含む | < 500ms |
| 更新処理（POST/PUT） | < 300ms |

---

## セキュリティ考慮事項

### JWT検証

- RS256署名検証（JWKS経由）
- `iss`, `aud`, `exp` クレームの検証
- トークン改ざん防止

### アクセス制御

- プロファイルは所有ユーザーのみアクセス可能
- `user_id` クレームによる自動フィルタリング

### データ保護

- パスワード等の機密情報は管理しない
- HTTPS通信推奨（本番環境）
- CORS設定で許可オリジンを制限（本番環境）

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [データベース設計](./03-database-design.md)
- [データ整合性](./04-data-consistency.md)
- [APIインターフェース定義](/09-api-contracts/01-overview.md)
- [TypeScript型定義](/09-api-contracts/05-typescript-types.md)