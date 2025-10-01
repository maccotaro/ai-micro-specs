# Admin API - システム管理・ログAPI仕様

**カテゴリ**: Backend Service API
**バージョン**: 1.0.0
**最終更新**: 2025-10-01

## 目次
- [概要](#概要)
- [システムステータス](#システムステータス)
- [システム管理](#システム管理)
- [ログ管理](#ログ管理)

---

## 概要

システム管理・ログAPIは、マイクロサービス全体の監視、メンテナンス、ログ管理機能を提供します。

**ベースURL**: `/admin/system`, `/admin/logs`

**主要機能**:
- システム全体のヘルスチェック
- データベース・Redisのステータス監視
- メンテナンスモード管理
- キャッシュクリア
- システムログのフィルタリング・検索

---

## データ型定義

### ServiceStatus

```typescript
enum ServiceStatus {
  ONLINE = "online",
  OFFLINE = "offline",
  WARNING = "warning"
}
```

### ServiceInfo

```typescript
interface ServiceInfo {
  name: string;                  // サービス名
  status: ServiceStatus;         // ステータス
  url: string;                   // エンドポイントURL
  response_time?: number;        // 応答時間（ミリ秒）
  last_check: string;            // 最終チェック時刻（ISO）
  error_message?: string;        // エラーメッセージ
}
```

### DatabaseStatus

```typescript
interface DatabaseStatus {
  status: ServiceStatus;
  connections: {
    active: number;              // アクティブ接続数
    max: number;                 // 最大接続数
  };
  response_time?: number;        // 応答時間（ミリ秒）
}
```

### RedisStatus

```typescript
interface RedisStatus {
  status: ServiceStatus;
  memory_usage: {
    used: string;                // 使用メモリ（例: "2.1MB"）
    max: string;                 // 最大メモリ（例: "512MB"）
    percentage: number;          // 使用率（0-100）
  };
  response_time?: number;        // 応答時間（ミリ秒）
}
```

---

## システムステータス

### GET /admin/system/status

システム全体のステータスを取得します。

**認証**: `admin` 必須

#### レスポンス

```typescript
interface SystemStatus {
  services: ServiceInfo[];       // 全サービス情報
  database: DatabaseStatus;      // データベース情報
  redis: RedisStatus;            // Redis情報
  overall: ServiceStatus;        // 全体ステータス
}

// 使用例
const status = await fetch('/api/admin/system/status')
  .then(r => r.json()) as SystemStatus;

console.log(`Overall status: ${status.overall}`);
status.services.forEach(s => {
  console.log(`${s.name}: ${s.status} (${s.response_time}ms)`);
});
```

#### レスポンス例

```json
{
  "services": [
    {
      "name": "Frontend (Next.js)",
      "status": "online",
      "url": "http://localhost:3002",
      "response_time": 25,
      "last_check": "2025-10-01T14:30:00Z"
    },
    {
      "name": "Auth Service",
      "status": "online",
      "url": "http://host.docker.internal:8002",
      "response_time": 45,
      "last_check": "2025-10-01T14:30:00Z"
    },
    {
      "name": "User API",
      "status": "online",
      "url": "http://host.docker.internal:8001",
      "response_time": 38,
      "last_check": "2025-10-01T14:30:00Z"
    },
    {
      "name": "Admin API",
      "status": "online",
      "url": "http://localhost:8003",
      "response_time": 15,
      "last_check": "2025-10-01T14:30:00Z"
    }
  ],
  "database": {
    "status": "online",
    "connections": {
      "active": 12,
      "max": 100
    },
    "response_time": 3
  },
  "redis": {
    "status": "online",
    "memory_usage": {
      "used": "2.1MB",
      "max": "512MB",
      "percentage": 0.41
    },
    "response_time": 2
  },
  "overall": "online"
}
```

### GET /admin/system/database/status

PostgreSQLデータベースの詳細ステータスを取得します。

**認証**: `admin` 必須

```typescript
const dbStatus = await fetch('/api/admin/system/database/status')
  .then(r => r.json()) as DatabaseStatus;

console.log(`DB connections: ${dbStatus.connections.active}/${dbStatus.connections.max}`);
```

### GET /admin/system/redis/status

Redisキャッシュの詳細ステータスを取得します。

**認証**: `admin` 必須

```typescript
const redisStatus = await fetch('/api/admin/system/redis/status')
  .then(r => r.json()) as RedisStatus;

console.log(`Redis memory: ${redisStatus.memory_usage.used} / ${redisStatus.memory_usage.max}`);
console.log(`Usage: ${redisStatus.memory_usage.percentage}%`);
```

### GET /admin/system/info

システム情報を取得します。

**認証**: `admin` 必須

```typescript
interface SystemInfo {
  service: string;               // サービス名
  version: string;               // バージョン
  environment: string;           // 環境（development/production）
  python_version: string;        // Pythonバージョン
  database: string;              // データベース名
  cache: string;                 // キャッシュシステム名
  uptime: string;                // 稼働時間
}

const info = await fetch('/api/admin/system/info')
  .then(r => r.json()) as SystemInfo;
```

### GET /admin/system/stats/summary

システム統計サマリーを取得します。

**認証**: `admin` 必須

```typescript
interface SystemStatsSummary {
  total_documents: number;
  total_users: number;
  total_knowledge_bases: number;
  active_jobs: number;
  storage_used_bytes: number;
  last_updated: string;
}

const summary = await fetch('/api/admin/system/stats/summary')
  .then(r => r.json()) as SystemStatsSummary;
```

---

## システム管理

### POST /admin/system/maintenance

メンテナンスモードを切り替えます。

**認証**: `super_admin` 必須

#### リクエストボディ

```typescript
interface MaintenanceRequest {
  enabled: boolean;              // true: メンテナンスモード有効
}

interface MaintenanceResponse {
  maintenance_mode: boolean;     // 現在のモード
  message: string;               // 結果メッセージ
}

// 使用例
const result = await fetch('/api/admin/system/maintenance', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ enabled: true })
}).then(r => r.json()) as MaintenanceResponse;

console.log(result.message); // "Maintenance mode enabled"
```

### POST /admin/system/cache/clear

Redisキャッシュをクリアします。

**認証**: `super_admin` 必須

#### リクエストボディ

```typescript
interface ClearCacheRequest {
  cache_type?: "all" | "redis" | "application"; // デフォルト: "all"
}

interface ClearCacheResponse {
  message: string;
  success: boolean;
}

// 使用例
const result = await fetch('/api/admin/system/cache/clear', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ cache_type: 'redis' })
}).then(r => r.json()) as ClearCacheResponse;
```

---

## ログ管理

### GET /admin/logs

システムログをフィルタリング・ページネーションして取得します。

**認証**: `admin` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `service` | string | - | サービス名でフィルタ（例: "auth", "user", "admin"） |
| `level` | string | - | ログレベルでフィルタ（DEBUG, INFO, WARN, ERROR） |
| `page` | number | 1 | ページ番号 |
| `limit` | number | 50 | 1ページあたりのログ数（最大1000） |

#### データ型

```typescript
enum LogLevel {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR"
}

interface LogEntry {
  id: string;                    // UUID
  service_name: string;          // サービス名
  level: LogLevel;               // ログレベル
  message: string;               // ログメッセージ
  metadata?: Record<string, any>; // 追加メタデータ
  created_at: string;            // ISO日時文字列
}

interface LogsResponse {
  logs: LogEntry[];
  total: number;                 // 総ログ数（フィルタ適用後）
  page: number;                  // 現在のページ
  limit: number;                 // ページサイズ
  pages: number;                 // 総ページ数
}
```

#### 使用例

```typescript
// エラーログのみを取得
const errorLogs = await fetch(
  '/api/admin/logs?level=ERROR&page=1&limit=100'
).then(r => r.json()) as LogsResponse;

errorLogs.logs.forEach(log => {
  console.log(`[${log.service_name}] ${log.message}`);
  if (log.metadata) {
    console.log('  Metadata:', JSON.stringify(log.metadata, null, 2));
  }
});
```

#### レスポンス例

```json
{
  "logs": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "service_name": "auth",
      "level": "ERROR",
      "message": "Failed to validate JWT token",
      "metadata": {
        "error_code": "JWT_EXPIRED",
        "user_id": "987fbc97-4bed-5078-9f07-9141ba07c9f3",
        "token_exp": "2025-10-01T13:00:00Z"
      },
      "created_at": "2025-10-01T14:32:15.123456Z"
    },
    {
      "id": "223e4567-e89b-12d3-a456-426614174001",
      "service_name": "admin",
      "level": "ERROR",
      "message": "Document processing failed",
      "metadata": {
        "document_id": "456fbc97-4bed-5078-9f07-9141ba07c9f4",
        "error": "OCR timeout after 60 seconds"
      },
      "created_at": "2025-10-01T14:30:45.678901Z"
    }
  ],
  "total": 1523,
  "page": 1,
  "limit": 100,
  "pages": 16
}
```

### GET /admin/logs/{service}

特定サービスのログを取得します。

**認証**: `admin` 必須

**パスパラメータ**: `service` (string) - サービス名（例: "auth", "user", "admin"）

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `level` | string | - | ログレベルでフィルタ |
| `limit` | number | 100 | 取得数（最大1000） |

```typescript
// Auth Serviceのエラーログを取得
const authErrorLogs = await fetch(
  '/api/admin/logs/auth?level=ERROR&limit=50'
).then(r => r.json()) as LogEntry[];

console.log(`Found ${authErrorLogs.length} error logs from auth service`);
```

### POST /admin/logs/create

ログエントリを作成します（テスト用）。

**認証**: `admin` 必須

#### リクエストボディ

```typescript
interface CreateLogRequest {
  service_name: string;          // サービス名
  level: LogLevel;               // ログレベル
  message: string;               // ログメッセージ
  metadata?: Record<string, any>; // 追加メタデータ
}

// 使用例
const newLog = await fetch('/api/admin/logs/create', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    service_name: 'test',
    level: LogLevel.INFO,
    message: 'Test log entry',
    metadata: { test: true, timestamp: new Date().toISOString() }
  })
}).then(r => r.json()) as LogEntry;
```

---

## React Hook使用例

### システムステータス監視

```typescript
function useSystemStatus(pollInterval: number = 30000) {
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchStatus = async () => {
      try {
        const data = await fetch('/api/admin/system/status')
          .then(r => r.json());
        setStatus(data);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to fetch');
      } finally {
        setLoading(false);
      }
    };

    fetchStatus();
    const interval = setInterval(fetchStatus, pollInterval);

    return () => clearInterval(interval);
  }, [pollInterval]);

  return { status, loading, error };
}

// 使用例
function SystemStatusDashboard() {
  const { status, loading, error } = useSystemStatus(30000); // 30秒ごとに更新

  if (loading) return <div>Loading system status...</div>;
  if (error) return <div>Error: {error}</div>;
  if (!status) return null;

  return (
    <div>
      <h2>System Status: {status.overall.toUpperCase()}</h2>

      <section>
        <h3>Services</h3>
        {status.services.map(service => (
          <div key={service.name}>
            <span className={`status-${service.status}`}>
              {service.name}: {service.status}
            </span>
            {service.response_time && (
              <span> ({service.response_time}ms)</span>
            )}
          </div>
        ))}
      </section>

      <section>
        <h3>Database</h3>
        <p>Status: {status.database.status}</p>
        <p>Connections: {status.database.connections.active}/{status.database.connections.max}</p>
      </section>

      <section>
        <h3>Redis</h3>
        <p>Status: {status.redis.status}</p>
        <p>Memory: {status.redis.memory_usage.used} / {status.redis.memory_usage.max} ({status.redis.memory_usage.percentage}%)</p>
      </section>
    </div>
  );
}
```

### ログ検索

```typescript
function useLogSearch(filters: {
  service?: string;
  level?: LogLevel;
  page?: number;
  limit?: number;
}) {
  const [logs, setLogs] = useState<LogsResponse | null>(null);
  const [loading, setLoading] = useState(false);

  const search = useCallback(async () => {
    setLoading(true);
    const params = new URLSearchParams();

    if (filters.service) params.append('service', filters.service);
    if (filters.level) params.append('level', filters.level);
    params.append('page', String(filters.page || 1));
    params.append('limit', String(filters.limit || 50));

    try {
      const data = await fetch(`/api/admin/logs?${params}`)
        .then(r => r.json());
      setLogs(data);
    } catch (err) {
      console.error('Failed to fetch logs:', err);
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    search();
  }, [search]);

  return { logs, loading, refetch: search };
}
```

---

## エラーレスポンス

### 標準エラー形式

```typescript
interface APIError {
  detail: string;                // エラー詳細メッセージ
}
```

### よくあるエラー

| コード | 説明 | 対処法 |
|-------|------|-------|
| 403 | 権限不足 | super_adminロールが必要な操作 |
| 500 | サーバーエラー | Redis/DB接続失敗、ログを確認 |
| 503 | サービス利用不可 | 外部サービスがダウンしている |

---

## 関連ドキュメント

- [ドキュメント処理API](./02-api-documents.md) - ドキュメント処理ステータス確認
- [ジョブ管理API](./02-api-jobs.md) - ジョブマネージャーのステータス
- [ナレッジベースAPI](./02-api-knowledge-bases.md) - ベクトルストアのヘルスチェック
