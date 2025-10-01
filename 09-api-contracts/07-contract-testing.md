# 契約テスト

**作成日**: 2025-09-30
**最終更新**: 2025-09-30
**対象バージョン**: v1.0

## 📋 目次

- [概要](#概要)
- [テスト戦略](#テスト戦略)
- [スキーマバリデーション](#スキーマバリデーション)
- [モックサーバー](#モックサーバー)
- [Pact テスト](#pactテスト)

---

## 概要

契約テスト（Contract Testing）は、サービス間のAPIコントラクトが期待通りに動作することを検証するテスト手法です。

### 契約テストの目的

1. **インターフェース互換性保証**: APIの破壊的変更を検出
2. **並行開発支援**: フロントエンドとバックエンドの独立開発
3. **回帰防止**: リリース前にAPI変更の影響を検証
4. **ドキュメント精度**: 実装とドキュメントの乖離を防止

---

## テスト戦略

### テストピラミッド

```
        ┌─────────────┐
        │   E2E Test  │  ← 少数
        ├─────────────┤
        │ Integration │  ← 中程度
        │    Test     │
        ├─────────────┤
        │ Contract    │  ← 多数
        │   Test      │
        ├─────────────┤
        │   Unit Test │  ← 最多
        └─────────────┘
```

---

## スキーマバリデーション

### Pythonでのスキーマ検証

```python
# tests/test_contracts.py
import pytest
from pydantic import ValidationError
from schemas.auth import LoginRequest, LoginResponse

def test_login_request_schema():
    """ログインリクエストスキーマ検証"""
    # 正常ケース
    valid_data = {
        "email": "user@example.com",
        "password": "SecurePass123!"
    }
    request = LoginRequest(**valid_data)
    assert request.email == "user@example.com"

    # 異常ケース: 無効なメールアドレス
    with pytest.raises(ValidationError):
        LoginRequest(email="invalid-email", password="SecurePass123!")

    # 異常ケース: パスワードが短い
    with pytest.raises(ValidationError):
        LoginRequest(email="user@example.com", password="short")

def test_login_response_schema():
    """ログインレスポンススキーマ検証"""
    response_data = {
        "access_token": "eyJhbGc...",
        "refresh_token": "eyJhbGc...",
        "token_type": "Bearer",
        "expires_in": 900,
        "user": {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "user@example.com",
            "role": "user"
        }
    }
    response = LoginResponse(**response_data)
    assert response.token_type == "Bearer"
    assert response.user.role == "user"
```

### TypeScriptでのスキーマ検証

```typescript
// tests/contracts.test.ts
import { z } from 'zod';

const LoginRequestSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

describe('Login Request Schema', () => {
  it('should validate correct login request', () => {
    const data = {
      email: 'user@example.com',
      password: 'SecurePass123!',
    };

    const result = LoginRequestSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('should reject invalid email', () => {
    const data = {
      email: 'invalid-email',
      password: 'SecurePass123!',
    };

    const result = LoginRequestSchema.safeParse(data);
    expect(result.success).toBe(false);
  });
});
```

---

## モックサーバー

### MSW（Mock Service Worker）

```typescript
// mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  // ログインAPI
  http.post('http://localhost:8002/api/v1/auth/login', async ({ request }) => {
    const body = await request.json();

    // リクエストバリデーション
    if (!body.email || !body.password) {
      return HttpResponse.json(
        { error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } },
        { status: 400 }
      );
    }

    // モックレスポンス
    return HttpResponse.json({
      status: 'success',
      data: {
        access_token: 'mock_access_token',
        refresh_token: 'mock_refresh_token',
        token_type: 'Bearer',
        expires_in: 900,
        user: {
          user_id: '550e8400-e29b-41d4-a716-446655440000',
          email: body.email,
          role: 'user',
        },
      },
    });
  }),

  // プロフィール取得API
  http.get('http://localhost:8001/api/v1/profiles/me', ({ request }) => {
    const authHeader = request.headers.get('Authorization');

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json(
        { error: { code: 'UNAUTHORIZED', message: 'Missing authorization' } },
        { status: 401 }
      );
    }

    return HttpResponse.json({
      status: 'success',
      data: {
        profile: {
          id: '550e8400-e29b-41d4-a716-446655440001',
          user_id: '550e8400-e29b-41d4-a716-446655440000',
          email: 'user@example.com',
          first_name: 'John',
          last_name: 'Doe',
          created_at: '2025-09-30T10:00:00Z',
          updated_at: '2025-09-30T10:00:00Z',
        },
      },
    });
  }),
];
```

### テスト実行

```typescript
// tests/api.test.ts
import { setupServer } from 'msw/node';
import { handlers } from '../mocks/handlers';

const server = setupServer(...handlers);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('Auth API', () => {
  it('should login successfully', async () => {
    const response = await fetch('http://localhost:8002/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'user@example.com',
        password: 'SecurePass123!',
      }),
    });

    const data = await response.json();
    expect(data.status).toBe('success');
    expect(data.data.access_token).toBe('mock_access_token');
  });
});
```

---

## Pact テスト

### Consumer側（Frontend）

```typescript
// tests/pact/auth.pact.test.ts
import { PactV3, MatchersV3 } from '@pact-foundation/pact';

const { eachLike, like } = MatchersV3;

const provider = new PactV3({
  consumer: 'UserFrontend',
  provider: 'AuthService',
});

describe('Auth Service Pact', () => {
  it('should login with valid credentials', () => {
    provider
      .given('user exists')
      .uponReceiving('a login request')
      .withRequest({
        method: 'POST',
        path: '/api/v1/auth/login',
        body: {
          email: 'user@example.com',
          password: 'SecurePass123!',
        },
        headers: {
          'Content-Type': 'application/json',
        },
      })
      .willRespondWith({
        status: 200,
        headers: {
          'Content-Type': 'application/json',
        },
        body: {
          status: 'success',
          data: {
            access_token: like('eyJhbGc...'),
            refresh_token: like('eyJhbGc...'),
            token_type: 'Bearer',
            expires_in: 900,
            user: {
              user_id: like('550e8400-e29b-41d4-a716-446655440000'),
              email: 'user@example.com',
              role: 'user',
            },
          },
        },
      });

    return provider.executeTest(async (mockService) => {
      const response = await fetch(`${mockService.url}/api/v1/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: 'user@example.com',
          password: 'SecurePass123!',
        }),
      });

      const data = await response.json();
      expect(data.status).toBe('success');
    });
  });
});
```

### Provider側（Backend）

```python
# tests/test_pact_provider.py
import pytest
from pact import Verifier

def test_auth_service_honors_pact_with_user_frontend():
    """Auth ServiceがUser Frontendとの契約を満たすことを検証"""
    verifier = Verifier(
        provider='AuthService',
        provider_base_url='http://localhost:8002'
    )

    # Pactファイル検証
    verifier.verify_pacts(
        './pacts/UserFrontend-AuthService.json',
        provider_states_setup_url='http://localhost:8002/_pact/provider_states'
    )
```

---

## 関連ドキュメント

- [データモデル定義](./03-data-models.md)
- [OpenAPI統合](./04-openapi-integration.md)
- [TypeScript型定義](./05-typescript-types.md)
- [Pydanticスキーマ](./06-pydantic-schemas.md)