# 負荷テスト

## ツール

- **Locust**: Python ベース
- **k6**: JavaScript ベース
- **JMeter**: GUI 付き

## Locust シナリオ

```python
# locustfile.py
from locust import HttpUser, task, between

class UserBehavior(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        # ログイン
        response = self.client.post("/login", json={
            "username": "testuser",
            "password": "testpass"
        })
        self.token = response.json()["access_token"]

    @task(3)
    def get_profile(self):
        self.client.get(
            "/profile",
            headers={"Authorization": f"Bearer {self.token}"}
        )

    @task(1)
    def update_profile(self):
        self.client.put(
            "/profile",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"first_name": "Updated"}
        )
```

## テスト実行

```bash
# Locust 起動
locust -f locustfile.py --host=http://localhost:8001

# コマンドラインから実行
locust -f locustfile.py \
  --host=http://localhost:8001 \
  --users 100 \
  --spawn-rate 10 \
  --run-time 5m \
  --headless
```

## k6 シナリオ

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
};

export default function () {
  let response = http.get('http://localhost:8001/profile');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
  sleep(1);
}
```

```bash
# k6 実行
k6 run load-test.js
```

## 負荷テストシナリオ

### 1. Baseline Test

通常負荷での動作確認

- ユーザー数: 10
- 実行時間: 5分

### 2. Load Test

想定負荷での動作確認

- ユーザー数: 100
- 実行時間: 10分

### 3. Stress Test

限界負荷の特定

- ユーザー数: 100 → 500
- 実行時間: 15分

### 4. Spike Test

急激な負荷変動への対応確認

- ユーザー数: 10 → 500 → 10
- 実行時間: 10分

---

**関連**: [パフォーマンス概要](./01-performance-overview.md), [モニタリング](./05-performance-monitoring.md)