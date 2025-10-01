# ログインシーケンス図

```mermaid
sequenceDiagram
    participant Browser as User Browser
    participant UFE as User Frontend<br/>(Next.js :3002)
    participant AuthAPI as Auth Service<br/>(:8002)
    participant UserAPI as User API<br/>(:8001)
    participant AuthDB as authdb
    participant ApiDB as apidb
    participant Redis as Redis

    Note over Browser,Redis: フロントエンド起動・初期化

    Browser->>UFE: 1. ページアクセス<br/>http://localhost:3002
    UFE->>UFE: Cookie確認
    alt Cookieなし
        UFE-->>Browser: ログイン画面表示
    else Cookie有効
        UFE->>UserAPI: GET /api/profile
        UserAPI-->>UFE: profile data
        UFE-->>Browser: ダッシュボード表示
    end

    Note over Browser,Redis: ログインフロー

    Browser->>UFE: 2. ログインフォーム送信<br/>{username, password}
    UFE->>UFE: バリデーション

    UFE->>AuthAPI: POST http://auth-service:8002/login<br/>Content-Type: application/json<br/>{username, password}

    AuthAPI->>AuthDB: SELECT * FROM users<br/>WHERE username = $1
    AuthDB-->>AuthAPI: user {id, password_hash, role}

    AuthAPI->>AuthAPI: bcrypt.verify(password, password_hash)

    alt 認証成功
        AuthAPI->>AuthAPI: JWT生成<br/>- access_token (15min)<br/>- refresh_token (7day)

        AuthAPI->>Redis: SET session:{user_id}<br/>value: {username, role}<br/>TTL: 3600

        AuthAPI-->>UFE: 200 OK<br/>{<br/>  access_token,<br/>  refresh_token,<br/>  user: {id, username, role}<br/>}

        UFE->>UFE: Cookie保存<br/>httpOnly, secure<br/>- access_token<br/>- refresh_token

        Note over Browser,Redis: プロファイル取得

        UFE->>UserAPI: GET http://user-service:8001/profile<br/>Authorization: Bearer {access_token}

        UserAPI->>AuthAPI: GET http://auth-service:8002/.well-known/jwks.json
        AuthAPI-->>UserAPI: {keys: [{kty, n, e, ...}]}

        UserAPI->>UserAPI: JWT検証<br/>RS256署名確認

        UserAPI->>Redis: GET profile:{user_id}
        alt キャッシュヒット
            Redis-->>UserAPI: cached profile
        else キャッシュミス
            UserAPI->>ApiDB: SELECT * FROM profiles<br/>WHERE user_id = $1
            ApiDB-->>UserAPI: profile data
            UserAPI->>Redis: SETEX profile:{user_id}<br/>TTL: 300
        end

        UserAPI-->>UFE: 200 OK<br/>{profile: {firstName, lastName, ...}}

        UFE-->>Browser: ダッシュボード表示<br/>Welcome, {firstName}!

    else 認証失敗
        AuthAPI-->>UFE: 401 Unauthorized<br/>{error: "Invalid credentials"}
        UFE-->>Browser: エラーメッセージ表示
    end
```

## シーケンスの詳細

### 1. 初期アクセス (0-1秒)
- ブラウザがフロントエンドにアクセス
- Cookie確認で既存セッションをチェック
- 未ログインならログイン画面表示

### 2. ログイン処理 (1-2秒)
- **フロントエンド**: 入力バリデーション
- **Auth Service**: ユーザー認証、JWT生成
- **Redis**: セッション保存（1時間TTL）
- **フロントエンド**: JWT をhttpOnly Cookieに保存

### 3. JWT検証 (200-500ms)
- **User API**: Auth ServiceからJWKS取得
- **User API**: JWT署名検証（RS256）
- JWKSはキャッシュして再利用

### 4. プロファイル取得 (50-200ms)
- **Redis**: キャッシュ確認（5分TTL）
- キャッシュミス時のみDB検索
- 取得後はRedisにキャッシュ

## タイミング

```
ログインボタンクリック
    ↓ (100ms) バリデーション
Auth Service呼び出し
    ↓ (500ms) DB検索・JWT生成
JWT Cookie保存
    ↓ (50ms)
User API呼び出し
    ↓ (200ms) JWT検証・プロファイル取得
ダッシュボード表示
-----------
合計: ~850ms
```

## エラーハンドリング

### 認証エラー
```
401 Unauthorized → ログイン画面にリダイレクト
```

### タイムアウト
```
503 Service Unavailable → リトライまたはエラー表示
```

### ネットワークエラー
```
Network Error → オフライン表示
```

---

**関連ドキュメント**:
- [認証フロー統合](../02-authentication-flow.md)
- [サービス間通信](../01-service-communication.md)
- [JWT検証フロー](./jwt-verification-flow.md)