# メンテナンス手順

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムの定期メンテナンス手順とベストプラクティスを定義します。

## メンテナンスの種類

### 1. 日次メンテナンス（自動化推奨）

- ログローテーション
- バックアップ実行
- ヘルスチェック
- ディスク使用量確認

### 2. 週次メンテナンス

- データベースバキューム
- Redisメモリ最適化
- ログ分析
- セキュリティアップデート確認

### 3. 月次メンテナンス

- パフォーマンスレビュー
- キャパシティプランニング
- データベースインデックス最適化
- 古いデータのアーカイブ

### 4. 四半期メンテナンス

- システム全体レビュー
- セキュリティ監査
- ディザスタリカバリテスト
- ドキュメント更新

---

## 日次メンテナンス

### 自動化スクリプト

```bash
#!/bin/bash
# daily-maintenance.sh

set -e

LOG_FILE="/var/log/maintenance/daily-$(date +%Y%m%d).log"
mkdir -p /var/log/maintenance

echo "===== Daily Maintenance: $(date) =====" | tee -a "$LOG_FILE"

# 1. ヘルスチェック
echo "[1/5] Running health checks..." | tee -a "$LOG_FILE"
for port in 8001 8002 8003; do
  if curl -f -s "http://localhost:$port/health" > /dev/null; then
    echo "  ✓ Service on port $port is healthy" | tee -a "$LOG_FILE"
  else
    echo "  ✗ Service on port $port is unhealthy" | tee -a "$LOG_FILE"
    # Alert notification
    curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
      -d "{\"text\":\"⚠️ Service on port $port is unhealthy\"}"
  fi
done

# 2. ディスク使用量確認
echo "[2/5] Checking disk usage..." | tee -a "$LOG_FILE"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
  echo "  ⚠️  Disk usage is high: ${DISK_USAGE}%" | tee -a "$LOG_FILE"
  curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
    -d "{\"text\":\"⚠️ Disk usage is high: ${DISK_USAGE}%\"}"
else
  echo "  ✓ Disk usage is normal: ${DISK_USAGE}%" | tee -a "$LOG_FILE"
fi

# 3. Dockerリソース確認
echo "[3/5] Checking Docker resources..." | tee -a "$LOG_FILE"
docker system df -v | tee -a "$LOG_FILE"

# 4. バックアップ実行
echo "[4/5] Running backups..." | tee -a "$LOG_FILE"
/opt/scripts/backup.sh >> "$LOG_FILE" 2>&1

# 5. ログローテーション確認
echo "[5/5] Verifying log rotation..." | tee -a "$LOG_FILE"
docker ps --format "{{.Names}}" | while read container; do
  LOG_SIZE=$(docker inspect --format='{{.LogPath}}' $container | xargs du -h | cut -f1)
  echo "  $container: $LOG_SIZE" | tee -a "$LOG_FILE"
done

echo "===== Daily Maintenance Complete: $(date) =====" | tee -a "$LOG_FILE"
```

### Cron設定

```bash
# /etc/cron.d/ai-micro-maintenance
# 毎日午前3時に実行
0 3 * * * root /opt/scripts/daily-maintenance.sh
```

---

## 週次メンテナンス

### PostgreSQL バキューム

**目的**: 不要な領域を解放し、パフォーマンスを最適化

```bash
#!/bin/bash
# weekly-postgres-maintenance.sh

echo "===== PostgreSQL Weekly Maintenance: $(date) ====="

# 1. VACUUM ANALYZE（全データベース）
echo "Running VACUUM ANALYZE..."
docker exec postgres psql -U postgres -c "VACUUM ANALYZE;" authdb
docker exec postgres psql -U postgres -c "VACUUM ANALYZE;" apidb
docker exec postgres psql -U postgres -c "VACUUM ANALYZE;" admindb

# 2. テーブルブロート確認
echo "Checking table bloat..."
docker exec postgres psql -U postgres -d authdb -c "
  SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS external_size
  FROM pg_tables
  WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
  LIMIT 10;
"

# 3. インデックス再構築（必要に応じて）
echo "Reindexing if necessary..."
# REINDEX は通常不要だが、ブロートが大きい場合のみ実行
# docker exec postgres psql -U postgres -d authdb -c "REINDEX DATABASE authdb;"

# 4. 統計情報更新
echo "Updating statistics..."
docker exec postgres psql -U postgres -c "ANALYZE;" authdb
docker exec postgres psql -U postgres -c "ANALYZE;" apidb
docker exec postgres psql -U postgres -c "ANALYZE;" admindb

echo "PostgreSQL maintenance complete."
```

