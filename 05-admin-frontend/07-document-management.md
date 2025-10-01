# 07-document-management.md - ドキュメント管理機能

## 概要

Admin Frontendのドキュメント管理機能は、PDFや Office ドキュメントのアップロード、Docling 処理ジョブの管理、OCR 結果の編集、RAG変換を統合的に提供します。

## ドキュメントライフサイクル

```
┌─────────────┐
│  アップロード │
│  /documents │
│  /new       │
└──────┬──────┘
       │
       ↓
┌─────────────────┐
│  処理キュー投入  │
│  Status: uploaded│
└──────┬──────────┘
       │
       ↓
┌─────────────────┐
│  Docling処理    │
│  Status:        │
│  processing     │
└──────┬──────────┘
       │
       ↓
┌─────────────────┐
│  OCR結果保存    │
│  Status:        │
│  processed      │
└──────┬──────────┘
       │
       ↓ (optional)
┌─────────────────┐
│  OCR調整        │
│  /documents/ocr/│
│  [id]           │
└──────┬──────────┘
       │
       ↓ (optional)
┌─────────────────┐
│  RAG変換        │
│  ベクトル化     │
└──────┬──────────┘
       │
       ↓
┌─────────────────┐
│  検索・チャット │
│  利用可能       │
└─────────────────┘
```

## ドキュメント一覧画面

### 画面構成

**ファイル:** `/src/pages/documents/index.tsx`

```typescript
export default function DocumentsPage() {
  const [documents, setDocuments] = useState<KnowledgeDocument[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState('');
  const [filterKnowledgeBase, setFilterKnowledgeBase] = useState('');
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [stats, setStats] = useState<DocumentStats | null>(null);

  // ドキュメント取得
  useEffect(() => {
    fetchDocuments();
    fetchStats();
  }, [currentPage, searchTerm, filterStatus, filterKnowledgeBase]);

  return (
    <Layout maxWidth="max-w-7xl">
      <div className="space-y-6">
        {/* ページヘッダー */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">ドキュメント管理</h1>
            <p className="text-sm text-gray-600">アップロード済みドキュメントの管理</p>
          </div>
          <Button onClick={() => router.push('/documents/new')}>
            <Plus className="w-4 h-4 mr-2" />
            新規アップロード
          </Button>
        </div>

        {/* 統計カード */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <StatCard
            title="総ドキュメント数"
            value={stats?.total || 0}
            icon={FileText}
          />
          <StatCard
            title="処理完了"
            value={stats?.processed || 0}
            icon={CheckCircle}
            color="green"
          />
          <StatCard
            title="処理中"
            value={stats?.processing || 0}
            icon={Clock}
            color="yellow"
          />
          <StatCard
            title="失敗"
            value={stats?.failed || 0}
            icon={XCircle}
            color="red"
          />
        </div>

        {/* フィルターパネル */}
        <Card>
          <CardContent className="pt-6">
            <div className="flex flex-wrap gap-4">
              <div className="flex-1 min-w-64">
                <Input
                  placeholder="ドキュメント名で検索..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  icon={<Search className="w-4 h-4" />}
                />
              </div>
              <Select value={filterStatus} onValueChange={setFilterStatus}>
                <SelectTrigger className="w-40">
                  <SelectValue placeholder="ステータス" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="">すべて</SelectItem>
                  <SelectItem value="uploaded">アップロード済み</SelectItem>
                  <SelectItem value="processing">処理中</SelectItem>
                  <SelectItem value="processed">処理完了</SelectItem>
                  <SelectItem value="failed">失敗</SelectItem>
                </SelectContent>
              </Select>
              <Select value={filterKnowledgeBase} onValueChange={setFilterKnowledgeBase}>
                <SelectTrigger className="w-48">
                  <SelectValue placeholder="ナレッジベース" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="">すべて</SelectItem>
                  {knowledgeBases.map(kb => (
                    <SelectItem key={kb.id} value={kb.id}>{kb.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button variant="outline" onClick={handleRefresh}>
                <RefreshCw className="w-4 h-4 mr-2" />
                更新
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* ドキュメントテーブル */}
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>ドキュメント名</TableHead>
                <TableHead>タイプ</TableHead>
                <TableHead>ステータス</TableHead>
                <TableHead>ナレッジベース</TableHead>
                <TableHead>サイズ</TableHead>
                <TableHead>アップロード日時</TableHead>
                <TableHead className="text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {documents.map(doc => (
                <TableRow key={doc.id}>
                  <TableCell className="font-medium">{doc.filename}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{getMimeTypeLabel(doc.mime_type)}</Badge>
                  </TableCell>
                  <TableCell>
                    <Badge className={statusColors[doc.status]}>
                      <StatusIcon className="w-4 h-4 mr-1" />
                      {statusLabels[doc.status]}
                    </Badge>
                  </TableCell>
                  <TableCell>{getKnowledgeBaseName(doc.knowledge_base_id)}</TableCell>
                  <TableCell>{formatBytes(doc.file_size)}</TableCell>
                  <TableCell>{formatDate(doc.created_at)}</TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="sm">
                          <MoreVertical className="w-4 h-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onClick={() => handleView(doc)}>
                          <Eye className="w-4 h-4 mr-2" />
                          表示
                        </DropdownMenuItem>
                        {doc.status === 'processed' && (
                          <DropdownMenuItem onClick={() => handleEditOCR(doc)}>
                            <Edit className="w-4 h-4 mr-2" />
                            OCR調整
                          </DropdownMenuItem>
                        )}
                        {doc.status === 'failed' && (
                          <DropdownMenuItem onClick={() => handleReprocess(doc)}>
                            <RefreshCw className="w-4 h-4 mr-2" />
                            再処理
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          onClick={() => handleDeleteClick(doc)}
                          className="text-destructive"
                        >
                          <Trash2 className="w-4 h-4 mr-2" />
                          削除
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>

          {/* ページネーション */}
          <div className="flex items-center justify-between px-4 py-3 border-t">
            <div className="text-sm text-gray-500">
              {totalDocuments}件中 {(currentPage - 1) * limit + 1} - {Math.min(currentPage * limit, totalDocuments)}件を表示
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                disabled={currentPage === 1}
              >
                前へ
              </Button>
              <span className="flex items-center px-3 text-sm">
                {currentPage} / {totalPages}
              </span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                disabled={currentPage === totalPages}
              >
                次へ
              </Button>
            </div>
          </div>
        </Card>
      </div>

      {/* 削除確認ダイアログ */}
      <DocumentDeleteDialog
        isOpen={showDeleteConfirm}
        document={documentToDelete}
        onConfirm={handleDelete}
        onCancel={handleCancelDelete}
        isDeleting={isDeleting}
      />
    </Layout>
  );
}
```

