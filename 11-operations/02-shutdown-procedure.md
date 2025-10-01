# システム停止手順

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システム全体の安全な停止順序と手順を定義します。

### 停止の基本方針

- **逆順停止**: 起動とは逆の順序で停止（フロントエンド → バックエンド → インフラ）
- **グレースフルシャットダウン**: データの整合性を保ちながら停止
- **状態確認**: 各サービス停止後に正常終了を確認

## システム停止順序

### 全体フロー

```
1. User Frontend (ai-micro-front-user)
2. Admin Frontend (ai-micro-front-admin)
3. Admin API Service (ai-micro-api-admin)
4. User API Service (ai-micro-api-user)
5. Authentication Service (ai-micro-api-auth)
6. Redis (ai-micro-redis)
7. PostgreSQL (ai-micro-postgres)
```

## 詳細停止手順

### Phase 1: フロントエンドサービスの停止

#### 1.1 User Frontend の停止

```bash
cd /path/to/ai-micro-service/ai-micro-front-user
docker compose down
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep user-frontend
# 何も表示されなければ停止完了

# ポート解放確認
lsof -i :3002
# 何も表示されなければポート解放完了
```

**期待される結果**:

- コンテナが存在しない
- ポート 3002 が解放されている

#### 1.2 Admin Frontend の停止

```bash
cd /path/to/ai-micro-service/ai-micro-front-admin
docker compose down
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep admin-frontend

# ポート解放確認
lsof -i :3003
```

**期待される結果**:

- コンテナが存在しない
- ポート 3003 が解放されている

#### 1.3 フロントエンド停止完了確認

```bash
# フロントエンドサービスが停止していることを確認
docker ps --filter "name=user-frontend" --filter "name=admin-frontend"
# 何も表示されなければ成功
```

---

### Phase 2: バックエンドサービスの停止

#### 2.1 Admin API Service の停止

```bash
cd /path/to/ai-micro-service/ai-micro-api-admin
docker compose down
```

**停止前の準備**:

```bash
# 進行中のドキュメント処理がないか確認（オプション）
docker logs --tail 50 admin-api | grep -i "processing"

# 必要に応じてタスク完了を待機
sleep 5
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep admin-api

# ポート解放確認
lsof -i :8003
```

**期待される結果**:

- コンテナが存在しない
- ポート 8003 が解放されている

#### 2.2 User API Service の停止

```bash
cd /path/to/ai-micro-service/ai-micro-api-user
docker compose down
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep user-api

# ポート解放確認
lsof -i :8001
```

**期待される結果**:

- コンテナが存在しない
- ポート 8001 が解放されている

#### 2.3 Authentication Service の停止

```bash
cd /path/to/ai-micro-service/ai-micro-api-auth
docker compose down
```

**停止前の準備**:

```bash
# アクティブセッション数確認（オプション）
docker exec redis redis-cli -a "${REDIS_PASSWORD}" keys "session:*" | wc -l

# ログ確認
docker logs --tail 20 auth-service
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep auth-service

# ポート解放確認
lsof -i :8002
```

**期待される結果**:

- コンテナが存在しない
- ポート 8002 が解放されている

#### 2.4 バックエンド停止完了確認

```bash
# 全バックエンドサービスが停止していることを確認
docker ps --filter "name=auth-service" --filter "name=user-api" --filter "name=admin-api"
# 何も表示されなければ成功
```

---

### Phase 3: インフラサービスの停止

#### 3.1 Redis の停止

**停止前のデータ永続化**:

```bash
# Redis データを強制保存（永続化設定による）
docker exec redis redis-cli -a "${REDIS_PASSWORD}" BGSAVE

# 保存完了を待機
sleep 3

# 保存状態確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" LASTSAVE
```

**停止実行**:

```bash
cd /path/to/ai-micro-service/ai-micro-redis
docker compose down
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep redis

# ポート解放確認
lsof -i :6379

# データファイルの存在確認（永続化設定時）
ls -lh /path/to/redis/data/dump.rdb 2>/dev/null || echo "No persistence file"
```

**期待される結果**:

- コンテナが存在しない
- ポート 6379 が解放されている
- 永続化設定時は `dump.rdb` が存在

#### 3.2 PostgreSQL の停止

**停止前のバックアップ（推奨）**:

```bash
# データベースバックアップ（オプションだが推奨）
BACKUP_DIR="/tmp/postgres-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/all-databases.sql"

echo "Backup saved to: $BACKUP_DIR"
```

**アクティブ接続の確認**:

