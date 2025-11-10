# MCP Tools詳細仕様

## 概要

ai-micro-mcp-adminは3つのMCPツールを公開します。各ツールは特定のユースケースに最適化されており、Claude Desktopや他のMCPクライアントから呼び出し可能です。

## ツール一覧

| ツール名 | 用途 | 処理時間 |
|---------|------|---------|
| search_documents | ナレッジベース検索（7段階RAG） | ~2.7秒 |
| get_knowledge_base_summary | KB統計・要約取得 | ~50ms |
| normalize_ocr_text | OCRテキスト正規化 | ~500ms |

## Tool 1: search_documents

### 目的

ナレッジベース内のドキュメントから、クエリに関連する情報を高精度に検索します。api-adminの7段階RAGパイプライン（Atlas層→Sparse/Dense→RRF→BM25/Cross-Encoder Re-ranker）を活用します。

### パラメータ

```json
{
  "name": "search_documents",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "検索クエリ（日本語・英語対応）"
      },
      "knowledge_base_id": {
        "type": "string",
        "format": "uuid",
        "description": "対象ナレッジベースのUUID"
      },
      "threshold": {
        "type": "number",
        "minimum": 0.0,
        "maximum": 1.0,
        "default": 0.6,
        "description": "類似度閾値（0.0〜1.0、推奨: 0.6〜0.8）"
      },
      "max_results": {
        "type": "integer",
        "minimum": 1,
        "maximum": 50,
        "default": 10,
        "description": "最大返却件数（1〜50）"
      }
    },
    "required": ["query", "knowledge_base_id"]
  }
}
```

### 実行例

**リクエスト**:
```json
{
  "name": "search_documents",
  "arguments": {
    "query": "マイナビのアルムナイサービスについて教えて",
    "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
    "threshold": 0.7,
    "max_results": 5
  }
}
```

**レスポンス**:
```json
{
  "query": "マイナビのアルムナイサービスについて教えて",
  "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
  "threshold": 0.7,
  "results": [
    {
      "content": "マイナビアルムナイは、退職者と企業をつなぐプラットフォームです...",
      "score": 0.92,
      "metadata": {
        "chunk_id": "chunk-abc-123",
        "document_id": "doc-456",
        "chunk_index": 5,
        "collection_id": "coll-789",
        "sparse_score": 0.85,
        "dense_score": 0.91,
        "rrf_score": 0.88,
        "bm25_score": 0.89,
        "cross_encoder_score": 0.92
      }
    },
    ...
  ],
  "count": 5
}
```

### 内部処理フロー

```
1. VectorSearchService.search()
   ├─ Prepare payload: {query, kb_id, threshold, top_k}
   ├─ Add JWT Authorization header
   └─ POST http://api-admin:8003/admin/search/hybrid

2. api-admin: 7-stage RAG pipeline
   ├─ Stage 1: Atlas layer (KB summary vector filter)
   ├─ Stage 2: Metadata filter (tenant, department, clearance)
   ├─ Stage 3A: Sparse search (PGroonga + BM25) → 500 results
   ├─ Stage 3B: Dense search (HNSW vector) → 500 results
   ├─ Stage 4: RRF merge → ~600 results
   ├─ Stage 5: BM25 re-ranker → 100 results
   └─ Stage 6: Cross-Encoder re-ranker → 10 results

3. Return results with metadata
```

### 使用例

**ユースケース1: 具体的な情報検索**
- クエリ: "リモートワーク手当の金額は？"
- 想定結果: 具体的な金額が記載されたチャンクを返却

**ユースケース2: 概念検索**
- クエリ: "社員教育について"
- 想定結果: 研修制度、キャリアパス、スキル開発等の関連情報

**ユースケース3: 複数語検索**
- クエリ: "副業 許可 条件"
- 想定結果: 副業ルール、申請方法、承認基準等

### threshold設定ガイド

| threshold | 用途 | Precision | Recall |
|-----------|------|-----------|--------|
| 0.5〜0.6 | 広範囲検索 | 中 | 高 |
| 0.6〜0.7 | バランス（推奨） | 高 | 中 |
| 0.7〜0.8 | 高精度検索 | 最高 | 低 |
| 0.8〜1.0 | 厳密検索 | 最高 | 最低 |

