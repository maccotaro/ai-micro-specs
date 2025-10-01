# 03-api-integration.md - API統合設計

## 概要

Admin Frontendは**BFF (Backend for Frontend)パターン**を採用し、Next.jsのAPI Routesを通じて複数のバックエンドマイクロサービスと通信します。この設計により、フロントエンドとバックエンドの疎結合、セキュリティ強化、エラーハンドリングの一元化を実現しています。

## BFFアーキテクチャ

### 通信フロー

```
ブラウザ (React)
    ↓ fetch/axios
Next.js API Routes (/api/*)
    ↓ HTTP
┌─────────────────────────────────────┐
│ バックエンドマイクロサービス        │
├─────────────────────────────────────┤
│ • Auth Service (8002)               │
│ • User API (8001)                   │
│ • Admin API (8003)                  │
│ • PostgreSQL (via services)         │
│ • Redis (via services)              │
└─────────────────────────────────────┘
```

### BFFの責務

1. **認証・認可:** JWT tokenの検証と管理
2. **リクエストプロキシ:** バックエンドAPIへのリクエスト中継
3. **データ変換:** バックエンドレスポンスのフロントエンド向け整形
4. **エラーハンドリング:** エラーレスポンスの統一化
5. **セキュリティ:** Cookie管理、CSRF対策

## API Routes構成

### 認証関連 (`/api/auth/*`)

#### `POST /api/auth/login`

**目的:** 管理者ログイン処理

**実装ファイル:** `/src/pages/api/auth/login.ts`

```typescript
// リクエスト
interface LoginRequest {
  email: string;
  password: string;
}

// レスポンス
interface LoginResponse {
  message: string;
  user?: {
    id: string;
    email: string;
    role: string;
  };
}

// 実装例
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { email, password } = req.body;

    // Auth Serviceへプロキシ
    const response = await fetch(`${AUTH_SERVER_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    const data = await response.json();

    if (!response.ok) {
      return res.status(response.status).json(data);
    }

    // JWT tokenをhttpOnlyクッキーに保存
    res.setHeader('Set-Cookie', [
      cookie.serialize('access_token', data.access_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        maxAge: 3600, // 1時間
        sameSite: 'strict',
        path: '/',
      }),
      cookie.serialize('refresh_token', data.refresh_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        maxAge: 86400 * 7, // 7日
        sameSite: 'strict',
        path: '/',
      }),
    ]);

    res.status(200).json({ message: 'Login successful', user: data.user });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

#### `POST /api/auth/logout`

**目的:** ログアウト処理とtoken無効化

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Cookieを削除
  res.setHeader('Set-Cookie', [
    cookie.serialize('access_token', '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      maxAge: 0,
      path: '/',
    }),
    cookie.serialize('refresh_token', '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      maxAge: 0,
      path: '/',
    }),
  ]);

  res.status(200).json({ message: 'Logout successful' });
}
```

#### `GET /api/auth/me`

**目的:** 現在のユーザー情報取得

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const token = req.cookies.access_token;

  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // Auth Serviceで検証
    const response = await fetch(`${AUTH_SERVER_URL}/auth/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

### ユーザー管理 (`/api/users/*`)

#### `GET /api/users`

**目的:** ユーザー一覧取得（ページネーション対応）

**実装ファイル:** `/src/pages/api/users/index.ts`

