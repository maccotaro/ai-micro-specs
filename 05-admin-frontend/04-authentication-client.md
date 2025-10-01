# 04-authentication-client.md - 管理者認証クライアント設計

## 概要

Admin Frontendは、管理者専用の認証・認可システムを実装しています。JWT tokenベースの認証、ロールベースアクセス制御(RBAC)、httpOnlyクッキーによるセキュアなtoken管理を特徴としています。

## 認証フロー

### ログインフロー

```
┌─────────────┐
│ ログイン画面│
│  /login     │
└──────┬──────┘
       │ メール+パスワード送信
       ↓
┌──────────────────────────────────┐
│ POST /api/auth/login             │
│ ┌──────────────────────────────┐│
│ │ 1. Auth Serviceへプロキシ    ││
│ │ 2. JWT token受信             ││
│ │ 3. httpOnlyクッキーに保存    ││
│ │ 4. ユーザー情報返却          ││
│ └──────────────────────────────┘│
└──────┬───────────────────────────┘
       │ 認証成功
       ↓
┌──────────────┐
│ ダッシュボード│
│  /dashboard  │
└──────────────┘
```

### Token管理

```typescript
// JWT Token構造
interface JWTPayload {
  sub: string;        // ユーザーID (UUID)
  email: string;      // メールアドレス
  role: string;       // ロール (admin, super_admin, user)
  iat: number;        // 発行時刻
  exp: number;        // 有効期限
  iss: string;        // 発行者 (Auth Service)
  aud: string;        // 対象 (Admin Frontend)
}

// クッキー設定
const cookieOptions = {
  httpOnly: true,                           // JavaScriptからアクセス不可
  secure: process.env.NODE_ENV === 'production', // HTTPS必須（本番のみ）
  sameSite: 'strict' as const,              // CSRF対策
  path: '/',                                // 全パスで有効
  maxAge: 3600,                             // 1時間（access_token）
  // maxAge: 86400 * 7,                     // 7日（refresh_token）
};
```

## useAuth Hook実装

### 基本構造

**ファイル:** `/src/hooks/useAuth.tsx`

```typescript
import { useState, useEffect, useCallback, createContext, useContext } from 'react';
import { useRouter } from 'next/router';

interface User {
  id: string;
  email: string;
  role: string;
  first_name?: string;
  last_name?: string;
}

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  error: string | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  hasRole: (role: string | string[]) => boolean;
  isAdmin: boolean;
  isSuperAdmin: boolean;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  // ユーザー情報取得
  const fetchUser = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const response = await fetch('/api/auth/me', {
        credentials: 'include',
      });

      if (response.ok) {
        const data = await response.json();
        setUser(data.user);
      } else if (response.status === 401) {
        // 未認証
        setUser(null);
      } else {
        throw new Error('Failed to fetch user');
      }
    } catch (err: any) {
      console.error('Auth fetch error:', err);
      setError(err.message);
      setUser(null);
    } finally {
      setLoading(false);
    }
  }, []);

  // 初回マウント時にユーザー情報取得
  useEffect(() => {
    fetchUser();
  }, [fetchUser]);

  // ログイン処理
  const login = useCallback(
    async (email: string, password: string) => {
      try {
        setError(null);

        const response = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ email, password }),
        });

        if (!response.ok) {
          const data = await response.json();
          throw new Error(data.error || 'Login failed');
        }

        const data = await response.json();
        setUser(data.user);

        // ダッシュボードへリダイレクト
        router.push('/dashboard');
      } catch (err: any) {
        console.error('Login error:', err);
        setError(err.message);
        throw err;
      }
    },
    [router]
  );

  // ログアウト処理
  const logout = useCallback(async () => {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'include',
      });
    } catch (err) {
      console.error('Logout error:', err);
    } finally {
      setUser(null);
      router.push('/login');
    }
  }, [router]);

  // ロールチェック
  const hasRole = useCallback(
    (role: string | string[]) => {
      if (!user) return false;

      const roles = Array.isArray(role) ? role : [role];
      return roles.includes(user.role);
    },
    [user]
  );

  // 便利なロールフラグ
  const isAdmin = user?.role === 'admin' || user?.role === 'super_admin';
  const isSuperAdmin = user?.role === 'super_admin';

  const value: AuthContextValue = {
    user,
    loading,
    error,
    login,
    logout,
    hasRole,
    isAdmin,
    isSuperAdmin,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// Hook
export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
```

### _app.tsx での使用

