# Admin API Service - 階層構造変換

**カテゴリ**: Document Processing / Hierarchy
**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [3つの階層タイプ](#3つの階層タイプ)
- [HierarchyConverterの設計](#hierarchyconverterの設計)
- [通し番号ID生成の修正](#通し番号id生成の修正-2025-09-02)
- [座標変換ロジック](#座標変換ロジック)
- [フロントエンド連携](#フロントエンド連携)

---

## 概要

**HierarchyConverter**は、Doclingが抽出したフラットな要素リストを、3種類の階層構造（論理的・空間的・意味的）に変換するコアモジュールです。この階層構造により、RAG（Retrieval Augmented Generation）での重要度フィルタリング、レイアウト再現、読み順序の正確な表現が可能になります。

### 階層構造変換の目的

| 目的 | 階層タイプ | 活用シーン |
|------|----------|----------|
| 読み順序の再現 | LOGICAL_ORDERING | テキスト抽出・要約生成 |
| レイアウト理解 | SPATIAL_HIERARCHY | 表のセル構造・図とキャプションの関連付け |
| 重要度判定 | SEMANTIC_HIERARCHY | RAG検索での重要度フィルタリング |

### 主要機能

- **3種類の階層生成**: 1つの文書を3つの視点で解析
- **文書全体通し番号**: ページを跨いだ連続ID（ID-1, ID-2, ...）
- **座標系変換**: PDF座標系→画像座標系への自動変換
- **メタデータ統合**: 処理結果を `metadata_hierarchy.json` に保存

---

## 3つの階層タイプ

### 1. LOGICAL_ORDERING - 論理的読み順序

人間が文書を読む自然な順序（上→下、左→右）を表現します。

**特徴**:
- `reading_order`: 順序番号による完全な読み順序
- 線形配列での順次処理に最適
- 見出し→本文→図表→キャプションの流れ

**データ構造**:
```json
{
  "id": "ID-1",
  "type": "title",
  "text": "Introduction",
  "reading_order": 1,     // 読み順序（1が最初）
  "bbox": {...}
}
```

**活用例**:
```python
# 読み順序でソートしてテキスト抽出
elements = sorted(
    page_data["hierarchical_elements"],
    key=lambda x: x.get("reading_order", 999)
)
full_text = "\n".join(elem["text"] for elem in elements)
```

### 2. SPATIAL_HIERARCHY - 空間的階層構造

レイアウト上の配置関係と包含関係を表現します。

**特徴**:
- `spatial_level`: 階層レベル（0=最上位）
- `spatial_parent`: 親要素のID
- `spatial_children`: 子要素のIDリスト
- 表のセル構造や図とキャプションの関係把握に有効

**データ構造**:
```json
{
  "id": "ID-5",
  "type": "table",
  "spatial_level": 0,
  "spatial_parent": null,
  "spatial_children": ["ID-6", "ID-7", "ID-8"],  // セル要素
  "bbox": {...}
}
```

**活用例**:
```python
# 表構造の再構築
def reconstruct_table(table_element: Dict, all_elements: List[Dict]):
    """表要素から構造を再構築"""
    cells = [
        elem for elem in all_elements
        if elem["id"] in table_element.get("spatial_children", [])
    ]

    # セルを行・列で整理
    rows = group_by_vertical_position(cells)
    return {"rows": rows, "columns": len(rows[0]) if rows else 0}
```

### 3. SEMANTIC_HIERARCHY - 意味的階層構造

内容の意味や重要度に基づく階層を表現します。

**特徴**:
- `semantic_level`: 意味的階層レベル（1=最重要）
- `importance_score`: 重要度スコア（0.0-1.0）
- `semantic_parent`: 意味的親要素のID
- RAGでの重要度フィルタリングに活用

**データ構造**:
```json
{
  "id": "ID-1",
  "type": "title",
  "text": "Introduction",
  "semantic_level": 1,          // 見出しレベル1
  "importance_score": 0.95,     // 非常に重要
  "semantic_parent": null,
  "semantic_children": ["ID-2", "ID-3"],  // 配下の段落
  "bbox": {...}
}
```

**活用例**:
```python
# 重要度でフィルタリング
def filter_important_elements(elements: List[Dict], threshold: float = 0.7):
    """重要度の高い要素のみ抽出（RAG用）"""
    return [
        elem for elem in elements
        if elem.get("importance_score", 0) >= threshold
    ]

# 見出しと直下の本文のみ取得
def get_section_summaries(elements: List[Dict]):
    """セクションサマリー生成"""
    summaries = []
    for elem in elements:
        if elem["type"] == "title" and elem["semantic_level"] <= 2:
            # 見出しと直下の最初の段落を取得
            children = elem.get("semantic_children", [])
            first_para = next(
                (e for e in elements if e["id"] in children and e["type"] == "text"),
                None
            )
            summaries.append({
                "title": elem["text"],
                "preview": first_para["text"][:200] if first_para else ""
            })
    return summaries
```

---

## HierarchyConverterの設計

### クラス構造

**ファイル**: `app/core/document_processing/hierarchy_converter.py`

```python
class HierarchyConverter:
    """semantic_hierarchyをフロントエンド用の階層構造に変換"""

    def __init__(self):
        self.logger = logger
        self.global_element_counter = 0  # 文書全体での通し番号カウンター

    def convert_page_to_hierarchy(
        self,
        page_layout: Dict[str, Any],
        page_number: int,
        metadata: Dict[str, Any],
        docling_document=None
    ) -> Dict[str, Any]:
        """ページレベル階層構造変換"""
        # 各要素にID付与と階層情報追加
        hierarchical_elements = []

        for element in page_layout.get("elements", []):
            # グローバルカウンターでID生成
            self.global_element_counter += 1
            element_id = f"ID-{self.global_element_counter}"

            # 階層情報追加
            hierarchical_element = self._enrich_element(
                element, element_id, page_number, metadata
            )

            hierarchical_elements.append(hierarchical_element)

        page_layout["hierarchical_elements"] = hierarchical_elements
        return page_layout
```

### 要素エンリッチメント

```python
def _enrich_element(
    self,
    element: Dict,
    element_id: str,
    page_number: int,
    metadata: Dict
) -> Dict:
    """要素に階層情報を追加"""

    enriched = element.copy()
    enriched["id"] = element_id
    enriched["page_number"] = page_number

    # 論理的読み順序
    enriched["reading_order"] = self._calculate_reading_order(element)

    # 空間的階層
    spatial_info = self._calculate_spatial_hierarchy(element, metadata)
    enriched.update(spatial_info)

    # 意味的階層
    semantic_info = self._calculate_semantic_hierarchy(element)
    enriched.update(semantic_info)

    return enriched
```

### 読み順序計算

```python
def _calculate_reading_order(self, element: Dict) -> int:
    """Y座標とX座標から読み順序を計算"""
    bbox = element.get("bbox", {})

    # Y座標優先（上→下）、次にX座標（左→右）
    y1 = bbox.get("y1", 0)
    x1 = bbox.get("x1", 0)

    # Y座標を100倍してX座標を加算（上から優先）
    return int(y1 * 100 + x1)
```

### 重要度スコア計算

```python
def _calculate_importance_score(self, element: Dict) -> float:
    """要素の重要度スコアを計算"""
    element_type = element.get("type", "text")

    # 要素タイプ別基本スコア
    type_scores = {
        "title": 0.95,
        "section_header": 0.90,
        "paragraph": 0.70,
        "list_item": 0.65,
        "table": 0.80,
        "figure": 0.75,
        "caption": 0.60,
        "footer": 0.30,
        "page_number": 0.10
    }

    base_score = type_scores.get(element_type, 0.50)

    # テキスト長で調整（長いほど重要）
    text_length = len(element.get("text", ""))
    if text_length > 200:
        base_score += 0.05
    elif text_length < 20:
        base_score -= 0.10

    # 0.0-1.0に正規化
    return max(0.0, min(1.0, base_score))
```

---

## 通し番号ID生成の修正 (2025-09-02)

### 問題の詳細

**修正前の問題**:
- `app/core/document_processing/base.py:284` でページごとに新しい `HierarchyConverter()` インスタンスを作成
- `global_element_counter` がページごとにリセットされ、各ページで `ID-1` から開始
- 結果: ページ1(ID-1,2,3...) → ページ2(ID-1,2,3...) → ページ3(ID-1,2,3...)

**問題のあったコード**:
```python
# 修正前（問題）
for page_num in range(num_pages):
    hierarchy_converter = HierarchyConverter()  # ←毎回新作成（NG）
    page_layout = hierarchy_converter.convert_page_to_hierarchy(...)
```

### 修正内容

**ファイル**: `app/core/document_processing/base.py:263-266, 330`

```python
# 修正後（正解）
# 文書全体で共有するHierarchyConverterインスタンスを作成
from .hierarchy_converter import HierarchyConverter
document_hierarchy_converter = HierarchyConverter()  # ←文書全体で共有

for page_num in range(num_pages):
    # 共有インスタンス使用（カウンターが継続）
    page_layout = document_hierarchy_converter.convert_page_to_hierarchy(
        page_layout, page_num + 1, page_metadata_ext, document
    )
```

### 修正結果

**修正前**: ページごとにIDリセット
```json
// ページ1
{"id": "ID-1", "page_number": 1, "type": "title"},
{"id": "ID-2", "page_number": 1, "type": "text"},
{"id": "ID-3", "page_number": 1, "type": "text"},

// ページ2（IDがリセット！）
{"id": "ID-1", "page_number": 2, "type": "title"},  // NG: 重複ID
{"id": "ID-2", "page_number": 2, "type": "text"},
{"id": "ID-3", "page_number": 2, "type": "text"}
```

**修正後**: 文書全体で通し番号
```json
// ページ1
{"id": "ID-1", "page_number": 1, "type": "title"},
{"id": "ID-2", "page_number": 1, "type": "text"},
{"id": "ID-3", "page_number": 1, "type": "text"},

// ページ2（通し番号継続）
{"id": "ID-4", "page_number": 2, "type": "title"},  // OK: 連続ID
{"id": "ID-5", "page_number": 2, "type": "text"},
{"id": "ID-6", "page_number": 2, "type": "text"}
```

### 影響範囲

**影響あり**:
- 新規処理文書のみ（修正後にアップロードされたPDF）

**影響なし**:
- 既存処理済み文書（再処理しない限り変更なし）

### 検証方法

```bash
# 新しいPDFをアップロードして処理
curl -X POST http://localhost:8003/admin/documents/upload \
  -F "file=@test.pdf" \
  -H "Authorization: Bearer $TOKEN"

# metadata_hierarchy.jsonでID連番を確認
cat /tmp/document_processing/20250930_*/metadata_hierarchy.json | \
  jq '.pages[].hierarchical_elements[].id'

# 期待される出力:
# "ID-1"
# "ID-2"
# "ID-3"
# "ID-4"  ← ページ2でも連続
# "ID-5"
# ...
```

### フロントエンド側の対応

**ファイル**: `ai-micro-front-admin/src/pages/documents/ocr/[id].tsx`

**修正前**: ページベースID生成（削除）
```typescript
// 修正前（削除）
const elementId = `${pageNumber * 1000 + elementIndex}`;
```

**修正後**: バックエンドIDをそのまま使用
```typescript
// 修正後
const elementId = element.id;  // バックエンドから取得したIDをそのまま使用
```

---

## 座標変換ロジック

### PDF座標系 vs 画像座標系

**PDF座標系** (Docling出力):
```
(0, 842.4) ←──────────→ (595.2, 842.4)  ← Y軸最大値（上端）
    ↑                         ↑
    │                         │
    │      PDF内容            │
    │                         │
    ↓                         ↓
(0, 0)     ←──────────→  (595.2, 0)     ← 原点（左下）
```

**画像座標系** (フロントエンド表示):
```
(0, 0)     ←──────────→  (1190, 0)      ← 原点（左上）
    ↓                         ↓
    │                         │
    │      画像内容            │
    │                         │
    ↓                         ↓
(0, 1684)  ←──────────→  (1190, 1684)   ← Y軸最大値（下端）
```

### 変換実装

**ファイル**: `app/core/document_processing/hierarchy_converter.py:496-558`

```python
def _convert_bbox_coordinates(
    self,
    bbox: Dict,
    page_height: float,
    element_type: str
) -> Dict:
    """PDF座標系→画像座標系変換"""

    x1 = bbox.get("x1", 0)
    y1_input = bbox.get("y1", 0)  # PDF Y座標
    x2 = bbox.get("x2", 0)
    y2_input = bbox.get("y2", 0)  # PDF Y座標

    # Figure要素は特別処理（座標変換なし）
    if element_type == "figure":
        y1_image = y1_input
        y2_image = y2_input
    else:
        # Y軸反転（PDF下端→画像上端）
        y1_image = page_height - y2_input
        y2_image = page_height - y1_input

    return {
        "x1": x1,
        "y1": y1_image,
        "x2": x2,
        "y2": y2_image
    }
```

### スケールファクター適用

**バックエンド**: `scale_factor=2.0` で画像生成・切り出し
**フロントエンド**: `rectangleScale=2.0` で表示補正

```python
# バックエンド: 画像切り出し時
x1 = int(bbox["x1"] * 2.0)
y1 = int(bbox["y1"] * 2.0)
x2 = int(bbox["x2"] * 2.0)
y2 = int(bbox["y2"] * 2.0)

cropped = image.crop((x1, y1, x2, y2))
```

```typescript
// フロントエンド: 矩形表示時
const rectangleScale = 2.0;

<div
  style={{
    left: `${rect.x * rectangleScale}px`,
    top: `${rect.y * rectangleScale}px`,
    width: `${rect.width * rectangleScale}px`,
    height: `${rect.height * rectangleScale}px`,
  }}
/>
```

---

## フロントエンド連携

### metadata_hierarchy.json の読み込み

**フロントエンド**: `ai-micro-front-admin/src/pages/documents/ocr/[id].tsx`

```typescript
// メタデータ取得
const response = await fetch(`/api/documents/${documentId}/metadata`);
const data = await response.json();
const metadata = data.metadata;

// ページデータ抽出
const pages = metadata.pages;
const currentPage = pages[pageNumber - 1];
const elements = currentPage.hierarchical_elements;
```

### 要素の描画

```typescript
// 矩形描画
{elements.map((element) => (
  <div
    key={element.id}
    className="absolute border-2 border-blue-500"
    style={{
      left: `${element.bbox.x1 * rectangleScale}px`,
      top: `${element.bbox.y1 * rectangleScale}px`,
      width: `${(element.bbox.x2 - element.bbox.x1) * rectangleScale}px`,
      height: `${(element.bbox.y2 - element.bbox.y1) * rectangleScale}px`,
    }}
    onClick={() => handleElementClick(element)}
  >
    {/* 要素タイプ表示 */}
    <span className="text-xs bg-blue-500 text-white px-1">
      {element.type}
    </span>
  </div>
))}
```

### 階層構造の活用

```typescript
// 重要度でフィルタリング
const importantElements = elements.filter(
  (elem) => elem.importance_score >= 0.7
);

// 読み順序でソート
const sortedElements = [...elements].sort(
  (a, b) => (a.reading_order || 0) - (b.reading_order || 0)
);

// 見出しのみ抽出
const headings = elements.filter(
  (elem) => elem.type === "title" && elem.semantic_level <= 2
);
```

### リージョンOCR実行

```typescript
// 特定要素のOCR再実行
async function reprocessElement(elementId: string) {
  const response = await fetch(
    `/api/documents/${documentId}/ocr-region`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        element_id: elementId,
        page_number: currentPageNumber,
        languages: ['ja', 'en']
      })
    }
  );

  const result = await response.json();
  // UIでOCR結果を表示・編集
}
```

---

## トラブルシューティング

### よくある問題

**問題1: 要素IDが重複している**
- **原因**: 旧バージョン（2025-09-02修正前）で処理された文書
- **解決**: 文書を再アップロード・再処理

**問題2: 矩形がずれている**
- **原因**: `rectangleScale` の不整合
- **解決**: フロントエンドの `rectangleScale = 2.0` を確認

**問題3: 重要度スコアが全て0.5**
- **原因**: 重要度計算ロジックの未実装
- **解決**: `_calculate_importance_score` の実装確認

**問題4: 空間的階層が構築されていない**
- **原因**: `spatial_parent/children` の計算未実装
- **解決**: 現在は論理的・意味的階層のみ実装（空間的は今後対応）

---

## 今後の改善計画

- [ ] 空間的階層の完全実装（親子関係の自動推論）
- [ ] 機械学習による重要度スコア改善
- [ ] 表構造の自動認識強化
- [ ] 図とキャプションの自動関連付け
- [ ] セクション境界の自動検出

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [ドキュメント処理パイプライン](./03-document-processing.md)
- [OCR設計](./04-ocr-design.md)
- [データベース設計](./06-database-design.md)