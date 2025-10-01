# User Frontend コンポーネント設計

**カテゴリ**: Frontend Service
**最終更新**: 2025-09-30

## 目次
- [コンポーネント設計方針](#コンポーネント設計方針)
- [コンポーネント構造](#コンポーネント構造)
- [再利用可能コンポーネント](#再利用可能コンポーネント)
- [ページコンポーネント](#ページコンポーネント)
- [スタイリング](#スタイリング)

---

## コンポーネント設計方針

### 基本原則

1. **単一責任の原則（SRP）**
   - 1つのコンポーネントは1つの責務のみを持つ
   - 複雑なコンポーネントは小さなコンポーネントに分割

2. **再利用性**
   - 汎用的なUI要素は再利用可能なコンポーネントとして作成
   - props経由でカスタマイズ可能に

3. **型安全性**
   - TypeScriptで型定義を必須化
   - propsの型を明確に定義

4. **テスタビリティ**
   - ロジックとUIを分離
   - カスタムHookでビジネスロジックを抽出

### コンポーネント分類

| 分類 | 説明 | 例 |
|------|------|---|
| **Presentational** | 見た目のみを担当、状態を持たない | Button, Card, Input |
| **Container** | データフェッチや状態管理を担当 | ProfileView, DocumentList |
| **Layout** | ページ構造を提供 | Header, Footer, Sidebar |
| **Page** | Next.jsのページコンポーネント | pages/*.tsx |

---

## コンポーネント構造

### ディレクトリ構造

```
src/
├── components/           # 再利用可能コンポーネント
│   ├── common/          # 共通UI要素
│   │   ├── Button.tsx
│   │   ├── Input.tsx
│   │   ├── Card.tsx
│   │   ├── Modal.tsx
│   │   └── Spinner.tsx
│   ├── forms/           # フォームコンポーネント
│   │   ├── LoginForm.tsx
│   │   ├── SignupForm.tsx
│   │   └── ProfileForm.tsx
│   ├── layout/          # レイアウトコンポーネント
│   │   ├── Header.tsx
│   │   ├── Footer.tsx
│   │   └── Navigation.tsx
│   └── rag/             # RAG機能コンポーネント
│       ├── ChatInterface.tsx
│       ├── DocumentCard.tsx
│       └── SearchBar.tsx
├── pages/               # Next.jsページ
│   ├── index.tsx
│   ├── login.tsx
│   ├── profile/
│   │   ├── view.tsx
│   │   └── edit.tsx
│   └── rag/
│       ├── chat.tsx
│       └── documents.tsx
└── hooks/               # カスタムHooks
    ├── useAuth.ts
    ├── useProfile.ts
    └── useDocuments.ts
```

---

## 再利用可能コンポーネント

### 1. Button コンポーネント

**ファイル**: `src/components/common/Button.tsx`

```typescript
import React from 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  loading?: boolean;
  fullWidth?: boolean;
  children: React.ReactNode;
}

export function Button({
  variant = 'primary',
  size = 'md',
  loading = false,
  fullWidth = false,
  disabled,
  className = '',
  children,
  ...props
}: ButtonProps) {
  const baseClasses = 'rounded-md font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors';

  const variantClasses = {
    primary: 'bg-indigo-600 text-white hover:bg-indigo-700 focus:ring-indigo-500',
    secondary: 'bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500',
    danger: 'bg-red-600 text-white hover:bg-red-700 focus:ring-red-500'
  };

  const sizeClasses = {
    sm: 'px-3 py-1.5 text-sm',
    md: 'px-4 py-2 text-base',
    lg: 'px-6 py-3 text-lg'
  };

  const widthClass = fullWidth ? 'w-full' : '';

  const classes = [
    baseClasses,
    variantClasses[variant],
    sizeClasses[size],
    widthClass,
    className
  ].join(' ');

  return (
    <button
      className={classes}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? (
        <span className="flex items-center justify-center">
          <Spinner size="sm" className="mr-2" />
          Loading...
        </span>
      ) : (
        children
      )}
    </button>
  );
}

// 使用例
export default function Example() {
  return (
    <div className="space-y-4">
      <Button variant="primary" size="md">
        Save
      </Button>

      <Button variant="secondary" size="sm">
        Cancel
      </Button>

      <Button variant="danger" loading>
        Deleting...
      </Button>

      <Button fullWidth>
        Full Width Button
      </Button>
    </div>
  );
}
```

### 2. Input コンポーネント

**ファイル**: `src/components/common/Input.tsx`

```typescript
import React from 'react';

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  helperText?: string;
}

export function Input({
  label,
  error,
  helperText,
  className = '',
  id,
  ...props
}: InputProps) {
  const inputId = id || label?.toLowerCase().replace(/\s+/g, '-');

  const inputClasses = [
    'block w-full rounded-md shadow-sm',
    'border-gray-300 focus:border-indigo-500 focus:ring-indigo-500',
    error ? 'border-red-300 focus:border-red-500 focus:ring-red-500' : '',
    className
  ].join(' ');

  return (
    <div>
      {label && (
        <label
          htmlFor={inputId}
          className="block text-sm font-medium text-gray-700 mb-1"
        >
          {label}
        </label>
      )}

      <input
        id={inputId}
        className={inputClasses}
        {...props}
      />

      {error && (
        <p className="mt-1 text-sm text-red-600">
          {error}
        </p>
      )}

      {!error && helperText && (
        <p className="mt-1 text-sm text-gray-500">
          {helperText}
        </p>
      )}
    </div>
  );
}

// 使用例
export default function Example() {
  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState('');

  return (
    <div className="space-y-4">
      <Input
        label="Email"
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="user@example.com"
        helperText="We'll never share your email"
      />

      <Input
        label="Password"
        type="password"
        error="Password must be at least 8 characters"
      />
    </div>
  );
}
```

### 3. Card コンポーネント

**ファイル**: `src/components/common/Card.tsx`

```typescript
import React from 'react';

interface CardProps {
  title?: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  className?: string;
}

export function Card({
  title,
  subtitle,
  children,
  footer,
  className = ''
}: CardProps) {
  return (
    <div className={`bg-white shadow rounded-lg overflow-hidden ${className}`}>
      {(title || subtitle) && (
        <div className="px-6 py-4 border-b border-gray-200">
          {title && (
            <h3 className="text-lg font-medium text-gray-900">
              {title}
            </h3>
          )}
          {subtitle && (
            <p className="mt-1 text-sm text-gray-500">
              {subtitle}
            </p>
          )}
        </div>
      )}

      <div className="px-6 py-4">
        {children}
      </div>

      {footer && (
        <div className="px-6 py-4 bg-gray-50 border-t border-gray-200">
          {footer}
        </div>
      )}
    </div>
  );
}

// 使用例
export default function Example() {
  return (
    <Card
      title="User Profile"
      subtitle="Manage your profile information"
      footer={
        <div className="flex justify-end space-x-3">
          <Button variant="secondary">Cancel</Button>
          <Button variant="primary">Save</Button>
        </div>
      }
    >
      <div className="space-y-4">
        <Input label="Name" />
        <Input label="Email" type="email" />
      </div>
    </Card>
  );
}
```

### 4. Modal コンポーネント

**ファイル**: `src/components/common/Modal.tsx`

```typescript
import React, { useEffect } from 'react';

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}

export function Modal({
  isOpen,
  onClose,
  title,
  children,
  footer
}: ModalProps) {
  // ESCキーで閉じる
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    if (isOpen) {
      document.addEventListener('keydown', handleEsc);
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleEsc);
      document.body.style.overflow = 'unset';
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Overlay */}
      <div
        className="fixed inset-0 bg-black bg-opacity-50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative bg-white rounded-lg shadow-xl max-w-lg w-full">
          {/* Header */}
          {title && (
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">
                {title}
              </h3>
              <button
                onClick={onClose}
                className="absolute top-4 right-4 text-gray-400 hover:text-gray-600"
              >
                <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          )}

          {/* Body */}
          <div className="px-6 py-4">
            {children}
          </div>

          {/* Footer */}
          {footer && (
            <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-end space-x-3">
              {footer}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// 使用例
export default function Example() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      <Button onClick={() => setIsOpen(true)}>
        Open Modal
      </Button>

      <Modal
        isOpen={isOpen}
        onClose={() => setIsOpen(false)}
        title="Confirm Deletion"
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsOpen(false)}>
              Cancel
            </Button>
            <Button variant="danger">
              Delete
            </Button>
          </>
        }
      >
        <p>Are you sure you want to delete this item?</p>
      </Modal>
    </>
  );
}
```

### 5. Spinner コンポーネント

**ファイル**: `src/components/common/Spinner.tsx`

```typescript
import React from 'react';

interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

export function Spinner({ size = 'md', className = '' }: SpinnerProps) {
  const sizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-8 h-8',
    lg: 'w-12 h-12'
  };

  return (
    <div
      className={`${sizeClasses[size]} ${className} animate-spin rounded-full border-2 border-gray-300 border-t-indigo-600`}
      role="status"
      aria-label="Loading"
    >
      <span className="sr-only">Loading...</span>
    </div>
  );
}

// 使用例
export default function LoadingPage() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <Spinner size="lg" />
    </div>
  );
}
```

---

## ページコンポーネント

### Profile View ページ

**ファイル**: `src/pages/profile/view.tsx`

```typescript
import { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';
import { Card } from '@/components/common/Card';
import { Button } from '@/components/common/Button';
import { Spinner } from '@/components/common/Spinner';

interface Profile {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  phone?: string;
  created_at: string;
  updated_at: string;
}

export default function ProfileView() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchProfile();
  }, []);

  const fetchProfile = async () => {
    try {
      const response = await fetch('/api/profile');

      if (response.status === 401) {
        router.push('/login');
        return;
      }

      if (response.ok) {
        const data = await response.json();
        setProfile(data);
      } else {
        setError('Failed to fetch profile');
      }
    } catch (error) {
      setError('An error occurred');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
      router.push('/login');
    } catch (error) {
      router.push('/login');
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Card title="Error">
          <p className="text-red-600">{error}</p>
          <div className="mt-4">
            <Link href="/login">
              <Button variant="primary">Go to Login</Button>
            </Link>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4">
      <div className="max-w-md mx-auto">
        <Card
          title="Profile"
          footer={
            <div className="space-y-3">
              <Link href="/profile/edit">
                <Button variant="primary" fullWidth>
                  Edit Profile
                </Button>
              </Link>
              <Link href="/">
                <Button variant="secondary" fullWidth>
                  Home
                </Button>
              </Link>
              <Button variant="danger" fullWidth onClick={handleLogout}>
                Logout
              </Button>
            </div>
          }
        >
          {profile && (
            <div className="space-y-4">
              <ProfileField label="Email" value={profile.email} />
              <ProfileField label="First Name" value={profile.first_name} />
              <ProfileField label="Last Name" value={profile.last_name} />
              <ProfileField label="Phone" value={profile.phone} />
              <ProfileField
                label="Member Since"
                value={new Date(profile.created_at).toLocaleDateString()}
              />
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}

function ProfileField({ label, value }: { label: string; value?: string }) {
  return (
    <div>
      <label className="block text-sm font-medium text-gray-700">
        {label}
      </label>
      <div className="mt-1 text-sm text-gray-900">
        {value || 'Not provided'}
      </div>
    </div>
  );
}
```

---

## スタイリング

### Tailwind CSSクラスの使用

**ユーティリティファースト**:
```typescript
<div className="flex items-center justify-between px-4 py-2 bg-white shadow rounded-lg">
  <h2 className="text-lg font-semibold text-gray-900">Title</h2>
  <button className="px-3 py-1 text-sm text-white bg-indigo-600 rounded hover:bg-indigo-700">
    Action
  </button>
</div>
```

**条件付きクラス**:
```typescript
import { cn } from '@/lib/utils';

<button
  className={cn(
    'px-4 py-2 rounded',
    isActive ? 'bg-indigo-600 text-white' : 'bg-gray-200 text-gray-700',
    disabled && 'opacity-50 cursor-not-allowed'
  )}
>
  Click Me
</button>
```

**レスポンシブデザイン**:
```typescript
<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
  {/* モバイル: 1列、タブレット: 2列、デスクトップ: 3列 */}
</div>
```

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [画面設計](./02-screen-design.md)
- [状態管理](./05-state-management.md)