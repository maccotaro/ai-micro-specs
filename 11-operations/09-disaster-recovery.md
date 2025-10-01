# 障害復旧手順（Disaster Recovery）

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムの災害復旧計画（DRP: Disaster Recovery Plan）と復旧手順を定義します。

## 災害復旧の目標

### RPO/RTO

| メトリクス | 目標値 | 説明 |
|-----------|--------|------|
| **RPO** (Recovery Point Objective) | 6時間 | 許容されるデータ損失の時間範囲 |
| **RTO** (Recovery Time Objective) | 4時間 | 許容されるサービス停止時間 |
| **MTTR** (Mean Time To Repair) | 2時間 | 平均復旧時間 |

### 災害レベル

| レベル | 定義 | 例 |
|--------|------|-----|
| **Level 1** | 単一コンポーネントの障害 | 1つのマイクロサービス停止 |
| **Level 2** | 複数コンポーネントの障害 | データベース障害 |
| **Level 3** | システム全体の障害 | サーバー全体のダウン |
| **Level 4** | 完全な災害 | データセンター全体の障害 |

---

## 災害シナリオと対応

### Level 1: 単一サービス障害

#### シナリオ: Auth Service がダウン

**影響範囲**:

- 新規ログインができない
- トークンリフレッシュができない
- 既存のアクティブセッションは影響なし（短期間）

**検知方法**:

- Prometheusアラート: `AuthServiceDown`
- ヘルスチェック失敗
- ユーザーからの報告

**復旧手順**:

```bash
# 1. サービス状態確認
docker ps | grep auth-service
docker logs auth-service --tail 100

# 2. 再起動試行
cd ai-micro-api-auth
docker compose restart

# 3. ヘルスチェック
curl -f http://localhost:8002/health

# 4. 再起動で解決しない場合
docker compose down
docker compose up -d

# 5. ログ確認
docker logs auth-service -f

# 6. 依存サービス確認
# PostgreSQL
docker exec postgres psql -U postgres -c "SELECT 1"

# Redis
docker exec redis redis-cli -a "${REDIS_PASSWORD}" ping
```

**予防措置**:

- 自動再起動ポリシーの設定
- ヘルスチェック監視
- リソース制限の適切な設定

---

### Level 2: データベース障害

#### シナリオ: PostgreSQL データ破損

**影響範囲**:

- 全サービスが機能停止
- データの読み書きができない

**検知方法**:

- Prometheusアラート: `PostgreSQLDown`
- アプリケーションログにDB接続エラー
- データ整合性エラー

**復旧手順**:

```bash
#!/bin/bash
# disaster-recovery-postgres.sh

echo "===== PostgreSQL Disaster Recovery Started: $(date) ====="

# 1. 現在の状態を記録
echo "Step 1: Recording current state..."
docker logs postgres > /tmp/postgres-failure-$(date +%Y%m%d_%H%M%S).log
docker inspect postgres > /tmp/postgres-inspect-$(date +%Y%m%d_%H%M%S).json

# 2. すべてのアプリケーションサービスを停止
echo "Step 2: Stopping application services..."
for service in ai-micro-api-auth ai-micro-api-user ai-micro-api-admin ai-micro-front-user ai-micro-front-admin; do
  cd /path/to/ai-micro-service/$service
  docker compose down
  cd -
done

# 3. PostgreSQL停止
echo "Step 3: Stopping PostgreSQL..."
cd /path/to/ai-micro-service/ai-micro-postgres
docker compose down

# 4. データボリュームの確認
echo "Step 4: Checking data volume..."
docker volume inspect postgres_data

# 5. 最新のバックアップを特定
echo "Step 5: Identifying latest backup..."
LATEST_BACKUP=$(ls -t /backups/postgres/all_databases_*.sql.gz | head -1)
echo "Latest backup: $LATEST_BACKUP"

# 6. データボリュームをクリア
echo "Step 6: Clearing data volume..."
read -p "WARNING: This will delete all PostgreSQL data. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Recovery cancelled."
  exit 1
fi

docker volume rm postgres_data
docker volume create postgres_data

# 7. PostgreSQL起動（空の状態）
echo "Step 7: Starting PostgreSQL..."
docker compose up -d
sleep 10

# 8. バックアップからリストア
echo "Step 8: Restoring from backup..."
gunzip -c "$LATEST_BACKUP" | docker exec -i postgres psql -U postgres

# 9. データ整合性確認
echo "Step 9: Verifying data integrity..."
docker exec postgres psql -U postgres -c "\l"
docker exec postgres psql -U postgres -d authdb -c "SELECT count(*) FROM users;"
docker exec postgres psql -U postgres -d apidb -c "SELECT count(*) FROM profiles;"
docker exec postgres psql -U postgres -d admindb -c "SELECT count(*) FROM documents;"

# 10. アプリケーションサービスを起動
echo "Step 10: Starting application services..."
/opt/scripts/startup-all.sh

# 11. 全体ヘルスチェック
echo "Step 11: Running health checks..."
sleep 30
for port in 8001 8002 8003; do
  curl -f "http://localhost:$port/health" && echo "✓ Service on port $port is healthy"
done

echo "===== PostgreSQL Disaster Recovery Completed: $(date) ====="

# 12. 通知
curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
  -d '{"text":"✅ PostgreSQL disaster recovery completed successfully"}'
```

