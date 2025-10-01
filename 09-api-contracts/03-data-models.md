# データモデル定義

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [認証関連モデル](#認証関連モデル)
- [ユーザー関連モデル](#ユーザー関連モデル)
- [ドキュメント関連モデル](#ドキュメント関連モデル)
- [共通モデル](#共通モデル)

---

## 概要

全サービスで使用される主要なデータモデルを定義します。

---

## 認証関連モデル

### LoginRequest

```typescript
interface LoginRequest {
  email: string;
  password: string;
}
```

### LoginResponse

```typescript
interface LoginResponse {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  expires_in: number;
  user: {
    user_id: string;
    email: string;
    role: "user" | "admin";
  };
}
```

### RegisterRequest

```typescript
interface RegisterRequest {
  email: string;
  password: string;
  role?: "user" | "admin";
}
```

### RefreshRequest

```typescript
interface RefreshRequest {
  refresh_token: string;
}
```

---

## ユーザー関連モデル

### UserProfile

```typescript
interface UserProfile {
  id: string;
  user_id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  avatar_url: string | null;
  created_at: string;
  updated_at: string;
}
```

### UpdateProfileRequest

```typescript
interface UpdateProfileRequest {
  first_name?: string;
  last_name?: string;
  avatar_url?: string;
}
```

---

## ドキュメント関連モデル

### Document

```typescript
interface Document {
  id: string;
  user_id: string;
  filename: string;
  file_path: string;
  file_size: number;
  mime_type: string;
  status: "uploaded" | "processing" | "completed" | "failed";
  created_at: string;
  updated_at: string;
}
```

### OCRResult

```typescript
interface OCRResult {
  id: string;
  document_id: string;
  page_number: number;
  text_content: string;
  hierarchical_elements: HierarchicalElement[];
  confidence: number;
  created_at: string;
}
```

### HierarchicalElement

```typescript
interface HierarchicalElement {
  id: string;
  type: "title" | "section" | "paragraph" | "list";
  level: number;
  text: string;
  bbox: [number, number, number, number];
  confidence: number;
  children: HierarchicalElement[];
}
```

---

## 共通モデル

### ApiResponse

```typescript
interface ApiResponse<T> {
  status: "success" | "error";
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: any;
  };
  message?: string;
}
```

### PaginationParams

```typescript
interface PaginationParams {
  page: number;
  per_page: number;
}
```

### PaginatedResponse

```typescript
interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  per_page: number;
  total_pages: number;
}
```

---

## 関連ドキュメント

- [TypeScript型定義](./05-typescript-types.md)
- [Pydanticスキーマ](./06-pydantic-schemas.md)
- [API仕様](../01-auth-service/02-api-specification.md)