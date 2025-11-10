# MCP Admin Service - アーキテクチャ詳細

## 概要

ai-micro-mcp-adminは、Model Context Protocol (MCP) サーバーとして、Claude DesktopやMCPクライアントに対してナレッジベース検索機能を提供します。本ドキュメントでは、サービスの詳細アーキテクチャ、ファイル構成、リクエストフロー、および設計思想を説明します。

## システムアーキテクチャ

### レイヤー構成

```
┌──────────────────────────────────────────────────────────────┐
│           Layer 1: HTTP Interface (FastAPI)                   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Routers (app/routers/mcp.py)                           │  │
│  │ - GET  /health                                         │  │
│  │ - GET  /                                               │  │
│  │ - GET  /mcp/tools (JWT認証)                            │  │
│  │ - POST /mcp/call_tool (JWT認証)                        │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│      Layer 2: Authentication & Authorization                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Dependencies (app/dependencies/auth.py)                │  │
│  │ - get_current_user() → JWT検証                         │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Core Auth (app/core/auth.py)                           │  │
│  │ - verify_token() → JWKS + RS256検証                    │  │
│  │ - get_jwks() → 10分キャッシュ                          │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Permissions (app/core/permissions.py)                  │  │
│  │ - check_knowledge_base_access() → RBAC                 │  │
│  │ - require_knowledge_base_access() → デコレータ         │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│             Layer 3: MCP Server Core                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ MCP Server (app/services/mcp_server.py)                │  │
│  │ - KnowledgeBaseMCPServer (singleton)                   │  │
│  │   ├─ list_tools() → ツール定義返却                     │  │
│  │   ├─ call_tool() → ツール実行ルーティング              │  │
│  │   ├─ execute_tool() → 認証付きツール実行               │  │
│  │   ├─ _search_documents()                               │  │
│  │   ├─ _get_kb_summary()                                 │  │
│  │   └─ _normalize_ocr_text()                             │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│          Layer 4: Business Logic Services                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ VectorSearchService (app/services/vector_search.py)    │  │
│  │ - search() → POST /admin/search/hybrid (api-admin)     │  │
│  │ - 非同期ベクトル検索（asyncio.to_thread）              │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ KBSummaryService (app/services/kb_summary.py)          │  │
│  │ - get_summary() → 直接SQL（admindb）                   │  │
│  │ - 接続リーク防止（finally句）                          │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│           Layer 5: Data Access & External Integration         │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Database (app/core/database.py)                        │  │
│  │ - SQLAlchemy Engine + Session                          │  │
│  │ - Connection Pool (20 + 30 overflow = 50)              │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ External Services                                      │  │
│  │ - PostgreSQL admindb (5432)                            │  │
│  │ - api-admin Hybrid Search API (8003)                   │  │
│  │ - Auth Service JWKS (8002)                             │  │
│  │ - Ollama (11434) - OCR正規化用                         │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## ファイル構成と責務

### ディレクトリツリー

```
ai-micro-mcp-admin/
├── app/
│   ├── __init__.py
│   ├── main.py                      # 【Entry Point】FastAPIアプリ定義
│   │
│   ├── core/                        # 【Core Layer】基盤機能
│   │   ├── __init__.py
│   │   ├── config.py                # 環境変数・設定管理（Pydantic）
│   │   ├── database.py              # DB接続プール・Session管理
│   │   ├── auth.py                  # JWT検証・JWKS統合
│   │   └── permissions.py           # KB アクセス制御・RBAC
│   │
│   ├── dependencies/                # 【Dependency Injection】FastAPI依存
│   │   ├── __init__.py
│   │   └── auth.py                  # get_current_user()依存注入
│   │
│   ├── routers/                     # 【HTTP Interface】エンドポイント定義
│   │   ├── __init__.py
│   │   └── mcp.py                   # /mcp ルート（tools, call_tool）
│   │
│   └── services/                    # 【Business Logic】サービス層
│       ├── __init__.py
│       ├── mcp_server.py            # MCP Server実装（ツール定義）
│       ├── vector_search.py         # ハイブリッド検索クライアント
│       └── kb_summary.py            # KB要約・統計サービス
│
├── Dockerfile                       # コンテナイメージ定義
├── docker-compose.yml               # ローカル開発環境
├── requirements.txt                 # Python依存パッケージ
├── .env                             # 環境変数（ローカル）
├── .env.example                     # 環境変数テンプレート
└── CLAUDE.md                        # 開発ガイドライン
```

### 各ファイルの詳細

#### 1. `app/main.py` (86行)

**役割**: FastAPIアプリケーション定義、ライフサイクル管理、ルート登録

**主要機能**:
- FastAPIアプリインスタンス作成
- CORSミドルウェア設定
- MCPサーバーシングルトン初期化（lifespan event）
- ルーター登録（`/mcp`）
- ヘルスチェックエンドポイント（`/health`）

**コード抜粋**:
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: MCP server initialization
    mcp_server = get_mcp_server()
    logger.info("MCP Server initialized with tools")
    yield
    # Shutdown: cleanup (if needed)

app = FastAPI(
    title="AI Micro MCP Admin",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(CORSMiddleware, ...)

# Router registration
app.include_router(mcp.router, prefix="/mcp", tags=["mcp"])

@app.get("/health")
async def health_check():
    return {"status": "healthy"}
```

