# インフラ構成

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [コンテナ構成](#コンテナ構成)
- [ネットワーク構成](#ネットワーク構成)
- [ストレージ構成](#ストレージ構成)
- [環境設定](#環境設定)
- [リソース割り当て](#リソース割り当て)
- [デプロイメント](#デプロイメント)
- [モニタリング](#モニタリング)

---

## 概要

ai-micro-serviceシステムは、Dockerコンテナベースのインフラストラクチャ上で動作します。各サービスは独立したコンテナとして実行され、Docker Composeによってオーケストレーションされます。

### インフラストラクチャの特徴

- **コンテナ化**: すべてのサービスがDockerコンテナとして実行
- **分散構成**: 各サービスが独自のdocker-compose.ymlを持つ
- **ポータビリティ**: 開発・本番環境での一貫性
- **スケーラビリティ**: 水平スケーリングが容易

---

## コンテナ構成

### サービス一覧とコンテナ仕様

| サービス名 | コンテナ名 | ベースイメージ | 公開ポート | 内部ポート |
|-----------|-----------|--------------|----------|-----------|
| User Frontend BFF | ai-micro-front-user | node:20-alpine | 3002 | 3000 |
| Admin Frontend BFF | ai-micro-front-admin | node:20-alpine | 3003 | 3000 |
| Auth Service | ai-micro-api-auth | python:3.11-slim | 8002 | 8000 |
| User API | ai-micro-api-user | python:3.11-slim | 8001 | 8000 |
| Admin API | ai-micro-api-admin | python:3.11-slim | 8003 | 8000 |
| PostgreSQL | postgres | postgres:15-alpine | 5432 | 5432 |
| Redis | redis | redis:7-alpine | 6379 | 6379 |

### コンテナの起動順序

```
1. PostgreSQL  (データベース初期化)
2. Redis       (キャッシュ準備)
3. Auth Service (認証サービス起動、JWKSエンドポイント公開)
4. User API    (JWKS取得、準備完了)
5. Admin API   (JWKS取得、準備完了)
6. User Frontend BFF (バックエンド接続確認)
7. Admin Frontend BFF (バックエンド接続確認)
```

**依存関係**:

```yaml
depends_on:
  user-api:
    - auth-service
    - postgres
    - redis
  auth-service:
    - postgres
    - redis
  user-frontend:
    - auth-service
    - user-api
```

### Docker Composeファイル構成

各サービスディレクトリに専用の`docker-compose.yml`が配置されています。

```
ai-micro-service/
├── ai-micro-postgres/
│   └── docker-compose.yml       # PostgreSQL定義
├── ai-micro-redis/
│   └── docker-compose.yml       # Redis定義
├── ai-micro-api-auth/
│   └── docker-compose.yml       # Auth Service定義
├── ai-micro-api-user/
│   └── docker-compose.yml       # User API定義
├── ai-micro-api-admin/
│   └── docker-compose.yml       # Admin API定義
├── ai-micro-front-user/
│   └── docker-compose.yml       # User Frontend定義
└── ai-micro-front-admin/
    └── docker-compose.yml       # Admin Frontend定義
```

---

## ネットワーク構成

### Docker ネットワーク

各サービスはDockerのブリッジネットワークを使用して通信します。

```
┌────────────────────────────────────────────────────────────┐
│                    Docker Bridge Network                    │
│                    (ai-micro-network)                       │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ User Frontend│  │ Admin Frontend│ │ Auth Service │    │
│  │ 172.20.0.2   │  │ 172.20.0.3   │  │ 172.20.0.4   │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ User API     │  │ Admin API    │  │ PostgreSQL   │    │
│  │ 172.20.0.5   │  │ 172.20.0.6   │  │ 172.20.0.10  │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                             │
│  ┌──────────────┐                                          │
│  │ Redis        │                                          │
│  │ 172.20.0.11  │                                          │
│  └──────────────┘                                          │
└────────────────────────────────────────────────────────────┘
         │                    │                    │
         │                    │                    │
    ┌────▼────────────────────▼────────────────────▼────┐
    │           Host Machine (macOS/Linux)             │
    │   localhost:3002 → 172.20.0.2:3000              │
    │   localhost:8002 → 172.20.0.4:8000              │
    └──────────────────────────────────────────────────┘
```

### ネットワークの作成

```bash
# 共有ネットワークの作成（オプション）
docker network create ai-micro-network
```

### サービス間通信のエンドポイント

| 呼び出し元 | 呼び出し先 | エンドポイント |
|-----------|-----------|--------------|
| User Frontend | Auth Service | http://host.docker.internal:8002 |
| User Frontend | User API | http://host.docker.internal:8001 |
| Admin Frontend | Auth Service | http://host.docker.internal:8002 |
| Admin Frontend | User API | http://host.docker.internal:8001 |
| Admin Frontend | Admin API | http://host.docker.internal:8003 |
| User API | Auth Service | http://host.docker.internal:8002 |
| Admin API | Auth Service | http://host.docker.internal:8002 |
| All Services | PostgreSQL | host.docker.internal:5432 |
| All Services | Redis | host.docker.internal:6379 |

**Note**: `host.docker.internal` はホストマシンのlocalhostを指します。

### ポートマッピング

```yaml
# User Frontend BFF
ports:
  - "3002:3000"  # ホスト:コンテナ

# Auth Service
ports:
  - "8002:8000"

# PostgreSQL
ports:
  - "5432:5432"

# Redis
ports:
  - "6379:6379"
```

---

## ストレージ構成

### Dockerボリューム

永続化が必要なデータはDockerボリュームで管理されます。

```
┌────────────────────────────────────────────────────┐
│ Docker Volumes                                     │
│                                                    │
│  ┌───────────────────────────┐                    │
│  │ postgres-data             │                    │
│  │ /var/lib/postgresql/data  │                    │
│  │                           │                    │
│  │ - authdb                  │                    │
│  │ - apidb                   │                    │
│  │ - admindb                 │                    │
│  └───────────────────────────┘                    │
│                                                    │
│  ┌───────────────────────────┐                    │
│  │ redis-data                │                    │
│  │ /data                     │                    │
│  │                           │                    │
│  │ - dump.rdb (persistence)  │                    │
│  └───────────────────────────┘                    │
│                                                    │
│  ┌───────────────────────────┐                    │
│  │ admin-uploads             │                    │
│  │ /app/uploads              │                    │
│  │                           │                    │
│  │ - documents/              │                    │
│  │ - images/                 │                    │
│  └───────────────────────────┘                    │
└────────────────────────────────────────────────────┘
```

### ボリューム定義例

```yaml
# PostgreSQL
volumes:
  - postgres-data:/var/lib/postgresql/data

# Redis
volumes:
  - redis-data:/data

# Admin API
volumes:
  - admin-uploads:/app/uploads

volumes:
  postgres-data:
    driver: local
  redis-data:
    driver: local
  admin-uploads:
    driver: local
```

### バックアップ戦略

#### PostgreSQLバックアップ

```bash
# データベースダンプ
docker exec postgres pg_dump -U postgres authdb > backup/authdb_$(date +%Y%m%d).sql
docker exec postgres pg_dump -U postgres apidb > backup/apidb_$(date +%Y%m%d).sql
docker exec postgres pg_dump -U postgres admindb > backup/admindb_$(date +%Y%m%d).sql

# ボリュームバックアップ
docker run --rm -v postgres-data:/data -v $(pwd)/backup:/backup \
  alpine tar czf /backup/postgres-data-$(date +%Y%m%d).tar.gz /data
```

#### Redisバックアップ

```bash
# RDBスナップショット
docker exec redis redis-cli SAVE

# ボリュームバックアップ
docker run --rm -v redis-data:/data -v $(pwd)/backup:/backup \
  alpine tar czf /backup/redis-data-$(date +%Y%m%d).tar.gz /data
```

---

## 環境設定

### 環境変数の管理

各サービスは`.env`ファイルで環境変数を管理します。

#### Auth Service (.env)

```bash
# Database
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/authdb

# Redis
REDIS_URL=redis://:password@host.docker.internal:6379
REDIS_PASSWORD=your-redis-password

# JWT Configuration
JWT_ISS=https://auth.example.com
JWT_AUD=fastapi-api
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=15
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7

# Security
SECRET_KEY=your-secret-key-change-in-production

# Service
PORT=8000
HOST=0.0.0.0
```

#### User API (.env)

```bash
# Database
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/apidb

# Redis
REDIS_URL=redis://:password@host.docker.internal:6379

# JWKS
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json

# Service
PORT=8000
HOST=0.0.0.0
```

#### Frontend (.env.local)

```bash
# Backend Services
AUTH_SERVER_URL=http://host.docker.internal:8002
API_SERVER_URL=http://host.docker.internal:8001

# JWT
JWT_SECRET=your-jwt-secret-key-change-in-production

# Next.js
NEXTAUTH_URL=http://localhost:3002
NEXTAUTH_SECRET=your-nextauth-secret
```

### 環境別設定

| 環境 | 設定ファイル | 特徴 |
|-----|------------|------|
| Development | .env.development | デバッグ有効、詳細ログ |
| Staging | .env.staging | 本番に近い設定、テストデータ |
| Production | .env.production | 最適化、最小ログ、セキュリティ強化 |

---

## リソース割り当て

### コンテナリソース制限

```yaml
# PostgreSQL
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
    reservations:
      cpus: '1.0'
      memory: 1G

# Redis
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 512M
    reservations:
      cpus: '0.5'
      memory: 256M

# FastAPI Services
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 512M

# Next.js Frontends
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 512M
```

### システム要件

#### 開発環境

- **CPU**: 4コア以上推奨
- **メモリ**: 8GB以上推奨
- **ストレージ**: 20GB以上の空き容量
- **Docker**: 20.10以上
- **Docker Compose**: 2.0以上

#### 本番環境

- **CPU**: 8コア以上推奨
- **メモリ**: 16GB以上推奨
- **ストレージ**: 100GB以上（ログ・データ含む）
- **ネットワーク**: 1Gbps以上

---

## デプロイメント

### ローカル開発環境のセットアップ

```bash
# 1. インフラサービスの起動
cd ai-micro-postgres && docker compose up -d
cd ../ai-micro-redis && docker compose up -d

# 2. バックエンドサービスの起動
cd ../ai-micro-api-auth && docker compose up -d
cd ../ai-micro-api-user && docker compose up -d
cd ../ai-micro-api-admin && docker compose up -d

# 3. フロントエンドサービスの起動
cd ../ai-micro-front-user && docker compose up -d
cd ../ai-micro-front-admin && docker compose up -d

# 4. ステータス確認
docker ps
```

### 全サービスの停止

```bash
# 逆順で停止
cd ai-micro-front-admin && docker compose down
cd ../ai-micro-front-user && docker compose down
cd ../ai-micro-api-admin && docker compose down
cd ../ai-micro-api-user && docker compose down
cd ../ai-micro-api-auth && docker compose down
cd ../ai-micro-redis && docker compose down
cd ../ai-micro-postgres && docker compose down
```

### ログの確認

```bash
# リアルタイムログ
docker compose logs -f <service-name>

# 最新100行
docker compose logs --tail=100 <service-name>

# 特定の時間範囲
docker compose logs --since 2025-09-30T00:00:00 <service-name>
```

---

## モニタリング

### ヘルスチェック

各サービスはヘルスチェックエンドポイントを提供します。

```yaml
# Auth Service Health Check
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### メトリクス収集（将来実装）

```
┌──────────────┐
│ Prometheus   │◄───┐
│ (Metrics DB) │    │
└──────┬───────┘    │
       │            │
       │ Scrape     │ Expose /metrics
       │            │
       ▼            │
┌──────────────┐   │
│ Grafana      │   │
│ (Dashboard)  │   │
└──────────────┘   │
                   │
        ┌──────────┴────────────┬──────────┐
        │                       │          │
   ┌────▼──────┐          ┌────▼────┐  ┌──▼─────┐
   │ Auth      │          │ User    │  │ Admin  │
   │ Service   │          │ API     │  │ API    │
   └───────────┘          └─────────┘  └────────┘
```

### ログ集約（将来実装）

```
┌──────────────┐
│ All Services │
│ (Container   │
│  logs)       │
└──────┬───────┘
       │
       │ stdout/stderr
       ▼
┌──────────────┐
│ Fluentd      │
│ (Log         │
│  Collector)  │
└──────┬───────┘
       │
       │ Forward
       ▼
┌──────────────┐
│ Elasticsearch│
│ (Log Store)  │
└──────┬───────┘
       │
       │ Query
       ▼
┌──────────────┐
│ Kibana       │
│ (Log UI)     │
└──────────────┘
```

---

## 関連ドキュメント

- [システム全体アーキテクチャ](./01-system-architecture.md)
- [技術スタック](./04-technology-stack.md)
- [運用ガイド](../11-operations/01-startup-procedure.md)
- [デプロイガイド](../13-deployment/01-deployment-overview.md)
- [モニタリング](../11-operations/03-monitoring.md)

---

**最終更新**: 2025-09-30