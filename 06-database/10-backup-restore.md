# データベースバックアップとリストア

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [バックアップ戦略](#バックアップ戦略)
- [pg_dump と pg_dumpall](#pg_dump-と-pg_dumpall)
- [データベース単位のバックアップ](#データベース単位のバックアップ)
- [リストア手順](#リストア手順)
- [自動バックアップの設定](#自動バックアップの設定)
- [Docker ボリューム管理](#docker-ボリューム管理)
- [災害復旧計画](#災害復旧計画)

---

## バックアップ戦略

### バックアップの種類

| バックアップタイプ | 頻度 | 保持期間 | 用途 |
|---------------|------|---------|------|
| 完全バックアップ | 毎日 | 30日 | 全データベースの復元 |
| データベース別バックアップ | 毎日 | 14日 | 個別データベースの復元 |
| マイグレーション前バックアップ | 必要時 | 永久 | ロールバック用 |
| Docker ボリュームスナップショット | 週次 | 4週 | 完全なシステム復元 |

### RPO と RTO

**RPO (Recovery Point Objective)**: データ損失許容時間
- **目標**: 24時間以内
- **実装**: 毎日深夜にバックアップ

**RTO (Recovery Time Objective)**: システム復旧時間
- **目標**: 1時間以内
- **実装**: 自動リストアスクリプト

---

## pg_dump と pg_dumpall

### pg_dumpall の使用（全データベース）

**コマンド**:
```bash
# すべてのデータベースをバックアップ
docker exec ai-micro-postgres pg_dumpall -U postgres > \
  backup_all_$(date +%Y%m%d_%H%M%S).sql
```

**出力内容**:
- すべてのデータベース（authdb、apidb、admindb）
- ロール（ユーザー）定義
- グローバル設定
- データベース作成文

**ファイルサイズ**:
```bash
# バックアップファイルのサイズ確認
ls -lh backup_all_*.sql

# 例: -rw-r--r-- 1 user user 5.2M Oct 15 03:00 backup_all_20251015_030000.sql
```

**圧縮版**:
```bash
# gzip で圧縮してバックアップ
docker exec ai-micro-postgres pg_dumpall -U postgres | gzip > \
  backup_all_$(date +%Y%m%d_%H%M%S).sql.gz

# 圧縮率の確認
ls -lh backup_all_*.sql.gz
# 例: -rw-r--r-- 1 user user 1.2M Oct 15 03:00 backup_all_20251015_030000.sql.gz
```

### pg_dump の使用（単一データベース）

**基本的な使用方法**:
```bash
# authdb をバックアップ
docker exec ai-micro-postgres pg_dump -U postgres authdb > \
  authdb_backup_$(date +%Y%m%d_%H%M%S).sql

# apidb をバックアップ
docker exec ai-micro-postgres pg_dump -U postgres apidb > \
  apidb_backup_$(date +%Y%m%d_%H%M%S).sql

# admindb をバックアップ
docker exec ai-micro-postgres pg_dump -U postgres admindb > \
  admindb_backup_$(date +%Y%m%d_%H%M%S).sql
```

**カスタムフォーマット（推奨）**:
```bash
# カスタムフォーマットでバックアップ（並列リストア可能）
docker exec ai-micro-postgres pg_dump -U postgres -Fc authdb > \
  authdb_backup_$(date +%Y%m%d_%H%M%S).dump
```

**メリット**:
- 圧縮されたバイナリ形式
- 並列リストア対応（`pg_restore -j 4`）
- テーブル単位の選択的リストア

---

## データベース単位のバックアップ

### authdb のバックアップ

```bash
# スクリプト: backup_authdb.sh
#!/bin/bash

BACKUP_DIR="/Users/makino/Documents/Work/github.com/ai-micro-service/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/authdb_${DATE}.sql.gz"

# バックアップディレクトリ作成
mkdir -p ${BACKUP_DIR}

# バックアップ実行
docker exec ai-micro-postgres pg_dump -U postgres authdb | gzip > ${BACKUP_FILE}

# 結果確認
if [ $? -eq 0 ]; then
    echo "✅ authdb バックアップ成功: ${BACKUP_FILE}"
    ls -lh ${BACKUP_FILE}
else
    echo "❌ authdb バックアップ失敗"
    exit 1
fi

# 古いバックアップを削除（14日以上前）
find ${BACKUP_DIR} -name "authdb_*.sql.gz" -mtime +14 -delete
```

### apidb のバックアップ

```bash
# スクリプト: backup_apidb.sh
#!/bin/bash

BACKUP_DIR="/Users/makino/Documents/Work/github.com/ai-micro-service/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/apidb_${DATE}.sql.gz"

mkdir -p ${BACKUP_DIR}

docker exec ai-micro-postgres pg_dump -U postgres apidb | gzip > ${BACKUP_FILE}

if [ $? -eq 0 ]; then
    echo "✅ apidb バックアップ成功: ${BACKUP_FILE}"
    ls -lh ${BACKUP_FILE}
else
    echo "❌ apidb バックアップ失敗"
    exit 1
fi

find ${BACKUP_DIR} -name "apidb_*.sql.gz" -mtime +14 -delete
```

### admindb のバックアップ

```bash
# スクリプト: backup_admindb.sh
#!/bin/bash

BACKUP_DIR="/Users/makino/Documents/Work/github.com/ai-micro-service/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/admindb_${DATE}.sql.gz"

mkdir -p ${BACKUP_DIR}

docker exec ai-micro-postgres pg_dump -U postgres admindb | gzip > ${BACKUP_FILE}

if [ $? -eq 0 ]; then
    echo "✅ admindb バックアップ成功: ${BACKUP_FILE}"
    ls -lh ${BACKUP_FILE}
else
    echo "❌ admindb バックアップ失敗"
    exit 1
fi

find ${BACKUP_DIR} -name "admindb_*.sql.gz" -mtime +14 -delete
```

### テーブル単位のバックアップ

```bash
# 特定のテーブルのみバックアップ
docker exec ai-micro-postgres pg_dump -U postgres -d authdb -t users > \
  users_table_backup_$(date +%Y%m%d_%H%M%S).sql

# 複数のテーブル
docker exec ai-micro-postgres pg_dump -U postgres -d admindb \
  -t documents -t knowledge_bases > \
  documents_kb_backup_$(date +%Y%m%d_%H%M%S).sql
```

---

## リストア手順

### 完全リストア（pg_dumpall から）

```bash
# 1. 既存のコンテナを停止
docker compose down

# 2. ボリュームを削除（データ完全削除）
docker volume rm ai-micro-postgres_postgres_data

# 3. コンテナを再起動（新しいボリューム作成）
docker compose up -d

# 4. PostgreSQL が起動するまで待機
sleep 10

# 5. バックアップからリストア
cat backup_all_20251015_030000.sql | \
  docker exec -i ai-micro-postgres psql -U postgres

# 6. リストア確認
docker exec ai-micro-postgres psql -U postgres -c "\l"
```

**圧縮ファイルからのリストア**:
```bash
gunzip -c backup_all_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres
```

### データベース単位のリストア

#### authdb のリストア

```bash
# 1. 既存のデータベースを削除（注意！）
docker exec ai-micro-postgres psql -U postgres -c "DROP DATABASE IF EXISTS authdb;"

# 2. データベースを再作成
docker exec ai-micro-postgres psql -U postgres -c "CREATE DATABASE authdb;"

# 3. バックアップからリストア
gunzip -c authdb_backup_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres -d authdb

# 4. リストア確認
docker exec ai-micro-postgres psql -U postgres -d authdb -c "\dt"
docker exec ai-micro-postgres psql -U postgres -d authdb -c "SELECT count(*) FROM users;"
```

#### apidb のリストア

```bash
docker exec ai-micro-postgres psql -U postgres -c "DROP DATABASE IF EXISTS apidb;"
docker exec ai-micro-postgres psql -U postgres -c "CREATE DATABASE apidb;"

gunzip -c apidb_backup_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres -d apidb

# 確認
docker exec ai-micro-postgres psql -U postgres -d apidb -c "SELECT count(*) FROM profiles;"
```

#### admindb のリストア

```bash
docker exec ai-micro-postgres psql -U postgres -c "DROP DATABASE IF EXISTS admindb;"
docker exec ai-micro-postgres psql -U postgres -c "CREATE DATABASE admindb;"

gunzip -c admindb_backup_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres -d admindb

# 確認
docker exec ai-micro-postgres psql -U postgres -d admindb -c "\dt"
```

### カスタムフォーマットからのリストア

```bash
# pg_restore を使用（並列リストア可能）
docker exec ai-micro-postgres pg_restore -U postgres -d authdb \
  -j 4 \  # 4並列
  /path/to/authdb_backup.dump
```

### テーブル単位のリストア

```bash
# 特定のテーブルのみリストア
cat users_table_backup.sql | \
  docker exec -i ai-micro-postgres psql -U postgres -d authdb
```

---

## 自動バックアップの設定

### cron による自動化（macOS/Linux）

**crontab の編集**:
```bash
crontab -e
```

**設定例**:
```cron
# 毎日深夜3時に完全バックアップ
0 3 * * * /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_all.sh

# 毎日深夜4時にデータベース別バックアップ
0 4 * * * /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_authdb.sh
0 4 * * * /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_apidb.sh
0 4 * * * /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_admindb.sh

# 毎週日曜深夜2時にボリュームスナップショット
0 2 * * 0 /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_volume.sh
```

### 自動バックアップスクリプト

**backup_all.sh**:
```bash
#!/bin/bash

set -e

BACKUP_DIR="/Users/makino/Documents/Work/github.com/ai-micro-service/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backup_all_${DATE}.sql.gz"
LOG_FILE="${BACKUP_DIR}/backup_${DATE}.log"

# ログ開始
echo "=== バックアップ開始: ${DATE} ===" | tee ${LOG_FILE}

# バックアップディレクトリ作成
mkdir -p ${BACKUP_DIR}

# 完全バックアップ実行
echo "pg_dumpall 実行中..." | tee -a ${LOG_FILE}
docker exec ai-micro-postgres pg_dumpall -U postgres | gzip > ${BACKUP_FILE} 2>> ${LOG_FILE}

if [ $? -eq 0 ]; then
    echo "✅ バックアップ成功: ${BACKUP_FILE}" | tee -a ${LOG_FILE}
    ls -lh ${BACKUP_FILE} | tee -a ${LOG_FILE}

    # Slack 通知（オプション）
    curl -X POST ${SLACK_WEBHOOK_URL} \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"✅ PostgreSQL バックアップ成功: ${DATE}\"}"
else
    echo "❌ バックアップ失敗" | tee -a ${LOG_FILE}

    # Slack 通知（エラー）
    curl -X POST ${SLACK_WEBHOOK_URL} \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"❌ PostgreSQL バックアップ失敗: ${DATE}\"}"

    exit 1
fi

# 古いバックアップを削除（30日以上前）
echo "古いバックアップを削除中..." | tee -a ${LOG_FILE}
find ${BACKUP_DIR} -name "backup_all_*.sql.gz" -mtime +30 -delete

# 古いログを削除（90日以上前）
find ${BACKUP_DIR} -name "backup_*.log" -mtime +90 -delete

echo "=== バックアップ完了: $(date +%Y%m%d_%H%M%S) ===" | tee -a ${LOG_FILE}
```

**実行権限の付与**:
```bash
chmod +x /Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_all.sh
```

### AWS S3 への自動アップロード

```bash
#!/bin/bash

# backup_to_s3.sh

BACKUP_DIR="/Users/makino/Documents/Work/github.com/ai-micro-service/backups"
S3_BUCKET="s3://your-backup-bucket/postgres/"

# ローカルバックアップ実行
/Users/makino/Documents/Work/github.com/ai-micro-service/scripts/backup_all.sh

# 最新のバックアップファイルを取得
LATEST_BACKUP=$(ls -t ${BACKUP_DIR}/backup_all_*.sql.gz | head -1)

# S3 にアップロード
aws s3 cp ${LATEST_BACKUP} ${S3_BUCKET}

if [ $? -eq 0 ]; then
    echo "✅ S3 アップロード成功: ${LATEST_BACKUP}"
else
    echo "❌ S3 アップロード失敗"
    exit 1
fi

# S3 の古いバックアップを削除（30日以上前）
aws s3 ls ${S3_BUCKET} | while read -r line; do
    createDate=$(echo $line | awk {'print $1" "$2'})
    createDate=$(date -d "$createDate" +%s)
    olderThan=$(date -d "30 days ago" +%s)

    if [[ $createDate -lt $olderThan ]]; then
        fileName=$(echo $line | awk {'print $4'})
        if [[ $fileName != "" ]]; then
            aws s3 rm ${S3_BUCKET}${fileName}
        fi
    fi
done
```

---

## Docker ボリューム管理

### ボリュームのバックアップ

```bash
# Docker ボリュームをtar.gzでバックアップ
docker run --rm \
  -v ai-micro-postgres_postgres_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/postgres_volume_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
```

### ボリュームのリストア

```bash
# 1. 既存のボリュームを削除
docker volume rm ai-micro-postgres_postgres_data

# 2. 新しいボリュームを作成
docker volume create ai-micro-postgres_postgres_data

# 3. バックアップからリストア
docker run --rm \
  -v ai-micro-postgres_postgres_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/postgres_volume_20251015_030000.tar.gz -C /data

# 4. コンテナを起動
docker compose up -d
```

### ボリュームのクローン

```bash
# 開発環境から本番環境へのデータコピー
docker run --rm \
  -v ai-micro-postgres_postgres_data:/source:ro \
  -v production_postgres_data:/dest \
  alpine sh -c "cd /source && cp -a . /dest"
```

---

## 災害復旧計画

### 災害シナリオと復旧手順

#### シナリオ1: データベース破損

**症状**: PostgreSQL が起動しない、データが読めない

**復旧手順**:
```bash
# 1. 最新の完全バックアップを確認
ls -lt backups/backup_all_*.sql.gz | head -1

# 2. コンテナとボリュームを削除
docker compose down
docker volume rm ai-micro-postgres_postgres_data

# 3. コンテナ再起動
docker compose up -d
sleep 10

# 4. バックアップからリストア
gunzip -c backups/backup_all_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres

# 5. データ確認
docker exec ai-micro-postgres psql -U postgres -c "\l"
docker exec ai-micro-postgres psql -U postgres -d authdb -c "SELECT count(*) FROM users;"
```

**復旧時間**: 約15分（データ量による）

#### シナリオ2: 誤ったデータ削除

**症状**: ユーザーが誤ってデータを削除した

**復旧手順**:
```bash
# 1. 影響範囲の確認
docker exec ai-micro-postgres psql -U postgres -d authdb -c \
  "SELECT count(*) FROM users WHERE created_at < '2025-10-15';"

# 2. 削除前のバックアップを特定
# （削除時刻が 2025-10-15 14:00 の場合、その直前のバックアップ）
ls -lt backups/backup_all_*.sql.gz

# 3. 一時データベースにリストア
docker exec ai-micro-postgres psql -U postgres -c "CREATE DATABASE authdb_temp;"

gunzip -c backups/backup_all_20251015_030000.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres -d authdb_temp

# 4. 削除されたデータを抽出
docker exec ai-micro-postgres psql -U postgres -d authdb_temp -c \
  "COPY (SELECT * FROM users WHERE id IN ('uuid1', 'uuid2')) TO STDOUT;" > deleted_users.csv

# 5. 本番データベースに再挿入
cat deleted_users.csv | docker exec -i ai-micro-postgres psql -U postgres -d authdb -c \
  "COPY users FROM STDIN;"

# 6. 一時データベースを削除
docker exec ai-micro-postgres psql -U postgres -c "DROP DATABASE authdb_temp;"
```

**復旧時間**: 約30分

#### シナリオ3: マイグレーション失敗

**症状**: スキーマ変更後にアプリケーションが動作しない

**復旧手順**:
```bash
# 1. マイグレーション前のバックアップからリストア
gunzip -c backups/backup_before_migration_20251015.sql.gz | \
  docker exec -i ai-micro-postgres psql -U postgres

# 2. アプリケーションを旧バージョンにロールバック
git checkout v1.0.0
docker compose down
docker compose up -d --build

# 3. 動作確認
curl http://localhost:8001/health
```

**復旧時間**: 約10分

---

## モニタリングとアラート

### バックアップ成功の確認

```bash
# 最新のバックアップが24時間以内か確認
LATEST_BACKUP=$(ls -t backups/backup_all_*.sql.gz | head -1)
BACKUP_AGE=$(( ($(date +%s) - $(stat -f %m ${LATEST_BACKUP})) / 3600 ))

if [ ${BACKUP_AGE} -gt 24 ]; then
    echo "⚠️ 警告: 最新バックアップが24時間以上前です"
    # Slack 通知
    curl -X POST ${SLACK_WEBHOOK_URL} \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"⚠️ PostgreSQL バックアップが24時間以上実行されていません\"}"
fi
```

### バックアップサイズの監視

```bash
# バックアップサイズの異常を検知
LATEST_BACKUP=$(ls -t backups/backup_all_*.sql.gz | head -1)
BACKUP_SIZE=$(stat -f %z ${LATEST_BACKUP})
EXPECTED_MIN_SIZE=$((1 * 1024 * 1024))  # 1MB

if [ ${BACKUP_SIZE} -lt ${EXPECTED_MIN_SIZE} ]; then
    echo "⚠️ 警告: バックアップサイズが異常に小さいです"
    # Slack 通知
fi
```

---

## ベストプラクティス

### バックアップのテスト

**定期的なリストアテスト（月次推奨）**:
```bash
# テスト環境でリストアを実行
docker run --name postgres-restore-test -e POSTGRES_PASSWORD=test -d postgres:15
sleep 10

gunzip -c backups/backup_all_latest.sql.gz | \
  docker exec -i postgres-restore-test psql -U postgres

# データ確認
docker exec postgres-restore-test psql -U postgres -c "\l"

# クリーンアップ
docker stop postgres-restore-test
docker rm postgres-restore-test
```

### 3-2-1 ルール

- **3**: 3つのコピーを保持
  - オリジナル（本番データベース）
  - ローカルバックアップ
  - リモートバックアップ（S3等）

- **2**: 2種類の異なるメディア
  - ローカルディスク
  - クラウドストレージ

- **1**: 1つはオフサイト
  - S3、別リージョン

---

## 関連ドキュメント

- [データベース概要](./01-overview.md)
- [データベース設定](./02-database-configuration.md)
- [マイグレーション管理](./09-migration-management.md)

---

**おわりに**: バックアップは保険です。使わないことが最善ですが、必要になったときには必ず役立ちます。定期的なバックアップとリストアテストを忘れずに実施してください。