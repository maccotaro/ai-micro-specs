# サービス間通信図

```mermaid
sequenceDiagram
    participant User as User Browser
    participant UFE as User Frontend
    participant AuthAPI as Auth Service
    participant UserAPI as User API
    participant Redis as Redis Cache
    participant AuthDB as authdb
    participant ApiDB as apidb

    Note over User,ApiDB: ユーザー登録・ログインフロー

    User->>UFE: 1. ユーザー登録<br/>(username, email, password)
    UFE->>AuthAPI: POST /register
    AuthAPI->>AuthDB: INSERT users
    AuthDB-->>AuthAPI: user created
    AuthAPI-->>UFE: 201 Created
    UFE-->>User: 登録完了

    User->>UFE: 2. ログイン<br/>(username, password)
    UFE->>AuthAPI: POST /login
    AuthAPI->>AuthDB: SELECT user
    AuthDB-->>AuthAPI: user data
    AuthAPI->>AuthAPI: パスワード検証
    AuthAPI->>AuthAPI: JWT生成
    AuthAPI->>Redis: SET session
    AuthAPI-->>UFE: access_token, refresh_token
    UFE->>UFE: Cookie保存
    UFE-->>User: ログイン成功

    Note over User,ApiDB: プロファイル取得フロー

    User->>UFE: 3. プロファイル表示
    UFE->>UserAPI: GET /profile<br/>Authorization: Bearer token
    UserAPI->>AuthAPI: GET /.well-known/jwks.json
    AuthAPI-->>UserAPI: JWT公開鍵
    UserAPI->>UserAPI: JWT検証

    UserAPI->>Redis: GET profile:user_id
    alt キャッシュヒット
        Redis-->>UserAPI: cached profile
    else キャッシュミス
        UserAPI->>ApiDB: SELECT profiles
        ApiDB-->>UserAPI: profile data
        UserAPI->>Redis: SET profile:user_id
    end

    UserAPI-->>UFE: profile data
    UFE-->>User: プロファイル表示

    Note over User,ApiDB: プロファイル更新フロー

    User->>UFE: 4. プロファイル更新
    UFE->>UserAPI: PUT /profile<br/>Authorization: Bearer token
    UserAPI->>UserAPI: JWT検証
    UserAPI->>ApiDB: UPDATE profiles
    ApiDB-->>UserAPI: updated
    UserAPI->>Redis: DEL profile:user_id
    UserAPI-->>UFE: updated profile
    UFE-->>User: 更新完了

    Note over User,ApiDB: ログアウトフロー

    User->>UFE: 5. ログアウト
    UFE->>AuthAPI: POST /logout<br/>Authorization: Bearer token
    AuthAPI->>Redis: SET blacklist:jti
    AuthAPI-->>UFE: 200 OK
    UFE->>UFE: Cookie削除
    UFE-->>User: ログアウト完了
```

## 通信パターン

### 1. 同期HTTP通信
- フロントエンド → バックエンドAPI
- バックエンドAPI間（JWT検証）

### 2. データベースアクセス
- Auth Service → authdb
- User API → apidb
- Admin API → admindb

### 3. キャッシュアクセス
- 全APIサービス → Redis
- セッション、JWT、プロファイルデータ

### 4. JWT検証フロー
- User/Admin API → Auth Service (JWKS)
- 公開鍵取得・キャッシュ

## 通信プロトコル

- **HTTP/REST**: フロントエンド ↔ バックエンド
- **PostgreSQL Protocol**: API ↔ Database
- **Redis Protocol**: API ↔ Redis

---

**関連ドキュメント**:
- [サービス間通信](../../08-integration/01-service-communication.md)
- [認証フロー](../../08-integration/02-authentication-flow.md)