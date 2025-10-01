# User Frontend API統合

**カテゴリ**: Frontend Service (BFF Pattern)
**最終更新**: 2025-09-30

## 目次
- [BFF層の役割](#bff層の役割)
- [認証API](#認証api)
- [プロファイルAPI](#プロファイルapi)
- [RAG API](#rag-api)
- [エラーハンドリング](#エラーハンドリング)
- [リクエスト例](#リクエスト例)

---

## BFF層の役割

User FrontendのBFF（Backend for Frontend）層は、Next.js API Routesを使用して実装されています。

### BFFの責務

1. **リクエストプロキシ**
   - フロントエンドからのリクエストをバックエンドサービスに転送
   - 複数のバックエンドサービスへのルーティング

2. **認証処理**
   - JWTトークンのhttpOnly Cookie管理
   - Authorizationヘッダーの付与
   - トークンリフレッシュ処理

3. **レスポンス変換**
   - バックエンドレスポンスのフロントエンド向け変換
   - エラーレスポンスの統一化

4. **セキュリティ**
   - Cookieの安全な設定
   - CORS処理
   - セキュリティヘッダー付与

### アーキテクチャ図

```
Browser                   BFF Layer                 Backend Services
  │                         │                            │
  ├─ POST /login           │                            │
  │  (email, password)     │                            │
  │                        ├─ POST /auth/login         │
  │                        │  (email, password)        ─┤→ Auth Service
  │                        │                           ←┤  (JWT tokens)
  │                        │                            │
  │                        ├─ Set httpOnly Cookies     │
  │  ← Login success       │                            │
  │     (no tokens)        │                            │
  │                        │                            │
  ├─ GET /profile          │                            │
  │  (Cookie: tokens)      │                            │
  │                        ├─ GET /profile              │
  │                        │  (Authorization: Bearer)  ─┤→ User API
  │                        │                           ←┤  (profile data)
  │  ← Profile data        │                            │
  │                        │                            │
```

---

## 認証API

### 1. ログイン (POST /api/auth/login)

**ファイル**: `src/pages/api/auth/login.ts`

**リクエスト**:
```typescript
POST /api/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "password123"
}
```

**レスポンス**:
```typescript
// 成功時
{
  "message": "Login successful",
  "user": {
    "email": "user@example.com"
  }
}
// + httpOnly Cookies: access_token, refresh_token

// 失敗時 (401)
{
  "error": "Invalid credentials"
}
```

**実装**:
```typescript
import { NextApiRequest, NextApiResponse } from 'next';
import { proxyRequestToAuth, handleProxyResponse } from '@/lib/fetcher';
import { setTokenCookies } from '@/lib/auth';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Auth Serviceにリクエストをプロキシ
    const response = await proxyRequestToAuth(req, '/auth/login');
    const { data, status } = await handleProxyResponse(response);

    // ログイン成功時、トークンをCookieに保存
    if (status === 200 && data.access_token && data.refresh_token) {
      setTokenCookies(res, data.access_token, data.refresh_token);

      return res.status(200).json({
        message: 'Login successful',
        user: data.user || { email: data.email }
      });
    }

    return res.status(status).json(data);
  } catch (error) {
    console.error('Login proxy error:', error);
    return res.status(500).json({
      error: 'Internal server error',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
```

**ヘルパー関数**: `lib/auth.ts`
```typescript
import cookie from 'cookie';
import { NextApiResponse } from 'next';

export function setTokenCookies(
  res: NextApiResponse,
  accessToken: string,
  refreshToken: string
) {
  const isProduction = process.env.NODE_ENV === 'production';
  const accessTokenTTL = parseInt(process.env.ACCESS_TOKEN_TTL_SEC || '900');

  res.setHeader('Set-Cookie', [
    cookie.serialize(
      process.env.ACCESS_TOKEN_COOKIE_NAME || 'access_token',
      accessToken,
      {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: accessTokenTTL,
        path: '/'
      }
    ),
    cookie.serialize(
      process.env.REFRESH_TOKEN_COOKIE_NAME || 'refresh_token',
      refreshToken,
      {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: 604800, // 7日
        path: '/'
      }
    )
  ]);
}
```

### 2. サインアップ (POST /api/auth/signup)

**ファイル**: `src/pages/api/auth/signup.ts`

**リクエスト**:
```typescript
POST /api/auth/signup
Content-Type: application/json

{
  "email": "newuser@example.com",
  "password": "securepass123"
}
```

**レスポンス**:
```typescript
// 成功時 (201)
{
  "message": "User registered successfully",
  "user": {
    "email": "newuser@example.com"
  }
}
// + httpOnly Cookies: access_token, refresh_token

// 失敗時 (400)
{
  "error": "Email already exists"
}
```

**実装**:
```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const response = await proxyRequestToAuth(req, '/auth/signup');
    const { data, status } = await handleProxyResponse(response);

    // サインアップ成功時、トークンをCookieに保存
    if ((status === 200 || status === 201) && data.access_token && data.refresh_token) {
      setTokenCookies(res, data.access_token, data.refresh_token);

      return res.status(201).json({
        message: 'User registered successfully',
        user: data.user || { email: data.email }
      });
    }

    return res.status(status).json(data);
  } catch (error) {
    console.error('Signup proxy error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

### 3. ログアウト (POST /api/auth/logout)

**ファイル**: `src/pages/api/auth/logout.ts`

**リクエスト**:
```typescript
POST /api/auth/logout
Cookie: access_token=...; refresh_token=...
```

**レスポンス**:
```typescript
// 成功時 (200)
{
  "message": "Logged out successfully"
}
// + Cookieクリア
```

**実装**:
```typescript
import cookie from 'cookie';
import { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const isProduction = process.env.NODE_ENV === 'production';

    // Cookieをクリア
    res.setHeader('Set-Cookie', [
      cookie.serialize('access_token', '', {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: 0,
        path: '/'
      }),
      cookie.serialize('refresh_token', '', {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: 0,
        path: '/'
      })
    ]);

    return res.status(200).json({ message: 'Logged out successfully' });
  } catch (error) {
    console.error('Logout error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

### 4. トークンリフレッシュ (POST /api/auth/refresh)

**ファイル**: `src/pages/api/auth/refresh.ts`

**リクエスト**:
```typescript
POST /api/auth/refresh
Cookie: refresh_token=...
```

**レスポンス**:
```typescript
// 成功時 (200)
{
  "message": "Token refreshed"
}
// + 新しいaccess_token Cookie

// 失敗時 (401)
{
  "error": "Invalid refresh token"
}
```

**実装**:
```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const cookies = cookie.parse(req.headers.cookie || '');
    const refreshToken = cookies.refresh_token;

    if (!refreshToken) {
      return res.status(401).json({ error: 'No refresh token' });
    }

    // Auth Serviceにリフレッシュリクエスト
    const response = await fetch(`${AUTH_SERVER_URL}/auth/refresh`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${refreshToken}`
      }
    });

    if (!response.ok) {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    const data = await response.json();

    // 新しいaccess_tokenをCookieに設定
    const isProduction = process.env.NODE_ENV === 'production';
    res.setHeader('Set-Cookie', [
      cookie.serialize('access_token', data.access_token, {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: 900,
        path: '/'
      })
    ]);

    return res.status(200).json({ message: 'Token refreshed' });
  } catch (error) {
    console.error('Token refresh error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

---

## プロファイルAPI

### 1. プロファイル取得 (GET /api/profile)

**ファイル**: `src/pages/api/profile/index.ts`

**リクエスト**:
```typescript
GET /api/profile
Cookie: access_token=...
```

**レスポンス**:
```typescript
// 成功時 (200)
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "first_name": "John",
  "last_name": "Doe",
  "phone": "+81-90-1234-5678",
  "created_at": "2025-01-15T10:00:00Z",
  "updated_at": "2025-09-30T15:30:00Z"
}

// 認証エラー (401)
{
  "error": "Unauthorized"
}
```

### 2. プロファイル作成/更新 (POST /api/profile)

**リクエスト**:
```typescript
POST /api/profile
Cookie: access_token=...
Content-Type: application/json

{
  "first_name": "Jane",
  "last_name": "Smith",
  "phone": "+81-80-9876-5432"
}
```

**レスポンス**:
```typescript
// 成功時 (200)
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "first_name": "Jane",
  "last_name": "Smith",
  "phone": "+81-80-9876-5432",
  "updated_at": "2025-09-30T16:00:00Z"
}
```

### 3. プロファイル更新 (PUT /api/profile)

**実装例**:
```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // GET, POST, PUT メソッドをサポート
  if (!['GET', 'POST', 'PUT'].includes(req.method || '')) {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const cookies = cookie.parse(req.headers.cookie || '');
    const accessToken = cookies.access_token;

    if (!accessToken) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // User API Serviceにプロキシ
    const response = await fetch(`${API_SERVER_URL}/profile`, {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`
      },
      ...(req.method !== 'GET' && { body: JSON.stringify(req.body) })
    });

    const data = await response.json();
    return res.status(response.status).json(data);
  } catch (error) {
    console.error('Profile API error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

---

## RAG API

### 1. ドキュメント検索 (POST /api/rag/search)

**ファイル**: `src/pages/api/rag/search.ts`

**リクエスト**:
```typescript
POST /api/rag/search
Cookie: access_token=...
Content-Type: application/json

{
  "query": "What is the main topic?",
  "knowledge_base_id": "kb-123",
  "top_k": 5
}
```

**レスポンス**:
```typescript
{
  "results": [
    {
      "chunk_id": "chunk-456",
      "document_id": "doc-789",
      "document_name": "report.pdf",
      "page_number": 5,
      "chunk_text": "The main topic is...",
      "score": 0.95
    }
  ]
}
```

### 2. ストリーミングチャット (POST /api/rag/query-stream)

**ファイル**: `src/pages/api/rag/query-stream.ts`

**リクエスト**:
```typescript
POST /api/rag/query-stream
Cookie: access_token=...
Content-Type: application/json

{
  "query": "Explain the process",
  "knowledge_base_id": "kb-123",
  "stream": true
}
```

**レスポンス**: Server-Sent Events (SSE)
```typescript
data: {"type":"chunk","content":"The"}
data: {"type":"chunk","content":" process"}
data: {"type":"chunk","content":" involves..."}
data: {"type":"sources","documents":[{"id":"doc-1","name":"guide.pdf"}]}
data: {"type":"done"}
```

**実装**:
```typescript
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const cookies = cookie.parse(req.headers.cookie || '');
    const accessToken = cookies.access_token;

    if (!accessToken) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Admin API Serviceにストリーミングリクエスト
    const response = await fetch(`${ADMIN_API_URL}/rag/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`
      },
      body: JSON.stringify({ ...req.body, stream: true })
    });

    if (!response.ok) {
      const error = await response.json();
      return res.status(response.status).json(error);
    }

    // SSEレスポンスヘッダー設定
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    // ストリームをクライアントに転送
    const reader = response.body?.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader!.read();
      if (done) break;

      const chunk = decoder.decode(value);
      res.write(chunk);
    }

    res.end();
  } catch (error) {
    console.error('RAG query stream error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

### 3. ドキュメント一覧 (GET /api/rag/documents)

**リクエスト**:
```typescript
GET /api/rag/documents?knowledge_base_id=kb-123&page=1&limit=20
Cookie: access_token=...
```

**レスポンス**:
```typescript
{
  "documents": [
    {
      "id": "doc-1",
      "name": "report.pdf",
      "type": "application/pdf",
      "size": 1024000,
      "status": "processed",
      "uploaded_at": "2025-09-30T10:00:00Z"
    }
  ],
  "total": 50,
  "page": 1,
  "limit": 20
}
```

### 4. ドキュメントアップロード (POST /api/rag/upload)

**ファイル**: `src/pages/api/rag/upload.ts`

**リクエスト**: `multipart/form-data`
```typescript
POST /api/rag/upload
Cookie: access_token=...
Content-Type: multipart/form-data

file: [binary data]
knowledge_base_id: kb-123
```

**レスポンス**:
```typescript
{
  "message": "File uploaded successfully",
  "document_id": "doc-new-123",
  "status": "uploaded"
}
```

**実装（formidableを使用）**:
```typescript
import formidable from 'formidable';
import fs from 'fs';

export const config = {
  api: {
    bodyParser: false // formidableを使用するため無効化
  }
};

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const cookies = cookie.parse(req.headers.cookie || '');
    const accessToken = cookies.access_token;

    if (!accessToken) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // formidableでファイルをパース
    const form = formidable({});
    const [fields, files] = await form.parse(req);

    const file = files.file?.[0];
    if (!file) {
      return res.status(400).json({ error: 'No file provided' });
    }

    // FormDataを作成してAdmin APIに送信
    const formData = new FormData();
    formData.append('file', fs.createReadStream(file.filepath));
    formData.append('knowledge_base_id', fields.knowledge_base_id?.[0] || '');

    const response = await fetch(`${ADMIN_API_URL}/rag/upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`
      },
      body: formData
    });

    const data = await response.json();
    return res.status(response.status).json(data);
  } catch (error) {
    console.error('Upload error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

---

## エラーハンドリング

### 共通エラーレスポンス

```typescript
interface ErrorResponse {
  error: string;
  details?: string;
  code?: string;
}
```

### エラーステータスコード

| コード | 意味 | 対処 |
|-------|------|------|
| 400 | Bad Request | リクエストパラメータを確認 |
| 401 | Unauthorized | ログインが必要、またはトークン期限切れ |
| 403 | Forbidden | 権限不足 |
| 404 | Not Found | リソースが存在しない |
| 405 | Method Not Allowed | HTTPメソッドが不正 |
| 500 | Internal Server Error | サーバーエラー |
| 503 | Service Unavailable | バックエンドサービスが利用不可 |

### エラーハンドリング実装

```typescript
// lib/fetcher.ts
export async function handleProxyResponse(response: Response) {
  const contentType = response.headers.get('content-type');

  if (contentType?.includes('application/json')) {
    const data = await response.json();
    return { data, status: response.status };
  }

  const text = await response.text();
  return {
    data: { error: text || 'Unknown error' },
    status: response.status
  };
}

// エラーハンドリングの使用例
try {
  const response = await fetch('/api/profile');

  if (response.status === 401) {
    // トークン期限切れ、リフレッシュを試行
    const refreshResponse = await fetch('/api/auth/refresh', { method: 'POST' });

    if (refreshResponse.ok) {
      // リトライ
      return fetch('/api/profile');
    } else {
      // ログインページへリダイレクト
      router.push('/login');
    }
  }

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Request failed');
  }

  const data = await response.json();
  return data;
} catch (error) {
  console.error('API error:', error);
  throw error;
}
```

---

## リクエスト例

### フロントエンドからのAPI呼び出し

```typescript
// pages/profile/view.tsx
import { useEffect, useState } from 'react';

export default function ProfileView() {
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchProfile();
  }, []);

  const fetchProfile = async () => {
    try {
      const response = await fetch('/api/profile');

      if (response.status === 401) {
        // 認証エラー、ログインページへ
        router.push('/login');
        return;
      }

      if (!response.ok) {
        throw new Error('Failed to fetch profile');
      }

      const data = await response.json();
      setProfile(data);
    } catch (error) {
      setError('An error occurred');
      console.error('Profile fetch error:', error);
    }
  };

  return (
    <div>
      {error && <div className="error">{error}</div>}
      {profile && <ProfileDisplay profile={profile} />}
    </div>
  );
}
```

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [認証クライアント実装](./04-authentication-client.md)
- [Auth Service API仕様](/01-auth-service/02-api-specification.md)
- [User API Service API仕様](/02-user-api/02-api-specification.md)