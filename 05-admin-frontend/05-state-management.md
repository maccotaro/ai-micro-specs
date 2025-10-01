# 05-state-management.md - 状態管理設計

## 概要

Admin Frontendでは、複雑な状態管理を効率的に行うため、以下の技術を組み合わせています:

1. **React Hooks**: ローカル状態管理（useState, useReducer）
2. **Custom Hooks**: ドメインロジックのカプセル化
3. **Context API**: グローバル状態共有（認証など）
4. **React Query (TanStack Query)**: サーバー状態管理（将来導入予定）

## 状態の分類

### 1. サーバー状態 (Server State)

バックエンドから取得・同期するデータ

- ユーザー一覧
- ドキュメント一覧
- ナレッジベース一覧
- ダッシュボード統計
- ジョブステータス

### 2. クライアント状態 (Client State)

フロントエンド独自の状態

- UI状態（モーダル開閉、選択状態など）
- フォーム入力値
- ページネーション情報
- フィルター条件

### 3. グローバル状態 (Global State)

アプリ全体で共有する状態

- 認証情報（ユーザー、Token）
- アプリ設定
- テーマ設定

## Custom Hooks設計

### useMetadataOperations

**目的:** OCR調整画面でのメタデータ操作を一元管理

**ファイル:** `/src/hooks/useMetadataOperations.ts`

```typescript
interface UseMetadataOperationsProps {
  pagesData: DocumentPage[];
  originalMetadata: any;
  metadataData: any;
}

interface UseMetadataOperationsReturn {
  fetchMetadata: (documentId: string) => Promise<any>;
  saveMetadata: (documentId: string, metadata: any) => Promise<any>;
  handleSave: (
    documentId: string,
    saving: boolean,
    setSaving: (v: boolean) => void,
    setHasChanges: (v: boolean) => void,
    setPagesData: (pages: DocumentPage[]) => void,
    setOriginalMetadata: (metadata: any) => void,
    convertMetadataToPages: Function
  ) => Promise<void>;
  rebuildHierarchicalStructure: (
    flatRectangles: Rectangle[],
    originalElements?: any[]
  ) => any[];
  calculateHierarchicalReadingOrderFromTree: (elements: any[]) => any[];
}

export const useMetadataOperations = ({
  pagesData,
  originalMetadata,
  metadataData
}: UseMetadataOperationsProps): UseMetadataOperationsReturn => {

  // メタデータ取得
  const fetchMetadata = useCallback(async (documentId: string) => {
    try {
      const response = await fetch(`/api/documents/${documentId}/metadata`, {
        method: 'GET',
        credentials: 'include',
        cache: 'no-cache',
      });

      if (!response.ok) {
        if (response.status === 401) {
          // 認証エラーはuseAuthで処理
          return;
        }
        const error = await response.json();
        throw new Error(error.error || 'Failed to retrieve metadata');
      }

      return await response.json();
    } catch (error) {
      console.error('Metadata fetch error:', error);
      throw error;
    }
  }, []);

  // メタデータ保存
  const saveMetadata = useCallback(async (documentId: string, metadata: any) => {
    try {
      const response = await fetch(`/api/documents/${documentId}/metadata`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ metadata }),
      });

      if (!response.ok) {
        if (response.status === 401) {
          return;
        }
        const error = await response.json();
        throw new Error(error.error || 'Failed to save metadata');
      }

      return await response.json();
    } catch (error) {
      console.error('Metadata save error:', error);
      throw error;
    }
  }, []);

  // フラット配列から階層構造を再構築
  const rebuildHierarchicalStructure = useCallback((
    flatRectangles: Rectangle[],
    originalElements: any[] = []
  ): any[] => {
    const rootElements = flatRectangles.filter(r => !r.parent_id);

    const buildElement = (rect: Rectangle): any => {
      const children = flatRectangles
        .filter(r => r.parent_id === rect.id)
        .map(childRect => buildElement(childRect));

      return {
        id: rect.id,
        type: rect.type,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        bbox: [rect.x, rect.y, rect.x + rect.width, rect.y + rect.height],
        text: rect.text || "",
        parent_id: rect.parent_id,
        table_info: rect.table_info,
        cropped_image_path: rect.croppedImagePath,
        children: children.length > 0 ? children : undefined,
      };
    };

    return rootElements.map(rootRect => buildElement(rootRect));
  }, []);

  // 階層構造からreading_orderを計算
  const calculateHierarchicalReadingOrderFromTree = useCallback((
    hierarchicalElements: any[]
  ): any[] => {
    let orderCounter = 0;

    const assignOrder = (element: any): any => {
      const orderedElement = {
        ...element,
        reading_order: orderCounter++,
      };

      if (element.children && element.children.length > 0) {
        orderedElement.children = element.children.map(assignOrder);
      }

      return orderedElement;
    };

    return hierarchicalElements.map(assignOrder);
  }, []);

  // 保存ハンドラ
  const handleSave = useCallback(async (
    documentId: string,
    saving: boolean,
    setSaving: (v: boolean) => void,
    setHasChanges: (v: boolean) => void,
    setPagesData: (pages: DocumentPage[]) => void,
    setOriginalMetadata: (metadata: any) => void,
    convertMetadataToPages: Function
  ) => {
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
  }, [pagesData, originalMetadata, metadataData, rebuildHierarchicalStructure, calculateHierarchicalReadingOrderFromTree, saveMetadata, fetchMetadata]);

  return {
    fetchMetadata,
    saveMetadata,
    handleSave,
    rebuildHierarchicalStructure,
    calculateHierarchicalReadingOrderFromTree,
  };
};
```

