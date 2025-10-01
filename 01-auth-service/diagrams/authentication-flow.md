# 認証フロー図

```mermaid
sequenceDiagram
    participant User as User
    participant Frontend as Frontend<br/>(Next.js)
    participant AuthAPI as Auth Service<br/>(FastAPI)
    participant DB as authdb<br/>(PostgreSQL)
    participant Redis as Redis

    Note over User,Redis: ユーザー登録フロー

    User->>Frontend: 1. 登録フォーム送信
    Frontend->>AuthAPI: POST /register<br/>{username, email, password}

    AuthAPI->>AuthAPI: バリデーション
    AuthAPI->>AuthAPI: パスワードハッシュ化<br/>(bcrypt)
    AuthAPI->>DB: INSERT INTO users
    DB-->>AuthAPI: user created (id, username, email)
    AuthAPI-->>Frontend: 201 Created<br/>{id, username, email}
    Frontend-->>User: 登録完了

    Note over User,Redis: ログインフロー

    User->>Frontend: 2. ログインフォーム送信
    Frontend->>AuthAPI: POST /login<br/>{username, password}

    AuthAPI->>DB: SELECT user WHERE username = ?
    DB-->>AuthAPI: user {id, username, password_hash, role}

    AuthAPI->>AuthAPI: パスワード検証<br/>bcrypt.verify(password, password_hash)

    alt パスワード一致
        AuthAPI->>AuthAPI: JWT生成<br/>- access_token (15分)<br/>- refresh_token (7日)

        AuthAPI->>Redis: SET session:{user_id}<br/>TTL: 3600秒

        AuthAPI-->>Frontend: 200 OK<br/>{access_token, refresh_token, user}
        Frontend->>Frontend: Cookie保存<br/>(httpOnly, secure)
        Frontend-->>User: ログイン成功
    else パスワード不一致
        AuthAPI-->>Frontend: 401 Unauthorized
        Frontend-->>User: ログイン失敗
    end

    Note over User,Redis: トークンリフレッシュフロー

    User->>Frontend: 3. アクセストークン期限切れ
    Frontend->>AuthAPI: POST /refresh<br/>Authorization: Bearer refresh_token

    AuthAPI->>AuthAPI: refresh_token検証

    alt トークン有効
        AuthAPI->>Redis: GET blacklist:{jti}
        Redis-->>AuthAPI: null (not blacklisted)

        AuthAPI->>AuthAPI: 新しいaccess_token生成
        AuthAPI-->>Frontend: 200 OK<br/>{access_token}
        Frontend->>Frontend: Cookie更新
        Frontend-->>User: 継続利用可能
    else トークン無効/期限切れ
        AuthAPI-->>Frontend: 401 Unauthorized
        Frontend-->>User: 再ログイン要求
    end

    Note over User,Redis: ログアウトフロー

    User->>Frontend: 4. ログアウト
    Frontend->>AuthAPI: POST /logout<br/>Authorization: Bearer access_token

    AuthAPI->>AuthAPI: トークン検証・JTI抽出
    AuthAPI->>Redis: SET blacklist:{jti}<br/>TTL: token有効期限
    AuthAPI->>Redis: DEL session:{user_id}

    AuthAPI-->>Frontend: 200 OK
    Frontend->>Frontend: Cookie削除
    Frontend-->>User: ログアウト完了
```

## フローの詳細

### 1. ユーザー登録
- パスワードをbcryptでハッシュ化
- authdbにユーザー情報を保存
- パスワードは平文で保存しない

### 2. ログイン
- ユーザー名でDB検索
- bcryptでパスワード検証
- JWT生成（RS256署名）
- Redisにセッション保存

### 3. トークンリフレッシュ
- refresh_tokenで新しいaccess_token取得
- ブラックリスト確認
- 無効なトークンは拒否

### 4. ログアウト
- トークンをブラックリストに追加
- セッション削除
- フロントエンドのCookie削除

## セキュリティ対策

- パスワードハッシュ化（bcrypt、rounds=12）
- JWT署名（RS256）
- httpOnly Cookie（XSS対策）
- Token Blacklist（ログアウト確実化）
- セッションタイムアウト（1時間）

---

**関連ドキュメント**:
- [JWT設計](../03-jwt-design.md)
- [セキュリティ実装](../05-security-implementation.md)
- [認証フロー統合](../../08-integration/02-authentication-flow.md)