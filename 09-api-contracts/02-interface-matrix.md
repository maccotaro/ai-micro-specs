# エンドポイント対応表

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [Auth Service API](#auth-service-api)
- [User API](#user-api)
- [Admin API](#admin-api)
- [Frontend BFF API](#frontend-bff-api)

---

## 概要

全サービスのAPIエンドポイント一覧と対応関係を示します。

---

## Auth Service API

### ベースURL
```
http://localhost:8002/api/v1
```

### エンドポイント一覧

| メソッド | パス | 説明 | 認証 |
|---------|------|------|------|
| POST | /auth/register | ユーザー登録 | 不要 |
| POST | /auth/login | ログイン | 不要 |
| POST | /auth/refresh | トークンリフレッシュ | リフレッシュトークン |
| POST | /auth/logout | ログアウト | 必要 |
| POST | /auth/verify | トークン検証 | 必要 |
| GET | /.well-known/jwks.json | JWKS取得 | 不要 |

---

## User API

### ベースURL
```
http://localhost:8001/api/v1
```

### エンドポイント一覧

| メソッド | パス | 説明 | 認証 | 権限 |
|---------|------|------|------|------|
| GET | /profiles/me | 自分のプロフィール取得 | 必要 | user, admin |
| PUT | /profiles/me | 自分のプロフィール更新 | 必要 | user, admin |
| GET | /profiles/{user_id} | 特定ユーザープロフィール取得 | 必要 | admin |
| PUT | /profiles/{user_id} | 特定ユーザープロフィール更新 | 必要 | admin |
| GET | /health | ヘルスチェック | 不要 | - |

---

## Admin API

### ベースURL
```
http://localhost:8003/api/v1
```

### エンドポイント一覧

| メソッド | パス | 説明 | 認証 | 権限 |
|---------|------|------|------|------|
| GET | /documents | ドキュメント一覧 | 必要 | admin |
| POST | /documents | ドキュメントアップロード | 必要 | admin |
| GET | /documents/{id} | ドキュメント詳細取得 | 必要 | admin |
| DELETE | /documents/{id} | ドキュメント削除 | 必要 | admin |
| POST | /documents/{id}/ocr | OCR処理実行 | 必要 | admin |
| GET | /documents/{id}/ocr | OCR結果取得 | 必要 | admin |
| GET | /users | ユーザー一覧（管理用） | 必要 | admin |
| DELETE | /users/{user_id} | ユーザー削除 | 必要 | admin |
| GET | /health | ヘルスチェック | 不要 | - |

---

## Frontend BFF API

### User Frontend BFF
```
http://localhost:3002/api
```

| メソッド | パス | 説明 | プロキシ先 |
|---------|------|------|----------|
| POST | /auth/login | ログイン | Auth Service |
| POST | /auth/logout | ログアウト | Auth Service |
| POST | /auth/refresh | トークンリフレッシュ | Auth Service |
| GET | /profile | プロフィール取得 | User API |
| PUT | /profile | プロフィール更新 | User API |

### Admin Frontend BFF
```
http://localhost:3003/api
```

| メソッド | パス | 説明 | プロキシ先 |
|---------|------|------|----------|
| POST | /auth/login | ログイン | Auth Service |
| POST | /auth/logout | ログアウト | Auth Service |
| GET | /profile | プロフィール取得 | User API |
| GET | /documents | ドキュメント一覧 | Admin API |
| POST | /documents | ドキュメントアップロード | Admin API |
| GET | /documents/{id} | ドキュメント詳細 | Admin API |
| POST | /documents/{id}/ocr | OCR処理 | Admin API |
| GET | /users | ユーザー一覧 | Admin API |

---

## 関連ドキュメント

- [Auth Service API仕様](../01-auth-service/02-api-specification.md)
- [データモデル定義](./03-data-models.md)
- [OpenAPI統合](./04-openapi-integration.md)