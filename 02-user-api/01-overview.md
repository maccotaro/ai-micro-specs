# User API Service 概要

**カテゴリ**: Backend Service
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [サービス概要](#サービス概要)
- [責務と役割](#責務と役割)
- [アーキテクチャ](#アーキテクチャ)
- [技術スタック](#技術スタック)
- [主要機能](#主要機能)
- [関連サービス](#関連サービス)

---

## サービス概要

User API Service (`ai-micro-api-user`) は、ユーザープロファイル情報の管理を専門とするマイクロサービスです。認証サービスから独立して動作し、ユーザーの個人情報（名前、住所、電話番号など）のCRUD操作を提供します。

### 基本情報

| 項目 | 内容 |
|------|------|
| サービス名 | User API Service |
| リポジトリ | `ai-micro-api-user/` |
| コンテナ名 | `ai-micro-api-user` |
| ポート | 8001 (外部) → 8000 (内部) |
| フレームワーク | FastAPI |
| 言語 | Python 3.11+ |
| データベース | PostgreSQL (`apidb`) |
| キャッシュ | Redis |

---

## 責務と役割

### 主要責務

1. **プロファイル管理**
   - ユーザープロファイルの作成・取得・更新
   - プロファイルデータの永続化
   - プロファイル情報のキャッシュ管理

2. **認証サービス連携**
   - JWT トークンの検証（JWKS経由）
   - 認証サービスからのメール情報取得
   - トークンベースのユーザー識別

3. **データ整合性**
   - `user_id` による認証サービスとの疎結合連携
   - プロファイル更新時のキャッシュ無効化
   - タイムスタンプの自動管理

4. **ヘルスチェック**
   - データベース接続状態の監視
   - Redis接続状態の監視
   - サービス稼働状態の公開

### 責務範囲外

- ユーザー認証処理（Auth Serviceの責務）
- パスワード管理（Auth Serviceの責務）
- 管理者向け機能（Admin API Serviceの責務）
- ドキュメント処理（Admin API Serviceの責務）

---

## アーキテクチャ

### サービス位置付け

```
┌─────────────────┐      ┌─────────────────┐
│ User Frontend   │      │ Admin Frontend  │
│   (Port 3002)   │      │   (Port 3003)   │
└────────┬────────┘      └────────┬────────┘
         │                        │
         └────────┬───────────────┘
                  │ HTTP/REST
         ┌────────▼────────┐
         │  User API       │
         │  (Port 8001)    │ ← このサービス
         └────────┬────────┘
                  │
      ┌───────────┼───────────┐
      │           │           │
┌─────▼─────┐ ┌──▼──────┐ ┌─▼───────────┐
│ PostgreSQL│ │  Redis  │ │Auth Service │
│  (apidb)  │ │(Cache)  │ │  (JWKS)     │
└───────────┘ └─────────┘ └─────────────┘
```

### ディレクトリ構造

```
ai-micro-api-user/
├── app/
│   ├── main.py                 # FastAPIエントリーポイント
│   ├── core/                   # コア機能
│   │   ├── config.py          # 設定管理
│   │   ├── security.py        # JWT認証
│   │   └── cache.py           # Redisキャッシュ
│   ├── models/                # データモデル
│   │   └── profile.py         # Profileモデル
│   ├── routers/               # APIエンドポイント
│   │   ├── profile.py         # プロファイルAPI
│   │   ├── health.py          # ヘルスチェック
│   │   └── documents.py       # ドキュメント連携
│   ├── db/                    # データベース
│   │   └── session.py         # DB接続管理
│   └── utils/                 # ユーティリティ
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── init.sql                   # DB初期化スクリプト
```

---

## 技術スタック

### コア技術

| カテゴリ | 技術 | バージョン | 用途 |
|---------|------|-----------|------|
| Framework | FastAPI | 0.104.1 | Webフレームワーク |
| Language | Python | 3.11+ | 実装言語 |
| ORM | SQLAlchemy | 2.x | データベースORM |
| Validation | Pydantic | 2.x | データバリデーション |
| Container | Docker | - | コンテナ化 |

### データストア

| 種類 | 製品 | 用途 |
|------|------|------|
| Primary DB | PostgreSQL 15 | プロファイルデータ永続化 |
| Cache | Redis 7 | プロファイルキャッシュ |

### 認証・セキュリティ

| 技術 | 用途 |
|------|------|
| JWT (RS256) | トークンベース認証 |
| JWKS | 公開鍵検証 |
| CORS | クロスオリジン制御 |

### 主要依存ライブラリ

```txt
fastapi              # Webフレームワーク
uvicorn              # ASGIサーバー
sqlalchemy           # ORM
psycopg2-binary      # PostgreSQLドライバ
redis                # Redisクライアント
pyjwt[crypto]        # JWT処理
requests             # HTTP通信（Auth Service連携）
python-dotenv        # 環境変数管理
```

---

## 主要機能

### 1. プロファイル管理API

#### GET /profile
- **機能**: 現在のユーザーのプロファイル取得
- **認証**: JWT必須
- **キャッシュ**: あり（TTL: 300秒）
- **自動作成**: プロファイルが存在しない場合は空プロファイルを作成

#### POST /profile
- **機能**: プロファイル作成または更新
- **認証**: JWT必須
- **動作**: 既存プロファイルがあれば更新、なければ作成
- **キャッシュ**: 更新時にキャッシュ削除

#### PUT /profile
- **機能**: プロファイル更新
- **認証**: JWT必須
- **動作**: 既存プロファイル必須（404エラー）
- **キャッシュ**: 更新時にキャッシュ削除

### 2. ヘルスチェック

#### GET /healthz
- **機能**: サービス稼働状態確認
- **認証**: 不要
- **チェック項目**:
  - PostgreSQL接続状態
  - Redis接続状態
- **レスポンス**:
  ```json
  {
    "status": "healthy",
    "database": "ok",
    "redis": "ok"
  }
  ```

### 3. ルートエンドポイント

#### GET /
- **機能**: サービス情報表示
- **認証**: 不要
- **レスポンス**: `{"message": "User Profile API is running"}`

---

## 関連サービス

### 依存サービス

| サービス | 依存理由 | 接続先 |
|---------|---------|-------|
| Auth Service | JWT検証（JWKS）、メール情報取得 | `http://host.docker.internal:8002` |
| PostgreSQL | プロファイルデータ永続化 | `postgresql://host.docker.internal:5432/apidb` |
| Redis | プロファイルキャッシュ | `redis://host.docker.internal:6379` |

### 利用サービス

| サービス | 利用方法 |
|---------|---------|
| User Frontend | プロファイル管理機能で使用 |
| Admin Frontend | ユーザー情報表示で使用 |

### サービス間通信

1. **User Frontend → User API**
   - プロファイル取得・更新リクエスト
   - JWTトークンをBearerヘッダで送信

2. **User API → Auth Service**
   - JWKS取得（JWT検証用）
   - `/auth/me` でメール情報取得

3. **User API → PostgreSQL**
   - プロファイルデータのCRUD操作

4. **User API → Redis**
   - プロファイルキャッシュの読み書き
   - キー形式: `cache:profile:{user_id}`

---

## 環境変数

### 必須設定

```env
# Database
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/apidb

# Redis
REDIS_URL=redis://:password@host.docker.internal:6379

# Auth Service Integration
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
JWT_ISS=https://auth.example.com
JWT_AUD=fastapi-api

# Cache Settings
PROFILE_CACHE_TTL_SEC=300

# Logging
LOG_LEVEL=INFO
```

---

## 起動方法

### Docker Compose使用

```bash
cd ai-micro-api-user
docker compose up -d

# ログ確認
docker compose logs -f ai-micro-api-user

# サービス確認
curl http://localhost:8001/
curl http://localhost:8001/healthz
```

### ローカル開発

```bash
cd ai-micro-api-user

# 依存関係インストール
pip install -r requirements.txt

# 開発サーバー起動
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

---

## パフォーマンス特性

### キャッシュ戦略

| 操作 | キャッシュ動作 | TTL |
|------|-------------|-----|
| GET /profile | キャッシュヒット優先 | 300秒 |
| POST /profile | キャッシュ削除 | - |
| PUT /profile | キャッシュ削除 | - |

### レスポンスタイム目標

- キャッシュヒット時: < 50ms
- キャッシュミス時: < 200ms
- 認証サービス連携含む: < 500ms

---

## セキュリティ

### 認証・認可

- 全プロファイルエンドポイントでJWT必須
- RS256署名検証（JWKS経由）
- `user_id` クレームによるユーザー識別

### データ保護

- パスワードなどの機密情報は管理しない（Auth Serviceの責務）
- プロファイルデータは当該ユーザーのみアクセス可能
- CORS設定で許可オリジンを制御（本番環境では要変更）

---

## 監視・ロギング

### ログ出力

```python
# リクエストログ（全エンドポイント）
Request started - request_id: {uuid}, method: GET, url: /profile

# 完了ログ（処理時間含む）
Request completed - request_id: {uuid}, user_id: {uuid},
  endpoint: /profile, status: 200, process_time: 0.1234s

# エラーログ
Unhandled exception - request_id: {uuid}, error: {message}
```

### ヘルスチェック

```bash
# 正常時
$ curl http://localhost:8001/healthz
{"status":"healthy","database":"ok","redis":"ok"}

# 異常時（503エラー）
{"status":"unhealthy","database":"error","redis":"ok"}
```

---

## トラブルシューティング

### よくある問題

1. **401 Unauthorized**
   - JWTトークンが無効または期限切れ
   - JWKS_URLが正しく設定されていない

2. **503 Service Unavailable（ヘルスチェック）**
   - PostgreSQL接続失敗 → DATABASE_URL確認
   - Redis接続失敗 → REDIS_URL、パスワード確認

3. **キャッシュが効かない**
   - Redis接続を確認
   - `PROFILE_CACHE_TTL_SEC` が0になっていないか確認

---

## 今後の拡張予定

- [ ] プロファイル画像アップロード機能
- [ ] プロファイル項目のカスタマイズ機能
- [ ] プロファイル変更履歴の記録
- [ ] Admin APIによるプロファイル一覧・検索機能

---

## 関連ドキュメント

- [API仕様詳細](./02-api-specification.md)
- [データベース設計](./03-database-design.md)
- [データ整合性](./04-data-consistency.md)
- [認証フロー統合](/08-integration/02-authentication-flow.md)
- [システム全体アーキテクチャ](/00-overview/01-system-architecture.md)