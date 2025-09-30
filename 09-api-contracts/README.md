# 09. APIインターフェース定義

フロントエンドとバックエンド、サービス間のAPIインターフェース定義を管理します。

## 📄 ドキュメント一覧

### 01. インターフェース定義概要
`01-overview.md`

APIインターフェース定義の目的、管理方法、OpenAPI活用を説明します。

### 02. エンドポイント対応表
`02-interface-matrix.md`

フロントエンド → BFF → バックエンド のエンドポイント対応を一覧化します。

**例**:
| Frontend呼び出し | BFFエンドポイント | バックエンド | 認証 |
|--------------|--------------|------------|------|
| `POST /api/auth/login` | `POST /api/auth/login` | Auth Service: `POST /auth/login` | - |
| `GET /api/profile` | `GET /api/profile` | User API: `GET /api/v1/profiles/me` | ✓ |

### 03. データモデル定義
`03-data-models.md`

共通のデータモデル（User、Profile、Document等）を定義します。

**主な内容**:
- JSON Schema形式でのデータモデル
- TypeScript型定義との対応
- Pydanticスキーマとの対応

### 04. OpenAPI統合仕様書
`04-openapi-integration.md`

各サービスのOpenAPI仕様を統合管理する方法を説明します。

**主な内容**:
- OpenAPI自動生成
- TypeScript型自動生成
- API契約テスト自動生成

### 05. TypeScript型定義
`05-typescript-types.md`

フロントエンドで使用するTypeScript型定義を説明します。

**主な内容**:
- 型定義の配置場所（`src/types/`）
- OpenAPIからの自動生成方法
- 型定義の更新フロー

### 06. Pydanticスキーマ定義
`06-pydantic-schemas.md`

バックエンドで使用するPydanticスキーマを説明します。

**主な内容**:
- スキーマの配置場所（`app/schemas/`）
- バリデーションルール
- OpenAPIドキュメント生成

### 07. API契約テスト仕様
`07-contract-testing.md`

APIの契約テスト（Contract Testing）の方法を説明します。

**主な内容**:
- Pact等のツール使用
- テストケース作成
- CI/CDへの組み込み

## 📂 OpenAPI仕様ファイル

`openapi/` ディレクトリには以下のファイルが含まれます:

- `auth-service.yaml` - 認証サービスのOpenAPI仕様
- `user-api.yaml` - ユーザーAPIのOpenAPI仕様
- `admin-api.yaml` - 管理APIのOpenAPI仕様
- `combined.yaml` - 統合版OpenAPI仕様

## 🎯 このセクションを読むべき人

- **全ての開発者**: APIインターフェースを理解するために必読
- **フロントエンド開発者**: API呼び出しを実装する際に参照
- **バックエンド開発者**: API設計・実装時に参照
- **QA担当者**: API契約テストを作成する場合

## 🔗 関連ドキュメント

- [01-auth-service/02-api-specification.md](../01-auth-service/) - 認証API詳細
- [02-user-api/02-api-specification.md](../02-user-api/) - ユーザーAPI詳細
- [03-admin-api/02-api-specification.md](../03-admin-api/) - 管理API詳細
- [08-integration/](../08-integration/) - サービス間連携
- [15-testing/05-contract-testing.md](../15-testing/) - 契約テスト詳細

## 🚀 クイックスタート

### OpenAPI仕様の確認
各サービスを起動し、以下のURLでSwagger UIを確認できます:

- Auth Service: http://localhost:8002/docs
- User API: http://localhost:8001/docs
- Admin API: http://localhost:8003/docs

### TypeScript型の自動生成
```bash
# openapi-typescriptを使用
npx openapi-typescript openapi/auth-service.yaml -o src/types/auth-api.ts
```

---

**このセクションは、フロントエンドとバックエンドの契約書です。インターフェース定義を正確に管理することで、開発の効率と品質が向上します。**