**使用例:**

```typescript
// OCR調整画面での使用
function OCRResultPage() {
  const [pagesData, setPagesData] = useState<DocumentPage[]>([]);
  const [originalMetadata, setOriginalMetadata] = useState<any>(null);
  const [metadataData, setMetadataData] = useState<any>(null);

  const metadataOperations = useMetadataOperations({
    pagesData,
    originalMetadata,
    metadataData
  });

  const handleSave = async () => {
    await metadataOperations.handleSave(
      id as string,
      saving,
      setSaving,
      setHasChanges,
      setPagesData,
      setOriginalMetadata,
      convertMetadataToPages
    );
  };

  return (
    <Layout>
      <button onClick={handleSave}>保存</button>
      {/* ... */}
    </Layout>
  );
}
```

### useRectangleOperations

**目的:** OCR調整画面での矩形操作を一元管理

**ファイル:** `/src/hooks/useRectangleOperations.ts`

```typescript
interface UseRectangleOperationsProps {
  pagesData: DocumentPage[];
  setPagesData: (pages: DocumentPage[]) => void;
  currentPageId: string;
  setCurrentText: (text: string) => void;
  setCurrentElementType: (type: string) => void;
  setHasChanges: (hasChanges: boolean) => void;
  zoomLevel: number;
  rectangleScale: number;
  naturalImageWidth: number;
  naturalImageHeight: number;
  previewRef: React.RefObject<HTMLDivElement>;
  expandedNodes: Set<string>;
  setExpandedNodes: (nodes: Set<string>) => void;
  pages: DocumentPage[];
  onScrollToTreeElement: (rectId: string) => void;
}

interface UseRectangleOperationsReturn {
  selectedRectId: string | null;
  setSelectedRectId: (id: string | null) => void;
  showActionButtons: string | null;
  setShowActionButtons: (id: string | null) => void;
  isDraggingRect: boolean;
  setIsDraggingRect: (dragging: boolean) => void;
  isResizing: boolean;
  setIsResizing: (resizing: boolean) => void;
  resizeHandle: string | null;
  setResizeHandle: (handle: string | null) => void;
  showDeleteConfirm: boolean;
  setShowDeleteConfirm: (show: boolean) => void;
  rectangleToDelete: Rectangle | null;
  setRectangleToDelete: (rect: Rectangle | null) => void;
  deleting: boolean;

  handleRectClick: (rectId: string) => void;
  handleRectMouseDown: (e: React.MouseEvent, rectId: string) => void;
  handleRectangleDrag: (e: React.MouseEvent) => void;
  handleResize: (e: React.MouseEvent) => void;
  handleMouseUp: () => void;
  handleDeleteClick: (rectId: string, ocrProcessing?: boolean) => void;
  handleRectangleDelete: () => Promise<void>;
}

export const useRectangleOperations = ({
  pagesData,
  setPagesData,
  currentPageId,
  setCurrentText,
  setCurrentElementType,
  setHasChanges,
  zoomLevel,
  rectangleScale,
  naturalImageWidth,
  naturalImageHeight,
  previewRef,
  expandedNodes,
  setExpandedNodes,
  pages,
  onScrollToTreeElement,
}: UseRectangleOperationsProps): UseRectangleOperationsReturn => {

  const [selectedRectId, setSelectedRectId] = useState<string | null>(null);
  const [showActionButtons, setShowActionButtons] = useState<string | null>(null);
  const [isDraggingRect, setIsDraggingRect] = useState(false);
  const [dragStart, setDragStart] = useState<{ x: number; y: number } | null>(null);
  const [dragOffset, setDragOffset] = useState<{ x: number; y: number } | null>(null);
  const [isResizing, setIsResizing] = useState(false);
  const [resizeHandle, setResizeHandle] = useState<string | null>(null);
  const [resizeStart, setResizeStart] = useState<Rectangle | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [rectangleToDelete, setRectangleToDelete] = useState<Rectangle | null>(null);
  const [deleting, setDeleting] = useState(false);

  // 矩形クリック処理
  const handleRectClick = useCallback((rectId: string) => {
    setSelectedRectId(rectId);
    setShowActionButtons(rectId);

    // テキストと要素タイプを更新
    const currentPage = pagesData.find(p => p.id === currentPageId);
    const rect = currentPage?.rectangles.find(r => r.id === rectId);

    if (rect) {
      setCurrentText(rect.text || "");
      setCurrentElementType(rect.type || "text");
    }

    onScrollToTreeElement(rectId);
  }, [pagesData, currentPageId, setCurrentText, setCurrentElementType, onScrollToTreeElement]);

  // 矩形ドラッグ開始
  const handleRectMouseDown = useCallback((e: React.MouseEvent, rectId: string) => {
    if (isResizing) return; // リサイズ中はドラッグ無効

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

  // 矩形ドラッグ中
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
  }, [isDraggingRect, selectedRectId, dragOffset, pagesData, currentPageId, previewRef, zoomLevel, rectangleScale, naturalImageWidth, naturalImageHeight, setPagesData, setHasChanges]);

  // リサイズ処理
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
  }, [isResizing, selectedRectId, resizeStart, resizeHandle, pagesData, currentPageId, previewRef, zoomLevel, rectangleScale, naturalImageWidth, naturalImageHeight, setPagesData, setHasChanges]);

  // マウスアップ処理
  const handleMouseUp = useCallback(() => {
    if (isDraggingRect) {
      setIsDraggingRect(false);
      setDragStart(null);
      setDragOffset(null);

      if (selectedRectId) {
        setTimeout(() => {
          setShowActionButtons(selectedRectId);
        }, 100);
      }
    }

    if (isResizing) {
      setIsResizing(false);
      setResizeHandle(null);
      setResizeStart(null);

      if (selectedRectId) {
        setTimeout(() => {
          setShowActionButtons(selectedRectId);
        }, 100);
      }
    }
  }, [isDraggingRect, isResizing, selectedRectId]);

  // 削除確認ダイアログ表示
  const handleDeleteClick = useCallback((rectId: string, ocrProcessing?: boolean) => {
    if (ocrProcessing) return;

    const currentPage = pagesData.find(p => p.id === currentPageId);
    const rect = currentPage?.rectangles.find(r => r.id === rectId);

    if (rect) {
      setRectangleToDelete(rect);
      setShowDeleteConfirm(true);
    }
  }, [pagesData, currentPageId]);

  // 削除実行
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
  }, [rectangleToDelete, pagesData, currentPageId, setPagesData, setHasChanges]);

  return {
    selectedRectId,
    setSelectedRectId,
    showActionButtons,
    setShowActionButtons,
    isDraggingRect,
    setIsDraggingRect,
    isResizing,
    setIsResizing,
    resizeHandle,
    setResizeHandle,
    showDeleteConfirm,
    setShowDeleteConfirm,
    rectangleToDelete,
    setRectangleToDelete,
    deleting,
    handleRectClick,
    handleRectMouseDown,
    handleRectangleDrag,
    handleResize,
    handleMouseUp,
    handleDeleteClick,
    handleRectangleDelete,
  };
};
```

