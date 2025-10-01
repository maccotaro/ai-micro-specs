# Admin API - ジョブ管理API仕様

**カテゴリ**: Backend Service API
**バージョン**: 1.0.0
**最終更新**: 2025-10-01

## 目次
- [概要](#概要)
- [ジョブステータス取得](#ジョブステータス取得)
- [ジョブ一覧取得](#ジョブ一覧取得)
- [ジョブクリーンアップ](#ジョブクリーンアップ)
- [デバッグ機能](#デバッグ機能)

---

## 概要

ジョブ管理APIは、バックグラウンドで実行される長時間処理（ドキュメント処理、ベクトル化など）の進捗監視と管理を提供します。

**ベースURL**: `/admin/jobs`

**主要機能**:
- ジョブステータス・進捗のリアルタイム取得
- ユーザー別ジョブ一覧取得
- 完了ジョブのクリーンアップ
- 処理中ジョブのリセット
- デバッグ用の詳細情報取得

---

## データ型定義

### JobStatus

```typescript
enum JobStatus {
  PENDING = "pending",       // 待機中
  RUNNING = "running",       // 実行中
  COMPLETED = "completed",   // 完了
  FAILED = "failed"          // 失敗
}
```

### JobProgress

```typescript
interface JobProgress {
  current_step: number;          // 現在のステップ番号
  total_steps: number;           // 総ステップ数
  step_description: string;      // 現在のステップ説明
  percentage: number;            // 進捗率（0-100）
  details?: Record<string, any>; // 追加詳細情報
}
```

### Job

```typescript
interface Job {
  job_id: string;                // ジョブID（UUID）
  job_type: string;              // ジョブタイプ（例: "document_processing", "vectorization"）
  description: string;           // ジョブ説明
  status: JobStatus;             // ジョブステータス
  progress: JobProgress;         // 進捗情報
  error?: string;                // エラーメッセージ（失敗時）
  result?: any;                  // 処理結果（完了時）
  created_at: string;            // 作成日時（ISO）
  started_at?: string;           // 開始日時（ISO）
  completed_at?: string;         // 完了日時（ISO）
}
```

---

## ジョブステータス取得

### GET /admin/jobs/{job_id}

特定ジョブのステータスと進捗を取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `job_id` (string)

#### レスポンス

```typescript
interface JobResponse extends Job {
  // 上記Job型のすべてのフィールド
}

// 使用例
const job = await fetch(`/api/admin/jobs/${jobId}`)
  .then(r => r.json()) as JobResponse;

console.log(`Progress: ${job.progress.percentage}%`);
console.log(`Status: ${job.status}`);
```

#### レスポンス例

```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "job_type": "document_processing",
  "description": "Processing document: report.pdf",
  "status": "running",
  "progress": {
    "current_step": 3,
    "total_steps": 5,
    "step_description": "Extracting text with OCR",
    "percentage": 60,
    "details": {
      "pages_processed": 12,
      "total_pages": 20
    }
  },
  "created_at": "2025-10-01T14:30:00Z",
  "started_at": "2025-10-01T14:30:05Z"
}
```

---

## ジョブ一覧取得

### GET /admin/jobs

現在のユーザーに関連する全ジョブを取得します。

**認証**: `get_current_user` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `status` | JobStatus | - | ステータスでフィルタ |

#### レスポンス

```typescript
interface JobListResponse {
  jobs: Job[];
  total: number;                 // 総ジョブ数
}

// 使用例
const activeJobs = await fetch('/api/admin/jobs?status=running')
  .then(r => r.json()) as JobListResponse;

console.log(`Active jobs: ${activeJobs.total}`);
```

### GET /admin/jobs/active

アクティブジョブ（PENDING/RUNNINGステータス）のみを取得します。

**認証**: `get_current_user` 必須

```typescript
// 実装注: これは /admin/jobs?status=running と同等
const activeJobs = await fetch('/api/admin/jobs/active')
  .then(r => r.json()) as JobListResponse;
```

### GET /admin/jobs/document/{document_id}

特定ドキュメントに関連するジョブを取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `document_id` (UUID)

```typescript
const docJobs = await fetch(`/api/admin/jobs/document/${documentId}`)
  .then(r => r.json()) as JobListResponse;
```

### GET /admin/jobs/completed/search

完了ジョブを検索します（フィルタリング対応）。

**認証**: `get_current_user` 必須

#### クエリパラメータ

| パラメータ | 型 | 説明 |
|-----------|---|------|
| `job_type` | string | ジョブタイプでフィルタ |
| `start_date` | string | 開始日（ISO） |
| `end_date` | string | 終了日（ISO） |
| `limit` | number | 取得件数（デフォルト: 100） |

```typescript
const completedJobs = await fetch(
  '/api/admin/jobs/completed/search?job_type=document_processing&limit=50'
).then(r => r.json()) as JobListResponse;
```

---

## ジョブクリーンアップ

### POST /admin/jobs/cleanup/completed

完了したジョブをクリーンアップします（古いジョブレコードを削除）。

**認証**: `admin` 必須

#### リクエストボディ

```typescript
interface CleanupCompletedRequest {
  older_than_days?: number;      // 指定日数より古いジョブを削除（デフォルト: 30）
}

interface CleanupCompletedResponse {
  message: string;
  deleted_count: number;         // 削除されたジョブ数
}

// 使用例
const result = await fetch('/api/admin/jobs/cleanup/completed', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ older_than_days: 7 })
}).then(r => r.json()) as CleanupCompletedResponse;

console.log(`Deleted ${result.deleted_count} old jobs`);
```

### POST /admin/jobs/cleanup/reset-processing

"processing"状態でスタックしたジョブをリセットします。

**認証**: `admin` 必須

```typescript
interface ResetProcessingResponse {
  message: string;
  reset_count: number;           // リセットされたジョブ数
}

// 使用例
const result = await fetch('/api/admin/jobs/cleanup/reset-processing', {
  method: 'POST'
}).then(r => r.json()) as ResetProcessingResponse;
```

### DELETE /admin/jobs/{job_id}

特定のジョブを削除します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `job_id` (string)

```typescript
await fetch(`/api/admin/jobs/${jobId}`, {
  method: 'DELETE'
});
```

---

## デバッグ機能

### GET /admin/jobs/debug/{job_id}

ジョブの詳細デバッグ情報を取得します（認証不要）。

**認証**: 不要（デバッグ専用）

**パスパラメータ**: `job_id` (string)

#### レスポンス

```typescript
interface JobDebugResponse {
  debug: true;
  found_in: "active_jobs" | "completed_storage"; // ジョブ検索場所
  job_id: string;
  job_type: string;
  description: string;
  status: string;
  progress: JobProgress;
  error?: string;
  result?: any;
  created_at: string;
  started_at?: string;
  completed_at?: string;
  debug_timestamp: string;       // デバッグ実行時刻
}

// 使用例
const debugInfo = await fetch(`/api/admin/jobs/debug/${jobId}`)
  .then(r => r.json()) as JobDebugResponse;

console.log(`Job found in: ${debugInfo.found_in}`);
```

#### エラーレスポンス（ジョブ未発見時）

```typescript
interface JobNotFoundDebugResponse {
  message: "Job not found";
  job_id: string;
  searched_locations: string[];  // 検索した場所一覧
  search_stats: {
    active_jobs_count: number;
    completed_jobs_count: number;
    total_searched: number;
  };
  timestamp: string;
}
```

### GET /admin/jobs/search/debug

ジョブ検索システムのデバッグ情報を取得します。

**認証**: `admin` 推奨

```typescript
interface JobSearchDebugResponse {
  active_jobs: {
    count: number;
    job_ids: string[];
  };
  completed_storage: {
    count: number;
    job_ids: string[];
  };
  storage_health: {
    active_jobs_available: boolean;
    completed_storage_available: boolean;
  };
}
```

---

## ジョブ進捗の監視パターン

### ポーリング方式

```typescript
async function monitorJob(jobId: string): Promise<Job> {
  while (true) {
    const job = await fetch(`/api/admin/jobs/${jobId}`)
      .then(r => r.json()) as Job;

    console.log(`Progress: ${job.progress.percentage}%`);

    if (job.status === JobStatus.COMPLETED) {
      console.log('Job completed successfully!');
      return job;
    }

    if (job.status === JobStatus.FAILED) {
      throw new Error(`Job failed: ${job.error}`);
    }

    // 2秒ごとにポーリング
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
}
```

### React Hook使用例

```typescript
function useJobStatus(jobId: string | null) {
  const [job, setJob] = useState<Job | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!jobId) return;

    setLoading(true);
    const interval = setInterval(async () => {
      try {
        const response = await fetch(`/api/admin/jobs/${jobId}`);
        if (!response.ok) throw new Error('Failed to fetch job status');

        const jobData = await response.json() as Job;
        setJob(jobData);

        // 完了または失敗時はポーリング停止
        if (jobData.status === JobStatus.COMPLETED ||
            jobData.status === JobStatus.FAILED) {
          clearInterval(interval);
          setLoading(false);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error');
        clearInterval(interval);
        setLoading(false);
      }
    }, 2000);

    return () => clearInterval(interval);
  }, [jobId]);

  return { job, loading, error };
}

// 使用例
function DocumentProcessingStatus({ jobId }: { jobId: string }) {
  const { job, loading, error } = useJobStatus(jobId);

  if (error) return <div>Error: {error}</div>;
  if (!job) return <div>Loading...</div>;

  return (
    <div>
      <h3>{job.description}</h3>
      <ProgressBar value={job.progress.percentage} />
      <p>{job.progress.step_description}</p>
      {job.status === JobStatus.COMPLETED && (
        <p>✓ Completed successfully!</p>
      )}
      {job.status === JobStatus.FAILED && (
        <p>✗ Failed: {job.error}</p>
      )}
    </div>
  );
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
| 404 | ジョブ未発見 | ジョブIDを確認、または完了ジョブが削除された可能性 |
| 403 | 権限不足 | 他ユーザーのジョブにアクセスしようとした |
| 500 | サーバーエラー | ジョブマネージャーの内部エラー、ログを確認 |

---

## 関連ドキュメント

- [ドキュメント処理API](./02-api-documents.md) - ドキュメント処理ジョブの開始
- [ナレッジベースAPI](./02-api-knowledge-bases.md) - ベクトル化ジョブの開始
- [システム管理API](./02-api-system-logs.md) - ジョブマネージャーのステータス確認
