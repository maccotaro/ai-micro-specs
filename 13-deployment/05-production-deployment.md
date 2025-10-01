# 本番デプロイ手順

## デプロイ前チェックリスト

- [ ] 全テストが通過
- [ ] Staging環境で動作確認
- [ ] データベースマイグレーション準備
- [ ] 環境変数の確認
- [ ] ロールバック手順の確認

## デプロイ手順

### 1. タグ作成

```bash
git checkout main
git pull origin main
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

### 2. GitHub Actionsの実行確認

GitHub の Actions タブで進捗確認:
- テスト実行
- ビルド
- Manual Approval待ち

### 3. 手動承認

GitHub の Actions ページで Approve ボタンをクリック

### 4. デプロイ実行

自動的にデプロイが開始される

### 5. ヘルスチェック

```bash
# サービスの健全性確認
curl https://app.example.com/health
curl https://api.example.com/health
```

### 6. 動作確認

- ログイン機能
- 主要な機能の動作
- エラーログの確認

## データベースマイグレーション

### 本番環境でのマイグレーション

```bash
# コンテナ内でマイグレーション実行
docker exec -it auth-service alembic upgrade head

# または SSH経由
ssh production-server "cd /app/ai-micro-api-auth && alembic upgrade head"
```

### ロールバック

```bash
# 1つ前に戻す
docker exec -it auth-service alembic downgrade -1
```

## ロールバック手順

### イメージのロールバック

```bash
# 前のバージョンのタグを確認
git tag -l

# 前のバージョンをデプロイ
docker pull ghcr.io/your-org/auth-service:v1.0.0
docker compose up -d
```

### データベースのロールバック

```bash
# マイグレーションのロールバック
alembic downgrade -1
```

## モニタリング

デプロイ後のモニタリング項目:

- **レスポンスタイム**: p95 < 200ms
- **エラー率**: < 0.1%
- **CPU使用率**: < 70%
- **メモリ使用率**: < 80%

```bash
# ログ確認
docker logs -f auth-service

# リソース確認
docker stats
```

## トラブルシューティング

### デプロイが失敗した場合

1. エラーログを確認
2. 環境変数を確認
3. データベース接続を確認
4. 必要に応じてロールバック

### サービスが起動しない場合

```bash
# コンテナのログ確認
docker logs auth-service

# コンテナの状態確認
docker ps -a

# ヘルスチェック
docker inspect auth-service | grep Health
```

## デプロイ後の通知

- Slack: #deployments チャンネルに通知
- Email: チームメンバーに送信

---

**関連**: [デプロイ概要](./01-deployment-overview.md), [CI/CD](./04-ci-cd.md)