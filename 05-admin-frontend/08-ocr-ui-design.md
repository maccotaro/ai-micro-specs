# 08-ocr-ui-design.md - OCRエディタUI設計

## 概要

OCRエディタ (`/documents/ocr/[id]`) は、Docling処理後のOCR結果を視覚的に確認・編集するための高度なインタラクティブUIです。画像プレビュー、矩形操作、階層構造編集、テキスト編集を統合した複雑なエディタ機能を提供します。

## 全体レイアウト構成

### 3カラムレイアウト

```
┌──────────────────────────────────────────────────────────────────────┐
│ ヘッダーバー                                  [保存] [RAG変換] [設定] │
├────┬─────────────────┬──────────────────────────────────────────────┤
│ P  │ 文書構造ツリー  │ プレビューキャンバス                         │
│ a  │ (60% height)    │ ┌────────────────────────────────────────┐ │
│ g  │                 │ │ [◀ 1/10 ▶] [- 100% +]                 │ │
│ e  │ □ Page 1        │ ├────────────────────────────────────────┤ │
│    │  ├─ ID-1 (title)│ │                                        │ │
│ L  │  ├─ ID-2 (text) │ │  ┌──────────────────┐                 │ │
│ i  │  └─ ID-3 (table)│ │  │ ID-1: タイトル   │  ←選択中       │ │
│ s  │    ├─ ID-4      │ │  │ (ハイライト)     │                 │ │
│ t  │    └─ ID-5      │ │  └──────────────────┘                 │ │
│    │ □ Page 2        │ │                                        │ │
│ (  │                 │ │  ┌──────────┐                         │ │
│ 4  │─────────────────│ │  │ ID-2:    │                         │ │
│ 0  │ OCRテキスト     │ │  │ 本文     │                         │ │
│ p  │ 編集エリア      │ │  └──────────┘                         │ │
│ x  │ (40% height)    │ │                                        │ │
│ )  │                 │ │  [矩形を選択してOCR実行または編集]     │ │
│    │ ID: ID-1        │ │                                        │ │
│    │ Type: [title▼] │ │                                        │ │
│    │ Text:           │ │                                        │ │
│    │ [___________]   │ │                                        │ │
└────┴─────────────────┴──────────────────────────────────────────────┘
```

**カラム幅:**
- 左カラム (ページリスト): 40px
- 中央カラム (構造+テキスト): 224px (56 * 4)
- 右カラム (プレビュー): flex-1 (残り全て)

## 座標系と変換ロジック

### バックエンドとフロントエンドの座標系

```
┌─────────────────────────────────────┐
│ バックエンド (Python)               │
├─────────────────────────────────────┤
│ • 座標系: 左上原点 (x, y)           │
│ • 単位: ポイント (72 DPI基準)       │
│ • 画像生成: 144 DPI (scale=2.0)     │
│ • 座標データ: 72 DPI基準で保存      │
└──────────────┬──────────────────────┘
               │ API
               ↓
┌─────────────────────────────────────┐
│ フロントエンド (TypeScript/React)   │
├─────────────────────────────────────┤
│ • 画像: 144 DPI PNG                 │
│ • 座標データ: 72 DPI基準で受信      │
│ • rectangleScale: 2.0 (固定値)      │
│ • zoomLevel: 0.5 〜 3.0 (可変)      │
└─────────────────────────────────────┘
```

### 重要な定数

**ファイル:** `/src/pages/documents/ocr/[id].tsx`

```typescript
// Line 98-100
const imageDisplayScale = 1.0;  // 画像サイズ係数（常に1.0）
const rectangleScale = 2.0;     // 矩形スケール係数（固定）
const displayWidth = naturalImageWidth * imageDisplayScale;
const displayHeight = naturalImageHeight * imageDisplayScale;

// 実際の表示サイズ
const containerWidth = displayWidth * zoomLevel;
const containerHeight = displayHeight * zoomLevel;
```

### rectangleScale = 2.0 の理由

1. **バックエンド画像生成:** 144 DPI (scale=2.0) で画像生成
2. **座標基準:** 72 DPI基準の座標データ
3. **表示補正:** 144 DPI画像に72 DPI座標を適用するため2倍が必要
4. **計算式:** `144 DPI ÷ 72 DPI = 2.0`

