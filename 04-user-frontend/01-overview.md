# User Frontend 概要

**カテゴリ**: Frontend Service (BFF Pattern)
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [サービス概要](#サービス概要)
- [責務と役割](#責務と役割)
- [アーキテクチャ](#アーキテクチャ)
- [技術スタック](#技術スタック)
- [主要機能](#主要機能)
- [関連サービス](#関連サービス)

---

## サービス概要

User Frontend (`ai-micro-front-user`) は、エンドユーザー向けのWebアプリケーションです。Next.jsを使用したBFF（Backend for Frontend）パターンを採用し、フロントエンドUIとバックエンドAPIのプロキシ層の両方を提供します。

### 基本情報

| 項目 | 内容 |
|------|------|
| サービス名 | User Frontend (BFF) |
| リポジトリ | `ai-micro-front-user/` |
| コンテナ名 | `ai-micro-front-user` |
| ポート | 3002 (外部) → 3000 (内部) |
| フレームワーク | Next.js 15 |
| 言語 | TypeScript |
| スタイリング | Tailwind CSS |
| ビルドツール | Turbopack (開発時) |

---

## 責務と役割

### 主要責務

1. **ユーザーインターフェース提供**
   - ログイン・サインアップ画面
   - プロファイル表示・編集画面
   - RAGチャット機能（ドキュメント検索・会話）
   - レスポンシブデザイン対応

2. **BFF層（APIプロキシ）**
   - 認証サービスへのリクエストプロキシ
   - User APIサービスへのリクエストプロキシ
   - Admin APIサービスへのリクエストプロキシ（RAG機能）
   - JWTトークンのCookie管理
   - セキュリティヘッダーの付与

3. **認証管理**
   - JWTトークンのhttpOnly Cookie保存
   - トークンリフレッシュ処理
   - ログアウト処理
   - 認証状態の管理

4. **セキュリティ実装**
   - httpOnly Cookieによるトークン保護
   - CSRF保護（SameSite Cookie属性）
   - セキュリティヘッダー設定
   - クライアントサイドでの機密情報非保持

### 責務範囲外

- ユーザー認証ロジック（Auth Serviceの責務）
- プロファイルデータ永続化（User API Serviceの責務）
- 管理機能（Admin Frontendの責務）

---

## アーキテクチャ

### サービス位置付け

```
┌───────────────────────────────────────────────────┐
│         User Frontend (Port 3002)                 │
│  ┌────────────────┐  ┌─────────────────────────┐ │
│  │  Pages (UI)    │  │  API Routes (BFF)       │ │
│  │  - /login      │  │  - /api/auth/*          │ │
│  │  - /signup     │  │  - /api/profile/*       │ │
│  │  - /profile/*  │  │  - /api/rag/*           │ │
│  │  - /rag/*      │  │  - /api/health          │ │
│  └────────┬───────┘  └────────┬────────────────┘ │
│           │                   │                   │
│           └───────┬───────────┘                   │
└───────────────────┼───────────────────────────────┘
                    │ HTTP/REST
        ┌───────────┼────────────┐
        │           │            │
   ┌────▼─────┐ ┌──▼──────┐ ┌───▼──────┐
   │Auth      │ │User API │ │Admin API │
   │Service   │ │Service  │ │Service   │
   │(8002)    │ │(8001)   │ │(8003)    │
   └──────────┘ └─────────┘ └──────────┘
```

### BFFパターンの実装

User Frontendは、Next.jsの機能を活用してBFFパターンを実装しています：

1. **Pages Router**: ユーザー向けUIページ
   - Server-side rendering (SSR) 対応
   - ファイルベースルーティング
   - TypeScriptによる型安全性

2. **API Routes**: バックエンドプロキシ層
   - `/api/*` エンドポイント
   - バックエンドサービスへのリクエスト転送
   - Cookie操作とトークン管理
   - レスポンス変換

### ディレクトリ構造

```
ai-micro-front-user/
├── src/
│   ├── pages/                    # Next.js Pages Router
│   │   ├── _app.tsx             # アプリケーション設定
│   │   ├── index.tsx            # ホームページ
│   │   ├── login.tsx            # ログインページ
│   │   ├── signup.tsx           # サインアップページ
│   │   ├── logout.tsx           # ログアウトページ
│   │   ├── profile/             # プロファイル管理
│   │   │   ├── view.tsx         # プロファイル表示
│   │   │   └── edit.tsx         # プロファイル編集
│   │   ├── rag/                 # RAG機能
│   │   │   ├── chat.tsx         # チャット画面
│   │   │   ├── documents.tsx   # ドキュメント一覧
│   │   │   └── upload.tsx       # アップロード画面
│   │   └── api/                 # API Routes (BFF層)
│   │       ├── auth/            # 認証API
│   │       │   ├── login.ts     # ログインプロキシ
│   │       │   ├── signup.ts    # サインアッププロキシ
│   │       │   ├── logout.ts    # ログアウト
│   │       │   └── refresh.ts   # トークンリフレッシュ
│   │       ├── profile/         # プロファイルAPI
│   │       │   └── index.ts     # プロファイルCRUD
│   │       ├── rag/             # RAG API
│   │       │   ├── search.ts    # ドキュメント検索
│   │       │   ├── query-stream.ts  # ストリーミングチャット
│   │       │   ├── documents.ts # ドキュメント管理
│   │       │   └── upload.ts    # ファイルアップロード
│   │       └── health.ts        # ヘルスチェック
│   ├── lib/                     # ユーティリティ
│   │   ├── auth.ts              # 認証ヘルパー
│   │   └── fetcher.ts           # APIクライアント
│   ├── styles/                  # スタイル
│   │   └── globals.css          # Tailwind CSS
│   └── types/                   # 型定義
├── public/                       # 静的ファイル
├── Dockerfile
├── docker-compose.yml
├── package.json
├── tsconfig.json
├── tailwind.config.js
├── next.config.js
├── CLAUDE.md
└── .env.local                   # 環境変数
```

---

## 技術スタック

### コア技術

| カテゴリ | 技術 | バージョン | 用途 |
|---------|------|-----------|------|
| Framework | Next.js | 15.0+ | Reactフレームワーク、SSR、APIルート |
| Language | TypeScript | 5.0+ | 型安全な開発 |
| UI Library | React | 18.0+ | ユーザーインターフェース |
| Styling | Tailwind CSS | 3.4+ | CSSフレームワーク |
| Build Tool | Turbopack | - | 高速開発ビルド |
| Container | Docker | - | コンテナ化 |

### 主要依存ライブラリ

```json
{
  "dependencies": {
    "next": "^15.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0",
    "cookie": "^1.0.0",
    "jsonwebtoken": "^9.0.0",
    "marked": "^16.2.1",
    "dompurify": "^3.2.6",
    "highlight.js": "^11.11.1",
    "formidable": "^3.5.4"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/react": "^18.0.0",
    "@types/cookie": "^0.6.0",
    "@types/jsonwebtoken": "^9.0.0",
    "typescript": "^5.0.0",
    "tailwindcss": "^3.4.0",
    "autoprefixer": "^10.4.0",
    "postcss": "^8.4.0",
    "eslint": "^8.0.0",
    "eslint-config-next": "^15.0.0"
  }
}
```

### 認証・セキュリティ

| 技術 | 用途 |
|------|------|
| JWT (jsonwebtoken) | トークン検証（BFF層） |
| httpOnly Cookie | トークン保存（XSS対策） |
| SameSite Cookie | CSRF対策 |
| Security Headers | XSS、Clickjacking対策 |

---

## 主要機能

### 1. 認証機能

#### ログイン (POST /api/auth/login)
```typescript
// フロントエンド: /login ページ
export default function LoginPage() {
  const handleLogin = async (email: string, password: string) => {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    if (response.ok) {
      router.push('/profile/view');
    }
  };
}

// BFF層: /api/auth/login.ts
export default async function handler(req, res) {
  const response = await proxyRequestToAuth(req, '/auth/login');
  const { data, status } = await handleProxyResponse(response);

  if (status === 200 && data.access_token && data.refresh_token) {
    setTokenCookies(res, data.access_token, data.refresh_token);
    return res.status(200).json({ message: 'Login successful' });
  }

  return res.status(status).json(data);
}
```

#### サインアップ (POST /api/auth/signup)
- 新規ユーザー登録
- Auth Serviceへのプロキシ
- 登録成功後、自動ログイン処理

#### ログアウト (POST /api/auth/logout)
```typescript
// BFF層でCookieをクリア
export default async function handler(req, res) {
  res.setHeader('Set-Cookie', [
    cookie.serialize('access_token', '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 0,
      path: '/'
    }),
    cookie.serialize('refresh_token', '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 0,
      path: '/'
    })
  ]);

  return res.status(200).json({ message: 'Logged out successfully' });
}
```

### 2. プロファイル管理

#### プロファイル表示 (/profile/view)
```typescript
interface Profile {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  phone?: string;
  created_at: string;
  updated_at: string;
}

export default function ProfileView() {
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    fetch('/api/profile')
      .then(res => res.json())
      .then(data => setProfile(data));
  }, []);

  return (
    <div className="profile-view">
      <h1>Profile</h1>
      <div>Email: {profile?.email}</div>
      <div>Name: {profile?.first_name} {profile?.last_name}</div>
    </div>
  );
}
```

#### プロファイル編集 (/profile/edit)
- フォームバリデーション
- PUT /api/profile でのデータ送信
- 更新成功後、表示ページへリダイレクト

### 3. RAG機能

#### チャット画面 (/rag/chat)
- ストリーミングレスポンス対応
- マークダウン表示
- ドキュメント参照情報表示
- ナレッジベース選択機能

#### ドキュメント管理 (/rag/documents)
- ドキュメント一覧表示
- アップロード機能
- ダウンロード機能
- ステータス表示

#### ドキュメント検索 (POST /api/rag/search)
```typescript
// Admin API経由でドキュメント検索
export default async function handler(req, res) {
  const { query, knowledge_base_id } = req.body;

  const response = await fetch(`${ADMIN_API_URL}/rag/search`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`
    },
    body: JSON.stringify({ query, knowledge_base_id })
  });

  const data = await response.json();
  return res.status(response.status).json(data);
}
```

### 4. ヘルスチェック

#### GET /api/health
```typescript
export default async function handler(req, res) {
  return res.status(200).json({
    status: 'healthy',
    service: 'User Frontend BFF',
    timestamp: new Date().toISOString()
  });
}
```

---

## 関連サービス

### 依存サービス

| サービス | 依存理由 | 接続先 |
|---------|---------|-------|
| Auth Service | ユーザー認証、JWT発行 | `http://host.docker.internal:8002` |
| User API Service | プロファイル管理 | `http://host.docker.internal:8001` |
| Admin API Service | RAG機能（検索、チャット） | `http://host.docker.internal:8003` |

### サービス間通信フロー

1. **ログインフロー**
   ```
   User Browser → User Frontend (UI: /login)
                → User Frontend (BFF: /api/auth/login)
                → Auth Service (POST /auth/login)
                ← JWT tokens
   User Frontend (BFF) ← Set httpOnly cookies
   User Browser ← Redirect to /profile/view
   ```

2. **プロファイル取得フロー**
   ```
   User Browser → User Frontend (UI: /profile/view)
                → User Frontend (BFF: /api/profile)
                → User API Service (GET /profile)
                   (with Authorization: Bearer {token})
                ← Profile data
   User Browser ← Display profile
   ```

3. **RAGチャットフロー**
   ```
   User Browser → User Frontend (UI: /rag/chat)
                → User Frontend (BFF: /api/rag/query-stream)
                → Admin API Service (POST /rag/query)
                ← Streaming response
   User Browser ← Display streaming text
   ```

---

## 環境変数

### 必須設定

```env
# Backend Service URLs
AUTH_SERVER_URL=http://host.docker.internal:8002
API_SERVER_URL=http://host.docker.internal:8001
ADMIN_API_URL=http://host.docker.internal:8003

# Cookie Configuration
ACCESS_TOKEN_COOKIE_NAME=access_token
REFRESH_TOKEN_COOKIE_NAME=refresh_token
ACCESS_TOKEN_TTL_SEC=900

# JWT Configuration
JWT_SECRET=your-jwt-secret-key-change-in-production

# Next.js Configuration
NEXTAUTH_URL=http://localhost:3002
NODE_ENV=development
```

---

## 起動方法

### Docker Compose使用（推奨）

```bash
cd ai-micro-front-user
docker compose up -d

# ログ確認
docker compose logs -f ai-micro-front-user

# サービス確認
curl http://localhost:3002
curl http://localhost:3002/api/health
```

### ローカル開発

```bash
cd ai-micro-front-user

# 依存関係インストール
npm install

# 開発サーバー起動（Turbopack使用）
npm run dev

# ビルド
npm run build

# 本番サーバー起動
npm run start

# 型チェック
npm run type-check

# リント
npm run lint
```

アクセスURL: http://localhost:3002

---

## セキュリティ

### Cookie設定

```typescript
// httpOnly Cookie設定例
export function setTokenCookies(
  res: NextApiResponse,
  accessToken: string,
  refreshToken: string
) {
  const isProduction = process.env.NODE_ENV === 'production';

  res.setHeader('Set-Cookie', [
    cookie.serialize('access_token', accessToken, {
      httpOnly: true,        // JavaScriptからアクセス不可
      secure: isProduction,  // 本番環境ではHTTPSのみ
      sameSite: 'strict',    // CSRF対策
      maxAge: 900,           // 15分
      path: '/'
    }),
    cookie.serialize('refresh_token', refreshToken, {
      httpOnly: true,
      secure: isProduction,
      sameSite: 'strict',
      maxAge: 604800,        // 7日
      path: '/'
    })
  ]);
}
```

### セキュリティベストプラクティス

1. **トークン管理**
   - JWTトークンはhttpOnly Cookieのみで保存
   - クライアントサイドJavaScriptから一切アクセス不可
   - リフレッシュトークンでアクセストークンを自動更新

2. **XSS対策**
   - httpOnly Cookie使用
   - DOMPurifyでユーザー入力をサニタイズ
   - Content Security Policy (CSP) 設定

3. **CSRF対策**
   - SameSite Cookie属性設定
   - トークン検証

4. **通信セキュリティ**
   - 本番環境ではHTTPS必須
   - Secure Cookie フラグ有効化

---

## パフォーマンス特性

### レンダリング戦略

- **SSR (Server-Side Rendering)**: 初回ページロード高速化
- **CSR (Client-Side Rendering)**: 動的コンテンツ
- **Static Generation**: 静的ページ（ホームページなど）

### 最適化

- Turbopackによる高速開発ビルド
- Next.js自動コード分割
- 画像最適化（next/image）
- フォント最適化

---

## 監視・ロギング

### ログ出力

```typescript
// API Route ログ例
console.log('Login request body:', req.body);
console.log('Auth server response status:', response.status);
console.error('Login proxy error details:', error);
```

### ヘルスチェック

```bash
$ curl http://localhost:3002/api/health
{
  "status": "healthy",
  "service": "User Frontend BFF",
  "timestamp": "2025-09-30T12:00:00.000Z"
}
```

---

## トラブルシューティング

### よくある問題

1. **401 Unauthorized**
   - Cookieが正しく設定されていない
   - トークンが期限切れ
   - バックエンドサービスとの通信失敗

2. **CORS エラー**
   - バックエンドサービスのCORS設定確認
   - 開発環境では通常発生しない（BFFパターンのため）

3. **ポート競合**
   - デフォルトポート3002が使用中
   - docker-compose.ymlのポート設定変更

4. **環境変数未設定**
   - `.env.local` ファイルの存在確認
   - 必須環境変数の設定確認

---

## 今後の拡張予定

- [ ] ユーザープロファイル画像アップロード
- [ ] 多言語対応（i18n）
- [ ] Progressive Web App (PWA) 対応
- [ ] リアルタイム通知機能
- [ ] パフォーマンスモニタリング強化

---

## 関連ドキュメント

- [画面設計](./02-screen-design.md)
- [API統合](./03-api-integration.md)
- [認証クライアント実装](./04-authentication-client.md)
- [状態管理](./05-state-management.md)
- [コンポーネント設計](./06-component-design.md)
- [プロファイル機能](./07-profile-features.md)
- [システム全体アーキテクチャ](/00-overview/01-system-architecture.md)