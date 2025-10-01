# 技術スタック

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [フロントエンド技術](#フロントエンド技術)
- [バックエンド技術](#バックエンド技術)
- [データストレージ](#データストレージ)
- [インフラストラクチャ](#インフラストラクチャ)
- [開発ツール](#開発ツール)
- [セキュリティ](#セキュリティ)
- [バージョン管理と互換性](#バージョン管理と互換性)

---

## 概要

ai-micro-serviceシステムは、モダンで実績のある技術スタックを採用しています。各レイヤーで最適な技術を選択し、スケーラビリティ、保守性、開発効率を両立させています。

### 技術選定の基準

1. **成熟度**: 本番環境での実績がある
2. **コミュニティ**: 活発な開発コミュニティとエコシステム
3. **パフォーマンス**: 高速で効率的
4. **開発体験**: 開発者が使いやすい
5. **保守性**: 長期的なメンテナンスが容易

---

## フロントエンド技術

### Core Framework

#### Next.js 15

```yaml
バージョン: 15.0+
ライセンス: MIT
用途: React フレームワーク、SSR/SSG/CSR
```

**選定理由**:
- Server-Side Rendering (SSR) サポート
- API Routes による BFF 実装
- ファイルベースルーティング
- Turbopack による高速ビルド
- Vercel によるエンタープライズサポート

**主要機能**:
- App Router (Next.js 13+)
- Server Components
- API Routes (BFF 層)
- Middleware (認証チェック)
- Image Optimization

#### React 18

```yaml
バージョン: 18.x
ライセンス: MIT
用途: UI コンポーネントライブラリ
```

**特徴**:
- Concurrent Rendering
- Server Components サポート
- Hooks による状態管理
- 豊富なエコシステム

### UI Framework

#### Tailwind CSS 3

```yaml
バージョン: 3.x
ライセンス: MIT
用途: ユーティリティファーストCSS
```

**特徴**:
- ユーティリティクラスベース
- JIT (Just-In-Time) コンパイル
- レスポンシブデザインサポート
- カスタマイズ可能

#### shadcn/ui (オプション)

```yaml
用途: React コンポーネントライブラリ
```

**特徴**:
- Radix UI ベース
- Tailwind CSS 統合
- アクセシビリティ対応

### 型システム

#### TypeScript 5

```yaml
バージョン: 5.x
ライセンス: Apache 2.0
用途: 静的型付け
```

**設定**:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "jsx": "preserve",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "incremental": true
  }
}
```

### 状態管理

#### React Hooks (Built-in)

- `useState`: ローカル状態
- `useEffect`: 副作用管理
- `useContext`: グローバル状態
- `useReducer`: 複雑な状態

#### SWR / React Query (推奨)

```yaml
用途: サーバー状態管理、キャッシング
```

**特徴**:
- 自動再取得
- キャッシング
- 楽観的更新
- エラーハンドリング

---

## バックエンド技術

### Web Framework

#### FastAPI

```yaml
バージョン: 0.104+ / 0.109+
言語: Python 3.11
ライセンス: MIT
用途: RESTful API フレームワーク
```

**実装バージョン**:
- Auth Service: `^0.109.0` (Poetry管理)
- User API: `0.104.1` (requirements.txt管理)
- Admin API: `^0.109.0` (Poetry管理)

**選定理由**:
- 高速（Starlette + Pydantic ベース）
- 自動 OpenAPI ドキュメント生成
- 型ヒントによる自動バリデーション
- 非同期処理サポート
- 優れた開発体験

**主要機能**:
- Dependency Injection
- 自動バリデーション（Pydantic）
- OpenAPI / Swagger UI
- CORS サポート
- WebSocket サポート

### データバリデーション

#### Pydantic

```yaml
バージョン: 2.x
用途: データバリデーション、設定管理
```

**使用例**:

```python
from pydantic import BaseModel, EmailStr, Field

class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=100)
    first_name: str = Field(min_length=1, max_length=50)
    last_name: str = Field(min_length=1, max_length=50)
```

### ORM (Object-Relational Mapping)

#### SQLAlchemy 2.0

```yaml
バージョン: 2.0+
用途: データベース ORM
```

**特徴**:
- 新しい async/await スタイル
- 型ヒントサポート
- マイグレーション（Alembic）
- 複雑なクエリのサポート

**使用例**:

```python
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

async def get_user(session: AsyncSession, user_id: str):
    stmt = select(User).where(User.id == user_id)
    result = await session.execute(stmt)
    return result.scalar_one_or_none()
```

### 認証・認可

#### python-jose (JWT)

```yaml
バージョン: 3.x
用途: JWT 生成・検証
```

#### passlib + bcrypt

```yaml
用途: パスワードハッシュ化
```

**ハッシュアルゴリズム**:
- bcrypt (デフォルト)
- Argon2 (オプション、推奨)

### 非同期処理

#### asyncio

```yaml
Python標準: 3.11+
用途: 非同期I/O
```

#### HTTPX

```yaml
用途: 非同期HTTPクライアント
```

---

## データストレージ

### リレーショナルデータベース

#### PostgreSQL 15

```yaml
バージョン: 15.x
ライセンス: PostgreSQL License
用途: メインデータベース
```

**選定理由**:
- ACID準拠
- 高度なインデックス（B-tree, Hash, GIN, GiST）
- JSONB サポート
- フルテキスト検索
- パーティショニング
- レプリケーション

**使用データベース**:
- `authdb`: 認証情報
- `apidb`: ユーザープロフィール
- `admindb`: 管理データ、ドキュメント

**拡張機能**:
- `uuid-ossp`: UUID生成
- `pg_trgm`: 類似検索
- `pg_stat_statements`: クエリ分析

### インメモリキャッシュ

#### Redis 7

```yaml
バージョン: 7.x
ライセンス: BSD
用途: キャッシュ、セッションストア
```

**選定理由**:
- 高速（インメモリ）
- 豊富なデータ構造（String, Hash, List, Set, Sorted Set）
- TTL サポート
- Pub/Sub
- 永続化オプション（RDB, AOF）

**使用用途**:
- セッション管理
- JWT ブラックリスト
- プロフィールキャッシュ
- JWKS キャッシュ
- レート制限

---

## インフラストラクチャ

### コンテナ化

#### Docker

```yaml
バージョン: 20.10+
用途: コンテナ化
```

**ベースイメージ**:
- `python:3.11-slim`: バックエンド
- `node:20-alpine`: フロントエンド
- `postgres:15-alpine`: データベース
- `redis:7-alpine`: キャッシュ

#### Docker Compose

```yaml
バージョン: 2.0+
用途: マルチコンテナオーケストレーション
```

### リバースプロキシ (将来)

#### Nginx

```yaml
用途: リバースプロキシ、ロードバランサー
```

---

## 開発ツール

### パッケージ管理

#### Python: Poetry

```yaml
バージョン: 1.5+
用途: Python依存関係管理
```

**pyproject.toml**:

```toml
[tool.poetry]
name = "ai-micro-api-auth"
version = "1.0.0"

[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.100.0"
uvicorn = {extras = ["standard"], version = "^0.23.0"}
sqlalchemy = "^2.0.0"
pydantic = "^2.0.0"
python-jose = {extras = ["cryptography"], version = "^3.3.0"}
```

#### Node.js: npm / pnpm

```yaml
用途: JavaScript依存関係管理
```

### リンター・フォーマッター

#### Python

- **Ruff**: 高速リンター
- **Black**: コードフォーマッター
- **mypy**: 静的型チェック
- **isort**: インポート並び替え

#### TypeScript/JavaScript

- **ESLint**: リンター
- **Prettier**: フォーマッター

### テストフレームワーク

#### Python: pytest

```yaml
用途: ユニットテスト、統合テスト
```

#### JavaScript: Jest / Vitest

```yaml
用途: ユニットテスト
```

#### E2E: Playwright

```yaml
用途: エンドツーエンドテスト
```

---

## セキュリティ

### 暗号化

#### RSA-2048 (JWT署名)

```yaml
アルゴリズム: RS256
鍵長: 2048 bits
用途: JWT署名
```

#### bcrypt (パスワードハッシュ)

```yaml
ラウンド: 12
用途: パスワードハッシュ化
```

### HTTPS/TLS

```yaml
プロトコル: TLS 1.3
証明書: Let's Encrypt (本番環境)
```

### CORS

```yaml
ライブラリ: fastapi.middleware.cors
設定: 環境別に制御
```

---

## バージョン管理と互換性

### 言語・ランタイム

| 技術 | 最小バージョン | 推奨バージョン | 互換性 |
|-----|--------------|--------------|-------|
| Python | 3.11 | 3.11+ | 3.12でも動作確認済み |
| Node.js | 18.17 | 20.x | 18 LTS, 20 LTS サポート |
| TypeScript | 5.0 | 5.x | 最新版推奨 |

### データベース

| 技術 | 最小バージョン | 推奨バージョン | 互換性 |
|-----|--------------|--------------|-------|
| PostgreSQL | 13 | 15+ | 13-16でテスト済み |
| Redis | 6 | 7+ | 6-7でテスト済み |

### フレームワーク

| 技術 | 最小バージョン | 推奨バージョン | 備考 |
|-----|--------------|--------------|------|
| FastAPI | 0.100 | 0.100+ | 1.0未満 |
| Next.js | 14.0 | 14.x | App Router使用 |
| React | 18.0 | 18.x | Server Components |
| SQLAlchemy | 2.0 | 2.0+ | async/await スタイル |

---

## 依存関係グラフ

### フロントエンド

```
Next.js 15
├── React 18
├── TypeScript 5
├── Tailwind CSS 3
├── SWR / React Query
└── @types/node, @types/react
```

### バックエンド

```
FastAPI
├── Starlette (ASGI フレームワーク)
├── Pydantic (バリデーション)
├── Uvicorn (ASGI サーバー)
├── SQLAlchemy (ORM)
│   └── asyncpg (PostgreSQL ドライバー)
├── python-jose (JWT)
│   └── cryptography
├── passlib (パスワードハッシュ)
│   └── bcrypt
└── redis-py (Redis クライアント)
```

---

## 技術選定の理由まとめ

| レイヤー | 技術 | 選定理由 |
|---------|------|---------|
| Frontend Framework | Next.js 15 | SSR、BFF、優れたDX |
| UI Library | React 18 | 豊富なエコシステム、Server Components |
| Styling | Tailwind CSS | 高速開発、一貫性 |
| Type System | TypeScript | 型安全、保守性 |
| Backend Framework | FastAPI | 高速、自動ドキュメント、型ヒント |
| ORM | SQLAlchemy 2.0 | 成熟、async対応、柔軟性 |
| Database | PostgreSQL 15 | ACID、高機能、実績 |
| Cache | Redis 7 | 高速、豊富なデータ構造 |
| Container | Docker | ポータビリティ、エコシステム |

---

## 将来の技術導入候補

### モニタリング

- **Prometheus + Grafana**: メトリクス監視
- **Jaeger / Tempo**: 分散トレーシング
- **Sentry**: エラートラッキング

### ログ集約

- **Elasticsearch + Kibana**: ログ検索・可視化
- **Fluentd / Loki**: ログ収集

### CI/CD

- **GitHub Actions**: 自動テスト・デプロイ
- **ArgoCD**: GitOps デプロイ

### オーケストレーション

- **Kubernetes**: コンテナオーケストレーション（スケール時）

---

## 関連ドキュメント

- [システム全体アーキテクチャ](./01-system-architecture.md)
- [インフラ構成](./03-infrastructure.md)
- [開発ガイド](../12-development/01-development-setup.md)
- [セキュリティ設計](../10-security/01-security-overview.md)

---

**最終更新**: 2025-09-30