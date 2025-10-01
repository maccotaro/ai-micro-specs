# 契約テスト

## Pact による契約テスト

### Consumer Side (Frontend)

```typescript
// tests/contract/user-api.pact.test.ts
import { pactWith } from 'jest-pact';
import { Matchers } from '@pact-foundation/pact';

pactWith({ consumer: 'UserFrontend', provider: 'UserAPI' }, provider => {
  describe('GET /profile', () => {
    beforeEach(() => {
      const expectedResponse = {
        id: Matchers.uuid(),
        username: Matchers.string('testuser'),
        email: Matchers.email(),
        createdAt: Matchers.iso8601DateTime(),
      };

      return provider.addInteraction({
        state: 'user exists',
        uponReceiving: 'a request for user profile',
        withRequest: {
          method: 'GET',
          path: '/profile',
          headers: {
            Authorization: Matchers.string('Bearer token'),
          },
        },
        willRespondWith: {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
          },
          body: expectedResponse,
        },
      });
    });

    it('returns user profile', async () => {
      const response = await fetch(`${provider.mockService.baseUrl}/profile`, {
        headers: {
          Authorization: 'Bearer token',
        },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data).toHaveProperty('id');
      expect(data).toHaveProperty('username');
    });
  });
});
```

### Provider Side (Backend)

```python
# tests/contract/test_user_api_provider.py
from pact import Verifier

def test_provider_contract():
    verifier = Verifier(
        provider='UserAPI',
        provider_base_url='http://localhost:8001'
    )

    output, _ = verifier.verify_pacts(
        './pacts/userfrontend-userapi.json',
        provider_states_setup_url='http://localhost:8001/_pact/setup'
    )

    assert output == 0
```

## Provider States

```python
# app/routers/pact.py
from fastapi import APIRouter

router = APIRouter()

@router.post("/_pact/setup")
async def setup_provider_state(state: dict):
    """契約テスト用のプロバイダー状態セットアップ"""
    if state["state"] == "user exists":
        # テストユーザーを作成
        await create_test_user({
            "id": "123",
            "username": "testuser",
            "email": "test@example.com"
        })
    return {"result": "success"}
```

## 契約の公開

```bash
# Pact Broker に公開
pact-broker publish \
  ./pacts \
  --consumer-app-version $GIT_COMMIT \
  --broker-base-url https://pact-broker.example.com \
  --broker-token $PACT_BROKER_TOKEN
```

---

**関連**: [統合テスト](./03-integration-testing.md), [パフォーマンステスト](./06-performance-testing.md)