# Admin API Service - ドキュメント処理パイプライン

**カテゴリ**: Document Processing
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [Docling統合](#docling統合)
- [7段階処理パイプライン](#7段階処理パイプライン)
- [レイアウト解析](#レイアウト解析)
- [画像処理](#画像処理)
- [出力ファイル構造](#出力ファイル構造)
- [パフォーマンス最適化](#パフォーマンス最適化)

---

## 概要

Admin API Serviceのドキュメント処理エンジンは、**Docling v2.0**をコアとした高度なPDF解析システムです。単なるテキスト抽出ではなく、レイアウト構造、意味的階層、視覚要素の自動認識を実現します。

### 主要機能

- **自動レイアウト解析**: 見出し、本文、図表、表の自動識別
- **3種類の階層構造**: 論理的・空間的・意味的な3つの視点で文書を解析
- **ハイブリッドOCR**: DoclingとEasyOCRの組み合わせで高精度文字認識
- **画像切り出し**: 図表要素の自動抽出と保存
- **座標マッピング**: PDF座標系から画像座標系への正確な変換

### 処理対応形式

| 形式 | 拡張子 | 対応状況 |
|------|-------|---------|
| PDF | `.pdf` | 完全対応 |
| Word | `.docx` | 基本対応 |
| PowerPoint | `.pptx` | 基本対応 |
| その他 | - | フォールバック処理 |

---

## Docling統合

### Docling とは

**Docling**は、IBM Researchが開発したドキュメント理解フレームワークです。深層学習ベースのレイアウト解析により、人間が読むような自然な順序で文書要素を抽出します。

### 統合アーキテクチャ

```
┌─────────────────────────────────────────┐
│         DocumentProcessor               │
│         (app/core/document_processing/  │
│                    base.py)             │
└──────────────┬──────────────────────────┘
               │
      ┌────────┼────────┐
      │        │        │
┌─────▼─────┐ │ ┌──────▼──────┐
│  Docling  │ │ │ Image       │
│ Processor │ │ │ Processor   │
└───────────┘ │ └─────────────┘
              │
      ┌───────▼──────┐
      │  Hierarchy   │
      │  Converter   │
      └──────────────┘
```

### Doclingコンポーネント

**ファイル**: `app/core/document_processing/docling_processor.py`

```python
class DoclingProcessor:
    """Docling統合プロセッサ"""

    def convert_document(self, document_path: str) -> DoclingDocument:
        """PDFをDoclingドキュメントに変換"""
        # Doclingパイプライン実行
        converter = DocumentConverter()
        result = converter.convert(document_path)
        return result.document

    def extract_document_metadata(self, document) -> Dict:
        """文書メタデータ抽出"""
        return {
            "total_pages": len(document.pages),
            "title": document.title,
            "author": document.author
        }
```

### Doclingキャッシュ管理

**環境変数**: `DOCLING_CACHE_DIR=/tmp/.docling_cache`

Doclingは初回実行時に深層学習モデル（約500MB）をダウンロードします:

- **レイアウト検出モデル**: TableTransformer
- **テーブル構造認識モデル**: TableFormer
- **OCRモデル**: Tesseract/EasyOCR連携

キャッシュディレクトリはDockerボリュームでマウントし、再起動時も保持します。

---

## 7段階処理パイプライン

### パイプライン全体図

```
1. 初期化・検証
   ↓
2. Docling変換（PDFパース）
   ↓
3. 統合構造解析（セクション分割）
   ↓
4. ページ処理ループ
   ├─ 4a. レイアウト抽出
   ├─ 4b. 階層構造変換
   ├─ 4c. 画像生成（144 DPI）
   └─ 4d. 画像切り出し
   ↓
5. メタデータ統合
   ↓
6. 階層メタデータ生成（metadata_hierarchy.json）
   ↓
7. 処理完了・DB保存
```

### Stage 1: 初期化・検証

**ファイル**: `app/core/document_processing/base.py:114-157`

```python
def process_document_with_progress(self, document_path: str, ...):
    """初期化・検証ステージ"""
    # メモリ使用量チェック
    self._check_memory_usage()

    # ファイル存在確認
    doc_path = Path(document_path)
    if not doc_path.exists():
        raise FileNotFoundError(f"Document not found: {document_path}")

    # 出力ディレクトリ作成
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = self.file_manager.create_output_directory(
        timestamp, original_filename
    )

    # 元ファイル保存
    self.file_manager.save_original_file(document_path, output_dir, ...)
```

**進捗報告**: `ステップ 0-2/10`

### Stage 2: Docling変換

**ファイル**: `app/core/document_processing/base.py:158-175`

```python
# Docling処理を試行
document = self.docling_processor.convert_document(document_path)

if not self.docling_processor.validate_document(document):
    raise ValueError("Invalid document structure")
```

**処理内容**:
- PDFパース
- ページ分割
- 初期レイアウト認識
- ページ次元情報取得

**進捗報告**: `ステップ 3-6/10` （Docling変換は時間がかかるため広範囲）

**タイムアウト**: なし（大規模PDFは数分かかる場合あり）

### Stage 3: 統合構造解析

**ファイル**: `app/core/document_processing/base.py:247-258`

```python
from .document_structure_analyzer import DocumentStructureAnalyzer

structure_analyzer = DocumentStructureAnalyzer()
unified_structure = structure_analyzer.create_unified_structure_from_docling(
    document, num_pages
)
```

**処理内容**:
- 文書全体のセクション構造解析
- 見出し階層の抽出
- セクション境界の決定

**出力例**:
```json
{
  "sections": [
    {
      "section_id": "section-1",
      "title": "Introduction",
      "start_page": 1,
      "end_page": 3,
      "level": 1
    }
  ]
}
```

### Stage 4: ページ処理ループ

**ファイル**: `app/core/document_processing/base.py:269-431`

各ページに対して4つのサブステージを実行:

#### Stage 4a: レイアウト抽出

**ファイル**: `app/core/document_processing/layout_extractor.py`

```python
page_layout = self.layout_extractor.extract_page_layout(
    document, page_num, output_dir
)
```

**抽出要素**:
- `text`: テキストブロック
- `title`: 見出し
- `figure`: 図表
- `table`: 表
- `caption`: キャプション
- `list_item`: リスト項目
- `page_number`: ページ番号
- `footer`: フッター

**出力形式**:
```json
{
  "page_number": 1,
  "elements": [
    {
      "type": "title",
      "text": "Introduction",
      "bbox": {"x1": 100, "y1": 150, "x2": 500, "y2": 200}
    }
  ]
}
```

#### Stage 4b: 階層構造変換

**ファイル**: `app/core/document_processing/base.py:304-338`

```python
# 文書全体で共有するHierarchyConverterインスタンス
document_hierarchy_converter = HierarchyConverter()

# ページレベル変換
page_layout = document_hierarchy_converter.convert_page_to_hierarchy(
    page_layout, page_num + 1, page_metadata_ext, document
)
```

**重要**: **2025-09-02修正** - 文書全体で1つのHierarchyConverterインスタンスを共有し、通し番号IDを生成します。

**変換内容**:
- 3種類の階層構造生成（LOGICAL, SPATIAL, SEMANTIC）
- 文書全体通し番号ID付与（ID-1, ID-2, ...）
- PDF座標→画像座標変換

**出力形式**:
```json
{
  "hierarchical_elements": [
    {
      "id": "ID-1",
      "type": "title",
      "text": "Introduction",
      "bbox": {...},
      "reading_order": 1,
      "spatial_level": 0,
      "semantic_level": 1
    }
  ]
}
```

#### Stage 4c: 画像生成

**ファイル**: `app/core/document_processing/image_processor.py:47`

```python
image = page.render(scale=2.0)  # 72 DPI → 144 DPI
pil_image = image.to_pil()
pil_image.save(output_path, 'PNG')
```

**解像度設定**:
- **PDF基準**: 72 DPI（標準）
- **生成画像**: 144 DPI（scale=2.0）
- **理由**: 高精度OCRとUI表示の両立

**出力ファイル**:
- `images/page_X_full.png`: ページ全体画像

#### Stage 4d: 画像切り出し

**ファイル**: `app/core/document_processing/base.py:349-386`

```python
for elem in croppable_elements:
    if self.image_cropper.crop_single_element(
        str(page_image_path), elem, str(images_dir), scale_factor=2.0
    ):
        cropped_elements.append(elem)
```

**切り出し対象**:
- `figure`: 図表
- `picture`: 画像
- `table`: 表
- `caption`: キャプション

**出力ファイル**:
- `images/figures/figure_X.png`: 切り出し図表

**進捗報告**: `ステップ 7-9/10` （ページ数に応じて進捗）

### Stage 5: メタデータ統合

**ファイル**: `app/core/document_processing/base.py:433-484`

```python
metadata = {
    "document_name": original_filename,
    "processing_timestamp": timestamp,
    "total_pages": num_pages,
    "total_elements": total_elements,
    "pages": pages_data,
    "processing_mode": "docling",
    "dimensions": {
        "pdf_page": {"width": 595.2, "height": 842.4},
        "image_page": {"width": 1190, "height": 1684}
    }
}
```

### Stage 6: 階層メタデータ生成

**ファイル**: `app/core/document_processing/base.py:500-548`

```python
from .hierarchy_converter import HierarchyConverter

hierarchy_converter = HierarchyConverter()
hierarchy_metadata = metadata.copy()

# 処理済みhierarchical_elementsを統合
for page_idx, page_data in enumerate(pages_data):
    hierarchy_metadata["pages"][page_idx]["hierarchical_elements"] = \
        page_data.get("hierarchical_elements", [])

# metadata_hierarchy.json保存
hierarchy_file = hierarchy_converter.save_hierarchy_metadata(
    hierarchy_metadata, output_dir
)
```

**出力ファイル**: `metadata_hierarchy.json`

**進捗報告**: `ステップ 9/10`

### Stage 7: 処理完了・DB保存

**ファイル**: `app/core/document_processing/base.py:637-659`

```python
return {
    "status": "success",
    "output_directory": str(output_dir),
    "files_created": {...},
    "total_pages": num_pages,
    "total_elements": total_elements,
    "processing_mode": "docling",
    "processing_time": f"{processing_time:.1f}s",
    "metadata": hierarchy_metadata  # DB保存用
}
```

**進捗報告**: `ステップ 10/10`

---

## レイアウト解析

### Doclingレイアウト認識

Doclingは深層学習モデル（TableTransformer）でレイアウト要素を自動認識します。

**認識可能な要素**:

| 要素タイプ | 説明 | Doclingラベル |
|-----------|------|--------------|
| `title` | 見出し | `DocItemLabel.TITLE` |
| `text` | 本文 | `DocItemLabel.TEXT` |
| `figure` | 図表 | `DocItemLabel.FIGURE` |
| `table` | 表 | `DocItemLabel.TABLE` |
| `caption` | キャプション | `DocItemLabel.CAPTION` |
| `list_item` | リスト項目 | `DocItemLabel.LIST_ITEM` |
| `page_number` | ページ番号 | `DocItemLabel.PAGE_NUMBER` |
| `footer` | フッター | `DocItemLabel.FOOTER` |

### 座標系の理解

**PDF座標系** (Docling出力):
- 原点: 左下
- Y軸: 上向き
- 単位: ポイント (1/72 inch)

**画像座標系** (フロントエンド表示):
- 原点: 左上
- Y軸: 下向き
- 単位: ピクセル

**変換式** (`hierarchy_converter.py:496-558`):
```python
if element_type == "figure":
    # Figure要素は座標変換なし
    y1_image = y1_input
    y2_image = y2_input
else:
    # その他要素はPDF→画像座標変換
    y1_image = page_height - y2_input
    y2_image = page_height - y1_input
```

---

## 画像処理

### 高品質画像生成

**ファイル**: `app/core/document_processing/image_processor.py`

```python
def create_page_image(self, page_num: int, images_dir: Path, document):
    """ページ画像生成（144 DPI）"""
    page = document.pages[page_num]
    image = page.render(scale=2.0)  # 72 DPI → 144 DPI
    pil_image = image.to_pil()

    output_path = images_dir / f"page_{page_num + 1}_full.png"
    pil_image.save(output_path, 'PNG', optimize=True)
```

### アノテーション付き画像

**ファイル**: `app/core/document_processing/image_processor.py:120-180`

```python
def create_annotated_image(self, page_image_path, page_layout, output_path):
    """レイアウトアノテーション描画"""
    image = Image.open(page_image_path)
    draw = ImageDraw.Draw(image)

    for elem in page_layout.get("hierarchical_elements", []):
        bbox = elem.get("bbox")
        elem_type = elem.get("type")

        # 要素タイプごとに色分け
        color = self._get_element_color(elem_type)

        # 矩形描画（2倍スケール適用）
        draw.rectangle(
            [bbox["x1"] * 2, bbox["y1"] * 2, bbox["x2"] * 2, bbox["y2"] * 2],
            outline=color,
            width=2
        )
```

**色分け**:
- `title`: 赤
- `text`: 青
- `figure`: 緑
- `table`: オレンジ
- `caption`: 紫

### 画像切り出し

**ファイル**: `app/core/document_processing/image_cropper.py`

```python
def crop_single_element(self, page_image_path: str, element: Dict,
                       output_dir: str, scale_factor: float = 2.0):
    """単一要素の切り出し"""
    bbox = element.get("bbox")

    # 座標にスケールファクター適用
    x1 = int(bbox["x1"] * scale_factor)
    y1 = int(bbox["y1"] * scale_factor)
    x2 = int(bbox["x2"] * scale_factor)
    y2 = int(bbox["y2"] * scale_factor)

    # 画像切り出し
    image = Image.open(page_image_path)
    cropped = image.crop((x1, y1, x2, y2))

    # 保存
    output_path = Path(output_dir) / f"{element['id']}.png"
    cropped.save(output_path, 'PNG')

    # 相対パスをメタデータに記録
    element["cropped_image_path"] = f"figures/{element['id']}.png"
```

---

## 出力ファイル構造

### ディレクトリ構成

```
/tmp/document_processing/
└── 20250930_143250_report.pdf/
    ├── original/
    │   └── report.pdf                    # 元ファイル
    ├── metadata_hierarchy.json           # 階層メタデータ（フロント用）
    └── images/
        ├── page_1_full.png               # ページ全体（144 DPI）
        ├── page_1_full_annotated.png     # アノテーション付き
        ├── page_2_full.png
        └── figures/
            ├── ID-5.png                  # 切り出し図表
            ├── ID-12.png
            └── ID-18.png
```

### metadata_hierarchy.json構造

```json
{
  "document_name": "report.pdf",
  "processing_timestamp": "20250930_143250",
  "total_pages": 15,
  "total_elements": 234,
  "dimensions": {
    "pdf_page": {"width": 595.2, "height": 842.4},
    "image_page": {"width": 1190, "height": 1684}
  },
  "pages": [
    {
      "page_number": 1,
      "hierarchical_elements": [
        {
          "id": "ID-1",
          "type": "title",
          "text": "Introduction",
          "bbox": {"x1": 100, "y1": 150, "x2": 500, "y2": 200},
          "reading_order": 1,
          "spatial_level": 0,
          "semantic_level": 1,
          "importance_score": 0.95
        }
      ],
      "has_hierarchy": true,
      "cropped_elements_count": 5,
      "cropped_figure_count": 3,
      "cropped_table_count": 2
    }
  ],
  "document_structure_summary": {
    "total_sections": 5,
    "document_type": "technical_report",
    "structure_confidence": 0.87,
    "has_unified_structure": true
  }
}
```

---

## パフォーマンス最適化

### メモリ管理

**ファイル**: `app/core/document_processing/base.py:90-113`

```python
def _check_memory_usage(self):
    """メモリ監視とGC実行"""
    memory_mb = psutil.Process().memory_info().rss / 1024 / 1024

    if memory_mb > 4000:  # 4GB閾値
        logger.warning(f"High memory usage: {memory_mb:.1f}MB")
        gc.collect()

        new_memory_mb = psutil.Process().memory_info().rss / 1024 / 1024
        logger.info(f"Memory after GC: {new_memory_mb:.1f}MB")

        if new_memory_mb > 10000:  # 10GB = 12GB制限の83%
            raise MemoryError(f"Memory usage too high: {new_memory_mb:.1f}MB")
```

### 処理時間短縮

1. **キャッシュ活用**:
   - Doclingモデル: `/tmp/.docling_cache`（約500MB）
   - EasyOCRモデル: `/tmp/.easyocr_models`（約300MB）

2. **並列処理**:
   - 現在は逐次処理
   - 今後の改善: ページ単位の並列処理

3. **段階的処理**:
   - レイアウト解析優先
   - OCRは必要に応じて後から実行

### 進捗報告機構

**ファイル**: `app/core/document_processing/base.py:63-88`

```python
def _log_progress_with_timing(self, description: str, step: int,
                              total: int, start_time: float,
                              progress_callback=None):
    """進捗ログ出力"""
    if progress_callback:
        progress_callback(step=step, total=total, description=description)

    progress_log = {
        "timestamp": datetime.now().isoformat(),
        "step": step,
        "total_steps": total,
        "percentage": round((step / total) * 100, 1),
        "description": description,
        "elapsed_seconds": round(time.time() - start_time, 2)
    }

    logger.info(f"📈 DOCUMENT_PROGRESS: {json.dumps(progress_log)}")
```

**フロントエンド連携**:
- WebSocket経由でリアルタイム進捗通知
- ログから進捗抽出して表示

---

## トラブルシューティング

### よくある問題

**問題1: Docling処理タイムアウト**
- **原因**: 大規模PDF（50ページ以上）
- **解決**: タイムアウト値を増やす、ページ分割処理

**問題2: メモリ不足エラー**
- **原因**: 高解像度画像、大量の図表
- **解決**: Docker メモリ制限を12GB→16GBに増やす

**問題3: 画像座標ずれ**
- **原因**: scale_factorの不整合
- **解決**: `rectangleScale = 2.0` をフロント・バックで統一

**問題4: 処理中断**
- **原因**: Doclingキャッシュディレクトリ権限エラー
- **解決**: `/tmp/.docling_cache` の権限確認

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [OCR設計](./04-ocr-design.md)
- [階層構造変換](./05-hierarchy-converter.md)
- [データベース設計](./06-database-design.md)