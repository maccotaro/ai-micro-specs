# Backend API Services Details

**Load When**: Backend API changes, new endpoints, or service logic modifications

## 1. ai-micro-api-auth (Port 8002)

### Purpose

Centralized authentication and authorization service

### Technology

- FastAPI (Python 3.11+)
- Poetry for dependency management
- PostgreSQL (`authdb`)
- Redis (sessions, token blacklist)

### Key Responsibilities

- User signup/login
- JWT token issuance (RS256 signing)
- Token validation and refresh with rotation
- Token blacklisting for logout
- JWKS endpoint for public key distribution

### API Endpoints

- `POST /auth/signup` - User registration
- `POST /auth/login` - User authentication
- `POST /auth/logout` - Token blacklisting
- `POST /auth/refresh` - Token refresh with rotation
- `GET /auth/me` - Current user info
- `GET /.well-known/jwks.json` - Public key for JWT verification
- `GET /healthz` - Health check

### Database Schema (`authdb`)

- **users** table: id (UUID), email, hashed_password, roles, created_at, updated_at

### Redis Patterns

- Sessions: `session:<user_id>:<session_id>` (TTL: 30 days)
- Access token blacklist: `blacklist:access:<jti>` (TTL: token expiration)
- Refresh token blacklist: `blacklist:refresh:<jti>` (TTL: token expiration)

### Key Files

- `/app/core/security.py` - JWT signing/verification logic
- `/app/routers/auth.py` - Authentication endpoints
- `/keys/` - RSA private/public key pair (RS256)

### Environment Variables

- `DATABASE_URL`: postgresql://postgres:password@host.docker.internal:5432/authdb
- `REDIS_URL`: redis://:password@host.docker.internal:6379
- `JWT_ISS`, `JWT_AUD` - Token claims
- `ACCESS_TOKEN_TTL_SEC`: 900 (15 min)
- `REFRESH_TOKEN_TTL_SEC`: 2592000 (30 days)

## 2. ai-micro-api-user (Port 8001)

### Purpose

User profile management service

### Technology

- FastAPI (Python 3.11+)
- pip for dependencies
- PostgreSQL (`apidb`)
- Redis (profile caching)

### Key Responsibilities

- User profile CRUD operations
- Profile data validation
- Profile caching with Redis

### API Endpoints

- `GET /profiles/{user_id}` - Fetch profile
- `PUT /profiles/{user_id}` - Update profile
- `POST /profiles` - Create profile

### Database Schema (`apidb`)

- **profiles** table: user_id (UUID, FK to authdb.users), first_name, last_name, email, created_at, updated_at

### Redis Patterns

- Profile cache: `profile:<user_id>` (TTL: 300 sec)

### Key Files

- `/app/routers/profile.py` - Profile endpoints
- `/app/models/profile.py` - Profile data models
- `/app/services/profile_service.py` - Business logic

### Environment Variables

- `DATABASE_URL`: postgresql://postgres:password@host.docker.internal:5432/apidb
- `REDIS_URL`: redis://:password@host.docker.internal:6379
- `JWKS_URL`: <http://host.docker.internal:8002/.well-known/jwks.json>

## 3. ai-micro-api-admin (Port 8003)

### Purpose

Admin operations, document processing, OCR, knowledge base management

### Technology

- FastAPI (Python 3.11+)
- Poetry for dependency management
- PostgreSQL (`admindb`)
- Redis (document processing state)
- OCR libraries: tesseract, paddleocr

### Key Responsibilities

- Document upload and OCR processing
- Hierarchical structure extraction (element ID generation)
- Knowledge base creation and management
- Chat interface with embeddings (RAG)

### API Endpoints

**Documents**:

- `POST /documents/upload` - Upload and process documents
- `GET /documents/{id}/ocr` - Retrieve OCR results
- `GET /documents/{id}/hierarchy` - Get hierarchical structure

**Knowledge Base**:

- `POST /knowledgebase` - Create KB
- `GET /knowledgebase` - List KBs
- `GET /knowledgebase/{id}` - Get KB details
- `POST /knowledgebase/{id}/chat` - Chat with KB

### Database Schema (`admindb`)

- **documents** table: id, title, file_path, ocr_result, created_at, updated_at
- **knowledge_bases** table: id, name, description, user_id, created_at, updated_at
- **kb_documents** table: kb_id, document_id, order

### Document Processing Pipeline

1. Upload → OCR (tesseract/paddleocr)
2. Layout analysis → Hierarchical structure extraction
3. Element ID generation (sequential, document-wide)
4. Store in admindb + cache processing state in Redis

### Key Files

- `/app/core/document_processing/base.py` - DocumentProcessor (HierarchyConverter)
- `/app/routers/documents.py` - Document endpoints
- `/app/routers/knowledgebase.py` - KB endpoints

### Environment Variables

- `DATABASE_URL`: postgresql://postgres:password@host.docker.internal:5432/admindb
- `REDIS_URL`: redis://:password@host.docker.internal:6379
- `JWKS_URL`: <http://host.docker.internal:8002/.well-known/jwks.json>

## Common Backend Patterns

### JWT Validation Middleware

All protected endpoints validate JWT using JWKS from Auth service:

1. Extract JWT from `Authorization: Bearer <token>` header
2. Fetch public key from `http://localhost:8002/.well-known/jwks.json`
3. Verify token signature (RS256)
4. Validate claims (`iss`, `aud`, `exp`)
5. Check Redis blacklist
6. Inject user info into request context

### Error Handling

- 401 Unauthorized: Invalid/expired token
- 403 Forbidden: Insufficient permissions
- 422 Validation Error: Invalid request data
- 500 Internal Server Error: Unexpected errors

### Database Connection Pattern

- Connection pooling (10-20 connections per service)
- Async SQLAlchemy for non-blocking I/O
- Transaction management with context managers

### Redis Usage

- Connection pooling (shared client)
- TTL-based expiration for all keys
- JSON serialization for complex data
- Pipeline for batch operations

## Development Commands

```bash
# Auth Service (Poetry)
cd ai-micro-api-auth
poetry install
poetry run uvicorn app.main:app --reload --port 8002

# User API (pip)
cd ai-micro-api-user
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001

# Admin API (Poetry)
cd ai-micro-api-admin
poetry install
poetry run uvicorn app.main:app --reload --port 8003

# Linting
poetry run ruff check .
poetry run mypy app/
```

## Testing Approach

- **Unit tests**: Business logic with pytest
- **Integration tests**: Database operations with test DB
- **Contract tests**: API contracts with OpenAPI validation
- **Performance tests**: Load testing with locust
