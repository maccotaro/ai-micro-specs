# User Frontend プロファイル機能

**カテゴリ**: Frontend Service
**最終更新**: 2025-09-30

## 目次
- [機能概要](#機能概要)
- [プロファイル表示](#プロファイル表示)
- [プロファイル編集](#プロファイル編集)
- [データフロー](#データフロー)
- [バリデーション](#バリデーション)

---

## 機能概要

プロファイル機能は、ユーザー自身の個人情報を管理するための機能です。

### 提供機能

| 機能 | エンドポイント | 説明 |
|------|-------------|------|
| プロファイル表示 | `/profile/view` | ユーザー情報の閲覧 |
| プロファイル編集 | `/profile/edit` | ユーザー情報の更新 |
| 自動プロファイル作成 | - | 初回アクセス時、空のプロファイルを自動作成 |

### データ構造

```typescript
interface Profile {
  id: string;                 // UUID
  email: string;              // ユーザーのメールアドレス（変更不可）
  first_name?: string;        // 名
  last_name?: string;         // 姓
  phone?: string;             // 電話番号
  created_at: string;         // 作成日時 (ISO 8601)
  updated_at: string;         // 更新日時 (ISO 8601)
}
```

---

## プロファイル表示

### 画面仕様

**パス**: `/profile/view`

**機能**:
- ユーザープロファイル情報の表示
- 編集画面への遷移
- ログアウト機能

### 実装例

**ファイル**: `src/pages/profile/view.tsx`

```typescript
import { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';

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
        // 未認証の場合、ログインページへ
        router.push('/login');
        return;
      }

      if (response.ok) {
        const data = await response.json();
        setProfile(data);
      } else {
        const errorData = await response.json();
        setError(errorData.error || 'Failed to fetch profile');
      }
    } catch (error) {
      console.error('Profile fetch error:', error);
      setError('An error occurred while fetching profile');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
      router.push('/login');
    } catch (error) {
      console.error('Logout error:', error);
      // エラーでもログインページへ
      router.push('/login');
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-lg">Loading profile...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="text-red-600 mb-4">{error}</div>
          <div className="space-y-3">
            <Link href="/login" className="block text-indigo-600 hover:text-indigo-500">
              Go to Login
            </Link>
            <button
              onClick={handleLogout}
              className="w-full py-2 px-4 bg-red-600 text-white rounded-md hover:bg-red-700"
            >
              Logout
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md mx-auto">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-extrabold text-gray-900">Profile</h1>
        </div>

        <div className="bg-white shadow rounded-lg px-6 py-8">
          {profile && (
            <div className="space-y-6">
              <ProfileField label="Email" value={profile.email} />
              <ProfileField label="First Name" value={profile.first_name} />
              <ProfileField label="Last Name" value={profile.last_name} />
              <ProfileField label="Phone" value={profile.phone} />
              <ProfileField
                label="Member Since"
                value={new Date(profile.created_at).toLocaleDateString()}
              />
              <ProfileField
                label="Last Updated"
                value={new Date(profile.updated_at).toLocaleDateString()}
              />
            </div>
          )}

          <div className="mt-8 space-y-3">
            <Link
              href="/profile/edit"
              className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700"
            >
              Edit Profile
            </Link>

            <Link
              href="/"
              className="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
            >
              Home
            </Link>

            <button
              onClick={handleLogout}
              className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-red-600 hover:bg-red-700"
            >
              Logout
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// フィールド表示コンポーネント
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

### API連携

**エンドポイント**: `GET /api/profile`

**リクエスト**:
```http
GET /api/profile HTTP/1.1
Cookie: access_token=...
```

**レスポンス**:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "first_name": "John",
  "last_name": "Doe",
  "phone": "+81-90-1234-5678",
  "created_at": "2025-01-15T10:00:00Z",
  "updated_at": "2025-09-30T15:30:00Z"
}
```

---

## プロファイル編集

### 画面仕様

**パス**: `/profile/edit`

**機能**:
- プロファイル情報の編集
- フォームバリデーション
- 保存・キャンセル機能

### 実装例

**ファイル**: `src/pages/profile/edit.tsx`

```typescript
import { useState, useEffect } from 'react';
import { useRouter } from 'next/router';

interface ProfileFormData {
  first_name: string;
  last_name: string;
  phone: string;
}

interface FormErrors {
  first_name?: string;
  last_name?: string;
  phone?: string;
}

export default function ProfileEdit() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [formData, setFormData] = useState<ProfileFormData>({
    first_name: '',
    last_name: '',
    phone: ''
  });
  const [errors, setErrors] = useState<FormErrors>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
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
        setFormData({
          first_name: data.first_name || '',
          last_name: data.last_name || '',
          phone: data.phone || ''
        });
      } else {
        setError('Failed to load profile');
      }
    } catch (error) {
      setError('An error occurred');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field: keyof ProfileFormData) => (
    e: React.ChangeEvent<HTMLInputElement>
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

  const validate = (): boolean => {
    const newErrors: FormErrors = {};

    // 電話番号のバリデーション（オプショナル）
    if (formData.phone && !/^\+?\d{10,15}$/.test(formData.phone.replace(/-/g, ''))) {
      newErrors.phone = 'Invalid phone number format';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) {
      return;
    }

    setSaving(true);
    setError('');

    try {
      const response = await fetch('/api/profile', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        // 成功時、表示ページへリダイレクト
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

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-lg">Loading profile...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md mx-auto">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-extrabold text-gray-900">Edit Profile</h1>
        </div>

        <form onSubmit={handleSubmit} className="bg-white shadow rounded-lg px-6 py-8">
          {error && (
            <div className="mb-4 p-3 bg-red-100 text-red-700 rounded">
              {error}
            </div>
          )}

          <div className="space-y-6">
            {/* Email (読み取り専用) */}
            <div>
              <label className="block text-sm font-medium text-gray-700">
                Email (cannot be changed)
              </label>
              <input
                type="email"
                value={profile?.email || ''}
                disabled
                className="mt-1 block w-full rounded-md bg-gray-100 border-gray-300 cursor-not-allowed"
              />
            </div>

            {/* First Name */}
            <div>
              <label htmlFor="first_name" className="block text-sm font-medium text-gray-700">
                First Name
              </label>
              <input
                id="first_name"
                type="text"
                value={formData.first_name}
                onChange={handleChange('first_name')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
              {errors.first_name && (
                <p className="mt-1 text-sm text-red-600">{errors.first_name}</p>
              )}
            </div>

            {/* Last Name */}
            <div>
              <label htmlFor="last_name" className="block text-sm font-medium text-gray-700">
                Last Name
              </label>
              <input
                id="last_name"
                type="text"
                value={formData.last_name}
                onChange={handleChange('last_name')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
              {errors.last_name && (
                <p className="mt-1 text-sm text-red-600">{errors.last_name}</p>
              )}
            </div>

            {/* Phone */}
            <div>
              <label htmlFor="phone" className="block text-sm font-medium text-gray-700">
                Phone
              </label>
              <input
                id="phone"
                type="tel"
                value={formData.phone}
                onChange={handleChange('phone')}
                placeholder="+81-90-1234-5678"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
              {errors.phone && (
                <p className="mt-1 text-sm text-red-600">{errors.phone}</p>
              )}
              <p className="mt-1 text-sm text-gray-500">
                Format: +81-90-1234-5678
              </p>
            </div>
          </div>

          <div className="mt-8 flex space-x-4">
            <button
              type="submit"
              disabled={saving}
              className="flex-1 py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
            >
              {saving ? 'Saving...' : 'Save Changes'}
            </button>

            <button
              type="button"
              onClick={() => router.push('/profile/view')}
              className="flex-1 py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
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

### API連携

**エンドポイント**: `PUT /api/profile`

**リクエスト**:
```http
PUT /api/profile HTTP/1.1
Cookie: access_token=...
Content-Type: application/json

{
  "first_name": "Jane",
  "last_name": "Smith",
  "phone": "+81-80-9876-5432"
}
```

**レスポンス**:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "first_name": "Jane",
  "last_name": "Smith",
  "phone": "+81-80-9876-5432",
  "created_at": "2025-01-15T10:00:00Z",
  "updated_at": "2025-09-30T16:00:00Z"
}
```

---

## データフロー

### プロファイル取得フロー

```
┌─────────────────────────────────────────────────────────┐
│ 1. User Browser                                         │
└─────────────────────────────────────────────────────────┘
              │
              ├─ GET /profile/view
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Next.js Page (pages/profile/view.tsx)               │
│    - useEffect でマウント時にデータフェッチ             │
└─────────────────────────────────────────────────────────┘
              │
              ├─ fetch('/api/profile')
              │  Cookie: access_token
              ▼
┌─────────────────────────────────────────────────────────┐
│ 3. BFF Layer (pages/api/profile/index.ts)              │
│    - Cookieからアクセストークンを取得                   │
│    - User API Serviceにプロキシ                         │
└─────────────────────────────────────────────────────────┘
              │
              ├─ GET http://user-api:8001/profile
              │  Authorization: Bearer {token}
              ▼
┌─────────────────────────────────────────────────────────┐
│ 4. User API Service                                     │
│    - JWTトークンを検証                                  │
│    - user_idを取得                                      │
│    - PostgreSQLからプロファイルデータ取得               │
│    - 存在しない場合は自動作成                           │
└─────────────────────────────────────────────────────────┘
              │
              ├─ Profile data
              ▼
┌─────────────────────────────────────────────────────────┐
│ 5. BFF Layer                                            │
│    - レスポンスをそのまま返却                           │
└─────────────────────────────────────────────────────────┘
              │
              ├─ Profile data (JSON)
              ▼
┌─────────────────────────────────────────────────────────┐
│ 6. Next.js Page                                         │
│    - setProfile(data)                                   │
│    - UIに表示                                           │
└─────────────────────────────────────────────────────────┘
```

### プロファイル更新フロー

```
User → フォーム入力
     → バリデーション (クライアント側)
     → PUT /api/profile (BFF)
     → User API Service
     → PostgreSQL更新
     → Redisキャッシュ削除
     → レスポンス
     → /profile/view へリダイレクト
```

---

## バリデーション

### クライアント側バリデーション

```typescript
const validate = (): boolean => {
  const newErrors: FormErrors = {};

  // First Name: 任意（バリデーションなし）
  // Last Name: 任意（バリデーションなし）

  // Phone: 任意だが、入力された場合は形式チェック
  if (formData.phone) {
    const phoneDigits = formData.phone.replace(/[^\d]/g, '');
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      newErrors.phone = 'Phone number must be 10-15 digits';
    }
  }

  setErrors(newErrors);
  return Object.keys(newErrors).length === 0;
};
```

### サーバー側バリデーション

User API Service側で以下をバリデーション:

1. **データ型チェック**
   - 各フィールドが適切な型かチェック

2. **文字列長チェック**
   - first_name, last_name: 最大100文字
   - phone: 最大20文字

3. **認証チェック**
   - JWTトークンの有効性
   - user_idの存在確認

---

## エラーハンドリング

### 認証エラー (401)

```typescript
if (response.status === 401) {
  // ログインページへリダイレクト
  router.push('/login');
  return;
}
```

### サーバーエラー (500)

```typescript
catch (error) {
  setError('An error occurred. Please try again later.');
}
```

### ネットワークエラー

```typescript
catch (error) {
  if (error instanceof TypeError && error.message === 'Failed to fetch') {
    setError('Network error. Please check your connection.');
  }
}
```

---

## テストシナリオ

### 正常系

1. **プロファイル表示**
   - ログイン済みユーザーがプロファイル表示ページにアクセス
   - プロファイルデータが正しく表示される

2. **プロファイル編集**
   - 編集ページでフィールドを変更
   - 保存ボタンをクリック
   - 表示ページに遷移し、変更が反映される

3. **初回プロファイル作成**
   - 新規登録直後のユーザーがプロファイルページにアクセス
   - 空のプロファイルが自動作成される
   - メールアドレスのみ表示される

### 異常系

1. **未認証アクセス**
   - ログインしていない状態でプロファイルページにアクセス
   - ログインページにリダイレクトされる

2. **バリデーションエラー**
   - 不正な電話番号形式で保存
   - エラーメッセージが表示される

3. **サーバーエラー**
   - User API Serviceが停止中
   - エラーメッセージが表示される

---

## 関連ドキュメント

- [User Frontend 概要](./01-overview.md)
- [画面設計](./02-screen-design.md)
- [API統合](./03-api-integration.md)
- [User API Service](/02-user-api/01-overview.md)