```bash
# アクティブな接続を確認
docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"

# 接続を強制終了（必要な場合のみ）
# docker exec postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('authdb', 'apidb', 'admindb');"
```

**停止実行**:

```bash
cd /path/to/ai-micro-service/ai-micro-postgres
docker compose down
```

**停止確認**:

```bash
# コンテナが停止していることを確認
docker ps | grep postgres

# ポート解放確認
lsof -i :5432

# データボリュームの存在確認（データ保持確認）
docker volume ls | grep postgres
```

**期待される結果**:

- コンテナが存在しない
- ポート 5432 が解放されている
- データボリュームは残存（データ保持）

#### 3.3 インフラ停止完了確認

```bash
# 全インフラサービスが停止していることを確認
docker ps --filter "name=postgres" --filter "name=redis"
# 何も表示されなければ成功
```

---

## 全体停止確認

### 全サービス停止確認

```bash
# すべてのサービスが停止していることを確認
docker ps --format "table {{.Names}}\t{{.Status}}" | \
  grep -E "postgres|redis|auth-service|user-api|admin-api|user-frontend|admin-frontend"
# 何も表示されなければ全停止成功

# または、すべての起動中コンテナを確認
docker ps
```

### データ保持確認

```bash
# データボリュームが残っていることを確認（データ永続化）
docker volume ls | grep -E "postgres|redis"
```

**期待される出力例**:

```
DRIVER    VOLUME NAME
local     ai-micro-postgres_postgres_data
local     ai-micro-redis_redis_data
```

### ポート解放確認

```bash
# すべてのポートが解放されていることを確認
for port in 3002 3003 5432 6379 8001 8002 8003; do
  if lsof -i :$port > /dev/null 2>&1; then
    echo "⚠️  Port $port is still in use"
  else
    echo "✓ Port $port is free"
  fi
done
```

---

## 停止自動化スクリプト

### 全体停止スクリプト（推奨）

```bash
#!/bin/bash
# shutdown-all.sh

set -e

BASE_DIR="/path/to/ai-micro-service"
LOG_FILE="/tmp/ai-micro-shutdown.log"

echo "Stopping ai-micro-service system..." | tee -a "$LOG_FILE"

# Phase 1: Frontend Services
echo "[1/3] Stopping frontend services..." | tee -a "$LOG_FILE"
cd "$BASE_DIR/ai-micro-front-user" && docker compose down
cd "$BASE_DIR/ai-micro-front-admin" && docker compose down

# Phase 2: Backend Services
echo "[2/3] Stopping backend services..." | tee -a "$LOG_FILE"
cd "$BASE_DIR/ai-micro-api-admin" && docker compose down
cd "$BASE_DIR/ai-micro-api-user" && docker compose down
cd "$BASE_DIR/ai-micro-api-auth" && docker compose down

# Phase 3: Infrastructure Services
echo "[3/3] Stopping infrastructure services..." | tee -a "$LOG_FILE"

# Redis: データ保存してから停止
echo "Saving Redis data..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" BGSAVE 2>/dev/null || true
sleep 3
cd "$BASE_DIR/ai-micro-redis" && docker compose down

# PostgreSQL: 停止
cd "$BASE_DIR/ai-micro-postgres" && docker compose down

# 停止確認
echo "Verifying shutdown..." | tee -a "$LOG_FILE"
RUNNING=$(docker ps --filter "name=postgres" --filter "name=redis" \
  --filter "name=auth-service" --filter "name=user-api" \
  --filter "name=admin-api" --filter "name=user-frontend" \
  --filter "name=admin-frontend" --format "{{.Names}}" | wc -l)

if [ "$RUNNING" -eq 0 ]; then
  echo "✓ All services stopped successfully" | tee -a "$LOG_FILE"
else
  echo "⚠️  Some services are still running" | tee -a "$LOG_FILE"
  docker ps
fi

echo "System shutdown complete!" | tee -a "$LOG_FILE"
```

**使用方法**:

```bash
chmod +x shutdown-all.sh
./shutdown-all.sh
```

---

### バックアップ付き停止スクリプト（本番環境推奨）

