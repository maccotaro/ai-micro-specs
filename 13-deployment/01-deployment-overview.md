# デプロイ概要

## 環境構成

| 環境 | 用途 | デプロイ方法 | URL |
|------|------|------------|-----|
| **Development** | ローカル開発 | docker compose | localhost:3002/3003 |
| **Staging** | 統合テスト | CI/CD自動 | staging.example.com |
| **Production** | 本番環境 | 手動承認後 | app.example.com |

## デプロイメントフロー

### Development (ローカル)

```bash
# 全サービス起動
docker compose up -d

# ログ確認
docker compose logs -f auth-service

# 停止
docker compose down
```

### Staging (自動)

```
develop ブランチマージ
    ↓
GitHub Actions
    ↓
テスト実行
    ↓
Docker イメージビルド
    ↓
デプロイ
    ↓
Slack 通知
```

### Production (手動承認)

```
main タグ作成
    ↓
GitHub Actions
    ↓
全テスト実行
    ↓
Manual Approval
    ↓
デプロイ
    ↓
通知
```

## サービス起動順序

```
1. PostgreSQL
2. Redis
3. Auth Service
4. User API Service
5. Admin API Service
6. User Frontend
7. Admin Frontend
```

## ヘルスチェック

各サービスのヘルスチェックエンドポイント:

- Auth Service: `http://localhost:8002/health`
- User Service: `http://localhost:8001/health`
- Admin Service: `http://localhost:8003/health`

```bash
# ヘルスチェック実行
curl http://localhost:8002/health
```

## ロールバック

```bash
# Docker Compose
docker compose down
docker compose up -d

# 前のイメージに戻す
docker pull ghcr.io/your-org/auth-service:v1.0.0
docker compose up -d
```

---

**関連**: [Docker Compose](./02-docker-compose.md), [CI/CD](./04-ci-cd.md)