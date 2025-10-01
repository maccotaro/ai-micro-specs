# 監視設計

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムの監視戦略、監視対象、メトリクス、およびツールについて定義します。

## 監視の目的

### 主要目標

1. **可用性の確保**: サービスが正常に稼働していることを確認
2. **パフォーマンス最適化**: ボトルネックの早期発見
3. **障害の早期検知**: 問題が深刻化する前に対応
4. **キャパシティ管理**: リソース使用状況の把握と予測

### 監視の4つの側面（Four Golden Signals）

1. **Latency（レイテンシ）**: リクエストの応答時間
2. **Traffic（トラフィック）**: システムへのリクエスト数
3. **Errors（エラー）**: エラー率
4. **Saturation（飽和度）**: リソース使用率

---

## 監視アーキテクチャ

### 推奨構成

```
┌─────────────────────────────────────────────────┐
│  Monitoring Stack                               │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐           │
│  │  Prometheus  │  │   Grafana    │           │
│  │  (Metrics)   │──│ (Visualization)          │
│  └──────────────┘  └──────────────┘           │
│         │                                       │
│  ┌──────────────┐  ┌──────────────┐           │
│  │     Loki     │  │ AlertManager │           │
│  │   (Logs)     │  │   (Alerts)   │           │
│  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
┌───────▼────────┐    ┌────────▼────────┐
│   Backend      │    │  Infrastructure │
│   Services     │    │    Services     │
│                │    │                 │
│ • Auth API     │    │ • PostgreSQL    │
│ • User API     │    │ • Redis         │
│ • Admin API    │    │ • Docker        │
└────────────────┘    └─────────────────┘
```

### 監視スタック

#### 1. Prometheus（メトリクス収集・保存）

- 時系列データベース
- Pull型メトリクス収集
- PromQL クエリ言語

#### 2. Grafana（可視化）

- ダッシュボード作成
- アラート可視化
- 複数データソース統合

#### 3. Loki（ログ集約）

- Prometheus風ログ集約
- Grafanaとの統合
- ラベルベースのログクエリ

#### 4. AlertManager（アラート管理）

- アラートルーティング
- 通知先管理（Slack, Email等）
- アラートグルーピング

---

## 監視対象とメトリクス

### 1. インフラストラクチャ監視

#### PostgreSQL

**監視項目**:

```yaml
メトリクス:
  - pg_up: データベース稼働状態
  - pg_connections_active: アクティブ接続数
  - pg_connections_max: 最大接続数
  - pg_database_size_bytes: データベースサイズ
  - pg_stat_database_tup_*: テーブル操作統計
  - pg_locks_count: ロック数
  - pg_replication_lag: レプリケーション遅延（該当時）

クエリ例:
  - Slow queries (1秒以上)
  - Long running transactions (5分以上)
  - Idle connections
  - Table bloat
```

**収集方法**:

```yaml
# docker-compose.yml に追加
services:
  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:password@postgres:5432/postgres?sslmode=disable"
    ports:
      - "9187:9187"
```

**重要メトリクスのしきい値**:

| メトリクス | 警告 | 重大 |
|-----------|------|------|
| Active connections | > 80 | > 95 |
| Database size | > 80% | > 90% |
| Slow queries/min | > 10 | > 50 |
| Replication lag | > 10s | > 30s |

#### Redis

**監視項目**:

```yaml
メトリクス:
  - redis_up: Redis稼働状態
  - redis_memory_used_bytes: メモリ使用量
  - redis_memory_max_bytes: メモリ上限
  - redis_connected_clients: 接続クライアント数
  - redis_commands_processed_total: 処理コマンド数
  - redis_keyspace_hits_total: キャッシュヒット数
  - redis_keyspace_misses_total: キャッシュミス数
  - redis_evicted_keys_total: 削除されたキー数

派生メトリクス:
  - Cache hit rate: hits / (hits + misses)
  - Memory fragmentation ratio
```

**収集方法**:

```yaml
# docker-compose.yml に追加
services:
  redis-exporter:
    image: oliver006/redis_exporter:latest
    environment:
      REDIS_ADDR: "redis:6379"
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
    ports:
      - "9121:9121"
```

**重要メトリクスのしきい値**:

| メトリクス | 警告 | 重大 |
|-----------|------|------|
| Memory usage | > 80% | > 90% |
| Connected clients | > 100 | > 200 |
| Cache hit rate | < 80% | < 60% |
| Evicted keys/min | > 10 | > 100 |

### 2. アプリケーション監視

#### FastAPI サービス（Auth, User API, Admin API）

**監視項目**:

```yaml
メトリクス:
  - http_requests_total: HTTPリクエスト総数（method, path, status_code別）
  - http_request_duration_seconds: リクエスト処理時間（histogram）
  - http_requests_in_progress: 処理中のリクエスト数
  - http_exceptions_total: 例外発生数

カスタムメトリクス:
  - auth_login_attempts_total: ログイン試行回数
  - auth_login_failures_total: ログイン失敗回数
  - jwt_tokens_issued_total: JWT発行数
  - jwt_tokens_refreshed_total: リフレッシュ数
  - jwt_verification_failures_total: JWT検証失敗数
  - profile_cache_hits_total: プロフィールキャッシュヒット
  - profile_cache_misses_total: プロフィールキャッシュミス
  - document_uploads_total: ドキュメントアップロード数
  - ocr_processing_duration_seconds: OCR処理時間
```

**実装例（Prometheusクライアント）**:

```python
# app/core/metrics.py
from prometheus_client import Counter, Histogram, Gauge
from prometheus_client import make_asgi_app

# HTTPメトリクス
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint']
)

# アプリケーションメトリクス
login_attempts = Counter('auth_login_attempts_total', 'Login attempts')
login_failures = Counter('auth_login_failures_total', 'Login failures')
jwt_issued = Counter('jwt_tokens_issued_total', 'JWT tokens issued')

# ゲージメトリクス
active_sessions = Gauge('auth_active_sessions', 'Active user sessions')

# app/main.py
from app.core.metrics import http_requests_total, http_request_duration
from prometheus_client import make_asgi_app

app = FastAPI()

# Prometheusエンドポイント
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# ミドルウェア
@app.middleware("http")
async def monitor_requests(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    http_requests_total.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()

    http_request_duration.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    return response
```

**重要メトリクスのしきい値**:

| メトリクス | 警告 | 重大 |
|-----------|------|------|
| Request duration (p95) | > 500ms | > 1s |
| Error rate | > 1% | > 5% |
| Requests in progress | > 100 | > 500 |
| Login failure rate | > 10% | > 30% |

#### Next.js フロントエンド（User, Admin）

**監視項目**:

```yaml
サーバーサイド:
  - nextjs_build_info: ビルド情報
  - nextjs_page_render_duration: ページレンダリング時間
  - nextjs_api_route_duration: APIルート処理時間

クライアントサイド（RUM - Real User Monitoring）:
  - page_load_time: ページロード時間
  - first_contentful_paint: FCP
  - largest_contentful_paint: LCP
  - cumulative_layout_shift: CLS
  - first_input_delay: FID
```

**実装方法**:

1. サーバーサイド: Prometheus client for Node.js
2. クライアントサイド: Web Vitals + カスタムビーコン送信

### 3. コンテナ監視

**監視項目**:

```yaml
メトリクス:
  - container_cpu_usage_seconds_total: CPU使用量
  - container_memory_usage_bytes: メモリ使用量
  - container_memory_max_usage_bytes: 最大メモリ使用量
  - container_network_receive_bytes_total: 受信バイト数
  - container_network_transmit_bytes_total: 送信バイト数
  - container_fs_reads_bytes_total: ディスク読み込み
  - container_fs_writes_bytes_total: ディスク書き込み
```

**収集方法（cAdvisor）**:

```yaml
# docker-compose.yml
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    ports:
      - "8080:8080"
```

---

## Prometheusセットアップ

### Prometheus設定

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # PostgreSQL
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  # Redis
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  # Auth Service
  - job_name: 'auth-service'
    static_configs:
      - targets: ['auth-service:8002']
    metrics_path: '/metrics'

  # User API
  - job_name: 'user-api'
    static_configs:
      - targets: ['user-api:8001']
    metrics_path: '/metrics'

  # Admin API
  - job_name: 'admin-api'
    static_configs:
      - targets: ['admin-api:8003']
    metrics_path: '/metrics'

  # cAdvisor
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

# Alerting
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - 'alerts/*.yml'
```

### Docker Compose統合

```yaml
# monitoring-stack/docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./alerts:/etc/prometheus/alerts
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    ports:
      - "9090:9090"
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
    ports:
      - "3000:3000"
    networks:
      - monitoring
    depends_on:
      - prometheus

  loki:
    image: grafana/loki:latest
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki
    networks:
      - monitoring

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"
    networks:
      - monitoring

volumes:
  prometheus_data:
  grafana_data:
  loki_data:

networks:
  monitoring:
    driver: bridge
