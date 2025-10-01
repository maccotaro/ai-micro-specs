# 変更履歴

このファイルには、ai-micro-serviceプロジェクトの重要な変更履歴を記録します。

## 記録形式

各変更は以下の形式で記録されます：

```
## [日付] - [変更のタイトル]

**影響範囲**: [サービス名]
**担当者**: [名前]

### 問題
...

### 解決策
...

### 影響
...
```

---

## [2025-10-01] - 階層構造ID生成の修正

**影響範囲**: Admin API Service, Admin Frontend
**担当者**: Claude Code

### 問題

`HierarchyConverter`が各ページで新しいインスタンスを作成していたため、要素IDがページごとにリセットされていた。

- **発生前**: ページ1: ID-1,2,3... ページ2: ID-1,2,3...
- **問題点**: ドキュメント全体で一意のIDが生成されていない

### 解決策

**Backend修正** (`ai-micro-api-admin/app/core/document_processing/base.py`):
- ドキュメント処理全体で共有される`HierarchyConverter`インスタンスを作成
- ページごとのインスタンス作成を削除

**Frontend修正** (`ai-micro-front-admin/src/pages/documents/ocr/[id].tsx`):
- ページベースのID生成ロジック削除
- バックエンドから返される`hierarchical_elements`のIDを直接使用

### 影響

- **発生後**: ページ1: ID-1,2,3... ページ2: ID-4,5,6... ページ3: ID-7,8,9...
- ドキュメント全体で連番のIDが正しく生成される

### 関連ドキュメント

- [Admin API - OCR設計](../03-admin-api/04-ocr-design.md)
- [Admin API - 階層変換](../03-admin-api/05-hierarchy-converter.md)
- [Admin Frontend - OCR UI設計](../05-admin-frontend/08-ocr-ui-design.md)

---

## [2025-09-30] - ドキュメント体系構築完了

**影響範囲**: 全体
**担当者**: Claude Code

### 実施内容

ai-micro-serviceプロジェクトの包括的なドキュメント体系を構築：

- **Phase 1**: 基本構造とテンプレート作成
- **Phase 2-A**: 優先度高（23ファイル）- 完了
- **Phase 2-B**: 優先度中（40ファイル）- 完了
- **Phase 2-C**: 優先度低（46ファイル）- 完了

### 作成ドキュメント

**合計109ファイル作成**:

- 00-overview/ (4ファイル)
- 01-auth-service/ (5ファイル)
- 02-user-api/ (4ファイル)
- 03-admin-api/ (6ファイル)
- 04-user-frontend/ (7ファイル)
- 05-admin-frontend/ (8ファイル)
- 06-database/ (10ファイル)
- 07-redis/ (10ファイル)
- 08-integration/ (7ファイル)
- 09-api-contracts/ (7ファイル)
- 10-security/ (10ファイル)
- 11-operations/ (9ファイル)
- 12-development/ (6ファイル)
- 13-deployment/ (5ファイル)
- 14-performance/ (5ファイル)
- 15-testing/ (6ファイル)

### 今後の予定

- **Phase 3**: 図表作成（シーケンス図、ER図等）
- **Phase 4**: レビュー・改善

---

## 変更記録テンプレート

新しい変更を記録する際は、以下のテンプレートをコピーして使用してください：

```markdown
## [YYYY-MM-DD] - [変更タイトル]

**影響範囲**: [サービス名]
**担当者**: [名前]

### 問題

[何が問題だったか]

### 解決策

[どのように解決したか]

### 影響

[変更による影響範囲と効果]

### 関連ドキュメント

- [リンク1](../path/to/doc.md)
- [リンク2](../path/to/doc.md)
```

---

**最終更新**: 2025-09-30