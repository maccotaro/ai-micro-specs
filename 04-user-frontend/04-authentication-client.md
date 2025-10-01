# User Frontend 認証クライアント実装

**カテゴリ**: Frontend Service
**最終更新**: 2025-09-30

## 目次
- [認証フロー概要](#認証フロー概要)
- [Cookie管理](#cookie管理)
- [トークンリフレッシュ](#トークンリフレッシュ)
- [認証状態管理](#認証状態管理)
- [保護ルート実装](#保護ルート実装)

---

## 認証フロー概要

User Frontendでは、JWT認証をhttpOnly Cookieを使用して実装しています。

### 認証フロー図

```
┌─────────────────────────────────────────────────────────────┐
│ 1. ログインフロー                                           │
└─────────────────────────────────────────────────────────────┘

Browser                  BFF                 Auth Service
  │                       │                       │
  ├─ POST /api/auth/login │                       │
  │  (email, password)    │                       │
  │                       ├─ POST /auth/login    │
  │                       │  (email, password)   ─┤
  │                       │                      ←┤ JWT tokens
  │                       │                       │ (access_token,
  │                       │                       │  refresh_token)
  │                       │                       │
  │                       ├─ Set-Cookie:         │
  │                       │   access_token=...   │
  │                       │   refresh_token=...  │
  │  ← 200 OK             │   (httpOnly, secure) │
  │    (no tokens in body)│                       │
  │                       │                       │

┌─────────────────────────────────────────────────────────────┐
│ 2. 認証済みリクエストフロー                                 │
└─────────────────────────────────────────────────────────────┘

Browser                  BFF                 User API
  │                       │                       │
  ├─ GET /api/profile     │                       │
  │  Cookie: access_token │                       │
  │                       ├─ GET /profile         │
  │                       │  Authorization:      ─┤
  │                       │  Bearer {token}      ←┤ Profile data
  │  ← Profile data       │                       │
  │                       │                       │

┌─────────────────────────────────────────────────────────────┐
│ 3. トークンリフレッシュフロー                               │
└─────────────────────────────────────────────────────────────┘

Browser                  BFF                 Auth Service
  │                       │                       │
  ├─ GET /api/profile     │                       │
  │  Cookie: access_token │                       │
  │         (expired)     │                       │
  │                       ├─ GET /profile         │
  │                       │  (expired token)     ─┤
  │                       │                      ←┤ 401 Unauthorized
  │                       │                       │
  │                       ├─ POST /auth/refresh  │
  │                       │  refresh_token       ─┤
  │                       │                      ←┤ New access_token
  │                       │                       │
  │                       ├─ Set-Cookie:         │
  │                       │   access_token=...   │
  │                       │   (new token)        │
  │                       │                       │
  │                       ├─ GET /profile (retry)│
  │                       │  (new token)         ─┤
  │  ← Profile data       │                      ←┤ Profile data
  │                       │                       │
```

### セキュリティ上の重要ポイント

1. **JWTトークンはブラウザのJavaScriptからアクセス不可**
   - httpOnly Cookie属性により保護
   - XSS攻撃からトークンを守る

2. **トークンはリクエストボディに含まれない**
   - ログインレスポンスにトークンを含めない
   - すべてCookieヘッダーで送信

3. **CSRF対策**
   - SameSite Cookie属性を使用
   - HTTPS環境ではSecure属性も有効化

---

## Cookie管理

### Cookie設定ヘルパー

**ファイル**: `src/lib/auth.ts`

```typescript
import cookie from 'cookie';
import { NextApiResponse } from 'next';

/**
 * JWTトークンをhttpOnly Cookieに設定
 */
export function setTokenCookies(
  res: NextApiResponse,
  accessToken: string,
  refreshToken: string
) {
  const isProduction = process.env.NODE_ENV === 'production';
  const accessTokenTTL = parseInt(process.env.ACCESS_TOKEN_TTL_SEC || '900'); // 15分

  res.setHeader('Set-Cookie', [
    // Access Token Cookie
    cookie.serialize(
      process.env.ACCESS_TOKEN_COOKIE_NAME || 'access_token',
      accessToken,
      {
        httpOnly: true,           // JavaScriptからアクセス不可
        secure: isProduction,     // HTTPS環境のみ送信
        sameSite: 'strict',       // CSRF対策
        maxAge: accessTokenTTL,   // 15分
        path: '/'                 // 全パスで有効
      }
    ),
    // Refresh Token Cookie
    cookie.serialize(
      process.env.REFRESH_TOKEN_COOKIE_NAME || 'refresh_token',
      refreshToken,
      {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: 604800,           // 7日
        path: '/'
      }
    )
  ]);
}

/**
 * Cookieをクリア（ログアウト時）
 */
export function clearTokenCookies(res: NextApiResponse) {
  const isProduction = process.env.NODE_ENV === 'production';

  res.setHeader('Set-Cookie', [
    cookie.serialize('access_token', '', {
      httpOnly: true,
      secure: isProduction,
      sameSite: 'strict',
      maxAge: 0,                  // 即座に削除
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
}

/**
 * リクエストからトークンを取得
 */
export function getTokensFromRequest(req: NextApiRequest) {
  const cookies = cookie.parse(req.headers.cookie || '');

  return {
    accessToken: cookies.access_token,
    refreshToken: cookies.refresh_token
  };
}
```

### Cookie属性の説明

| 属性 | 値 | 理由 |
|------|----|----|
| `httpOnly` | `true` | JavaScriptからアクセス不可（XSS対策） |
| `secure` | `true` (本番) | HTTPS通信のみで送信 |
| `sameSite` | `'strict'` | CSRF攻撃対策 |
| `maxAge` | 900秒 (access) / 604800秒 (refresh) | トークン有効期限 |
| `path` | `'/'` | 全エンドポイントで有効 |

---

## トークンリフレッシュ

### 自動リフレッシュ実装

**ファイル**: `src/lib/fetcher.ts`

```typescript
/**
 * 認証付きAPIリクエストヘルパー
 * アクセストークン期限切れ時、自動的にリフレッシュを試行
 */
export async function authenticatedFetch(
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  // 初回リクエスト
  let response = await fetch(url, {
    ...options,
    credentials: 'include' // Cookie送信を有効化
  });

  // 401エラーの場合、トークンリフレッシュを試行
  if (response.status === 401) {
    console.log('Access token expired, attempting refresh...');

    const refreshResponse = await fetch('/api/auth/refresh', {
      method: 'POST',
      credentials: 'include'
    });

    if (refreshResponse.ok) {
      console.log('Token refreshed successfully, retrying request...');

      // リトライ
      response = await fetch(url, {
        ...options,
        credentials: 'include'
      });
    } else {
      console.error('Token refresh failed, redirecting to login...');
      // リフレッシュ失敗、ログインページへリダイレクト
      if (typeof window !== 'undefined') {
        window.location.href = '/login';
      }
      throw new Error('Authentication failed');
    }
  }

  return response;
}

/**
 * 使用例
 */
export async function getProfile() {
  const response = await authenticatedFetch('/api/profile');

  if (!response.ok) {
    throw new Error('Failed to fetch profile');
  }

  return response.json();
}

export async function updateProfile(data: ProfileUpdateData) {
  const response = await authenticatedFetch('/api/profile', {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data)
  });

  if (!response.ok) {
    throw new Error('Failed to update profile');
  }

  return response.json();
}
```

### BFF層でのリフレッシュ処理

**ファイル**: `src/pages/api/auth/refresh.ts`

```typescript
import { NextApiRequest, NextApiResponse } from 'next';
import cookie from 'cookie';

const AUTH_SERVER_URL = process.env.AUTH_SERVER_URL;

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Cookieからリフレッシュトークンを取得
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
      console.error('Token refresh failed:', response.status);
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    const data = await response.json();

    // 新しいアクセストークンをCookieに設定
    const isProduction = process.env.NODE_ENV === 'production';
    const accessTokenTTL = parseInt(process.env.ACCESS_TOKEN_TTL_SEC || '900');

    res.setHeader('Set-Cookie', [
      cookie.serialize('access_token', data.access_token, {
        httpOnly: true,
        secure: isProduction,
        sameSite: 'strict',
        maxAge: accessTokenTTL,
        path: '/'
      })
    ]);

    return res.status(200).json({ message: 'Token refreshed successfully' });
  } catch (error) {
    console.error('Token refresh error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
```

---

## 認証状態管理

### React Hookを使った認証状態管理

**ファイル**: `src/hooks/useAuth.ts`

```typescript
import { useState, useEffect } from 'react';
import { useRouter } from 'next/router';

interface User {
  email: string;
  id?: string;
}

export function useAuth() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    checkAuthStatus();
  }, []);

  /**
   * 認証状態確認
   */
  const checkAuthStatus = async () => {
    try {
      const response = await fetch('/api/profile');

      if (response.ok) {
        const profile = await response.json();
        setUser({ email: profile.email, id: profile.id });
      } else if (response.status === 401) {
        // 未認証
        setUser(null);
      } else {
        throw new Error('Failed to check auth status');
      }
    } catch (err) {
      console.error('Auth check error:', err);
      setError('Failed to check authentication status');
      setUser(null);
    } finally {
      setLoading(false);
    }
  };

  /**
   * ログイン
   */
  const login = async (email: string, password: string) => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });

      if (response.ok) {
        const data = await response.json();
        setUser(data.user);
        return true;
      } else {
        const data = await response.json();
        setError(data.error || 'Login failed');
        return false;
      }
    } catch (err) {
      console.error('Login error:', err);
      setError('An error occurred during login');
      return false;
    } finally {
      setLoading(false);
    }
  };

  /**
   * ログアウト
   */
  const logout = async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
      setUser(null);
      router.push('/login');
    } catch (err) {
      console.error('Logout error:', err);
      // エラーでもログアウト処理を続行
      setUser(null);
      router.push('/login');
    }
  };

  return {
    user,
    loading,
    error,
    isAuthenticated: !!user,
    login,
    logout,
    checkAuthStatus
  };
}
```

### 使用例

```typescript
import { useAuth } from '@/hooks/useAuth';

export default function ProfilePage() {
  const { user, loading, isAuthenticated, logout } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !isAuthenticated) {
      // 未認証の場合、ログインページへリダイレクト
      router.push('/login');
    }
  }, [loading, isAuthenticated, router]);

  if (loading) {
    return <div>Loading...</div>;
  }

  if (!isAuthenticated) {
    return null; // リダイレクト中
  }

  return (
    <div>
      <h1>Profile</h1>
      <p>Email: {user?.email}</p>
      <button onClick={logout}>Logout</button>
    </div>
  );
}
```

---

## 保護ルート実装

### Higher-Order Component (HOC) による保護

**ファイル**: `src/components/ProtectedRoute.tsx`

```typescript
import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { useAuth } from '@/hooks/useAuth';

export function withAuth<P extends object>(
  Component: React.ComponentType<P>
) {
  return function ProtectedRoute(props: P) {
    const router = useRouter();
    const { isAuthenticated, loading } = useAuth();

    useEffect(() => {
      if (!loading && !isAuthenticated) {
        // ログインページへリダイレクト
        router.push('/login');
      }
    }, [loading, isAuthenticated, router]);

    // ローディング中
    if (loading) {
      return (
        <div className="min-h-screen flex items-center justify-center">
          <div className="text-lg">Loading...</div>
        </div>
      );
    }

    // 未認証
    if (!isAuthenticated) {
      return null; // リダイレクト中
    }

    // 認証済み、コンポーネントを表示
    return <Component {...props} />;
  };
}
```

### 使用例

```typescript
import { withAuth } from '@/components/ProtectedRoute';

function ProfileView() {
  return (
    <div>
      <h1>Profile</h1>
      {/* プロファイル内容 */}
    </div>
  );
}

// HOCでラップして保護ルートに
export default withAuth(ProfileView);
```

### ミドルウェアによる保護（Next.js 13+）

**ファイル**: `src/middleware.ts`

```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// 保護対象のパス
const protectedPaths = ['/profile', '/rag'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // 保護対象パスかチェック
  const isProtectedPath = protectedPaths.some(path =>
    pathname.startsWith(path)
  );

  if (!isProtectedPath) {
    return NextResponse.next();
  }

  // アクセストークンの存在確認
  const accessToken = request.cookies.get('access_token');

  if (!accessToken) {
    // トークンがない場合、ログインページへリダイレクト
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('redirect', pathname);
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/profile/:path*', '/rag/:path*']
};
```

---

## セキュリティベストプラクティス

### 1. トークン保存

✅ **推奨**: httpOnly Cookie
```typescript
res.setHeader('Set-Cookie', [
  cookie.serialize('access_token', token, {
    httpOnly: true,  // JavaScriptからアクセス不可
    secure: true,    // HTTPS必須
    sameSite: 'strict'
  })
]);
```

❌ **非推奨**: localStorage / sessionStorage
```typescript
// XSS攻撃に脆弱
localStorage.setItem('access_token', token);
```

### 2. トークン送信

✅ **推奨**: Cookie（自動送信）
```typescript
fetch('/api/profile', {
  credentials: 'include' // Cookie送信を有効化
});
```

❌ **非推奨**: Authorizationヘッダー（フロントエンドから）
```typescript
// フロントエンドJavaScriptでトークンを扱うのは危険
fetch('/api/profile', {
  headers: {
    'Authorization': `Bearer ${token}` // 避けるべき
  }
});
```

### 3. エラーハンドリング

```typescript
// トークン期限切れの適切な処理
if (response.status === 401) {
  // リフレッシュを試行
  const refreshed = await refreshToken();

  if (refreshed) {
    // リトライ
    return fetch(url);
  } else {
    // ログインページへ
    router.push('/login');
  }
}
```

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [API統合](./03-api-integration.md)
- [Auth Service JWT実装](/01-auth-service/03-jwt-implementation.md)
- [セキュリティベストプラクティス](/08-integration/03-security-practices.md)