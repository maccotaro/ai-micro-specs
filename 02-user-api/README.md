# 02. ユーザーAPI（ai-micro-api-user）

ユーザープロフィール管理を担当するバックエンドサービスの設計ドキュメント。

## 📄 ドキュメント

- `01-overview.md` - サービス概要
- `02-api-specification.md` - API仕様（プロフィール取得・更新）
- `03-database-design.md` - apidb データベース設計
- `04-data-consistency.md` - authdbとの整合性管理

## 🔗 連携

- PostgreSQL (apidb), Redis, Auth Service (JWKS)

**Port**: 8001