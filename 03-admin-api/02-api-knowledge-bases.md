# Admin API - ナレッジベースAPI仕様

**カテゴリ**: Backend Service API
**バージョン**: 1.0.0
**最終更新**: 2025-11-08

## 目次
- [概要](#概要)
- [ナレッジベース管理](#ナレッジベース管理)
- [チャット・検索機能](#チャット検索機能)
- [ドキュメント関連機能](#ドキュメント関連機能)

---

## 概要

ナレッジベースAPIは、ドキュメントコレクションの管理、ベクトル検索、RAGベースのチャット機能を提供します。

**ベースURL**: `/admin/knowledge-bases`

**主要機能**:
- ナレッジベースのCRUD操作
- ベクトル検索によるドキュメント検索
- ストリーミングチャット（RAG）
- カスタムプロンプトのサポート
- アクセス権限管理

---

## データ型定義

### KnowledgeBaseStatus

```typescript
enum KnowledgeBaseStatus {
  ACTIVE = "active",
  INACTIVE = "inactive",
  ARCHIVED = "archived"
}
```

### KnowledgeBase

```typescript
interface KnowledgeBase {
  id: string;                    // UUID
  name: string;                  // ナレッジベース名
  description?: string;          // 説明
  user_id: string;               // 作成者ID（UUID）
  status: KnowledgeBaseStatus;   // ステータス
  is_public: boolean;            // 公開フラグ
  prompt?: string;               // カスタムプロンプト
  permissions?: Record<string, any>; // 権限設定
  processing_settings?: Record<string, any>; // 処理設定
  search_settings?: Record<string, any>; // 検索設定
  tags?: string[];               // タグ配列
  category?: string;             // カテゴリ
  document_count: number;        // 関連ドキュメント数
  storage_size: number;          // ストレージサイズ（バイト）
  created_at: string;            // 作成日時（ISO）
  updated_at: string;            // 更新日時（ISO）
}
```

---

## ナレッジベース管理

### POST /admin/knowledge-bases

ナレッジベースを作成します。

**認証**: `admin` 必須

#### リクエストボディ

```typescript
interface KnowledgeBaseCreate {
  name: string;                  // 必須: ナレッジベース名
  description?: string;          // 説明
  is_public?: boolean;           // デフォルト: false
  prompt?: string;               // カスタムプロンプト
  permissions?: Record<string, any>;
  processing_settings?: Record<string, any>;
  search_settings?: Record<string, any>;
  tags?: string[];
  category?: string;
}

// 使用例
const kb = await fetch('/api/admin/knowledge-bases', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: '技術ドキュメント',
    description: '社内技術文書集',
    is_public: false,
    prompt: 'あなたは技術文書の専門家です。正確で詳細な情報を提供してください。',
    tags: ['技術', '社内'],
    category: 'technical'
  })
}).then(r => r.json()) as KnowledgeBase;
```

#### レスポンス例

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "name": "技術ドキュメント",
  "description": "社内技術文書集",
  "user_id": "987fbc97-4bed-5078-9f07-9141ba07c9f3",
  "status": "active",
  "is_public": false,
  "prompt": "あなたは技術文書の専門家です。正確で詳細な情報を提供してください。",
  "tags": ["技術", "社内"],
  "category": "technical",
  "document_count": 0,
  "storage_size": 0,
  "created_at": "2025-10-01T14:30:00Z",
  "updated_at": "2025-10-01T14:30:00Z"
}
```

### GET /admin/knowledge-bases

ナレッジベース一覧を取得します（ページネーション・フィルタリング対応）。

**認証**: `admin` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `page` | number | 1 | ページ番号 |
| `limit` | number | 20 | 1ページあたりの件数（最大100） |
| `search` | string | - | 名前・説明で検索 |
| `status` | KnowledgeBaseStatus | - | ステータスでフィルタ |
| `category` | string | - | カテゴリでフィルタ |
| `is_public` | boolean | - | 公開/非公開フィルタ |
| `user_id` | string | - | ユーザーIDでフィルタ |

#### レスポンス

```typescript
interface KnowledgeBaseListResponse {
  knowledge_bases: KnowledgeBase[];
  total: number;                 // 総件数
  page: number;                  // 現在のページ
  limit: number;                 // ページサイズ
  pages: number;                 // 総ページ数
}

// 使用例
const kbList = await fetch(
  '/api/admin/knowledge-bases?page=1&limit=20&status=active'
).then(r => r.json()) as KnowledgeBaseListResponse;
```

### GET /admin/knowledge-bases/{knowledge_base_id}

特定のナレッジベースを取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `knowledge_base_id` (UUID)

**アクセス制御**:
- 所有者は常にアクセス可能
- 公開ナレッジベースは全ユーザーがアクセス可能
- 管理者は全ナレッジベースにアクセス可能

```typescript
const kb = await fetch(`/api/admin/knowledge-bases/${kbId}`)
  .then(r => r.json()) as KnowledgeBase;
```

### PUT /admin/knowledge-bases/{knowledge_base_id}

ナレッジベースを更新します。

**認証**: `get_current_user` 必須（所有者または管理者のみ）

#### リクエストボディ

```typescript
interface KnowledgeBaseUpdate {
  name?: string;
  description?: string;
  status?: KnowledgeBaseStatus;
  is_public?: boolean;
  prompt?: string;
  permissions?: Record<string, any>;
  processing_settings?: Record<string, any>;
  search_settings?: Record<string, any>;
  tags?: string[];
  category?: string;
}

// 使用例
await fetch(`/api/admin/knowledge-bases/${kbId}`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    description: '更新された説明',
    is_public: true,
    status: KnowledgeBaseStatus.ACTIVE
  })
});
```

### DELETE /admin/knowledge-bases/{knowledge_base_id}

ナレッジベースを削除します。

**認証**: `get_current_user` 必須（所有者または管理者のみ）

**パスパラメータ**: `knowledge_base_id` (UUID)

```typescript
await fetch(`/api/admin/knowledge-bases/${kbId}`, {
  method: 'DELETE'
});
```

---

## チャット・検索機能

### POST /admin/knowledge-bases/{knowledge_base_id}/chat/stream

ナレッジベースに対してストリーミングチャットを実行します（RAG）。

**認証**: `get_current_user` 必須

**パスパラメータ**: `knowledge_base_id` (UUID)

#### リクエストボディ

```typescript
interface ChatRequest {
  query: string;                 // 必須: ユーザークエリ
  threshold?: number;            // 類似度閾値（0-1、デフォルト: 0.5）
  max_results?: number;          // 最大取得ドキュメント数（デフォルト: 5）
}