### 座標変換の適用箇所

#### 1. 矩形の表示 (Canvas → Screen)

```typescript
// Line 2554-2557: 矩形のスタイル計算
style={{
  left: rect.x * rectangleScale * zoomLevel,      // 72 DPI → 144 DPI → ズーム適用
  top: rect.y * rectangleScale * zoomLevel,
  width: rect.width * rectangleScale * zoomLevel,
  height: rect.height * rectangleScale * zoomLevel,
}}
```

#### 2. マウス座標の変換 (Screen → Canvas)

```typescript
// Line 669-670: マウス座標を画像座標に変換
const rect = previewRef.current?.getBoundingClientRect();
const clientX = e.clientX - rect.left;  // ブラウザ座標
const clientY = e.clientY - rect.top;

// 画像座標系に変換
const mouseX = clientX / (zoomLevel * rectangleScale);  // Screen → 72 DPI
const mouseY = clientY / (zoomLevel * rectangleScale);
```

#### 3. OCR実行時の座標送信 (Canvas → Backend)

```typescript
// Line 541-544: バックエンドへ144 DPI座標を送信
const response = await fetch(`/api/documents/${documentId}/ocr-region`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    x: Math.round(rectangle.x * rectangleScale),        // 72 DPI → 144 DPI
    y: Math.round(rectangle.y * rectangleScale),
    width: Math.round(rectangle.width * rectangleScale),
    height: Math.round(rectangle.height * rectangleScale),
    page_number: currentPage.pageNumber,
  }),
});
```

## 矩形操作機能

### 1. 矩形選択

**トリガー:** 矩形をクリック

**動作:**
1. `selectedRectId` を設定
2. 矩形をハイライト表示 (border-blue-500)
3. OCRテキスト編集エリアに要素情報を表示
4. アクションボタンメニューを表示
5. 文書構造ツリーで該当要素までスクロール

**実装:**

```typescript
// Line 654-702: handleRectangleSelect
const handleRectangleSelect = (rectId: string) => {
  // ページノード選択時はページ切り替え
  if (rectId.startsWith('page-')) {
    setCurrentPageId(rectId);
    rectangleOperations.setSelectedRectId(null);
    return;
  }

  // 要素検索
  let elementPage = pages.find(page => page.id === currentPageId);
  let targetElement = elementPage?.rectangles.find(rect => rect.id === rectId);

  if (!targetElement) {
    // 他ページを検索
    elementPage = pages.find(page =>
      page.rectangles.some(rect => rect.id === rectId)
    );
    targetElement = elementPage?.rectangles.find(rect => rect.id === rectId);
  }

  if (!elementPage || !targetElement) {
    console.warn(`Element with id "${rectId}" not found`);
    return;
  }

  if (elementPage.id !== currentPageId) {
    // ページ切り替えが必要
    setPendingSelection(rectId);
    setCurrentPageId(elementPage.id);

    setTimeout(() => {
      scrollToElement(targetElement);
      scrollToTreeElement(rectId);
    }, 400);
  } else {
    // 同一ページ内の要素選択
    rectangleOperations.setSelectedRectId(rectId);
    setPendingSelection(null);
    setCurrentElementType(targetElement.type || "text");

    scrollToElement(targetElement);

    setTimeout(() => {
      scrollToTreeElement(rectId);
    }, 100);
  }
};
```

### 2. 矩形移動 (ドラッグ)

**トリガー:** 矩形をマウスダウン → ドラッグ

**動作:**
1. `isDraggingRect = true`
2. ドラッグ開始位置とオフセットを記録
3. マウス移動に応じて矩形位置を更新
4. 画像境界内に制限
5. マウスアップで確定

**実装:**

