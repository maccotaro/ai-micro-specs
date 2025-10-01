# スケーラビリティ設計

## 水平スケーリング

### アプリケーションサーバー

```yaml
# Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-service-hpa
spec:
  scaleTargetRef:
    kind: Deployment
    name: auth-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### データベース

#### Read Replica

```python
# 読み取りはレプリカへ
read_db = Database("postgresql://replica-host/db")
write_db = Database("postgresql://primary-host/db")

# 読み取り
users = await read_db.fetch_all("SELECT * FROM users")

# 書き込み
await write_db.execute("INSERT INTO users ...")
```

#### Connection Pooling

```python
database = Database(
    "postgresql://...",
    min_size=10,  # 最小接続数
    max_size=20   # 最大接続数
)
```

## 垂直スケーリング

### リソース制限

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## キャッシュ戦略

### Redis Cluster

```
Redis Cluster
├─ Master 1 → Replica 1-1, 1-2
├─ Master 2 → Replica 2-1, 2-2
└─ Master 3 → Replica 3-1, 3-2
```

### キャッシュレイヤー

```
[Client]
    ↓
[CDN Cache]
    ↓
[Application Cache (Redis)]
    ↓
[Database]
```

## ロードバランシング

### Round Robin

```
Request 1 → Server 1
Request 2 → Server 2
Request 3 → Server 3
Request 4 → Server 1
```

### Least Connections

```
Request → 最も接続数の少ないサーバー
```

---

**関連**: [パフォーマンス概要](./01-performance-overview.md), [最適化ガイド](./03-optimization-guide.md)