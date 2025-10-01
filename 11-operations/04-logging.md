# ログ設計

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムにおけるログ設計、ログレベル、ログフォーマット、集約方法について定義します。

## ログ設計の原則

### 基本方針

1. **構造化ログ**: JSON形式で機械可読性を確保
2. **適切なレベル**: ログレベルを適切に使い分け
3. **コンテキスト情報**: 必要な情報を過不足なく記録
4. **一貫性**: 全サービスで統一されたフォーマット
5. **パフォーマンス**: ログ出力がボトルネックにならない

### ログの3つの用途

1. **デバッグ**: 開発時の問題調査
2. **運用監視**: 本番環境の状態把握
3. **監査**: セキュリティとコンプライアンス

---

## ログレベル

### レベル定義

| レベル | 用途 | 例 |
|--------|------|-----|
| **DEBUG** | 詳細なデバッグ情報（開発環境のみ） | 変数の値、関数の入出力 |
| **INFO** | 通常動作の情報 | リクエスト受信、処理完了 |
| **WARNING** | 警告（処理は継続） | リトライ発生、非推奨機能使用 |
| **ERROR** | エラー（処理失敗） | API呼び出し失敗、例外発生 |
| **CRITICAL** | 致命的エラー（サービス停止） | データベース接続不可 |

### 環境別ログレベル

```yaml
開発環境: DEBUG
ステージング環境: INFO
本番環境: INFO (一部サービスはWARNING)
```

---

## ログフォーマット

### 構造化ログ（JSON）

**標準フォーマット**:

```json
{
  "timestamp": "2025-09-30T12:34:56.789Z",
  "level": "INFO",
  "service": "auth-service",
  "environment": "production",
  "trace_id": "abc123xyz",
  "request_id": "req-456",
  "user_id": "user-789",
  "method": "POST",
  "path": "/api/auth/login",
  "status_code": 200,
  "duration_ms": 145,
  "message": "User logged in successfully",
  "context": {
    "ip_address": "192.168.1.100",
    "user_agent": "Mozilla/5.0..."
  }
}
```

### 必須フィールド

| フィールド | 説明 | 例 |
|-----------|------|-----|
| `timestamp` | ISO 8601形式のタイムスタンプ | 2025-09-30T12:34:56.789Z |
| `level` | ログレベル | INFO, ERROR |
| `service` | サービス名 | auth-service |
| `message` | ログメッセージ | User logged in |

### 推奨フィールド

| フィールド | 説明 | 例 |
|-----------|------|-----|
| `environment` | 実行環境 | production, staging |
| `trace_id` | 分散トレーシングID | abc123xyz |
| `request_id` | リクエストID | req-456 |
| `user_id` | ユーザーID（認証後） | user-789 |
| `duration_ms` | 処理時間（ミリ秒） | 145 |

---

## サービス別ログ実装

### FastAPI サービス（Auth, User API, Admin API）

#### ログ設定

```python
# app/core/logging.py
import logging
import json
import sys
from datetime import datetime
from pythonjsonlogger import jsonlogger

class CustomJsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)

        # タイムスタンプ
        log_record['timestamp'] = datetime.utcnow().isoformat() + 'Z'

        # ログレベル
        log_record['level'] = record.levelname

        # サービス名（環境変数から取得）
        log_record['service'] = os.getenv('SERVICE_NAME', 'unknown')
        log_record['environment'] = os.getenv('ENVIRONMENT', 'development')

def setup_logging():
    log_level = os.getenv('LOG_LEVEL', 'INFO')

    # ハンドラ設定
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(CustomJsonFormatter(
        '%(timestamp)s %(level)s %(service)s %(message)s'
    ))

    # ルートロガー設定
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.addHandler(handler)

    # サードパーティライブラリのログレベル調整
    logging.getLogger('uvicorn').setLevel(logging.WARNING)
    logging.getLogger('sqlalchemy').setLevel(logging.WARNING)

# アプリケーション起動時
setup_logging()
logger = logging.getLogger(__name__)
```

#### ミドルウェアでのリクエストログ

```python
# app/middleware/logging.py
import time
import uuid
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # リクエストID生成
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id

        # 開始時刻
        start_time = time.time()

        # リクエストログ
        logger.info("Request received", extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "client_ip": request.client.host,
            "user_agent": request.headers.get("user-agent")
        })

        # 処理実行
        response = await call_next(request)

        # レスポンスログ
        duration_ms = (time.time() - start_time) * 1000

        log_level = logging.INFO if response.status_code < 400 else logging.ERROR

        logger.log(log_level, "Request completed", extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": round(duration_ms, 2)
        })

        # レスポンスヘッダーにリクエストIDを追加
        response.headers["X-Request-ID"] = request_id

        return response

# app/main.py
app.add_middleware(LoggingMiddleware)
```

#### ビジネスロジックでのログ

