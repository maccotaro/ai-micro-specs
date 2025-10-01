# システム起動手順

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システム全体の正しい起動順序と手順を定義します。

### 起動の基本方針

- **依存関係の順守**: インフラ → バックエンド → フロントエンドの順で起動
- **ヘルスチェック**: 各サービス起動後に正常性を確認
- **段階的起動**: 一度にすべてを起動せず、依存関係に従って順次起動

## システム起動順序

### 全体フロー

```
1. PostgreSQL (ai-micro-postgres)
2. Redis (ai-micro-redis)
3. Authentication Service (ai-micro-api-auth)
4. User API Service (ai-micro-api-user)
5. Admin API Service (ai-micro-api-admin)
6. User Frontend (ai-micro-front-user)
7. Admin Frontend (ai-micro-front-admin)
```

## 詳細起動手順

### Phase 1: インフラサービスの起動

#### 1.1 PostgreSQL の起動

```bash
cd /path/to/ai-micro-service/ai-micro-postgres
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep postgres

# データベース接続確認
docker exec postgres psql -U postgres -c "SELECT 1"

# データベース存在確認
docker exec postgres psql -U postgres -c "\l" | grep -E "authdb|apidb|admindb"
```

**期待される結果**:

- コンテナが `Up` 状態
- `SELECT 1` が成功
- `authdb`, `apidb`, `admindb` が存在

**トラブルシューティング**:

```bash
# ログ確認
docker logs postgres

# 再起動が必要な場合
docker compose restart
```

#### 1.2 Redis の起動

```bash
cd /path/to/ai-micro-service/ai-micro-redis
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep redis

# Redis接続確認（パスワードは.envから取得）
docker exec redis redis-cli -a "${REDIS_PASSWORD}" ping

# メモリ使用量確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" info memory
```

**期待される結果**:

- コンテナが `Up` 状態
- `PONG` レスポンス

**トラブルシューティング**:

```bash
# ログ確認
docker logs redis

# Redis設定確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" config get "*"
```

#### 1.3 インフラ起動完了確認

```bash
# 全インフラサービスの状態確認
docker ps --filter "name=postgres" --filter "name=redis" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**待機時間**: PostgreSQL と Redis が完全に起動するまで 10-15秒 待機

---

### Phase 2: バックエンドサービスの起動

#### 2.1 Authentication Service の起動

```bash
cd /path/to/ai-micro-service/ai-micro-api-auth
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep auth-service

# ヘルスチェック
curl -f http://localhost:8002/health || echo "Health check failed"

# JWKS エンドポイント確認
curl -f http://localhost:8002/.well-known/jwks.json || echo "JWKS endpoint failed"

# ログ確認
docker logs --tail 50 auth-service
```

**期待される結果**:

- ヘルスチェック: `200 OK`
- JWKS エンドポイント: JSON レスポンス
- ログに `Application startup complete` が表示

**トラブルシューティング**:

```bash
# 環境変数確認
docker exec auth-service env | grep -E "DATABASE_URL|REDIS_URL|JWT_"

# RSA鍵ペア確認
docker exec auth-service ls -la /app/keys/
```

#### 2.2 User API Service の起動

```bash
cd /path/to/ai-micro-service/ai-micro-api-user
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep user-api

# ヘルスチェック
curl -f http://localhost:8001/health || echo "Health check failed"

# JWKS取得確認（Auth Serviceへの接続確認）
docker logs --tail 20 user-api | grep -i "jwks"
```

**期待される結果**:

- ヘルスチェック: `200 OK`
- ログに JWKS 取得成功メッセージ

#### 2.3 Admin API Service の起動

```bash
cd /path/to/ai-micro-service/ai-micro-api-admin
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep admin-api

# ヘルスチェック
curl -f http://localhost:8003/health || echo "Health check failed"

# ログ確認
docker logs --tail 50 admin-api
```

**期待される結果**:

- ヘルスチェック: `200 OK`
- ログに `Application startup complete` が表示

#### 2.4 バックエンド起動完了確認

```bash
# 全バックエンドサービスの状態確認
docker ps --filter "name=auth-service" --filter "name=user-api" --filter "name=admin-api" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# すべてのヘルスチェック
curl -f http://localhost:8002/health && \
curl -f http://localhost:8001/health && \
curl -f http://localhost:8003/health && \
echo "All backend services are healthy"
```

---

### Phase 3: フロントエンドサービスの起動

#### 3.1 User Frontend の起動

```bash
cd /path/to/ai-micro-service/ai-micro-front-user
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep user-frontend

