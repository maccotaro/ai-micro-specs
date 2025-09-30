# 03. 管理API（ai-micro-api-admin）

管理機能とドキュメント処理・OCRを担当するバックエンドサービスの設計ドキュメント。

## 📄 ドキュメント

- `01-overview.md` - サービス概要
- `02-api-specification.md` - API仕様
- `03-document-processing.md` - ドキュメント処理設計
- `04-ocr-design.md` - OCR機能設計
- `05-hierarchy-converter.md` - 階層構造変換（ID生成含む）
- `06-database-design.md` - admindb データベース設計

## 🔗 連携

- PostgreSQL (admindb), Redis, Auth Service (JWKS)

**Port**: 8003