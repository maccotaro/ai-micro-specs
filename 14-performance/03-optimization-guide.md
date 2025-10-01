# 最適化ガイド

## バックエンド最適化

### 1. データベースクエリ

#### インデックスの追加

```sql
-- 頻繁に検索されるカラムにインデックス
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_profiles_user_id ON profiles(user_id);

-- 複合インデックス
CREATE INDEX idx_users_role_status ON users(role, status);
```

#### クエリ最適化

```python
# SELECT * を避ける
users = await db.fetch_all("SELECT id, username, email FROM users")

# LIMIT 使用
users = await db.fetch_all("SELECT * FROM users LIMIT 100")
```

### 2. キャッシング

#### Redis キャッシュ

```python
import redis.asyncio as redis

async def get_user_profile(user_id: str):
    # キャッシュから取得
    cached = await redis_client.get(f"profile:{user_id}")
    if cached:
        return json.loads(cached)

    # データベースから取得
    profile = await db.fetch_one("SELECT * FROM profiles WHERE user_id = $1", user_id)

    # キャッシュに保存 (TTL: 5分)
    await redis_client.setex(f"profile:{user_id}", 300, json.dumps(profile))

    return profile
```

### 3. 非同期処理

```python
from fastapi import BackgroundTasks

async def send_email(email: str):
    # 時間のかかる処理
    await email_service.send(email)

@router.post("/register")
async def register(user_data: UserCreate, bg_tasks: BackgroundTasks):
    user = await user_service.create(user_data)
    bg_tasks.add_task(send_email, user.email)
    return user
```

## フロントエンド最適化

### 1. コード分割

```typescript
import dynamic from 'next/dynamic';

const HeavyComponent = dynamic(() => import('@/components/HeavyComponent'), {
  loading: () => <p>Loading...</p>,
  ssr: false,
});
```

### 2. 画像最適化

```typescript
import Image from 'next/image';

<Image
  src="/profile.jpg"
  alt="Profile"
  width={200}
  height={200}
  priority={false}
/>
```

### 3. メモ化

```typescript
import { useMemo, useCallback } from 'react';

const sortedData = useMemo(() => {
  return data.sort((a, b) => a.name.localeCompare(b.name));
}, [data]);

const handleClick = useCallback((id: string) => {
  console.log('Clicked:', id);
}, []);
```

## インフラ最適化

### 1. CDN活用

- 静的ファイルをCDNに配置
- エッジキャッシング

### 2. HTTP/2使用

- 多重化通信
- ヘッダー圧縮

### 3. コンテナ最適化

```dockerfile
# マルチステージビルド
FROM node:20-alpine AS builder
WORKDIR /app
COPY . .
RUN npm run build

FROM node:20-alpine
COPY --from=builder /app/.next ./.next
CMD ["npm", "start"]
```

---

**関連**: [パフォーマンス概要](./01-performance-overview.md), [スケーラビリティ](./04-scalability.md)