#### 2. `app/core/config.py` (57行)

**役割**: 環境変数管理、設定値の型安全アクセス

**主要設定**:
```python
class Settings(BaseSettings):
    # Application
    APP_NAME: str = "AI Micro MCP Admin"
    DEBUG: bool = False
    HOST: str = "0.0.0.0"
    PORT: int = 8004

    # Database
    DATABASE_URL: str

    # Authentication
    JWKS_URL: str
    JWT_ALGORITHM: str = "RS256"
    JWT_AUDIENCE: str = "fastapi-api"
    JWT_ISSUER: str

    # Ollama
    OLLAMA_BASE_URL: str = "http://host.docker.internal:11434"
    CHAT_MODEL: str = "pakachan/elyza-llama3-8b:latest"

    class Config:
        env_file = ".env"

settings = Settings()  # Singleton
```

#### 3. `app/core/database.py` (34行)

**役割**: SQLAlchemy接続プール管理、Session提供

**接続プール設定**:
```python
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=20,              # 基本接続数
    max_overflow=30,           # 追加接続数（合計50）
    pool_timeout=30,           # 接続取得タイムアウト（秒）
    pool_recycle=3600,         # 接続リサイクル（1時間）
    pool_pre_ping=True,        # ヘルスチェック有効化
    echo=settings.DEBUG        # SQL ログ出力
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    """Dependency injection for DB session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

**最適化ポイント**:
- 50並行接続対応（pool_size=20 + max_overflow=30）
- 1時間ごとに接続リサイクル（長時間接続の問題回避）
- pool_pre_ping=True（切断検知・自動再接続）

#### 4. `app/core/auth.py` (111行)

**役割**: JWT検証、JWKS統合、トークン検証

**主要関数**:

**1. `get_jwks()` - JWKS取得とキャッシュ**
```python
_jwks_cache: Optional[Dict[str, Any]] = None
_jwks_cache_time: Optional[datetime] = None

async def get_jwks() -> Dict[str, Any]:
    """Fetch JWKS from auth service with 10-minute cache"""
    global _jwks_cache, _jwks_cache_time

    if _jwks_cache and (datetime.utcnow() - _jwks_cache_time).total_seconds() < 600:
        return _jwks_cache

    response = await httpx.AsyncClient().get(settings.JWKS_URL, timeout=10.0)
    _jwks_cache = response.json()
    _jwks_cache_time = datetime.utcnow()
    return _jwks_cache
