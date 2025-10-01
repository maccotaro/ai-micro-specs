# テストガイド

## テスト戦略

```
       /\
      /  \  E2E Tests (10%)
     /----\
    /      \ Integration Tests (30%)
   /--------\
  /          \ Unit Tests (60%)
 /____________\
```

## Python (FastAPI) テスト

### Unit Tests

```python
# tests/unit/test_security.py
import pytest
from app.core.security import create_access_token, verify_token

def test_create_access_token():
    token = create_access_token(user_id="123", username="test", role="user")
    assert isinstance(token, str)
    assert len(token) > 0

def test_verify_token_valid():
    token = create_access_token(user_id="123", username="test", role="user")
    payload = verify_token(token)
    assert payload["sub"] == "123"
```

### Integration Tests

```python
# tests/integration/test_auth_flow.py
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_login_flow():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/login", json={
            "username": "testuser",
            "password": "testpass"
        })
        assert response.status_code == 200
        assert "access_token" in response.json()
```

### テスト実行

```bash
# 全テスト実行
poetry run pytest

# カバレッジ測定
poetry run pytest --cov=app --cov-report=html

# 特定のファイルのみ
poetry run pytest tests/unit/test_security.py
```

## TypeScript (Next.js) テスト

### Component Tests

```typescript
// tests/components/Button.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { Button } from '@/components/Button';

describe('Button Component', () => {
  it('renders button with label', () => {
    render(<Button label="Click me" onClick={() => {}} />);
    expect(screen.getByText('Click me')).toBeInTheDocument();
  });

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn();
    render(<Button label="Click me" onClick={handleClick} />);
    fireEvent.click(screen.getByText('Click me'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });
});
```

### API Route Tests

```typescript
// tests/api/auth.test.ts
import { createMocks } from 'node-mocks-http';
import handler from '@/pages/api/auth/login';

describe('/api/auth/login', () => {
  it('returns 200 with valid credentials', async () => {
    const { req, res } = createMocks({
      method: 'POST',
      body: { username: 'testuser', password: 'testpass' },
    });

    await handler(req, res);
    expect(res._getStatusCode()).toBe(200);
  });
});
```

### テスト実行

```bash
# 全テスト実行
npm test

# Watch モード
npm test -- --watch

# カバレッジ
npm test -- --coverage
```

## E2E Tests (Playwright)

```typescript
// tests/e2e/user-journey.spec.ts
import { test, expect } from '@playwright/test';

test('user can register and login', async ({ page }) => {
  await page.goto('http://localhost:3002/register');
  await page.fill('input[name="username"]', 'newuser');
  await page.fill('input[name="password"]', 'password123');
  await page.click('button[type="submit"]');
  await expect(page).toHaveURL('http://localhost:3002/dashboard');
});
```

```bash
# E2E テスト実行
npx playwright test
```

## テストカバレッジ目標

- Unit Tests: 80%以上
- Integration Tests: 70%以上
- E2E Tests: 主要フロー全カバー

---

**関連**: [開発環境](./01-development-setup.md), [デバッグガイド](./05-debugging-guide.md)