### データ取得

```typescript
// ドキュメント一覧取得
const fetchDocuments = async () => {
  setLoading(true);
  setError(null);

  try {
    const params = new URLSearchParams();
    params.set('page', currentPage.toString());
    params.set('limit', limit.toString());
    if (searchTerm) params.set('search', searchTerm);
    if (filterStatus) params.set('status', filterStatus);
    if (filterKnowledgeBase) params.set('knowledge_base_id', filterKnowledgeBase);

    const response = await fetch(`/api/documents?${params.toString()}`, {
      credentials: 'include',
    });

    if (!response.ok) {
      throw new Error('Failed to fetch documents');
    }

    const data: KnowledgeDocumentListResponse = await response.json();
    setDocuments(data.documents || []);
    setTotalDocuments(data.total || 0);
    setTotalPages(data.pages || 1);
  } catch (err) {
    console.error('Error fetching documents:', err);
    setError('ドキュメント一覧の取得に失敗しました');
  } finally {
    setLoading(false);
  }
};

// 統計情報取得
const fetchStats = async () => {
  try {
    const response = await fetch('/api/documents/stats', {
      credentials: 'include',
    });

    if (response.ok) {
      const data: DocumentStats = await response.json();
      setStats(data);
    }
  } catch (err) {
    console.error('Error fetching stats:', err);
  }
};
```

## ドキュメントアップロード画面

### アップロードフロー

**ファイル:** `/src/pages/documents/new.tsx`