```typescript
// useRectangleOperations.ts
const handleRectMouseDown = useCallback((e: React.MouseEvent, rectId: string) => {
  if (isResizing) return;

  e.stopPropagation();
  setIsDraggingRect(true);
  setSelectedRectId(rectId);
  setShowActionButtons(null);

  const rect = previewRef.current?.getBoundingClientRect();
  if (rect) {
    const clientX = e.clientX - rect.left;
    const clientY = e.clientY - rect.top;

    // 画像座標に変換
    const imageX = clientX / (zoomLevel * rectangleScale);
    const imageY = clientY / (zoomLevel * rectangleScale);

    setDragStart({ x: imageX, y: imageY });

    // 矩形の位置との差分を記録
    const currentPage = pagesData.find(p => p.id === currentPageId);
    const rectangle = currentPage?.rectangles.find(r => r.id === rectId);

    if (rectangle) {
      setDragOffset({
        x: imageX - rectangle.x,
        y: imageY - rectangle.y,
      });
    }
  }
}, [isResizing, pagesData, currentPageId, previewRef, zoomLevel, rectangleScale]);

const handleRectangleDrag = useCallback((e: React.MouseEvent) => {
  if (!isDraggingRect || !selectedRectId || !dragOffset) return;

  const rect = previewRef.current?.getBoundingClientRect();
  if (!rect) return;

  const clientX = e.clientX - rect.left;
  const clientY = e.clientY - rect.top;

  const imageX = clientX / (zoomLevel * rectangleScale);
  const imageY = clientY / (zoomLevel * rectangleScale);

  // 新しい位置を計算
  const newX = imageX - dragOffset.x;
  const newY = imageY - dragOffset.y;

  // 境界チェック
  const currentPage = pagesData.find(p => p.id === currentPageId);
  const rectangle = currentPage?.rectangles.find(r => r.id === selectedRectId);

  if (!rectangle) return;

  const boundedX = Math.max(0, Math.min(naturalImageWidth - rectangle.width, newX));
  const boundedY = Math.max(0, Math.min(naturalImageHeight - rectangle.height, newY));

  // 状態更新
  setPagesData(prevPages =>
    prevPages.map(page =>
      page.id === currentPageId
        ? {
            ...page,
            rectangles: page.rectangles.map(r =>
              r.id === selectedRectId
                ? { ...r, x: boundedX, y: boundedY }
                : r
            )
          }
        : page
    )
  );

  setHasChanges(true);
}, [/* dependencies */]);
```

### 3. 矩形リサイズ

**トリガー:** リサイズハンドル (4角) をマウスダウン → ドラッグ

**ハンドル位置:**
- `nw`: 左上
- `ne`: 右上
- `sw`: 左下
- `se`: 右下

**動作:**
1. `isResizing = true`
2. リサイズハンドルの種類を記録
3. マウス移動に応じてサイズ・位置を調整
4. 最小サイズ (10x10) と境界を制限
5. マウスアップで確定

**実装:**

```typescript
// Line 2621-2651: リサイズハンドルの描画
{selectedRectId === rect.id && !isDraggingRect && (
  <>
    {/* nw (左上) */}
    <div
      className="absolute w-3 h-3 bg-blue-500 border border-white rounded-full cursor-nw-resize"
      style={{ left: -6, top: -6 }}
      onMouseDown={(e) => handleResizeMouseDown(e, 'nw', rect.id)}
    />
    {/* ne (右上) */}
    <div
      className="absolute w-3 h-3 bg-blue-500 border border-white rounded-full cursor-ne-resize"
      style={{ right: -6, top: -6 }}
      onMouseDown={(e) => handleResizeMouseDown(e, 'ne', rect.id)}
    />
    {/* sw (左下) */}
    <div
      className="absolute w-3 h-3 bg-blue-500 border border-white rounded-full cursor-sw-resize"
      style={{ left: -6, bottom: -6 }}
      onMouseDown={(e) => handleResizeMouseDown(e, 'sw', rect.id)}
    />
    {/* se (右下) */}
    <div
      className="absolute w-3 h-3 bg-blue-500 border border-white rounded-full cursor-se-resize"
      style={{ right: -6, bottom: -6 }}
      onMouseDown={(e) => handleResizeMouseDown(e, 'se', rect.id)}
    />
  </>
)}
```

