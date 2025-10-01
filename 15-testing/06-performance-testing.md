# パフォーマンステスト

## Locust

### セットアップ

```bash
pip install locust
```

### テストシナリオ

```python
# locustfile.py
from locust import HttpUser, task, between

class APIUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        """テスト開始時にログイン"""
        response = self.client.post("/login", json={
            "username": "testuser",
            "password": "testpass"
        })
        self.token = response.json()["access_token"]

    @task(3)
    def get_profile(self):
        """プロファイル取得 (重み: 3)"""
        self.client.get(
            "/profile",
            headers={"Authorization": f"Bearer {self.token}"}
        )

    @task(1)
    def update_profile(self):
        """プロファイル更新 (重み: 1)"""
        self.client.put(
            "/profile",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"first_name": "Updated"}
        )
```

### テスト実行

```bash
# Web UI起動
locust -f locustfile.py --host=http://localhost:8001

# コマンドライン実行
locust -f locustfile.py \
  --host=http://localhost:8001 \
  --users 100 \
  --spawn-rate 10 \
  --run-time 5m \
  --headless
```

## k6

### セットアップ

```bash
brew install k6  # macOS
```

### テストシナリオ

```javascript
// load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp-up
    { duration: '5m', target: 100 },  // Stay
    { duration: '2m', target: 0 },    // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95%のリクエストが500ms以下
    http_req_failed: ['rate<0.01'],    // エラー率1%未満
  },
};

export default function () {
  // ログイン
  let loginRes = http.post('http://localhost:8001/login', JSON.stringify({
    username: 'testuser',
    password: 'testpass',
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(loginRes, {
    'login successful': (r) => r.status === 200,
  });

  let token = loginRes.json('access_token');

  // プロファイル取得
  let profileRes = http.get('http://localhost:8001/profile', {
    headers: { Authorization: `Bearer ${token}` },
  });

  check(profileRes, {
    'profile fetch successful': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });

  sleep(1);
}
```

### テスト実行

```bash
k6 run load-test.js

# クラウド実行
k6 cloud load-test.js
```

## パフォーマンス目標

| メトリクス | 目標値 |
|-----------|--------|
| Response Time (p95) | < 200ms |
| Error Rate | < 0.1% |
| Throughput | > 1000 req/s |
| CPU Usage | < 70% |
| Memory Usage | < 80% |

---

**関連**: [契約テスト](./05-contract-testing.md), [テスト戦略](./01-testing-strategy.md)