---

## Tool 2: get_knowledge_base_summary

### 目的

ナレッジベース全体の概要・統計情報を取得します。ユーザーが「このKBについて教えて」と尋ねた際に使用され、直接SQL（admindb）で高速に情報を取得します。

### パラメータ

```json
{
  "name": "get_knowledge_base_summary",
  "inputSchema": {
    "type": "object",
    "properties": {
      "knowledge_base_id": {
        "type": "string",
        "format": "uuid",
        "description": "対象ナレッジベースのUUID"
      }
    },
    "required": ["knowledge_base_id"]
  }
}
```

### 実行例

**リクエスト**:
```json
{
  "name": "get_knowledge_base_summary",
  "arguments": {
    "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e"
  }
}
```

**レスポンス**:
```json
{
  "knowledge_base_id": "cf23c222-b024-4533-81aa-52e4f673281e",
  "summary": "マイナビサービス概要: マイナビが提供する各種サービスの説明資料",
  "statistics": {
    "total_documents": 15,
    "total_collections": 3,
    "total_chunks": 342
  },
  "generated_at": "2025-11-08T10:30:45.123456Z"
}
```

### 内部処理フロー

```
1. KBSummaryService.get_summary()
   └─ Direct SQL query (admindb)

2. SQL execution
   SELECT kb.name, kb.description,
          COUNT(DISTINCT c.id) as total_collections,
          COUNT(DISTINCT d.id) as total_documents,
          COALESCE(SUM(d.chunk_count), 0) as total_chunks
   FROM knowledge_bases kb
   LEFT JOIN collections c ON c.knowledge_base_id = kb.id
   LEFT JOIN documents d ON d.collection_id = c.id
   WHERE kb.id = :kb_id
   GROUP BY kb.id, kb.name, kb.description

3. Format response with statistics
```

### 使用例

**ユースケース1: KB概要確認**
- クエリ: "このナレッジベースについて教えて"
- ツール選択: get_knowledge_base_summary
- 結果: ドキュメント数、コレクション数、チャンク数を含む要約

**ユースケース2: メタ情報取得**
- クエリ: "このKBにはいくつのドキュメントがありますか？"
- ツール選択: get_knowledge_base_summary
- 結果: 統計情報から total_documents を抽出

---

## Tool 3: normalize_ocr_text

### 目的

OCR処理で誤認識されたハイフン（-）を、文脈に応じて日本語の長音符（ー）に正規化します。LLM（Ollama）を利用した文脈考慮型の変換を実行します。

### パラメータ

```json
{
  "name": "normalize_ocr_text",
  "inputSchema": {
    "type": "object",
    "properties": {
      "text": {
        "type": "string",
        "description": "正規化対象のOCRテキスト"
      }
    },
    "required": ["text"]
  }
}
```

### 実行例

**リクエスト**:
```json
{
  "name": "normalize_ocr_text",
  "arguments": {
    "text": "マイナビキャリ-では、キャリアコンサルティングを提供しています。"
  }
}
```

**レスポンス**:
```json
{
  "original_text": "マイナビキャリ-では、キャリアコンサルティングを提供しています。",
  "normalized_text": "マイナビキャリアでは、キャリアコンサルティングを提供しています。",
  "status": "success"
}
```

### 内部処理フロー

```
1. _normalize_ocr_text(text)
   └─ Call Ollama API with prompt

2. LLM generation (Ollama)
   POST http://ollama:11434/api/generate
   Prompt:
     以下のOCRテキストに含まれるハイフン（-）を、
     文脈から適切な長音符（ー）に変換してください。
     単なる記号のハイフンはそのまま残してください。

     Input: {text}

3. Parse LLM output and return normalized text
```

### 使用例

**ユースケース1: カタカナ長音修正**
- Input: "マネ-ジャ-", "ユ-ザ-"
- Output: "マネージャー", "ユーザー"

**ユースケース2: 英単語ハイフン保持**
- Input: "self-service", "e-mail"
- Output: "self-service", "e-mail" （変更なし）

