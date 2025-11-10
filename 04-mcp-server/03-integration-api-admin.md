# api-admin統合詳細

## 概要

ai-micro-mcp-adminとai-micro-api-adminは、双方向の統合により、エンタープライズRAG機能を実現しています。本ドキュメントでは、2つのサービス間の統合ポイント、リクエストチェーン、データフローを詳細に説明します。

## 統合パターン

### パターン1: mcp-admin → api-admin（検索委譲）

MCPツール `search_documents` は、api-adminのハイブリッド検索APIを呼び出します。

```
MCP Client
    ↓ MCP Protocol
mcp-admin (8004)
    ├─ Tool: search_documents
    └─ VectorSearchService
        ↓ HTTP POST /admin/search/hybrid
api-admin (8003)
    ├─ HybridRetriever
    └─ 7-stage RAG pipeline
        ↓ SQL queries
admindb (PostgreSQL)
```

### パターン2: api-admin → mcp-admin（ツール実行）

api-adminのチャット機能は、MCPClientを経由してmcp-adminのツールを呼び出します。

```
Frontend
    ↓ HTTP POST /knowledge_bases/{id}/chat/stream
api-admin (8003)
    ├─ MCPChatService
    ├─ MCPClient
    │   ├─ list_tools() → GET /mcp/tools
    │   └─ call_tool() → POST /mcp/call_tool
    └─ LLM response generation
        ↓
mcp-admin (8004)
    ├─ MCP Server
    └─ Tool execution
```

## api-admin側の統合コンポーネント

### 1. MCPClient (`app/services/mcp_client.py`)

**役割**: mcp-adminへのHTTPクライアント、ツール呼び出しの抽象化

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-admin/app/services/mcp_client.py` (115行)

**実装**:
```python
class MCPClient:
    """HTTP client for calling mcp-admin MCP endpoints"""

    def __init__(self, mcp_server_url: str = "http://host.docker.internal:8004"):
        self.mcp_server_url = mcp_server_url
        self.client = httpx.AsyncClient(timeout=60.0)

    async def list_tools(self, jwt_token: str) -> List[Dict]:
        """GET /mcp/tools - List available MCP tools"""
        headers = {"Authorization": f"Bearer {jwt_token}"}

        response = await self.client.get(
            f"{self.mcp_server_url}/mcp/tools",
            headers=headers
        )

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Failed to list tools: {response.text}"
            )

        return response.json()

    async def call_tool(
        self,
        tool_name: str,
        arguments: Dict,
        jwt_token: str
    ) -> Any:
        """POST /mcp/call_tool - Execute MCP tool"""
        headers = {"Authorization": f"Bearer {jwt_token}"}

        payload = {
            "name": tool_name,
            "arguments": arguments
        }

        response = await self.client.post(
            f"{self.mcp_server_url}/mcp/call_tool",
            json=payload,
            headers=headers
        )

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Tool execution failed: {response.text}"
            )

        return response.json()
```

### 2. MCPChatService (`app/services/mcp_chat_service.py`)

**役割**: LLMツール選択、MCP実行、応答生成のオーケストレーション

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-admin/app/services/mcp_chat_service.py` (479行)

**主要メソッド**:

```python
class MCPChatService:
    def __init__(self):
        self.mcp_client = MCPClient()
        self.ollama_client = OllamaClient()

    async def generate_response(
        self,
        query: str,
        knowledge_base_id: UUID,
        jwt_token: str,
        threshold: float = 0.6,
        max_results: int = 10,
        force_tool: str = None,
        custom_prompt: str = None
    ) -> AsyncGenerator[str, None]:
        """
        Full chat response generation pipeline:
        1. List MCP tools
        2. Select tool (LLM or forced)
        3. Execute tool
        4. Generate final response with streaming
        """

        # Step 1: Get available tools
        tools = await self.mcp_client.list_tools(jwt_token)

        # Step 2: Tool selection
        if force_tool:
            tool_selection = {
                "tool_name": force_tool,
                "arguments": {
                    "query": query,
                    "knowledge_base_id": str(knowledge_base_id),
                    "threshold": threshold,
                    "max_results": max_results
                }
            }
        else:
            tool_selection = await self._select_tool_with_llm(query, tools)

        # Step 3: Execute selected tool
        tool_result = await self._execute_selected_tool(
            tool_selection,
            knowledge_base_id,
            jwt_token,
            threshold,
            max_results
        )

        # Step 4: Generate final response (streaming)
        async for chunk in self._generate_final_response(
            query,
            tool_result,
            custom_prompt
        ):
            yield chunk

    async def _select_tool_with_llm(
        self,
        query: str,
        tools: List[Dict]
    ) -> Dict:
        """Use LLM to select appropriate tool"""
        prompt = f"""
        User query: "{query}"

        Available tools:
        {json.dumps(tools, indent=2, ensure_ascii=False)}

        Select the most appropriate tool and return JSON:
        {{"tool_name": "...", "arguments": {{...}}}}

        Rules:
        - Use "search_documents" for specific information queries
        - Use "get_knowledge_base_summary" for KB overview/statistics
        - Use "normalize_ocr_text" for OCR text normalization
        """

        response = await self.ollama_client.generate(
            model="pakachan/elyza-llama3-8b:latest",
            prompt=prompt,
            format="json"
        )

        return json.loads(response["response"])

    async def _execute_selected_tool(
        self,
        tool_selection: Dict,
        knowledge_base_id: UUID,
        jwt_token: str,
        threshold: float,
        max_results: int
    ) -> Dict:
        """Execute selected MCP tool via MCPClient"""
        tool_name = tool_selection["tool_name"]
        arguments = tool_selection.get("arguments", {})

        # Override with provided parameters
        if "knowledge_base_id" in arguments:
            arguments["knowledge_base_id"] = str(knowledge_base_id)
        if "threshold" in arguments:
            arguments["threshold"] = threshold
        if "max_results" in arguments:
            arguments["max_results"] = max_results

        # Call MCP tool
        result = await self.mcp_client.call_tool(
            tool_name=tool_name,
            arguments=arguments,
            jwt_token=jwt_token
        )

        return result

    async def _generate_final_response(
        self,
        query: str,
        tool_result: Dict,
        custom_prompt: str = None
    ) -> AsyncGenerator[str, None]:
        """Generate final LLM response with streaming"""
        # Build context from tool results
        if "results" in tool_result:
            context = "\n\n".join([
                f"[ドキュメント {i+1}]\n{r['content']}"
                for i, r in enumerate(tool_result["results"][:5])
            ])
        else:
            context = json.dumps(tool_result, ensure_ascii=False, indent=2)

        # Build prompt
        prompt = custom_prompt or f"""
        以下のコンテキストを参考に、ユーザーの質問に答えてください。

        【質問】
        {query}

        【コンテキスト】
        {context}

        【回答】
        """

        # Stream LLM response
        async for chunk in self.ollama_client.generate_stream(
            model="gemma2:9b",
            prompt=prompt
        ):
            yield chunk["response"]
```

### 3. Knowledge Bases Chat Router

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-api-admin/app/routers/knowledge_bases_chat.py`

**エンドポイント**:
```python
@router.post("/{knowledge_base_id}/chat/stream")
async def chat_with_knowledge_base_stream(
    knowledge_base_id: UUID,
    request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    """Stream chat responses using MCP tools"""

    # Extract JWT token
    jwt_token = request.headers.get("authorization", "").replace("Bearer ", "")

    # Initialize chat service
    chat_service = MCPChatService()

    # Stream response
    async def response_generator():
        async for chunk in chat_service.generate_response(
            query=request.query,
            knowledge_base_id=knowledge_base_id,
            jwt_token=jwt_token,
            threshold=request.threshold,
            max_results=request.max_results
        ):
            yield f"data: {chunk}\n\n"

    return StreamingResponse(
        response_generator(),
        media_type="text/event-stream"
    )
```

## mcp-admin側の統合コンポーネント

### 1. VectorSearchService (`app/services/vector_search.py`)

**役割**: api-adminのハイブリッド検索APIクライアント

**ファイル**: `/Users/makino/Documents/Work/github.com/ai-micro-service/ai-micro-mcp-admin/app/services/vector_search.py` (216行)

**実装**:
```python
class VectorSearchService:
    """Client for api-admin's hybrid search API"""

    def __init__(self):
        self.api_admin_url = "http://host.docker.internal:8003"
        self.hybrid_search_endpoint = f"{self.api_admin_url}/admin/search/hybrid"
        self.client = httpx.AsyncClient(timeout=60.0)

    async def search(
        self,
        query: str,
        knowledge_base_id: UUID,
        threshold: float = 0.6,
        top_k: int = 10,
        user_context: Optional[Dict] = None,
        jwt_token: Optional[str] = None
    ) -> List[Dict]:
        """
        Call api-admin's hybrid search API (7-stage RAG pipeline)

        Request format:
        {
          "query": str,
          "tenant_id": UUID,
          "knowledge_base_id": UUID,
          "user_filters": {
            "department": str,
            "clearance_level": str
          },
          "top_k": int
        }
        """

        # Prepare payload
        payload = {
            "query": query,
            "knowledge_base_id": str(knowledge_base_id),
            "threshold": threshold,
            "top_k": top_k,
            "user_context": user_context or {}
        }

        # Add Authorization header
        headers = {}
        if jwt_token:
            headers["Authorization"] = f"Bearer {jwt_token}"

        # POST request (non-blocking)
        response = await self.client.post(
            self.hybrid_search_endpoint,
            json=payload,
            headers=headers
        )

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Hybrid search failed: {response.text}"
            )

        # Parse results
        data = response.json()
        return data.get("results", [])
