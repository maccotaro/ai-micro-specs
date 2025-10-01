# User Frontend 画面設計

**カテゴリ**: Frontend Service
**最終更新**: 2025-09-30

## 目次
- [画面一覧](#画面一覧)
- [認証画面](#認証画面)
- [プロファイル画面](#プロファイル画面)
- [RAG機能画面](#rag機能画面)
- [共通UI要素](#共通ui要素)

---

## 画面一覧

### 公開画面（認証不要）

| パス | 画面名 | 説明 |
|------|--------|------|
| `/` | ホーム | サービス紹介、ログイン状態確認 |
| `/login` | ログイン | ユーザー認証画面 |
| `/signup` | サインアップ | 新規ユーザー登録 |

### 保護画面（認証必須）

| パス | 画面名 | 説明 |
|------|--------|------|
| `/profile/view` | プロファイル表示 | ユーザー情報表示 |
| `/profile/edit` | プロファイル編集 | ユーザー情報編集 |
| `/rag/chat` | RAGチャット | ドキュメント検索・会話 |
| `/rag/documents` | ドキュメント一覧 | アップロードドキュメント管理 |
| `/rag/upload` | ドキュメントアップロード | 新規ファイルアップロード |
| `/logout` | ログアウト | ログアウト処理とリダイレクト |

---

## 認証画面

### 1. ホームページ (`/`)

**目的**: サービス紹介と認証状態に応じたナビゲーション

**レイアウト**:
```
┌──────────────────────────────────────┐
│  Header                              │
│  [Logo] [Home] [Login] [Signup]     │
├──────────────────────────────────────┤
│                                      │
│         Welcome to User Portal       │
│                                      │
│  認証済み: → Go to Profile           │
│  未認証:   → Login / Signup          │
│                                      │
└──────────────────────────────────────┘
```

**実装例**:
```typescript
export default function HomePage() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkAuthStatus();
  }, []);

  const checkAuthStatus = async () => {
    try {
      const response = await fetch('/api/profile');
      setIsAuthenticated(response.ok);
    } catch {
      setIsAuthenticated(false);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <div>Loading...</div>;

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow">
        <nav className="max-w-7xl mx-auto px-4 py-4">
          <Link href="/">Home</Link>
          {!isAuthenticated && (
            <>
              <Link href="/login">Login</Link>
              <Link href="/signup">Signup</Link>
            </>
          )}
          {isAuthenticated && (
            <Link href="/profile/view">Profile</Link>
          )}
        </nav>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-8">
        <h1 className="text-4xl font-bold mb-4">
          Welcome to User Portal
        </h1>
        {isAuthenticated ? (
          <Link href="/profile/view" className="btn-primary">
            Go to Profile
          </Link>
        ) : (
          <div className="space-x-4">
            <Link href="/login" className="btn-primary">
              Login
            </Link>
            <Link href="/signup" className="btn-secondary">
              Signup
            </Link>
          </div>
        )}
      </main>
    </div>
  );
}
```

### 2. ログイン画面 (`/login`)

**目的**: ユーザー認証

**レイアウト**:
```
┌──────────────────────────────────────┐
│            Login                     │
├──────────────────────────────────────┤
│                                      │
│  Email                               │
│  [___________________________]       │
│                                      │
│  Password                            │
│  [___________________________]       │
│                                      │
│  [    Login    ]                     │
│                                      │
│  Don't have an account? → Signup     │
│                                      │
└──────────────────────────────────────┘
```

**実装例**:
```typescript
export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });

      if (response.ok) {
        router.push('/profile/view');
      } else {
        const data = await response.json();
        setError(data.error || 'Login failed');
      }
    } catch (error) {
      setError('An error occurred during login');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="max-w-md w-full">
        <h1 className="text-3xl font-extrabold text-center mb-8">
          Login
        </h1>

        <form onSubmit={handleSubmit} className="bg-white shadow rounded-lg px-8 py-6">
          {error && (
            <div className="mb-4 p-3 bg-red-100 text-red-700 rounded">
              {error}
            </div>
          )}

          <div className="mb-4">
            <label htmlFor="email" className="block text-sm font-medium text-gray-700">
              Email
            </label>
            <input
              type="email"
              id="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
              required
            />
          </div>

          <div className="mb-6">
            <label htmlFor="password" className="block text-sm font-medium text-gray-700">
              Password
            </label>
            <input
              type="password"
              id="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50"
          >
            {loading ? 'Logging in...' : 'Login'}
          </button>

          <div className="mt-4 text-center">
            <Link href="/signup" className="text-sm text-indigo-600 hover:text-indigo-500">
              Don't have an account? Sign up
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
```

### 3. サインアップ画面 (`/signup`)

**目的**: 新規ユーザー登録

**レイアウト**:
```
┌──────────────────────────────────────┐
│          Sign Up                     │
├──────────────────────────────────────┤
│                                      │
│  Email                               │
│  [___________________________]       │
│                                      │
│  Password                            │
│  [___________________________]       │
│                                      │
│  Confirm Password                    │
│  [___________________________]       │
│                                      │
│  [    Sign Up    ]                   │
│                                      │
│  Already have an account? → Login    │
│                                      │
└──────────────────────────────────────┘
```

**実装例**:
```typescript
export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    // バリデーション
    if (password !== confirmPassword) {
      setError('Passwords do not match');
      return;
    }

    if (password.length < 8) {
      setError('Password must be at least 8 characters');
      return;
    }

    setLoading(true);

    try {
      const response = await fetch('/api/auth/signup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });

      if (response.ok) {
        // サインアップ成功後、自動ログイン
        router.push('/profile/view');
      } else {
        const data = await response.json();
        setError(data.error || 'Signup failed');
      }
    } catch (error) {
      setError('An error occurred during signup');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="max-w-md w-full">
        <h1 className="text-3xl font-extrabold text-center mb-8">
          Sign Up
        </h1>

        <form onSubmit={handleSubmit} className="bg-white shadow rounded-lg px-8 py-6">
          {error && (
            <div className="mb-4 p-3 bg-red-100 text-red-700 rounded">
              {error}
            </div>
          )}

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700">
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
              required
            />
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700">
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
              required
            />
          </div>

          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700">
              Confirm Password
            </label>
            <input
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 px-4 border border-transparent rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50"
          >
            {loading ? 'Signing up...' : 'Sign Up'}
          </button>

          <div className="mt-4 text-center">
            <Link href="/login" className="text-sm text-indigo-600 hover:text-indigo-500">
              Already have an account? Login
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
```

---

## プロファイル画面

### 1. プロファイル表示 (`/profile/view`)

**目的**: ユーザー情報の表示

**レイアウト**:
```
┌──────────────────────────────────────┐
│  Profile                             │
├──────────────────────────────────────┤
│                                      │
│  Email:        user@example.com      │
│  First Name:   John                  │
│  Last Name:    Doe                   │
│  Phone:        +81-90-1234-5678      │
│  Member Since: 2025-01-15            │
│  Last Updated: 2025-09-30            │
│                                      │
│  [  Edit Profile  ]                  │
│  [     Home       ]                  │
│  [    Logout      ]                  │
│                                      │
└──────────────────────────────────────┘
```

**データ型**:
```typescript
interface Profile {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  phone?: string;
  created_at: string;
  updated_at: string;
}
```

### 2. プロファイル編集 (`/profile/edit`)

**目的**: ユーザー情報の編集

**レイアウト**:
```
┌──────────────────────────────────────┐
│  Edit Profile                        │
├──────────────────────────────────────┤
│                                      │
│  Email (読み取り専用)                │
│  [user@example.com_______________]   │
│                                      │
│  First Name                          │
│  [___________________________]       │
│                                      │
│  Last Name                           │
│  [___________________________]       │
│                                      │
│  Phone                               │
│  [___________________________]       │
│                                      │
│  [  Save Changes  ] [  Cancel  ]     │
│                                      │
└──────────────────────────────────────┘
```

**実装例**:
```typescript
export default function ProfileEdit() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchProfile();
  }, []);

  const fetchProfile = async () => {
    try {
      const response = await fetch('/api/profile');
      if (response.ok) {
        const data = await response.json();
        setProfile(data);
        setFirstName(data.first_name || '');
        setLastName(data.last_name || '');
        setPhone(data.phone || '');
      }
    } catch (error) {
      setError('Failed to load profile');
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError('');

    try {
      const response = await fetch('/api/profile', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          first_name: firstName,
          last_name: lastName,
          phone: phone
        })
      });

      if (response.ok) {
        router.push('/profile/view');
      } else {
        const data = await response.json();
        setError(data.error || 'Failed to update profile');
      }
    } catch (error) {
      setError('An error occurred while updating profile');
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div>Loading...</div>;

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4">
      <div className="max-w-md mx-auto">
        <h1 className="text-3xl font-extrabold text-center mb-8">
          Edit Profile
        </h1>

        <form onSubmit={handleSubmit} className="bg-white shadow rounded-lg px-6 py-8">
          {error && (
            <div className="mb-4 p-3 bg-red-100 text-red-700 rounded">
              {error}
            </div>
          )}

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700">
              Email (cannot be changed)
            </label>
            <input
              type="email"
              value={profile?.email || ''}
              disabled
              className="mt-1 block w-full rounded-md bg-gray-100 cursor-not-allowed"
            />
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700">
              First Name
            </label>
            <input
              type="text"
              value={firstName}
              onChange={(e) => setFirstName(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300"
            />
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700">
              Last Name
            </label>
            <input
              type="text"
              value={lastName}
              onChange={(e) => setLastName(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300"
            />
          </div>

          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700">
              Phone
            </label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              className="mt-1 block w-full rounded-md border-gray-300"
            />
          </div>

          <div className="flex space-x-4">
            <button
              type="submit"
              disabled={saving}
              className="flex-1 py-2 px-4 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50"
            >
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
            <button
              type="button"
              onClick={() => router.push('/profile/view')}
              className="flex-1 py-2 px-4 bg-gray-300 text-gray-700 rounded-md hover:bg-gray-400"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
```

---

## RAG機能画面

### 1. チャット画面 (`/rag/chat`)

**目的**: ドキュメントベースの質問応答

**レイアウト**:
```
┌──────────────────────────────────────────────────┐
│  RAG Chat                    [Knowledge Base: ▼] │
├──────────────────────────────────────────────────┤
│                                                  │
│  [User]  What is the main topic of document A?  │
│                                                  │
│  [AI]    The main topic of document A is...     │
│          (streaming response)                    │
│                                                  │
│  Referenced Documents:                           │
│  - Document A (page 5, chunk 12)                 │
│  - Document B (page 2, chunk 3)                  │
│                                                  │
├──────────────────────────────────────────────────┤
│  [_________________________________] [Send]      │
└──────────────────────────────────────────────────┘
```

**主な機能**:
- ストリーミングレスポンス表示
- マークダウンフォーマット対応
- 参照ドキュメント表示
- ナレッジベース選択
- 会話履歴表示

### 2. ドキュメント一覧 (`/rag/documents`)

**目的**: アップロード済みドキュメントの管理

**レイアウト**:
```
┌──────────────────────────────────────────────────┐
│  My Documents              [+ Upload New]        │
├──────────────────────────────────────────────────┤
│  Search: [________________]  Filter: [All ▼]     │
├──────────────────────────────────────────────────┤
│  Name              Type    Status      Actions   │
│  ────────────────────────────────────────────── │
│  document_a.pdf    PDF     Processed   [👁][📥]  │
│  report_2025.docx  Word    Processing  [👁][📥]  │
│  slides.pptx       PPT     Uploaded    [👁][📥]  │
│                                                  │
│  Pagination: [<] 1 2 3 [>]                       │
└──────────────────────────────────────────────────┘
```

### 3. ドキュメントアップロード (`/rag/upload`)

**目的**: 新規ドキュメントのアップロード

**レイアウト**:
```
┌──────────────────────────────────────┐
│  Upload Document                     │
├──────────────────────────────────────┤
│                                      │
│  Knowledge Base                      │
│  [Select Knowledge Base... ▼]       │
│                                      │
│  File Upload                         │
│  ┌────────────────────────────────┐ │
│  │  Drag & Drop file here         │ │
│  │  or                            │ │
│  │  [ Browse Files ]              │ │
│  └────────────────────────────────┘ │
│                                      │
│  Supported formats:                  │
│  PDF, Word, PowerPoint, Excel        │
│  Max size: 50MB                      │
│                                      │
│  [    Upload    ]                    │
│                                      │
└──────────────────────────────────────┘
```

---

## 共通UI要素

### 1. ローディング状態

```typescript
// スピナーコンポーネント
function LoadingSpinner() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="spinner w-8 h-8"></div>
      <p className="ml-2 text-gray-600">Loading...</p>
    </div>
  );
}
```

### 2. エラー表示

```typescript
// エラーメッセージコンポーネント
function ErrorMessage({ message }: { message: string }) {
  return (
    <div className="p-3 bg-red-100 text-red-700 rounded-md">
      {message}
    </div>
  );
}
```

### 3. 成功メッセージ

```typescript
// 成功メッセージコンポーネント
function SuccessMessage({ message }: { message: string }) {
  return (
    <div className="p-3 bg-green-100 text-green-700 rounded-md">
      {message}
    </div>
  );
}
```

### 4. ボタンスタイル

```css
/* Primary Button */
.btn-primary {
  @apply py-2 px-4 border border-transparent rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50;
}

/* Secondary Button */
.btn-secondary {
  @apply py-2 px-4 border border-gray-300 rounded-md shadow-sm text-gray-700 bg-white hover:bg-gray-50;
}

/* Danger Button */
.btn-danger {
  @apply py-2 px-4 border border-transparent rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700;
}
```

### 5. レスポンシブデザイン

```typescript
// モバイル対応例
<div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
  {/* コンテンツ */}
</div>
```

**ブレークポイント**:
- `sm`: 640px以上
- `md`: 768px以上
- `lg`: 1024px以上
- `xl`: 1280px以上

---

## アクセシビリティ

### ベストプラクティス

1. **セマンティックHTML**
   ```html
   <header>, <nav>, <main>, <article>, <footer>
   ```

2. **フォームラベル**
   ```html
   <label htmlFor="email">Email</label>
   <input id="email" type="email" />
   ```

3. **キーボードナビゲーション**
   - Tab順序の最適化
   - フォーカス状態の視覚化

4. **ARIAラベル**
   ```html
   <button aria-label="Close dialog">×</button>
   ```

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [API統合](./03-api-integration.md)
- [コンポーネント設計](./06-component-design.md)