**ユースケース3: 混在テキスト**
- Input: "サ-ビス（service）のガイドライン"
- Output: "サービス（service）のガイドライン"

### 精度向上のポイント

- LLMモデル: `pakachan/elyza-llama3-8b:latest`（日本語特化）
- 文脈理解: 前後の文字から長音符の妥当性を判断
- ハイフン保持: 英単語内のハイフンは変換しない

---

## ツール選択ロジック（api-admin側）

api-adminのMCPChatServiceは、ユーザークエリに応じて最適なツールを自動選択します。

### 選択基準

```python
# Tool selection with LLM (api-admin: app/services/mcp_chat_service.py)

async def _select_tool_with_llm(query: str, tools: List[Dict]) -> Dict:
    """Use LLM to select appropriate tool based on query intent"""

    prompt = f"""
    User query: "{query}"

    Available tools:
    1. search_documents: Search specific information in documents
    2. get_knowledge_base_summary: Get overview/statistics of KB
    3. normalize_ocr_text: Normalize OCR text (hyphens → long vowel marks)

    Select the most appropriate tool and return JSON:
    {{"tool_name": "...", "arguments": {{...}}}}
    """

    # Call Ollama for tool selection
    response = await ollama_client.generate(prompt)
    return json.loads(response)
```

### 選択例

| ユーザークエリ | 選択ツール | 理由 |
|-------------|-----------|------|
| "リモートワーク手当は？" | search_documents | 具体的情報検索 |
| "このKBについて" | get_knowledge_base_summary | KB メタ情報取得 |
| "副業の規定を教えて" | search_documents | 規定文書検索 |
| "このKBには何件のドキュメントがある？" | get_knowledge_base_summary | 統計情報取得 |
| "OCR結果: マネ-ジャ-" | normalize_ocr_text | テキスト正規化 |

---

## エラーハンドリング

### 共通エラー

| エラー | HTTPステータス | 原因 |
|-------|---------------|------|
| Invalid authentication credentials | 401 | JWT トークン無効・期限切れ |
| Access denied to this knowledge base | 403 | KB アクセス権限なし |
| Knowledge base not found | 404 | 存在しないKB ID |
| Failed to connect to api-admin service | 503 | api-admin停止・ネットワークエラー |

### ツール別エラー

**search_documents**:
- `threshold out of range (0.0-1.0)`: threshold値が範囲外
- `max_results exceeds limit (50)`: max_results > 50
- `No results found`: 閾値が高すぎる、またはクエリに一致する文書なし

**get_knowledge_base_summary**:
- `No collections found`: コレクションが0件
- `No documents found`: ドキュメントが0件（エラーではなく警告）

**normalize_ocr_text**:
- `LLM service unavailable`: Ollamaサービス停止
- `Text too long (max 10000 chars)`: 入力テキストが長すぎる

---

## ベストプラクティス

### 1. threshold設定

- 初回検索: threshold=0.6（バランス型）
- 結果が多すぎる: threshold=0.7〜0.8に上げる
- 結果が少なすぎる: threshold=0.5に下げる

### 2. max_results設定

- LLM応答生成用: max_results=10（推奨）
- 精査用リスト: max_results=20〜50
- プレビュー: max_results=3〜5

### 3. クエリ最適化

- 具体的な質問: "副業の申請方法は？"（◯）
- 曖昧な質問: "副業について"（△）
- キーワードのみ: "副業"（△）

### 4. ツール選択の強制

api-admin経由で呼び出す場合、`force_tool`パラメータでツールを強制指定可能：

```python
# api-admin: MCPChatService
response = await mcp_chat_service.generate_response(
    query="マイナビのサービスは？",
    knowledge_base_id=kb_id,
    force_tool="search_documents"  # ツール選択をスキップ
)
```

---

## 関連ドキュメント

- [README.md](./README.md) - MCP Admin Service概要
- [01-architecture.md](./01-architecture.md) - 詳細アーキテクチャ
- [03-integration-api-admin.md](./03-integration-api-admin.md) - api-admin連携（ツール選択ロジック）
- [../17-rag-system/01-architecture.md](../17-rag-system/01-architecture.md) - 7段階RAGパイプライン詳細