# アプリケーション接続確認
curl -I http://localhost:3002 | head -n 1

# ログ確認
docker logs --tail 30 user-frontend
```

**期待される結果**:

- HTTP ステータス: `200 OK` または `304 Not Modified`
- ログに Next.js 起動完了メッセージ

#### 3.2 Admin Frontend の起動

```bash
cd /path/to/ai-micro-service/ai-micro-front-admin
docker compose up -d
```

**起動確認**:

```bash
# コンテナ起動確認
docker ps | grep admin-frontend

# アプリケーション接続確認
curl -I http://localhost:3003 | head -n 1

# ログ確認
docker logs --tail 30 admin-frontend
```

**期待される結果**:

- HTTP ステータス: `200 OK` または `304 Not Modified`
- ログに Next.js 起動完了メッセージ

#### 3.3 フロントエンド起動完了確認

```bash
# 全フロントエンドサービスの状態確認
docker ps --filter "name=user-frontend" --filter "name=admin-frontend" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# ブラウザアクセス確認
echo "User Frontend: http://localhost:3002"
echo "Admin Frontend: http://localhost:3003"
```

---

## 全体起動確認

### 全サービス状態確認

```bash
# すべてのサービスが起動していることを確認
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "postgres|redis|auth-service|user-api|admin-api|user-frontend|admin-frontend"
```

**期待される出力**:

```
NAMES            STATUS       PORTS
postgres         Up 2 minutes 0.0.0.0:5432->5432/tcp
redis            Up 2 minutes 0.0.0.0:6379->6379/tcp
auth-service     Up 1 minute  0.0.0.0:8002->8002/tcp
user-api         Up 1 minute  0.0.0.0:8001->8001/tcp
admin-api        Up 1 minute  0.0.0.0:8003->8003/tcp
user-frontend    Up 30 sec    0.0.0.0:3002->3002/tcp
admin-frontend   Up 30 sec    0.0.0.0:3003->3003/tcp
```

### エンドツーエンド動作確認

```bash
# 1. ヘルスチェック（全バックエンド）
for port in 8001 8002 8003; do
  echo "Checking http://localhost:$port/health"
  curl -f "http://localhost:$port/health" || echo "Failed"
done

# 2. フロントエンドアクセス確認
for port in 3002 3003; do
  echo "Checking http://localhost:$port"
  curl -I "http://localhost:$port" | head -n 1
done

# 3. 認証フロー確認（オプション）
# ログインAPIテスト
curl -X POST http://localhost:8002/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}'
```

---

## 起動自動化スクリプト

### 全体起動スクリプト（推奨）

```bash
#!/bin/bash
# startup-all.sh

set -e

BASE_DIR="/path/to/ai-micro-service"
LOG_FILE="/tmp/ai-micro-startup.log"

echo "Starting ai-micro-service system..." | tee -a "$LOG_FILE"

# Phase 1: Infrastructure
echo "[1/3] Starting infrastructure services..." | tee -a "$LOG_FILE"
cd "$BASE_DIR/ai-micro-postgres" && docker compose up -d
cd "$BASE_DIR/ai-micro-redis" && docker compose up -d
echo "Waiting for infrastructure (15s)..."
sleep 15

# Phase 2: Backend Services
echo "[2/3] Starting backend services..." | tee -a "$LOG_FILE"
cd "$BASE_DIR/ai-micro-api-auth" && docker compose up -d
sleep 5
cd "$BASE_DIR/ai-micro-api-user" && docker compose up -d
cd "$BASE_DIR/ai-micro-api-admin" && docker compose up -d
echo "Waiting for backend services (10s)..."
sleep 10

# Phase 3: Frontend Services
echo "[3/3] Starting frontend services..." | tee -a "$LOG_FILE"
cd "$BASE_DIR/ai-micro-front-user" && docker compose up -d
cd "$BASE_DIR/ai-micro-front-admin" && docker compose up -d
sleep 5

