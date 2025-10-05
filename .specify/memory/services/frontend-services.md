# Frontend Services Details

**Load When**: Frontend-related features or UI changes

## 1. ai-micro-front-user (Port 3002)

### Purpose

End-user frontend application

### Technology

- Next.js 14+ (TypeScript, React)
- TailwindCSS
- ShadcnUI components

### Key Responsibilities

- User authentication UI (login, signup)
- Profile management pages
- BFF proxy to Auth + User API services

### Directory Structure

```text
src/
├── pages/
│   ├── api/          # BFF API routes
│   ├── auth/         # Login, signup pages
│   └── profile/      # Profile management
├── components/       # Reusable UI components
└── lib/              # Utilities, API clients
```

### Integration Points

- **Auth Service (8002)**: Login, signup, token refresh
- **User API (8001)**: Profile CRUD operations
- **Cookies**: httpOnly cookies for JWT storage

### Environment Variables

- `AUTH_SERVER_URL`: <http://host.docker.internal:8002>
- `API_SERVER_URL`: <http://host.docker.internal:8001>
- `JWT_SECRET`: For cookie encryption

## 2. ai-micro-front-admin (Port 3003)

### Purpose

Admin dashboard with document/knowledge base management

### Technology

- Next.js 14+ (TypeScript, React)
- ShadcnUI components
- TailwindCSS

### Key Responsibilities

- Admin authentication UI
- Document upload, OCR processing, hierarchical structure management
- Knowledge base creation and chat interface
- BFF proxy to Auth + User + Admin API services

### Directory Structure

```text
src/
├── pages/
│   ├── api/                  # BFF API routes
│   ├── documents/            # Document management
│   │   ├── index.tsx
│   │   ├── [id]/edit.tsx
│   │   ├── new.tsx
│   │   └── ocr/[id].tsx      # ⚠️ 1,350 lines - needs refactoring
│   ├── knowledgebase/        # KB management
│   │   ├── index.tsx
│   │   ├── [id]/
│   │   │   ├── edit.tsx      # ⚠️ 1,184 lines - needs refactoring
│   │   │   ├── chat.tsx
│   │   │   └── documents/new.tsx
│   └── settings/
└── components/
    ├── ui/                   # ShadcnUI components
    └── documents/            # Document-specific components
```

### Integration Points

- **Auth Service (8002)**: Admin login, token validation
- **User API (8001)**: User profile lookups
- **Admin API (8003)**: Document processing, KB operations, chat
- **Cookies**: httpOnly cookies for JWT storage

### Known Issues

**File Size Violations** (Constitutional limit: 500 lines):

- `src/pages/documents/ocr/[id].tsx` (1,350 lines)
  - Refactor into: OCRViewer, ElementTree, HierarchyEditor components
- `src/pages/knowledgebase/[id]/edit.tsx` (1,184 lines)
  - Refactor into: KBEditor, DocumentList, Settings components

**Refactoring Strategy**: Use Specify workflow to create refactoring spec when next modifying these files

### Environment Variables

- `AUTH_SERVER_URL`: <http://host.docker.internal:8002>
- `API_SERVER_URL`: <http://host.docker.internal:8001>
- `ADMIN_API_URL`: <http://host.docker.internal:8003>
- `JWT_SECRET`: For cookie encryption

## Common Frontend Patterns

### BFF Pattern Implementation

```text
Browser → Next.js API Route (/api/users) → Backend Service (8001/users)
         ↑ httpOnly cookies               ↑ JWT in headers
```

- Frontend pages: UI rendering, user interactions
- API routes (`/api/*`): Proxy requests to backend microservices
- JWT tokens: Managed via httpOnly cookies (XSS prevention)
- No direct backend communication from browser JavaScript

### Authentication Flow

1. User logs in → BFF `/api/auth/login` → Auth service
2. Auth service returns JWT tokens (access + refresh)
3. BFF stores tokens in httpOnly cookies
4. Subsequent requests: BFF extracts tokens from cookies → adds to backend request headers
5. Backend validates JWTs using JWKS

### Error Handling

- API errors: Display user-friendly messages
- Token expiration: Automatic refresh or redirect to login
- Network errors: Retry logic with exponential backoff

### State Management

- Local state: React useState/useReducer
- Server state: SWR or React Query for caching
- Global state: Context API (minimal usage)

## Development Commands

```bash
# Install dependencies
npm install

# Development server
npm run dev  # Port 3002 (user) or 3003 (admin)

# Build
npm run build

# Production
npm run start

# Linting
npm run lint
```

## Testing Approach

- **Unit tests**: Components with Jest + React Testing Library
- **Integration tests**: API routes with MSW (Mock Service Worker)
- **E2E tests**: Critical flows with Playwright
- **Contract tests**: Verify API proxy behavior matches backend contracts
