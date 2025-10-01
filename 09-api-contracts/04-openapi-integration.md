# OpenAPI統合

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [OpenAPI設定](#openapi設定)
- [スキーマ定義](#スキーマ定義)
- [自動生成ドキュメント](#自動生成ドキュメント)
- [クライアントコード生成](#クライアントコード生成)

---

## 概要

FastAPIは、OpenAPI 3.0に基づいた自動ドキュメント生成をサポートしています。

---

## OpenAPI設定

### FastAPI設定

```python
from fastapi import FastAPI

app = FastAPI(
    title="Auth Service API",
    description="認証・認可サービスのAPI",
    version="1.0.0",
    openapi_url="/openapi.json",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_tags=[
        {"name": "auth", "description": "認証関連エンドポイント"},
        {"name": "users", "description": "ユーザー管理エンドポイント"},
    ]
)
```

---

## スキーマ定義

### Pydanticモデル

```python
from pydantic import BaseModel, EmailStr

class LoginRequest(BaseModel):
    """ログインリクエスト"""
    email: EmailStr
    password: str

    class Config:
        json_schema_extra = {
            "example": {
                "email": "user@example.com",
                "password": "SecurePass123!"
            }
        }
```

### エンドポイント定義

```python
@app.post(
    "/api/v1/auth/login",
    response_model=LoginResponse,
    tags=["auth"],
    summary="ユーザーログイン",
    description="メールアドレスとパスワードで認証し、JWTトークンを発行します。"
)
async def login(credentials: LoginRequest):
    """ログイン処理"""
    pass
```

---

## 自動生成ドキュメント

### Swagger UI

アクセス: `http://localhost:8002/docs`

- インタラクティブなAPI テスト
- リクエスト/レスポンス例の表示
- 認証トークン設定

### ReDoc

アクセス: `http://localhost:8002/redoc`

- 読みやすいドキュメント
- 検索機能
- ダウンロード可能なOpenAPI仕様

---

## クライアントコード生成

### openapi-generator

```bash
# TypeScriptクライアント生成
openapi-generator-cli generate \
  -i http://localhost:8002/openapi.json \
  -g typescript-fetch \
  -o ./generated/client

# Pythonクライアント生成
openapi-generator-cli generate \
  -i http://localhost:8002/openapi.json \
  -g python \
  -o ./generated/python-client
```

---

## 関連ドキュメント

- [データモデル定義](./03-data-models.md)
- [TypeScript型定義](./05-typescript-types.md)
- [契約テスト](./07-contract-testing.md)