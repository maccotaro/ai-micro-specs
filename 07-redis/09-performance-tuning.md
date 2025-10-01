# Redis パフォーマンスチューニング

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [パフォーマンスチューニングの概要](#パフォーマンスチューニングの概要)
- [メモリ管理](#メモリ管理)
- [ネットワーク最適化](#ネットワーク最適化)
- [コマンド最適化](#コマンド最適化)
- [接続プーリング](#接続プーリング)
- [監視とメトリクス](#監視とメトリクス)
- [ボトルネックの特定](#ボトルネックの特定)
- [ベンチマーク](#ベンチマーク)

---

## パフォーマンスチューニングの概要

### チューニングの目標

1. **レスポンス時間の最小化**: 99パーセンタイルで 10ms 以下
2. **スループットの最大化**: 10,000 ops/sec 以上
3. **メモリ効率の向上**: 使用メモリの最適化
4. **安定性の確保**: レイテンシスパイクの削減

### 現在の構成

**メモリ**: 512 MB
**削除ポリシー**: volatile-ttl
**永続化**: RDB（スナップショット）
**ネットワーク**: Docker ホストネットワーク

---

## メモリ管理

### maxmemory 設定

**現在の設定**: `redis.conf`

```conf
# 最大メモリ（512MB）
maxmemory 512mb

# メモリ削除ポリシー
maxmemory-policy volatile-ttl
```

### メモリ削除ポリシーの選択

| ポリシー | 説明 | 使用ケース |
|---------|------|----------|
| `volatile-ttl` | TTL が短いキーから削除 | ✅ ai-micro-service（現在） |
| `volatile-lru` | TTL 付きキーで最も使われていないものを削除 | キャッシュ主体 |
| `volatile-lfu` | TTL 付きキーで最も使用頻度が低いものを削除 | 高度なキャッシュ |
| `allkeys-lru` | すべてのキーで LRU | 純粋なキャッシュ |
| `allkeys-lfu` | すべてのキーで LFU | 純粋なキャッシュ（高度） |
| `volatile-random` | TTL 付きキーからランダム削除 | 特殊用途 |
| `allkeys-random` | すべてのキーからランダム削除 | 特殊用途 |
| `noeviction` | 削除しない（エラー返却） | データ損失が許されない場合 |

**ai-micro-service での選択理由**:
- セッション、キャッシュ、ブラックリストはすべて TTL 付き
- TTL が短いものから削除することで古いデータを優先的に削除
- メモリ不足時も最も重要度の低いデータから削除

### メモリ使用量の確認

```bash
# メモリ情報の確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory

# 主要メトリクス
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory | grep -E "used_memory_human|used_memory_peak_human|maxmemory_human"
```

**出力例**:
```
used_memory_human:156.23M
used_memory_peak_human:248.45M
maxmemory_human:512.00M
```

### メモリ使用量の最適化

#### 1. データ構造の選択

```python
# 非効率: 大きな JSON 文字列
profile_data = json.dumps({
    "user_id": "uuid",
    "first_name": "太郎",
    "last_name": "山田",
    "email": "taro@example.com",
    # ... 多数のフィールド
})
redis_client.setex(f"cache:profile:{user_id}", 300, profile_data)

# 効率的: 必要なフィールドのみ
profile_data = json.dumps({
    "user_id": user_id,
    "name": f"{first_name} {last_name}",
    "email": email
})
redis_client.setex(f"cache:profile:{user_id}", 300, profile_data)
```

#### 2. キー名の最適化

```python
# 非効率: 長いキー名
key = "application:cache:user:profile:metadata:550e8400-e29b-41d4-a716-446655440000"

# 効率的: 短いキー名
key = "cache:profile:550e8400-e29b-41d4-a716-446655440000"
```

#### 3. TTL の適切な設定

```python
# すべてのキーに TTL を設定
redis_client.setex(key, ttl, value)  # OK

# TTL なし（メモリリークの原因）
redis_client.set(key, value)  # NG
```

### メモリフラグメンテーション

```bash
# フラグメンテーション率の確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory | grep mem_fragmentation_ratio

# 出力例: mem_fragmentation_ratio:1.23
```

**フラグメンテーション率の解釈**:
- `< 1.0`: スワップ発生（危険）
- `1.0 - 1.5`: 正常範囲
- `> 1.5`: フラグメンテーションが高い

**対処法**:
```bash
# Redis 再起動（フラグメンテーション解消）
docker restart ai-micro-redis

# または Active Defragmentation（Redis 4.0+）
# redis.conf に追加
# activedefrag yes
```

---

## ネットワーク最適化

### TCP 設定

**現在の設定**: `redis.conf`

```conf
# TCP バックログ
tcp-backlog 511

# TCP キープアライブ
tcp-keepalive 300

# クライアントタイムアウト（0 = 無効）
timeout 0
```

### パイプライン化

複数のコマンドを一度に送信してネットワークラウンドトリップを削減：

```python
# 非効率: 個別のコマンド実行
for user_id in user_ids:
    profile = redis_client.get(f"cache:profile:{user_id}")

# 効率的: パイプライン
pipeline = redis_client.pipeline()
for user_id in user_ids:
    pipeline.get(f"cache:profile:{user_id}")
results = pipeline.execute()
```

**パフォーマンス向上**:
- 個別コマンド: 100 ops = 100 RTT
- パイプライン: 100 ops = 1 RTT

### バッチ操作

```python
# MGET: 複数キーの一括取得
keys = [f"cache:profile:{uid}" for uid in user_ids]
profiles = redis_client.mget(keys)

# MSET: 複数キーの一括設定
data = {
    f"cache:profile:{uid1}": json.dumps(profile1),
    f"cache:profile:{uid2}": json.dumps(profile2),
}
redis_client.mset(data)
```

---

## コマンド最適化

### 避けるべきコマンド

| コマンド | 問題 | 代替案 |
|---------|------|--------|
| `KEYS *` | すべてのキーをスキャン（O(N)） | `SCAN` を使用 |
| `FLUSHALL` | すべてのデータを削除 | TTL による自動削除 |
| `DEL` 大量のキー | ブロッキング | `UNLINK`（非同期削除） |
| `SMEMBERS` 大きな Set | すべてのメンバーを返す | `SSCAN` を使用 |

### SCAN の使用

```python
# 悪い例: KEYS コマンド（本番環境では使用禁止）
keys = redis_client.keys("session:*")  # ブロッキング！

# 良い例: SCAN コマンド
def scan_keys(pattern: str):
    """
    SCAN を使ってキーを安全に取得
    """
    cursor = 0
    keys = []

    while True:
        cursor, partial_keys = redis_client.scan(
            cursor,
            match=pattern,
            count=100
        )
        keys.extend(partial_keys)

        if cursor == 0:
            break

    return keys

# 使用例
session_keys = scan_keys("session:*")
```

### 複雑なクエリの最適化

```python
# 非効率: 複数回の GET
user_ids = ["user1", "user2", "user3"]
profiles = []
for uid in user_ids:
    profile = redis_client.get(f"cache:profile:{uid}")
    if profile:
        profiles.append(json.loads(profile))

# 効率的: MGET + フィルタリング
keys = [f"cache:profile:{uid}" for uid in user_ids]
results = redis_client.mget(keys)
profiles = [json.loads(r) for r in results if r]
```

---

## 接続プーリング

### コネクションプールの設定

```python
# app/db/redis_client.py

import redis

# コネクションプール作成
pool = redis.ConnectionPool(
    host='host.docker.internal',
    port=6379,
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True,
    max_connections=20,        # 最大接続数
    socket_connect_timeout=5,  # 接続タイムアウト
    socket_timeout=5,          # コマンドタイムアウト
    socket_keepalive=True,     # TCP キープアライブ
    socket_keepalive_options={
        socket.TCP_KEEPIDLE: 1,
        socket.TCP_KEEPINTVL: 1,
        socket.TCP_KEEPCNT: 5
    }
)

# プールから Redis クライアント作成
redis_client = redis.Redis(connection_pool=pool)
```

### プールサイズの最適化

**計算式**:
```
max_connections = (CPU コア数) × 2 + ディスク数
```

**例**:
- 4コアCPU、1ディスク → 10接続
- 8コアCPU、2ディスク → 18接続

**ai-micro-service での設定**:
```python
max_connections=20  # 適度な設定
```

### 接続数の監視

```bash
# 現在の接続数
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} CLIENT LIST | wc -l

# 接続情報の詳細
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO clients
```

---

## 監視とメトリクス

### 主要メトリクス

#### 1. メモリメトリクス

```bash
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory
```

**重要な指標**:
- `used_memory`: 使用メモリ
- `used_memory_peak`: ピークメモリ使用量
- `mem_fragmentation_ratio`: フラグメンテーション率
- `evicted_keys`: 削除されたキー数

#### 2. パフォーマンスメトリクス

```bash
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO stats
```

**重要な指標**:
- `total_commands_processed`: 処理されたコマンド数
- `instantaneous_ops_per_sec`: 現在の ops/sec
- `rejected_connections`: 拒否された接続数
- `keyspace_hits`: キャッシュヒット数
- `keyspace_misses`: キャッシュミス数

#### 3. キャッシュヒット率

```bash
# キャッシュヒット率の計算
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO stats | grep -E "keyspace_hits|keyspace_misses"
```

**計算**:
```
hit_rate = hits / (hits + misses) × 100
```

**目標**:
- ✅ 80%以上: 良好
- ⚠️ 60-80%: 改善の余地
- ❌ 60%以下: キャッシュ戦略の見直しが必要

### リアルタイム監視

```bash
# リアルタイムコマンド監視
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} MONITOR

# レイテンシ監視
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --latency

# レイテンシヒストリー
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --latency-history
```

### スロークエリログ

```bash
# スローログ設定の確認
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} CONFIG GET slowlog-*

# スローログの取得（最新10件）
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} SLOWLOG GET 10

# スローログのリセット
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} SLOWLOG RESET
```

**スローログの設定** (`redis.conf`):
```conf
# 10ms 以上のコマンドをログ
slowlog-log-slower-than 10000

# 最大128件保持
slowlog-max-len 128
```

---

## ボトルネックの特定

### 1. CPU ボトルネック

**症状**:
- ops/sec が低い
- レイテンシが高い

**確認**:
```bash
# CPU 使用率
docker stats ai-micro-redis
```

**対処**:
- 重いコマンドの最適化（KEYS → SCAN）
- データ構造の見直し
- シャーディング（将来的に）

### 2. メモリボトルネック

**症状**:
- `used_memory` が `maxmemory` に近い
- `evicted_keys` が増加

**確認**:
```bash
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO memory | grep -E "used_memory|maxmemory|evicted_keys"
```

**対処**:
- `maxmemory` を増やす
- TTL を短くする
- 不要なキーを削除

### 3. ネットワークボトルネック

**症状**:
- レイテンシが高い
- スループットが低い

**確認**:
```bash
# ネットワーク統計
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO stats | grep total_net
```

**対処**:
- パイプライン化
- バッチ操作
- データ圧縮

### 4. ディスク I/O ボトルネック

**症状**:
- BGSAVE 時にレイテンシスパイク
- RDB 保存に時間がかかる

**確認**:
```bash
# RDB 保存時間
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} INFO persistence | grep rdb_last_bgsave_time_sec
```

**対処**:
- SSD を使用
- `save` 設定を緩和
- AOF を無効化（または `appendfsync everysec`）

---

## ベンチマーク

### redis-benchmark の使用

```bash
# 基本ベンチマーク
docker exec ai-micro-redis redis-benchmark -a ${REDIS_PASSWORD} -q

# 特定のコマンドをベンチマーク
docker exec ai-micro-redis redis-benchmark -a ${REDIS_PASSWORD} -t set,get -n 100000 -q

# パイプラインベンチマーク
docker exec ai-micro-redis redis-benchmark -a ${REDIS_PASSWORD} -t set,get -n 100000 -P 16 -q

# 結果例
SET: 98765.43 requests per second
GET: 101234.57 requests per second
```

### カスタムベンチマーク

```python
# app/tests/benchmark_redis.py

import time
import redis
import json

def benchmark_cache_operations(iterations: int = 10000):
    """
    キャッシュ操作のベンチマーク
    """

    # SET 操作
    start = time.time()
    for i in range(iterations):
        profile_data = json.dumps({
            "user_id": f"user-{i}",
            "name": f"User {i}",
            "email": f"user{i}@example.com"
        })
        redis_client.setex(f"cache:profile:user-{i}", 300, profile_data)
    set_duration = time.time() - start

    # GET 操作
    start = time.time()
    for i in range(iterations):
        redis_client.get(f"cache:profile:user-{i}")
    get_duration = time.time() - start

    # 結果
    print(f"SET: {iterations/set_duration:.2f} ops/sec")
    print(f"GET: {iterations/get_duration:.2f} ops/sec")

    # クリーンアップ
    pipeline = redis_client.pipeline()
    for i in range(iterations):
        pipeline.delete(f"cache:profile:user-{i}")
    pipeline.execute()

# 実行
benchmark_cache_operations()
```

### パフォーマンス目標

| 操作 | 目標 | 現在値（推定） |
|-----|------|-------------|
| SET | 50,000 ops/sec | ✅ 達成可能 |
| GET | 100,000 ops/sec | ✅ 達成可能 |
| レイテンシ（p99） | < 10ms | ✅ 達成可能 |
| メモリ使用量 | < 400MB | ✅ 現在156MB |
| キャッシュヒット率 | > 80% | ⚠️ 要測定 |

---

## チューニングチェックリスト

### 設定レベル

- ✅ `maxmemory` を適切に設定（512MB）
- ✅ `maxmemory-policy` を選択（volatile-ttl）
- ✅ TTL をすべてのキーに設定
- ✅ RDB スナップショット設定
- ✅ `tcp-backlog` 設定（511）

### アプリケーションレベル

- ✅ コネクションプーリング使用
- ✅ パイプライン化（複数コマンド）
- ✅ バッチ操作（MGET/MSET）
- ✅ SCAN 使用（KEYS 禁止）
- ✅ エラーハンドリング実装

### 監視レベル

- ⚠️ メモリ使用量の監視
- ⚠️ キャッシュヒット率の測定
- ⚠️ スローログの確認
- ⚠️ レイテンシの監視
- ⚠️ 定期的なベンチマーク

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [キャッシュ戦略](./06-cache-strategy.md)
- [永続化設定](./08-persistence.md)
- [高可用性戦略](./10-high-availability.md)

---

**次のステップ**: [高可用性戦略](./10-high-availability.md) を参照して、Redis の耐障害性と可用性向上の方法を確認してください。