```python
# app/services/auth.py
import logging

logger = logging.getLogger(__name__)

async def login(username: str, password: str):
    logger.info("Login attempt", extra={
        "username": username,
        "action": "login"
    })

    try:
        user = await authenticate_user(username, password)

        if user:
            logger.info("Login successful", extra={
                "user_id": user.id,
                "username": username,
                "action": "login_success"
            })
            return user
        else:
            logger.warning("Login failed: invalid credentials", extra={
                "username": username,
                "action": "login_failure",
                "reason": "invalid_credentials"
            })
            return None

    except Exception as e:
        logger.error("Login error", extra={
            "username": username,
            "action": "login_error",
            "error": str(e)
        }, exc_info=True)
        raise
```

#### セキュリティセンシティブな情報の扱い

**ログに含めてはいけない情報**:

- パスワード
- トークン（完全な形）
- クレジットカード番号
- 個人情報（PII）

**実装例**:

```python
# app/core/logging.py
import re

SENSITIVE_PATTERNS = [
    r'"password":\s*"[^"]*"',
    r'"token":\s*"[^"]*"',
    r'"secret":\s*"[^"]*"',
]

def sanitize_log_data(data: dict) -> dict:
    """センシティブ情報をマスク"""
    sanitized = data.copy()

    if 'password' in sanitized:
        sanitized['password'] = '***REDACTED***'

    if 'token' in sanitized:
        # 最初の4文字と最後の4文字のみ表示
        token = sanitized['token']
        if len(token) > 8:
            sanitized['token'] = f"{token[:4]}...{token[-4:]}"

    return sanitized

# 使用例
logger.info("User data", extra=sanitize_log_data(user_data))
```

### Next.js フロントエンド

#### サーバーサイドログ

```typescript
// lib/logger.ts
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() };
    },
  },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  base: {
    service: process.env.SERVICE_NAME || 'frontend',
    environment: process.env.NODE_ENV,
  },
});

export default logger;
```

#### APIルートでのログ

```typescript
// pages/api/[...path].ts
import logger from '@/lib/logger';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const requestId = generateRequestId();

  logger.info({
    msg: 'API request received',
    request_id: requestId,
    method: req.method,
    path: req.url,
  });

  try {
    const response = await proxyToBackend(req);

    logger.info({
      msg: 'API request completed',
      request_id: requestId,
      status: response.status,
    });

    return res.status(response.status).json(response.data);

  } catch (error) {
    logger.error({
      msg: 'API request failed',
      request_id: requestId,
      error: error.message,
    });

    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

#### クライアントサイドログ（エラーのみ）

```typescript
// lib/clientLogger.ts
export function logClientError(error: Error, context?: Record<string, any>) {
  // 本番環境ではバックエンドに送信
  if (process.env.NODE_ENV === 'production') {
    fetch('/api/log/client-error', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: error.message,
        stack: error.stack,
        context,
        timestamp: new Date().toISOString(),
      }),
    }).catch(() => {
      // ログ送信失敗は無視
    });
  } else {
    console.error('Client error:', error, context);
  }
}

// 使用例
try {
  await fetchUserProfile();
} catch (error) {
  logClientError(error, { userId: user.id, action: 'fetch_profile' });
}
```

---

## ログ集約

### アーキテクチャ

```
┌──────────────────────────────────────────┐
│  Services (Docker Containers)            │
│  • auth-service (stdout/stderr)          │
│  • user-api (stdout/stderr)              │
│  • admin-api (stdout/stderr)             │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Log Collection (Docker Logging Driver)  │
│  • json-file driver                      │
│  • or fluentd driver                     │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Log Aggregation (Loki or ELK)           │
│  • Parsing & Indexing                    │
│  • Storage                               │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Visualization (Grafana or Kibana)       │
│  • Log Search                            │
│  • Log Analytics                         │
└──────────────────────────────────────────┘
```

### Loki による集約（推奨）

**利点**:

- Prometheusと同じラベルベースのアーキテクチャ
- Grafanaとの統合が容易
- 軽量でコスト効率が良い

#### Loki 設定

```yaml
# loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h  # 30 days
```

#### Docker Logging Driver

```yaml
# docker-compose.yml
services:
  auth-service:
    image: auth-service:latest
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "service,environment"

  # または Loki driver使用
  user-api:
    image: user-api:latest
    logging:
      driver: "loki"
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        loki-batch-size: "400"
```

#### Promtail（Loki Log Collector）

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
```

```yaml
# docker-compose.yml
services:
  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
```

---

## ログクエリとフィルタリング

### LogQL（Loki Query Language）

#### 基本クエリ

```logql
# 特定サービスのログ
{service="auth-service"}

# エラーレベルのログ
{service="auth-service"} |= "ERROR"

# ユーザーIDでフィルタ
{service="user-api"} | json | user_id="user-789"

# レスポンスタイム > 1秒
{service="admin-api"} | json | duration_ms > 1000
```

#### 集計クエリ

