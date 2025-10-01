# CI/CDパイプライン

## GitHub Actions ワークフロー

### テストワークフロー

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          cd ai-micro-api-auth
          poetry install
      - name: Run tests
        run: |
          cd ai-micro-api-auth
          poetry run pytest --cov=app

  test-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install dependencies
        run: |
          cd ai-micro-front-user
          npm ci
      - name: Run tests
        run: |
          cd ai-micro-front-user
          npm test
```

### ビルドワークフロー

```yaml
# .github/workflows/build.yml
name: Build and Push

on:
  push:
    branches: [main, develop]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./ai-micro-api-auth
          push: true
          tags: ghcr.io/your-org/auth-service:${{ github.sha }}
```

### デプロイワークフロー

```yaml
# .github/workflows/deploy-staging.yml
name: Deploy to Staging

on:
  push:
    branches: [develop]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: |
          # デプロイスクリプト実行
          ssh user@staging-server "cd /app && docker compose pull && docker compose up -d"

      - name: Notify Slack
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {"text": "🚀 Deployed to staging"}
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## デプロイフロー

### Staging (自動)

```
develop ブランチへのプッシュ
    ↓
GitHub Actions
    ├─ Lint & Test
    ├─ Build Docker images
    ├─ Push to registry
    └─ Deploy to staging
    ↓
Slack 通知
```

### Production (手動承認)

```
main タグ作成 (v1.0.0)
    ↓
GitHub Actions
    ├─ 全テスト実行
    ├─ Build Docker images
    └─ Manual Approval
    ↓ (承認後)
Deploy to production
    ↓
通知
```

## ブランチ戦略

| ブランチ | 環境 | デプロイ |
|---------|------|---------|
| `feature/*` | なし | なし |
| `develop` | Staging | 自動 |
| `main` (tag) | Production | 手動承認 |

---

**関連**: [デプロイ概要](./01-deployment-overview.md), [本番デプロイ](./05-production-deployment.md)