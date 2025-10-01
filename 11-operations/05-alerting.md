# アラート設計

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムにおけるアラート戦略、アラートルール、通知設定について定義します。

## アラート設計の原則

### 基本方針

1. **Actionable（対応可能）**: アラートに対して明確なアクションが存在する
2. **Meaningful（意味がある）**: ビジネスへの影響がある
3. **Low False Positive（誤検知が少ない）**: 信頼性が高い
4. **Prioritized（優先順位付け）**: 重要度に応じた階層化
5. **Well-Documented（文書化）**: 対応手順が明確

### アラート疲れ（Alert Fatigue）の防止

```
❌ 避けるべきアラート:
  - 対応不要なアラート
  - 頻繁すぎるアラート
  - 不明瞭なアラート

✅ 良いアラート:
  - ユーザー影響があるもの
  - 緊急対応が必要なもの
  - 明確な対応手順があるもの
```

---

## アラートレベル

### レベル定義

| レベル | 深刻度 | 対応時間 | 通知方法 | 例 |
|--------|--------|----------|----------|-----|
| **CRITICAL** | 致命的 | 即座（5分以内） | PagerDuty + Slack + SMS | サービス全停止 |
| **ERROR** | エラー | 緊急（30分以内） | Slack + Email | エラー率 > 5% |
| **WARNING** | 警告 | 通常（4時間以内） | Slack | メモリ使用率 > 80% |
| **INFO** | 情報 | 通知のみ | Slack | デプロイ完了 |

### エスカレーション

```
CRITICAL アラート:
  1. 即座に一次対応チームに通知
  2. 15分応答なし → 二次対応チームに通知
  3. 30分未解決 → マネージャーに通知

ERROR アラート:
  1. 一次対応チームに通知
  2. 1時間未解決 → エスカレーション

WARNING アラート:
  1. Slack通知のみ
  2. 24時間継続 → チケット作成
```

---

## AlertManager 設定

### 基本設定

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: '${SLACK_WEBHOOK_URL}'

# ルートルート（デフォルト）
route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'service', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

  # サブルート（重要度別）
  routes:
    # CRITICAL: PagerDuty + Slack
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      group_wait: 0s
      repeat_interval: 5m

    # ERROR: Slack + Email
    - match:
        severity: error
      receiver: 'slack-email-notifications'
      repeat_interval: 1h

    # WARNING: Slack のみ
    - match:
        severity: warning
      receiver: 'slack-notifications'
      repeat_interval: 4h

# Receivers（通知先）
receivers:
  # Slack通知
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: |
          *Severity*: {{ .GroupLabels.severity }}
          *Service*: {{ .GroupLabels.service }}
          *Summary*: {{ .CommonAnnotations.summary }}
          *Description*: {{ .CommonAnnotations.description }}

  # Slack + Email
  - name: 'slack-email-notifications'
    slack_configs:
      - channel: '#alerts-critical'
        title: '🚨 {{ .GroupLabels.alertname }}'
        text: |
          *Severity*: ERROR
          *Service*: {{ .GroupLabels.service }}
          *Summary*: {{ .CommonAnnotations.summary }}
          *Runbook*: {{ .CommonAnnotations.runbook_url }}
    email_configs:
      - to: 'oncall@example.com'
        from: 'alertmanager@example.com'
        subject: 'ALERT: {{ .GroupLabels.alertname }}'

  # PagerDuty（CRITICAL）
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
        description: '{{ .CommonAnnotations.summary }}'
    slack_configs:
      - channel: '#incidents'
        title: '🔴 CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          *Service*: {{ .GroupLabels.service }}
          *Summary*: {{ .CommonAnnotations.summary }}
          *PagerDuty*: Incident created

# Inhibition rules（抑制ルール）
inhibit_rules:
  # CRITICALアラートが発火中はWARNINGを抑制
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['service']

  # サービスダウン中は他のアラートを抑制
  - source_match:
      alertname: 'ServiceDown'
    target_match_re:
      alertname: '.*'
    equal: ['service']
