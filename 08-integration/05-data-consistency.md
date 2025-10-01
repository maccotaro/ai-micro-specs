# データ整合性

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [データ分離戦略](#データ分離戦略)
- [整合性保証パターン](#整合性保証パターン)
- [イベントソーシング](#イベントソーシング)
- [実装例](#実装例)

---

## 概要

マイクロサービスアーキテクチャでは、各サービスが独自のデータベースを持つため、データ整合性の維持が課題となります。本システムでは以下の戦略を採用しています。

### データベース分離

```
authdb (PostgreSQL)
├── users            # 認証情報

apidb (PostgreSQL)
├── profiles         # ユーザープロフィール（user_id FK）

admindb (PostgreSQL)
├── documents        # ドキュメント情報
└── ocr_results      # OCR処理結果

Redis
├── sessions         # セッション情報
├── cache            # キャッシュデータ
└── blacklist        # トークンブラックリスト
```

---

## データ分離戦略

### 1. 外部キー参照

```python
# apidb.profiles
class Profile(Base):
    __tablename__ = "profiles"

    id = Column(UUID, primary_key=True)
    user_id = Column(UUID, nullable=False)  # authdb.usersへの論理FK
    first_name = Column(String)
    last_name = Column(String)
```

**注意**: 物理的な外部キー制約は設定せず、アプリケーションレベルで整合性を保証

### 2. 結果整合性（Eventual Consistency）

```python
# ユーザー作成時
async def create_user(user_data: UserCreate):
    # 1. authdbにユーザー作成
    user = await create_user_in_authdb(user_data)

    # 2. apidbにプロフィール作成（非同期）
    await publish_event("user.created", {"user_id": user.id})

    return user
```

---

## 整合性保証パターン

### Sagaパターン

```python
# ユーザー削除Saga
class DeleteUserSaga:
    async def execute(self, user_id: str):
        try:
            # ステップ1: プロフィール削除
            await self.delete_profile(user_id)

            # ステップ2: ドキュメント削除
            await self.delete_documents(user_id)

            # ステップ3: ユーザー削除
            await self.delete_user(user_id)

        except Exception as e:
            # 補償トランザクション実行
            await self.compensate(user_id)
            raise

    async def compensate(self, user_id: str):
        """ロールバック処理"""
        # 必要に応じてデータ復元
        pass
```

---

## イベントソーシング

### イベント発行

```python
import redis.asyncio as redis

async def publish_user_event(event_type: str, data: dict):
    """ユーザーイベント発行"""
    r = redis.from_url("redis://localhost:6379")
    await r.publish(
        f"user.{event_type}",
        json.dumps({
            "timestamp": datetime.utcnow().isoformat(),
            "data": data
        })
    )
```

---

## 実装例

### ユーザー作成フロー

```python
@router.post("/register")
async def register_user(user_data: UserCreate):
    # 1. authdbにユーザー作成
    user = User(
        id=uuid.uuid4(),
        email=user_data.email,
        hashed_password=hash_password(user_data.password)
    )
    await authdb.save(user)

    # 2. イベント発行
    await publish_user_event("created", {
        "user_id": str(user.id),
        "email": user.email
    })

    return {"user_id": str(user.id)}

# User APIでイベント購読
async def handle_user_created(data: dict):
    """ユーザー作成イベントハンドラ"""
    profile = Profile(
        id=uuid.uuid4(),
        user_id=data["user_id"],
        email=data["email"]
    )
    await apidb.save(profile)
```

---

## 関連ドキュメント

- [データベース設計](../06-database/01-overview.md)
- [サービス間通信](./01-service-communication.md)