```typescript
// src/pages/_app.tsx
import type { AppProps } from 'next/app';
import { AuthProvider } from '@/hooks/useAuth';
import '@/styles/globals.css';

export default function App({ Component, pageProps }: AppProps) {
  return (
    <AuthProvider>
      <Component {...pageProps} />
    </AuthProvider>
  );
}
```

## ログイン画面実装

### ログインページ

**ファイル:** `/src/pages/login.tsx`

```typescript
import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';

export default function LoginPage() {
  const { user, login, loading: authLoading } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // 既にログイン済みの場合はダッシュボードへ
  useEffect(() => {
    if (!authLoading && user) {
      router.push('/dashboard');
    }
  }, [authLoading, user, router]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await login(email, password);
      // ログイン成功時はuseAuthのlogin内でリダイレクト
    } catch (err: any) {
      setError(err.message || 'ログインに失敗しました');
    } finally {
      setLoading(false);
    }
  };

  // ローディング中
  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div>読み込み中...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
        <div>
          <h2 className="text-center text-3xl font-bold text-gray-900">
            管理者ログイン
          </h2>
          <p className="mt-2 text-center text-sm text-gray-600">
            Admin Portal
          </p>
        </div>

        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          <div className="space-y-4">
            <div>
              <Label htmlFor="email">メールアドレス</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                placeholder="admin@example.com"
                disabled={loading}
              />
            </div>

            <div>
              <Label htmlFor="password">パスワード</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                placeholder="••••••••"
                disabled={loading}
              />
            </div>
          </div>

          <Button
            type="submit"
            className="w-full"
            disabled={loading}
          >
            {loading ? 'ログイン中...' : 'ログイン'}
          </Button>
        </form>

        <div className="text-center text-sm text-gray-600">
          <p>パスワードを忘れた場合は管理者にお問い合わせください</p>
        </div>
      </div>
    </div>
  );
}
```

## 保護されたルート (Protected Routes)

### withAuth Higher-Order Component

```typescript
// src/lib/withAuth.tsx
import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { useAuth } from '@/hooks/useAuth';

interface WithAuthOptions {
  requireRoles?: string[];
  redirectTo?: string;
}

export function withAuth<P extends object>(
  Component: React.ComponentType<P>,
  options: WithAuthOptions = {}
) {
  return function ProtectedRoute(props: P) {
    const { user, loading } = useAuth();
    const router = useRouter();
    const { requireRoles = [], redirectTo = '/login' } = options;

    useEffect(() => {
      if (!loading) {
        if (!user) {
          // 未認証の場合はログインページへ
          router.push(redirectTo);
        } else if (requireRoles.length > 0) {
          // ロールチェック
          const hasRequiredRole = requireRoles.includes(user.role);
          if (!hasRequiredRole) {
            // 権限不足の場合は403ページへ
            router.push('/403');
          }
        }
      }
    }, [user, loading, router]);

    // ローディング中
    if (loading) {
      return (
        <div className="min-h-screen flex items-center justify-center">
          <div>読み込み中...</div>
        </div>
      );
    }

    // 未認証または権限不足
    if (!user || (requireRoles.length > 0 && !requireRoles.includes(user.role))) {
      return null;
    }

    // 認証・認可OK
    return <Component {...props} />;
  };
}

// 使用例
export default withAuth(DashboardPage, {
  requireRoles: ['admin', 'super_admin'],
});
```

### ページレベルでの保護

```typescript
// src/pages/users/index.tsx
import { withAuth } from '@/lib/withAuth';
import { Layout } from '@/components/Layout/Layout';

function UsersPage() {
  return (
    <Layout>
      <h1>ユーザー管理</h1>
      {/* ... */}
    </Layout>
  );
}

// super_adminのみアクセス可能
export default withAuth(UsersPage, {
  requireRoles: ['super_admin'],
});
```

### Layout内での保護

```typescript
// src/components/Layout/Layout.tsx
import { useAuth } from '@/hooks/useAuth';
import { useRouter } from 'next/router';
import { useEffect } from 'react';

export function Layout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    // 公開ページを除いて認証チェック
    const publicPages = ['/login', '/404', '/403'];
    const isPublicPage = publicPages.includes(router.pathname);

    if (!loading && !user && !isPublicPage) {
      router.push('/login');
    }
  }, [user, loading, router]);

  if (loading) {
    return <div>読み込み中...</div>;
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header, Sidebar, Content */}
      {children}
    </div>
  );
}
```