```

---

## アラートルール

### インフラストラクチャアラート

#### PostgreSQL

```yaml
# alerts/postgres.yml
groups:
  - name: postgres
    interval: 30s
    rules:
      # PostgreSQL ダウン
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
          service: postgresql
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL instance {{ $labels.instance }} is down for more than 1 minute."
          runbook_url: "https://docs.example.com/runbooks/postgres-down"

      # 接続数が上限に近い
      - alert: PostgreSQLTooManyConnections
        expr: |
          (pg_stat_database_numbackends / pg_settings_max_connections * 100) > 80
        for: 5m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "PostgreSQL connection limit approaching"
          description: "PostgreSQL instance {{ $labels.instance }} is using {{ $value }}% of max connections."
          runbook_url: "https://docs.example.com/runbooks/postgres-connections"

      # スロークエリが多い
      - alert: PostgreSQLSlowQueries
        expr: |
          rate(pg_stat_statements_mean_exec_time_seconds{query!~".*pg_stat.*"}[5m]) > 1
        for: 10m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "High number of slow queries detected"
          description: "Database {{ $labels.datname }} has queries with average execution time > 1s."

      # データベースサイズが大きい
      - alert: PostgreSQLDatabaseSizeLarge
        expr: |
          (pg_database_size_bytes / 1024 / 1024 / 1024) > 50
        for: 1h
        labels:
          severity: info
          service: postgresql
        annotations:
          summary: "Database size is large"
          description: "Database {{ $labels.datname }} size is {{ $value }}GB."

      # レプリケーション遅延（該当時）
      - alert: PostgreSQLReplicationLag
        expr: |
          pg_replication_lag > 30
        for: 5m
        labels:
          severity: error
          service: postgresql
        annotations:
          summary: "PostgreSQL replication lag detected"
          description: "Replication lag is {{ $value }} seconds on {{ $labels.instance }}."
```

#### Redis

```yaml
# alerts/redis.yml
groups:
  - name: redis
    interval: 30s
    rules:
      # Redis ダウン
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
          service: redis
        annotations:
          summary: "Redis is down"
          description: "Redis instance {{ $labels.instance }} is down."
          runbook_url: "https://docs.example.com/runbooks/redis-down"

      # メモリ使用率が高い
      - alert: RedisMemoryHigh
        expr: |
          (redis_memory_used_bytes / redis_memory_max_bytes * 100) > 80
        for: 5m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis memory usage is high"
          description: "Redis instance {{ $labels.instance }} is using {{ $value }}% of max memory."

      # キャッシュヒット率が低い
      - alert: RedisCacheHitRateLow
        expr: |
          (rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100) < 60
        for: 15m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis cache hit rate is low"
          description: "Redis cache hit rate is {{ $value }}% on {{ $labels.instance }}."

      # 接続数が多い
      - alert: RedisTooManyConnections
        expr: redis_connected_clients > 100
        for: 5m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Too many Redis connections"
          description: "Redis has {{ $value }} connected clients on {{ $labels.instance }}."

      # キー削除が頻繁
      - alert: RedisHighEvictionRate
        expr: rate(redis_evicted_keys_total[5m]) > 10
        for: 10m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "High Redis key eviction rate"
          description: "Redis is evicting {{ $value }} keys/sec on {{ $labels.instance }}."
```

### アプリケーションアラート

#### Auth Service

```yaml
# alerts/auth-service.yml
groups:
  - name: auth-service
    interval: 30s
    rules:
      # サービスダウン
      - alert: AuthServiceDown
        expr: up{job="auth-service"} == 0
        for: 2m
        labels:
          severity: critical
          service: auth-service
        annotations:
          summary: "Auth Service is down"
          description: "Auth Service has been down for more than 2 minutes."
          runbook_url: "https://docs.example.com/runbooks/auth-service-down"

      # エラー率が高い
      - alert: AuthServiceHighErrorRate
        expr: |
          (sum(rate(http_requests_total{service="auth-service",status=~"5.."}[5m])) /
          sum(rate(http_requests_total{service="auth-service"}[5m])) * 100) > 5
        for: 5m
        labels:
          severity: error
          service: auth-service
        annotations:
          summary: "High error rate in Auth Service"
          description: "Auth Service error rate is {{ $value }}%."

      # レスポンスタイムが遅い
      - alert: AuthServiceHighLatency
        expr: |
          histogram_quantile(0.95,
            rate(http_request_duration_seconds_bucket{service="auth-service"}[5m])
          ) > 1
        for: 10m
        labels:
          severity: warning
          service: auth-service
        annotations:
          summary: "High latency in Auth Service"
          description: "Auth Service p95 latency is {{ $value }}s."

      # ログイン失敗率が高い
      - alert: AuthServiceHighLoginFailureRate
        expr: |
          (rate(auth_login_failures_total[5m]) /
          rate(auth_login_attempts_total[5m]) * 100) > 30
        for: 5m
        labels:
          severity: warning
          service: auth-service
        annotations:
          summary: "High login failure rate"
          description: "Login failure rate is {{ $value }}%."

      # JWT検証失敗が多い
      - alert: AuthServiceJWTVerificationFailures
        expr: rate(jwt_verification_failures_total[5m]) > 10
        for: 5m
        labels:
          severity: error
          service: auth-service
        annotations:
          summary: "High JWT verification failure rate"
          description: "JWT verification failures: {{ $value }} per second."