### Redis メモリ最適化

```bash
#!/bin/bash
# weekly-redis-maintenance.sh

echo "===== Redis Weekly Maintenance: $(date) ====="

# 1. メモリ使用状況確認
echo "Current memory usage:"
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory | grep -E "used_memory_human|maxmemory_human|mem_fragmentation_ratio"

# 2. メモリフラグメンテーション確認
FRAG_RATIO=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory | grep mem_fragmentation_ratio | cut -d: -f2 | tr -d '\r')

if (( $(echo "$FRAG_RATIO > 1.5" | bc -l) )); then
  echo "High memory fragmentation detected: $FRAG_RATIO"
  echo "Consider restarting Redis to defragment memory"
  # 本番環境では慎重に実行
  # docker compose restart redis
fi

# 3. 期限切れキーのクリーンアップ（自動だが確認）
echo "Checking expired keys cleanup..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO keyspace

# 4. Slow logの確認
echo "Checking slow log..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" SLOWLOG GET 10

# 5. 永続化データの保存（RDB）
echo "Triggering RDB save..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" BGSAVE

echo "Redis maintenance complete."
```

### ログ分析

```bash
#!/bin/bash
# weekly-log-analysis.sh

echo "===== Weekly Log Analysis: $(date) ====="

# 1. エラーログの集計
echo "Top errors in the past week:"
docker logs --since 168h auth-service 2>&1 | grep -i "ERROR" | \
  awk -F'"message":' '{print $2}' | sort | uniq -c | sort -rn | head -10

# 2. アクセスログの分析
echo "Top API endpoints by request count:"
docker logs --since 168h user-api 2>&1 | grep "Request completed" | \
  awk -F'"path":' '{print $2}' | cut -d',' -f1 | sort | uniq -c | sort -rn | head -10

# 3. パフォーマンス分析
echo "Slow requests (>1s) count:"
docker logs --since 168h user-api 2>&1 | grep "Request completed" | \
  awk -F'"duration_ms":' '{print $2}' | cut -d',' -f1 | awk '$1 > 1000' | wc -l

# 4. ログファイルサイズ確認
echo "Log file sizes:"
docker ps --format "{{.Names}}" | while read container; do
  LOG_PATH=$(docker inspect --format='{{.LogPath}}' $container)
  if [ -f "$LOG_PATH" ]; then
    du -h "$LOG_PATH" | awk -v name="$container" '{print name": "$1}'
  fi
done

echo "Log analysis complete."
```

### Cron設定（週次）

```bash
# /etc/cron.d/ai-micro-maintenance
# 毎週日曜日午前2時に実行
0 2 * * 0 root /opt/scripts/weekly-postgres-maintenance.sh
30 2 * * 0 root /opt/scripts/weekly-redis-maintenance.sh
0 3 * * 0 root /opt/scripts/weekly-log-analysis.sh
```

---

## 月次メンテナンス

### データベースインデックス最適化

```sql
-- 未使用インデックスの確認
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 重複インデックスの確認
SELECT
    a.indrelid::regclass AS table_name,
    a.indexrelid::regclass AS index1,
    b.indexrelid::regclass AS index2,
    a.indkey AS columns1,
    b.indkey AS columns2
FROM pg_index a
JOIN pg_index b ON a.indrelid = b.indrelid
WHERE a.indexrelid < b.indexrelid
  AND a.indkey::text = b.indkey::text;

-- インデックスブロート確認
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
```

### 古いデータのアーカイブ

```bash
#!/bin/bash
# monthly-data-archive.sh

echo "===== Monthly Data Archive: $(date) ====="

ARCHIVE_DATE=$(date -d '6 months ago' +%Y-%m-%d)

# 1. 古いログエントリをアーカイブ
echo "Archiving old log entries before $ARCHIVE_DATE..."
docker exec postgres psql -U postgres -d admindb -c "
  -- アーカイブテーブルに移動
  INSERT INTO logs_archive
  SELECT * FROM logs
  WHERE created_at < '$ARCHIVE_DATE';

  -- 元テーブルから削除
  DELETE FROM logs
  WHERE created_at < '$ARCHIVE_DATE';
"

# 2. 削除済みドキュメントのクリーンアップ
echo "Cleaning up soft-deleted documents..."
docker exec postgres psql -U postgres -d admindb -c "
  DELETE FROM documents
  WHERE deleted_at IS NOT NULL
    AND deleted_at < '$ARCHIVE_DATE';
"

# 3. セッションテーブルのクリーンアップ
echo "Cleaning up expired sessions..."
docker exec postgres psql -U postgres -d authdb -c "
  DELETE FROM refresh_tokens
  WHERE expires_at < NOW() - INTERVAL '30 days';
"

# 4. バキューム実行
echo "Running VACUUM..."
docker exec postgres psql -U postgres -c "VACUUM FULL;" admindb

echo "Data archive complete."
```