```

**非同期処理の最適化（2025-10-23）**:
```python
# In mcp-admin VectorSearchService (indirect via api-admin HybridRetriever)
# api-admin側でブロッキング処理を非同期化

# api-admin: app/services/hybrid_retriever.py
results = await asyncio.to_thread(
    self.vector_store.similarity_search_with_score,
    query, k=top_k, filter=filter_condition
)
# Prevents event loop blocking, enables concurrent requests
```

## リクエストチェーン詳細

### チェーン1: ユーザークエリ → MCP検索 → LLM応答

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Frontend Request                                     │
└───────────────────────┬─────────────────────────────────────┘
                        │ POST /knowledge_bases/{id}/chat/stream
                        │ Body: {query: "マイナビのサービスは？"}
                        │ Header: Authorization: Bearer <JWT>
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: api-admin - MCPChatService                          │
│ ├─ MCPClient.list_tools(jwt_token)                          │
│ │   └─ GET http://mcp-admin:8004/mcp/tools                  │
│ │      Response: [search_documents, get_kb_summary, ...]    │
│ │                                                             │
│ ├─ _select_tool_with_llm(query, tools)                      │
│ │   └─ POST http://ollama:11434/api/generate                │
│ │      Prompt: "Select tool for: マイナビのサービスは？"      │
│ │      Response: {tool_name: "search_documents", ...}        │
│ │                                                             │
│ ├─ MCPClient.call_tool("search_documents", ...)             │
│ │   └─ POST http://mcp-admin:8004/mcp/call_tool             │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│ Step 3: mcp-admin - MCP Server                              │
│ ├─ Verify JWT token (JWKS)                                  │
│ ├─ Check KB access permission (RBAC)                        │
│ ├─ Execute: _search_documents()                             │
│ │   └─ VectorSearchService.search()                         │
│ │       └─ POST http://api-admin:8003/admin/search/hybrid   │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│ Step 4: api-admin - Hybrid Search API                       │
│ ├─ Stage 1: Atlas layer (KB summary vector filter)          │
│ ├─ Stage 2: Metadata filter (tenant, department, clearance) │
│ ├─ Stage 3: Sparse + Dense search (500 + 500 results)       │
│ ├─ Stage 4: RRF merge (~600 results)                        │
│ ├─ Stage 5: BM25 re-ranker (100 results)                    │
│ ├─ Stage 6: Cross-Encoder re-ranker (10 results)            │
│ └─ Return: [                                                 │
│      {content: "...", score: 0.92, metadata: {...}},         │
│      ...                                                      │
│    ]                                                          │
└───────────────────────┬─────────────────────────────────────┘
                        │ Return results
┌───────────────────────▼─────────────────────────────────────┐
│ Step 5: mcp-admin - Format Response                         │
│ └─ Return: {query: "...", results: [...], count: 10}        │
└───────────────────────┬─────────────────────────────────────┘
                        │ Return to api-admin
┌───────────────────────▼─────────────────────────────────────┐
│ Step 6: api-admin - MCPChatService                          │
│ ├─ _generate_final_response(query, tool_result)             │
│ │   └─ POST http://ollama:11434/api/generate (streaming)    │
│ │      Prompt: "Answer based on: [search results]"           │
│ │      Model: gemma2:9b                                      │
│ │                                                             │
│ └─ Stream response chunks                                    │
└───────────────────────┬─────────────────────────────────────┘
                        │ Stream: "マイナビバイトは..."
┌───────────────────────▼─────────────────────────────────────┐
│ Step 7: Frontend                                             │
│ └─ Display streaming response to user                        │
└─────────────────────────────────────────────────────────────┘
```

### チェーン2: MCP検索のみ（Claude Desktop直接呼び出し）

```
Claude Desktop
    ↓ MCP Protocol
    └─ Tool: search_documents
       └─ Arguments: {query, kb_id, threshold, max_results}

mcp-admin (8004)
    ├─ JWT verification (provided by Claude Desktop)
    ├─ KB access check
    └─ VectorSearchService.search()
        ↓ POST /admin/search/hybrid
api-admin (8003)
    └─ 7-stage RAG pipeline
        └─ Return results

mcp-admin
    └─ Format response
        └─ Return to Claude Desktop

Claude Desktop
    └─ Display results to user
```

## 共有データベース

両サービスは同じ `admindb` データベースを利用します。

### テーブルアクセスパターン