```

**2. `verify_token()` - JWT署名検証**
```python
async def verify_token(token: str) -> Dict[str, Any]:
    """Verify JWT token with RS256 signature"""
    # 1. Extract 'kid' from header
    unverified_header = jwt.get_unverified_header(token)
    kid = unverified_header.get("kid")

    # 2. Fetch JWKS
    jwks = await get_jwks()
    key_data = next((k for k in jwks["keys"] if k["kid"] == kid), None)

    # 3. Reconstruct public key
    public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))

    # 4. Verify signature
    payload = jwt.decode(
        token,
        public_key,
        algorithms=[settings.JWT_ALGORITHM],
        audience=settings.JWT_AUDIENCE,
        issuer=settings.JWT_ISSUER
    )
    return payload
```

#### 5. `app/core/permissions.py` (86行)

**役割**: ロールベースアクセス制御 (RBAC)、KB アクセス権チェック

**主要関数**:

**1. `check_knowledge_base_access()` - KB アクセス権チェック**
```python
async def check_knowledge_base_access(
    user_id: str,
    knowledge_base_id: UUID,
    user_roles: list,
    db: Session
) -> bool:
    """Check if user has access to knowledge base"""
    # Admin bypass
    if "super_admin" in user_roles or "admin" in user_roles:
        return True

    # Query: created_by or is_public
    kb = db.query(KnowledgeBase).filter(
        KnowledgeBase.id == knowledge_base_id,
        or_(
            KnowledgeBase.created_by == user_id,
            KnowledgeBase.is_public == True
        )
    ).first()

    return kb is not None
```

**2. `require_knowledge_base_access()` - デコレータ**
```python
def require_knowledge_base_access(knowledge_base_id_param: str = "knowledge_base_id"):
    """Decorator to enforce KB access control"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            kb_id = kwargs.get(knowledge_base_id_param)
            user = kwargs.get("current_user")
            db = kwargs.get("db")

            has_access = await check_knowledge_base_access(
                user["sub"], kb_id, user.get("roles", []), db
            )

            if not has_access:
                raise HTTPException(status_code=403, detail="Access denied to this knowledge base")

            return await func(*args, **kwargs)
        return wrapper
    return decorator
```

#### 6. `app/dependencies/auth.py` (28行)

**役割**: FastAPI依存注入、JWT検証の統合

```python
from fastapi import Depends, HTTPException, Header
from typing import Optional

async def get_current_user(authorization: Optional[str] = Header(None)) -> dict:
    """Dependency: Extract and verify JWT token from Authorization header"""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    token = authorization.replace("Bearer ", "")

    try:
        payload = await verify_token(token)
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid JWT token")
    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="Authentication service unavailable")
```

#### 7. `app/routers/mcp.py` (79行)

**役割**: /mcp エンドポイント定義、HTTPリクエストハンドリング

**エンドポイント**:

**1. GET /mcp/tools**
```python
@router.get("/tools")
async def list_tools(current_user: dict = Depends(get_current_user)):
    """List available MCP tools"""
    mcp_server = get_mcp_server()
    return mcp_server.tools_list
```

**2. POST /mcp/call_tool**
```python
@router.post("/call_tool")
async def call_tool(
    request: CallToolRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Execute MCP tool with JWT authentication"""
    mcp_server = get_mcp_server()

    # Extract JWT token
    jwt_token = request.headers.get("authorization", "").replace("Bearer ", "")

    # Execute tool
    result = await mcp_server.execute_tool(
        name=request.name,
        arguments=request.arguments,
        jwt_token=jwt_token,
        current_user=current_user,
        db=db
    )

    return result