### パフォーマンスレビュー

```bash
#!/bin/bash
# monthly-performance-review.sh

echo "===== Monthly Performance Review: $(date) ====="

# 1. スロークエリトップ10
echo "Top 10 slow queries:"
docker exec postgres psql -U postgres -d authdb -c "
  SELECT
    query,
    calls,
    mean_exec_time,
    max_exec_time,
    total_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"

# 2. Redisキャッシュヒット率
echo "Redis cache hit rate:"
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO stats | \
  grep -E "keyspace_hits|keyspace_misses"

# 3. APIレスポンスタイム（Prometheusから取得）
echo "API response time (p95):"
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[30d]))' | \
  jq -r '.data.result[] | "\(.metric.job): \(.value[1])s"'

# 4. エラー率
echo "Error rate by service:"
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{status=~"5.."}[30d]))by(job)/sum(rate(http_requests_total[30d]))by(job)*100' | \
  jq -r '.data.result[] | "\(.metric.job): \(.value[1])%"'

echo "Performance review complete."
```

### Cron設定（月次）

```bash
# /etc/cron.d/ai-micro-maintenance
# 毎月1日午前1時に実行
0 1 1 * * root /opt/scripts/monthly-data-archive.sh
0 2 1 * * root /opt/scripts/monthly-performance-review.sh
```

---

## システムアップデート

### Dockerイメージの更新

```bash
#!/bin/bash
# update-docker-images.sh

echo "===== Docker Images Update: $(date) ====="

# 1. 現在のイメージバージョン確認
echo "Current images:"
docker images | grep -E "auth-service|user-api|admin-api|user-frontend|admin-frontend"

# 2. 新しいイメージをプル
echo "Pulling new images..."
cd /path/to/ai-micro-service

services=("ai-micro-api-auth" "ai-micro-api-user" "ai-micro-api-admin" "ai-micro-front-user" "ai-micro-front-admin")

for service in "${services[@]}"; do
  echo "Updating $service..."
  cd "$service"

  # バックアップ（設定ファイル）
  cp .env .env.backup

  # 新しいイメージでリビルド
  docker compose build --no-cache

  # ローリングアップデート
  docker compose up -d

  # ヘルスチェック
  sleep 10
  if docker ps | grep -q "$service"; then
    echo "✓ $service updated successfully"
  else
    echo "✗ $service update failed, rolling back..."
    docker compose down
    # 前のイメージで起動
    docker compose up -d
  fi

  cd ..
done

# 3. 未使用イメージのクリーンアップ
echo "Cleaning up old images..."
docker image prune -f

echo "Docker images update complete."
```

### セキュリティパッチ適用

```bash
#!/bin/bash
# apply-security-patches.sh

echo "===== Applying Security Patches: $(date) ====="

# 1. システムパッケージの更新確認
echo "Checking for system updates..."
apt update
apt list --upgradable

# 2. Pythonパッケージの脆弱性スキャン
echo "Scanning Python dependencies for vulnerabilities..."
for service in ai-micro-api-auth ai-micro-api-user ai-micro-api-admin; do
  echo "Checking $service..."
  cd "/path/to/ai-micro-service/$service"

  if [ -f "requirements.txt" ]; then
    pip-audit -r requirements.txt
  elif [ -f "poetry.lock" ]; then
    poetry run safety check
  fi

  cd -
done

# 3. Node.js パッケージの脆弱性スキャン
echo "Scanning Node.js dependencies for vulnerabilities..."
for service in ai-micro-front-user ai-micro-front-admin; do
  echo "Checking $service..."
  cd "/path/to/ai-micro-service/$service"

  npm audit
  # 自動修正（慎重に）
  # npm audit fix

  cd -
done

# 4. Dockerベースイメージの更新
echo "Updating Docker base images..."
docker pull python:3.11-slim
docker pull node:20-alpine
docker pull postgres:15-alpine
docker pull redis:7-alpine

echo "Security patches check complete."
```

---

## メンテナンスモードの管理

### メンテナンスモードの有効化

