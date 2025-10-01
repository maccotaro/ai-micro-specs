# 環境変数一覧

## Auth Service

```bash
# データベース
DATABASE_URL=postgresql://user:password@host:5432/authdb

# Redis
REDIS_URL=redis://:password@host:6379

# JWT
JWT_ISS=https://auth.example.com
JWT_AUD=fastapi-api
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=15
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7

# ログ
LOG_LEVEL=INFO
```

## User API Service

```bash
# データベース
DATABASE_URL=postgresql://user:password@host:5432/apidb

# Redis
REDIS_URL=redis://:password@host:6379

# JWT検証
JWKS_URL=http://auth-service:8002/.well-known/jwks.json

# ログ
LOG_LEVEL=INFO
```

## Admin API Service

```bash
# データベース
DATABASE_URL=postgresql://user:password@host:5432/admindb

# Redis
REDIS_URL=redis://:password@host:6379

# JWT検証
JWKS_URL=http://auth-service:8002/.well-known/jwks.json

# S3
S3_BUCKET=documents
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret

# OCR
GOOGLE_APPLICATION_CREDENTIALS=/app/keys/gcp-credentials.json
```

## User Frontend

```bash
# バックエンドAPI
AUTH_SERVER_URL=http://auth-service:8002
API_SERVER_URL=http://user-service:8001

# JWT
JWT_SECRET=your-jwt-secret-key

# Next.js
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.example.com
```

## Admin Frontend

```bash
# バックエンドAPI
AUTH_SERVER_URL=http://auth-service:8002
API_SERVER_URL=http://user-service:8001
ADMIN_API_URL=http://admin-service:8003

# JWT
JWT_SECRET=your-jwt-secret-key

# Next.js
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.example.com
```

## .env ファイル管理

### .env.example

```bash
cp .env.example .env
# .env を編集
```

### .gitignore

```
.env
.env.*
!.env.example
```

## 環境別設定

### Development

```bash
DATABASE_URL=postgresql://postgres:password@localhost:5432/authdb
LOG_LEVEL=DEBUG
```

### Production

```bash
DATABASE_URL=${DATABASE_URL}  # 環境変数から取得
LOG_LEVEL=INFO
```

---

**関連**: [Docker Compose](./02-docker-compose.md), [本番デプロイ](./05-production-deployment.md)