```typescript
export default function DocumentUploadPage() {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [knowledgeBaseId, setKnowledgeBaseId] = useState('');
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      // ファイルサイズチェック (50MB)
      if (file.size > 50 * 1024 * 1024) {
        setError('ファイルサイズが50MBを超えています');
        return;
      }

      // MIMEタイプチェック
      const allowedTypes = [
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ];

      if (!allowedTypes.includes(file.type)) {
        setError('対応していないファイル形式です');
        return;
      }

      setSelectedFile(file);
      setError(null);
    }
  };

  const handleUpload = async () => {
    if (!selectedFile || !knowledgeBaseId) {
      setError('ファイルとナレッジベースを選択してください');
      return;
    }

    setUploading(true);
    setError(null);
    setUploadProgress(0);

    try {
      const formData = new FormData();
      formData.append('file', selectedFile);
      formData.append('knowledge_base_id', knowledgeBaseId);

      const xhr = new XMLHttpRequest();

      // 進捗監視
      xhr.upload.addEventListener('progress', (e) => {
        if (e.lengthComputable) {
          const progress = (e.loaded / e.total) * 100;
          setUploadProgress(Math.round(progress));
        }
      });

      // 完了処理
      xhr.addEventListener('load', () => {
        if (xhr.status === 200 || xhr.status === 201) {
          const data = JSON.parse(xhr.responseText);

          // 処理ジョブのポーリング開始
          if (data.job_id) {
            pollJobStatus(data.job_id);
          } else {
            router.push('/documents');
          }
        } else {
          const error = JSON.parse(xhr.responseText);
          throw new Error(error.error || 'アップロードに失敗しました');
        }
      });

      xhr.addEventListener('error', () => {
        throw new Error('アップロード中にエラーが発生しました');
      });

      xhr.open('POST', '/api/documents/upload');
      xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
      xhr.send(formData);
    } catch (err: any) {
      console.error('Upload error:', err);
      setError(err.message || 'アップロードに失敗しました');
      setUploading(false);
    }
  };

  const pollJobStatus = async (jobId: string) => {
    const pollInterval = 2000; // 2秒
    const maxAttempts = 150; // 最大5分
    let attempts = 0;

    const poll = async () => {
      try {
        const response = await fetch(`/api/jobs/${jobId}`, {
          credentials: 'include',
        });

        if (!response.ok) {
          throw new Error('ジョブステータスの取得に失敗しました');
        }

        const job = await response.json();

        if (job.status === 'completed') {
          // 処理完了
          router.push('/documents');
        } else if (job.status === 'failed') {
          // 処理失敗
          throw new Error(job.error || 'ドキュメント処理に失敗しました');
        } else if (attempts < maxAttempts) {
          // 継続してポーリング
          attempts++;
          setTimeout(poll, pollInterval);
        } else {
          // タイムアウト
          throw new Error('処理がタイムアウトしました');
        }
      } catch (err: any) {
        console.error('Job polling error:', err);
        setError(err.message);
        setUploading(false);
      }
    };

    poll();
  };

  return (
    <Layout maxWidth="max-w-2xl">
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">ドキュメントアップロード</h1>
          <p className="text-sm text-gray-600">新しいドキュメントをアップロードして処理します</p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>ファイル選択</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* ドラッグ&ドロップエリア */}
            <div
              className={cn(
                "border-2 border-dashed rounded-lg p-8 text-center",
                selectedFile ? "border-green-500 bg-green-50" : "border-gray-300"
              )}
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => {
                e.preventDefault();
                const file = e.dataTransfer.files[0];
                if (file) {
                  handleFileSelect({ target: { files: [file] } } as any);
                }
              }}
            >
              {selectedFile ? (
                <div className="space-y-2">
                  <FileText className="w-12 h-12 mx-auto text-green-500" />
                  <p className="font-medium">{selectedFile.name}</p>
                  <p className="text-sm text-gray-500">
                    {formatBytes(selectedFile.size)}
                  </p>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setSelectedFile(null)}
                  >
                    変更
                  </Button>
                </div>
              ) : (
                <div className="space-y-2">
                  <Upload className="w-12 h-12 mx-auto text-gray-400" />
                  <p className="text-sm font-medium">ファイルをドラッグ&ドロップ</p>
                  <p className="text-xs text-gray-500">または</p>
                  <Button
                    variant="outline"
                    onClick={() => document.getElementById('file-input')?.click()}
                  >
                    ファイルを選択
                  </Button>
                  <input
                    id="file-input"
                    type="file"
                    className="hidden"
                    accept=".pdf,.docx,.pptx"
                    onChange={handleFileSelect}
                  />
                  <p className="text-xs text-gray-500 mt-2">
                    対応形式: PDF, DOCX, PPTX (最大50MB)
                  </p>
                </div>
              )}
            </div>

            {/* ナレッジベース選択 */}
            <div>
              <Label>ナレッジベース</Label>
              <Select value={knowledgeBaseId} onValueChange={setKnowledgeBaseId}>
                <SelectTrigger>
                  <SelectValue placeholder="選択してください" />
                </SelectTrigger>
                <SelectContent>
                  {knowledgeBases.map(kb => (
                    <SelectItem key={kb.id} value={kb.id}>
                      {kb.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* エラー表示 */}
            {error && (
              <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* 進捗表示 */}
            {uploading && (
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span>アップロード中...</span>
                  <span>{uploadProgress}%</span>
                </div>
                <Progress value={uploadProgress} />
              </div>
            )}
          </CardContent>
          <CardFooter className="flex justify-between">
            <Button variant="outline" onClick={() => router.back()}>
              キャンセル
            </Button>
            <Button
              onClick={handleUpload}
              disabled={!selectedFile || !knowledgeBaseId || uploading}
            >
              {uploading ? 'アップロード中...' : 'アップロード'}
            </Button>
          </CardFooter>
        </Card>
      </div>
    </Layout>
  );
}
```

## ドキュメント削除

### 削除確認ダイアログ

**ファイル:** `/src/components/documents/DocumentDeleteDialog.tsx`