// 使用例（ストリーミング）
const response = await fetch(
  `/api/admin/knowledge-bases/${kbId}/chat/stream`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: 'Next.jsのサーバーコンポーネントについて教えてください',
      threshold: 0.6,
      max_results: 10
    })
  }
);

const reader = response.body?.getReader();
const decoder = new TextDecoder();

while (true) {
  const { done, value } = await reader!.read();
  if (done) break;

  const chunk = decoder.decode(value);
  console.log(chunk); // ストリーミングテキスト出力
}
```

#### React使用例

```typescript
function StreamingChat({ knowledgeBaseId }: { knowledgeBaseId: string }) {
  const [query, setQuery] = useState('');
  const [response, setResponse] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setResponse('');

    const res = await fetch(
      `/api/admin/knowledge-bases/${knowledgeBaseId}/chat/stream`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, threshold: 0.6 })
      }
    );

    const reader = res.body?.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader!.read();
      if (done) break;

      const chunk = decoder.decode(value);
      setResponse(prev => prev + chunk);
    }

    setLoading(false);
  };

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="質問を入力..."
        />
        <button type="submit" disabled={loading}>
          {loading ? '回答中...' : '送信'}
        </button>
      </form>
      <div className="response-area">
        {response}
      </div>
    </div>
  );
}
```

### POST /admin/knowledge-bases/{knowledge_base_id}/chat/search

ナレッジベース内でベクトル検索を実行します（チャットなし）。

**認証**: `get_current_user` 必須

**パスパラメータ**: `knowledge_base_id` (UUID)

#### リクエストボディ

```typescript
interface SearchRequest {
  query: string;                 // 必須: 検索クエリ
  threshold?: number;            // 類似度閾値（デフォルト: 0.5）
  max_results?: number;          // 最大取得件数（デフォルト: 10）
}