```typescript
// useRectangleOperations.ts: handleResize
const handleResize = useCallback((e: React.MouseEvent) => {
  if (!isResizing || !selectedRectId || !resizeStart || !resizeHandle) return;

  const rect = previewRef.current?.getBoundingClientRect();
  if (!rect) return;

  const clientX = e.clientX - rect.left;
  const clientY = e.clientY - rect.top;

  const imageX = clientX / (zoomLevel * rectangleScale);
  const imageY = clientY / (zoomLevel * rectangleScale);

  let newX = resizeStart.x;
  let newY = resizeStart.y;
  let newWidth = resizeStart.width;
  let newHeight = resizeStart.height;

  // ハンドル別のリサイズロジック
  if (resizeHandle.includes('n')) {
    const deltaY = imageY - resizeStart.y;
    newY = resizeStart.y + deltaY;
    newHeight = resizeStart.height - deltaY;
  }
  if (resizeHandle.includes('s')) {
    newHeight = imageY - resizeStart.y;
  }
  if (resizeHandle.includes('w')) {
    const deltaX = imageX - resizeStart.x;
    newX = resizeStart.x + deltaX;
    newWidth = resizeStart.width - deltaX;
  }
  if (resizeHandle.includes('e')) {
    newWidth = imageX - resizeStart.x;
  }

  // 最小サイズと境界チェック
  newWidth = Math.max(10, Math.min(naturalImageWidth - newX, newWidth));
  newHeight = Math.max(10, Math.min(naturalImageHeight - newY, newHeight));

  // 状態更新
  setPagesData(prevPages =>
    prevPages.map(page =>
      page.id === currentPageId
        ? {
            ...page,
            rectangles: page.rectangles.map(r =>
              r.id === selectedRectId
                ? { ...r, x: newX, y: newY, width: newWidth, height: newHeight }
                : r
            )
          }
        : page
    )
  );

  setHasChanges(true);
}, [/* dependencies */]);
```

### 4. 新規矩形作成

**トリガー:** 背景エリアでマウスダウン → ドラッグ

**動作:**
1. `isDrawingMode = true`
2. 開始点を記録
3. マウス移動で矩形を視覚化 (border-dashed border-green-500)
4. マウスアップで矩形を作成
5. 最小サイズ (10x10) チェック
6. 新規ID生成 (`ID-${nextRectId}`)
7. アクションボタンメニューを表示

**実装:**

```typescript
// Line 704-825: 新規描画処理
const handleCanvasMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
  if (ocrOperations.ocrProcessing) return;

  // 背景エリアでのクリックの場合のみ描画モードを開始
  if (e.target === previewRef.current) {
    const rect = previewRef.current.getBoundingClientRect();
    const clientX = e.clientX - rect.left;
    const clientY = e.clientY - rect.top;

    // 画像座標系に変換
    const x = clientX / (zoomLevel * rectangleScale);
    const y = clientY / (zoomLevel * rectangleScale);

    setDrawStart({ x, y });
    setIsDrawingMode(true);
    setHasMouseMoved(false);
    rectangleOperations.setShowActionButtons(null);
    rectangleOperations.setSelectedRectId(null);
  }
};

const handleMouseMove = (e: React.MouseEvent) => {
  // 描画モード中の処理
  if (isDrawingMode && drawStart) {
    const rect = previewRef.current?.getBoundingClientRect();
    if (rect) {
      const clientX = e.clientX - rect.left;
      const clientY = e.clientY - rect.top;

      // 画像座標系に変換
      const x = clientX / (zoomLevel * rectangleScale);
      const y = clientY / (zoomLevel * rectangleScale);

      if (!hasMouseMoved && (Math.abs(x - drawStart.x) > 5 || Math.abs(y - drawStart.y) > 5)) {
        setHasMouseMoved(true);
      }

      if (hasMouseMoved) {
        setDrawEnd({ x, y });
      }
    }
  }
};

const handleMouseUp = () => {
  // 描画完了の処理
  if (isDrawingMode && drawStart && drawEnd && hasMouseMoved) {
    const newRectId = generateNewRectId();
    const x = Math.min(drawStart.x, drawEnd.x);
    const y = Math.min(drawStart.y, drawEnd.y);
    const width = Math.abs(drawEnd.x - drawStart.x);
    const height = Math.abs(drawEnd.y - drawStart.y);

    // 境界制限を適用
    const boundedX = Math.max(0, Math.min(naturalImageWidth - width, x));
    const boundedY = Math.max(0, Math.min(naturalImageHeight - height, y));
    const boundedWidth = Math.min(width, naturalImageWidth - boundedX);
    const boundedHeight = Math.min(height, naturalImageHeight - boundedY);

    const newRect: Rectangle = {
      id: newRectId,
      type: "text", // 初期値
      x: boundedX,
      y: boundedY,
      width: boundedWidth,
      height: boundedHeight,
    };

    // 最小サイズチェック
    if (newRect.width > 10 && newRect.height > 10) {
      const newRectangles = [...rectangles, newRect];
      updatePageRectangles(currentPageId, newRectangles);
      rectangleOperations.setSelectedRectId(newRectId);

      // アクションボタンを表示
      setTimeout(() => {
        rectangleOperations.setShowActionButtons(newRectId);
      }, 100);
    }
  }

  // 状態をリセット
  setIsDrawingMode(false);
  setDrawStart(null);
  setDrawEnd(null);
  setHasMouseMoved(false);
};
```

