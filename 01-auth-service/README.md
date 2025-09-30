# 01. 認証サービス（ai-micro-api-auth）

認証、JWT トークン発行・検証、ユーザー認証管理を担当するバックエンドサービスの設計ドキュメント。

## 📄 ドキュメント一覧

### 01. 認証サービス概要設計書
`01-overview.md`

認証サービスの責務、アーキテクチャ、技術スタックを説明します。

### 02. API仕様書
`02-api-specification.md`

認証関連のAPIエンドポイント仕様を定義します。

**主なエンドポイント**:
- `POST /auth/login` - ログイン
- `POST /auth/logout` - ログアウト
- `POST /auth/refresh` - トークンリフレッシュ
- `GET /.well-known/jwks.json` - JWKS公開鍵配信

### 03. JWT設計書
`03-jwt-design.md`

JWT トークンの仕様、クレーム構造、鍵管理を説明します。

**主な内容**:
- RS256 アルゴリズム
- トークンクレーム（iss, aud, sub, role等）
- アクセストークン・リフレッシュトークンの有効期限
- 鍵ローテーション戦略

### 04. データベース設計書（authdb）
`04-database-design.md`

認証情報を格納する authdb の設計を説明します。

**主なテーブル**:
- `users` - ユーザー認証情報（email, password_hash, role等）

### 05. セキュリティ実装設計書
`05-security-implementation.md`

認証サービス固有のセキュリティ実装を説明します。

**主な内容**:
- パスワードハッシュ化（bcrypt/argon2）
- トークンブラックリスト管理
- レート制限
- CORS設定

## 🔐 サービスの責務

1. **ユーザー認証**: ログイン・ログアウト処理
2. **JWT発行**: アクセストークン・リフレッシュトークンの発行
3. **JWKS公開**: 他サービスが検証に使用する公開鍵の配信
4. **トークン管理**: トークンの失効・ブラックリスト管理
5. **セッション管理**: Redisを使用したセッション管理

## 🔗 連携サービス

- **PostgreSQL（authdb）**: 認証情報の永続化
- **Redis**: セッション管理、トークンブラックリスト
- **User Frontend BFF**: ログイン・ログアウトリクエストの受信
- **Admin Frontend BFF**: 管理者ログインリクエストの受信
- **User API・Admin API**: JWKS経由でのトークン検証

## 📊 図表ファイル

`diagrams/` ディレクトリには以下の図が含まれます:

- `authentication-flow.png` - 認証フロー図
- `token-lifecycle.png` - トークンライフサイクル図
- `authdb-er-diagram.png` - authdb ER図

## 🎯 このセクションを読むべき人

- **バックエンド開発者**: 認証ロジックを実装・修正する場合
- **セキュリティ担当者**: 認証セキュリティを確認する場合
- **フロントエンド開発者**: 認証フローを理解する場合
- **インフラ担当者**: 認証サービスのデプロイを行う場合

## 🔗 関連ドキュメント

- [08-integration/02-authentication-flow.md](../08-integration/) - 認証フロー統合版
- [09-api-contracts/](../09-api-contracts/) - API仕様詳細
- [10-security/](../10-security/) - セキュリティ全体方針
- [06-database/04-authdb-schema.md](../06-database/) - authdb詳細

---

**Port**: 8002
**Technology**: FastAPI (Python)
**Database**: PostgreSQL (authdb) + Redis