```typescript
interface UsersQueryParams {
  page?: number;
  limit?: number;
  search?: string;
  role?: string;
  status?: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const token = req.cookies.access_token;

  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // クエリパラメータ構築
  const params = new URLSearchParams();
  if (req.query.page) params.set('page', req.query.page as string);
  if (req.query.limit) params.set('limit', req.query.limit as string);
  if (req.query.search) params.set('search', req.query.search as string);
  if (req.query.role) params.set('role', req.query.role as string);

  try {
    const response = await fetch(
      `${API_SERVER_URL}/users?${params.toString()}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch users' });
  }
}
```

#### `PUT /api/users/[id]`

**目的:** ユーザー情報更新

```typescript
interface UpdateUserRequest {
  first_name?: string;
  last_name?: string;
  role?: string;
  is_active?: boolean;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'PUT') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(`${API_SERVER_URL}/users/${id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(req.body),
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to update user' });
  }
}
```

### ドキュメント管理 (`/api/documents/*`)

#### `GET /api/documents`

**目的:** ドキュメント一覧取得

**実装ファイル:** `/src/pages/api/documents/index.ts`

```typescript
interface DocumentsQueryParams {
  page?: number;
  limit?: number;
  search?: string;
  status?: DocumentStatus;
  knowledge_base_id?: string;
  document_type?: string;
}

interface DocumentListResponse {
  documents: KnowledgeDocument[];
  total: number;
  pages: number;
  current_page: number;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<DocumentListResponse | ErrorResponse>
) {
  const token = req.cookies.access_token;

  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const params = new URLSearchParams();
  if (req.query.page) params.set('skip', String((Number(req.query.page) - 1) * Number(req.query.limit || 20)));
  if (req.query.limit) params.set('limit', req.query.limit as string);
  if (req.query.search) params.set('search', req.query.search as string);
  if (req.query.status) params.set('status', req.query.status as string);
  if (req.query.knowledge_base_id) params.set('knowledge_base_id', req.query.knowledge_base_id as string);

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents?${params.toString()}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    const data = await response.json();

    // レスポンス変換（Admin APIからフロントエンド形式へ）
    const transformedData: DocumentListResponse = {
      documents: data.documents || [],
      total: data.total || 0,
      pages: Math.ceil((data.total || 0) / Number(req.query.limit || 20)),
      current_page: Number(req.query.page || 1),
    };

    res.status(200).json(transformedData);
  } catch (error) {
    console.error('Documents fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch documents' });
  }
}
```

#### `POST /api/documents/upload`

**目的:** ドキュメントアップロード（マルチパート対応）

**実装ファイル:** `/src/pages/api/documents/upload.ts`

```typescript
import formidable from 'formidable';
import fs from 'fs';
import FormData from 'form-data';

export const config = {
  api: {
    bodyParser: false, // formidableを使うため無効化
  },
};

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const token = req.cookies.access_token;

  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // フォームデータをパース
    const form = formidable({ multiples: false });
    const [fields, files] = await form.parse(req);

    const file = files.file?.[0];
    const knowledgeBaseId = fields.knowledge_base_id?.[0];

    if (!file || !knowledgeBaseId) {
      return res.status(400).json({ error: 'Missing file or knowledge_base_id' });
    }

    // Admin APIへマルチパート送信
    const formData = new FormData();
    formData.append('file', fs.createReadStream(file.filepath), {
      filename: file.originalFilename || 'document',
      contentType: file.mimetype || 'application/octet-stream',
    });
    formData.append('knowledge_base_id', knowledgeBaseId);

    const response = await fetch(`${ADMIN_API_URL}/admin/documents/upload`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        ...formData.getHeaders(),
      },
      body: formData,
    });

    const data = await response.json();

    // 一時ファイルを削除
    fs.unlinkSync(file.filepath);

    res.status(response.status).json(data);
  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({ error: 'Upload failed' });
  }
}
```

#### `GET /api/documents/[id]/metadata`

**目的:** ドキュメントメタデータ取得

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/metadata`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch metadata' });
  }
}
```

#### `PUT /api/documents/[id]/metadata`

**目的:** メタデータ更新（OCR結果保存）

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'PUT') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/metadata`,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(req.body),
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to update metadata' });
  }
}
```

#### `POST /api/documents/[id]/process`

**目的:** ドキュメント処理ジョブ開始

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/process`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(req.body),
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to start processing' });
  }
}
```

### OCR機能 (`/api/documents/[id]/*`)

#### `POST /api/documents/[id]/ocr-region`

**目的:** 指定領域のOCR実行

**実装ファイル:** `/src/pages/api/documents/[id]/ocr-region.ts`