### 5. 矩形削除

**トリガー:** アクションボタンの削除ボタン または ツリーの削除ボタン

**動作:**
1. 削除確認ダイアログを表示
2. 確認後、子要素も含めて削除
3. `hasChanges = true`

**実装:**

```typescript
// useRectangleOperations.ts
const handleDeleteClick = useCallback((rectId: string, ocrProcessing?: boolean) => {
  if (ocrProcessing) return;

  const currentPage = pagesData.find(p => p.id === currentPageId);
  const rect = currentPage?.rectangles.find(r => r.id === rectId);

  if (rect) {
    setRectangleToDelete(rect);
    setShowDeleteConfirm(true);
  }
}, [pagesData, currentPageId]);

const handleRectangleDelete = useCallback(async () => {
  if (!rectangleToDelete) return;

  setDeleting(true);

  try {
    // 子要素を含めて削除
    const getAllChildren = (parentId: string): string[] => {
      const currentPage = pagesData.find(p => p.id === currentPageId);
      if (!currentPage) return [];

      const children = currentPage.rectangles
        .filter(r => r.parent_id === parentId)
        .map(r => r.id);

      const allChildren = [...children];
      children.forEach(childId => {
        allChildren.push(...getAllChildren(childId));
      });

      return allChildren;
    };

    const idsToDelete = [rectangleToDelete.id, ...getAllChildren(rectangleToDelete.id)];

    // 状態から削除
    setPagesData(prevPages =>
      prevPages.map(page =>
        page.id === currentPageId
          ? {
              ...page,
              rectangles: page.rectangles.filter(r => !idsToDelete.includes(r.id))
            }
          : page
      )
    );

    setHasChanges(true);
    setShowDeleteConfirm(false);
    setRectangleToDelete(null);
    setSelectedRectId(null);
  } catch (error) {
    console.error('Delete error:', error);
    alert('削除に失敗しました');
  } finally {
    setDeleting(false);
  }
}, [rectangleToDelete, pagesData, currentPageId]);
```

## OCR実行機能

### OCR処理フロー

**トリガー:** アクションボタンの「OCR」ボタン

**動作:**
1. 選択矩形の座標を144 DPI変換
2. `/api/documents/[id]/ocr-region` へPOST
3. 処理中は`ocrProcessing = rectId`
4. 結果を受信して`rectangles[].text`を更新
5. 選択中の場合はテキストエリアも更新
6. `hasChanges = true`

**実装:**

```typescript
// useOCRProcessing.ts
const handleOCR = useCallback(async (rectId: string, documentId: string) => {
  const currentPage = pagesData.find(p => p.id === currentPageId);
  const rectangle = currentPage?.rectangles.find(r => r.id === rectId);

  if (!rectangle) {
    alert('対象の矩形が見つかりません');
    return;
  }

  setOcrProcessing(rectId);
  setShowActionButtons(null);

  try {
    const rectangleScale = 2.0; // 144 DPI変換

    const response = await fetch(`/api/documents/${documentId}/ocr-region`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({
        x: Math.round(rectangle.x * rectangleScale),
        y: Math.round(rectangle.y * rectangleScale),
        width: Math.round(rectangle.width * rectangleScale),
        height: Math.round(rectangle.height * rectangleScale),
        page_number: currentPage.pageNumber,
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'OCR処理に失敗しました');
    }

    const data = await response.json();

    // OCR結果を反映
    setPagesData(prevPages =>
      prevPages.map(page =>
        page.id === currentPageId
          ? {
              ...page,
              rectangles: page.rectangles.map(r =>
                r.id === rectId
                  ? { ...r, text: data.text }
                  : r
              )
            }
          : page
      )
    );

    // 選択中の場合はテキストエリアも更新
    if (selectedRectId === rectId) {
      setCurrentText(data.text);
    }

    setHasChanges(true);
  } catch (error: any) {
    console.error('OCR error:', error);
    alert(`OCR処理に失敗しました: ${error.message}`);
  } finally {
    setOcrProcessing(null);
  }
}, [/* dependencies */]);
```