### useOCRProcessing

**目的:** OCR処理の実行とステータス管理

**ファイル:** `/src/hooks/useOCRProcessing.ts`

```typescript
interface UseOCRProcessingProps {
  pagesData: DocumentPage[];
  setPagesData: (pages: DocumentPage[]) => void;
  setHasChanges: (hasChanges: boolean) => void;
  currentPageId: string;
  selectedRectId: string | null;
  setCurrentText: (text: string) => void;
  setShowActionButtons: (id: string | null) => void;
}

interface UseOCRProcessingReturn {
  ocrProcessing: string | null;
  handleOCR: (rectId: string, documentId: string) => Promise<void>;
}

export const useOCRProcessing = ({
  pagesData,
  setPagesData,
  setHasChanges,
  currentPageId,
  selectedRectId,
  setCurrentText,
  setShowActionButtons,
}: UseOCRProcessingProps): UseOCRProcessingReturn => {

  const [ocrProcessing, setOcrProcessing] = useState<string | null>(null);

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
      const rectangleScale = 2.0; // 144 DPI

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
  }, [pagesData, currentPageId, selectedRectId, setPagesData, setCurrentText, setHasChanges, setShowActionButtons]);

  return {
    ocrProcessing,
    handleOCR,
  };
};
```

### useImageProcessing