```bash
#!/bin/bash
# shutdown-with-backup.sh

set -e

BASE_DIR="/path/to/ai-micro-service"
BACKUP_DIR="/backups/ai-micro-$(date +%Y%m%d-%H%M%S)"

echo "Creating backup before shutdown..."
mkdir -p "$BACKUP_DIR"

# PostgreSQL バックアップ
echo "Backing up PostgreSQL..."
docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/all-databases.sql"

# Redis バックアップ（永続化設定時）
echo "Backing up Redis..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" BGSAVE
sleep 5
docker cp redis:/data/dump.rdb "$BACKUP_DIR/redis-dump.rdb" 2>/dev/null || true

echo "Backup completed: $BACKUP_DIR"

# 通常の停止処理を実行
./shutdown-all.sh

echo "Backup location: $BACKUP_DIR"
```

---

## 停止モード

### 通常停止（Graceful Shutdown）

```bash
# 推奨: データ保存・コンテナ削除・ボリューム保持
docker compose down
```

**特徴**:

- コンテナは削除される
- ボリュームは保持される
- ネットワークは削除される

### 完全停止（ボリューム削除）

```bash
# 注意: データがすべて削除される
docker compose down -v
```

**警告**: `-v` オプションはボリュームも削除するため、データが失われます。開発環境のリセット時のみ使用。

### 一時停止（Pause）

```bash
# コンテナを一時停止（メモリ状態保持）
docker compose pause

# 再開
docker compose unpause
```

**用途**: 短時間の一時停止時に使用。

---

## 停止時の注意事項

### データ整合性の確保

#### PostgreSQL

```bash
# アクティブトランザクションの確認
docker exec postgres psql -U postgres -c \
  "SELECT datname, count(*) FROM pg_stat_activity WHERE state != 'idle' GROUP BY datname;"

# 長時間実行中のクエリ確認
docker exec postgres psql -U postgres -c \
  "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';"
```

#### Redis

```bash
# 未保存の変更数確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO persistence | grep changes_since_last_save

# 手動保存
docker exec redis redis-cli -a "${REDIS_PASSWORD}" SAVE
```

### 進行中の処理の確認

```bash
# Admin API: ドキュメント処理状況確認
docker logs --tail 100 admin-api | grep -E "processing|upload|ocr"

# Auth Service: 認証処理確認
docker logs --tail 50 auth-service | grep -E "login|logout|token"
```

### 再起動が必要な場合

```bash
# 停止せずに再起動
docker compose restart

# または個別サービス再起動
docker restart <service-name>
```

---

## よくある停止エラーと対処法

### エラー: コンテナが停止しない

**症状**:

```
Container still running after docker compose down
```

**対処法**:

```bash
# 強制停止（10秒後にKILL）
docker compose down --timeout 10

# それでも停止しない場合
docker ps | grep <service-name>
docker kill <container-id>
```

### エラー: ボリュームが削除できない

**症状**:

```
Error response from daemon: volume is in use
```

**対処法**:

```bash
# 使用中のコンテナを確認
docker ps -a --filter volume=<volume-name>

# すべてのコンテナを停止
docker stop $(docker ps -aq)

# ボリューム削除
docker volume rm <volume-name>
```

### エラー: ポートが解放されない

**症状**:

```bash
lsof -i :8002
# プロセスがまだ存在する
```

**対処法**:

```bash
# プロセスIDを取得して強制終了
kill -9 $(lsof -t -i:8002)

# Dockerネットワークのクリーンアップ
docker network prune -f
```

---

## 停止チェックリスト

- [ ] User Frontend (port 3002) が停止している
- [ ] Admin Frontend (port 3003) が停止している
- [ ] Admin API (port 8003) が停止している
- [ ] User API (port 8001) が停止している
- [ ] Auth Service (port 8002) が停止している
- [ ] Redis (port 6379) が停止している
- [ ] PostgreSQL (port 5432) が停止している
- [ ] すべてのポートが解放されている
- [ ] データボリュームが保持されている（意図的に削除する場合を除く）
- [ ] 必要に応じてバックアップが作成されている

---

## 緊急停止手順

システムが応答しない場合の緊急停止:

```bash
# すべてのコンテナを強制停止
docker kill $(docker ps -q)

# すべてのコンテナを削除
docker rm -f $(docker ps -aq)

# ネットワークとボリュームのクリーンアップ（オプション）
docker network prune -f
# docker volume prune -f  # 注意: データが失われます
```

---

## 参考資料

- [01-startup-procedure.md](./01-startup-procedure.md) - システム起動手順
- [08-backup-restore.md](./08-backup-restore.md) - バックアップ・リストア手順
- [09-disaster-recovery.md](./09-disaster-recovery.md) - 障害復旧手順
- [../06-database/10-backup-restore.md](../06-database/10-backup-restore.md) - データベースバックアップ

---

**変更履歴**:

- 2025-09-30: 初版作成