# 06. データベースインフラ（ai-micro-postgres）

PostgreSQLデータベースの設計と管理に関するドキュメント。

## 📄 ドキュメント

- `01-overview.md` - PostgreSQL概要
- `02-database-configuration.md` - データベース構成
- `03-schema-design-overview.md` - スキーマ設計概要
- `04-authdb-schema.md` - authdb スキーマ詳細
- `05-apidb-schema.md` - apidb スキーマ詳細
- `06-admindb-schema.md` - admindb スキーマ詳細
- `07-er-diagram.md` - ER図（全体）
- `08-cross-database-relations.md` - DB間の論理的関連
- `09-migration-management.md` - マイグレーション管理
- `10-backup-restore.md` - バックアップ・リストア

## 🗄️ データベース

- **authdb** - 認証情報
- **apidb** - ユーザープロフィール
- **admindb** - ドキュメント・OCR結果

**Port**: 5432