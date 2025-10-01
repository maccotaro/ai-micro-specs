# [2025-10-01] - 階層構造ID生成の修正

**更新日**: 2025-10-01
**影響範囲**: Admin API Service, Admin Frontend
**担当者**: Claude Code

## 問題

ドキュメント処理において、`HierarchyConverter`が各ページで新しいインスタンスを作成していたため、要素IDがページごとにリセットされる問題が発生していました。

### 問題の詳細

**発生前の動作**:
```
ページ1: ID-1, ID-2, ID-3, ...
ページ2: ID-1, ID-2, ID-3, ...  ← IDがリセット
ページ3: ID-1, ID-2, ID-3, ...  ← IDがリセット
```

**原因**:
- `HierarchyConverter`インスタンスがページ処理ごとに作成されていた
- `global_element_counter`がページごとにリセットされていた
- ドキュメント全体で一意のIDが生成されていなかった

## 解決策

### 1. Backend修正

**ファイル**: `ai-micro-api-admin/app/core/document_processing/base.py`

**変更内容**:
- ドキュメント処理全体で共有される`HierarchyConverter`インスタンスを作成
- ページごとのインスタンス作成を削除し、共有インスタンスを使用

**修正前**:
```python
# 各ページで新しいインスタンスを作成（問題）
for page_data in pages:
    converter = HierarchyConverter()  # ← ここでリセット
    hierarchical = converter.convert(elements)
```

**修正後**:
```python
# ドキュメント全体で共有インスタンスを使用
converter = HierarchyConverter()  # ← 一度だけ作成

for page_data in pages:
    hierarchical = converter.convert(elements)  # ← 共有インスタンス使用
```

### 2. Frontend修正

**ファイル**: `ai-micro-front-admin/src/pages/documents/ocr/[id].tsx`

**変更内容**:
- ページベースのID生成ロジック削除
- バックエンドから返される`hierarchical_elements`のIDを直接使用

**修正前**:
```typescript
// フロントエンドでページベースID生成（削除）
const elementId = `ID-${pageNumber * 1000 + elementIndex}`;
```

**修正後**:
```typescript
// バックエンド生成のIDを直接使用
const elementId = element.id;  // hierarchical_elementsから取得
```

## 影響

### 修正後の動作

**正しい動作**:
```
ページ1: ID-1, ID-2, ID-3, ...
ページ2: ID-4, ID-5, ID-6, ...  ← 連番で継続
ページ3: ID-7, ID-8, ID-9, ...  ← 連番で継続
```

### メリット

1. **一意性の保証**: ドキュメント全体で一意のIDが生成される
2. **要素の追跡**: 要素を一意に識別できる
3. **データ整合性**: バックエンドとフロントエンドでID管理が統一される

### 影響範囲

- **Admin API Service**: ドキュメント処理ロジック
- **Admin Frontend**: OCR結果表示UI
- **既存データ**: 影響なし（新規アップロード時から適用）

## テスト方法

### 1. 新規ドキュメントのアップロード

```bash
# 管理画面にログイン
curl -X POST http://localhost:8003/login

# 複数ページのPDFをアップロード
curl -X POST http://localhost:8003/documents/upload \
  -F "file=@multi-page.pdf"
```

### 2. 結果確認

```bash
# ドキュメント詳細を取得
curl http://localhost:8003/documents/{document_id}

# hierarchical_elementsのIDを確認
# ページ1: ID-1, ID-2, ...
# ページ2: ID-4, ID-5, ... (連番であることを確認)
```

### 3. Frontend確認

- 管理画面でドキュメントを表示
- 各要素のIDがページをまたいで連番になっていることを確認

## 関連ドキュメント

- [Admin API - ドキュメント処理](../03-admin-api/03-document-processing.md)
- [Admin API - OCR設計](../03-admin-api/04-ocr-design.md)
- [Admin API - 階層変換](../03-admin-api/05-hierarchy-converter.md)
- [Admin Frontend - ドキュメント管理](../05-admin-frontend/07-document-management.md)
- [Admin Frontend - OCR UI設計](../05-admin-frontend/08-ocr-ui-design.md)

## 関連コミット

```bash
# コミット例
git log --oneline --grep="hierarchy"
```

---

**最終更新**: 2025-10-01
**ステータス**: ✅ 完了