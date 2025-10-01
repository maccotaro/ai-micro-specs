# Redis セッション管理

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [セッション管理の概要](#セッション管理の概要)
- [セッションデータ構造](#セッションデータ構造)
- [セッションライフサイクル](#セッションライフサイクル)
- [セッション検証](#セッション検証)
- [セッション更新（リフレッシュ）](#セッション更新リフレッシュ)
- [複数デバイス対応](#複数デバイス対応)
- [セッション管理API](#セッション管理api)
- [セキュリティ考慮事項](#セキュリティ考慮事項)

---

## セッション管理の概要

### セッションの役割

Redis セッション管理は、ユーザーの認証状態を維持するための仕組みです。JWT トークンと組み合わせることで、セキュアでスケーラブルな認証システムを実現します。

### セッション vs JWT

| 項目 | JWT のみ | JWT + Redis セッション |
|-----|---------|---------------------|
| ステートレス性 | ✅ 完全ステートレス | ⚠️ セミステートフル |
| ログアウト | ❌ 困難（ブラックリスト必要） | ✅ 簡単（セッション削除） |
| トークンリフレッシュ | ⚠️ 複雑 | ✅ シンプル |
| 複数デバイス管理 | ❌ 困難 | ✅ 容易 |
| セキュリティ | ⚠️ トークン盗難リスク | ✅ セッション無効化可能 |
| スケーラビリティ | ✅ 高 | ⚠️ Redis に依存 |

### ai-micro-service でのアプローチ

JWT と Redis セッションを組み合わせたハイブリッド方式を採用：

- **JWT**: API リクエストの認証（ステートレス）
- **Redis セッション**: ログイン状態の管理（ステートフル）

---

## セッションデータ構造

### キーパターン

```
session:<user_id>:<session_id>
```

**例**:
```
session:550e8400-e29b-41d4-a716-446655440000:sess-7f3d9a1b
```

### データスキーマ

**データ型**: String (JSON)

**完全なスキーマ**:
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "session_id": "sess-7f3d9a1b",
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "created_at": "2025-09-30T10:00:00Z",
  "expires_at": "2025-09-30T11:00:00Z",
  "last_activity": "2025-09-30T10:15:30Z",
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  "device_info": {
    "device_type": "desktop",
    "os": "Windows",
    "browser": "Chrome"
  },
  "metadata": {
    "login_method": "password",
    "remember_me": false
  }
}
```

### フィールド説明

| フィールド | 型 | 必須 | 説明 |
|----------|---|------|------|
| user_id | UUID | ✅ | ユーザーID |
| session_id | String | ✅ | セッションID（一意識別子） |
| access_token | String | ✅ | JWT アクセストークン |
| refresh_token | String | ✅ | JWT リフレッシュトークン |
| created_at | ISO8601 | ✅ | セッション作成日時 |
| expires_at | ISO8601 | ✅ | セッション有効期限 |
| last_activity | ISO8601 | ❌ | 最終アクティビティ日時 |
| ip_address | String | ❌ | クライアントIPアドレス |
| user_agent | String | ❌ | ユーザーエージェント文字列 |
| device_info | Object | ❌ | デバイス情報 |
| metadata | Object | ❌ | その他のメタデータ |

---

## セッションライフサイクル

### 1. セッション作成（ログイン時）

```python
# app/services/session_manager.py

import uuid
from datetime import datetime, timedelta
import json

class SessionManager:
    def __init__(self, redis_client: Redis):
        self.redis = redis_client

    def create_session(
        self,
        user_id: str,
        access_token: str,
        refresh_token: str,
        ip_address: str,
        user_agent: str,
        ttl: int = 3600
    ) -> str:
        """
        新しいセッションを作成

        Args:
            user_id: ユーザーID
            access_token: JWT アクセストークン
            refresh_token: JWT リフレッシュトークン
            ip_address: クライアントIPアドレス
            user_agent: ユーザーエージェント
            ttl: セッションTTL（秒）

        Returns:
            str: セッションID
        """

        # セッションID生成
        session_id = f"sess-{uuid.uuid4().hex[:8]}"

        # セッションデータ作成
        now = datetime.utcnow()
        session_data = {
            "user_id": user_id,
            "session_id": session_id,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "created_at": now.isoformat(),
            "expires_at": (now + timedelta(seconds=ttl)).isoformat(),
            "last_activity": now.isoformat(),
            "ip_address": ip_address,
            "user_agent": user_agent,
            "device_info": self._parse_user_agent(user_agent),
            "metadata": {
                "login_method": "password",
                "remember_me": False
            }
        }

        # Redis に保存
        session_key = f"session:{user_id}:{session_id}"
        self.redis.setex(
            session_key,
            ttl,
            json.dumps(session_data, ensure_ascii=False)
        )

        logger.info(f"Session created: {session_id} for user: {user_id}")

        return session_id

    def _parse_user_agent(self, user_agent: str) -> dict:
        """
        User-Agent 文字列をパースしてデバイス情報を抽出
        """

        # 簡易的な実装（本番環境では user-agents ライブラリを使用）
        device_info = {
            "device_type": "unknown",
            "os": "unknown",
            "browser": "unknown"
        }

        if "Mobile" in user_agent or "Android" in user_agent:
            device_info["device_type"] = "mobile"
        elif "Tablet" in user_agent or "iPad" in user_agent:
            device_info["device_type"] = "tablet"
        else:
            device_info["device_type"] = "desktop"

        if "Windows" in user_agent:
            device_info["os"] = "Windows"
        elif "Mac" in user_agent:
            device_info["os"] = "macOS"
        elif "Linux" in user_agent:
            device_info["os"] = "Linux"
        elif "Android" in user_agent:
            device_info["os"] = "Android"
        elif "iOS" in user_agent or "iPhone" in user_agent:
            device_info["os"] = "iOS"

        if "Chrome" in user_agent:
            device_info["browser"] = "Chrome"
        elif "Firefox" in user_agent:
            device_info["browser"] = "Firefox"
        elif "Safari" in user_agent:
            device_info["browser"] = "Safari"
        elif "Edge" in user_agent:
            device_info["browser"] = "Edge"

        return device_info
```

### 2. セッション取得

```python
class SessionManager:
    def get_session(self, user_id: str, session_id: str) -> dict:
        """
        セッションデータを取得

        Returns:
            dict: セッションデータ、存在しない場合は None
        """

        session_key = f"session:{user_id}:{session_id}"
        session_data = self.redis.get(session_key)

        if not session_data:
            return None

        return json.loads(session_data)

    def get_all_user_sessions(self, user_id: str) -> list:
        """
        ユーザーのすべてのセッションを取得
        """

        sessions = []
        session_pattern = f"session:{user_id}:*"

        cursor = 0
        while True:
            cursor, keys = self.redis.scan(
                cursor,
                match=session_pattern,
                count=100
            )

            for key in keys:
                session_data = self.redis.get(key)
                if session_data:
                    session = json.loads(session_data)
                    # TTL も追加
                    session["ttl"] = self.redis.ttl(key)
                    sessions.append(session)

            if cursor == 0:
                break

        return sessions
```

### 3. セッション更新（アクティビティ記録）

```python
class SessionManager:
    def update_last_activity(self, user_id: str, session_id: str):
        """
        最終アクティビティ時刻を更新
        """

        session_key = f"session:{user_id}:{session_id}"
        session_data = self.redis.get(session_key)

        if not session_data:
            return False

        session = json.loads(session_data)
        session["last_activity"] = datetime.utcnow().isoformat()

        # TTL を維持したまま更新
        ttl = self.redis.ttl(session_key)
        if ttl > 0:
            self.redis.setex(
                session_key,
                ttl,
                json.dumps(session, ensure_ascii=False)
            )

        return True
```

### 4. セッション削除（ログアウト時）

```python
class SessionManager:
    def delete_session(self, user_id: str, session_id: str) -> bool:
        """
        特定のセッションを削除
        """

        session_key = f"session:{user_id}:{session_id}"
        result = self.redis.delete(session_key)

        if result > 0:
            logger.info(f"Session deleted: {session_id} for user: {user_id}")
            return True

        return False

    def delete_all_user_sessions(self, user_id: str) -> int:
        """
        ユーザーのすべてのセッションを削除（全デバイスからログアウト）
        """

        session_pattern = f"session:{user_id}:*"
        deleted_count = 0

        cursor = 0
        while True:
            cursor, keys = self.redis.scan(
                cursor,
                match=session_pattern,
                count=100
            )

            if keys:
                deleted_count += self.redis.delete(*keys)

            if cursor == 0:
                break

        logger.info(f"Deleted {deleted_count} sessions for user: {user_id}")
        return deleted_count
```

---

## セッション検証

### ミドルウェアでの検証

```python
# app/middleware/session_middleware.py

from fastapi import Request, HTTPException, status

async def validate_session_middleware(request: Request, call_next):
    """
    セッション検証ミドルウェア
    """

    # Authorization ヘッダーからトークン取得
    auth_header = request.headers.get("authorization")

    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]

        try:
            # JWT をデコード
            payload = jwt.decode(token, public_key, algorithms=["RS256"])
            user_id = payload.get("sub")
            session_id = payload.get("sid")  # カスタムクレーム

            if session_id:
                # Redis でセッション検証
                session_manager = SessionManager(redis_client)
                session = session_manager.get_session(user_id, session_id)

                if not session:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Session not found or expired"
                    )

                # 最終アクティビティを更新
                session_manager.update_last_activity(user_id, session_id)

                # リクエストにセッション情報を追加
                request.state.session = session

        except jwt.JWTError:
            pass  # JWT エラーは別の認証ミドルウェアで処理

    response = await call_next(request)
    return response
```

---

## セッション更新（リフレッシュ）

### トークンリフレッシュ時のセッション更新

```python
# app/routers/auth.py

@router.post("/refresh")
async def refresh_token(
    request: RefreshTokenRequest,
    session_manager: SessionManager = Depends(get_session_manager)
):
    """
    アクセストークンのリフレッシュとセッション更新
    """

    # 1. リフレッシュトークンを検証
    try:
        payload = jwt.decode(
            request.refresh_token,
            public_key,
            algorithms=["RS256"]
        )
        user_id = payload.get("sub")
        session_id = payload.get("sid")
    except jwt.JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    # 2. セッション取得
    session = session_manager.get_session(user_id, session_id)

    if not session:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session not found"
        )

    # 3. 新しいアクセストークンを生成
    new_access_token = create_access_token(user_id, session_id)

    # 4. セッションを更新
    session["access_token"] = new_access_token
    session["last_activity"] = datetime.utcnow().isoformat()

    session_key = f"session:{user_id}:{session_id}"
    ttl = session_manager.redis.ttl(session_key)

    if ttl > 0:
        session_manager.redis.setex(
            session_key,
            ttl,
            json.dumps(session, ensure_ascii=False)
        )

    return {
        "access_token": new_access_token,
        "token_type": "bearer",
        "expires_in": 900
    }
```

---

## 複数デバイス対応

### デバイス一覧の取得

```python
# app/routers/sessions.py

@router.get("/sessions")
async def get_user_sessions(
    session_manager: SessionManager = Depends(get_session_manager),
    current_user: User = Depends(get_current_user)
):
    """
    ユーザーのアクティブなセッション一覧を取得
    """

    sessions = session_manager.get_all_user_sessions(str(current_user.id))

    # セッション情報を整形
    formatted_sessions = []

    for session in sessions:
        formatted_sessions.append({
            "session_id": session["session_id"],
            "created_at": session["created_at"],
            "last_activity": session.get("last_activity"),
            "expires_at": session["expires_at"],
            "device_info": session.get("device_info", {}),
            "ip_address": session.get("ip_address"),
            "is_current": session["session_id"] == request.state.session.get("session_id")
        })

    return {
        "sessions": formatted_sessions,
        "count": len(formatted_sessions)
    }
```

### 特定デバイスのログアウト

```python
@router.delete("/sessions/{session_id}")
async def logout_device(
    session_id: str,
    session_manager: SessionManager = Depends(get_session_manager),
    current_user: User = Depends(get_current_user)
):
    """
    特定のセッション（デバイス）からログアウト
    """

    # セッションが存在し、ユーザーのものであることを確認
    session = session_manager.get_session(str(current_user.id), session_id)

    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found"
        )

    # セッション削除
    success = session_manager.delete_session(str(current_user.id), session_id)

    if success:
        # トークンもブラックリストに追加
        # ...

        return {"message": "Session terminated successfully"}

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to terminate session"
    )
```

### すべてのデバイスからログアウト

```python
@router.delete("/sessions")
async def logout_all_devices(
    session_manager: SessionManager = Depends(get_session_manager),
    current_user: User = Depends(get_current_user)
):
    """
    すべてのデバイスからログアウト
    """

    deleted_count = session_manager.delete_all_user_sessions(str(current_user.id))

    return {
        "message": f"Logged out from {deleted_count} device(s)",
        "count": deleted_count
    }
```

---

## セッション管理API

### セッション統計の取得

```python
@router.get("/admin/sessions/stats")
async def get_session_statistics(
    session_manager: SessionManager = Depends(get_session_manager),
    current_user: User = Depends(require_admin)
):
    """
    全セッションの統計情報を取得（管理者のみ）
    """

    # すべてのセッションキーを取得
    all_sessions = []
    cursor = 0

    while True:
        cursor, keys = session_manager.redis.scan(
            cursor,
            match="session:*",
            count=1000
        )

        for key in keys:
            session_data = session_manager.redis.get(key)
            if session_data:
                all_sessions.append(json.loads(session_data))

        if cursor == 0:
            break

    # 統計計算
    total_sessions = len(all_sessions)
    active_users = len(set(s["user_id"] for s in all_sessions))

    device_types = {}
    for session in all_sessions:
        device_type = session.get("device_info", {}).get("device_type", "unknown")
        device_types[device_type] = device_types.get(device_type, 0) + 1

    return {
        "total_sessions": total_sessions,
        "active_users": active_users,
        "device_types": device_types,
        "avg_sessions_per_user": round(total_sessions / active_users, 2) if active_users > 0 else 0
    }
```

---

## セキュリティ考慮事項

### 1. セッションハイジャック対策

```python
# IP アドレスとユーザーエージェントの検証

def validate_session_fingerprint(
    session: dict,
    current_ip: str,
    current_user_agent: str
) -> bool:
    """
    セッションのフィンガープリント検証
    """

    # IP アドレスチェック（厳格）
    if session.get("ip_address") != current_ip:
        logger.warning(
            f"IP address mismatch for session: {session['session_id']}, "
            f"expected: {session.get('ip_address')}, got: {current_ip}"
        )
        return False

    # User-Agent チェック（緩やか）
    if session.get("user_agent") != current_user_agent:
        logger.info(
            f"User-Agent changed for session: {session['session_id']}"
        )
        # User-Agent は変わることがあるので警告のみ

    return True
```

### 2. セッションタイムアウト

```python
# 非アクティブセッションの自動削除

async def cleanup_inactive_sessions(
    session_manager: SessionManager,
    inactive_threshold: int = 1800  # 30分
):
    """
    非アクティブなセッションを削除
    """

    cursor = 0
    deleted_count = 0

    while True:
        cursor, keys = session_manager.redis.scan(
            cursor,
            match="session:*",
            count=100
        )

        for key in keys:
            session_data = session_manager.redis.get(key)
            if session_data:
                session = json.loads(session_data)

                last_activity = datetime.fromisoformat(session["last_activity"])
                inactive_seconds = (datetime.utcnow() - last_activity).total_seconds()

                if inactive_seconds > inactive_threshold:
                    session_manager.redis.delete(key)
                    deleted_count += 1
                    logger.info(f"Deleted inactive session: {session['session_id']}")

        if cursor == 0:
            break

    return deleted_count
```

### 3. 同時セッション数の制限

```python
# ユーザーあたりの最大セッション数を制限

def enforce_max_sessions(
    user_id: str,
    max_sessions: int = 5,
    session_manager: SessionManager
):
    """
    ユーザーの同時セッション数を制限
    """

    sessions = session_manager.get_all_user_sessions(user_id)

    if len(sessions) >= max_sessions:
        # 最も古いセッションを削除
        sessions.sort(key=lambda s: s["created_at"])

        oldest_session = sessions[0]
        session_manager.delete_session(user_id, oldest_session["session_id"])

        logger.info(
            f"Deleted oldest session for user {user_id} "
            f"due to max session limit ({max_sessions})"
        )
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [Auth Service の Redis 使用法](./03-auth-service-usage.md)
- [データ構造概要](./02-data-structure-overview.md)
- [セキュリティ](/10-security/02-authentication.md)

---

**次のステップ**: [永続化設定](./08-persistence.md) を参照して、Redis のデータ永続化戦略を確認してください。