interface DocumentResult {
  document_id: string;           // ドキュメントID
  chunk_id: string;              // チャンクID
  content: string;               // ドキュメント内容
  similarity: number;            // 類似度スコア（0-1）
  metadata: Record<string, any>; // メタデータ
}

interface SearchResponse {
  results: DocumentResult[];
  query: string;                 // 実行されたクエリ
  total: number;                 // 見つかった件数
}

// 使用例
const searchResults = await fetch(
  `/api/admin/knowledge-bases/${kbId}/chat/search`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: 'FastAPIの認証実装',
      threshold: 0.7,
      max_results: 20
    })
  }
).then(r => r.json()) as SearchResponse;

searchResults.results.forEach(doc => {
  console.log(`[${doc.similarity.toFixed(2)}] ${doc.content.substring(0, 100)}...`);
});
```

### POST /admin/knowledge-bases/{knowledge_base_id}/chat/test

チャット機能のテストエンドポイント（開発・デバッグ用）。

**認証**: `get_current_user` 必須

```typescript
interface ChatTestRequest {
  query: string;
  debug?: boolean;               // デバッグ情報を含める
}

interface ChatTestResponse {
  success: boolean;
  message: string;
  context_documents?: DocumentResult[]; // 使用されたコンテキスト
  prompt_used?: string;          // 使用されたプロンプト
  debug_info?: Record<string, any>;
}

// 使用例
const testResult = await fetch(
  `/api/admin/knowledge-bases/${kbId}/chat/test`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: 'テストクエリ',
      debug: true
    })
  }
).then(r => r.json()) as ChatTestResponse;
```

### GET /admin/knowledge-bases/{knowledge_base_id}/chat/health

チャット機能のヘルスチェックを実行します。

**認証**: `get_current_user` 必須

```typescript
interface ChatHealthResponse {
  status: "healthy" | "unhealthy";
  vector_store_ready: boolean;
  embeddings_available: boolean;
  llm_available: boolean;
  knowledge_base_exists: boolean;
  document_count: number;
  last_check: string;            // ISO日時
}

// 使用例
const health = await fetch(
  `/api/admin/knowledge-bases/${kbId}/chat/health`
).then(r => r.json()) as ChatHealthResponse;

if (health.status !== 'healthy') {
  console.error('Chat service is not ready');
}
```

### POST /admin/knowledge-bases/{knowledge_base_id}/chat/stream_mcp

MCP (Model Context Protocol) サーバー経由でストリーミングチャットを実行します。7段階RAGパイプラインとLLMツール選択を統合した高度なチャット機能です。

**認証**: `get_current_user` 必須

**パスパラメータ**: `knowledge_base_id` (UUID)

**特徴**:
- **Stage 0: MCPツール選択**: LLMがクエリに応じて最適なツールを選択（search_documents、get_knowledge_base_summary等）
- **7段階RAGパイプライン**: Atlas層フィルタリング → Sparse検索 → Dense検索 → RRF統合 → BM25 Re-ranker → Cross-Encoder → LLM生成
- **非同期ベクトル検索**: `asyncio.to_thread()` による高速化
- **接続プール最適化**: 50並行接続対応（20基本+30オーバーフロー）

#### リクエストボディ

```typescript
interface MCPChatRequest {
  query: string;                 // 必須: ユーザークエリ
  threshold?: number;            // 類似度閾値（0-1、デフォルト: 0.6）
  top_k?: number;                // 最大取得ドキュメント数（デフォルト: 10）
  user_context?: {               // ユーザーコンテキスト（任意）
    department?: string;         // 部署フィルタ
    clearance_level?: string;    // 機密レベルフィルタ
  };
}

// 使用例（ストリーミング）
const response = await fetch(
  `/api/admin/knowledge-bases/${kbId}/chat/stream_mcp`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: 'マイナビのサービスは？',
      threshold: 0.6,
      top_k: 10,
      user_context: {
        department: '営業部',
        clearance_level: 'internal'
      }
    })
  }
);

const reader = response.body?.getReader();
const decoder = new TextDecoder();

while (true) {
  const { done, value } = await reader!.read();
  if (done) break;

  const chunk = decoder.decode(value);
  console.log(chunk); // ストリーミングテキスト出力
}
```

#### レスポンス形式

**Server-Sent Events (SSE)** 形式でストリーミング:

```
data: {"type":"tool_selection","tool":"search_documents","reasoning":"クエリが製品・サービスに関する質問のため"}

