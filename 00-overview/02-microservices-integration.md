# マイクロサービス連携

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [サービス間通信の原則](#サービス間通信の原則)
- [認証連携](#認証連携)
- [データ連携](#データ連携)
- [エラーハンドリング](#エラーハンドリング)
- [サービスディスカバリー](#サービスディスカバリー)
- [分散トランザクション](#分散トランザクション)

---

## 概要

ai-micro-serviceシステムでは、7つのマイクロサービスが協調動作します。各サービスは独立性を保ちながら、必要に応じて他のサービスと連携してエンドユーザーに価値を提供します。

### 連携の基本原則

1. **疎結合**: サービス間の依存を最小限に抑える
2. **同期通信**: HTTP/RESTによる同期的なリクエスト・レスポンス
3. **認証統一**: JWT方式による統一的な認証・認可
4. **データ自律性**: 各サービスが専用のデータベースを保有

---

## サービス間通信の原則

### 通信プロトコル

すべてのサービス間通信は **HTTP/1.1 REST API** で実装されています。

```yaml
プロトコル: HTTP/1.1
フォーマット: JSON
認証方式: JWT (Bearer Token)
エンコーディング: UTF-8
```

### 通信パターン

#### 1. BFF → Backend Services（プロキシパターン）

```
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │ GET /api/profile
       ▼
┌──────────────┐
│ User BFF     │
│ (Next.js)    │
└──────┬───────┘
       │ GET /profile
       │ Authorization: Bearer <JWT>
       ▼
┌──────────────┐
│ User API     │
│ (FastAPI)    │
└──────────────┘
```

**特徴**:
- BFFがリクエストをプロキシ
- CookieからJWTを抽出してAuthorizationヘッダーに付与
- レスポンスをそのまま返却、またはフォーマット変換

#### 2. Backend → Auth Service（JWKS取得パターン）

```
┌──────────────┐
│ User API     │
│ (FastAPI)    │
└──────┬───────┘
       │ GET /.well-known/jwks.json
       ▼
┌──────────────┐
│ Auth Service │
│ (FastAPI)    │
└──────────────┘
```

**特徴**:
- 各バックエンドサービスは起動時にJWKSを取得
- 定期的にJWKSを更新（TTL: 600秒）
- キャッシュして再利用

#### 3. Backend → Redis（キャッシュパターン）

```
┌──────────────┐
│ User API     │
└──────┬───────┘
       │ 1. GET profile:<user_id>
       ▼
┌──────────────┐      ┌──────────────┐
│ Redis        │      │ PostgreSQL   │
└──────┬───────┘      └──────────────┘
       │ Cache Miss
       └───────────────────────┐
                               │ 2. SELECT * FROM profiles
                               └────────────┐
                                            ▼
                               ┌──────────────┐
                               │ User API     │
                               └──────┬───────┘
                                      │ 3. SETEX profile:<user_id> 300
                                      ▼
                               ┌──────────────┐
                               │ Redis        │
                               └──────────────┘
```

**特徴**:
- Cache-Asideパターン
- キャッシュミス時にDBから取得してキャッシュ
- TTLによる自動無効化

---

## 認証連携

### JWT発行フロー

```mermaid
sequenceDiagram
    participant Client
    participant BFF
    participant AuthService
    participant PostgreSQL
    participant Redis

    Client->>BFF: POST /api/auth/login
    BFF->>AuthService: POST /auth/login
    AuthService->>PostgreSQL: SELECT * FROM users WHERE email=?
    PostgreSQL-->>AuthService: User record
    AuthService->>AuthService: Verify password (bcrypt)
    AuthService->>AuthService: Generate JWT (access + refresh)
    AuthService->>Redis: SET session:<session_id>
    Redis-->>AuthService: OK
    AuthService-->>BFF: JWT tokens
    BFF->>BFF: Set httpOnly cookies
    BFF-->>Client: Login success
```

### JWT検証フロー

```mermaid
sequenceDiagram
    participant BFF
    participant UserAPI
    participant AuthService
    participant Redis

    BFF->>UserAPI: GET /profile (Bearer JWT)
    UserAPI->>UserAPI: Decode JWT header
    alt JWKS cached
        UserAPI->>UserAPI: Verify JWT signature
    else JWKS not cached
        UserAPI->>AuthService: GET /.well-known/jwks.json
        AuthService-->>UserAPI: JWKS
        UserAPI->>Redis: SETEX jwks 600
        UserAPI->>UserAPI: Verify JWT signature
    end
    UserAPI->>UserAPI: Validate claims (exp, iss, aud)
    UserAPI->>Redis: CHECK token_blacklist:<jti>
    Redis-->>UserAPI: Not blacklisted
    UserAPI->>UserAPI: Extract user_id from JWT
```

### サービス間認証マトリクス

| 呼び出し元 | 呼び出し先 | 認証方法 | 必要なClaim |
|-----------|-----------|---------|------------|
| User BFF | Auth Service | なし（ログイン時） | - |
| User BFF | User API | JWT Bearer | sub, role |
| Admin BFF | Auth Service | なし（ログイン時） | - |
| Admin BFF | User API | JWT Bearer | sub, role=admin |
| Admin BFF | Admin API | JWT Bearer | sub, role=admin |
| User API | Auth Service | なし（JWKS取得） | - |
| Admin API | Auth Service | なし（JWKS取得） | - |

---

## データ連携

### データベース間の関連

各サービスは専用のデータベースを持ち、直接的なJOINは行いません。

```
┌─────────────────────┐
│ authdb              │
│ ┌─────────────────┐ │
│ │ users           │ │
│ │ - id (UUID)     │ │◄─── user_id参照（論理的）
│ │ - email         │ │
│ │ - password_hash │ │
│ │ - role          │ │
│ └─────────────────┘ │
└─────────────────────┘

┌─────────────────────┐
│ apidb               │
│ ┌─────────────────┐ │
│ │ profiles        │ │
│ │ - id (UUID)     │ │
│ │ - user_id (UUID)│ │──── authdb.users.id を参照（外部キーなし）
│ │ - first_name    │ │
│ │ - last_name     │ │
│ └─────────────────┘ │
└─────────────────────┘

┌─────────────────────┐
│ admindb             │
│ ┌─────────────────┐ │
│ │ documents       │ │
│ │ - id (UUID)     │ │
│ │ - uploaded_by   │ │──── authdb.users.id を参照（外部キーなし）
│ └─────────────────┘ │
└─────────────────────┘
```

**重要**: データベース間の整合性は**アプリケーションレベル**で管理されます。

### ユーザー登録時のデータ連携

```
1. Auth Service: authdb.users にユーザー作成
   ├─ id: UUID生成
   ├─ email: 入力値
   ├─ password_hash: bcryptでハッシュ化
   └─ role: "user" (デフォルト)

2. User API: apidb.profiles にプロフィール作成
   ├─ id: UUID生成
   ├─ user_id: authdb.users.id と同じUUID
   ├─ first_name: 入力値
   └─ last_name: 入力値
```

### プロフィール取得時のデータ連携

```
1. BFF: JWTからuser_idを抽出
2. User API:
   a. Redisキャッシュをチェック (key: profile:<user_id>)
   b. キャッシュミス: apidb.profiles から取得
   c. Redisにキャッシュ (TTL: 300秒)
3. User API: プロフィールを返却
```

### データ整合性の保証

#### ユーザー削除時のカスケード処理

```python
# Pseudo-code: User deletion flow
def delete_user(user_id: str):
    # Step 1: Mark user as deleted in authdb
    auth_service.soft_delete_user(user_id)

    # Step 2: Delete or anonymize profile in apidb
    user_api.delete_profile(user_id)

    # Step 3: Transfer or delete documents in admindb
    admin_api.transfer_documents(user_id, new_owner_id)

    # Step 4: Invalidate all tokens
    redis.add_to_blacklist(user_id)

    # Step 5: Clear all caches
    redis.delete(f"profile:{user_id}")
    redis.delete(f"session:{user_id}:*")
```

**課題**: このフローは非トランザクショナルで、部分的な失敗の可能性があります。

**将来の改善案**:
- Sagaパターンの導入
- イベントソーシング
- 補償トランザクション

---

## エラーハンドリング

### エラーレスポンスの標準化

すべてのサービスは以下の形式でエラーを返却します。

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid or expired token",
    "details": {
      "reason": "Token signature verification failed",
      "timestamp": "2025-09-30T12:34:56Z"
    }
  }
}
```

### HTTPステータスコードの使用

| ステータスコード | 用途 | 例 |
|----------------|------|---|
| 200 OK | 成功 | プロフィール取得成功 |
| 201 Created | リソース作成成功 | ユーザー登録成功 |
| 400 Bad Request | リクエスト不正 | バリデーションエラー |
| 401 Unauthorized | 認証失敗 | JWT無効または期限切れ |
| 403 Forbidden | 認可失敗 | 権限不足 |
| 404 Not Found | リソース不在 | ユーザーが見つからない |
| 409 Conflict | 競合 | メールアドレス重複 |
| 500 Internal Server Error | サーバーエラー | 予期しないエラー |
| 503 Service Unavailable | サービス利用不可 | DB接続エラー |

### エラー伝播

```
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │ GET /api/profile
       ▼
┌──────────────┐
│ User BFF     │
└──────┬───────┘
       │ GET /profile (Bearer JWT)
       ▼
┌──────────────┐
│ User API     │──┐ JWT検証失敗
└──────────────┘  │
       │           │
       ▼           │
  401 Unauthorized │
       │           │
       ▼           │
┌──────────────┐  │
│ User BFF     │◄─┘
│ - Log error  │
│ - Clear cookies (optional)
└──────┬───────┘
       │ 401 Unauthorized
       ▼
┌──────────────┐
│ User Browser │
│ → Redirect   │
│   to login   │
└──────────────┘
```

### リトライ戦略

| エラー種別 | リトライ | 戦略 |
|-----------|---------|-----|
| 401 Unauthorized | なし | ログイン画面へリダイレクト |
| 403 Forbidden | なし | エラーメッセージ表示 |
| 404 Not Found | なし | エラーメッセージ表示 |
| 500 Internal Server Error | 3回 | Exponential Backoff (1s, 2s, 4s) |
| 503 Service Unavailable | 3回 | Exponential Backoff (1s, 2s, 4s) |
| Network Error | 3回 | Exponential Backoff (1s, 2s, 4s) |

---

## サービスディスカバリー

### 静的設定方式

現在のシステムはDocker Composeによる静的設定を使用しています。

```yaml
# docker-compose.yml (概念例)
services:
  auth-service:
    hostname: auth-service
    ports:
      - "8002:8002"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/authdb
      - REDIS_URL=redis://:password@redis:6379

  user-api:
    hostname: user-api
    ports:
      - "8001:8001"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/apidb
      - REDIS_URL=redis://:password@redis:6379
      - JWKS_URL=http://auth-service:8002/.well-known/jwks.json
```

### サービスエンドポイント解決

| サービス名 | 開発環境 | Dockerコンテナ内 |
|-----------|---------|-----------------|
| Auth Service | http://localhost:8002 | http://auth-service:8002 |
| User API | http://localhost:8001 | http://user-api:8001 |
| Admin API | http://localhost:8003 | http://admin-api:8003 |
| PostgreSQL | localhost:5432 | postgres:5432 |
| Redis | localhost:6379 | redis:6379 |

### host.docker.internalの使用

BFF（Next.js）からバックエンドサービスを呼び出す際は `host.docker.internal` を使用します。

```typescript
// Frontend BFF API route
const response = await fetch(
  `http://host.docker.internal:8002/auth/login`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  }
);
```

**理由**: BFFコンテナから見てバックエンドはホストマシンで動作しているため。

---

## 分散トランザクション

### 現状: ベストエフォート方式

現在のシステムは、複数サービスにまたがるトランザクションを**厳密には**保証していません。

#### 例: ユーザー登録フロー

```
1. Auth Service: ユーザー作成 → 成功
2. User API: プロフィール作成 → 失敗（例: DB接続エラー）

結果: authdb.usersにユーザーは作成されたが、apidb.profilesは作成されず
     → データ不整合が発生
```

### 整合性保証の現在のアプローチ

#### 1. アプリケーションレベルのロールバック

```python
# Pseudo-code
def register_user(email, password, first_name, last_name):
    user_id = None
    try:
        # Step 1: Create user in authdb
        user_id = auth_service.create_user(email, password)

        # Step 2: Create profile in apidb
        user_api.create_profile(user_id, first_name, last_name)

        return {"user_id": user_id, "status": "success"}
    except Exception as e:
        # Rollback: Delete user if profile creation failed
        if user_id:
            auth_service.delete_user(user_id)
        raise e
```

**問題点**:
- ロールバック自体が失敗する可能性
- ネットワーク障害時の不整合

#### 2. 最終的整合性（Eventual Consistency）

プロフィールが作成されていない場合、次回アクセス時に自動作成する。

```python
def get_or_create_profile(user_id):
    profile = get_profile(user_id)
    if profile is None:
        # Profile not found, create default profile
        profile = create_default_profile(user_id)
    return profile
```

### 将来の改善案

#### 1. Sagaパターン

```
Saga: User Registration

Step 1: CreateUser
  - Success → Step 2
  - Failure → End with error

Step 2: CreateProfile
  - Success → Step 3
  - Failure → Compensate: DeleteUser

Step 3: SendWelcomeEmail
  - Success → End
  - Failure → Log warning (non-critical)
```

#### 2. イベントソーシング

```
Event Store:
  1. UserCreatedEvent (user_id, email, timestamp)
  2. ProfileCreatedEvent (user_id, first_name, last_name, timestamp)

State reconstruction:
  - All events applied → User is fully registered
  - Only UserCreatedEvent → Profile creation pending
```

#### 3. 2フェーズコミット（2PC）

分散トランザクションマネージャーの導入（重量級、パフォーマンス影響大）

---

## 関連ドキュメント

- [システム全体アーキテクチャ](./01-system-architecture.md)
- [サービス間通信](../08-integration/01-service-communication.md)
- [認証フロー統合](../08-integration/02-authentication-flow.md)
- [JWT検証フロー](../08-integration/04-jwt-verification.md)
- [データ整合性](../08-integration/05-data-consistency.md)
- [エラー伝播](../08-integration/06-error-propagation.md)

---

**最終更新**: 2025-09-30