**目的:** 画像切り出しと保存処理

**ファイル:** `/src/hooks/useImageProcessing.ts`

```typescript
interface UseImageProcessingProps {
  pagesData: DocumentPage[];
  setPagesData: (pages: DocumentPage[]) => void;
  currentPageId: string;
  rectangleScale: number;
}

interface UseImageProcessingReturn {
  cropProcessing: string | null;
  showImageModal: boolean;
  croppedImageData: CroppedImageData | null;
  hoverImagePath: string | null;
  setShowImageModal: (show: boolean) => void;
  setCroppedImageData: (data: CroppedImageData | null) => void;
  setHoverImagePath: (path: string | null) => void;
  handleCropImage: (rectId: string, documentId: string) => Promise<void>;
  handleImageSaved: () => void;
}

export const useImageProcessing = ({
  pagesData,
  setPagesData,
  currentPageId,
  rectangleScale,
}: UseImageProcessingProps): UseImageProcessingReturn => {

  const [cropProcessing, setCropProcessing] = useState<string | null>(null);
  const [showImageModal, setShowImageModal] = useState(false);
  const [croppedImageData, setCroppedImageData] = useState<CroppedImageData | null>(null);
  const [hoverImagePath, setHoverImagePath] = useState<string | null>(null);

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

  const handleImageSaved = useCallback(() => {
    // 保存後の処理（必要に応じて）
    setShowImageModal(false);
    setCroppedImageData(null);
  }, []);

  return {
    cropProcessing,
    showImageModal,
    croppedImageData,
    hoverImagePath,
    setShowImageModal,
    setCroppedImageData,
    setHoverImagePath,
    handleCropImage,
    handleImageSaved,
  };
};
```

### useDocumentDelete

**目的:** ドキュメント削除処理とステータス管理

**ファイル:** `/src/hooks/useDocumentDelete.ts`

```typescript
interface UseDocumentDeleteOptions {
  onSuccess?: () => void;
  onError?: (error: Error) => void;
}

interface UseDocumentDeleteReturn {
  showDeleteConfirm: boolean;
  documentToDelete: KnowledgeDocument | null;
  isDeleting: boolean;
  handleDeleteClick: (document: KnowledgeDocument) => void;
  handleDelete: () => Promise<void>;
  handleCancelDelete: () => void;
  setShowDeleteConfirm: (show: boolean) => void;
}

export const useDocumentDelete = ({
  onSuccess,
  onError,
}: UseDocumentDeleteOptions = {}): UseDocumentDeleteReturn => {

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [documentToDelete, setDocumentToDelete] = useState<KnowledgeDocument | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const handleDeleteClick = useCallback((document: KnowledgeDocument) => {
    setDocumentToDelete(document);
    setShowDeleteConfirm(true);
  }, []);

  const handleDelete = useCallback(async () => {
    if (!documentToDelete) return;

    setIsDeleting(true);

    try {
      const response = await fetch(`/api/documents/${documentToDelete.id}`, {
        method: 'DELETE',
        credentials: 'include',
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'ドキュメントの削除に失敗しました');
      }

      setShowDeleteConfirm(false);
      setDocumentToDelete(null);
      onSuccess?.();
    } catch (error: any) {
      console.error('Delete error:', error);
      onError?.(error);
    } finally {
      setIsDeleting(false);
    }
  }, [documentToDelete, onSuccess, onError]);

  const handleCancelDelete = useCallback(() => {
    setShowDeleteConfirm(false);
    setDocumentToDelete(null);
  }, []);

  return {
    showDeleteConfirm,
    documentToDelete,
    isDeleting,
    handleDeleteClick,
    handleDelete,
    handleCancelDelete,
    setShowDeleteConfirm,
  };
};
```

