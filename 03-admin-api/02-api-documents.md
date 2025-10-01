# Admin API - ドキュメント処理API仕様

**カテゴリ**: Backend Service API
**バージョン**: 1.0.0
**最終更新**: 2025-10-01

## 目次
- [概要](#概要)
- [ドキュメントアップロード](#ドキュメントアップロード)
- [ドキュメント管理](#ドキュメント管理)
- [ドキュメント処理](#ドキュメント処理)
- [OCRメタデータ管理](#ocrメタデータ管理)
- [画像処理](#画像処理)
- [ベクトル化・RAG処理](#ベクトル化rag処理)
- [メンテナンス機能](#メンテナンス機能)

---

## 概要

ドキュメント処理APIは、PDF文書のアップロード、OCR処理、メタデータ管理、画像抽出、ベクトル化を提供します。

**ベースURL**: `/admin/documents`

**主要機能**:
- PDFアップロードとDocling処理
- OCRメタデータのCRUD操作
- 画像切り出しと保存
- ベクトル化・RAG処理
- 孤立ドキュメントのクリーンアップ

---

## ドキュメントアップロード

### POST /admin/documents/upload

PDFファイルをアップロードし、データベースレコードを作成します。

**認証**: `admin` 必須

#### リクエスト: Multipart Form Data

| フィールド | 型 | 必須 | 説明 |
|-----------|---|------|------|
| `file` | File | ○ | PDFファイル（最大50MB） |
| `knowledge_base_id` | string | × | ナレッジベースID（UUID） |
| `is_public` | boolean | × | 公開フラグ（デフォルト: false） |
| `category` | string | × | カテゴリ |
| `tags` | string | × | タグ配列のJSON文字列 |

#### TypeScript Interface

```typescript
interface DocumentResponse {
  id: string;                    // UUID
  original_filename: string;     // 元のファイル名
  filename: string;              // 保存ファイル名
  file_path: string;             // ファイルパス
  file_size: number;             // ファイルサイズ（バイト）
  mime_type: string;             // MIMEタイプ
  status: DocumentStatus;        // "uploaded" | "processing" | "completed" | "failed"
  knowledge_base_id?: string;    // ナレッジベースID
  user_id: string;               // アップロードユーザーID
  is_public: boolean;            // 公開フラグ
  category?: string;             // カテゴリ
  tags?: string[];               // タグ配列
  page_count?: number;           // ページ数
  created_at: string;            // ISO日時
  updated_at: string;            // ISO日時
}

// 使用例
async function uploadDocument(file: File, knowledgeBaseId?: string) {
  const formData = new FormData();
  formData.append('file', file);
  if (knowledgeBaseId) {
    formData.append('knowledge_base_id', knowledgeBaseId);
  }

  const response = await fetch('/api/admin/documents/upload', {
    method: 'POST',
    credentials: 'include',
    body: formData
  });

  if (!response.ok) throw new Error('Upload failed');
  return response.json() as Promise<DocumentResponse>;
}
```

---

## ドキュメント管理

### GET /admin/documents

ドキュメント一覧を取得します（ページネーション・フィルタリング対応）。

**認証**: `get_current_user` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `page` | number | 1 | ページ番号 |
| `limit` | number | 20 | 1ページあたりの件数（最大100） |
| `knowledge_base_id` | string | - | ナレッジベースIDでフィルタ |
| `status` | string | - | ステータスでフィルタ |
| `search` | string | - | ファイル名で検索 |
| `category` | string | - | カテゴリでフィルタ |
| `is_public` | boolean | - | 公開/非公開フィルタ |
| `user_id` | string | - | ユーザーIDでフィルタ（admin専用） |
| `document_type` | string | - | `knowledge_base`, `standalone`, `all` |

#### TypeScript Interface

```typescript
interface DocumentListResponse {
  documents: DocumentResponse[];
  total: number;                 // 総件数
  page: number;                  // 現在のページ
  limit: number;                 // ページサイズ
  pages: number;                 // 総ページ数
}

// 使用例
const result = await fetch(
  '/api/admin/documents?page=1&limit=20&status=completed&search=report'
).then(r => r.json()) as DocumentListResponse;
```

### GET /admin/documents/{document_id}

特定のドキュメント情報を取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `document_id` (UUID)

**レスポンス**: `DocumentResponse`

### PUT /admin/documents/{document_id}

ドキュメント情報を更新します。

**認証**: `get_current_user` 必須

#### リクエストボディ

```typescript
interface DocumentUpdate {
  category?: string;
  tags?: string[];
  is_public?: boolean;
  status?: DocumentStatus;
}

// 使用例
await fetch(`/api/admin/documents/${documentId}`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    category: 'reports',
    tags: ['Q4', '2025'],
    is_public: false
  })
});
```

### DELETE /admin/documents/{document_id}

ドキュメントと関連ファイルを削除します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `document_id` (UUID)

```typescript
await fetch(`/api/admin/documents/${documentId}`, {
  method: 'DELETE'
});
```

### GET /admin/documents/stats/summary

ドキュメント統計情報を取得します。

**認証**: `get_current_user` 必須

```typescript
interface DocumentStats {
  total_documents: number;
  by_status: Record<DocumentStatus, number>;
  total_storage_bytes: number;
  by_category: Record<string, number>;
}
```

### GET /admin/documents/status

ドキュメント処理サービスのステータスを取得します。

**認証**: `admin` 必須

```typescript
interface ProcessingStatus {
  status: "ready" | "error";
  message: string;
  mode: "docling_with_fallback" | "fallback_only";
  output_directory: string;
  cache_directories: {
    easyocr: string;
    docling: string;
  };
}
```

---

## ドキュメント処理

### POST /admin/documents/{document_id}/process

既存ドキュメントの処理を開始します（バックグラウンドジョブ）。

**認証**: `admin` 必須

**パスパラメータ**: `document_id` (UUID)

```typescript
interface ProcessJobResponse {
  job_id: string;                // ジョブID
  message: string;               // 処理開始メッセージ
  status: "pending" | "running"; // ジョブステータス
}

// 使用例
const job = await fetch(`/api/admin/documents/${documentId}/process`, {
  method: 'POST'
}).then(r => r.json()) as ProcessJobResponse;

// ジョブステータスを確認
const status = await fetch(`/api/admin/jobs/${job.job_id}`)
  .then(r => r.json());
```

### POST /admin/documents/{document_id}/upload-structured-json

構造化JSONメタデータをアップロードします。

**認証**: `get_current_user` 必須

**リクエストボディ**: JSON形式のメタデータ

---

## OCRメタデータ管理

### GET /admin/documents/{document_id}/ocr-metadata

OCRメタデータを取得します（優先順位: edited > original > filesystem）。

**認証**: `get_current_user` 必須

#### レスポンス

```typescript
interface OCRMetadataResponse {
  document_id: string;           // UUID
  metadata: any;                 // metadata_hierarchy.jsonの内容
  source: "edited" | "original" | "filesystem"; // メタデータソース
  is_edited: boolean;            // 編集済みフラグ
  output_directory?: string;     // 出力ディレクトリパス
}

// 使用例
const ocrData = await fetch(
  `/api/admin/documents/${documentId}/ocr-metadata`
).then(r => r.json()) as OCRMetadataResponse;
```

### PUT /admin/documents/{document_id}/ocr-metadata

OCRメタデータを更新します。

**認証**: `get_current_user` 必須

#### リクエストボディ

```typescript
interface OCRMetadataUpdateRequest {
  metadata: any;                 // 更新後のメタデータ
}

interface OCRMetadataUpdateResponse {
  success: boolean;
  message: string;
  document_id: string;
  updated_at: string;            // ISO日時
}

// 使用例
await fetch(`/api/admin/documents/${documentId}/ocr-metadata`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    metadata: updatedMetadata
  })
});
```

### POST /admin/documents/{document_id}/ocr-region

指定領域のOCR処理を実行します。

**認証**: `get_current_user` 必須

```typescript
interface OCRRegionRequest {
  page_number: number;
  bbox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

interface OCRRegionResponse {
  text: string;                  // 抽出テキスト
  confidence?: number;           // 信頼度（0-1）
}
```

---

## 画像処理

### GET /admin/documents/{document_id}/image

ドキュメント画像を取得します（複数パス解決戦略でフォールバック対応）。

**認証**: `get_current_user` 必須

**クエリパラメータ**:
- `path` (string): 画像の相対パス（例: `figures/figure_1.png`）

```typescript
// 画像URL生成
function getDocumentImageUrl(documentId: string, imagePath: string): string {
  return `/api/admin/documents/${documentId}/image?path=${encodeURIComponent(imagePath)}`;
}

// React使用例
<img
  src={getDocumentImageUrl(docId, 'figures/figure_1.png')}
  alt="Figure 1"
/>
```

### GET /admin/documents/{document_id}/images/{image_name}

ドキュメント画像を取得します（旧形式、後方互換性のため維持）。

**認証**: `get_current_user` 必須

**パスパラメータ**: `image_name` (例: `page_1_full.png`)

### GET /admin/documents/{document_id}/cropped/{filename}

切り出し画像を取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `filename` (例: `cropped_1234567890.png`)

### POST /admin/documents/{document_id}/crop-image

画像を切り出します。

**認証**: `get_current_user` 必須

#### リクエストボディ

```typescript
interface CropImageRequest {
  image_path: string;            // 元画像パス
  bbox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  output_filename?: string;      // 出力ファイル名
}

interface CropImageResponse {
  success: boolean;
  cropped_image_path: string;    // 切り出し画像パス
  message: string;
}
```

### POST /admin/documents/{document_id}/save-cropped-image

Base64画像を保存します。

**認証**: `get_current_user` 必須

#### リクエストボディ

```typescript
interface SaveCroppedImageRequest {
  image_data: string;            // Base64エンコード画像データ
  element_id: string;            // 要素ID
  bbox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

interface SaveCroppedImageResponse {
  success: boolean;
  image_path: string;            // 保存画像パス
  message: string;
}
```

---

## ベクトル化・RAG処理

### POST /admin/documents/{document_id}/vectorize

ドキュメントをベクトル化してナレッジベースに登録します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `document_id` (UUID)

```typescript
interface VectorizeResponse {
  success: boolean;
  message: string;
  chunks_created: number;        // 作成されたチャンク数
  knowledge_base_id: string;     // ナレッジベースID
}

// 使用例
const result = await fetch(
  `/api/admin/documents/${documentId}/vectorize`,
  { method: 'POST' }
).then(r => r.json()) as VectorizeResponse;
```

### POST /admin/documents/{document_id}/reprocess-rag

RAG処理を再実行します。

**認証**: `get_current_user` 必須

```typescript
interface ReprocessRAGResponse {
  success: boolean;
  message: string;
  chunks_updated: number;
}
```

---

## メンテナンス機能

**ベースURL**: `/admin/documents/maintenance`

### GET /admin/documents/maintenance/cleanup/orphaned

孤立ドキュメント（ファイルが存在しないレコード）を検索します。

**認証**: `admin` 必須

```typescript
interface OrphanedDocument {
  id: string;
  filename: string;
  reason: string;
  status: DocumentStatus;
}

interface OrphanedDocumentsResponse {
  orphaned_documents: OrphanedDocument[];
  total_found: number;
}

// 使用例
const orphaned = await fetch(
  '/api/admin/documents/maintenance/cleanup/orphaned'
).then(r => r.json()) as OrphanedDocumentsResponse;
```

### DELETE /admin/documents/maintenance/cleanup/orphaned/{document_id}

孤立ドキュメントレコードを削除します。

**認証**: `admin` 必須

**パスパラメータ**: `document_id` (UUID)

```typescript
await fetch(
  `/api/admin/documents/maintenance/cleanup/orphaned/${documentId}`,
  { method: 'DELETE' }
);
```

### POST /admin/documents/maintenance/cleanup/reset-processing

"processing"状態でスタックしたドキュメントを"uploaded"にリセットします。

**認証**: `admin` 必須

```typescript
interface ResetProcessingResponse {
  message: string;
  reset_count: number;
}

// 使用例
const result = await fetch(
  '/api/admin/documents/maintenance/cleanup/reset-processing',
  { method: 'POST' }
).then(r => r.json()) as ResetProcessingResponse;
```

---

## エラーレスポンス

### 標準エラー形式

```typescript
interface APIError {
  detail: string;                // エラー詳細メッセージ
}
```

### よくあるエラー

| コード | 説明 | 例 |
|-------|------|---|
| 400 | リクエスト不正 | ファイルサイズ超過、不正なUUID |
| 404 | リソース未発見 | ドキュメント・画像が存在しない |
| 413 | ファイルサイズ超過 | 50MB制限超過 |
| 500 | サーバーエラー | 処理失敗、ファイルシステムエラー |

---

## 関連ドキュメント

- [ドキュメント処理パイプライン](./03-document-processing.md)
- [OCR設計](./04-ocr-design.md)
- [階層構造変換](./05-hierarchy-converter.md)
- [ジョブ管理API](./02-api-jobs.md)
- [ナレッジベースAPI](./02-api-knowledge-bases.md)
