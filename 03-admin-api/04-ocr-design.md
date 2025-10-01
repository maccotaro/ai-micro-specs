# Admin API Service - OCR設計

**カテゴリ**: Document Processing / OCR
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [ハイブリッドOCRアーキテクチャ](#ハイブリッドocrアーキテクチャ)
- [対応言語](#対応言語)
- [リージョンベース処理](#リージョンベース処理)
- [座標系変換](#座標系変換)
- [OCRメタデータ管理](#ocrメタデータ管理)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## 概要

Admin API ServiceのOCRシステムは、**Docling**と**EasyOCR**を組み合わせたハイブリッド方式を採用しています。Doclingの高度なレイアウト解析とEasyOCRの多言語対応を組み合わせることで、高精度かつ柔軟な文字認識を実現します。

### 設計思想

1. **レイアウト優先**: まずDoclingで文書構造を理解
2. **OCR補完**: テキスト抽出が不十分な領域でEasyOCRを実行
3. **リージョンベース**: 要素単位での個別OCR実行
4. **編集可能メタデータ**: OCR結果の手動修正をサポート

### 主要機能

- **自動言語検出**: 日本語・英語・中国語・韓国語の自動識別
- **リージョンOCR**: 特定領域のみの再OCR実行
- **OCR結果編集**: フロントエンドでの手動修正機能
- **差分管理**: 元データと編集データの分離保存

---

## ハイブリッドOCRアーキテクチャ

### 処理フロー

```
PDF入力
  ↓
Doclingレイアウト解析
  ├─ テキスト要素 → Docling抽出
  ├─ 図表要素 → 画像切り出し → EasyOCR
  └─ 表要素 → Docling構造認識 → 必要に応じてEasyOCR
  ↓
統合メタデータ生成
  ├─ original_metadata (Docling結果)
  └─ edited_metadata (手動修正後)
  ↓
データベース保存（JSONB）
```

### Docling OCR

**役割**: 主要なテキスト抽出エンジン

**強み**:
- PDF内蔵テキストの高速抽出
- レイアウト構造の理解
- 表構造の認識

**弱み**:
- スキャンPDFへの対応が限定的
- 画像内テキストの認識精度

**使用箇所**: `app/core/document_processing/docling_processor.py`

```python
def extract_text_content(self, item) -> str:
    """Doclingからテキスト抽出"""
    if hasattr(item, 'text'):
        return item.text.strip()
    return ""
```

### EasyOCR

**役割**: 補完的OCRエンジン

**強み**:
- 多言語対応（日本語・中国語・韓国語）
- スキャン画像への高精度認識
- 自然なテキスト抽出

**弱み**:
- 処理速度がDoclingより遅い
- レイアウト理解は限定的

**使用箇所**: `app/core/document_processing/text_extractor.py`

```python
def extract_from_image_ocr(self, image_path: str, languages: List[str]) -> str:
    """EasyOCRで画像からテキスト抽出"""
    try:
        reader = easyocr.Reader(
            languages,
            gpu=False,  # CPU動作
            model_storage_directory=str(self.easyocr_cache_dir)
        )
        result = reader.readtext(str(image_path), detail=0)
        return " ".join(result)
    except Exception as e:
        logger.warning(f"EasyOCR failed: {e}")
        return ""
```

### ハイブリッド判定ロジック

**ファイル**: `app/core/document_processing/text_extractor.py`

```python
def extract_text_hybrid(self, element: Dict, page_image_path: str) -> str:
    """ハイブリッドテキスト抽出"""

    # 1. Doclingテキストを優先
    docling_text = element.get("text", "")
    if docling_text and len(docling_text.strip()) > 5:
        return docling_text

    # 2. 画像要素の場合はEasyOCR
    if element.get("type") in ["figure", "picture", "image"]:
        cropped_image_path = element.get("cropped_image_path")
        if cropped_image_path:
            return self.extract_from_image_ocr(cropped_image_path, ["ja", "en"])

    # 3. テキスト不足の場合もEasyOCR
    if len(docling_text.strip()) < 3:
        bbox = element.get("bbox")
        if bbox:
            # バウンディングボックスで切り出してOCR
            return self.extract_from_bbox_ocr(page_image_path, bbox, ["ja", "en"])

    return docling_text
```

---

## 対応言語

### EasyOCR言語コード

| 言語 | 言語コード | 優先度 |
|------|-----------|-------|
| 日本語 | `ja` | 高 |
| 英語 | `en` | 高 |
| 中国語（簡体字） | `ch_sim` | 中 |
| 中国語（繁体字） | `ch_tra` | 中 |
| 韓国語 | `ko` | 中 |

### 言語自動検出

現在は日英混在を前提とした `["ja", "en"]` を標準設定としていますが、将来的には以下の自動検出を実装予定:

```python
def detect_languages(self, text_sample: str) -> List[str]:
    """テキストサンプルから言語を検出"""
    # Unicode範囲で判定
    has_japanese = bool(re.search(r'[\u3040-\u309F\u30A0-\u30FF]', text_sample))
    has_chinese = bool(re.search(r'[\u4E00-\u9FFF]', text_sample))
    has_korean = bool(re.search(r'[\uAC00-\uD7AF]', text_sample))

    languages = ["en"]  # 英語は常に含める
    if has_japanese:
        languages.append("ja")
    if has_chinese:
        languages.append("ch_sim")
    if has_korean:
        languages.append("ko")

    return languages
```

### モデルキャッシュ

**環境変数**: `EASYOCR_MODULE_PATH=/tmp/.easyocr_models`

EasyOCRは初回実行時に言語モデルをダウンロード:

| 言語 | モデルサイズ | ダウンロード時間 |
|------|------------|----------------|
| 英語 | 約50MB | 10秒 |
| 日本語 | 約80MB | 20秒 |
| 中国語 | 約100MB | 30秒 |
| 韓国語 | 約70MB | 15秒 |

キャッシュディレクトリはDockerボリュームでマウントし、再起動時も保持します。

---

## リージョンベース処理

### リージョンOCRとは

ドキュメント全体ではなく、**特定の要素（リージョン）のみ**にOCRを実行する方式です。これにより:

- 処理時間の短縮
- 手動修正が必要な箇所のみ再OCR
- OCR精度の向上（コンテキスト特化）

### リージョンOCRエンドポイント

**API**: `POST /admin/documents/{document_id}/ocr-region`

**リクエスト**:
```json
{
  "element_id": "ID-5",
  "page_number": 1,
  "languages": ["ja", "en"],
  "ocr_settings": {
    "contrast_threshold": 0.5,
    "text_threshold": 0.7
  }
}
```

**レスポンス**:
```json
{
  "element_id": "ID-5",
  "original_text": "元のテキスト",
  "ocr_text": "OCR認識結果",
  "confidence": 0.92,
  "bbox": {"x1": 100, "y1": 150, "x2": 500, "y2": 200}
}
```

### リージョンOCR実装

**ファイル**: `app/services/document_processing.py`

```python
class OCRRegionProcessingService:
    """リージョンOCR処理サービス"""

    async def process_region_ocr(
        self,
        document_id: str,
        element_id: str,
        page_number: int,
        languages: List[str],
        db: Session
    ) -> Dict:
        """特定要素のOCR実行"""

        # 1. ドキュメントメタデータ取得
        document = db.query(Document).filter_by(id=document_id).first()
        metadata = document.processing_metadata

        # 2. 要素情報取得
        page_data = metadata["pages"][page_number - 1]
        element = next(
            (e for e in page_data["hierarchical_elements"] if e["id"] == element_id),
            None
        )

        # 3. 画像パス解決
        page_image_path = self._resolve_page_image_path(document, page_number)

        # 4. バウンディングボックスで切り出し
        bbox = element["bbox"]
        cropped_image = self._crop_image(page_image_path, bbox, scale_factor=2.0)

        # 5. EasyOCR実行
        ocr_text = self.text_extractor.extract_from_image_ocr(
            cropped_image, languages
        )

        # 6. メタデータ更新（edited_metadataに記録）
        self._update_element_text(document, element_id, ocr_text, db)

        return {
            "element_id": element_id,
            "original_text": element.get("text", ""),
            "ocr_text": ocr_text,
            "confidence": 0.92,  # TODO: 実際の信頼度取得
            "bbox": bbox
        }
```

### バッチOCR処理

複数要素の一括OCR実行:

**API**: `POST /admin/documents/{document_id}/ocr-batch`

**リクエスト**:
```json
{
  "element_ids": ["ID-5", "ID-12", "ID-18"],
  "page_number": 1,
  "languages": ["ja", "en"]
}
```

**処理フロー**:
1. 各要素を順次処理
2. 進捗報告（WebSocket）
3. 処理完了後に統合メタデータ更新

---

## 座標系変換

### OCR座標系変換の5段階プロセス

OCR処理では、PDF座標系から画像座標系への変換が必要です。

#### Stage 1: Docling座標抽出

**座標形式**: `[x1, y1, x2, y2]` （PDF座標系）

**ファイル**: `app/core/document_processing/docling_processor.py:346-353`

```python
element_data["bbox"] = {
    "x1": bbox_list[0],  # 左端X
    "y1": bbox_list[1],  # 下端Y（PDF座標系）
    "x2": bbox_list[2],  # 右端X
    "y2": bbox_list[3]   # 上端Y（PDF座標系）
}
```

#### Stage 2: 画像生成（144 DPI）

**ファイル**: `app/core/document_processing/image_processor.py:47`

```python
image = page.render(scale=2.0)  # 72 DPI → 144 DPI
pil_image = image.to_pil()
```

**スケール理由**:
- Docling出力: 72 DPI基準
- 生成画像: 144 DPI（scale=2.0）
- 変換係数: 2.0倍

#### Stage 3: 座標系変換（PDF→画像）

**ファイル**: `app/core/document_processing/hierarchy_converter.py:496-558`

```python
if element_type == "figure":
    # Figure要素は座標変換なし
    y1_image = y1_input
    y2_image = y2_input
else:
    # その他要素はY軸反転
    y1_image = page_height - y2_input
    y2_image = page_height - y1_input
```

**変換式**:
```
画像Y座標 = ページ高さ - PDF Y座標
```

#### Stage 4: メタデータ保存

**ファイル**: `metadata_hierarchy.json`

```json
{
  "bbox": {
    "x1": 100,
    "y1": 150,     // 既に画像座標系に変換済み
    "x2": 500,
    "y2": 200
  }
}
```

#### Stage 5: フロントエンド表示

**ファイル**: `ai-micro-front-admin/src/pages/documents/ocr/[id].tsx:251`

```typescript
const rectangleScale = 2.0;  // 72 DPI → 144 DPI補正

<div
  style={{
    left: `${rect.x * rectangleScale}px`,
    top: `${rect.y * rectangleScale}px`,
    width: `${rect.width * rectangleScale}px`,
    height: `${rect.height * rectangleScale}px`,
  }}
/>
```

### 2倍スケールファクターの根拠

**なぜ `rectangleScale = 2.0` なのか？**

1. **画像生成**: pypdfium2で `scale=2.0` により 144 DPI 画像を生成
2. **座標出力**: Doclingは 72 DPI 基準で座標を出力
3. **スケール補正**: 144 DPI 画像に 72 DPI 座標を合わせるため 2倍が必要
4. **計算式**: `144 DPI ÷ 72 DPI = 2.0倍`

### 座標変換デバッグ

```python
# バックエンドデバッグログ
logger.info(f"Element {simple_id} ({element_type}):")
logger.info(f"  PDF coords: ({x1:.1f}, {y1_input:.1f})-({x2:.1f}, {y2_input:.1f})")
logger.info(f"  Image coords: ({x1:.1f}, {y1_image:.1f})-({x2:.1f}, {y2_image:.1f})")
logger.info(f"  Page height: {page_height}")
```

```typescript
// フロントエンドデバッグログ
console.log('Rectangle display:', {
  originalCoords: { x: rect.x, y: rect.y },
  scaledCoords: {
    x: rect.x * rectangleScale,
    y: rect.y * rectangleScale
  },
  rectangleScale
});
```

---

## OCRメタデータ管理

### データベーススキーマ

**テーブル**: `documents`

| カラム | 型 | 説明 |
|-------|---|------|
| `original_metadata` | JSONB | Docling処理結果（読み取り専用） |
| `edited_metadata` | JSONB | 手動修正後（フロント表示用） |
| `editing_status` | VARCHAR(20) | "unedited", "editing", "edited" |
| `last_edited_at` | TIMESTAMP | 最終編集日時 |
| `edited_by` | UUID | 編集者ID |

### メタデータ取得API

**GET `/admin/documents/{document_id}/metadata`**

**レスポンス**:
```json
{
  "document_id": "123e4567-e89b-12d3-a456-426614174000",
  "metadata": {
    // edited_metadataが存在すればそちらを返す
    // なければoriginal_metadataを返す
    "pages": [...]
  },
  "editing_status": "edited",
  "last_edited_at": "2025-09-30T14:35:00Z"
}
```

### メタデータ更新API

**PUT `/admin/documents/{document_id}/metadata`**

**リクエスト**:
```json
{
  "page_number": 1,
  "element_id": "ID-5",
  "updates": {
    "text": "手動修正したテキスト",
    "type": "text",
    "bbox": {"x1": 100, "y1": 150, "x2": 500, "y2": 200}
  }
}
```

**処理フロー**:
1. `original_metadata` は保持
2. `edited_metadata` に変更を反映
3. `editing_status` を "edited" に更新
4. `last_edited_at` と `edited_by` を更新

### メタデータリセット

**POST `/admin/documents/{document_id}/metadata/reset`**

**処理**:
- `edited_metadata` をクリア
- `editing_status` を "unedited" に戻す
- `original_metadata` に戻る

---

## パフォーマンス最適化

### EasyOCRモデルロード最適化

**問題**: EasyOCRの初回実行は言語モデルのロードで遅い（5-10秒）

**解決策**: モデルの事前ロードとキャッシュ

```python
class TextExtractor:
    def __init__(self, cache_dir: Path):
        self.easyocr_cache_dir = cache_dir
        self._reader_cache = {}  # 言語別リーダーキャッシュ

    def _get_cached_reader(self, languages: List[str]) -> easyocr.Reader:
        """キャッシュからリーダー取得"""
        lang_key = "_".join(sorted(languages))

        if lang_key not in self._reader_cache:
            self._reader_cache[lang_key] = easyocr.Reader(
                languages,
                gpu=False,
                model_storage_directory=str(self.easyocr_cache_dir)
            )

        return self._reader_cache[lang_key]
```

### GPU加速（オプション）

EasyOCRはGPU対応していますが、現在はCPU動作:

```python
reader = easyocr.Reader(
    languages,
    gpu=True,  # GPU有効化
    model_storage_directory=str(self.easyocr_cache_dir)
)
```

**注意**: GPUを使用する場合は:
- CUDA対応GPU必須
- Dockerイメージに `nvidia-docker` 設定
- `requirements.txt` に `torch` GPU版追加

### 並列OCR処理

複数要素の並列OCR実行:

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

async def batch_ocr_parallel(self, elements: List[Dict], languages: List[str]):
    """並列OCR実行"""
    with ThreadPoolExecutor(max_workers=4) as executor:
        tasks = [
            asyncio.get_event_loop().run_in_executor(
                executor,
                self.extract_from_image_ocr,
                elem["cropped_image_path"],
                languages
            )
            for elem in elements
        ]
        results = await asyncio.gather(*tasks)

    return results
```

### メモリ最適化

大量の画像処理時のメモリリーク防止:

```python
def extract_from_image_ocr(self, image_path: str, languages: List[str]) -> str:
    """メモリリーク防止版"""
    try:
        reader = self._get_cached_reader(languages)
        result = reader.readtext(str(image_path), detail=0)
        text = " ".join(result)

        # 明示的にメモリ解放
        del result
        gc.collect()

        return text
    except Exception as e:
        logger.warning(f"EasyOCR failed: {e}")
        return ""
```

---

## トラブルシューティング

### よくある問題

**問題1: EasyOCRモデルダウンロード失敗**
- **原因**: ネットワークエラー、キャッシュディレクトリ権限不足
- **解決**: `/tmp/.easyocr_models` の権限確認、手動ダウンロード

**問題2: OCR精度が低い**
- **原因**: 画像解像度不足、コントラスト不足
- **解決**: `scale=2.0` を `scale=3.0` に増やす、前処理で画像調整

**問題3: 座標ずれ（矩形が要素に合わない）**
- **原因**: `rectangleScale` の不整合
- **解決**: バックエンド `scale_factor` とフロント `rectangleScale` を2.0に統一

**問題4: 日本語認識失敗**
- **原因**: 言語設定ミス、モデル未ダウンロード
- **解決**: `languages=["ja", "en"]` を確認、`/tmp/.easyocr_models` にモデル存在確認

---

## 今後の改善計画

- [ ] GPU加速対応
- [ ] 言語自動検出機能
- [ ] OCR信頼度スコアの活用
- [ ] テーブルOCRの精度向上（Docling TableFormer活用）
- [ ] リアルタイムOCR編集UI
- [ ] OCR履歴管理（バージョン管理）

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [ドキュメント処理パイプライン](./03-document-processing.md)
- [階層構造変換](./05-hierarchy-converter.md)
- [データベース設計](./06-database-design.md)