---

### Level 3: システム全体障害

#### シナリオ: ホストサーバーの障害

**影響範囲**:

- 全サービス停止
- すべての機能が利用不可

**検知方法**:

- サーバー監視ツールからのアラート
- すべてのサービスが応答しない
- pingが通らない

**復旧手順**:

```bash
#!/bin/bash
# disaster-recovery-full-system.sh

echo "===== Full System Disaster Recovery Started: $(date) ====="

# 前提: 新しいサーバーが用意されている

# 1. Dockerインストール
echo "Step 1: Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Docker Composeインストール
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 2. システムファイルの復元
echo "Step 2: Restoring system files..."
# リポジトリからクローン
git clone https://github.com/your-org/ai-micro-service.git /opt/ai-micro-service
cd /opt/ai-micro-service

# 3. 最新のフルバックアップを特定
echo "Step 3: Identifying latest full backup..."
# S3からダウンロード（またはオフサイトバックアップから）
aws s3 cp s3://your-backup-bucket/ai-micro-service/full_backup_latest.tar.gz /tmp/

# バックアップ解凍
tar -xzf /tmp/full_backup_latest.tar.gz -C /tmp/

# 4. 設定ファイル復元
echo "Step 4: Restoring configuration files..."
tar -xzf /tmp/*/config_*.tar.gz -C /opt/ai-micro-service

# 5. インフラサービス起動
echo "Step 5: Starting infrastructure services..."
cd /opt/ai-micro-service/ai-micro-postgres
docker compose up -d
sleep 15

cd /opt/ai-micro-service/ai-micro-redis
docker compose up -d
sleep 10

# 6. データベース復元
echo "Step 6: Restoring databases..."
gunzip -c /tmp/*/all_databases_*.sql.gz | docker exec -i postgres psql -U postgres

# 7. Redis復元
echo "Step 7: Restoring Redis..."
gunzip -c /tmp/*/redis_*.rdb.gz > /tmp/dump.rdb
docker cp /tmp/dump.rdb redis:/data/dump.rdb
docker compose -f /opt/ai-micro-service/ai-micro-redis/docker-compose.yml restart

# 8. ファイル復元
echo "Step 8: Restoring files..."
tar -xzf /tmp/*/files_backup_*.tar.gz -C /tmp/
# （ファイルを適切なディレクトリにコピー）

# 9. アプリケーションサービス起動
echo "Step 9: Starting application services..."
cd /opt/ai-micro-service/ai-micro-api-auth && docker compose up -d && cd -
sleep 10
cd /opt/ai-micro-service/ai-micro-api-user && docker compose up -d && cd -
cd /opt/ai-micro-service/ai-micro-api-admin && docker compose up -d && cd -
sleep 10
cd /opt/ai-micro-service/ai-micro-front-user && docker compose up -d && cd -
cd /opt/ai-micro-service/ai-micro-front-admin && docker compose up -d && cd -

# 10. ヘルスチェック
echo "Step 10: Running comprehensive health checks..."
sleep 30

# サービスヘルスチェック
for port in 8001 8002 8003; do
  if curl -f "http://localhost:$port/health" > /dev/null 2>&1; then
    echo "✓ Service on port $port is healthy"
  else
    echo "✗ Service on port $port is unhealthy"
  fi
done

# フロントエンド確認
curl -I http://localhost:3002 | head -1
curl -I http://localhost:3003 | head -1

# 11. データ整合性確認
echo "Step 11: Verifying data integrity..."
docker exec postgres psql -U postgres -d authdb -c "SELECT count(*) FROM users;"
docker exec postgres psql -U postgres -d apidb -c "SELECT count(*) FROM profiles;"
docker exec postgres psql -U postgres -d admindb -c "SELECT count(*) FROM documents;"

# 12. 監視システムの再構築
echo "Step 12: Rebuilding monitoring stack..."
# Prometheus, Grafana等のセットアップ

echo "===== Full System Disaster Recovery Completed: $(date) ====="

# 13. 通知とドキュメント
curl -X POST ${SLACK_WEBHOOK_URL} -H 'Content-Type: application/json' \
  -d '{"text":"✅ Full system disaster recovery completed. All services operational."}'

# インシデントレポート作成
cat > /tmp/incident_report_$(date +%Y%m%d).md <<EOF
# Disaster Recovery Report

**Date**: $(date)
**Incident**: Full system failure
**Recovery Time**: X hours
**Data Loss**: X hours (RPO: 6 hours)

## Timeline
- Detection: YYYY-MM-DD HH:MM
- Recovery Started: YYYY-MM-DD HH:MM
- Recovery Completed: YYYY-MM-DD HH:MM

## Actions Taken
1. Provisioned new server
2. Restored from backup dated YYYY-MM-DD
3. Verified data integrity
4. All services operational

## Lessons Learned
- [To be filled]

## Action Items
- [To be filled]
EOF

echo "Incident report created: /tmp/incident_report_$(date +%Y%m%d).md"
```