```

#### 8. `app/services/mcp_server.py` (371行)

**役割**: MCP Server実装、ツール定義・実行ロジック

**クラス構造**:
```python
class KnowledgeBaseMCPServer:
    def __init__(self):
        self.server = Server("knowledge-base-tools")
        self.vector_service = VectorSearchService()
        self.summary_service = KBSummaryService()
        self.tools_list = self._create_tools_list()
        self._register_tools()

    def _create_tools_list(self) -> List[Tool]:
        """Create MCP tool definitions"""
        return [
            Tool(
                name="search_documents",
                description="Search for specific information in knowledge base documents",
                inputSchema={...}
            ),
            Tool(name="get_knowledge_base_summary", ...),
            Tool(name="normalize_ocr_text", ...)
        ]

    def _register_tools(self):
        """Register tool handlers with MCP server"""
        @self.server.list_tools()
        async def list_tools() -> List[Tool]:
            return self.tools_list

        @self.server.call_tool()
        async def call_tool(name: str, arguments: Dict) -> List[TextContent]:
            # Route to appropriate tool
            if name == "search_documents":
                result = await self._search_documents(...)
            elif name == "get_knowledge_base_summary":
                result = await self._get_kb_summary(...)
            elif name == "normalize_ocr_text":
                result = await self._normalize_ocr_text(...)
            return [TextContent(type="text", text=json.dumps(result))]

    async def execute_tool(self, name, arguments, jwt_token, current_user, db):
        """Public method for tool execution with auth"""
        # Validate KB access
        kb_id = arguments.get("knowledge_base_id")
        if kb_id:
            has_access = await check_knowledge_base_access(...)
            if not has_access:
                raise PermissionError("Access denied")

        # Execute tool
        if name == "search_documents":
            return await self._search_documents(...)
        # ...

    async def _search_documents(self, query, knowledge_base_id, threshold, max_results):
        """Tool implementation: search_documents"""
        results = await self.vector_service.search(
            query=query,
            knowledge_base_id=knowledge_base_id,
            threshold=threshold,
            top_k=max_results
        )
        return {"query": query, "results": results, ...}

    # ... _get_kb_summary(), _normalize_ocr_text()
```

**シングルトンパターン**:
```python
_mcp_server_instance: Optional[KnowledgeBaseMCPServer] = None

def get_mcp_server() -> KnowledgeBaseMCPServer:
    """Get singleton MCP server instance"""
    global _mcp_server_instance
    if _mcp_server_instance is None:
        _mcp_server_instance = KnowledgeBaseMCPServer()
    return _mcp_server_instance
