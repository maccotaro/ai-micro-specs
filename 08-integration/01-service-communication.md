# サービス間通信

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [通信パターン](#通信パターン)
- [通信プロトコル](#通信プロトコル)
- [サービスディスカバリ](#サービスディスカバリ)
- [エラーハンドリング](#エラーハンドリング)
- [タイムアウト設定](#タイムアウト設定)
- [実装例](#実装例)

---

## 概要

本システムは、7つのマイクロサービスが協調動作する分散システムです。各サービス間の通信は、主にHTTP/RESTとRedis経由のデータ共有によって実現されています。

### 通信トポロジー

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend Layer (BFF)                     │
│  ┌─────────────────────┐      ┌─────────────────────┐      │
│  │ User Frontend       │      │ Admin Frontend      │      │
│  │ (Port: 3002)        │      │ (Port: 3003)        │      │
│  └──────────┬──────────┘      └──────────┬──────────┘      │
└─────────────┼─────────────────────────────┼─────────────────┘
              │                             │
              │ HTTP/REST                   │ HTTP/REST
              │                             │
┌─────────────┼─────────────────────────────┼─────────────────┐
│             │     Backend Layer           │                 │
│             │                             │                 │
│  ┌──────────▼──────────┐     ┌──────────▼──────────┐      │
│  │ Auth Service        │     │ User API            │      │
│  │ (Port: 8002)        │◄────┤ (Port: 8001)        │      │
│  └─────────────────────┘     └─────────────────────┘      │
│             │ JWKS                    │                     │
│             │                         │                     │
│  ┌──────────▼─────────────────────────▼──────────┐        │
│  │ Admin API                                      │        │
│  │ (Port: 8003)                                   │        │
│  └────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
              │                             │
              ▼                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                     │
│  ┌─────────────────────┐      ┌─────────────────────┐      │
│  │ PostgreSQL          │      │ Redis               │      │
│  │ - authdb            │      │ - Sessions          │      │
│  │ - apidb             │      │ - Cache             │      │
│  │ - admindb           │      │ - Blacklist         │      │
│  └─────────────────────┘      └─────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 通信パターン

### 1. 同期通信（HTTP/REST）

最も一般的な通信パターンです。

#### フロントエンド → バックエンド

```typescript
// Next.js APIルート（BFF）からバックエンドAPI呼び出し
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  try {
    const response = await fetch('http://host.docker.internal:8001/api/v1/profiles/me', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });

    const data = await response.json();
    res.status(200).json(data);
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

#### バックエンド → バックエンド（JWKS取得）

```python
import httpx
from typing import Dict

async def fetch_jwks() -> Dict:
    """Auth ServiceからJWKS取得"""
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(
            "http://host.docker.internal:8002/.well-known/jwks.json"
        )
        response.raise_for_status()
        return response.json()
```

### 2. 非同期通信（Redis Pub/Sub）

イベント駆動アーキテクチャの実装に使用。

```python
import redis.asyncio as redis

# Publisher（Auth Service）
async def publish_user_logged_out(user_id: str):
    """ログアウトイベント発行"""
    r = redis.from_url("redis://localhost:6379")
    await r.publish(
        "user.logout",
        json.dumps({"user_id": user_id, "timestamp": datetime.utcnow().isoformat()})
    )

# Subscriber（User API / Admin API）
async def subscribe_to_events():
    """イベント購読"""
    r = redis.from_url("redis://localhost:6379")
    pubsub = r.pubsub()
    await pubsub.subscribe("user.logout")

    async for message in pubsub.listen():
        if message["type"] == "message":
            data = json.loads(message["data"])
            await handle_user_logout(data["user_id"])
```

### 3. データ共有（Redis Cache）

Redisを共有キャッシュとして使用。

```python
import redis.asyncio as redis
import json

# データ書き込み（Auth Service）
async def cache_user_session(user_id: str, session_data: dict):
    """セッション情報キャッシュ"""
    r = redis.from_url("redis://localhost:6379")
    await r.setex(
        f"session:{user_id}",
        3600,  # 1時間
        json.dumps(session_data)
    )

# データ読み込み（User API）
async def get_user_session(user_id: str) -> dict:
    """セッション情報取得"""
    r = redis.from_url("redis://localhost:6379")
    data = await r.get(f"session:{user_id}")
    return json.loads(data) if data else None
```

---

## 通信プロトコル

### HTTP/REST仕様

#### リクエスト形式

```http
POST /api/v1/profiles HTTP/1.1
Host: localhost:8001
Content-Type: application/json
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
Accept: application/json

{
  "first_name": "John",
  "last_name": "Doe"
}
```

#### レスポンス形式

```http
HTTP/1.1 200 OK
Content-Type: application/json
X-Request-ID: 550e8400-e29b-41d4-a716-446655440000

{
  "status": "success",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "first_name": "John",
    "last_name": "Doe"
  }
}
```

### WebSocket（将来対応予定）

リアルタイム通信が必要な場合に使用。

```typescript
// WebSocket接続例
const ws = new WebSocket('ws://localhost:8001/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

ws.send(JSON.stringify({ type: 'subscribe', channel: 'notifications' }));
```

---

## サービスディスカバリ

### 静的設定方式

現在は環境変数による静的設定を採用。

```bash
# User Frontend .env
AUTH_SERVER_URL=http://host.docker.internal:8002
API_SERVER_URL=http://host.docker.internal:8001

# User API .env
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
AUTH_SERVICE_URL=http://host.docker.internal:8002
```

### Docker Compose ネットワーク

```yaml
# docker-compose.yml
version: '3.8'

services:
  auth-service:
    image: ai-micro-api-auth
    ports:
      - "8002:8002"
    networks:
      - microservices-network

  user-api:
    image: ai-micro-api-user
    ports:
      - "8001:8001"
    networks:
      - microservices-network

networks:
  microservices-network:
    driver: bridge
```

### サービスディスカバリ（将来実装）

Consulなどを使用した動的サービスディスカバリ。

```python
import consul

# Consul登録
c = consul.Consul(host='localhost', port=8500)
c.agent.service.register(
    name='user-api',
    service_id='user-api-1',
    address='localhost',
    port=8001,
    check=consul.Check.http('http://localhost:8001/health', interval='10s')
)

# サービス検索
services = c.health.service('auth-service', passing=True)[1]
auth_service_url = f"http://{services[0]['Service']['Address']}:{services[0]['Service']['Port']}"
```

---

## エラーハンドリング

### リトライ戦略

```python
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10)
)
async def call_service_with_retry(url: str, **kwargs):
    """リトライ付きサービス呼び出し"""
    async with httpx.AsyncClient() as client:
        response = await client.request(**kwargs, url=url)
        response.raise_for_status()
        return response.json()
```

### サーキットブレーカー

```python
from pybreaker import CircuitBreaker

# サーキットブレーカー設定
breaker = CircuitBreaker(
    fail_max=5,              # 5回失敗でオープン
    timeout_duration=60,     # 60秒後にハーフオープン
    exclude=[httpx.HTTPStatusError]  # 除外する例外
)

@breaker
async def call_auth_service(endpoint: str):
    """Auth Service呼び出し（サーキットブレーカー付き）"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"http://localhost:8002{endpoint}")
        return response.json()
```

### フォールバック処理

```python
async def get_user_profile_with_fallback(user_id: str) -> dict:
    """フォールバック付きプロフィール取得"""
    try:
        # メインAPI呼び出し
        return await call_user_api(user_id)
    except httpx.HTTPError:
        # キャッシュからフォールバック
        cached_data = await redis_client.get(f"profile:{user_id}")
        if cached_data:
            return json.loads(cached_data)

        # デフォルトデータ返却
        return {
            "id": user_id,
            "first_name": "Unknown",
            "last_name": "User",
            "email": "unknown@example.com"
        }
```

---

## タイムアウト設定

### HTTPクライアント設定

```python
import httpx

# タイムアウト設定
timeout = httpx.Timeout(
    connect=5.0,    # 接続タイムアウト: 5秒
    read=10.0,      # 読み込みタイムアウト: 10秒
    write=10.0,     # 書き込みタイムアウト: 10秒
    pool=5.0        # プールタイムアウト: 5秒
)

async with httpx.AsyncClient(timeout=timeout) as client:
    response = await client.get("http://localhost:8001/api/v1/profiles/me")
```

### サービス別推奨タイムアウト

| サービス | 接続タイムアウト | 読み込みタイムアウト | 説明 |
|---------|--------------|------------------|------|
| Auth Service | 3秒 | 5秒 | 認証処理は高速 |
| User API | 3秒 | 10秒 | プロフィール取得 |
| Admin API | 5秒 | 30秒 | ドキュメント処理含む |
| JWKS取得 | 2秒 | 3秒 | キャッシュされるため短め |

---

## 実装例

### BFFからバックエンドへの呼び出し

```typescript
// pages/api/profile.ts
import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Cookieからトークン取得
  const accessToken = req.cookies.access_token;

  if (!accessToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // User APIへリクエスト転送
    const response = await fetch(
      `${process.env.API_SERVER_URL}/api/v1/profiles/me`,
      {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        // タイムアウト設定
        signal: AbortSignal.timeout(10000),
      }
    );

    if (!response.ok) {
      throw new Error(`API responded with status ${response.status}`);
    }

    const data = await response.json();
    res.status(200).json(data);

  } catch (error) {
    console.error('Error calling User API:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
```

### バックエンド間通信（JWT検証）

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import httpx
from jose import jwt
from functools import lru_cache

security = HTTPBearer()

@lru_cache(maxsize=1)
def get_jwks_cache():
    """JWKSキャッシュ（アプリケーションライフタイム）"""
    return {}

async def get_jwks() -> dict:
    """JWKSを取得（1時間キャッシュ）"""
    cache = get_jwks_cache()

    if "keys" not in cache or cache.get("expires_at", 0) < time.time():
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(
                "http://host.docker.internal:8002/.well-known/jwks.json"
            )
            response.raise_for_status()
            cache["keys"] = response.json()
            cache["expires_at"] = time.time() + 3600

    return cache["keys"]

async def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """JWT検証（Auth Serviceの公開鍵使用）"""
    try:
        token = credentials.credentials
        jwks = await get_jwks()

        # トークンデコード
        header = jwt.get_unverified_header(token)
        key = next(k for k in jwks["keys"] if k["kid"] == header["kid"])

        payload = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience="fastapi-api",
            issuer="https://auth.example.com"
        )

        return payload

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
```

---

## 関連ドキュメント

- [認証フロー統合](./02-authentication-flow.md)
- [JWT検証フロー](./04-jwt-verification.md)
- [BFFパターン](./07-bff-pattern.md)
- [エラー伝播](./06-error-propagation.md)
- [システム全体アーキテクチャ](../00-overview/01-system-architecture.md)