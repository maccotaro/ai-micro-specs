# TypeScript型定義

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [認証型定義](#認証型定義)
- [ユーザー型定義](#ユーザー型定義)
- [ドキュメント型定義](#ドキュメント型定義)
- [ユーティリティ型](#ユーティリティ型)

---

## 概要

フロントエンド（Next.js/React）で使用するTypeScript型定義を提供します。

---

## 認証型定義

```typescript
// types/auth.ts

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  expires_in: number;
  user: UserInfo;
}

export interface UserInfo {
  user_id: string;
  email: string;
  role: UserRole;
}

export type UserRole = "user" | "admin";

export interface RegisterRequest {
  email: string;
  password: string;
  role?: UserRole;
}

export interface RegisterResponse {
  user_id: string;
  email: string;
  role: UserRole;
  created_at: string;
}

export interface RefreshTokenRequest {
  refresh_token: string;
}

export interface RefreshTokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  expires_in: number;
}
```

---

## ユーザー型定義

```typescript
// types/user.ts

export interface UserProfile {
  id: string;
  user_id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  created_at: string;
  updated_at: string;
}

export interface UpdateProfileRequest {
  first_name?: string;
  last_name?: string;
  avatar_url?: string;
  bio?: string;
}

export interface UpdateProfileResponse {
  profile: UserProfile;
}
```

---

## ドキュメント型定義

```typescript
// types/document.ts

export type DocumentStatus = "uploaded" | "processing" | "completed" | "failed";

export interface Document {
  id: string;
  user_id: string;
  filename: string;
  file_path: string;
  file_size: number;
  mime_type: string;
  status: DocumentStatus;
  created_at: string;
  updated_at: string;
}

export interface DocumentListResponse {
  documents: Document[];
  total: number;
  page: number;
  per_page: number;
}

export interface OCRResult {
  id: string;
  document_id: string;
  page_number: number;
  text_content: string;
  hierarchical_elements: HierarchicalElement[];
  confidence: number;
  created_at: string;
}

export type ElementType = "title" | "section" | "paragraph" | "list" | "table";

export interface HierarchicalElement {
  id: string;
  type: ElementType;
  level: number;
  text: string;
  bbox: [number, number, number, number];
  confidence: number;
  children: HierarchicalElement[];
}

export interface UploadDocumentRequest {
  file: File;
}

export interface UploadDocumentResponse {
  document: Document;
}
```

---

## ユーティリティ型

```typescript
// types/common.ts

export interface ApiResponse<T = any> {
  status: "success" | "error";
  data?: T;
  error?: ApiError;
  message?: string;
}

export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, any>;
  trace_id?: string;
}

export interface PaginationParams {
  page?: number;
  per_page?: number;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  per_page: number;
  total_pages: number;
}

// 型ガード
export function isApiError(response: ApiResponse): response is Required<Pick<ApiResponse, 'error'>> {
  return response.status === "error" && !!response.error;
}

export function isApiSuccess<T>(response: ApiResponse<T>): response is Required<Pick<ApiResponse<T>, 'data'>> {
  return response.status === "success" && !!response.data;
}
```

### 使用例

```typescript
// lib/api.ts
import type { LoginRequest, LoginResponse, ApiResponse } from '@/types';

export async function login(credentials: LoginRequest): Promise<LoginResponse> {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(credentials),
  });

  const result: ApiResponse<LoginResponse> = await response.json();

  if (isApiError(result)) {
    throw new Error(result.error.message);
  }

  return result.data;
}
```

---

## 関連ドキュメント

- [データモデル定義](./03-data-models.md)
- [Pydanticスキーマ](./06-pydantic-schemas.md)
- [OpenAPI統合](./04-openapi-integration.md)