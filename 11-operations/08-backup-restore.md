# バックアップ・リストア手順

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムのバックアップ戦略、バックアップ手順、リストア手順を定義します。

## バックアップ戦略

### バックアップ対象

1. **PostgreSQL データベース**
   - authdb（認証情報）
   - apidb（ユーザープロフィール）
   - admindb（ドキュメント、OCRデータ）

2. **Redis データ**
   - セッション情報
   - キャッシュデータ

3. **ファイルシステム**
   - アップロードされたドキュメント
   - OCR処理済みファイル
   - RSA鍵ペア

4. **設定ファイル**
   - `.env` ファイル
   - `docker-compose.yml`
   - アプリケーション設定

### バックアップ頻度

| データ種別 | 頻度 | 保持期間 | 優先度 |
|-----------|------|----------|--------|
| PostgreSQL（Full） | 日次 | 30日 | 最高 |
| PostgreSQL（Incremental） | 6時間毎 | 7日 | 高 |
| Redis（RDB） | 6時間毎 | 7日 | 中 |
| ファイルシステム | 日次 | 30日 | 高 |
| 設定ファイル | 変更時 | 無期限 | 高 |

### RPO/RTO目標

| 項目 | 目標 |
|------|------|
| **RPO** (Recovery Point Objective) | 6時間以内 |
| **RTO** (Recovery Time Objective) | 4時間以内 |

---

## PostgreSQL バックアップ

### 完全バックアップ（pg_dump）

#### 単一データベースのバックアップ

```bash
#!/bin/bash
# backup-postgres-single.sh

BACKUP_DIR="/backups/postgres/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

DATABASES=("authdb" "apidb" "admindb")

for DB in "${DATABASES[@]}"; do
  echo "Backing up $DB..."

  # SQL形式でバックアップ
  docker exec postgres pg_dump -U postgres -d "$DB" \
    --format=custom \
    --compress=9 \
    --file=/tmp/"${DB}_$(date +%Y%m%d_%H%M%S).dump"

  # ホストにコピー
  docker cp postgres:/tmp/"${DB}_$(date +%Y%m%d_%H%M%S).dump" \
    "$BACKUP_DIR/${DB}_$(date +%Y%m%d_%H%M%S).dump"

  # コンテナ内の一時ファイル削除
  docker exec postgres rm /tmp/"${DB}_$(date +%Y%m%d_%H%M%S).dump"

  echo "✓ $DB backup completed"
done

# バックアップファイルの圧縮
cd "$BACKUP_DIR"
tar -czf "../postgres_backup_$(date +%Y%m%d_%H%M%S).tar.gz" .
cd -

echo "All PostgreSQL backups completed: $BACKUP_DIR"
```

#### 全データベースのバックアップ（pg_dumpall）

```bash
#!/bin/bash
# backup-postgres-all.sh

BACKUP_DIR="/backups/postgres"
mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/all_databases_$(date +%Y%m%d_%H%M%S).sql"

echo "Creating full backup of all PostgreSQL databases..."

# すべてのデータベースとグローバルオブジェクトをバックアップ
docker exec postgres pg_dumpall -U postgres > "$BACKUP_FILE"

# 圧縮
gzip "$BACKUP_FILE"

echo "✓ Full backup completed: ${BACKUP_FILE}.gz"

# 古いバックアップの削除（30日以上前）
find "$BACKUP_DIR" -name "all_databases_*.sql.gz" -mtime +30 -delete

echo "Backup retention policy applied (30 days)"
```

### 増分バックアップ（WALアーカイブ）

**設定（postgresql.conf）**:

```conf
# WALアーカイブ有効化
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /mnt/wal_archive/%f && cp %p /mnt/wal_archive/%f'
max_wal_senders = 3
```

**WALアーカイブスクリプト**:

```bash
#!/bin/bash
# backup-postgres-wal.sh

WAL_ARCHIVE_DIR="/backups/postgres/wal_archive"
mkdir -p "$WAL_ARCHIVE_DIR"

# WALファイルをアーカイブディレクトリにコピー
docker exec postgres bash -c 'cp -a /var/lib/postgresql/data/pg_wal/*.* /mnt/wal_archive/' || true

echo "WAL files archived to $WAL_ARCHIVE_DIR"

# 古いWALファイルの削除（7日以上前）
find "$WAL_ARCHIVE_DIR" -mtime +7 -delete
```

