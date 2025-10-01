# Redis 高可用性戦略

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [高可用性の概要](#高可用性の概要)
- [現在の構成と制限](#現在の構成と制限)
- [レプリケーション](#レプリケーション)
- [Redis Sentinel](#redis-sentinel)
- [Redis Cluster](#redis-cluster)
- [障害シナリオと対応](#障害シナリオと対応)
- [将来のアーキテクチャ](#将来のアーキテクチャ)
- [移行計画](#移行計画)

---

## 高可用性の概要

### 高可用性の重要性

Redis は ai-micro-service システムにおいて以下の重要な役割を担っています：

1. **セッション管理**: ユーザーのログイン状態
2. **トークンブラックリスト**: セキュリティの要
3. **プロファイルキャッシュ**: パフォーマンスの鍵
4. **レート制限**: システム保護

Redis がダウンすると、これらの機能がすべて影響を受けます。

### 可用性の目標

| レベル | 稼働率 | 年間ダウンタイム | 用途 |
|-------|-------|---------------|------|
| 99% | Two nines | 3.65日 | 開発環境 |
| 99.9% | Three nines | 8.76時間 | ✅ 現在の目標（ステージング） |
| 99.99% | Four nines | 52.56分 | 本番環境（将来） |
| 99.999% | Five nines | 5.26分 | ミッションクリティカル（将来） |

---

## 現在の構成と制限

### 現在のアーキテクチャ

```
┌─────────────────────────┐
│  ai-micro-redis         │
│  (Single Instance)      │
│                         │
│  - Port: 6379          │
│  - Container: Redis 7  │
│  - Persistence: RDB    │
│  - No Replication      │
└─────────────────────────┘
         ↑
         │
    ┌────┴────┐
    │ Services│
    └─────────┘
```

### 制限事項

1. **単一障害点（SPOF）**
   - Redis コンテナがダウンすると全サービスが影響を受ける
   - 再起動時にセッションが失われる

2. **スケーラビリティの制限**
   - 読み取り負荷を分散できない
   - メモリ容量が単一ノードに制限される

3. **障害復旧時間（RTO）**
   - 手動での再起動が必要
   - データ復旧に時間がかかる可能性

### 緩和策（現在実施中）

1. **エラーハンドリング**
   - Redis 障害時にデータベースにフォールバック
   - セッション検証のスキップ（緊急時）

2. **自動再起動**
   ```yaml
   # docker-compose.yml
   restart: unless-stopped
   ```

3. **定期的なバックアップ**
   - RDB スナップショット（15分ごと）
   - 日次バックアップ

---

## レプリケーション

### レプリケーションの仕組み

Redis レプリケーションは、マスター-スレーブ構成でデータを複製します。

```
┌─────────────────┐
│  Master         │
│  (Read/Write)   │
└────────┬────────┘
         │ replication
    ┌────┴────┬────────┐
    │         │        │
┌───▼───┐ ┌──▼───┐ ┌──▼───┐
│Replica│ │Replica│ │Replica│
│(Read) │ │(Read) │ │(Read) │
└───────┘ └──────┘ └──────┘
```

### メリット

1. **読み取りスケーリング**: レプリカで読み取り負荷を分散
2. **データの冗長性**: マスター障害時にレプリカからデータ復旧
3. **ゼロダウンタイム**: レプリカを昇格させて継続稼働

### 設定例

#### Master 設定

```yaml
# docker-compose.yml (Master)
version: '3.9'
services:
  redis-master:
    image: redis:7
    container_name: redis-master
    command: redis-server /usr/local/etc/redis/redis.conf --requirepass ${REDIS_PASSWORD}
    ports:
      - "6379:6379"
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
      - redis_master_data:/data
    networks:
      - redis-network

volumes:
  redis_master_data:

networks:
  redis-network:
```

#### Replica 設定

```yaml
# docker-compose.yml (Replica)
version: '3.9'
services:
  redis-replica-1:
    image: redis:7
    container_name: redis-replica-1
    command: >
      redis-server
      --replicaof redis-master 6379
      --masterauth ${REDIS_PASSWORD}
      --requirepass ${REDIS_PASSWORD}
    ports:
      - "6380:6379"
    volumes:
      - redis_replica_1_data:/data
    networks:
      - redis-network
    depends_on:
      - redis-master

  redis-replica-2:
    image: redis:7
    container_name: redis-replica-2
    command: >
      redis-server
      --replicaof redis-master 6379
      --masterauth ${REDIS_PASSWORD}
      --requirepass ${REDIS_PASSWORD}
    ports:
      - "6381:6379"
    volumes:
      - redis_replica_2_data:/data
    networks:
      - redis-network
    depends_on:
      - redis-master

volumes:
  redis_replica_1_data:
  redis_replica_2_data:

networks:
  redis-network:
    external: true
```

### レプリケーションの確認

```bash
# Master の情報確認
docker exec redis-master redis-cli -a ${REDIS_PASSWORD} INFO replication

# Replica の情報確認
docker exec redis-replica-1 redis-cli -a ${REDIS_PASSWORD} INFO replication
```

**出力例（Master）**:
```
# Replication
role:master
connected_slaves:2
slave0:ip=172.18.0.3,port=6379,state=online,offset=1234,lag=0
slave1:ip=172.18.0.4,port=6379,state=online,offset=1234,lag=0
```

### 読み取り専用レプリカの使用

```python
# app/db/redis_client.py

import redis

class RedisClient:
    def __init__(self):
        # Master（書き込み用）
        self.master = redis.Redis(
            host='redis-master',
            port=6379,
            password=os.getenv('REDIS_PASSWORD'),
            decode_responses=True
        )

        # Replica（読み取り用）
        self.replica = redis.Redis(
            host='redis-replica-1',
            port=6379,
            password=os.getenv('REDIS_PASSWORD'),
            decode_responses=True
        )

    def set(self, key, value, ttl=None):
        """Master に書き込み"""
        if ttl:
            return self.master.setex(key, ttl, value)
        return self.master.set(key, value)

    def get(self, key):
        """Replica から読み取り"""
        try:
            return self.replica.get(key)
        except redis.ConnectionError:
            # Replica 障害時は Master から読み取り
            return self.master.get(key)
```

---

## Redis Sentinel

### Sentinel の役割

Redis Sentinel は、自動フェイルオーバーを提供する高可用性ソリューションです。

**主な機能**:
1. **監視**: Master と Replica の健全性監視
2. **通知**: 障害時にアラート送信
3. **自動フェイルオーバー**: Master 障害時に Replica を昇格
4. **設定提供**: クライアントに現在の Master 情報を提供

### アーキテクチャ

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│Sentinel 1│     │Sentinel 2│     │Sentinel 3│
└────┬─────┘     └────┬─────┘     └────┬─────┘
     │                │                │
     └────────────────┼────────────────┘
                      │ monitoring
         ┌────────────┴────────────┐
         │                         │
    ┌────▼─────┐            ┌─────▼────┐
    │  Master  │replication │ Replica  │
    │(R/W)     │◄───────────┤(Read)    │
    └──────────┘            └──────────┘
```

### Sentinel 設定例

#### Sentinel 設定ファイル

```conf
# sentinel.conf
port 26379

# Master 監視設定
sentinel monitor mymaster redis-master 6379 2
sentinel auth-pass mymaster ${REDIS_PASSWORD}

# ダウン判定タイムアウト（30秒）
sentinel down-after-milliseconds mymaster 30000

# フェイルオーバータイムアウト（3分）
sentinel failover-timeout mymaster 180000

# 同時にレプリケーション可能な Replica 数
sentinel parallel-syncs mymaster 1
```

#### Docker Compose 設定

```yaml
# docker-compose.yml (Sentinel)
version: '3.9'
services:
  sentinel-1:
    image: redis:7
    container_name: redis-sentinel-1
    command: redis-sentinel /usr/local/etc/redis/sentinel.conf
    ports:
      - "26379:26379"
    volumes:
      - ./sentinel.conf:/usr/local/etc/redis/sentinel.conf
    networks:
      - redis-network

  sentinel-2:
    image: redis:7
    container_name: redis-sentinel-2
    command: redis-sentinel /usr/local/etc/redis/sentinel.conf
    ports:
      - "26380:26379"
    volumes:
      - ./sentinel.conf:/usr/local/etc/redis/sentinel.conf
    networks:
      - redis-network

  sentinel-3:
    image: redis:7
    container_name: redis-sentinel-3
    command: redis-sentinel /usr/local/etc/redis/sentinel.conf
    ports:
      - "26381:26379"
    volumes:
      - ./sentinel.conf:/usr/local/etc/redis/sentinel.conf
    networks:
      - redis-network

networks:
  redis-network:
    external: true
```

### クライアントでの Sentinel 使用

```python
# app/db/redis_client.py

from redis.sentinel import Sentinel

class RedisClient:
    def __init__(self):
        # Sentinel 接続設定
        sentinel = Sentinel(
            [
                ('sentinel-1', 26379),
                ('sentinel-2', 26379),
                ('sentinel-3', 26379)
            ],
            socket_timeout=5,
            password=os.getenv('REDIS_PASSWORD')
        )

        # Master 取得（書き込み用）
        self.master = sentinel.master_for(
            'mymaster',
            socket_timeout=5,
            password=os.getenv('REDIS_PASSWORD'),
            decode_responses=True
        )

        # Replica 取得（読み取り用）
        self.replica = sentinel.slave_for(
            'mymaster',
            socket_timeout=5,
            password=os.getenv('REDIS_PASSWORD'),
            decode_responses=True
        )
```

### フェイルオーバーのテスト

```bash
# Master を停止
docker stop redis-master

# Sentinel ログを確認（自動フェイルオーバー）
docker logs redis-sentinel-1

# 新しい Master を確認
docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
```

---

## Redis Cluster

### Cluster の概要

Redis Cluster は、データを複数のノードに分散する水平スケーリングソリューションです。

**特徴**:
- **シャーディング**: データを 16384 個のハッシュスロットに分割
- **自動フェイルオーバー**: ノード障害時に自動で Replica を昇格
- **スケーラビリティ**: ノード追加でメモリとスループットを拡張

### アーキテクチャ

```
┌──────────────────────────────────────┐
│         Redis Cluster                │
│                                      │
│  ┌─────────┐  ┌─────────┐  ┌───────┐│
│  │Master 1 │  │Master 2 │  │Master3││
│  │Slots    │  │Slots    │  │Slots  ││
│  │0-5460   │  │5461-    │  │10923- ││
│  │         │  │10922    │  │16383  ││
│  └────┬────┘  └────┬────┘  └───┬───┘│
│       │            │            │    │
│  ┌────▼────┐  ┌───▼─────┐  ┌──▼────┐│
│  │Replica1 │  │Replica2 │  │Replica││
│  │         │  │         │  │3      ││
│  └─────────┘  └─────────┘  └───────┘│
└──────────────────────────────────────┘
```

### Cluster 設定例

```yaml
# docker-compose.yml (Cluster)
version: '3.9'
services:
  redis-1:
    image: redis:7
    container_name: redis-cluster-1
    command: >
      redis-server
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    ports:
      - "7000:6379"
      - "17000:16379"
    volumes:
      - redis_cluster_1_data:/data
    networks:
      - redis-network

  # redis-2 ~ redis-6 も同様に定義

volumes:
  redis_cluster_1_data:
  # ...

networks:
  redis-network:
```

### Cluster の作成

```bash
# Cluster 作成
docker exec redis-cluster-1 redis-cli -a ${REDIS_PASSWORD} --cluster create \
  redis-1:6379 \
  redis-2:6379 \
  redis-3:6379 \
  redis-4:6379 \
  redis-5:6379 \
  redis-6:6379 \
  --cluster-replicas 1
```

### 注意事項

1. **複雑性**: 設定と運用が複雑
2. **クライアント対応**: Cluster 対応クライアントが必要
3. **マルチキー操作**: 同一スロットのキーのみサポート
4. **メモリオーバーヘッド**: クラスタメタデータが必要

---

## 障害シナリオと対応

### シナリオ 1: Redis コンテナのクラッシュ

**現在の構成**:
1. Docker の `restart: unless-stopped` が自動再起動
2. 最大15分分のセッションデータが失われる
3. ユーザーは再ログインが必要

**Sentinel 構成（将来）**:
1. Replica が自動的に Master に昇格
2. 数秒のダウンタイムのみ
3. セッションデータは保持される

### シナリオ 2: ホストマシンの障害

**現在の構成**:
1. すべてのサービスがダウン
2. 手動でのリストアが必要

**クラウド構成（将来）**:
1. 別のホストで自動起動
2. ロードバランサーが自動的に切り替え

### シナリオ 3: ネットワーク分断

**Sentinel 構成**:
1. Sentinel がクォーラムで判断
2. 誤ったフェイルオーバーを防止
3. スプリットブレインの回避

---

## 将来のアーキテクチャ

### フェーズ 1: レプリケーション導入

**目標**: 読み取りスケーリングとデータ冗長性

```
Master (R/W) → Replica 1 (R) → Replica 2 (R)
```

**実装時期**: 本番環境リリース前

### フェーズ 2: Sentinel 導入

**目標**: 自動フェイルオーバー

```
Sentinel × 3
    ↓ monitoring
Master + Replica × 2
```

**実装時期**: 本番環境での高可用性が必要になった時点

### フェーズ 3: Cluster 検討

**目標**: 水平スケーリング

**検討条件**:
- メモリ使用量が 4GB を超える
- トラフィックが 100,000 ops/sec を超える

---

## 移行計画

### レプリケーション導入の手順

#### ステップ 1: Replica の追加

```bash
# 1. Replica コンテナを起動
docker compose -f docker-compose-replica.yml up -d

# 2. レプリケーション状態の確認
docker exec redis-master redis-cli -a ${REDIS_PASSWORD} INFO replication

# 3. 同期完了を確認
docker exec redis-replica-1 redis-cli -a ${REDIS_PASSWORD} INFO replication
```

#### ステップ 2: アプリケーションの更新

```python
# 読み取りを Replica に分散
redis_client.get()  # Replica から読み取り
redis_client.set()  # Master に書き込み
```

#### ステップ 3: 動作確認

```bash
# 負荷テスト
redis-benchmark -h redis-replica-1 -a ${REDIS_PASSWORD} -t get -n 100000

# フェイルオーバーテスト
docker stop redis-master
# 手動で Replica を昇格
docker exec redis-replica-1 redis-cli -a ${REDIS_PASSWORD} REPLICAOF NO ONE
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [永続化設定](./08-persistence.md)
- [パフォーマンスチューニング](./09-performance-tuning.md)

---

**まとめ**: 現在は単一ノード構成ですが、将来的にはレプリケーションと Sentinel を導入することで、高可用性を実現する計画です。本番環境では、これらの高可用性機能の導入を強く推奨します。