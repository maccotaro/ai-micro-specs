# デバッグガイド

## Python (FastAPI) デバッグ

### VS Code デバッガー

```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "FastAPI: Auth Service",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": ["app.main:app", "--reload", "--port", "8002"],
      "cwd": "${workspaceFolder}/ai-micro-api-auth"
    }
  ]
}
```

### ログ出力

```python
import logging

logger = logging.getLogger(__name__)

logger.debug("Debug message", extra={"user_id": user_id})
logger.info("User login", extra={"username": username})
logger.error("Login failed", extra={"error": str(e)}, exc_info=True)
```

### pdb デバッガー

```python
import pdb

def complex_function(data):
    # デバッガー起動
    pdb.set_trace()
    result = process_data(data)
    return result
```

## TypeScript (Next.js) デバッグ

### ブラウザ DevTools

```typescript
export default function Dashboard() {
  const [data, setData] = useState(null);

  useEffect(() => {
    console.log('Dashboard mounted');
    fetchData().then(result => {
      console.log('Data fetched:', result);
      setData(result);
    });
  }, []);

  return <div>Dashboard</div>;
}
```

### debugger 文

```typescript
function processData(input: any) {
  debugger; // ここで実行一時停止
  return transform(input);
}
```

## Docker デバッグ

### コンテナログ

```bash
# リアルタイムログ
docker logs -f auth-service

# 最新100行
docker logs --tail 100 auth-service
```

### コンテナ内でコマンド実行

```bash
# bash シェルに入る
docker exec -it auth-service bash

# Python シェル
docker exec -it auth-service poetry run python

# curl でヘルスチェック
docker exec auth-service curl http://localhost:8002/health
```

## データベースデバッグ

### PostgreSQL

```bash
# データベースに接続
docker exec -it postgres psql -U postgres -d authdb

# テーブル確認
\dt

# クエリ実行計画
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

### Redis

```bash
# Redis CLI
docker exec -it redis redis-cli -a password

# キー確認
KEYS *

# 値取得
GET user:123:profile
```

## よくある問題と解決方法

### 認証エラー (401)

```bash
# トークン確認
curl -v http://localhost:3002/api/profile

# バックエンドログ確認
docker logs auth-service | grep "token"
```

### データベース接続エラー

```bash
# PostgreSQL 起動確認
docker ps | grep postgres

# 接続テスト
docker exec postgres psql -U postgres -c "SELECT 1"
```

### N+1 クエリ問題

```python
# SQLログを有効化
import logging
logging.getLogger('sqlalchemy.engine').setLevel(logging.DEBUG)
```

---

**関連**: [開発環境](./01-development-setup.md), [テストガイド](./04-testing-guide.md)