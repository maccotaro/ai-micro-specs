# Redis 永続化設定

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [永続化の概要](#永続化の概要)
- [RDB (Redis Database)](#rdb-redis-database)
- [AOF (Append Only File)](#aof-append-only-file)
- [RDB vs AOF 比較](#rdb-vs-aof-比較)
- [ハイブリッド永続化](#ハイブリッド永続化)
- [バックアップ戦略](#バックアップ戦略)
- [リストア手順](#リストア手順)
- [運用ベストプラクティス](#運用ベストプラクティス)

---

## 永続化の概要

### 永続化の必要性

Redis はインメモリデータストアですが、以下の理由から永続化が重要です：

1. **データ保護**: サーバー再起動時にデータを保持
2. **障害回復**: クラッシュ時のデータ損失を最小化
3. **バックアップ**: 定期的なスナップショットによるデータ保護
4. **レプリケーション**: スレーブノードへのデータ同期

### ai-micro-service での永続化戦略

現在の構成では **RDB（スナップショット）** を使用しています：

- **利点**: シンプルで軽量、バックアップが容易
- **欠点**: 最新データが失われる可能性（最大15分）
- **用途**: セッション管理、キャッシュ（短命データ）

---

## RDB (Redis Database)

### RDB の仕組み

RDB は、指定された条件でデータベース全体のスナップショットをディスクに保存します。

**保存ファイル**: `/data/dump.rdb`

### 現在の設定

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-redis/redis.conf`

```conf
# RDB スナップショット設定
save 900 1      # 900秒間に1回以上の変更があれば保存
save 300 10     # 300秒間に10回以上の変更があれば保存
save 60 10000   # 60秒間に10000回以上の変更があれば保存

# エラー時の書き込み停止
stop-writes-on-bgsave-error yes

# RDB 圧縮
rdbcompression yes

# RDB チェックサム
rdbchecksum yes

# ファイル名
dbfilename dump.rdb

# 保存ディレクトリ
dir /data
```

### save 設定の解説

| 設定 | 意味 | 使用ケース |
|-----|------|----------|
| `save 900 1` | 15分間に1回以上変更 | 低頻度更新時のバックアップ |
| `save 300 10` | 5分間に10回以上変更 | 中頻度更新時のバックアップ |
| `save 60 10000` | 1分間に10000回以上変更 | 高頻度更新時のバックアップ |

### 手動スナップショット

```bash
# SAVE コマンド（ブロッキング）
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} SAVE

# BGSAVE コマンド（ノンブロッキング、推奨）
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} BGSAVE

# BGSAVE の状態確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} LASTSAVE
```

### BGSAVE の仕組み

```
1. Redis が fork() を実行してバックグラウンドプロセスを作成
2. 子プロセスが現在のデータセットを dump.rdb に書き込み
3. 書き込み完了後、古い dump.rdb を新しいファイルで置き換え
4. 親プロセスは通常通り動作を継続
```

**メリット**:
- メインプロセスをブロックしない
- パフォーマンスへの影響が最小限

**デメリット**:
- fork() 時にメモリ使用量が一時的に増加
- 大量のデータがある場合は時間がかかる

### RDB の自動実行確認

```bash
# 最後のスナップショット時刻
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} LASTSAVE

# RDB 保存状態の確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO persistence
```

**出力例**:
```
# Persistence
loading:0
rdb_changes_since_last_save:45
rdb_bgsave_in_progress:0
rdb_last_save_time:1727683200
rdb_last_bgsave_status:ok
rdb_last_bgsave_time_sec:2
rdb_current_bgsave_time_sec:-1
```

---

## AOF (Append Only File)

### AOF の仕組み

AOF は、すべての書き込み操作をログファイルに追記します。Redis 再起動時にログを再実行してデータを復元します。

**保存ファイル**: `/data/appendonly.aof`

### AOF 設定（現在は無効）

**ファイル**: `redis.conf`

```conf
# AOF を無効化（現在の設定）
appendonly no

# AOF ファイル名
appendfilename "appendonly.aof"

# fsync ポリシー
appendfsync everysec

# AOF リライト中の fsync
no-appendfsync-on-rewrite no

# AOF 自動リライト
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

### AOF を有効化する場合

**本番環境でより強固なデータ保護が必要な場合**:

```conf
# AOF を有効化
appendonly yes

# fsync ポリシー（推奨: everysec）
appendfsync everysec
```

### appendfsync ポリシー

| ポリシー | 説明 | データ損失リスク | パフォーマンス |
|---------|------|---------------|-------------|
| `always` | 書き込みごとに fsync | 最小（1コマンドのみ） | 最も遅い |
| `everysec` | 1秒ごとに fsync | 小（最大1秒分） | 高速 |
| `no` | OS に任せる | 大（数十秒分） | 最も高速 |

**推奨**: `everysec`（パフォーマンスと耐久性のバランス）

### AOF リライト

AOF ファイルは時間とともに肥大化するため、定期的にリライト（最適化）が必要です。

```bash
# 手動 AOF リライト
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} BGREWRITEAOF

# リライト状態の確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO persistence | grep aof
```

---

## RDB vs AOF 比較

### 機能比較表

| 項目 | RDB | AOF |
|-----|-----|-----|
| **データ損失リスク** | 中（最大15分） | 小（最大1秒） |
| **ファイルサイズ** | 小（圧縮） | 大（未圧縮ログ） |
| **復旧速度** | 高速 | 低速 |
| **メモリ使用量** | fork 時に増加 | 少ない |
| **CPU 負荷** | fork 時に高い | 低い |
| **設定の複雑さ** | シンプル | やや複雑 |

### 使用ケース別推奨

| 使用ケース | 推奨方式 | 理由 |
|----------|--------|------|
| セッション管理 | RDB | データは短命、完全な耐久性不要 |
| キャッシュ | RDB または None | 再生成可能なデータ |
| ショッピングカート | AOF | データ損失が許容できない |
| ユーザー設定 | RDB + AOF | バランス型 |
| リアルタイムメッセージング | AOF | 高い耐久性が必要 |

### ai-micro-service での選択

**現在: RDB のみ**

理由:
- セッション管理が主な用途（短命データ）
- プロファイルキャッシュは再生成可能
- トークンブラックリストは TTL で自動削除
- 最大15分のデータ損失は許容範囲

**将来的に AOF を検討すべきケース**:
- ジョブステータスが重要になった場合
- 永続的なキューを実装する場合
- ユーザーの重要な状態を保存する場合

---

## ハイブリッド永続化

### RDB + AOF の併用

Redis 4.0 以降では、RDB と AOF を同時に有効化できます。

**設定例**:
```conf
# RDB 有効化
save 900 1
save 300 10
save 60 10000

# AOF 有効化
appendonly yes
appendfsync everysec

# AOF リライト時に RDB を使用（Redis 4.0+）
aof-use-rdb-preamble yes
```

### メリット

- **高速復旧**: RDB で大部分を復元、AOF で最新データを補完
- **データ損失最小化**: AOF による高い耐久性
- **柔軟性**: 両方のバックアップを保持

### デメリット

- 設定が複雑
- ディスク使用量が増加
- 管理の手間が増加

---

## バックアップ戦略

### 1. 自動バックアップ（RDB）

Redis の `save` 設定により自動的にスナップショットが作成されます。

### 2. 定期的な手動バックアップ

```bash
# バックアップスクリプト（Cron で実行）
#!/bin/bash

BACKUP_DIR="/backup/redis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# BGSAVE 実行
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} BGSAVE

# 完了を待つ
while [ $(docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO persistence | grep rdb_bgsave_in_progress:1 | wc -l) -eq 1 ]; do
  echo "Waiting for BGSAVE to complete..."
  sleep 2
done

# dump.rdb をコピー
docker cp ai-micro-redis:/data/dump.rdb "${BACKUP_DIR}/dump_${TIMESTAMP}.rdb"

echo "Backup completed: ${BACKUP_DIR}/dump_${TIMESTAMP}.rdb"

# 古いバックアップを削除（7日以前）
find "${BACKUP_DIR}" -name "dump_*.rdb" -mtime +7 -delete
```

### 3. Cron 設定

```bash
# Crontab に追加（毎日午前3時にバックアップ）
0 3 * * * /path/to/redis_backup.sh >> /var/log/redis_backup.log 2>&1
```

### 4. バックアップの検証

```bash
# バックアップファイルの整合性チェック
redis-check-rdb /backup/redis/dump_20250930_030000.rdb
```

### 5. リモートバックアップ

```bash
# AWS S3 にバックアップをアップロード
aws s3 cp "${BACKUP_DIR}/dump_${TIMESTAMP}.rdb" \
  s3://my-redis-backups/ai-micro-service/

# Google Cloud Storage
gsutil cp "${BACKUP_DIR}/dump_${TIMESTAMP}.rdb" \
  gs://my-redis-backups/ai-micro-service/
```

---

## リストア手順

### 1. RDB からのリストア

```bash
# 1. Redis を停止
docker compose stop redis

# 2. 既存の dump.rdb を削除
docker exec ai-micro-redis rm /data/dump.rdb

# 3. バックアップファイルをコピー
docker cp /backup/redis/dump_20250930_030000.rdb ai-micro-redis:/data/dump.rdb

# 4. 権限設定
docker exec ai-micro-redis chown redis:redis /data/dump.rdb

# 5. Redis を起動
docker compose start redis

# 6. ログで復元を確認
docker compose logs -f redis
```

### 2. 別の Redis インスタンスへのリストア

```bash
# 1. 新しい Redis インスタンスを起動
docker run -d --name redis-restore \
  -v /backup/redis/dump_20250930_030000.rdb:/data/dump.rdb:ro \
  redis:7

# 2. データ確認
docker exec redis-restore redis-cli DBSIZE

# 3. 必要に応じてデータを移行
```

### 3. AOF からのリストア（AOF 有効時）

```bash
# 1. Redis を停止
docker compose stop redis

# 2. appendonly.aof をコピー
docker cp /backup/redis/appendonly.aof ai-micro-redis:/data/

# 3. Redis を起動
docker compose start redis

# 4. Redis が AOF を再実行してデータを復元
# 大きなファイルの場合は時間がかかる
```

---

## 運用ベストプラクティス

### 1. 定期的なバックアップ

- 毎日1回のスナップショット（深夜時間帯）
- 週次で別のストレージにコピー
- 月次でアーカイブ保存

### 2. バックアップの保持期間

```
日次バックアップ: 7日間
週次バックアップ: 4週間
月次バックアップ: 12ヶ月
```

### 3. 監視とアラート

```python
# バックアップ失敗の監視

def check_backup_status():
    """
    最後のバックアップが成功したか確認
    """

    info = redis_client.info("persistence")

    # 最後の BGSAVE ステータス
    if info["rdb_last_bgsave_status"] != "ok":
        send_alert("Redis backup failed!")

    # 最後のバックアップ時刻
    last_save = datetime.fromtimestamp(info["rdb_last_save_time"])
    age = (datetime.now() - last_save).total_seconds()

    # 24時間以上バックアップがない場合
    if age > 86400:
        send_alert(f"Redis backup is too old: {age/3600:.1f} hours")
```

### 4. ディスク容量の監視

```bash
# ディスク使用量の確認
docker exec ai-micro-redis df -h /data

# dump.rdb のサイズ確認
docker exec ai-micro-redis ls -lh /data/dump.rdb
```

### 5. メモリ使用量の監視

```bash
# fork 時のメモリ使用量を考慮
# 最大メモリ使用量 = 現在のメモリ使用量 × 2

docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory | grep used_memory_human
```

### 6. バックアップのテスト

定期的にバックアップからのリストアをテスト環境で実行：

```bash
# テストスクリプト
#!/bin/bash

# 1. テスト用 Redis インスタンスを起動
docker run -d --name redis-test redis:7

# 2. バックアップをリストア
docker cp /backup/redis/dump_latest.rdb redis-test:/data/dump.rdb

# 3. Redis 再起動
docker restart redis-test

# 4. データ確認
docker exec redis-test redis-cli DBSIZE

# 5. クリーンアップ
docker rm -f redis-test
```

---

## トラブルシューティング

### BGSAVE が失敗する

**症状**: `rdb_last_bgsave_status:ok` が `err` になる

**原因と対処**:

1. **ディスク容量不足**
   ```bash
   docker exec ai-micro-redis df -h /data
   # 対処: 古いバックアップを削除
   ```

2. **メモリ不足（fork 失敗）**
   ```bash
   # /var/log/syslog または dmesg を確認
   # 対処: メモリを増やすか、maxmemory を削減
   ```

3. **権限エラー**
   ```bash
   docker exec ai-micro-redis ls -la /data
   # 対処: chown redis:redis /data
   ```

### dump.rdb が破損している

```bash
# 整合性チェック
redis-check-rdb /data/dump.rdb

# 破損している場合は古いバックアップからリストア
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [パフォーマンスチューニング](./09-performance-tuning.md)
- [高可用性戦略](./10-high-availability.md)

---

**次のステップ**: [パフォーマンスチューニング](./09-performance-tuning.md) を参照して、Redis のパフォーマンス最適化手法を確認してください。