### 自動バックアップスケジュール

```bash
# /etc/cron.d/postgres-backup

# 完全バックアップ: 毎日午前2時
0 2 * * * root /opt/scripts/backup-postgres-all.sh >> /var/log/backup.log 2>&1

# 増分バックアップ（WAL）: 6時間毎
0 */6 * * * root /opt/scripts/backup-postgres-wal.sh >> /var/log/backup.log 2>&1
```

---

## PostgreSQL リストア

### 完全リストア（pg_restore）

```bash
#!/bin/bash
# restore-postgres.sh

BACKUP_FILE="$1"
DATABASE="$2"

if [ -z "$BACKUP_FILE" ] || [ -z "$DATABASE" ]; then
  echo "Usage: $0 <backup_file> <database_name>"
  exit 1
fi

echo "Restoring $DATABASE from $BACKUP_FILE..."

# 1. 既存データベースを削除（慎重に！）
echo "WARNING: This will delete the existing database!"
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

# 2. アクティブな接続を終了
docker exec postgres psql -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = '$DATABASE' AND pid != pg_backend_pid();
"

# 3. データベース削除
docker exec postgres psql -U postgres -c "DROP DATABASE IF EXISTS $DATABASE;"

# 4. データベース再作成
docker exec postgres psql -U postgres -c "CREATE DATABASE $DATABASE;"

# 5. バックアップをコンテナにコピー
docker cp "$BACKUP_FILE" postgres:/tmp/restore.dump

# 6. リストア実行
docker exec postgres pg_restore -U postgres -d "$DATABASE" \
  --verbose \
  --no-owner \
  --no-acl \
  /tmp/restore.dump

# 7. 一時ファイル削除
docker exec postgres rm /tmp/restore.dump

echo "✓ Database $DATABASE restored successfully"

# 8. ANALYZE実行
docker exec postgres psql -U postgres -d "$DATABASE" -c "ANALYZE;"

echo "✓ Statistics updated"
```

### 全データベースのリストア（pg_dumpall から）

```bash
#!/bin/bash
# restore-postgres-all.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup_file.sql.gz>"
  exit 1
fi

echo "Restoring all databases from $BACKUP_FILE..."

# 1. バックアップファイル解凍
gunzip -c "$BACKUP_FILE" > /tmp/restore_all.sql

# 2. リストア実行
docker exec -i postgres psql -U postgres < /tmp/restore_all.sql

# 3. 一時ファイル削除
rm /tmp/restore_all.sql

echo "✓ All databases restored successfully"
```

### Point-in-Time Recovery (PITR)

```bash
#!/bin/bash
# restore-postgres-pitr.sh

BASE_BACKUP="$1"
TARGET_TIME="$2"  # 例: '2025-09-30 12:00:00'

if [ -z "$BASE_BACKUP" ] || [ -z "$TARGET_TIME" ]; then
  echo "Usage: $0 <base_backup> <target_time>"
  echo "Example: $0 /backups/base_backup.tar.gz '2025-09-30 12:00:00'"
  exit 1
fi

echo "Performing Point-in-Time Recovery to $TARGET_TIME..."

# 1. PostgreSQL停止
docker compose -f ai-micro-postgres/docker-compose.yml down

# 2. データディレクトリクリア
rm -rf /var/lib/docker/volumes/postgres_data/*

# 3. ベースバックアップを展開
tar -xzf "$BASE_BACKUP" -C /var/lib/docker/volumes/postgres_data/

# 4. recovery.confを作成
cat > /var/lib/docker/volumes/postgres_data/_data/recovery.conf <<EOF
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_time = '$TARGET_TIME'
recovery_target_action = 'promote'
EOF

# 5. PostgreSQL起動
docker compose -f ai-micro-postgres/docker-compose.yml up -d

echo "✓ PITR initiated. Check logs for completion."
docker logs -f postgres
```

---

## Redis バックアップ