**api-admin（読み書き）**:
- `knowledge_bases` - CRUD操作
- `collections` - CRUD操作
- `documents` - CRUD操作
- `langchain_pg_embedding` - ベクトル挿入・検索
- `document_fulltext` - 全文検索インデックス
- `knowledge_bases_summary_embedding` - Atlas層KB要約
- `collections_summary_embedding` - Atlas層Collection要約

**mcp-admin（読み取りのみ）**:
- `knowledge_bases` - KB情報取得（get_knowledge_base_summary）
- `collections` - Collection統計（get_knowledge_base_summary）
- `documents` - ドキュメント統計（get_knowledge_base_summary）
- ※ベクトル検索は api-admin経由で間接アクセス

## パフォーマンス最適化

### 1. 接続プール設定

**mcp-admin**:
```python
# app/core/database.py
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=20,       # 基本接続数
    max_overflow=30,    # 追加接続数
    pool_timeout=30,    # 接続取得タイムアウト
    pool_recycle=3600   # 接続リサイクル（1時間）
)
```

**api-admin**:
```python
# Similar configuration
pool_size=30, max_overflow=50
# Total: 80 concurrent connections
```

### 2. 非同期処理

**mcp-admin → api-admin HTTP通信**:
- `httpx.AsyncClient()` 使用
- 非ブロッキングHTTPリクエスト

**api-admin ベクトル検索**:
```python
# asyncio.to_thread() でブロッキング処理分離
results = await asyncio.to_thread(
    self.vector_store.similarity_search_with_score,
    query, k=top_k
)
```

### 3. キャッシュ戦略

**JWT JWKS キャッシュ（mcp-admin）**:
- 10分間キャッシュ
- Auth Service負荷軽減

**LLM応答キャッシュ（検討中）**:
- 同一クエリの繰り返しを避ける
- Redis利用

## エラーハンドリングと再試行

### HTTP通信エラー

```python
# MCPClient (api-admin)
try:
    response = await self.client.post(url, json=payload, headers=headers)
    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)
    return response.json()
except httpx.RequestError as e:
    raise HTTPException(status_code=503, detail=f"MCP server unavailable: {str(e)}")
```

### JWT認証エラー

```python
# mcp-admin: get_current_user()
try:
    payload = await verify_token(token)
    return payload
except JWTError:
    raise HTTPException(status_code=401, detail="Invalid JWT token")
except httpx.RequestError:
    raise HTTPException(status_code=503, detail="Auth service unavailable")
```

### タイムアウト設定

| サービス | タイムアウト | 対象 |
|---------|-------------|------|
| MCPClient | 60秒 | mcp-admin呼び出し |
| VectorSearchService | 60秒 | api-admin ハイブリッド検索 |
| Ollama Client | 120秒 | LLM生成 |
| DB Connection Pool | 30秒 | 接続取得待機 |

## セキュリティ統合

### JWT トークンフロー

```
1. User Login (Auth Service)
   └─ Issue: access_token (15min) + refresh_token (30 days)

2. Frontend → api-admin
   └─ Authorization: Bearer <access_token>

3. api-admin → mcp-admin (MCPClient.call_tool)
   └─ Authorization: Bearer <access_token> (forwarded)

4. mcp-admin → api-admin (VectorSearchService.search)
   └─ Authorization: Bearer <access_token> (forwarded)

5. Each service verifies JWT independently
   ├─ api-admin: verify_token() with JWKS
   └─ mcp-admin: verify_token() with JWKS (same mechanism)
```

### RBAC統合

両サービスで同一のロール体系を使用：
- `super_admin`: 全KB アクセス（両サービス）
- `admin`: 全KB アクセス（両サービス）
- `user`: 作成したKBまたは公開KBのみ（両サービス）

## モニタリング・ロギング

### ログ統合

**api-admin**:
```python
logger.info(f"MCP tool selected: {tool_name}")
logger.info(f"MCP tool execution: {tool_name} for KB {kb_id}")
```

**mcp-admin**:
```python
logger.info(f"Tool executed: {name} for KB {kb_id} by user {user_id}")
logger.info(f"Hybrid search: {len(results)} results for query '{query}'")
```

### メトリクス収集（検討中）

- MCP呼び出し回数（ツール別）
- ハイブリッド検索レイテンシ
- ツール選択精度（LLM判断の正確性）

## 関連ドキュメント

- [README.md](./README.md) - MCP Admin Service概要
- [01-architecture.md](./01-architecture.md) - 詳細アーキテクチャ
- [02-mcp-tools.md](./02-mcp-tools.md) - MCPツール詳細
- [../03-admin-api/02-api-knowledge-bases.md](../03-admin-api/02-api-knowledge-bases.md) - ナレッジベースAPI（チャットエンドポイント）
- [../17-rag-system/README.md](../17-rag-system/README.md) - エンタープライズRAGシステム
