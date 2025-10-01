# エラー伝播

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [エラー分類](#エラー分類)
- [エラーレスポンス形式](#エラーレスポンス形式)
- [エラー伝播パターン](#エラー伝播パターン)
- [実装例](#実装例)

---

## 概要

マイクロサービス間でエラーを適切に伝播させ、ユーザーに分かりやすいエラーメッセージを返却することが重要です。

---

## エラー分類

### HTTPステータスコード

| コード | カテゴリ | 説明 |
|-------|---------|------|
| 400 | クライアントエラー | リクエスト不正 |
| 401 | 認証エラー | 認証失敗 |
| 403 | 認可エラー | 権限不足 |
| 404 | リソースエラー | リソース不存在 |
| 422 | バリデーションエラー | 入力検証失敗 |
| 429 | レート制限 | リクエスト過多 |
| 500 | サーバーエラー | 内部エラー |
| 503 | サービス停止 | サービス利用不可 |

---

## エラーレスポンス形式

### 統一フォーマット

```json
{
  "status": "error",
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message",
    "details": {},
    "trace_id": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

---

## エラー伝播パターン

### パターン1: エラー変換

```python
async def call_backend_service():
    try:
        response = await httpx.get("http://backend/api")
        return response.json()
    except httpx.HTTPStatusError as e:
        # バックエンドエラーをフロントエンド向けに変換
        if e.response.status_code == 404:
            raise HTTPException(status_code=404, detail="Resource not found")
        raise HTTPException(status_code=500, detail="Backend error")
```

### パターン2: エラー集約

```python
async def aggregate_errors():
    errors = []

    try:
        await service1()
    except Exception as e:
        errors.append({"service": "service1", "error": str(e)})

    try:
        await service2()
    except Exception as e:
        errors.append({"service": "service2", "error": str(e)})

    if errors:
        raise HTTPException(status_code=500, detail={"errors": errors})
```

---

## 実装例

### FastAPIエラーハンドラ

```python
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

app = FastAPI()

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "status": "error",
            "error": {
                "code": "HTTP_ERROR",
                "message": exc.detail,
                "trace_id": request.headers.get("X-Request-ID")
            }
        }
    )
```

---

## 関連ドキュメント

- [サービス間通信](./01-service-communication.md)
- [API仕様](../01-auth-service/02-api-specification.md)