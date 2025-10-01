# User Frontend 状態管理

**カテゴリ**: Frontend Service
**最終更新**: 2025-09-30

## 目次
- [状態管理の方針](#状態管理の方針)
- [React Hooks](#react-hooks)
- [ローカルステート](#ローカルステート)
- [サーバーステート](#サーバーステート)
- [フォーム管理](#フォーム管理)

---

## 状態管理の方針

User Frontendでは、シンプルさを重視し、React標準のHooksを中心とした状態管理を採用しています。

### 状態の分類

| 状態の種類 | 管理方法 | 例 |
|-----------|---------|---|
| **ローカルステート** | `useState`, `useReducer` | フォーム入力、UI状態 |
| **サーバーステート** | `useEffect` + `fetch` | プロファイルデータ、ドキュメント一覧 |
| **認証ステート** | カスタムHook (`useAuth`) | ユーザー情報、ログイン状態 |
| **URLステート** | Next.js Router | ページ遷移、クエリパラメータ |

### 外部ライブラリを使用しない理由

1. **シンプルさの維持**
   - アプリケーション規模が小規模〜中規模
   - 複雑な状態管理は不要

2. **学習コスト削減**
   - React標準機能のみで完結
   - チームメンバーの参入障壁を下げる

3. **バンドルサイズ削減**
   - 不要な依存関係を避ける
   - ページロード速度の最適化

---

## React Hooks

### 1. useState - ローカル状態管理

**基本的な使用例**:
```typescript
import { useState } from 'react';

export default function LoginForm() {
  // 単一の値
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  // 真偽値
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  // オブジェクト
  const [formData, setFormData] = useState({
    email: '',
    password: ''
  });

  const handleChange = (field: string, value: string) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
  };

  return (
    <form>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
      />
      <input
        type={showPassword ? 'text' : 'password'}
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      <button
        type="button"
        onClick={() => setShowPassword(!showPassword)}
      >
        {showPassword ? 'Hide' : 'Show'} Password
      </button>
    </form>
  );
}
```

### 2. useEffect - 副作用管理

**データフェッチ**:
```typescript
import { useState, useEffect } from 'react';

export default function ProfileView() {
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchProfile();
  }, []); // 空配列 = マウント時のみ実行

  const fetchProfile = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/profile');

      if (!response.ok) {
        throw new Error('Failed to fetch profile');
      }

      const data = await response.json();
      setProfile(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;

  return <ProfileDisplay profile={profile} />;
}
```

**依存配列の使用**:
```typescript
// 特定の値が変更された時のみ実行
useEffect(() => {
  fetchDocuments(searchTerm);
}, [searchTerm]); // searchTerm変更時に実行

// クリーンアップ関数
useEffect(() => {
  const timer = setTimeout(() => {
    console.log('Delayed action');
  }, 1000);

  // コンポーネントアンマウント時に実行
  return () => {
    clearTimeout(timer);
  };
}, []);
```

### 3. useReducer - 複雑な状態管理

**使用例**: 複数の関連する状態を持つフォーム
```typescript
import { useReducer } from 'react';

// 状態の型定義
interface FormState {
  values: {
    firstName: string;
    lastName: string;
    phone: string;
  };
  errors: {
    firstName?: string;
    lastName?: string;
    phone?: string;
  };
  touched: {
    firstName?: boolean;
    lastName?: boolean;
    phone?: boolean;
  };
  isSubmitting: boolean;
}

// アクションの型定義
type FormAction =
  | { type: 'SET_FIELD'; field: string; value: string }
  | { type: 'SET_ERROR'; field: string; error: string }
  | { type: 'TOUCH_FIELD'; field: string }
  | { type: 'SUBMIT_START' }
  | { type: 'SUBMIT_SUCCESS' }
  | { type: 'SUBMIT_ERROR' }
  | { type: 'RESET' };

// Reducer関数
function formReducer(state: FormState, action: FormAction): FormState {
  switch (action.type) {
    case 'SET_FIELD':
      return {
        ...state,
        values: {
          ...state.values,
          [action.field]: action.value
        }
      };

    case 'SET_ERROR':
      return {
        ...state,
        errors: {
          ...state.errors,
          [action.field]: action.error
        }
      };

    case 'TOUCH_FIELD':
      return {
        ...state,
        touched: {
          ...state.touched,
          [action.field]: true
        }
      };

    case 'SUBMIT_START':
      return {
        ...state,
        isSubmitting: true
      };

    case 'SUBMIT_SUCCESS':
      return {
        ...state,
        isSubmitting: false
      };

    case 'SUBMIT_ERROR':
      return {
        ...state,
        isSubmitting: false
      };

    case 'RESET':
      return initialState;

    default:
      return state;
  }
}

// 初期状態
const initialState: FormState = {
  values: {
    firstName: '',
    lastName: '',
    phone: ''
  },
  errors: {},
  touched: {},
  isSubmitting: false
};

// コンポーネント
export default function ProfileEditForm() {
  const [state, dispatch] = useReducer(formReducer, initialState);

  const handleChange = (field: string, value: string) => {
    dispatch({ type: 'SET_FIELD', field, value });

    // バリデーション
    if (!value.trim()) {
      dispatch({ type: 'SET_ERROR', field, error: 'Required field' });
    } else {
      dispatch({ type: 'SET_ERROR', field, error: '' });
    }
  };

  const handleBlur = (field: string) => {
    dispatch({ type: 'TOUCH_FIELD', field });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    dispatch({ type: 'SUBMIT_START' });

    try {
      const response = await fetch('/api/profile', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(state.values)
      });

      if (response.ok) {
        dispatch({ type: 'SUBMIT_SUCCESS' });
        // 成功処理
      } else {
        throw new Error('Update failed');
      }
    } catch (error) {
      dispatch({ type: 'SUBMIT_ERROR' });
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <label>First Name</label>
        <input
          type="text"
          value={state.values.firstName}
          onChange={(e) => handleChange('firstName', e.target.value)}
          onBlur={() => handleBlur('firstName')}
        />
        {state.touched.firstName && state.errors.firstName && (
          <div className="error">{state.errors.firstName}</div>
        )}
      </div>

      <button type="submit" disabled={state.isSubmitting}>
        {state.isSubmitting ? 'Saving...' : 'Save'}
      </button>
    </form>
  );
}
```

### 4. useCallback - 関数メモ化

**パフォーマンス最適化**:
```typescript
import { useState, useCallback } from 'react';

export default function DocumentList() {
  const [documents, setDocuments] = useState([]);
  const [searchTerm, setSearchTerm] = useState('');

  // 関数をメモ化して不要な再生成を防ぐ
  const handleSearch = useCallback(async (term: string) => {
    const response = await fetch(`/api/rag/documents?search=${term}`);
    const data = await response.json();
    setDocuments(data.documents);
  }, []); // 依存配列が空 = 関数は再生成されない

  // searchTermが変更された時のみ実行
  const debouncedSearch = useCallback(
    debounce((term: string) => {
      handleSearch(term);
    }, 500),
    [handleSearch]
  );

  return (
    <div>
      <input
        type="text"
        value={searchTerm}
        onChange={(e) => {
          setSearchTerm(e.target.value);
          debouncedSearch(e.target.value);
        }}
      />
      <DocumentGrid documents={documents} />
    </div>
  );
}

// デバウンスヘルパー
function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout;

  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}
```

### 5. useMemo - 値のメモ化

**計算コストの高い処理の最適化**:
```typescript
import { useMemo } from 'react';

export default function DocumentStats({ documents }) {
  // documentsが変更された時のみ再計算
  const stats = useMemo(() => {
    return {
      total: documents.length,
      processed: documents.filter(d => d.status === 'processed').length,
      processing: documents.filter(d => d.status === 'processing').length,
      failed: documents.filter(d => d.status === 'failed').length,
      totalSize: documents.reduce((sum, d) => sum + d.size, 0)
    };
  }, [documents]);

  return (
    <div>
      <div>Total: {stats.total}</div>
      <div>Processed: {stats.processed}</div>
      <div>Processing: {stats.processing}</div>
      <div>Failed: {stats.failed}</div>
      <div>Total Size: {formatBytes(stats.totalSize)}</div>
    </div>
  );
}
```

---

## ローカルステート

### フォーム状態管理

**シンプルなフォーム**:
```typescript
export default function ContactForm() {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    message: ''
  });
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);

  const handleChange = (field: string) => (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
  ) => {
    setFormData(prev => ({
      ...prev,
      [field]: e.target.value
    }));

    // エラーをクリア
    if (errors[field]) {
      setErrors(prev => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  };

  const validate = () => {
    const newErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    }

    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!/\S+@\S+\.\S+/.test(formData.email)) {
      newErrors.email = 'Invalid email format';
    }

    if (!formData.message.trim()) {
      newErrors.message = 'Message is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) return;

    setSubmitting(true);

    try {
      const response = await fetch('/api/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        alert('Message sent!');
        setFormData({ name: '', email: '', message: '' });
      }
    } catch (error) {
      alert('Failed to send message');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <input
          type="text"
          value={formData.name}
          onChange={handleChange('name')}
          placeholder="Name"
        />
        {errors.name && <span className="error">{errors.name}</span>}
      </div>

      <div>
        <input
          type="email"
          value={formData.email}
          onChange={handleChange('email')}
          placeholder="Email"
        />
        {errors.email && <span className="error">{errors.email}</span>}
      </div>

      <div>
        <textarea
          value={formData.message}
          onChange={handleChange('message')}
          placeholder="Message"
        />
        {errors.message && <span className="error">{errors.message}</span>}
      </div>

      <button type="submit" disabled={submitting}>
        {submitting ? 'Sending...' : 'Send'}
      </button>
    </form>
  );
}
```

### UI状態管理

**モーダル、ドロップダウンなど**:
```typescript
export default function DocumentItem({ document }) {
  const [showMenu, setShowMenu] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleDelete = async () => {
    await fetch(`/api/documents/${document.id}`, { method: 'DELETE' });
    setShowDeleteConfirm(false);
  };

  return (
    <div>
      <h3>{document.name}</h3>

      <button onClick={() => setShowMenu(!showMenu)}>
        Options
      </button>

      {showMenu && (
        <div className="dropdown-menu">
          <button onClick={() => setShowDeleteConfirm(true)}>
            Delete
          </button>
        </div>
      )}

      {showDeleteConfirm && (
        <div className="modal">
          <p>Are you sure you want to delete this document?</p>
          <button onClick={handleDelete}>Yes, Delete</button>
          <button onClick={() => setShowDeleteConfirm(false)}>Cancel</button>
        </div>
      )}
    </div>
  );
}
```

---

## サーバーステート

### データフェッチパターン

**基本パターン**:
```typescript
export default function useDocuments() {
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchDocuments();
  }, []);

  const fetchDocuments = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/rag/documents');
      const data = await response.json();
      setDocuments(data.documents);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const refetch = () => {
    fetchDocuments();
  };

  return {
    documents,
    loading,
    error,
    refetch
  };
}
```

### ページネーション

```typescript
export default function DocumentList() {
  const [documents, setDocuments] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    fetchDocuments(page);
  }, [page]);

  const fetchDocuments = async (pageNum: number) => {
    setLoading(true);

    try {
      const response = await fetch(`/api/rag/documents?page=${pageNum}&limit=20`);
      const data = await response.json();

      setDocuments(data.documents);
      setTotalPages(Math.ceil(data.total / 20));
    } catch (error) {
      console.error('Fetch error:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      {loading ? (
        <div>Loading...</div>
      ) : (
        <>
          <DocumentGrid documents={documents} />

          <div className="pagination">
            <button
              onClick={() => setPage(p => Math.max(1, p - 1))}
              disabled={page === 1}
            >
              Previous
            </button>

            <span>Page {page} of {totalPages}</span>

            <button
              onClick={() => setPage(p => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
            >
              Next
            </button>
          </div>
        </>
      )}
    </div>
  );
}
```

### 楽観的更新（Optimistic Update）

```typescript
export default function DocumentItem({ document, onUpdate }) {
  const [isUpdating, setIsUpdating] = useState(false);

  const toggleFavorite = async () => {
    const previousState = document.isFavorite;

    // 楽観的更新: APIレスポンス前にUIを更新
    onUpdate({
      ...document,
      isFavorite: !previousState
    });

    setIsUpdating(true);

    try {
      const response = await fetch(`/api/documents/${document.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isFavorite: !previousState })
      });

      if (!response.ok) {
        throw new Error('Update failed');
      }
    } catch (error) {
      // エラー時、元の状態に戻す
      onUpdate({
        ...document,
        isFavorite: previousState
      });
      alert('Failed to update favorite status');
    } finally {
      setIsUpdating(false);
    }
  };

  return (
    <button onClick={toggleFavorite} disabled={isUpdating}>
      {document.isFavorite ? '★' : '☆'}
    </button>
  );
}
```

---

## フォーム管理

### カスタムフォームHook

```typescript
import { useState, useCallback } from 'react';

