# インターフェース定義概要

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [APIコントラクトの目的](#apiコントラクトの目的)
- [定義方法](#定義方法)
- [バージョニング戦略](#バージョニング戦略)
- [ドキュメント生成](#ドキュメント生成)

---

## 概要

APIコントラクトは、サービス間のインターフェース仕様を明確に定義し、フロントエンドとバックエンド、またはバックエンド間の通信規約を文書化したものです。

### APIコントラクトの役割

1. **仕様の明確化**: リクエスト/レスポンス形式の定義
2. **型安全性**: TypeScript型定義とPydanticスキーマ
3. **自動生成**: OpenAPIからクライアントコード生成
4. **契約テスト**: スキーマに基づくテスト自動化

---

## APIコントラクトの目的

### 開発効率の向上

- フロントエンドとバックエンドの並行開発
- モックサーバーによる早期テスト
- スキーマドリブン開発

### 品質保証

- リクエスト/レスポンスの自動バリデーション
- 契約テストによる互換性保証
- 型安全なコード生成

---

## 定義方法

### OpenAPI 3.0

```yaml
openapi: 3.0.0
info:
  title: Auth Service API
  version: 1.0.0

paths:
  /api/v1/auth/login:
    post:
      summary: ユーザーログイン
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/LoginRequest'
      responses:
        '200':
          description: ログイン成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/LoginResponse'
```

### Pydantic (Python)

```python
from pydantic import BaseModel, EmailStr

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
```

### TypeScript

```typescript
export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
}
```

---

## バージョニング戦略

### URLパスバージョニング

```
/api/v1/auth/login  ← 現行バージョン
/api/v2/auth/login  ← 新バージョン
```

### 後方互換性の維持

- 既存エンドポイントは削除しない
- 新機能は新バージョンで提供
- 非推奨（deprecated）マーキング

---

## ドキュメント生成

### FastAPI自動生成

```python
from fastapi import FastAPI

app = FastAPI(
    title="Auth Service API",
    version="1.0.0",
    openapi_url="/openapi.json",
    docs_url="/docs",
    redoc_url="/redoc"
)
```

アクセス:
- Swagger UI: `http://localhost:8002/docs`
- ReDoc: `http://localhost:8002/redoc`
- OpenAPI JSON: `http://localhost:8002/openapi.json`

---

## 関連ドキュメント

- [エンドポイント対応表](./02-interface-matrix.md)
- [データモデル定義](./03-data-models.md)
- [OpenAPI統合](./04-openapi-integration.md)
- [TypeScript型定義](./05-typescript-types.md)
- [Pydanticスキーマ](./06-pydantic-schemas.md)
- [契約テスト](./07-contract-testing.md)