data: {"type":"search_start","stage":"atlas_layer"}

data: {"type":"search_result","count":10,"execution_time_ms":2500}

data: {"type":"llm_start","model":"gemma2:9b"}

data: {"type":"token","content":"マイナビバイトは"}

data: {"type":"token","content":"、アルバイト・パート求人情報サイトです"}

data: {"type":"done","total_time_ms":5200}
```

#### React使用例（MCP統合）

```typescript
function MCPStreamingChat({ knowledgeBaseId }: { knowledgeBaseId: string }) {
  const [query, setQuery] = useState('');
  const [response, setResponse] = useState('');
  const [metadata, setMetadata] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setResponse('');
    setMetadata(null);

    const res = await fetch(
      `/api/admin/knowledge-bases/${knowledgeBaseId}/chat/stream_mcp`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query,
          threshold: 0.6,
          top_k: 10,
          user_context: {
            department: '営業部'
          }
        })
      }
    );

    const reader = res.body?.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader!.read();
      if (done) break;

      const chunk = decoder.decode(value);
      const lines = chunk.split('\n');

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = JSON.parse(line.substring(6));

          if (data.type === 'token') {
            setResponse(prev => prev + data.content);
          } else if (data.type === 'done') {
            setMetadata(data);
          }
        }
      }
    }

    setLoading(false);
  };

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="質問を入力..."
        />
        <button type="submit" disabled={loading}>
          {loading ? '回答中...' : '送信'}
        </button>
      </form>
      <div className="response-area">
        {response}
      </div>
      {metadata && (
        <div className="metadata">
          処理時間: {metadata.total_time_ms}ms
        </div>
      )}
    </div>
  );
}
```

#### 7段階RAGパイプライン詳細

**Stage 1: Atlas層フィルタリング** (~50ms):
- KB/Collection要約ベクトルで事前フィルタリング
- 関連性95%以上のKB/Collectionを選別

**Stage 2: メタデータフィルタ** (~10ms):
- テナント分離（tenant_id）
- 部署フィルタ（user_context.department）
- 機密レベルフィルタ（user_context.clearance_level）

**Stage 3A: Sparse検索** (~200ms):
- PGroonga全文検索（日本語形態素解析）
- BM25スコアリング（k1=1.5, b=0.75）
- 結果: 約500件

**Stage 3B: Dense検索** (~300ms):
- PGVector HNSW インデックス
- コサイン類似度計算
- embedding: bge-m3:567m (1024次元)
- 結果: 約500件

**Stage 4: RRF統合** (~50ms):
- Reciprocal Rank Fusion
- スパース+Dense結果をマージ
- 結果: 約600件

**Stage 5: BM25 Re-ranker** (~150ms):
- MeCab トークナイザー + rank-bm25
- 600件→100件に絞り込み

**Stage 6: Cross-Encoder Re-ranker** (~800ms CPU / ~200ms GPU):
- モデル: intfloat/multilingual-e5-large-instruct
- 100件→10件に絞り込み
- 最終スコア計算

**Stage 7: LLM生成** (ストリーミング):
- gemma2:9b で応答生成
- カスタムプロンプト対応

**合計処理時間**: ~2.5秒（検索） + LLM生成時間

#### MCP統合の利点

1. **インテリジェントツール選択**: LLMが質問内容に応じて最適なツール（検索、要約取得、テキスト正規化）を自動選択
2. **並行処理最適化**: 非同期ベクトル検索により5-10 req/sで33%高速化
3. **スケーラビリティ**: 接続プール50並行接続対応
4. **JWKS認証統合**: 10分キャッシュで認証サービス負荷軽減
5. **監査ログ**: 全RAG操作を`rag_audit_logs`テーブルに記録

#### エラーハンドリング

```typescript
try {
  const response = await fetch(
    `/api/admin/knowledge-bases/${kbId}/chat/stream_mcp`,
    { method: 'POST', body: JSON.stringify({ query }) }
  );

  if (!response.ok) {
    const error = await response.json();
    console.error('MCP Chat Error:', error.detail);
  }
} catch (err) {
  console.error('Network Error:', err);
}
```

**エラーコード**:
- **400**: 無効なリクエスト（queryが空、threshold範囲外等）
- **403**: 権限不足（KB未所有、非公開KBへの不正アクセス）
- **404**: ナレッジベースが見つからない
- **503**: MCPサーバー利用不可、ベクトルストア未初期化

#### パフォーマンス最適化（2025-10-23実施）

**非同期ベクトル検索**:
```python
# app/services/vector_search.py
results = await asyncio.to_thread(
    self.vector_store.similarity_search_with_score,
    query, k=top_k, filter=filter_condition
)
```

**接続プール拡張**:
```python
# app/core/database.py
engine = create_engine(
    DATABASE_URL,
    pool_size=20,        # 10→20
    max_overflow=30,     # 20→30
    pool_timeout=30,
    pool_recycle=3600
)
```

**ベンチマーク結果** (2025-10-23):
| 負荷レベル | 最適化前 | 最適化後 | 改善率 |
|-----------|---------|---------|--------|
| 低負荷 (1-2 req/s) | 2.8s | 2.7s | 4% |
| 中負荷 (5-10 req/s) | 4.2s (queuing) | 2.8s | 33% |
| 高負荷 (20+ req/s) | タイムアウト | 3.5s | 安定化 |

---

## ドキュメント関連機能

### GET /admin/knowledge-bases/{knowledge_base_id}/documents

ナレッジベースに関連するドキュメント一覧を取得します。

**認証**: `get_current_user` 必須

**パスパラメータ**: `knowledge_base_id` (UUID)

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `page` | number | 1 | ページ番号 |
| `limit` | number | 20 | ページサイズ |
| `status` | string | - | ステータスフィルタ |

```typescript
interface KnowledgeDocumentListResponse {
  documents: DocumentResponse[]; // ドキュメント一覧
  total: number;
  page: number;
  limit: number;
  pages: number;
}