### RDBスナップショットバックアップ

```bash
#!/bin/bash
# backup-redis.sh

BACKUP_DIR="/backups/redis/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "Creating Redis backup..."

# 1. BGSAVEコマンドでスナップショット作成
docker exec redis redis-cli -a "${REDIS_PASSWORD}" BGSAVE

# 2. BGSAVE完了を待機
echo "Waiting for BGSAVE to complete..."
while [ $(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LASTSAVE) -eq $(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LASTSAVE) ]; do
  sleep 1
done

# 3. dump.rdbをコピー
docker cp redis:/data/dump.rdb "$BACKUP_DIR/redis_$(date +%Y%m%d_%H%M%S).rdb"

# 4. 圧縮
gzip "$BACKUP_DIR/redis_$(date +%Y%m%d_%H%M%S).rdb"

echo "✓ Redis backup completed: $BACKUP_DIR"

# 古いバックアップの削除（7日以上前）
find "$BACKUP_DIR/.." -name "redis_*.rdb.gz" -mtime +7 -delete
```

### AOF（Append-Only File）バックアップ

```bash
#!/bin/bash
# backup-redis-aof.sh

BACKUP_DIR="/backups/redis/aof"
mkdir -p "$BACKUP_DIR"

echo "Backing up Redis AOF..."

# AOFファイルをコピー
docker cp redis:/data/appendonly.aof "$BACKUP_DIR/appendonly_$(date +%Y%m%d_%H%M%S).aof"

# 圧縮
gzip "$BACKUP_DIR/appendonly_$(date +%Y%m%d_%H%M%S).aof"

echo "✓ Redis AOF backup completed"
```

---

## Redis リストア

### RDBからのリストア

```bash
#!/bin/bash
# restore-redis.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <redis_backup.rdb.gz>"
  exit 1
fi

echo "Restoring Redis from $BACKUP_FILE..."

# 1. Redis停止
docker compose -f ai-micro-redis/docker-compose.yml down

# 2. 解凍
gunzip -c "$BACKUP_FILE" > /tmp/dump.rdb

# 3. バックアップファイルをデータディレクトリにコピー
docker cp /tmp/dump.rdb redis:/data/dump.rdb

# 4. Redis起動
docker compose -f ai-micro-redis/docker-compose.yml up -d

echo "✓ Redis restored successfully"

# 5. 動作確認
sleep 5
docker exec redis redis-cli -a "${REDIS_PASSWORD}" PING
```

---

## ファイルシステムバックアップ

### アップロードファイルのバックアップ

```bash
#!/bin/bash
# backup-files.sh

BACKUP_DIR="/backups/files/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "Backing up uploaded files..."

# 1. Admin API のアップロードディレクトリ
docker cp admin-api:/app/uploads "$BACKUP_DIR/uploads"

# 2. Auth Service のRSA鍵
docker cp auth-service:/app/keys "$BACKUP_DIR/auth-keys"

# 3. 圧縮
cd "$BACKUP_DIR/.."
tar -czf "files_backup_$(date +%Y%m%d_%H%M%S).tar.gz" "$(date +%Y%m%d)"
cd -

echo "✓ File backup completed: $BACKUP_DIR"

# 古いバックアップの削除（30日以上前）
find "$BACKUP_DIR/.." -name "files_backup_*.tar.gz" -mtime +30 -delete
```

### ファイルのリストア

```bash
#!/bin/bash
# restore-files.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <files_backup.tar.gz>"
  exit 1
fi

echo "Restoring files from $BACKUP_FILE..."

# 1. 解凍
TEMP_DIR="/tmp/restore_files"
mkdir -p "$TEMP_DIR"
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# 2. ファイルをコンテナにコピー
docker cp "$TEMP_DIR/uploads" admin-api:/app/uploads
docker cp "$TEMP_DIR/auth-keys" auth-service:/app/keys

# 3. パーミッション設定
docker exec admin-api chmod -R 755 /app/uploads
docker exec auth-service chmod 600 /app/keys/*.pem

# 4. 一時ディレクトリ削除
rm -rf "$TEMP_DIR"

echo "✓ Files restored successfully"
```

---