```

---

## Grafana ダッシュボード

### 推奨ダッシュボード

#### 1. システム全体概要

```
┌─────────────────────────────────────────┐
│  System Overview Dashboard              │
├─────────────────────────────────────────┤
│  [Service Status] [Request Rate]        │
│  [Error Rate]     [Latency (p95)]       │
├─────────────────────────────────────────┤
│  Service Health (Up/Down indicators)    │
│  • Auth Service    ✅                   │
│  • User API        ✅                   │
│  • Admin API       ✅                   │
│  • PostgreSQL      ✅                   │
│  • Redis           ✅                   │
└─────────────────────────────────────────┘
```

**主要パネル**:

- Service availability (uptime)
- Request throughput (req/sec)
- Error rate (%)
- Response time percentiles (p50, p95, p99)

#### 2. データベースダッシュボード

```
┌─────────────────────────────────────────┐
│  PostgreSQL Dashboard                   │
├─────────────────────────────────────────┤
│  [Active Connections] [QPS]             │
│  [Database Size]      [Cache Hit Rate]  │
├─────────────────────────────────────────┤
│  Slow Queries (duration > 1s)           │
│  Top 10 queries by execution time       │
└─────────────────────────────────────────┘
```

#### 3. Redis ダッシュボード

```
┌─────────────────────────────────────────┐
│  Redis Dashboard                        │
├─────────────────────────────────────────┤
│  [Memory Usage]   [Connected Clients]   │
│  [Hit Rate]       [Commands/sec]        │
├─────────────────────────────────────────┤
│  Key Space Overview                     │
│  Eviction Rate                          │
└─────────────────────────────────────────┘
```

#### 4. アプリケーションダッシュボード

```
┌─────────────────────────────────────────┐
│  Application Performance Dashboard      │
├─────────────────────────────────────────┤
│  [Endpoint Latency] [Request Count]     │
│  [Error Rate]       [Active Requests]   │
├─────────────────────────────────────────┤
│  Top Endpoints by Traffic               │
│  Error Rate by Endpoint                 │
│  Login Success/Failure Rate             │
└─────────────────────────────────────────┘
```

### ダッシュボードのインポート

```bash
# Grafanaダッシュボードをコードとして管理（provisioning）
mkdir -p grafana/dashboards

# ダッシュボードJSONファイルを配置
# - system-overview.json
# - postgres-dashboard.json
# - redis-dashboard.json
# - application-performance.json
```

---

## ヘルスチェック

### エンドポイント実装

#### FastAPI サービス

```python
# app/routers/health.py
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from redis.asyncio import Redis

router = APIRouter()

@router.get("/health")
async def health_check(
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis)
):
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {}
    }

    # Database check
    try:
        await db.execute("SELECT 1")
        health_status["checks"]["database"] = "ok"
    except Exception as e:
        health_status["checks"]["database"] = f"error: {str(e)}"
        health_status["status"] = "unhealthy"

    # Redis check
    try:
        await redis.ping()
        health_status["checks"]["redis"] = "ok"
    except Exception as e:
        health_status["checks"]["redis"] = f"error: {str(e)}"
        health_status["status"] = "unhealthy"

    return health_status

@router.get("/ready")
async def readiness_check():
    """Kubernetes readiness probe"""
    return {"status": "ready"}

@router.get("/live")
async def liveness_check():
    """Kubernetes liveness probe"""
    return {"status": "alive"}
```

### Docker Healthcheck

```yaml
# docker-compose.yml
services:
  auth-service:
    image: auth-service:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8002/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

---

## 監視のベストプラクティス

### 1. SLI/SLO/SLA の設定

**SLI（Service Level Indicator）**: 測定可能な指標

```yaml
例:
  - Availability: uptime percentage
  - Latency: p95 response time < 500ms
  - Error rate: < 1%
```

**SLO（Service Level Objective）**: 目標値

```yaml
例:
  - 99.9% availability (月間 43.2分のダウンタイム許容)
  - 95%のリクエストが500ms以内に応答
  - エラー率 < 0.1%
```

**SLA（Service Level Agreement）**: 顧客との合意

```yaml
例:
  - 99.5% availability保証
  - 違反時の補償条件
```

### 2. アラートの原則

- **Actionable**: 対応可能なアラートのみ
- **Low False Positive**: 誤検知を最小化
- **Clear**: 何が問題か明確に
- **Prioritized**: 重要度の階層化

### 3. ダッシュボード設計

- **ターゲット別**: 運用者向け、開発者向け、経営層向け
- **階層化**: 全体 → サービス → 詳細
- **時系列**: 過去との比較が容易

### 4. データ保持期間

```yaml
短期（高解像度）: 7日間 (15秒間隔)
中期（中解像度）: 30日間 (1分間隔)
長期（低解像度）: 1年間 (5分間隔)
```

---

## 参考資料

- [04-logging.md](./04-logging.md) - ログ設計
- [05-alerting.md](./05-alerting.md) - アラート設計
- [../14-performance/05-performance-monitoring.md](../14-performance/05-performance-monitoring.md) - パフォーマンス監視
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

---

**変更履歴**:

- 2025-09-30: 初版作成