```typescript
interface DocumentDeleteDialogProps {
  isOpen: boolean;
  document: KnowledgeDocument | null;
  onConfirm: () => Promise<void>;
  onCancel: () => void;
  isDeleting: boolean;
}

export function DocumentDeleteDialog({
  isOpen,
  document,
  onConfirm,
  onCancel,
  isDeleting,
}: DocumentDeleteDialogProps) {
  return (
    <AlertDialog open={isOpen} onOpenChange={onCancel}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle className="flex items-center gap-2">
            <ExclamationTriangle className="h-5 w-5 text-destructive" />
            ドキュメントの削除
          </AlertDialogTitle>
          <AlertDialogDescription>
            {document && (
              <>
                「{document.filename}」を削除しようとしています。
                <br />
                <br />
                このドキュメントに関連するすべてのデータ（OCR結果、ベクトルデータ、チャンク）も削除されます。
                <br />
                <br />
                <strong>この操作は取り消すことができません。</strong>本当に削除しますか?
              </>
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={onCancel} disabled={isDeleting}>
            キャンセル
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={onConfirm}
            disabled={isDeleting}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            {isDeleting ? '削除中...' : '削除する'}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

### 削除処理Hook

**ファイル:** `/src/hooks/useDocumentDelete.ts`

```typescript
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

## ジョブステータス監視

### リアルタイム更新

```typescript
// useJobStatus Hook
interface UseJobStatusOptions {
  jobId: string;
  interval?: number;
  onComplete?: (result: any) => void;
  onError?: (error: string) => void;
}

export function useJobStatus({
  jobId,
  interval = 2000,
  onComplete,
  onError,
}: UseJobStatusOptions) {
  const [status, setStatus] = useState<JobStatus | null>(null);
  const [polling, setPolling] = useState(true);

  useEffect(() => {
    if (!polling || !jobId) return;

    const pollStatus = async () => {
      try {
        const response = await fetch(`/api/jobs/${jobId}`, {
          credentials: 'include',
        });

        if (!response.ok) {
          throw new Error('Failed to fetch job status');
        }

        const data: JobStatus = await response.json();
        setStatus(data);

        if (data.status === 'completed') {
          setPolling(false);
          onComplete?.(data.result);
        } else if (data.status === 'failed') {
          setPolling(false);
          onError?.(data.error || 'Job failed');
        }
      } catch (error: any) {
        console.error('Job polling error:', error);
        setPolling(false);
        onError?.(error.message);
      }
    };

    const timerId = setInterval(pollStatus, interval);
    pollStatus(); // 即座に1回実行

    return () => clearInterval(timerId);
  }, [jobId, polling, interval]);

  return { status, polling, stopPolling: () => setPolling(false) };
}

// 使用例
function DocumentProcessingStatus({ documentId }: { documentId: string }) {
  const { status, polling } = useJobStatus({
    jobId: documentId,
    interval: 2000,
    onComplete: (result) => {
      toast.success('処理が完了しました');
      router.push(`/documents/ocr/${documentId}`);
    },
    onError: (error) => {
      toast.error(`処理に失敗しました: ${error}`);
    },
  });

  if (!polling) return null;

  return (
    <div className="flex items-center gap-2">
      <Loader className="w-4 h-4 animate-spin" />
      <span>処理中... {status?.progress}%</span>
    </div>
  );
}
```

## 型定義

```typescript
// /src/types/knowledgebase.ts

export interface KnowledgeDocument {
  id: string;
  filename: string;
  original_filename: string;
  mime_type: string;
  file_size: number;
  status: DocumentStatus;
  knowledge_base_id: string;
  processing_job_id?: string;
  metadata?: any;
  created_at: string;
  updated_at: string;
}

export type DocumentStatus = 'uploaded' | 'processing' | 'processed' | 'failed';

export interface DocumentStats {
  total: number;
  uploaded: number;
  processing: number;
  processed: number;
  failed: number;
}

export interface KnowledgeDocumentListResponse {
  documents: KnowledgeDocument[];
  total: number;
  pages: number;
  current_page: number;
}

export interface JobStatus {
  id: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress: number; // 0-100
  message: string;
  result?: any;
  error?: string;
  created_at: string;
  updated_at: string;
}
```

## まとめ

ドキュメント管理機能により、以下を実現しています:

1. **直感的なUI:** ドラッグ&ドロップアップロード、フィルタリング、検索
2. **リアルタイム監視:** ジョブステータスのポーリングと進捗表示
3. **エラーハンドリング:** 明確なエラーメッセージと回復手段
4. **安全な削除:** 確認ダイアログと影響範囲の明示
5. **統合ワークフロー:** アップロード→処理→OCR調整→RAG変換の一貫した流れ

これらにより、管理者は効率的にドキュメントを管理し、OCR結果を編集して、高品質なナレッジベースを構築できます。