## 画像切り出し機能

### 切り出しフロー

**トリガー:** アクションボタンの「切り出し」ボタン

**動作:**
1. 選択矩形の座標を144 DPI変換
2. `/api/documents/[id]/crop-image` へPOST
3. Base64画像データを受信
4. モーダルでプレビュー表示
5. 保存ボタンでサーバーに保存
6. `croppedImagePath` を更新

**実装:**

```typescript
// useImageProcessing.ts
const handleCropImage = useCallback(async (rectId: string, documentId: string) => {
  const currentPage = pagesData.find(p => p.id === currentPageId);
  const rectangle = currentPage?.rectangles.find(r => r.id === rectId);

  if (!rectangle) {
    alert('対象の矩形が見つかりません');
    return;
  }

  setCropProcessing(rectId);

  try {
    const response = await fetch(`/api/documents/${documentId}/crop-image`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({
        x: Math.round(rectangle.x * rectangleScale),
        y: Math.round(rectangle.y * rectangleScale),
        width: Math.round(rectangle.width * rectangleScale),
        height: Math.round(rectangle.height * rectangleScale),
        page_number: currentPage.pageNumber,
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || '画像切り出しに失敗しました');
    }

    const data = await response.json();

    setCroppedImageData({
      imageData: data.image_data,
      filename: data.filename,
      rectId: rectId,
    });
    setShowImageModal(true);
  } catch (error: any) {
    console.error('Crop error:', error);
    alert(`画像切り出しに失敗しました: ${error.message}`);
  } finally {
    setCropProcessing(null);
  }
}, [pagesData, currentPageId, rectangleScale]);
```

## テキスト編集機能

### OCRTextEditor

**ファイル:** `/src/components/OCREditor/OCRTextEditor.tsx`

**機能:**

1. **要素タイプ選択:** 12種類のタイプから選択
2. **テキスト編集:** textarea で自由編集
3. **テーブル情報編集:** table_cellタイプの場合、col/row/cell_type編集
4. **変更検出:** 入力時に`hasChanges = true`

**実装:**

```typescript
export const OCRTextEditor: React.FC<Props> = ({
  currentText,
  currentElementType,
  selectedRectId,
  selectedRectangle,
  ocrProcessing,
  onTextChange,
  onElementTypeChange,
  onTableInfoChange,
  onChangesUpdate,
}) => {
  return (
    <div className="bg-white border rounded-lg flex flex-col" style={{ height: '40%' }}>
      {/* ヘッダー: 要素タイプ選択 */}
      <div className="px-3 py-2 border-b bg-gray-50">
        <h3 className="text-sm font-semibold">OCRテキスト</h3>
        <select
          value={currentElementType}
          onChange={(e) => {
            onElementTypeChange(e.target.value);
            onChangesUpdate(true);
          }}
          disabled={!selectedRectId || !!ocrProcessing}
        >
          <option value="text">text</option>
          <option value="title">title</option>
          {/* ... 全12タイプ ... */}
        </select>
      </div>

      {/* テーブル情報（table_cellの場合） */}
      {currentElementType === 'table_cell' && (
        <div className="px-3 py-2 border-b bg-blue-50">
          <h4 className="text-xs font-semibold">テーブル情報</h4>
          <div className="grid grid-cols-2 gap-2">
            <input
              type="number"
              value={selectedRectangle?.table_info?.col ?? 0}
              onChange={(e) => onTableInfoChange('col', parseInt(e.target.value))}
            />
            <input
              type="number"
              value={selectedRectangle?.table_info?.row ?? 0}
              onChange={(e) => onTableInfoChange('row', parseInt(e.target.value))}
            />
            <select
              value={selectedRectangle?.table_info?.cell_type ?? 'data'}
              onChange={(e) => onTableInfoChange('cell_type', e.target.value)}
            >
              <option value="data">データセル</option>
              <option value="col_header">列ヘッダー</option>
              <option value="row_header">行ヘッダー</option>
            </select>
          </div>
        </div>
      )}

      {/* テキスト編集エリア */}
      <div className="p-2 flex-1">
        <textarea
          value={currentText}
          onChange={(e) => {
            onTextChange(e.target.value);
            onChangesUpdate(true);
          }}
          disabled={!selectedRectId || !!ocrProcessing}
          className="w-full h-full p-2 border rounded text-xs resize-none"
        />
      </div>
    </div>
  );
};
```

