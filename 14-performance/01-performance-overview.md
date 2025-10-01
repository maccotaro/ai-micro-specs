# パフォーマンス全体方針

## パフォーマンス目標

| メトリクス | 目標値 |
|-----------|--------|
| APIレスポンスタイム (p95) | < 200ms |
| DBクエリ時間 (p95) | < 50ms |
| ページロード時間 (p75) | < 2s |
| エラー率 | < 0.1% |
| CPU使用率 | < 70% |
| メモリ使用率 | < 80% |

## 最適化の優先順位

1. **Critical Path**: ユーザー体験に直接影響
   - ログイン処理
   - ダッシュボード表示
   - ドキュメントアップロード

2. **High Priority**: 頻繁に使用される機能
   - API呼び出し
   - データベースクエリ
   - キャッシュヒット率

3. **Medium Priority**: バックグラウンド処理
   - バッチ処理
   - レポート生成

## ボトルネック特定

### 1. N+1 クエリ問題

```python
# ❌ BAD: N+1 クエリ
users = await db.fetch_all("SELECT * FROM users")
for user in users:
    profile = await db.fetch_one("SELECT * FROM profiles WHERE user_id = $1", user.id)

# ✅ GOOD: JOIN使用
results = await db.fetch_all("""
    SELECT u.*, p.*
    FROM users u
    LEFT JOIN profiles p ON u.id = p.user_id
""")
```

### 2. キャッシュ活用

```python
from functools import lru_cache

@lru_cache(maxsize=100)
async def get_config():
    return await db.fetch_one("SELECT * FROM config")
```

### 3. 非同期処理

```python
from fastapi import BackgroundTasks

@router.post("/register")
async def register(user_data: UserCreate, bg_tasks: BackgroundTasks):
    user = await user_service.create(user_data)
    bg_tasks.add_task(send_welcome_email, user.email)
    return user
```

---

**関連**: [負荷テスト](./02-load-testing.md), [最適化ガイド](./03-optimization-guide.md)