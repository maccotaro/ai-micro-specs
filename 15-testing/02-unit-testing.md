# ユニットテスト

## Python (pytest)

### テスト構造

```
tests/
├── unit/
│   ├── test_security.py
│   ├── test_password.py
│   └── test_validation.py
└── conftest.py
```

### テスト例

```python
# tests/unit/test_security.py
import pytest
from app.core.security import create_access_token, verify_token

def test_create_access_token():
    """アクセストークン生成のテスト"""
    token = create_access_token(
        user_id="123",
        username="test",
        role="user"
    )
    assert isinstance(token, str)
    assert len(token) > 0

def test_verify_token_valid():
    """有効なトークンの検証"""
    token = create_access_token(user_id="123", username="test", role="user")
    payload = verify_token(token)
    assert payload["sub"] == "123"
    assert payload["username"] == "test"

def test_verify_token_expired():
    """期限切れトークンの検証"""
    with pytest.raises(Exception) as exc_info:
        verify_token("expired_token")
    assert "expired" in str(exc_info.value).lower()
```

### Fixtures

```python
# conftest.py
import pytest

@pytest.fixture
def test_user():
    return {
        "id": "123",
        "username": "testuser",
        "email": "test@example.com"
    }

@pytest.fixture
def mock_db(mocker):
    return mocker.patch("app.core.database.database")
```

## TypeScript (Jest)

### テスト例

```typescript
// tests/unit/utils.test.ts
import { formatDate, validateEmail } from '@/lib/utils';

describe('formatDate', () => {
  it('formats date correctly', () => {
    const date = new Date('2024-01-15');
    expect(formatDate(date)).toBe('2024-01-15');
  });
});

describe('validateEmail', () => {
  it('returns true for valid email', () => {
    expect(validateEmail('test@example.com')).toBe(true);
  });

  it('returns false for invalid email', () => {
    expect(validateEmail('invalid')).toBe(false);
  });
});
```

## テスト実行

```bash
# Python
poetry run pytest tests/unit/
poetry run pytest tests/unit/test_security.py -v

# TypeScript
npm test tests/unit/
npm test -- --coverage
```

---

**関連**: [テスト戦略](./01-testing-strategy.md), [統合テスト](./03-integration-testing.md)