```bash
#!/bin/bash
# enable-maintenance-mode.sh

echo "Enabling maintenance mode..."

# 1. ユーザーに通知（Slack等）
curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
  -d '{"text":"🔧 System maintenance starting in 5 minutes"}'

# 2. 5分待機
sleep 300

# 3. メンテナンスページを表示
# Nginxリバースプロキシの場合
cat > /etc/nginx/maintenance.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Maintenance</title>
</head>
<body>
  <h1>System Maintenance</h1>
  <p>We are currently performing scheduled maintenance.</p>
  <p>Expected completion: $(date -d '+2 hours' '+%Y-%m-%d %H:%M')</p>
</body>
</html>
EOF

# Nginxにメンテナンスモードを設定
# location / {
#   return 503;
#   error_page 503 /maintenance.html;
# }

nginx -s reload

echo "Maintenance mode enabled."
```

### メンテナンスモードの解除

```bash
#!/bin/bash
# disable-maintenance-mode.sh

echo "Disabling maintenance mode..."

# 1. Nginxの通常モードに戻す
nginx -s reload

# 2. ヘルスチェック
for port in 8001 8002 8003; do
  curl -f "http://localhost:$port/health" || echo "Service $port not ready"
done

# 3. ユーザーに通知
curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
  -d '{"text":"✅ System maintenance completed. All services are now available."}'

echo "Maintenance mode disabled."
```

---

## メンテナンスチェックリスト

### 日次

- [ ] すべてのサービスが正常に稼働しているか確認
- [ ] ディスク使用量が80%未満であることを確認
- [ ] バックアップが正常に完了したことを確認
- [ ] 重大なエラーログがないか確認

### 週次

- [ ] PostgreSQL VACUUM ANALYZE を実行
- [ ] Redisメモリフラグメンテーションを確認
- [ ] ログファイルを分析し、異常パターンがないか確認
- [ ] セキュリティアップデートを確認

### 月次

- [ ] データベースインデックスを最適化
- [ ] 古いデータをアーカイブ
- [ ] パフォーマンスレビューを実施
- [ ] 未使用リソースをクリーンアップ
- [ ] ドキュメントを更新

### 四半期

- [ ] システム全体のセキュリティ監査
- [ ] ディザスタリカバリ手順をテスト
- [ ] キャパシティプランニングを実施
- [ ] アーキテクチャレビューを実施

---

## メンテナンスのベストプラクティス

### 1. 変更管理

- すべての変更を記録
- 変更前にバックアップを取得
- ロールバック計画を準備

### 2. メンテナンスウィンドウ

```yaml
推奨メンテナンス時間:
  日次: 午前3:00 - 4:00（自動化）
  週次: 日曜日 午前2:00 - 5:00
  月次: 毎月第1日曜日 午前1:00 - 6:00
```

### 3. 通知とコミュニケーション

- メンテナンス開始の24時間前に通知
- メンテナンス開始5分前に最終通知
- 完了後に完了通知

### 4. ドキュメント化

- メンテナンス実施内容を記録
- 発見した問題と対処法を記録
- 次回の改善点を記録

### 5. 自動化

```bash
# すべてのメンテナンススクリプトを一箇所に管理
/opt/ai-micro-service/maintenance/
  ├── daily/
  │   ├── health-check.sh
  │   ├── backup.sh
  │   └── disk-check.sh
  ├── weekly/
  │   ├── postgres-maintenance.sh
  │   ├── redis-maintenance.sh
  │   └── log-analysis.sh
  ├── monthly/
  │   ├── data-archive.sh
  │   ├── performance-review.sh
  │   └── index-optimization.sh
  └── utils/
      ├── enable-maintenance-mode.sh
      └── disable-maintenance-mode.sh
```

---

## トラブルシューティング

### メンテナンス中に問題が発生した場合

1. **即座にロールバック**

   ```bash
   # 変更前のバックアップから復元
   /opt/scripts/rollback.sh
   ```
2. **問題を記録**

   - 何が起きたか
   - どの操作の後に発生したか
   - エラーメッセージ
3. **ステークホルダーに連絡**

   - 技術リード
   - プロダクトマネージャー
   - カスタマーサポート
4. **ポストモーテム実施**

   - 根本原因分析
   - 再発防止策

---

## 参考資料

- [01-startup-procedure.md](./01-startup-procedure.md) - システム起動手順
- [02-shutdown-procedure.md](./02-shutdown-procedure.md) - システム停止手順
- [08-backup-restore.md](./08-backup-restore.md) - バックアップ・リストア
- [09-disaster-recovery.md](./09-disaster-recovery.md) - 障害復旧手順
- [../06-database/10-backup-restore.md](../06-database/10-backup-restore.md) - データベースバックアップ

---

**変更履歴**:

- 2025-09-30: 初版作成