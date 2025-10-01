# Pydanticスキーマ

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [認証スキーマ](#認証スキーマ)
- [ユーザースキーマ](#ユーザースキーマ)
- [ドキュメントスキーマ](#ドキュメントスキーマ)
- [バリデーション](#バリデーション)

---

## 概要

PydanticはPythonの型ヒントを使用したデータバリデーションライブラリです。FastAPIと統合して、リクエスト/レスポンスの自動検証を行います。

---

## 認証スキーマ

```python
# schemas/auth.py
from pydantic import BaseModel, EmailStr, Field
from typing import Literal

class LoginRequest(BaseModel):
    """ログインリクエスト"""
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)

    class Config:
        json_schema_extra = {
            "example": {
                "email": "user@example.com",
                "password": "SecurePass123!"
            }
        }

class UserInfo(BaseModel):
    """ユーザー情報"""
    user_id: str
    email: EmailStr
    role: Literal["user", "admin"]

class LoginResponse(BaseModel):
    """ログインレスポンス"""
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_in: int = 900
    user: UserInfo

class RegisterRequest(BaseModel):
    """ユーザー登録リクエスト"""
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    role: Literal["user", "admin"] = "user"

    @field_validator('password')
    @classmethod
    def validate_password(cls, v: str) -> str:
        """パスワード強度検証"""
        if not any(c.isupper() for c in v):
            raise ValueError('Password must contain at least one uppercase letter')
        if not any(c.islower() for c in v):
            raise ValueError('Password must contain at least one lowercase letter')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain at least one digit')
        return v

class RefreshTokenRequest(BaseModel):
    """トークンリフレッシュリクエスト"""
    refresh_token: str

class RefreshTokenResponse(BaseModel):
    """トークンリフレッシュレスポンス"""
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_in: int = 900
```

---

## ユーザースキーマ

```python
# schemas/user.py
from pydantic import BaseModel, EmailStr, Field, HttpUrl
from typing import Optional
from datetime import datetime
from uuid import UUID

class UserProfileBase(BaseModel):
    """ユーザープロフィール基本スキーマ"""
    first_name: Optional[str] = Field(None, max_length=100)
    last_name: Optional[str] = Field(None, max_length=100)
    avatar_url: Optional[HttpUrl] = None
    bio: Optional[str] = Field(None, max_length=500)

class UserProfile(UserProfileBase):
    """ユーザープロフィール"""
    id: UUID
    user_id: UUID
    email: EmailStr
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "user_id": "550e8400-e29b-41d4-a716-446655440001",
                "email": "user@example.com",
                "first_name": "John",
                "last_name": "Doe",
                "avatar_url": "https://example.com/avatar.jpg",
                "bio": "Software Developer",
                "created_at": "2025-09-30T10:00:00Z",
                "updated_at": "2025-09-30T10:00:00Z"
            }
        }

class UpdateProfileRequest(UserProfileBase):
    """プロフィール更新リクエスト"""
    pass

class UpdateProfileResponse(BaseModel):
    """プロフィール更新レスポンス"""
    profile: UserProfile
```

---

## ドキュメントスキーマ

```python
# schemas/document.py
from pydantic import BaseModel, Field
from typing import Literal, List, Optional
from datetime import datetime
from uuid import UUID

class DocumentStatus(str):
    """ドキュメントステータス"""
    UPLOADED = "uploaded"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class DocumentBase(BaseModel):
    """ドキュメント基本スキーマ"""
    filename: str = Field(..., max_length=255)
    mime_type: str = Field(..., max_length=100)

class Document(DocumentBase):
    """ドキュメント"""
    id: UUID
    user_id: UUID
    file_path: str
    file_size: int
    status: Literal["uploaded", "processing", "completed", "failed"]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class HierarchicalElement(BaseModel):
    """階層構造要素"""
    id: str
    type: Literal["title", "section", "paragraph", "list", "table"]
    level: int = Field(..., ge=1, le=6)
    text: str
    bbox: tuple[float, float, float, float]
    confidence: float = Field(..., ge=0.0, le=1.0)
    children: List["HierarchicalElement"] = []

class OCRResult(BaseModel):
    """OCR結果"""
    id: UUID
    document_id: UUID
    page_number: int = Field(..., ge=1)
    text_content: str
    hierarchical_elements: List[HierarchicalElement]
    confidence: float = Field(..., ge=0.0, le=1.0)
    created_at: datetime

    class Config:
        from_attributes = True

class UploadDocumentResponse(BaseModel):
    """ドキュメントアップロードレスポンス"""
    document: Document

class DocumentListResponse(BaseModel):
    """ドキュメント一覧レスポンス"""
    documents: List[Document]
    total: int
    page: int = 1
    per_page: int = 10
```

---

## バリデーション

### カスタムバリデーター

```python
from pydantic import BaseModel, field_validator
import re

class UserCreate(BaseModel):
    email: str
    password: str

    @field_validator('email')
    @classmethod
    def validate_email_domain(cls, v: str) -> str:
        """メールドメイン検証"""
        allowed_domains = ['example.com', 'company.com']
        domain = v.split('@')[1]
        if domain not in allowed_domains:
            raise ValueError(f'Email domain must be one of {allowed_domains}')
        return v

    @field_validator('password')
    @classmethod
    def validate_password_complexity(cls, v: str) -> str:
        """パスワード複雑性検証"""
        if len(v) < 12:
            raise ValueError('Password must be at least 12 characters')

        if not re.search(r'[A-Z]', v):
            raise ValueError('Password must contain uppercase letter')

        if not re.search(r'[a-z]', v):
            raise ValueError('Password must contain lowercase letter')

        if not re.search(r'\d', v):
            raise ValueError('Password must contain digit')

        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', v):
            raise ValueError('Password must contain special character')

        return v
```

### モデル検証

```python
from pydantic import BaseModel, model_validator

class DateRange(BaseModel):
    start_date: datetime
    end_date: datetime

    @model_validator(mode='after')
    def validate_date_range(self) -> 'DateRange':
        """日付範囲検証"""
        if self.start_date >= self.end_date:
            raise ValueError('start_date must be before end_date')
        return self
```

---

## 関連ドキュメント

- [データモデル定義](./03-data-models.md)
- [TypeScript型定義](./05-typescript-types.md)
- [OpenAPI統合](./04-openapi-integration.md)
- [契約テスト](./07-contract-testing.md)