## 座標系変換Hook

### useCoordinateSystem

**目的:** メタデータからページデータへの変換

**ファイル:** `/src/hooks/useCoordinateSystem.ts`

```typescript
export function convertMetadataToPages(
  metadata: any,
  documentId: string,
  setNaturalImageWidth: (width: number) => void,
  setNaturalImageHeight: (height: number) => void
): DocumentPage[] {
  if (!metadata?.metadata?.pages) {
    return [];
  }

  const pages = metadata.metadata.pages.map((page: any, index: number) => {
    const pageId = `page-${page.page_number || index + 1}`;

    // 画像サイズを設定（最初のページのみ）
    if (index === 0 && page.width && page.height) {
      setNaturalImageWidth(page.width);
      setNaturalImageHeight(page.height);
    }

    // 階層構造からフラット配列に変換
    const flattenElements = (elements: any[], parentId?: string): Rectangle[] => {
      const result: Rectangle[] = [];

      elements.forEach(element => {
        const rect: Rectangle = {
          id: element.id,
          type: element.type || element.obj_type || 'text',
          x: element.x || element.bbox?.[0] || 0,
          y: element.y || element.bbox?.[1] || 0,
          width: element.width || (element.bbox ? element.bbox[2] - element.bbox[0] : 0),
          height: element.height || (element.bbox ? element.bbox[3] - element.bbox[1] : 0),
          text: element.text || "",
          parent_id: parentId,
          table_info: element.table_info,
          croppedImagePath: element.cropped_image_path,
        };

        result.push(rect);

        // 子要素を再帰的に処理
        if (element.children && element.children.length > 0) {
          result.push(...flattenElements(element.children, element.id));
        }
      });

      return result;
    };

    const rectangles = page.hierarchical_elements
      ? flattenElements(page.hierarchical_elements)
      : [];

    return {
      id: pageId,
      name: `Page ${page.page_number || index + 1}`,
      pageNumber: page.page_number || index + 1,
      imagePath: `/api/documents/${documentId}/images/page_${String(page.page_number || index + 1).padStart(4, '0')}.png`,
      rectangles,
    };
  });

  return pages;
}
```

## Context APIの使用

### AuthContext

既に `04-authentication-client.md` で詳述済み

```typescript
// src/hooks/useAuth.tsx
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  // 認証状態管理
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
```

## 状態管理のベストプラクティス

### 1. 状態の配置

**ローカル状態:**
- コンポーネント内で完結する状態
- 親コンポーネントに影響しない状態

**リフトアップ:**
- 複数コンポーネントで共有する状態
- 共通の親に配置

**Custom Hooks:**
- ドメインロジック+状態
- 再利用性の高い処理

**Context:**
- アプリ全体で共有する状態
- prop drillingを避けたい場合

### 2. 命名規則

```typescript
// 状態
const [isLoading, setIsLoading] = useState(false);
const [hasError, setHasError] = useState(false);
const [showModal, setShowModal] = useState(false);

// ハンドラ
const handleSubmit = () => {};
const handleChange = () => {};
const handleClick = () => {};

// Hooks
const useDocumentList = () => {};
const useAuth = () => {};
const usePermission = () => {};
```

### 3. パフォーマンス最適化

```typescript
// useMemo: 重い計算結果をメモ化
const filteredDocuments = useMemo(() => {
  return documents.filter(doc => doc.status === filterStatus);
}, [documents, filterStatus]);

// useCallback: 関数をメモ化
const handleDelete = useCallback((id: string) => {
  // 削除処理
}, [dependencies]);

// React.memo: コンポーネントのメモ化
export const DocumentCard = React.memo(({ document }: Props) => {
  // ...
});
```

### 4. エラーハンドリング

```typescript
const [error, setError] = useState<string | null>(null);

try {
  // API呼び出し
} catch (err: any) {
  setError(err.message);
  console.error('Error:', err);
}

// エラー表示
{error && <Alert variant="destructive">{error}</Alert>}
```

## まとめ

Admin Frontendの状態管理設計により、以下を実現しています:

1. **責務の分離:** ドメインロジックをCustom Hooksにカプセル化
2. **再利用性:** 共通処理の抽出と再利用
3. **保守性:** 状態とロジックの一元管理
4. **パフォーマンス:** 適切なメモ化と最適化
5. **型安全性:** TypeScriptによる型定義

これらの設計により、複雑な状態管理が必要なOCR調整画面でも、明確で保守しやすいコードが実現されています。