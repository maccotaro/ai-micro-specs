# BFFパターン

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [BFFの責務](#bffの責務)
- [アーキテクチャ](#アーキテクチャ)
- [実装パターン](#実装パターン)
- [セキュリティ考慮事項](#セキュリティ考慮事項)

---

## 概要

BFF（Backend for Frontend）は、フロントエンドとバックエンドサービスの間に位置し、フロントエンド固有の要件に特化したAPIレイヤーを提供します。

### BFFの利点

1. **フロントエンド最適化**: UI要件に合わせたAPIレスポンス
2. **セキュリティ**: トークン管理をサーバー側で実施
3. **集約**: 複数バックエンドAPIの呼び出しを1つに集約
4. **変換**: バックエンドデータをフロントエンド向けに変換

---

## BFFの責務

### 1. APIプロキシ

```typescript
// pages/api/profile.ts
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const accessToken = req.cookies.access_token;

  const response = await fetch(
    `${process.env.API_SERVER_URL}/api/v1/profiles/me`,
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    }
  );

  const data = await response.json();
  res.status(response.status).json(data);
}
```

### 2. トークン管理

```typescript
// JWT をhttpOnly cookieで管理
res.setHeader('Set-Cookie', [
  `access_token=${accessToken}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900`,
  `refresh_token=${refreshToken}; HttpOnly; Secure; SameSite=Strict; Path=/api/auth; Max-Age=604800`,
]);
```

### 3. データ集約

```typescript
// 複数APIからデータ取得して集約
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const [profile, documents] = await Promise.all([
    fetch(`${process.env.API_SERVER_URL}/api/v1/profiles/me`),
    fetch(`${process.env.ADMIN_API_URL}/api/v1/documents`),
  ]);

  res.json({
    profile: await profile.json(),
    documents: await documents.json(),
  });
}
```

### 4. SSR（Server-Side Rendering）

```typescript
// pages/dashboard.tsx
export const getServerSideProps: GetServerSideProps = async (context) => {
  const accessToken = context.req.cookies.access_token;

  if (!accessToken) {
    return {
      redirect: {
        destination: '/login',
        permanent: false,
      },
    };
  }

  const response = await fetch(
    `${process.env.API_SERVER_URL}/api/v1/profiles/me`,
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    }
  );

  const profile = await response.json();

  return {
    props: { profile },
  };
};
```

---

## アーキテクチャ

### BFF配置図

```
┌─────────────────────────────────────────────┐
│               Browser                       │
└────────────────┬────────────────────────────┘
                 │ HTTPS
                 ▼
┌─────────────────────────────────────────────┐
│          Next.js BFF Layer                  │
│  ┌─────────────────────────────────────┐   │
│  │ Pages (SSR/CSR)                     │   │
│  │  - /dashboard                       │   │
│  │  - /profile                         │   │
│  └─────────────────────────────────────┘   │
│  ┌─────────────────────────────────────┐   │
│  │ API Routes (/api/*)                 │   │
│  │  - /api/auth/*                      │   │
│  │  - /api/profile                     │   │
│  │  - /api/documents                   │   │
│  └─────────────────────────────────────┘   │
└────────────────┬────────────────────────────┘
                 │ Internal Network
        ┌────────┼────────┐
        │                 │
        ▼                 ▼
┌──────────────┐  ┌──────────────┐
│ Auth Service │  │ User API     │
│ Port: 8002   │  │ Port: 8001   │
└──────────────┘  └──────────────┘
```

---

## 実装パターン

### パターン1: シンプルプロキシ

```typescript
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const { method, body } = req;
  const accessToken = req.cookies.access_token;

  const response = await fetch(
    `${process.env.API_SERVER_URL}${req.url}`,
    {
      method,
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: method !== 'GET' ? JSON.stringify(body) : undefined,
    }
  );

  const data = await response.json();
  res.status(response.status).json(data);
}
```

### パターン2: データ変換

```typescript
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const response = await fetch(`${process.env.API_SERVER_URL}/api/v1/profiles/me`);
  const profile = await response.json();

  // フロントエンド向けに変換
  const transformed = {
    displayName: `${profile.first_name} ${profile.last_name}`,
    avatar: profile.avatar_url || '/default-avatar.png',
    memberSince: new Date(profile.created_at).getFullYear(),
  };

  res.json(transformed);
}
```

### パターン3: エラー変換

```typescript
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  try {
    const response = await fetch(`${process.env.API_SERVER_URL}/api/v1/profiles/me`);

    if (!response.ok) {
      const error = await response.json();

      // ユーザーフレンドリーなエラーメッセージに変換
      return res.status(response.status).json({
        error: translateErrorMessage(error),
      });
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: 'サーバーエラーが発生しました' });
  }
}
```

---

## セキュリティ考慮事項

### 1. トークンの保護

```typescript
// ✅ 正しい実装: httpOnly cookie
res.setHeader('Set-Cookie',
  `access_token=${token}; HttpOnly; Secure; SameSite=Strict`
);

// ❌ 危険な実装: localStorage
// localStorage.setItem('access_token', token);  // XSS攻撃のリスク
```

### 2. CSRF保護

```typescript
// middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(req: NextRequest) {
  // CSRFトークン検証
  if (req.method !== 'GET') {
    const csrfToken = req.headers.get('X-CSRF-Token');
    const cookieToken = req.cookies.get('csrf_token');

    if (!csrfToken || csrfToken !== cookieToken) {
      return NextResponse.json({ error: 'CSRF validation failed' }, { status: 403 });
    }
  }

  return NextResponse.next();
}
```

### 3. レート制限

```typescript
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15分
  max: 100, // 最大100リクエスト
});

export default limiter;
```

---

## 関連ドキュメント

- [サービス間通信](./01-service-communication.md)
- [認証フロー](./02-authentication-flow.md)
- [フロントエンド概要](../04-user-frontend/01-overview.md)