## 階層構造ドラッグ&ドロップ

### ドラッグ可能なツリー

**動作:**

1. **ドラッグ開始:** 要素をドラッグ
2. **ドロップ位置決定:**
   - `before`: 上に挿入
   - `after`: 下に挿入
   - `inside`: 子要素として追加
3. **循環参照チェック:** 親が子の子孫にならないよう検証
4. **parent_id更新:** ドロップ位置に応じて更新

**実装:**

```typescript
// Line 828-920: ドラッグ&ドロップハンドラー
const handleDrop = (e: React.DragEvent, targetNodeId: string) => {
  e.preventDefault();
  if (!draggedItem || draggedItem === targetNodeId) return;

  const newRectangles = [...rectangles];
  const draggedIndex = newRectangles.findIndex((r) => r.id === draggedItem);
  const targetIndex = newRectangles.findIndex((r) => r.id === targetNodeId);
  const draggedRect = newRectangles[draggedIndex];
  const targetRect = newRectangles[targetIndex];

  if (!draggedRect || !targetRect) return;

  // 循環参照チェック
  const getAllChildren = (parent_id: string): string[] => {
    const children = newRectangles.filter((r) => r.parent_id === parent_id).map((r) => r.id);
    const allChildren = [...children];
    children.forEach((childId) => {
      allChildren.push(...getAllChildren(childId));
    });
    return allChildren;
  };

  const draggedChildren = getAllChildren(draggedItem);
  if (draggedChildren.includes(targetNodeId)) {
    return; // 循環参照を防止
  }

  // 要素を削除
  newRectangles.splice(draggedIndex, 1);

  // 新しい位置を計算
  const newTargetIndex = newRectangles.findIndex((r) => r.id === targetNodeId);
  let insertIndex = newTargetIndex;

  switch (dropPosition) {
    case "before":
      draggedRect.parent_id = targetRect.parent_id;
      insertIndex = newTargetIndex;
      break;
    case "after":
      draggedRect.parent_id = targetRect.parent_id;
      insertIndex = newTargetIndex + 1;
      break;
    case "inside":
      draggedRect.parent_id = targetNodeId;
      insertIndex = newTargetIndex + 1;
      break;
  }

  // 新しい位置に挿入
  newRectangles.splice(insertIndex, 0, draggedRect);
  updatePageRectangles(currentPageId, newRectangles);

  setDraggedItem(null);
  setDragOverItem(null);
  setDropPosition(null);
};
```

## ズーム機能

### ズームレベル管理

**範囲:** 0.5x 〜 3.0x (0.25刻み)

**ボタン:**
- `-`: ズームアウト
- `+`: ズームイン
- 表示: `{Math.round(zoomLevel * 100)}%`

**実装:**

```typescript
// Line 540-548
const handleZoomIn = () => {
  if (ocrOperations.ocrProcessing) return;
  setZoomLevel((prev) => Math.min(prev + 0.25, 3));
};

const handleZoomOut = () => {
  if (ocrOperations.ocrProcessing) return;
  setZoomLevel((prev) => Math.max(prev - 0.25, 0.5));
};
```

## 保存機能

### 保存処理

**トリガー:** ヘッダーの「保存」ボタン