```

#### User API & Admin API

```yaml
# alerts/api-services.yml
groups:
  - name: api-services
    interval: 30s
    rules:
      # サービスダウン
      - alert: APIServiceDown
        expr: up{job=~"user-api|admin-api"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} is down"
          description: "{{ $labels.job }} has been down for more than 2 minutes."

      # エラー率が高い
      - alert: APIServiceHighErrorRate
        expr: |
          (sum(rate(http_requests_total{job=~"user-api|admin-api",status=~"5.."}[5m])) by (job) /
          sum(rate(http_requests_total{job=~"user-api|admin-api"}[5m])) by (job) * 100) > 5
        for: 5m
        labels:
          severity: error
        annotations:
          summary: "High error rate in {{ $labels.job }}"
          description: "{{ $labels.job }} error rate is {{ $value }}%."

      # リクエスト処理中が多い
      - alert: APIServiceHighConcurrency
        expr: http_requests_in_progress{job=~"user-api|admin-api"} > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High concurrent requests in {{ $labels.job }}"
          description: "{{ $labels.job }} has {{ $value }} requests in progress."

      # OCR処理時間が長い（Admin API）
      - alert: AdminAPISlowOCRProcessing
        expr: |
          histogram_quantile(0.95,
            rate(ocr_processing_duration_seconds_bucket{job="admin-api"}[5m])
          ) > 30
        for: 10m
        labels:
          severity: warning
          service: admin-api
        annotations:
          summary: "Slow OCR processing"
          description: "OCR p95 processing time is {{ $value }}s."