## 設定ファイルのバックアップ

### 設定ファイルバックアップスクリプト

```bash
#!/bin/bash
# backup-config.sh

BACKUP_DIR="/backups/config"
mkdir -p "$BACKUP_DIR"

CONFIG_BACKUP="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "Backing up configuration files..."

# バックアップ対象ファイルのリスト
tar -czf "$CONFIG_BACKUP" \
  -C /path/to/ai-micro-service \
  --exclude='node_modules' \
  --exclude='.next' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  ai-micro-api-auth/.env \
  ai-micro-api-auth/docker-compose.yml \
  ai-micro-api-user/.env \
  ai-micro-api-user/docker-compose.yml \
  ai-micro-api-admin/.env \
  ai-micro-api-admin/docker-compose.yml \
  ai-micro-front-user/.env \
  ai-micro-front-user/docker-compose.yml \
  ai-micro-front-admin/.env \
  ai-micro-front-admin/docker-compose.yml \
  ai-micro-postgres/.env \
  ai-micro-postgres/docker-compose.yml \
  ai-micro-redis/.env \
  ai-micro-redis/docker-compose.yml

echo "✓ Configuration backup completed: $CONFIG_BACKUP"
```

---

## 完全システムバックアップ

### 統合バックアップスクリプト

```bash
#!/bin/bash
# backup-full-system.sh

set -e

BACKUP_ROOT="/backups/full_system/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_ROOT"

LOG_FILE="$BACKUP_ROOT/backup.log"

echo "===== Full System Backup Started: $(date) =====" | tee "$LOG_FILE"

# 1. PostgreSQL
echo "[1/5] Backing up PostgreSQL..." | tee -a "$LOG_FILE"
/opt/scripts/backup-postgres-all.sh >> "$LOG_FILE" 2>&1
mv /backups/postgres/all_databases_*.sql.gz "$BACKUP_ROOT/"

# 2. Redis
echo "[2/5] Backing up Redis..." | tee -a "$LOG_FILE"
/opt/scripts/backup-redis.sh >> "$LOG_FILE" 2>&1
mv /backups/redis/$(date +%Y%m%d)/redis_*.rdb.gz "$BACKUP_ROOT/"

# 3. Files
echo "[3/5] Backing up files..." | tee -a "$LOG_FILE"
/opt/scripts/backup-files.sh >> "$LOG_FILE" 2>&1
mv /backups/files/files_backup_*.tar.gz "$BACKUP_ROOT/"

# 4. Configuration
echo "[4/5] Backing up configuration..." | tee -a "$LOG_FILE"
/opt/scripts/backup-config.sh >> "$LOG_FILE" 2>&1
mv /backups/config/config_*.tar.gz "$BACKUP_ROOT/"

# 5. メタデータ作成
echo "[5/5] Creating metadata..." | tee -a "$LOG_FILE"
cat > "$BACKUP_ROOT/metadata.json" <<EOF
{
  "backup_time": "$(date -Iseconds)",
  "system_version": "1.0.0",
  "components": {
    "postgresql": "$(ls $BACKUP_ROOT/all_databases_*.sql.gz 2>/dev/null | wc -l) files",
    "redis": "$(ls $BACKUP_ROOT/redis_*.rdb.gz 2>/dev/null | wc -l) files",
    "files": "$(ls $BACKUP_ROOT/files_backup_*.tar.gz 2>/dev/null | wc -l) files",
    "config": "$(ls $BACKUP_ROOT/config_*.tar.gz 2>/dev/null | wc -l) files"
  }
}
EOF

# 最終圧縮
cd "$BACKUP_ROOT/.."
tar -czf "full_backup_$(date +%Y%m%d_%H%M%S).tar.gz" "$(basename $BACKUP_ROOT)"

echo "===== Full System Backup Completed: $(date) =====" | tee -a "$LOG_FILE"
echo "Backup location: $BACKUP_ROOT"

# 古いフルバックアップの削除（30日以上前）
find /backups/full_system -name "full_backup_*.tar.gz" -mtime +30 -delete
```

---

## リストア手順（完全復旧）

### 完全システムリストア

