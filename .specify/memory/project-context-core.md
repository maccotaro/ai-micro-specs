# Project Context: AI Microservices System (Core)

**Last Updated**: 2025-10-05
**Version**: 1.2.0 (Context-optimized)

## Quick Architecture Overview

This is a microservices system with 7 services for authentication, user management, and document processing.

### Architecture Diagram

```text
┌─────────────────────────────────────────────┐
│  User Frontend (3002) │ Admin Frontend (3003) │
│       Next.js BFF     │      Next.js BFF      │
└────────┬──────────────┴──────────┬────────────┘
         │                         │
         ▼                         ▼
┌─────────────────────────────────────────────┐
│ Auth (8002) │ User API (8001) │ Admin (8003)│
│   FastAPI   │     FastAPI     │   FastAPI   │
└────────┬────┴────────┬──────────┴─────┬──────┘
         │             │                │
         ▼             ▼                ▓
┌─────────────────────────────────────────────┐
│ PostgreSQL (authdb, apidb, admindb) │ Redis │
└─────────────────────────────────────────────┘
```

## Service Directory

**Detailed service information**: See `.specify/memory/services/`

### Quick Reference

| Service | Port | Type | Details File |
|---------|------|------|--------------|
| ai-micro-front-user | 3002 | Next.js | `services/frontend-services.md` |
| ai-micro-front-admin | 3003 | Next.js | `services/frontend-services.md` |
| ai-micro-api-auth | 8002 | FastAPI | `services/api-services.md` |
| ai-micro-api-user | 8001 | FastAPI | `services/api-services.md` |
| ai-micro-api-admin | 8003 | FastAPI | `services/api-services.md` |
| ai-micro-postgres | 5432 | PostgreSQL | `services/infrastructure.md` |
| ai-micro-redis | 6379 | Redis | `services/infrastructure.md` |

## Common Integration Patterns

### Authentication & Authorization

- **Method**: JWT (RS256) with JWKS-based validation
- **Flow**: Login → Auth service → JWT tokens → httpOnly cookies
- **Token TTL**: Access 15min, Refresh 30days
- **Claims**: `sub`, `iss`, `aud`, `iat`, `exp`, `jti`, `scope`, `roles`
- **Validation**: All services validate via JWKS from `http://localhost:8002/.well-known/jwks.json`

### Database Access

- **Pattern**: Each service owns its database (no cross-DB joins)
- **Databases**:
  - `authdb`: User credentials, roles (Auth service)
  - `apidb`: User profiles (User API service)
  - `admindb`: Documents, knowledge bases (Admin API service)
- **Schema**: UUID primary keys, `created_at`/`updated_at` timestamps

### Shared State (Redis)

- **Sessions**: `session:<user_id>:<session_id>`
- **Token Blacklist**: `blacklist:access:<jti>`, `blacklist:refresh:<jti>`
- **Caching**: `profile:<user_id>`, document processing state

### Service Communication

- **Frontend → Backend**: BFF pattern (API routes proxy to backend)
- **Backend → Backend**: Direct HTTP with JWT validation
- **No**: Direct database access across services

## Development Workflow

### System Startup

```bash
# 1. Infrastructure
cd ai-micro-postgres && docker compose up -d
cd ../ai-micro-redis && docker compose up -d

# 2. Backend
cd ../ai-micro-api-auth && docker compose up -d
cd ../ai-micro-api-user && docker compose up -d
cd ../ai-micro-api-admin && docker compose up -d

# 3. Frontend
cd ../ai-micro-front-user && docker compose up -d
cd ../ai-micro-front-admin && docker compose up -d
```

### Access Points

- User Frontend: <http://localhost:3002>
- Admin Frontend: <http://localhost:3003>
- APIs: 8002 (Auth), 8001 (User), 8003 (Admin)

## Specify Workflow Integration

### Service Scope Identification

When using `/specify`, determine:

1. **Which service(s)**?
   - Frontend only? Backend only? Full-stack?
   - Refer to service details in `services/*.md`

2. **New service needed**?
   - Justify why existing 7 services insufficient
   - Document in spec.md

3. **Integration points**?
   - API contracts between services
   - Database access patterns
   - Authentication requirements

### Specification Guidelines

- **Use Service Integration section** in spec-template
- **Reference service details** from `services/*.md` as needed
- **Plan contract tests** at service boundaries
- **Respect service boundaries** (no direct cross-service DB access)

## Known Technical Debt

### File Size Violations (500+ lines)

**Frontend**:

- `ai-micro-front-admin/src/pages/documents/ocr/[id].tsx` (1,350 lines)
- `ai-micro-front-admin/src/pages/knowledgebase/[id]/edit.tsx` (1,184 lines)

**Backend**: No current violations

**Migration Plan**: Refactor during next feature addition (see Constitution Legacy Code Migration Policy)

## References

- **Service Details**: `.specify/memory/services/*.md`
- **Constitution**: `.specify/memory/constitution.md`
- **Root Docs**: `/ai-micro-service/CLAUDE.md`
- **Service Docs**: Each service has its own `CLAUDE.md`
