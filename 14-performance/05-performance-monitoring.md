# パフォーマンス監視

## メトリクス収集

### Prometheus メトリクス

```python
from prometheus_client import Counter, Histogram

# リクエスト数
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

# レスポンス時間
request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

@router.get("/users")
async def get_users():
    with request_duration.labels(method='GET', endpoint='/users').time():
        users = await user_service.get_all()
        http_requests_total.labels(method='GET', endpoint='/users', status='200').inc()
        return users
```

### アプリケーションログ

```python
logger.info(
    "API request completed",
    extra={
        "path": "/users",
        "method": "GET",
        "duration_ms": 123,
        "status_code": 200
    }
)
```

## ダッシュボード

### Grafana パネル

1. **Response Time (p50, p95, p99)**
2. **Request Rate (req/sec)**
3. **Error Rate (%)**
4. **CPU/Memory Usage**

### アラート設定

```yaml
# High Response Time
- alert: HighResponseTime
  expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
  for: 5m
  annotations:
    summary: "High response time detected"

# High Error Rate
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01
  for: 5m
  annotations:
    summary: "High error rate detected"
```

## パフォーマンステスト

### Lighthouse (フロントエンド)

```bash
npx lighthouse http://localhost:3002 --view
```

### Python プロファイリング

```python
import cProfile

def profile_function():
    profiler = cProfile.Profile()
    profiler.enable()

    # 測定したい処理
    result = expensive_operation()

    profiler.disable()
    profiler.print_stats()
```

---

**関連**: [パフォーマンス概要](./01-performance-overview.md), [負荷テスト](./02-load-testing.md)