# Health Check
echo "Running health checks..." | tee -a "$LOG_FILE"
for port in 8001 8002 8003; do
  if curl -f -s "http://localhost:$port/health" > /dev/null; then
    echo "✓ Service on port $port is healthy" | tee -a "$LOG_FILE"
  else
    echo "✗ Service on port $port is not responding" | tee -a "$LOG_FILE"
  fi
done

echo "System startup complete!" | tee -a "$LOG_FILE"
echo "User Frontend: http://localhost:3002"
echo "Admin Frontend: http://localhost:3003"
```

**使用方法**:

```bash
chmod +x startup-all.sh
./startup-all.sh
```

---

## 起動時の注意事項

### 環境変数の確認

各サービスの `.env` ファイルが正しく設定されていることを確認：

```bash
# 必須環境変数チェックスクリプト
for service in ai-micro-api-auth ai-micro-api-user ai-micro-api-admin; do
  echo "Checking $service/.env"
  cd "/path/to/ai-micro-service/$service"
  if [ -f .env ]; then
    grep -E "DATABASE_URL|REDIS_URL" .env || echo "Missing required variables"
  else
    echo ".env file not found!"
  fi
done
```

### ポート競合の確認

```bash
# 必要なポートが空いているか確認
for port in 3002 3003 5432 6379 8001 8002 8003; do
  if lsof -i :$port > /dev/null 2>&1; then
    echo "⚠️  Port $port is already in use"
  else
    echo "✓ Port $port is available"
  fi
done
```

### Docker リソースの確認

```bash
# Dockerのディスク使用量確認
docker system df

# 必要に応じてクリーンアップ
docker system prune -f
```

---

## よくある起動エラーと対処法

### エラー: PostgreSQL 接続失敗

**症状**:

```
sqlalchemy.exc.OperationalError: could not connect to server
```

**対処法**:

```bash
# PostgreSQLの状態確認
docker logs postgres

# 再起動
cd ai-micro-postgres && docker compose restart
```

### エラー: Redis 接続失敗

**症状**:

```
redis.exceptions.ConnectionError: Error connecting to Redis
```

**対処法**:

```bash
# Redisの状態確認
docker logs redis

# 認証情報確認
echo $REDIS_PASSWORD

# 再起動
cd ai-micro-redis && docker compose restart
```

### エラー: JWKS 取得失敗

**症状**:

```
Failed to fetch JWKS from auth service
```

**対処法**:

```bash
# Auth Serviceが起動しているか確認
curl http://localhost:8002/.well-known/jwks.json

# Auth Serviceを先に起動
cd ai-micro-api-auth && docker compose up -d
sleep 10

# その後、User/Admin APIを起動
```

### エラー: ポート競合

**症状**:

```
Bind for 0.0.0.0:8002 failed: port is already allocated
```

**対処法**:

```bash
# ポート使用プロセスを特定
lsof -i :8002

# プロセスを停止またはポート番号を変更
```

---

## 起動チェックリスト

- [ ] PostgreSQL が起動し、3つのデータベース（authdb, apidb, admindb）が存在する
- [ ] Redis が起動し、`PING` コマンドが成功する
- [ ] Auth Service (port 8002) のヘルスチェックが成功する
- [ ] Auth Service の JWKS エンドポイントがアクセス可能
- [ ] User API (port 8001) のヘルスチェックが成功する
- [ ] Admin API (port 8003) のヘルスチェックが成功する
- [ ] User Frontend (port 3002) がブラウザで表示される
- [ ] Admin Frontend (port 3003) がブラウザで表示される
- [ ] すべてのコンテナが `Up` 状態である
- [ ] ログにエラーメッセージがないことを確認

---

## 参考資料

- [02-shutdown-procedure.md](./02-shutdown-procedure.md) - システム停止手順
- [06-troubleshooting.md](./06-troubleshooting.md) - トラブルシューティング
- [../13-deployment/02-docker-compose.md](../13-deployment/02-docker-compose.md) - Docker Compose設定
- [../13-deployment/03-environment-variables.md](../13-deployment/03-environment-variables.md) - 環境変数設定

---

**変更履歴**:

- 2025-09-30: 初版作成