```

### コンテナアラート

```yaml
# alerts/containers.yml
groups:
  - name: containers
    interval: 30s
    rules:
      # CPU使用率が高い
      - alert: ContainerHighCPU
        expr: |
          (rate(container_cpu_usage_seconds_total{name=~".+"}[5m]) * 100) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage in {{ $labels.name }}"
          description: "Container {{ $labels.name }} CPU usage is {{ $value }}%."

      # メモリ使用率が高い
      - alert: ContainerHighMemory
        expr: |
          (container_memory_usage_bytes{name=~".+"} /
          container_spec_memory_limit_bytes{name=~".+"} * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage in {{ $labels.name }}"
          description: "Container {{ $labels.name }} memory usage is {{ $value }}%."

      # コンテナ再起動が頻繁
      - alert: ContainerFrequentRestarts
        expr: |
          rate(container_last_seen{name=~".+"}[10m]) > 0.1
        for: 5m
        labels:
          severity: error
        annotations:
          summary: "Frequent container restarts"
          description: "Container {{ $labels.name }} is restarting frequently."
```

---

## 通知設定

### Slack 通知

#### Webhook設定

```bash
# Slack Incoming Webhook URLを取得
# 1. Slack Workspace で Incoming Webhooks アプリを追加
# 2. Webhook URLをコピー
# 3. AlertManager設定に追加

export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

#### チャンネル設計

```
#alerts: 通常のアラート（WARNING, INFO）
#alerts-critical: ERROR, CRITICAL アラート
#incidents: CRITICAL インシデント専用
#deployments: デプロイ通知
```

#### カスタムSlack通知

```python
# app/core/notifications.py
import httpx

SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

async def send_slack_alert(message: str, severity: str = "info"):
    emoji_map = {
        "critical": "🔴",
        "error": "🟠",
        "warning": "🟡",
        "info": "🔵"
    }

    payload = {
        "text": f"{emoji_map.get(severity, '🔵')} {message}",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*{severity.upper()}*: {message}"
                }
            }
        ]
    }

    async with httpx.AsyncClient() as client:
        await client.post(SLACK_WEBHOOK_URL, json=payload)

# 使用例
await send_slack_alert("Database connection failed", severity="error")
```

### Email 通知

```yaml
# alertmanager.yml
receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'team@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alertmanager@example.com'
        auth_password: '${SMTP_PASSWORD}'
        headers:
          Subject: '[ALERT] {{ .GroupLabels.alertname }}'
```

### PagerDuty 統合

```yaml
# alertmanager.yml
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
        url: 'https://events.pagerduty.com/v2/enqueue'
        description: '{{ .CommonAnnotations.summary }}'
        severity: '{{ .CommonLabels.severity }}'
        details:
          service: '{{ .CommonLabels.service }}'
          alert: '{{ .GroupLabels.alertname }}'
```

---

## アラート対応 Runbook

### Runbook の構成

各アラートには対応手順（Runbook）を用意:

```markdown
# PostgreSQLDown Runbook

## 概要
PostgreSQLが停止している状態

## 影響
- 全サービスがデータベースにアクセス不可
- 認証、ユーザー情報取得が不可

## 緊急対応（5分以内）
1. PostgreSQLコンテナ状態確認
   ```bash
   docker ps | grep postgres
   docker logs postgres
   ```

2. 再起動試行
   ```bash
   cd ai-micro-postgres
   docker compose restart
   ```

3. 接続確認
   ```bash
   docker exec postgres psql -U postgres -c "SELECT 1"
   ```

## 根本原因調査
- ログ確認: `/var/lib/docker/containers/.../postgres.log`
- ディスク容量確認: `df -h`
- メモリ確認: `free -h`

## エスカレーション
- 15分で復旧しない場合 → データベーススペシャリストに連絡
```

### Runbook の保存場所

```
docs/runbooks/
  ├── postgres-down.md
  ├── redis-down.md
  ├── auth-service-down.md
  ├── high-error-rate.md
  └── high-latency.md
```

---

## アラートテスト

### 手動テストアラート送信

```bash
# AlertManagerにテストアラート送信
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[
    {
      "labels": {
        "alertname": "TestAlert",
        "severity": "warning",
        "service": "test"
      },
      "annotations": {
        "summary": "This is a test alert",
        "description": "Testing alert notification"
      }
    }
  ]'
```

### アラートルール検証

```bash
# Prometheusルールファイル検証
promtool check rules alerts/*.yml

# 特定のアラートが発火するか確認
promtool query instant http://localhost:9090 \
  'up{job="auth-service"} == 0'
```

---

## アラートのメトリクス

### アラート自体の監視

```yaml
# AlertManagerメトリクス
alertmanager_notifications_total  # 通知送信総数
alertmanager_notifications_failed_total  # 通知失敗数
alertmanager_alerts  # アクティブアラート数
alertmanager_silences  # サイレンス数
```

### アラート品質メトリクス

```yaml
計測すべきメトリクス:
  - MTTD (Mean Time To Detect): 障害検知までの平均時間
  - MTTR (Mean Time To Resolve): 解決までの平均時間
  - False Positive Rate: 誤検知率
  - Alert Fatigue Index: アラート疲れ指数
```

---

## ベストプラクティス

### 1. アラートは症状に対して、原因ではない

```yaml
# ❌ 悪い例
- alert: DiskUsageHigh
  expr: disk_usage > 80%

# ✅ 良い例
- alert: ServiceDegradedDueToHighDiskUsage
  expr: disk_usage > 80% AND service_error_rate > 5%
```

### 2. アラートにはコンテキストを含める

```yaml
annotations:
  summary: "PostgreSQL connection limit approaching"
  description: "Current: {{ $value }}%, Max: 100 connections"
  impact: "New connections may be rejected"
  runbook_url: "https://docs.example.com/runbooks/postgres-connections"
  dashboard_url: "https://grafana.example.com/d/postgres"
```

### 3. アラート閾値の調整

```yaml
# 初期設定
threshold: 80%

# 運用データを元に調整
# - 過去1ヶ月の最大値: 75%
# - 余裕を持たせて: 85%に調整
threshold: 85%
```

### 4. サイレンス機能の活用

```bash
# メンテナンス中はアラートをサイレンス
amtool silence add \
  alertname=PostgreSQLDown \
  --duration=2h \
  --comment="Scheduled maintenance"
```

---

## 参考資料

- [03-monitoring.md](./03-monitoring.md) - 監視設計
- [04-logging.md](./04-logging.md) - ログ設計
- [06-troubleshooting.md](./06-troubleshooting.md) - トラブルシューティング
- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [AlertManager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

---

**変更履歴**:

- 2025-09-30: 初版作成