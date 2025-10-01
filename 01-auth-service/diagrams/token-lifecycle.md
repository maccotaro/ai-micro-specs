# トークンライフサイクル図

```mermaid
stateDiagram-v2
    [*] --> TokenGeneration: ログイン成功

    state TokenGeneration {
        [*] --> CreateAccessToken
        CreateAccessToken --> CreateRefreshToken
        CreateRefreshToken --> SaveToRedis
        SaveToRedis --> [*]
    }

    TokenGeneration --> Active: トークン発行

    state Active {
        [*] --> Valid
        Valid --> InUse: API呼び出し
        InUse --> Valid: 検証成功
        Valid --> NearExpiry: 有効期限近い
    }

    Active --> Refreshing: refresh_token使用

    state Refreshing {
        [*] --> ValidateRefreshToken
        ValidateRefreshToken --> CheckBlacklist
        CheckBlacklist --> IssueNewAccessToken
        IssueNewAccessToken --> [*]
    }

    Refreshing --> Active: 新access_token発行

    Active --> Expired: 有効期限切れ
    Active --> Blacklisted: ログアウト
    Active --> Revoked: 管理者による無効化

    Expired --> [*]: 再ログイン必要
    Blacklisted --> [*]: 使用不可
    Revoked --> [*]: 使用不可
```

## トークンの状態

### 1. Token Generation (生成)
- **access_token**: 有効期限15分
- **refresh_token**: 有効期限7日
- Redisにセッション保存（TTL: 1時間）

### 2. Active (有効)
- JWT検証成功
- 有効期限内
- ブラックリストに未登録

### 3. Near Expiry (期限間近)
- 残り有効期限が5分未満
- フロントエンドで自動リフレッシュ推奨

### 4. Refreshing (リフレッシュ中)
- refresh_tokenで新access_token取得
- ブラックリスト確認
- 新トークン発行

### 5. Expired (期限切れ)
- 有効期限超過
- 401 Unauthorized
- 再ログインまたはリフレッシュ必要

### 6. Blacklisted (ブラックリスト登録)
- ログアウト時に登録
- 使用不可
- Redis TTL: 元の有効期限まで

### 7. Revoked (取り消し)
- 管理者による強制無効化
- セキュリティインシデント時

## トークンタイムライン

```mermaid
gantt
    title JWT Token Lifecycle
    dateFormat  YYYY-MM-DD HH:mm

    section Access Token
    生成                :2024-01-01 10:00, 1m
    有効期間            :2024-01-01 10:01, 15m
    期限切れ            :milestone, 2024-01-01 10:16, 0m

    section Refresh Token
    生成                :2024-01-01 10:00, 1m
    有効期間            :2024-01-01 10:01, 7d
    期限切れ            :milestone, 2024-01-08 10:01, 0m

    section Session
    Redis保存           :2024-01-01 10:00, 1h
    セッション期限      :milestone, 2024-01-01 11:00, 0m
```

## トークン検証フロー

```mermaid
flowchart TD
    Start([トークン受信]) --> ExtractToken[トークン抽出]
    ExtractToken --> VerifySignature{署名検証}

    VerifySignature -->|失敗| Invalid[401 Invalid Token]
    VerifySignature -->|成功| CheckExpiry{有効期限確認}

    CheckExpiry -->|期限切れ| Expired[401 Token Expired]
    CheckExpiry -->|有効| CheckBlacklist{ブラックリスト確認}

    CheckBlacklist -->|登録あり| Blacklisted[401 Token Blacklisted]
    CheckBlacklist -->|登録なし| ValidToken[✓ 検証成功]

    Invalid --> End([終了])
    Expired --> End
    Blacklisted --> End
    ValidToken --> End

    style ValidToken fill:#c8e6c9
    style Invalid fill:#ffcdd2
    style Expired fill:#ffcdd2
    style Blacklisted fill:#ffcdd2
```

## トークン管理戦略

### Access Token
- **有効期限**: 15分
- **用途**: API認証
- **保存場所**: httpOnly Cookie
- **リフレッシュ**: 自動（期限間近時）

### Refresh Token
- **有効期限**: 7日
- **用途**: access_token再発行
- **保存場所**: httpOnly Cookie
- **ローテーション**: 使用時に新規発行推奨

### Blacklist（Redis）
- **キー**: `blacklist:{jti}`
- **TTL**: トークン元の有効期限
- **用途**: ログアウト時の無効化

### Session（Redis）
- **キー**: `session:{user_id}`
- **TTL**: 3600秒（1時間）
- **用途**: アクティブセッション管理

---

**関連ドキュメント**:
- [JWT設計](../03-jwt-design.md)
- [認証フロー](./authentication-flow.md)
- [Redis使用](../../07-redis/03-auth-service-usage.md)