interface FormConfig<T> {
  initialValues: T;
  validate?: (values: T) => Partial<Record<keyof T, string>>;
  onSubmit: (values: T) => Promise<void>;
}

export function useForm<T extends Record<string, any>>({
  initialValues,
  validate,
  onSubmit
}: FormConfig<T>) {
  const [values, setValues] = useState<T>(initialValues);
  const [errors, setErrors] = useState<Partial<Record<keyof T, string>>>({});
  const [touched, setTouched] = useState<Partial<Record<keyof T, boolean>>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleChange = useCallback((field: keyof T, value: any) => {
    setValues(prev => ({
      ...prev,
      [field]: value
    }));

    // フィールド変更時、エラーをクリア
    if (errors[field]) {
      setErrors(prev => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  }, [errors]);

  const handleBlur = useCallback((field: keyof T) => {
    setTouched(prev => ({
      ...prev,
      [field]: true
    }));

    // バリデーション実行
    if (validate) {
      const validationErrors = validate(values);
      if (validationErrors[field]) {
        setErrors(prev => ({
          ...prev,
          [field]: validationErrors[field]
        }));
      }
    }
  }, [values, validate]);

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();

    // 全フィールドをtouchedに
    const allTouched = Object.keys(values).reduce((acc, key) => {
      acc[key as keyof T] = true;
      return acc;
    }, {} as Partial<Record<keyof T, boolean>>);
    setTouched(allTouched);

    // バリデーション
    if (validate) {
      const validationErrors = validate(values);
      setErrors(validationErrors);

      if (Object.keys(validationErrors).length > 0) {
        return;
      }
    }

    // 送信
    setIsSubmitting(true);
    try {
      await onSubmit(values);
    } catch (error) {
      console.error('Form submission error:', error);
    } finally {
      setIsSubmitting(false);
    }
  }, [values, validate, onSubmit]);

  const reset = useCallback(() => {
    setValues(initialValues);
    setErrors({});
    setTouched({});
  }, [initialValues]);

  return {
    values,
    errors,
    touched,
    isSubmitting,
    handleChange,
    handleBlur,
    handleSubmit,
    reset
  };
}
```

### 使用例

```typescript
interface ProfileFormData {
  firstName: string;
  lastName: string;
  phone: string;
}