```bash
#!/bin/bash
# restore-full-system.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <full_backup_YYYYMMDD_HHMMSS.tar.gz>"
  exit 1
fi

echo "===== Full System Restore Started: $(date) ====="

# 1. バックアップ解凍
RESTORE_DIR="/tmp/restore_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESTORE_DIR"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

BACKUP_DIR=$(ls -d $RESTORE_DIR/*/ | head -1)

# 2. メタデータ確認
cat "$BACKUP_DIR/metadata.json"
read -p "Continue with restore? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

# 3. すべてのサービスを停止
echo "Stopping all services..."
cd /path/to/ai-micro-service
for service in ai-micro-front-admin ai-micro-front-user ai-micro-api-admin ai-micro-api-user ai-micro-api-auth ai-micro-redis ai-micro-postgres; do
  cd "$service" && docker compose down && cd ..
done

# 4. PostgreSQL リストア
echo "Restoring PostgreSQL..."
/opt/scripts/restore-postgres-all.sh "$BACKUP_DIR/all_databases_"*.sql.gz

# 5. Redis リストア
echo "Restoring Redis..."
/opt/scripts/restore-redis.sh "$BACKUP_DIR/redis_"*.rdb.gz

# 6. Files リストア
echo "Restoring files..."
/opt/scripts/restore-files.sh "$BACKUP_DIR/files_backup_"*.tar.gz

# 7. Configuration リストア
echo "Restoring configuration..."
tar -xzf "$BACKUP_DIR/config_"*.tar.gz -C /path/to/ai-micro-service

# 8. すべてのサービスを起動
echo "Starting all services..."
/opt/scripts/startup-all.sh

# 9. ヘルスチェック
echo "Running health checks..."
sleep 30
for port in 8001 8002 8003; do
  curl -f "http://localhost:$port/health" && echo "✓ Service on port $port is healthy"
done

# 10. クリーンアップ
rm -rf "$RESTORE_DIR"

echo "===== Full System Restore Completed: $(date) ====="
```

---

## バックアップ検証

### バックアップ整合性チェック

```bash
#!/bin/bash
# verify-backup.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup_file>"
  exit 1
fi

echo "Verifying backup integrity: $BACKUP_FILE"

# 1. ファイル存在確認
if [ ! -f "$BACKUP_FILE" ]; then
  echo "✗ Backup file not found"
  exit 1
fi

# 2. ファイルサイズ確認
FILE_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null)
if [ "$FILE_SIZE" -lt 1000 ]; then
  echo "✗ Backup file is too small: $FILE_SIZE bytes"
  exit 1
fi

# 3. 圧縮ファイルの整合性確認
if [[ "$BACKUP_FILE" == *.gz ]]; then
  gunzip -t "$BACKUP_FILE" 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "✓ Backup file integrity verified"
  else
    echo "✗ Backup file is corrupted"
    exit 1
  fi
fi

# 4. PostgreSQLバックアップの場合、pg_restoreで検証
if [[ "$BACKUP_FILE" == *.dump ]]; then
  docker exec postgres pg_restore --list "$BACKUP_FILE" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "✓ PostgreSQL backup is valid"
  else
    echo "✗ PostgreSQL backup is invalid"
    exit 1
  fi
fi

echo "✓ All checks passed"
```

---

## オフサイトバックアップ

### S3へのバックアップ転送

```bash
#!/bin/bash
# backup-to-s3.sh

BACKUP_DIR="/backups"
S3_BUCKET="s3://your-backup-bucket/ai-micro-service"

echo "Uploading backups to S3..."

# AWS CLIがインストールされている前提
aws s3 sync "$BACKUP_DIR" "$S3_BUCKET" \
  --exclude "*" \
  --include "full_backup_*.tar.gz" \
  --storage-class STANDARD_IA

echo "✓ Backups uploaded to S3"
```

---

## 参考資料

- [09-disaster-recovery.md](./09-disaster-recovery.md) - 障害復旧手順
- [../06-database/10-backup-restore.md](../06-database/10-backup-restore.md) - データベースバックアップ詳細
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence](https://redis.io/docs/management/persistence/)

---

**変更履歴**:

- 2025-09-30: 初版作成