---

### Level 4: データセンター全体の障害

#### シナリオ: 完全な災害（火災、地震等）

**影響範囲**:

- すべてのハードウェアが失われる
- オフサイトバックアップからの復旧が必要

**前提条件**:

- オフサイトバックアップが存在する（S3等）
- 別のデータセンターまたはクラウド環境が利用可能

**復旧手順**:

```bash
#!/bin/bash
# disaster-recovery-datacenter-failure.sh

echo "===== Datacenter Disaster Recovery Started: $(date) ====="

# 1. 新しいクラウド環境のプロビジョニング
echo "Step 1: Provisioning new cloud environment..."
# AWS EC2インスタンス作成（例）
# terraform apply -var="environment=disaster-recovery"

# 2. S3からバックアップダウンロード
echo "Step 2: Downloading backups from S3..."
aws s3 sync s3://your-backup-bucket/ai-micro-service /tmp/backups/ \
  --exclude "*" \
  --include "full_backup_*.tar.gz"

# 最新バックアップ
LATEST_BACKUP=$(ls -t /tmp/backups/full_backup_*.tar.gz | head -1)
echo "Latest backup: $LATEST_BACKUP"

# 3. Level 3と同様の復旧手順を実行
# （上記の disaster-recovery-full-system.sh を実行）
/opt/scripts/disaster-recovery-full-system.sh "$LATEST_BACKUP"

# 4. DNSの更新
echo "Step 4: Updating DNS records..."
# 新しいIPアドレスにDNSを更新
# aws route53 change-resource-record-sets ...

# 5. SSL証明書の設定
echo "Step 5: Configuring SSL certificates..."
# Let's Encrypt等で証明書を取得

# 6. 最終検証
echo "Step 6: Final verification..."
# 外部からのアクセステスト
curl -f https://your-domain.com/health

echo "===== Datacenter Disaster Recovery Completed: $(date) ====="
```

---

## 災害復旧テスト

### 定期的な復旧演習

**頻度**: 四半期に1回

**テストシナリオ**:

1. **単一サービス障害シミュレーション**

   ```bash
   # Auth Serviceを意図的に停止
   docker stop auth-service

   # 復旧手順を実行
   # 復旧時間を計測
   ```
2. **データベース障害シミュレーション**

   ```bash
   # PostgreSQLを停止してバックアップから復旧
   # RPO/RTOを達成できるか確認
   ```
3. **完全復旧テスト（年1回）**

   ```bash
   # ステージング環境で本番同様の構成を破壊
   # オフサイトバックアップから完全復旧
   ```

### テスト結果の記録

```markdown
# Disaster Recovery Test Report

**Test Date**: 2025-09-30
**Test Type**: Full System Recovery
**Environment**: Staging

## Results
- **RTO Goal**: 4 hours
- **Actual RTO**: 3.5 hours ✓
- **RPO Goal**: 6 hours
- **Actual RPO**: 4 hours ✓

## Issues Identified
1. Backup download from S3 took longer than expected
2. DNS propagation delay

## Action Items
1. Optimize backup file size
2. Pre-configure DNS records for failover
```

---

## 災害復旧チェックリスト

### 事前準備

- [ ] 最新のバックアップが存在することを確認
- [ ] オフサイトバックアップが正常に保存されている
- [ ] 復旧手順書が最新である
- [ ] 復旧スクリプトが動作することを確認
- [ ] 緊急連絡先リストが最新である
- [ ] 代替インフラ（クラウド等）が利用可能

### 障害発生時

- [ ] インシデント管理チケットを作成
- [ ] ステークホルダーに通知（顧客、経営陣）
- [ ] 障害レベルを判定
- [ ] 復旧チームを招集
- [ ] 復旧手順を開始
- [ ] 進捗を定期的に報告

### 復旧後

- [ ] すべてのサービスが正常稼働していることを確認
- [ ] データ整合性を検証
- [ ] 監視システムが正常に動作していることを確認
- [ ] ユーザーに復旧を通知
- [ ] インシデントレポートを作成
- [ ] ポストモーテムを実施
- [ ] 再発防止策を文書化

---

## 緊急連絡先

```yaml
# emergency-contacts.yml

技術チーム:
  一次対応:
    - 名前: 技術リード
      電話: +81-XX-XXXX-XXXX
      Email: tech-lead@example.com

  二次対応:
    - 名前: インフラエンジニア
      電話: +81-XX-XXXX-XXXX
      Email: infra@example.com

ステークホルダー:
  プロダクトマネージャー:
    - 名前: PM
      電話: +81-XX-XXXX-XXXX
      Email: pm@example.com

  経営陣:
    - 名前: CTO
      電話: +81-XX-XXXX-XXXX
      Email: cto@example.com

外部ベンダー:
  クラウドプロバイダー:
    - サポート番号: +81-XX-XXXX-XXXX
    - アカウントID: XXXXXXXXX

  データセンター:
    - サポート番号: +81-XX-XXXX-XXXX
    - 契約番号: XXXXXXXXX
```

---

## 災害復旧のベストプラクティス

### 1. 3-2-1 バックアップルール

- **3** つのコピーを保持
- **2** つの異なるメディアに保存
- **1** つはオフサイトに保存

### 2. 自動化

- バックアップは自動化
- 復旧手順もできる限り自動化
- 定期的なテストも自動化

### 3. ドキュメント化

- 復旧手順を詳細に文書化
- 最新の状態に保つ
- 誰でも実行できるように

### 4. 定期的なテスト

- 四半期に1回は復旧テスト
- 実際に障害を発生させて訓練
- テスト結果を記録・改善

### 5. コミュニケーション

- ステークホルダーへの定期報告
- インシデント発生時の明確な連絡体制
- 復旧後のポストモーテム

---

## 参考資料

- [08-backup-restore.md](./08-backup-restore.md) - バックアップ・リストア手順
- [01-startup-procedure.md](./01-startup-procedure.md) - システム起動手順
- [06-troubleshooting.md](./06-troubleshooting.md) - トラブルシューティング
- [../06-database/10-backup-restore.md](../06-database/10-backup-restore.md) - データベースバックアップ

---

**変更履歴**:

- 2025-09-30: 初版作成