**動作:**
1. `pagesData` から新しいメタデータを構築
2. フラット配列 (`rectangles`) から階層構造 (`hierarchical_elements`) を再構築
3. `reading_order` を計算
4. `/api/documents/[id]/metadata` へPUT
5. 保存後にメタデータを再取得
6. `hasChanges = false`

**実装:**

```typescript
// useMetadataOperations.ts: handleSave
const handleSave = useCallback(async (/* params */) => {
  if (saving) return;

  setSaving(true);

  try {
    // 現在のpagesDataから新しいメタデータを構築
    const updatedMetadata = { ...metadataData.metadata };
    updatedMetadata.pages = pagesData.map(page => {
      const originalPage = originalMetadata.pages.find(
        (p: any) => p.page_number === page.pageNumber
      );

      // フラット配列から階層構造を再構築
      const hierarchicalStructure = rebuildHierarchicalStructure(
        page.rectangles,
        originalPage?.hierarchical_elements || []
      );

      // reading_orderを計算
      const structureWithOrder = calculateHierarchicalReadingOrderFromTree(
        hierarchicalStructure
      );

      return {
        ...originalPage,
        page_number: page.pageNumber,
        hierarchical_elements: structureWithOrder,
      };
    });

    // バックエンドに保存
    await saveMetadata(documentId, updatedMetadata);

    // 保存後にメタデータを再取得
    const freshMetadata = await fetchMetadata(documentId);
    const freshPages = convertMetadataToPages(freshMetadata, documentId);

    setPagesData(freshPages);
    setOriginalMetadata(JSON.parse(JSON.stringify(freshMetadata.metadata)));
    setHasChanges(false);

    alert('メタデータを保存しました');
  } catch (error: any) {
    console.error('Save error:', error);
    alert(`保存に失敗しました: ${error.message}`);
  } finally {
    setSaving(false);
  }
}, [/* dependencies */]);
```

## RAG変換機能

### RAG変換フロー

**トリガー:** ヘッダーの「RAG変換」ボタン

**動作:**
1. 最新のメタデータを保存
2. ベクトル化処理を実行
3. 部分的成功 (422) / 完全成功 (200) / エラー (500) を処理
4. 結果メッセージを表示

**実装:**

```typescript
// Line 331-397: handleRAGConvert
const handleRAGConvert = async () => {
  if (!metadataData || !metadataData.metadata) {
    setRagError('メタデータが読み込まれていません');
    return;
  }

  setRagConverting(true);
  setRagError(null);
  setRagSuccess(null);
  setRagWarning(null);

  try {
    const response = await fetch(`/api/documents/${id}/rag-convert`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ metadata: metadataData.metadata }),
    });

    const result = await response.json();

    // 部分的成功の場合（422ステータス）
    if (response.status === 422 && result.status === 'partial_success') {
      setRagWarning(`${result.message}\n\n詳細: ${result.vector_error}`);
      setTimeout(() => setRagWarning(null), 10000);
      return;
    }

    // その他のエラーの場合
    if (!response.ok) {
      let errorMessage = result.error || 'RAG変換に失敗しました';
      if (result.vector_error) {
        errorMessage += `\n\nベクトル処理エラー: ${result.vector_error}`;
      }
      throw new Error(errorMessage);
    }

    // 完全成功の場合
    const successMessage = result.result?.chunks_created
      ? `RAG変換が正常に完了しました（${result.result.chunks_created}個のチャンクを作成）`
      : 'RAG変換が正常に完了しました';

    setRagSuccess(successMessage);
    setTimeout(() => setRagSuccess(null), 5000);

  } catch (error: any) {
    console.error('RAG convert error:', error);
    setRagError(error.message);
  } finally {
    setRagConverting(false);
  }
};
```

## まとめ

OCRエディタUIの設計により、以下を実現しています:

1. **直感的な操作:** ドラッグ&ドロップ、リサイズ、クリック選択
2. **高度な編集:** 階層構造、テキスト、タイプ、テーブル情報
3. **リアルタイムフィードバック:** 座標変換、ズーム、ハイライト
4. **統合ワークフロー:** OCR実行、画像切り出し、保存、RAG変換
5. **エラーハンドリング:** 境界チェック、循環参照防止、最小サイズ制限

これらにより、管理者は複雑なドキュメント構造を視覚的に編集し、高品質なOCR結果を作成できます。