```typescript
interface OCRRegionRequest {
  x: number;
  y: number;
  width: number;
  height: number;
  page_number: number;
}

interface OCRRegionResponse {
  text: string;
  confidence: number;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;
  const { x, y, width, height, page_number } = req.body;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/ocr-region`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          x: Math.round(x),
          y: Math.round(y),
          width: Math.round(width),
          height: Math.round(height),
          page_number,
        }),
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    console.error('OCR region error:', error);
    res.status(500).json({ error: 'OCR processing failed' });
  }
}
```

#### `POST /api/documents/[id]/crop-image`

**目的:** 画像領域の切り出し

```typescript
interface CropImageRequest {
  x: number;
  y: number;
  width: number;
  height: number;
  page_number: number;
}

interface CropImageResponse {
  image_data: string; // Base64
  filename: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/crop-image`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(req.body),
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Image crop failed' });
  }
}
```

#### `POST /api/documents/[id]/rag-convert`

**目的:** ドキュメントのRAG変換（ベクトル化）

```typescript
interface RAGConvertRequest {
  metadata: any; // 最新のメタデータ
}

interface RAGConvertResponse {
  status: 'success' | 'partial_success' | 'error';
  message: string;
  result?: {
    chunks_created: number;
    vectors_stored: number;
  };
  vector_error?: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    // 1. メタデータを保存
    const metadataResponse = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/metadata`,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ metadata: req.body.metadata }),
      }
    );

    if (!metadataResponse.ok) {
      throw new Error('Metadata save failed');
    }

    // 2. ベクトル処理を実行
    const vectorResponse = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/vectorize`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
      }
    );

    if (!vectorResponse.ok) {
      const vectorError = await vectorResponse.json();
      // 部分的成功（メタデータは保存されたがベクトル化失敗）
      return res.status(422).json({
        status: 'partial_success',
        message: 'メタデータは保存されましたが、ベクトル処理に失敗しました',
        vector_error: vectorError.error || 'Vector processing failed',
      });
    }

    const vectorData = await vectorResponse.json();

    res.status(200).json({
      status: 'success',
      message: 'RAG変換が完了しました',
      result: vectorData,
    });
  } catch (error: any) {
    console.error('RAG convert error:', error);
    res.status(500).json({
      status: 'error',
      message: 'RAG変換に失敗しました',
      error: error.message,
    });
  }
}
```

### ジョブステータス (`/api/jobs/*`)

#### `GET /api/jobs/[id]`

**目的:** ジョブステータス取得（ポーリング用）

```typescript
interface JobStatus {
  id: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress: number; // 0-100
  message: string;
  result?: any;
  error?: string;
  created_at: string;
  updated_at: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<JobStatus | ErrorResponse>
) {
  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(`${ADMIN_API_URL}/admin/jobs/${id}`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch job status' });
  }
}
```

#### `GET /api/admin/jobs/document/[documentId]`

