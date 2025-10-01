# 統合テスト

## API Integration Tests

### Python (FastAPI)

```python
# tests/integration/test_auth_flow.py
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_user_registration_flow():
    """ユーザー登録フローのテスト"""
    async with AsyncClient(app=app, base_url="http://test") as client:
        # 新規ユーザー登録
        response = await client.post("/register", json={
            "username": "newuser",
            "email": "newuser@example.com",
            "password": "SecurePass123!"
        })
        assert response.status_code == 201
        data = response.json()
        assert data["username"] == "newuser"
        assert "id" in data

@pytest.mark.asyncio
async def test_login_logout_flow():
    """ログイン・ログアウトフローのテスト"""
    async with AsyncClient(app=app, base_url="http://test") as client:
        # ログイン
        login_response = await client.post("/login", json={
            "username": "testuser",
            "password": "testpass"
        })
        assert login_response.status_code == 200
        tokens = login_response.json()
        access_token = tokens["access_token"]

        # 認証が必要なエンドポイント
        profile_response = await client.get(
            "/profile",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        assert profile_response.status_code == 200

        # ログアウト
        logout_response = await client.post(
            "/logout",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        assert logout_response.status_code == 200
```

### TypeScript (Next.js API Routes)

```typescript
// tests/integration/api/auth.test.ts
import { createMocks } from 'node-mocks-http';
import handler from '@/pages/api/auth/login';

describe('/api/auth/login', () => {
  it('returns 200 with valid credentials', async () => {
    const { req, res } = createMocks({
      method: 'POST',
      body: {
        username: 'testuser',
        password: 'testpass',
      },
    });

    await handler(req, res);

    expect(res._getStatusCode()).toBe(200);
    const data = JSON.parse(res._getData());
    expect(data).toHaveProperty('access_token');
  });

  it('returns 401 with invalid credentials', async () => {
    const { req, res } = createMocks({
      method: 'POST',
      body: {
        username: 'testuser',
        password: 'wrongpass',
      },
    });

    await handler(req, res);
    expect(res._getStatusCode()).toBe(401);
  });
});
```

## データベース統合テスト

```python
@pytest.mark.asyncio
async def test_user_crud(db_session):
    """ユーザーCRUD操作のテスト"""
    # Create
    user = await user_service.create({
        "username": "testuser",
        "email": "test@example.com",
        "password": "password"
    })
    assert user.id is not None

    # Read
    fetched_user = await user_service.get_by_id(user.id)
    assert fetched_user.username == "testuser"

    # Update
    updated_user = await user_service.update(user.id, {"email": "new@example.com"})
    assert updated_user.email == "new@example.com"

    # Delete
    await user_service.delete(user.id)
    deleted_user = await user_service.get_by_id(user.id)
    assert deleted_user is None
```

## テスト実行

```bash
# Python
poetry run pytest tests/integration/ -v

# TypeScript
npm test tests/integration/
```

---

**関連**: [ユニットテスト](./02-unit-testing.md), [E2Eテスト](./04-e2e-testing.md)