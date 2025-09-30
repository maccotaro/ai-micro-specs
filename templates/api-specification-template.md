# [サービス名] - API仕様書

**更新日**: YYYY-MM-DD
**バージョン**: 1.0
**ベースURL**: `http://localhost:[PORT]`

## 概要

このドキュメントは、[サービス名]が提供するAPIエンドポイントの仕様を定義します。

## 認証

### 認証方式
- **方式**: Bearer Token (JWT)
- **ヘッダー**: `Authorization: Bearer {token}`

### 認証不要のエンドポイント
- `GET /health`
- `POST /auth/login`

## 共通仕様

### リクエストヘッダー
```
Content-Type: application/json
Authorization: Bearer {JWT_TOKEN}
```

### レスポンス形式

#### 成功時
```json
{
  "data": { ... },
  "message": "Success",
  "timestamp": "2025-09-30T12:00:00Z"
}
```

#### エラー時
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "エラーメッセージ",
    "details": { ... }
  },
  "timestamp": "2025-09-30T12:00:00Z"
}
```

### ステータスコード
| コード | 意味 | 使用例 |
|-------|------|--------|
| 200 | OK | 成功 |
| 201 | Created | リソース作成成功 |
| 400 | Bad Request | リクエストエラー |
| 401 | Unauthorized | 認証エラー |
| 403 | Forbidden | 権限エラー |
| 404 | Not Found | リソースが存在しない |
| 500 | Internal Server Error | サーバーエラー |

## エンドポイント一覧

### 1. [エンドポイント名]

#### 基本情報
- **メソッド**: `GET`
- **パス**: `/api/v1/resource`
- **認証**: 必要
- **説明**: [エンドポイントの説明]

#### リクエスト

##### パスパラメータ
| パラメータ名 | 型 | 必須 | 説明 |
|------------|----|----|------|
| `id` | string | ✓ | リソースID |

##### クエリパラメータ
| パラメータ名 | 型 | 必須 | デフォルト | 説明 |
|------------|----|----|----------|------|
| `page` | integer | - | 1 | ページ番号 |
| `limit` | integer | - | 10 | 1ページあたりの件数 |

##### リクエストボディ
```json
{
  "field1": "string",
  "field2": 123,
  "field3": true
}
```

**スキーマ定義**:
| フィールド名 | 型 | 必須 | 説明 |
|------------|----|----|------|
| `field1` | string | ✓ | フィールド1の説明 |
| `field2` | integer | - | フィールド2の説明 |

#### レスポンス

##### 成功時（200 OK）
```json
{
  "data": {
    "id": "123",
    "name": "example",
    "created_at": "2025-09-30T12:00:00Z"
  },
  "message": "Success"
}
```

##### エラー時（400 Bad Request）
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "バリデーションエラー",
    "details": {
      "field1": "必須項目です"
    }
  }
}
```

#### サンプルコード

##### cURL
```bash
curl -X GET "http://localhost:8000/api/v1/resource?page=1&limit=10" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

##### JavaScript (fetch)
```javascript
const response = await fetch('http://localhost:8000/api/v1/resource?page=1&limit=10', {
  method: 'GET',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json'
  }
});
const data = await response.json();
```

##### Python (requests)
```python
import requests

headers = {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json'
}
response = requests.get(
    'http://localhost:8000/api/v1/resource',
    params={'page': 1, 'limit': 10},
    headers=headers
)
data = response.json()
```

---

## エラーコード一覧

| エラーコード | HTTPステータス | 説明 | 対処方法 |
|------------|--------------|------|---------|
| `VALIDATION_ERROR` | 400 | バリデーションエラー | リクエストパラメータを確認 |
| `UNAUTHORIZED` | 401 | 認証エラー | トークンを確認 |
| `FORBIDDEN` | 403 | 権限不足 | 権限を確認 |
| `NOT_FOUND` | 404 | リソースが存在しない | IDを確認 |

## レート制限

- **制限**: 100リクエスト/分
- **ヘッダー**:
  - `X-RateLimit-Limit`: 制限値
  - `X-RateLimit-Remaining`: 残り回数
  - `X-RateLimit-Reset`: リセット時刻（Unix時間）

## 変更履歴

| バージョン | 日付 | 変更内容 |
|----------|------|---------|
| 1.0 | YYYY-MM-DD | 初版作成 |

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [データモデル](./03-data-models.md)
- [OpenAPI仕様](../09-api-contracts/openapi/)

---

**作成者**: [名前]
**最終更新**: YYYY-MM-DD