// 使用例
const docs = await fetch(
  `/api/admin/knowledge-bases/${kbId}/documents?page=1&limit=50`
).then(r => r.json()) as KnowledgeDocumentListResponse;
```

---

## カスタムプロンプトの使用

ナレッジベースには専用のカスタムプロンプトを設定できます。設定されている場合、チャット時にデフォルトプロンプトの代わりに使用されます。

### プロンプト設定例

```typescript
// カスタムプロンプト付きでナレッジベースを作成
const kb = await fetch('/api/admin/knowledge-bases', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: '法務ドキュメント',
    description: '法務関連文書集',
    prompt: `あなたは法務の専門家です。以下のルールに従ってください：
1. 正確性を最優先し、曖昧な表現を避ける
2. 法的根拠を明示する
3. 解釈に幅がある場合は複数の見解を提示する
4. 専門用語は必要に応じて説明を加える

提供されたコンテキストに基づいて回答してください。`
  })
});
```

### プロンプトの更新

```typescript
// 既存ナレッジベースのプロンプトを更新
await fetch(`/api/admin/knowledge-bases/${kbId}`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    prompt: '更新されたカスタムプロンプト...'
  })
});
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

| コード | 説明 | 対処法 |
|-------|------|-------|
| 400 | リクエスト不正 | 同名のナレッジベースが既に存在 |
| 403 | 権限不足 | 非公開ナレッジベースへの不正アクセス |
| 404 | ナレッジベース未発見 | IDを確認、または削除された可能性 |
| 503 | サービス利用不可 | ベクトルストアが初期化されていない |

---

## 関連ドキュメント

- [チャット履歴管理API](./07-api-chat-sessions.md) - チャットセッション・メッセージ管理
- [ハイブリッド検索API](./08-api-hybrid-search.md) - 7段階RAGパイプライン詳細仕様
- [テナント管理API](./09-api-tenants.md) - マルチテナント対応
- [ドキュメント処理API](./02-api-documents.md) - ドキュメントのアップロードとベクトル化
- [ジョブ管理API](./02-api-jobs.md) - ベクトル化ジョブの監視
- [プロンプトテンプレートAPI](./02-api-prompt-templates.md) - システム全体のプロンプト管理
- [エンタープライズRAGシステム](../17-rag-system/README.md) - 7段階パイプライン、Atlas層、ハイブリッド検索の詳細設計
- [MCPサーバー](../04-mcp-server/README.md) - Model Context Protocol統合
- [MCP統合設計](../04-mcp-server/03-integration-api-admin.md) - api-admin ⇔ mcp-admin双方向統合