```logql
# エラー数の推移
sum(rate({level="ERROR"}[5m])) by (service)

# レスポンスタイムのp95
quantile_over_time(0.95, {service="auth-service"} | json | unwrap duration_ms [5m])

# ログイン成功/失敗率
sum(rate({service="auth-service", action="login_success"}[5m]))
/
sum(rate({service="auth-service", action=~"login_.*"}[5m]))
```

### Grafana でのログ可視化

#### ログパネルの作成

```
1. Grafana ダッシュボードで "Add Panel"
2. Data source: Loki
3. Query:
   {service="auth-service", level="ERROR"}
4. Visualization: Logs
5. Options:
   - Show time: Yes
   - Show labels: Yes
   - Wrap lines: Yes
```

#### ログとメトリクスの相関

```
Dashboard with:
  - Top: Metrics panel (Request rate, Error rate)
  - Bottom: Logs panel (Filtered by time range)

Clicking on error spike in metrics → Auto-filter logs for that time
```

---

## ログローテーション

### Docker ログローテーション

```yaml
# docker-compose.yml
services:
  auth-service:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"    # ファイルサイズ上限
        max-file: "3"      # 保持ファイル数
        compress: "true"   # 圧縮有効化
```

**結果**: 最大30MBのログを保持（10MB × 3ファイル）

### Loki データ保持

```yaml
# loki-config.yml
table_manager:
  retention_deletes_enabled: true
  retention_period: 720h  # 30日間保持
```

---

## ログのベストプラクティス

### 1. ログに含めるべき情報

**必須**:

- タイムスタンプ
- ログレベル
- サービス名
- メッセージ

**推奨**:

- リクエストID（分散トレーシング用）
- ユーザーID（認証後）
- 処理時間
- エラー詳細（スタックトレース）

### 2. ログに含めてはいけない情報

- パスワード
- APIキー・シークレット
- トークン（完全な形）
- クレジットカード情報
- 個人情報（PII）

### 3. ログレベルの使い分け

```python
# DEBUG: 開発時のみ
logger.debug(f"Calculated value: {result}")

# INFO: 正常な動作
logger.info("User profile updated successfully", extra={"user_id": user_id})

# WARNING: 注意が必要だが処理は継続
logger.warning("Cache miss, fetching from database", extra={"key": cache_key})

# ERROR: エラーが発生したが回復可能
logger.error("Failed to send email", extra={"user_id": user_id}, exc_info=True)

# CRITICAL: サービスが継続できない致命的エラー
logger.critical("Database connection lost", exc_info=True)
```

### 4. 構造化ログのメリット

```python
# ❌ 悪い例: 文字列結合
logger.info(f"User {user_id} logged in from {ip_address}")

# ✅ 良い例: 構造化
logger.info("User logged in", extra={
    "user_id": user_id,
    "ip_address": ip_address,
    "action": "login"
})
```

**理由**: 構造化ログは機械可読性が高く、クエリやフィルタリングが容易。

### 5. コンテキストの伝播

```python
# リクエストIDをコンテキストに保存
from contextvars import ContextVar

request_id_var: ContextVar[str] = ContextVar('request_id', default=None)

# ミドルウェアで設定
request_id_var.set(request_id)

# 各ログで自動的に含める
class RequestIdFilter(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_var.get()
        return True

logger.addFilter(RequestIdFilter())
```

---

## パフォーマンス考慮事項

### ログ出力のコスト

```python
# ❌ 悪い例: 不要な文字列処理
logger.debug(f"Complex calculation: {expensive_function()}")
# → expensive_function()はDEBUGレベルが無効でも実行される

# ✅ 良い例: レベルチェック
if logger.isEnabledFor(logging.DEBUG):
    logger.debug(f"Complex calculation: {expensive_function()}")

# または lazy evaluation
logger.debug("Complex calculation: %s", expensive_function)
```

### 非同期ログ出力

```python
# 非同期ハンドラ使用（高スループット時）
from logging.handlers import QueueHandler, QueueListener
import queue

log_queue = queue.Queue()
queue_handler = QueueHandler(log_queue)

# リスナーは別スレッドで動作
listener = QueueListener(log_queue, file_handler, json_handler)
listener.start()
```

---

## トラブルシューティング

### ログが出力されない

```bash
# Dockerコンテナログ確認
docker logs <container-name>

# ログレベル確認
docker exec <container-name> env | grep LOG_LEVEL

# ログ設定ファイル確認
docker exec <container-name> cat /app/logging.conf
```

### ログディスク使用量の増加

```bash
# ディスク使用量確認
docker system df

# ログファイルサイズ確認
du -sh /var/lib/docker/containers/*/*-json.log

# 古いログのクリーンアップ
docker system prune --volumes
```

---

## 参考資料

- [03-monitoring.md](./03-monitoring.md) - 監視設計
- [05-alerting.md](./05-alerting.md) - アラート設計
- [06-troubleshooting.md](./06-troubleshooting.md) - トラブルシューティング
- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- [Python logging Best Practices](https://docs.python.org/3/howto/logging.html)

---

**変更履歴**:

- 2025-09-30: 初版作成