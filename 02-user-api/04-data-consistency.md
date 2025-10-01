# User API Service - データ整合性

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次

- [整合性概要](#整合性概要)
- [サービス間データ整合性](#サービス間データ整合性)
- [キャッシュ整合性](#キャッシュ整合性)
- [トランザクション管理](#トランザクション管理)
- [整合性の課題と対策](#整合性の課題と対策)
- [監視とトラブルシューティング](#監視とトラブルシューティング)

---

## 整合性概要

User API Service では、以下の3つのデータストア間で整合性を保証する必要があります。

### データストアの関係

```
┌─────────────────┐       ┌─────────────────┐
│  Auth Service   │       │   User API      │
│   (authdb)      │       │   (apidb)       │
│                 │       │                 │
│  users          │◄─────┤  profiles       │
│  - id (UUID)    │ 論理  │  - user_id      │
│  - email        │ 連携  │  - first_name   │
│  - password     │       │  - last_name    │
└─────────────────┘       └────────┬────────┘
                                   │
                          ┌────────▼────────┐
                          │  Redis Cache    │
                          │                 │
                          │  cache:profile: │
                          │  {user_id}      │
                          └─────────────────┘
```

### 整合性レベル

| データストア間 | 整合性モデル | 説明 |
|------------|------------|------|
| authdb ↔ apidb | **結果整合性** (Eventual Consistency) | Auth Service 更新後、User API が連携 |
| apidb ↔ Redis | **強整合性** (Strong Consistency) | 更新時にキャッシュ削除で即座に反映 |
| Redis ↔ Client | **キャッシュ整合性** (Cache Consistency) | TTL満了またはデータ更新時に同期 |

---

## サービス間データ整合性

### Auth Service との連携

#### 連携データフロー

```
1. ユーザー登録（Auth Service）
   POST /auth/register
   → authdb.users に新規ユーザー作成
   → user_id (UUID) が割り当てられる

2. 初回プロファイルアクセス（User API）
   GET /profile （JWT トークン付き）
   → JWT から user_id 抽出
   → apidb.profiles を検索（存在しない）
   → 空プロファイル自動作成（user_id 紐付け）
   → Auth Service から email 取得
   → プロファイル返却

3. プロファイル更新（User API）
   POST /profile
   → apidb.profiles 更新
   → Redis キャッシュ削除
```

#### user_id による疎結合設計

**設計方針**:
- `profiles.user_id` は `authdb.users.id` と論理的に対応
- 物理的な外部キー制約は設定しない（データベース分離）

**メリット**:
- Auth Service と User API が独立してデプロイ・スケール可能
- Auth Service 障害時も User API は既存データに対して動作可能

**整合性保証メカニズム**:
1. **JWT 検証**: ユーザーが存在することを Auth Service が保証
2. **自動作成**: プロファイル未存在時に空プロファイル作成（孤立レコード防止）
3. **Auth Service 連携**: `/auth/me` でメール情報取得（リアルタイム同期）

---

### メール情報の同期

#### メール取得フロー

```python
# app/routers/profile.py
async def get_user_email_from_auth_service(token: str) -> str:
    """認証サービスからユーザーのemail情報を取得"""
    try:
        auth_service_url = "http://host.docker.internal:8002/auth/me"
        headers = {"Authorization": f"Bearer {token}"}

        response = requests.get(auth_service_url, headers=headers, timeout=10)
        response.raise_for_status()

        user_info = response.json()
        email = user_info.get("email", "")
        logger.info(f"Retrieved email from auth service: {email}")
        return email

    except Exception as e:
        logger.error(f"Failed to get user email from auth service: {e}")
        return ""
```

#### メール情報の扱い

| 項目 | 説明 |
|------|------|
| **保存場所** | `authdb.users.email` （Auth Service が管理） |
| **User API での扱い** | リアルタイム取得（キャッシュしない） |
| **取得タイミング** | プロファイル取得・更新時 |
| **エラー時の動作** | 空文字列 `""` を返す（エラー非伝播） |
| **タイムアウト** | 10秒 |

**設計理由**:
- メール情報は Auth Service のマスターデータ
- User API はメールを保存せず、必要時に取得（Single Source of Truth）
- メール変更時の同期処理不要

---

## キャッシュ整合性

### Redis キャッシュ戦略

#### キャッシュキー形式

```
cache:profile:{user_id}
```

**例**:
```
cache:profile:7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d
```

#### キャッシュデータ構造

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "7f3a1c9d-5b2e-4a6f-8d1e-9c7b4a5f3e2d",
  "email": "user@example.com",
  "first_name": "太郎",
  "last_name": "山田",
  "name": "山田 太郎",
  "address": "東京都渋谷区1-2-3",
  "phone": "090-1234-5678",
  "created_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T15:30:00Z"
}
```

---

### キャッシュ更新パターン

#### パターン1: Cache-Aside（読み取り時）

```python
@router.get("/profile", response_model=ProfileResponse)
async def get_profile(
    current_user: Dict[str, Any] = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = current_user["user_id"]
    cache_key = f"cache:profile:{user_id}"

    # 1. キャッシュ確認
    cached_profile = await cache_manager.get(cache_key)
    if cached_profile:
        logger.info(f"Profile cache hit for user_id: {user_id}")
        return ProfileResponse(**cached_profile)

    # 2. データベースから取得
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    if not profile:
        # 3. 存在しない場合は自動作成
        profile = Profile(user_id=UUID(user_id), ...)
        db.add(profile)
        db.commit()

    # 4. キャッシュに保存
    await cache_manager.set(cache_key, profile_data, settings.profile_cache_ttl_sec)

    return ProfileResponse(...)
```

**フロー**:
1. キャッシュ確認 → ヒットすれば返却（~50ms）
2. キャッシュミス → データベース取得（~200ms）
3. キャッシュに保存（TTL: 300秒）

---

#### パターン2: Write-Through（更新時）

```python
@router.put("/profile", response_model=ProfileResponse)
async def update_profile(
    profile_data: ProfileUpdate,
    current_user: Dict[str, Any] = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = UUID(current_user["user_id"])
    cache_key = f"cache:profile:{user_id}"

    # 1. データベース更新
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    for field, value in profile_data.dict(exclude_unset=True).items():
        setattr(profile, field, value)
    db.commit()
    db.refresh(profile)

    # 2. キャッシュ削除（次回アクセス時に再構築）
    await cache_manager.delete(cache_key)
    logger.info(f"Profile cache cleared for user_id: {user_id}")

    return ProfileResponse(...)
```

**フロー**:
1. データベース更新
2. キャッシュ削除（古いデータ削除）
3. 次回 GET 時にキャッシュ再構築

**設計理由**:
- 更新直後は再取得されるケースが多い
- 更新時にキャッシュ再構築すると無駄が多い
- キャッシュ削除のみで次回アクセス時に再構築（Lazy Loading）

---

### キャッシュ整合性の保証

#### TTL（Time To Live）設定

```python
# app/core/config.py
profile_cache_ttl_sec: int = 300  # 5分
```

**動作**:
- キャッシュは最大5分間保持
- 5分経過後、自動的に期限切れ
- 次回アクセス時にデータベースから再取得

**トレードオフ**:
- TTL短縮 → 整合性向上、パフォーマンス低下
- TTL延長 → パフォーマンス向上、整合性低下

**推奨設定**:
- 開発環境: 60秒（短めでデバッグしやすい）
- 本番環境: 300秒（パフォーマンス優先）

---

#### キャッシュスタンピード対策

**問題**: キャッシュ期限切れ時に大量リクエストが同時にDBアクセス

**現状**: 未実装（影響は限定的）

**理由**:
- プロファイルは特定ユーザーのみアクセス
- 同一ユーザーからの同時リクエストは稀
- データベースクエリが軽量（user_id インデックス使用）

**将来的な対策**:
```python
import asyncio

# ダブルチェックロッキング
cached = await cache_manager.get(cache_key)
if cached:
    return cached

async with redis_lock(f"lock:{cache_key}", timeout=5):
    # ロック取得後に再度キャッシュ確認
    cached = await cache_manager.get(cache_key)
    if cached:
        return cached

    # データベース取得とキャッシュ保存
    profile = db.query(Profile).filter(...).first()
    await cache_manager.set(cache_key, profile_data, ttl)
    return profile
```

---

## トランザクション管理

### データベーストランザクション

#### 単一レコード更新

```python
@router.put("/profile")
async def update_profile(...):
    # SQLAlchemy セッションは自動的にトランザクション管理
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()

    # 更新処理
    profile.phone = "090-9999-9999"

    # コミット（成功時）
    db.commit()
    db.refresh(profile)

    # ロールバック（エラー時は自動的に実行）
    # db.rollback()
```

**トランザクション境界**:
- `db.query()` 〜 `db.commit()` までが1トランザクション
- エラー発生時は自動ロールバック（SQLAlchemy セッション管理）

---

#### 複数操作のアトミック性

現時点ではプロファイル更新は単一レコード操作のみですが、将来的に複数テーブル更新が必要な場合:

```python
from sqlalchemy.orm import Session

@router.post("/profile/with-history")
async def update_profile_with_history(
    profile_data: ProfileUpdate,
    db: Session = Depends(get_db)
):
    try:
        # 1. プロファイル更新
        profile = db.query(Profile).filter(...).first()
        profile.phone = profile_data.phone

        # 2. 変更履歴記録（仮想的な例）
        history = ProfileHistory(
            user_id=profile.user_id,
            old_phone=profile.phone,
            new_phone=profile_data.phone
        )
        db.add(history)

        # 3. アトミックコミット
        db.commit()

    except Exception as e:
        db.rollback()
        logger.error(f"Transaction failed: {e}")
        raise HTTPException(status_code=500, detail="Update failed")
```

---

## 整合性の課題と対策

### 課題1: Auth Service 障害時のメール情報取得

**問題**:
- Auth Service ダウン時、`/auth/me` が失敗
- メール情報が空文字列になる

**現状の対策**:
```python
try:
    email = await get_user_email_from_auth_service(token)
except Exception:
    email = ""  # エラー時は空文字列
```

**改善案**:
```python
# メールをキャッシュして Auth Service 障害時も返却
cache_key_email = f"cache:email:{user_id}"
cached_email = await cache_manager.get(cache_key_email)
if cached_email:
    return cached_email

email = await get_user_email_from_auth_service(token)
if email:
    await cache_manager.set(cache_key_email, email, ttl=3600)  # 1時間
return email
```

---

### 課題2: キャッシュとDBの不整合

**問題**:
- データベース直接更新時、キャッシュが古いまま残る
- 管理者が SQL で直接更新した場合など

**対策1: 管理用エンドポイント**
```python
@router.delete("/admin/cache/{user_id}")
async def clear_user_cache(user_id: UUID):
    """管理者用: 特定ユーザーのキャッシュクリア"""
    cache_key = f"cache:profile:{user_id}"
    await cache_manager.delete(cache_key)
    return {"message": "Cache cleared"}
```

**対策2: TTL による自動期限切れ**
- 最大5分で古いキャッシュは自動削除
- 致命的な不整合は発生しない

---

### 課題3: ユーザー削除時の孤立プロファイル

**問題**:
- Auth Service でユーザー削除
- User API のプロファイルが残る（孤立レコード）

**現状**:
- 外部キー制約なし → 孤立レコード発生可能

**対策案**:
```python
# Auth Service 側でユーザー削除イベント発行
# User API 側でイベント受信してプロファイル削除

@router.delete("/profile/cascade/{user_id}")
async def delete_profile_cascade(user_id: UUID, db: Session = Depends(get_db)):
    """Auth Service から呼ばれるプロファイル削除エンドポイント"""
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    if profile:
        db.delete(profile)
        db.commit()
        await cache_manager.delete(f"cache:profile:{user_id}")
    return {"message": "Profile deleted"}
```

---

## 監視とトラブルシューティング

### 整合性チェックスクリプト

```python
# scripts/check_data_consistency.py
import requests

def check_orphaned_profiles():
    """孤立プロファイルのチェック"""
    # User API から全プロファイル取得
    profiles = db.query(Profile).all()

    orphaned = []
    for profile in profiles:
        # Auth Service にユーザー存在確認
        response = requests.get(
            f"http://host.docker.internal:8002/auth/user/{profile.user_id}",
            headers={"Authorization": f"Bearer {admin_token}"}
        )
        if response.status_code == 404:
            orphaned.append(profile.user_id)

    return orphaned

# 定期実行（cron）
# 0 3 * * * python scripts/check_data_consistency.py
```

---

### ログによる整合性監視

```python
# app/routers/profile.py

# キャッシュヒット率
logger.info(f"Profile cache hit for user_id: {user_id}")  # キャッシュヒット
logger.info(f"Profile cached for user_id: {user_id}")     # キャッシュミス

# Auth Service 連携エラー
logger.error(f"Failed to get user email from auth service: {e}")

# データベース更新
logger.info(f"Profile cache cleared for user_id: {user_id}")
```

**監視項目**:
- キャッシュヒット率（目標: 80%以上）
- Auth Service 連携エラー率（目標: < 1%）
- データベースクエリ時間（目標: < 200ms）

---

### トラブルシューティング

#### 症状1: プロファイルが更新されない

**確認手順**:
```bash
# 1. データベース確認
docker exec postgres psql -U postgres -d apidb \
  -c "SELECT * FROM profiles WHERE user_id = 'uuid-here';"

# 2. キャッシュ確認
docker exec redis redis-cli -a password GET "cache:profile:uuid-here"

# 3. キャッシュ削除
docker exec redis redis-cli -a password DEL "cache:profile:uuid-here"
```

#### 症状2: メール情報が空

**確認手順**:
```bash
# Auth Service 接続確認
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8002/auth/me

# User API ログ確認
docker compose logs -f ai-micro-api-user | grep "Failed to get user email"
```

---

## 関連ドキュメント

- [サービス概要](./01-overview.md)
- [API仕様書](./02-api-specification.md)
- [データベース設計](./03-database-design.md)
- [認証フロー統合](/08-integration/02-authentication-flow.md)
- [データ整合性設計](/08-integration/05-data-consistency.md)