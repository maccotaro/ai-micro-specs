# Docker Compose設定

## docker-compose.yml

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass password
    ports:
      - "6379:6379"

  auth-service:
    build: ./ai-micro-api-auth
    ports:
      - "8002:8002"
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/authdb
      REDIS_URL: redis://:password@redis:6379
    depends_on:
      - postgres
      - redis

  user-service:
    build: ./ai-micro-api-user
    ports:
      - "8001:8001"
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/apidb
      REDIS_URL: redis://:password@redis:6379
    depends_on:
      - postgres
      - redis

  user-frontend:
    build: ./ai-micro-front-user
    ports:
      - "3002:3000"
    environment:
      AUTH_SERVER_URL: http://auth-service:8002
      API_SERVER_URL: http://user-service:8001
    depends_on:
      - auth-service
      - user-service

  admin-frontend:
    build: ./ai-micro-front-admin
    ports:
      - "3003:3000"
    environment:
      AUTH_SERVER_URL: http://auth-service:8002
      API_SERVER_URL: http://user-service:8001
      ADMIN_API_URL: http://admin-service:8003
    depends_on:
      - auth-service
      - user-service
      - admin-service

volumes:
  postgres_data:
```

## コマンド

```bash
# 起動 (バックグラウンド)
docker compose up -d

# 特定サービスのみ起動
docker compose up -d postgres redis

# ログ確認
docker compose logs -f auth-service

# サービス再起動
docker compose restart auth-service

# 停止
docker compose stop

# 削除 (ボリュームも削除)
docker compose down -v

# ビルドして起動
docker compose up --build -d
```

## トラブルシューティング

### ポート競合

```bash
# ポート確認
lsof -i :8002
kill -9 <PID>
```

### イメージ再ビルド

```bash
# キャッシュなしでビルド
docker compose build --no-cache auth-service
docker compose up -d auth-service
```

---

**関連**: [デプロイ概要](./01-deployment-overview.md), [環境変数](./03-environment-variables.md)