export default function ProfileEditForm() {
  const router = useRouter();

  const form = useForm<ProfileFormData>({
    initialValues: {
      firstName: '',
      lastName: '',
      phone: ''
    },
    validate: (values) => {
      const errors: Partial<Record<keyof ProfileFormData, string>> = {};

      if (!values.firstName.trim()) {
        errors.firstName = 'First name is required';
      }

      if (!values.lastName.trim()) {
        errors.lastName = 'Last name is required';
      }

      if (values.phone && !/^\+?\d{10,15}$/.test(values.phone)) {
        errors.phone = 'Invalid phone number';
      }

      return errors;
    },
    onSubmit: async (values) => {
      const response = await fetch('/api/profile', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values)
      });

      if (response.ok) {
        router.push('/profile/view');
      } else {
        throw new Error('Failed to update profile');
      }
    }
  });

  return (
    <form onSubmit={form.handleSubmit}>
      <div>
        <label>First Name</label>
        <input
          type="text"
          value={form.values.firstName}
          onChange={(e) => form.handleChange('firstName', e.target.value)}
          onBlur={() => form.handleBlur('firstName')}
        />
        {form.touched.firstName && form.errors.firstName && (
          <span className="error">{form.errors.firstName}</span>
        )}
      </div>

      <div>
        <label>Last Name</label>
        <input
          type="text"
          value={form.values.lastName}
          onChange={(e) => form.handleChange('lastName', e.target.value)}
          onBlur={() => form.handleBlur('lastName')}
        />
        {form.touched.lastName && form.errors.lastName && (
          <span className="error">{form.errors.lastName}</span>
        )}
      </div>

      <div>
        <label>Phone</label>
        <input
          type="tel"
          value={form.values.phone}
          onChange={(e) => form.handleChange('phone', e.target.value)}
          onBlur={() => form.handleBlur('phone')}
        />
        {form.touched.phone && form.errors.phone && (
          <span className="error">{form.errors.phone}</span>
        )}
      </div>

      <button type="submit" disabled={form.isSubmitting}>
        {form.isSubmitting ? 'Saving...' : 'Save'}
      </button>
    </form>
  );
}
```

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [コンポーネント設計](./06-component-design.md)
- [認証クライアント実装](./04-authentication-client.md)