## ロールベースアクセス制御 (RBAC)

### ロール定義

```typescript
// src/types/auth.ts
export type Role = 'user' | 'admin' | 'super_admin';

export interface RolePermissions {
  role: Role;
  permissions: string[];
  description: string;
}

export const rolePermissions: RolePermissions[] = [
  {
    role: 'user',
    permissions: ['read:own_profile', 'update:own_profile'],
    description: '一般ユーザー',
  },
  {
    role: 'admin',
    permissions: [
      'read:users',
      'read:documents',
      'create:documents',
      'update:documents',
      'delete:documents',
      'read:knowledge_bases',
      'create:knowledge_bases',
      'update:knowledge_bases',
      'read:logs',
    ],
    description: '管理者（ドキュメント管理権限）',
  },
  {
    role: 'super_admin',
    permissions: [
      'read:users',
      'create:users',
      'update:users',
      'delete:users',
      'read:documents',
      'create:documents',
      'update:documents',
      'delete:documents',
      'read:knowledge_bases',
      'create:knowledge_bases',
      'update:knowledge_bases',
      'delete:knowledge_bases',
      'read:logs',
      'read:system_settings',
      'update:system_settings',
    ],
    description: 'スーパー管理者（全権限）',
  },
];
```

### 権限チェックHook

```typescript
// src/hooks/usePermission.ts
import { useMemo } from 'react';
import { useAuth } from './useAuth';
import { rolePermissions } from '@/types/auth';

export function usePermission() {
  const { user } = useAuth();

  const permissions = useMemo(() => {
    if (!user) return [];

    const roleConfig = rolePermissions.find((rp) => rp.role === user.role);
    return roleConfig?.permissions || [];
  }, [user]);

  const hasPermission = (permission: string): boolean => {
    return permissions.includes(permission);
  };

  const hasAnyPermission = (perms: string[]): boolean => {
    return perms.some((p) => permissions.includes(p));
  };

  const hasAllPermissions = (perms: string[]): boolean => {
    return perms.every((p) => permissions.includes(p));
  };

  return {
    permissions,
    hasPermission,
    hasAnyPermission,
    hasAllPermissions,
  };
}

// 使用例
function UserManagementPage() {
  const { hasPermission } = usePermission();

  return (
    <div>
      {hasPermission('delete:users') && (
        <Button onClick={handleDelete}>削除</Button>
      )}
    </div>
  );
}
```

### 条件付きレンダリングコンポーネント

```typescript
// src/components/auth/Can.tsx
import { usePermission } from '@/hooks/usePermission';

interface CanProps {
  permission: string;
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

export function Can({ permission, children, fallback = null }: CanProps) {
  const { hasPermission } = usePermission();

  if (hasPermission(permission)) {
    return <>{children}</>;
  }

  return <>{fallback}</>;
}

// 使用例
import { Can } from '@/components/auth/Can';

function DocumentList() {
  return (
    <div>
      <Can permission="delete:documents">
        <Button variant="destructive">削除</Button>
      </Can>

      <Can
        permission="create:documents"
        fallback={<p>ドキュメント作成権限がありません</p>}
      >
        <Button>新規作成</Button>
      </Can>
    </div>
  );
}
```

## Token更新 (Refresh Token)

### 自動更新ロジック

```typescript
// src/lib/auth.ts
export async function refreshAccessToken(): Promise<boolean> {
  try {
    const response = await fetch('/api/auth/refresh', {
      method: 'POST',
      credentials: 'include',
    });

    if (response.ok) {
      return true;
    }

    return false;
  } catch (error) {
    console.error('Token refresh failed:', error);
    return false;
  }
}

// Axios interceptorでの実装例
import axios from 'axios';

let isRefreshing = false;
let failedQueue: any[] = [];

const processQueue = (error: any, token: string | null = null) => {
  failedQueue.forEach((prom) => {
    if (error) {
      prom.reject(error);
    } else {
      prom.resolve(token);
    }
  });

  failedQueue = [];
};

axios.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    if (error.response?.status === 401 && !originalRequest._retry) {
      if (isRefreshing) {
        // Tokenリフレッシュ中は待機
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        })
          .then(() => {
            return axios(originalRequest);
          })
          .catch((err) => {
            return Promise.reject(err);
          });
      }

      originalRequest._retry = true;
      isRefreshing = true;

      try {
        const success = await refreshAccessToken();

        if (success) {
          processQueue(null);
          return axios(originalRequest);
        } else {
          processQueue(new Error('Token refresh failed'), null);
          // ログインページへリダイレクト
          window.location.href = '/login';
          return Promise.reject(error);
        }
      } catch (refreshError) {
        processQueue(refreshError, null);
        window.location.href = '/login';
        return Promise.reject(refreshError);
      } finally {
        isRefreshing = false;
      }
    }

    return Promise.reject(error);
  }
);
```