**目的:** ドキュメントに関連するジョブ取得

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const { documentId } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/jobs/document/${documentId}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch document jobs' });
  }
}
```

### ダッシュボード (`/api/dashboard/*`)

#### `GET /api/dashboard/stats`

**目的:** ダッシュボード統計情報取得

**実装ファイル:** `/src/pages/api/dashboard/stats.ts`

```typescript
interface DashboardStats {
  totalUsers: number;
  activeUsers: number;
  newUsersToday: number;
  systemAlerts: number;
  servicesOnline: number;
  totalServices: number;
  userGrowthData: ChartData;
  userStatusData: ChartData;
  recentActivities: Activity[];
  lastUpdated: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<DashboardStats | ErrorResponse>
) {
  const token = req.cookies.access_token;

  try {
    // 複数のエンドポイントから並列取得
    const [usersRes, docsRes, systemRes] = await Promise.all([
      fetch(`${API_SERVER_URL}/admin/users/stats`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
      fetch(`${ADMIN_API_URL}/admin/documents/stats`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
      fetch(`${ADMIN_API_URL}/admin/system/status`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    ]);

    const [usersData, docsData, systemData] = await Promise.all([
      usersRes.json(),
      docsRes.json(),
      systemRes.json(),
    ]);

    // データを統合
    const stats: DashboardStats = {
      totalUsers: usersData.total || 0,
      activeUsers: usersData.active || 0,
      newUsersToday: usersData.new_today || 0,
      systemAlerts: systemData.alerts?.length || 0,
      servicesOnline: systemData.services_online || 0,
      totalServices: systemData.total_services || 5,
      userGrowthData: usersData.growth_chart || { labels: [], datasets: [] },
      userStatusData: usersData.status_chart || { labels: [], datasets: [] },
      recentActivities: usersData.recent_activities || [],
      lastUpdated: new Date().toISOString(),
    };

    res.status(200).json(stats);
  } catch (error) {
    console.error('Dashboard stats error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard stats' });
  }
}
```

### ナレッジベース (`/api/knowledge-bases/*`)

#### `GET /api/knowledge-bases`

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const token = req.cookies.access_token;
  const params = new URLSearchParams();
  if (req.query.limit) params.set('limit', req.query.limit as string);

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/knowledge-bases?${params.toString()}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch knowledge bases' });
  }
}
```

#### `POST /api/knowledge-bases/[id]/chat/stream`

**目的:** RAGチャットのストリーミング応答

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    // Server-Sent Events設定
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const response = await fetch(
      `${ADMIN_API_URL}/admin/knowledge-bases/${id}/chat/stream`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(req.body),
      }
    );

    // ストリームをパイプ
    if (response.body) {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value);
        res.write(chunk);
      }
    }

    res.end();
  } catch (error) {
    console.error('Chat stream error:', error);
    res.status(500).json({ error: 'Chat streaming failed' });
  }
}
```

## ファイル処理ハンドリング

### 画像プロキシ

#### `GET /api/documents/[id]/images/[imageName]`

**目的:** ドキュメント画像の配信（認証付き）

```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const { id, imageName } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/images/${imageName}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    );

    if (!response.ok) {
      return res.status(response.status).json({ error: 'Image not found' });
    }

    // Content-Typeをそのまま転送
    const contentType = response.headers.get('Content-Type') || 'image/png';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'public, max-age=86400'); // 1日キャッシュ

    // バイナリデータをパイプ
    const buffer = await response.arrayBuffer();
    res.send(Buffer.from(buffer));
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch image' });
  }
}
```

### 切り出し画像保存

#### `POST /api/documents/[id]/save-cropped-image`

```typescript
interface SaveCroppedImageRequest {
  image_data: string; // Base64
  filename: string;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id } = req.query;
  const token = req.cookies.access_token;

  try {
    const response = await fetch(
      `${ADMIN_API_URL}/admin/documents/${id}/save-cropped-image`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(req.body),
      }
    );

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to save image' });
  }
}
```

## エラーハンドリング戦略

### 統一エラーレスポンス

```typescript
interface ErrorResponse {
  error: string;
  details?: string;
  code?: string;
}

// エラーハンドラーミドルウェア
function handleAPIError(error: any, res: NextApiResponse) {
  console.error('API Error:', error);

  if (error.response) {
    // バックエンドからのエラーレスポンス
    return res.status(error.response.status).json({
      error: error.response.data.error || 'Request failed',
      details: error.response.data.details,
      code: error.response.data.code,
    });
  }

  if (error.code === 'ECONNREFUSED') {
    return res.status(503).json({
      error: 'Service unavailable',
      details: 'Backend service is not responding',
      code: 'SERVICE_UNAVAILABLE',
    });
  }

  // その他のエラー
  return res.status(500).json({
    error: 'Internal server error',
    details: error.message,
  });
}
```

### 認証エラーハンドリング

```typescript
async function withAuth(
  handler: (req: NextApiRequest, res: NextApiResponse) => Promise<void>
) {
  return async (req: NextApiRequest, res: NextApiResponse) => {
    const token = req.cookies.access_token;

    if (!token) {
      return res.status(401).json({
        error: 'Unauthorized',
        code: 'NO_TOKEN',
      });
    }

    // Tokenの有効性検証（オプション）
    try {
      const verifyResponse = await fetch(`${AUTH_SERVER_URL}/auth/verify`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (!verifyResponse.ok) {
        return res.status(401).json({
          error: 'Invalid token',
          code: 'INVALID_TOKEN',
        });
      }

      // ハンドラー実行
      await handler(req, res);
    } catch (error) {
      return res.status(500).json({
        error: 'Authentication failed',
      });
    }
  };
}

// 使用例
export default withAuth(async (req, res) => {
  // 認証済みの処理
});
```

## リトライとタイムアウト

### Fetch設定

```typescript
const fetchWithTimeout = async (
  url: string,
  options: RequestInit = {},
  timeout = 30000
): Promise<Response> => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    return response;
  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('Request timeout');
    }
    throw error;
  }
};
```

### リトライロジック

```typescript
async function fetchWithRetry(
  url: string,
  options: RequestInit = {},
  retries = 3,
  delay = 1000
): Promise<Response> {
  try {
    return await fetchWithTimeout(url, options);
  } catch (error) {
    if (retries > 0) {
      await new Promise((resolve) => setTimeout(resolve, delay));
      return fetchWithRetry(url, options, retries - 1, delay * 2);
    }
    throw error;
  }
}
```

## ジョブステータスポーリング

### フロントエンド実装

```typescript
// useJobStatus.ts
import { useState, useEffect } from 'react';

interface UseJobStatusOptions {
  jobId: string;
  interval?: number; // ミリ秒
  onComplete?: (result: any) => void;
  onError?: (error: string) => void;
}

export function useJobStatus({
  jobId,
  interval = 2000,
  onComplete,
  onError,
}: UseJobStatusOptions) {
  const [status, setStatus] = useState<JobStatus | null>(null);
  const [polling, setPolling] = useState(true);

  useEffect(() => {
    if (!polling || !jobId) return;

    const pollStatus = async () => {
      try {
        const response = await fetch(`/api/jobs/${jobId}`, {
          credentials: 'include',
        });

        if (!response.ok) {
          throw new Error('Failed to fetch job status');
        }

        const data: JobStatus = await response.json();
        setStatus(data);

        if (data.status === 'completed') {
          setPolling(false);
          onComplete?.(data.result);
        } else if (data.status === 'failed') {
          setPolling(false);
          onError?.(data.error || 'Job failed');
        }
      } catch (error: any) {
        console.error('Job polling error:', error);
        setPolling(false);
        onError?.(error.message);
      }
    };

    const timerId = setInterval(pollStatus, interval);
    pollStatus(); // 即座に1回実行

    return () => clearInterval(timerId);
  }, [jobId, polling, interval]);

  return { status, polling, stopPolling: () => setPolling(false) };
}

// 使用例
function DocumentProcessing({ documentId }: { documentId: string }) {
  const { status, polling } = useJobStatus({
    jobId: documentId,
    interval: 2000,
    onComplete: (result) => {
      console.log('Processing complete:', result);
      router.push(`/documents/ocr/${documentId}`);
    },
    onError: (error) => {
      console.error('Processing failed:', error);
      toast.error(`処理に失敗しました: ${error}`);
    },
  });

  return (
    <div>
      {polling && <div>処理中... {status?.progress}%</div>}
    </div>
  );
}
```

## まとめ

Admin FrontendのAPI統合設計により、以下を実現しています:

1. **セキュリティ:** httpOnlyクッキーによるToken管理、CSRF対策
2. **拡張性:** BFFパターンによるマイクロサービス疎結合
3. **信頼性:** エラーハンドリング、リトライ、タイムアウト処理
4. **パフォーマンス:** 並列リクエスト、キャッシング、ストリーミング
5. **保守性:** 統一されたエラーレスポンス、型定義、ログ出力

これらの設計により、安全で拡張可能なAPI統合が実現されています。