```

#### 9. `app/services/vector_search.py` (216行)

**役割**: api-admin ハイブリッド検索API クライアント、非同期ベクトル検索

**主要機能**:
```python
class VectorSearchService:
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
        """
        # Prepare request
        payload = {
            "query": query,
            "knowledge_base_id": str(knowledge_base_id),
            "threshold": threshold,
            "top_k": top_k,
            "user_context": user_context or {}
        }

        headers = {}
        if jwt_token:
            headers["Authorization"] = f"Bearer {jwt_token}"

        # Non-blocking HTTP call
        response = await self.client.post(
            self.hybrid_search_endpoint,
            json=payload,
            headers=headers
        )

        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=response.text)

        return response.json()["results"]
```

**非同期処理の最適化**:
```python
# 2025-10-23 optimization: asyncio.to_thread for blocking ops
results = await asyncio.to_thread(
    self.vector_store.similarity_search_with_score,
    query, k=top_k, filter=filter_condition
)
# Prevents event loop blocking, enables concurrent requests
```

#### 10. `app/services/kb_summary.py` (61行)

**役割**: KB 要約・統計情報取得（直接SQL）

```python
class KBSummaryService:
    async def get_summary(self, knowledge_base_id: UUID, db: Session) -> Dict:
        """Get KB summary with statistics"""
        try:
            # Direct SQL query
            result = db.execute(
                text("""
                    SELECT
                        kb.name,
                        kb.description,
                        COUNT(DISTINCT c.id) as total_collections,
                        COUNT(DISTINCT d.id) as total_documents,
                        COALESCE(SUM(d.chunk_count), 0) as total_chunks
                    FROM knowledge_bases kb
                    LEFT JOIN collections c ON c.knowledge_base_id = kb.id
                    LEFT JOIN documents d ON d.collection_id = c.id
                    WHERE kb.id = :kb_id
                    GROUP BY kb.id, kb.name, kb.description
                """),
                {"kb_id": str(knowledge_base_id)}
            ).fetchone()

            return {
                "knowledge_base_id": str(knowledge_base_id),
                "summary": f"{result.name}: {result.description}",
                "statistics": {
                    "total_documents": result.total_documents,
                    "total_collections": result.total_collections,
                    "total_chunks": result.total_chunks
                },
                "generated_at": datetime.utcnow().isoformat()
            }
        finally:
            db.close()  # Prevent connection leak
```

## リクエストフロー

### Flow 1: ツール一覧取得（GET /mcp/tools）

```
1. Client Request
   GET /mcp/tools
   Authorization: Bearer <JWT_TOKEN>

2. FastAPI Router (app/routers/mcp.py)
   ├─ Dependency: get_current_user(authorization)
   │  ├─ Extract token from header
   │  ├─ Call verify_token(token)
   │  │  ├─ Extract 'kid' from JWT header
   │  │  ├─ Fetch JWKS (cached 10 min)
   │  │  ├─ Reconstruct public key
   │  │  └─ Verify RS256 signature
   │  └─ Return payload: {sub, roles, ...}
   │
   └─ Handler: list_tools()
      ├─ Get MCP server singleton
      └─ Return: mcp_server.tools_list

3. Response
   [
     {name: "search_documents", ...},
     {name: "get_knowledge_base_summary", ...},
     {name: "normalize_ocr_text", ...}
   ]
```

### Flow 2: ツール実行（POST /mcp/call_tool）

```
1. Client Request
   POST /mcp/call_tool
   Authorization: Bearer <JWT_TOKEN>
   Body: {
     "name": "search_documents",
     "arguments": {
       "query": "マイナビのサービスは？",
       "knowledge_base_id": "cf23c222-...",
       "threshold": 0.6,
       "max_results": 10
     }
   }

2. FastAPI Router (app/routers/mcp.py)
   ├─ Dependency: get_current_user(authorization)
   │  └─ JWT verification (same as Flow 1)
   │
   ├─ Dependency: get_db()
   │  └─ SQLAlchemy Session creation
   │
   └─ Handler: call_tool(request, current_user, db)
      ├─ Extract JWT token from header
      ├─ Get MCP server singleton
      └─ Call: mcp_server.execute_tool(...)

3. MCP Server (app/services/mcp_server.py)
   execute_tool(name="search_documents", arguments={...}, jwt_token, current_user, db)
   ├─ Extract knowledge_base_id from arguments
   ├─ Call: check_knowledge_base_access(user_id, kb_id, roles, db)
   │  ├─ Check: super_admin or admin → bypass
   │  ├─ Query: SELECT FROM knowledge_bases WHERE id=kb_id AND (created_by=user_id OR is_public=true)
   │  └─ Return: True/False
   │
   ├─ If access denied → raise PermissionError (403)
   │
   └─ Call: _search_documents(query, kb_id, threshold, max_results)

4. Vector Search Service (app/services/vector_search.py)
   search(query, kb_id, threshold, top_k)
   ├─ Prepare payload: {query, kb_id, threshold, top_k, user_context}
   ├─ Add Authorization header: Bearer <JWT_TOKEN>
   ├─ HTTP POST → http://host.docker.internal:8003/admin/search/hybrid
   │  └─ api-admin executes 7-stage RAG pipeline:
   │     ├─ Stage 1: Atlas layer filtering
   │     ├─ Stage 2: Metadata filter
   │     ├─ Stage 3: Sparse + Dense search
   │     ├─ Stage 4: RRF merge
   │     ├─ Stage 5: BM25 re-ranking
   │     └─ Stage 6: Cross-Encoder re-ranking
   │
   └─ Return: [{"content": "...", "score": 0.92, "metadata": {...}}, ...]

5. MCP Server (app/services/mcp_server.py)
   _search_documents() wraps results
   └─ Return: {
        "query": "マイナビのサービスは？",
        "knowledge_base_id": "cf23c222-...",
        "threshold": 0.6,
        "results": [...],
        "count": 10
      }

6. Response
   {
     "query": "マイナビのサービスは？",
     "results": [
       {
         "content": "マイナビバイトは...",
         "score": 0.92,
         "metadata": {
           "chunk_id": "abc-123",
           "document_id": "doc-456",
           "sparse_score": 0.85,
           "dense_score": 0.91,
           "bm25_score": 0.88,
           "cross_encoder_score": 0.92
         }
       },
       ...
     ],
     "count": 10
   }
```

## 設計思想

### 1. レイヤードアーキテクチャ

各レイヤーは明確な責務を持ち、依存方向は一方向（上→下）：
- HTTP Interface → Authentication → MCP Server → Business Logic → Data Access
- 各レイヤーの変更が他レイヤーに波及しない（疎結合）

### 2. シングルトンパターン

MCPサーバーはアプリケーション全体で1インスタンス：
- メモリ効率化（ツール定義の重複生成を回避）
- 状態の一貫性（全リクエストで同じサーバーインスタンス）

### 3. 依存性注入 (Dependency Injection)

FastAPIの依存注入を活用：
- `get_current_user()`: JWT検証をエンドポイント宣言で自動実行
- `get_db()`: DB Sessionの自動管理（try-finally保証）
- テスタビリティ向上（モック差し替え可能）

### 4. 非同期処理

すべてのI/O処理は非同期：
- `async def` 関数 + `await` キーワード
- `asyncio.to_thread()`: ブロッキング処理のスレッド分離
- httpx.AsyncClient: 非同期HTTP通信

### 5. 接続プール最適化

PostgreSQL接続プールを適切にサイズ設定：
- pool_size=20: 常時接続数
- max_overflow=30: 追加接続数（合計50）
- pool_recycle=3600: 1時間で接続リフレッシュ
- pool_pre_ping=True: 接続ヘルスチェック

### 6. セキュリティ第一

すべてのMCPエンドポイントはJWT認証必須：
- RS256署名検証（非対称鍵）
- JWKS統合（公開鍵自動取得）
- ロールベースアクセス制御 (RBAC)
- KB単位のアクセス制御

### 7. 分離されたビジネスロジック

MCPサーバーは検索ロジックを実装せず、api-adminに委譲：
- 単一責任の原則（MCP Protocol実装に専念）
- api-adminの7段階RAGパイプラインを再利用
- マイクロサービス間の疎結合

## パフォーマンス特性

### 処理時間内訳（典型的なsearch_documentsリクエスト）

| ステージ | 処理時間 | 説明 |
|---------|---------|------|
| HTTP受信・パース | ~5ms | FastAPI request parsing |
| JWT検証 | ~10ms | JWKS取得（キャッシュ） + RS256検証 |
| KB アクセス制御 | ~5ms | DB query: knowledge_bases |
| VectorSearchService HTTP | ~50ms | mcp-admin → api-admin HTTP overhead |
| 7段階RAGパイプライン（api-admin） | ~2500ms | Atlas〜Cross-Encoder |
| 結果整形・返却 | ~30ms | JSON serialization |
| **合計** | **~2.6秒** | E2E（クライアント→レスポンス） |

### 並行処理性能

| 同時リクエスト数 | 平均レスポンス時間 | 備考 |
|----------------|-------------------|------|
| 1-5 | 2.6秒 | ベースライン |
| 10 | 2.7秒 | 接続プール余裕あり |
| 20 | 2.9秒 | pool_size=20に到達 |
| 30 | 3.1秒 | overflow開始 |
| 50 | 3.5秒 | max overflow到達 |
| 51+ | タイムアウトリスク | pool_timeout=30秒 |

**最適化（2025-10-23実施）**:
- 非同期ベクトル検索: `asyncio.to_thread()` でブロッキング処理分離
- 接続プール拡張: 20+30=50並行接続対応
- 接続リーク防止: finally句での確実なクローズ

## 関連ドキュメント

- [README.md](./README.md) - MCP Admin Service概要
- [02-mcp-tools.md](./02-mcp-tools.md) - 3つのMCPツール詳細仕様
- [03-integration-api-admin.md](./03-integration-api-admin.md) - api-admin連携詳細
- [04-authentication.md](./04-authentication.md) - JWT認証・認可フロー
- [05-performance.md](./05-performance.md) - パフォーマンス最適化詳細