### API Routes実装

```typescript
// src/pages/api/auth/refresh.ts
import { NextApiRequest, NextApiResponse } from 'next';
import cookie from 'cookie';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const refreshToken = req.cookies.refresh_token;

  if (!refreshToken) {
    return res.status(401).json({ error: 'No refresh token' });
  }

  try {
    // Auth Serviceでrefresh tokenを検証
    const response = await fetch(`${AUTH_SERVER_URL}/auth/refresh`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });

    if (!response.ok) {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    const data = await response.json();

    // 新しいaccess tokenをクッキーに保存
    res.setHeader(
      'Set-Cookie',
      cookie.serialize('access_token', data.access_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        maxAge: 3600,
        sameSite: 'strict',
        path: '/',
      })
    );

    res.status(200).json({ message: 'Token refreshed' });
  } catch (error) {
    console.error('Token refresh error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

## セキュリティベストプラクティス

### CSRF対策

```typescript
// CSRF tokenの生成とチェック
import { randomBytes } from 'crypto';

export function generateCSRFToken(): string {
  return randomBytes(32).toString('hex');
}

// Middleware
export function csrfProtection(
  req: NextApiRequest,
  res: NextApiResponse,
  next: () => void
) {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
    return next();
  }

  const token = req.headers['x-csrf-token'];
  const sessionToken = req.cookies.csrf_token;

  if (!token || !sessionToken || token !== sessionToken) {
    return res.status(403).json({ error: 'Invalid CSRF token' });
  }

  next();
}
```

### XSS対策

- httpOnlyクッキー使用（JavaScriptからアクセス不可）
- Content Security Policy (CSP) ヘッダー設定
- ユーザー入力のサニタイズ

### セッションタイムアウト

```typescript
// useSessionTimeout.ts
import { useEffect, useCallback, useRef } from 'react';
import { useAuth } from './useAuth';

export function useSessionTimeout(timeoutMinutes = 30) {
  const { logout } = useAuth();
  const timeoutRef = useRef<NodeJS.Timeout>();

  const resetTimeout = useCallback(() => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    timeoutRef.current = setTimeout(() => {
      alert('セッションがタイムアウトしました');
      logout();
    }, timeoutMinutes * 60 * 1000);
  }, [logout, timeoutMinutes]);

  useEffect(() => {
    // ユーザーアクティビティをリスン
    const events = ['mousedown', 'keydown', 'scroll', 'touchstart'];

    events.forEach((event) => {
      window.addEventListener(event, resetTimeout);
    });

    resetTimeout(); // 初回タイマー設定

    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      events.forEach((event) => {
        window.removeEventListener(event, resetTimeout);
      });
    };
  }, [resetTimeout]);
}

// _app.tsxで使用
function App({ Component, pageProps }: AppProps) {
  useSessionTimeout(30); // 30分

  return (
    <AuthProvider>
      <Component {...pageProps} />
    </AuthProvider>
  );
}
```

## テスト用認証情報

開発・テスト環境で使用する管理者アカウント:

```typescript
// CLAUDE.mdに記載の認証情報
export const TEST_CREDENTIALS = {
  email: 'maccotaro@gmail.com',
  password: 'YK@4TAtTGwcijmW',
  role: 'super_admin',
};

// テストスクリプト例
// curl -c /tmp/cookies.txt -X POST "http://localhost:3003/api/auth/login" \
//   -H "Content-Type: application/json" \
//   -d '{"email":"maccotaro@gmail.com","password":"YK@4TAtTGwcijmW"}'
```

## まとめ

Admin Frontendの認証クライアント設計により、以下を実現しています:

1. **セキュアなToken管理:** httpOnlyクッキーによるXSS対策
2. **ロールベースアクセス制御:** 細かい権限管理
3. **自動Token更新:** シームレスなUX
4. **セッション管理:** タイムアウトと自動ログアウト
5. **保護されたルート:** 未認証・権限不足ユーザーの自動リダイレクト

これらの設計により、安全で使いやすい管理者認証システムが実現されています。