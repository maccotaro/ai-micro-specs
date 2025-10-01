# コーディング規約

## 命名規則

- **変数・関数**: snake_case (Python), camelCase (TypeScript)
- **クラス**: PascalCase
- **定数**: UPPER_SNAKE_CASE
- **ファイル名**: kebab-case

## Python (FastAPI)

### 型ヒント必須

```python
async def get_user_profile(user_id: str) -> Optional[UserProfile]:
    """ユーザープロファイルを取得"""
    pass
```

### Pydanticモデル

```python
class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: str = Field(..., description="メールアドレス")
    password: str = Field(..., min_length=8)
```

### エラーハンドリング

```python
async def get_user(user_id: str) -> User:
    user = await db.get_user(user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail=f"User {user_id} not found"
        )
    return user
```

## TypeScript (Next.js)

### 型定義

```typescript
type UserRole = 'admin' | 'user' | 'guest';

interface User {
  id: string;
  username: string;
  email: string;
  role: UserRole;
}
```

### Reactコンポーネント

```typescript
interface ButtonProps {
  label: string;
  onClick: () => void;
  variant?: 'primary' | 'secondary';
}

export const Button: FC<ButtonProps> = ({ label, onClick, variant = 'primary' }) => {
  return <button onClick={onClick}>{label}</button>;
};
```

## コミット規約

```
<type>(<scope>): <subject>

feat(auth): implement JWT refresh token
fix(api): handle null response
docs(readme): update installation guide
```

---

**関連**: [開発環境](./01-development-setup.md), [Gitワークフロー](./03-git-workflow.md)