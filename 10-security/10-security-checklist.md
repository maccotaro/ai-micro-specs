# セキュリティチェックリスト

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [開発チェックリスト](#開発チェックリスト)
- [本番デプロイチェックリスト](#本番デプロイチェックリスト)
- [セキュリティ監査チェックリスト](#セキュリティ監査チェックリスト)
- [インシデント対応チェックリスト](#インシデント対応チェックリスト)

---

## 開発チェックリスト

### 認証・認可

- [ ] パスワードはbcryptでハッシュ化されている
- [ ] JWT は RS256 で署名されている
- [ ] トークン有効期限が適切に設定されている（Access: 15分, Refresh: 30日）
- [ ] トークンブラックリストが実装されている
- [ ] ログアウト時にトークンが無効化される
- [ ] ロールベースアクセス制御（RBAC）が実装されている
- [ ] アカウントロックアウト機能が実装されている（5回失敗で30分ロック）

### データ保護

- [ ] 環境変数で機密情報を管理している
- [ ] `.env` ファイルが `.gitignore` に追加されている
- [ ] データベース接続文字列にパスワードが含まれていない（環境変数使用）
- [ ] Redis にパスワード認証が設定されている
- [ ] ログに機密情報（パスワード、トークン等）を出力していない
- [ ] エラーメッセージに詳細な内部情報を含めていない

### 入力検証

- [ ] すべてのユーザー入力が Pydantic で検証されている
- [ ] SQLクエリはORM または パラメータ化クエリを使用している
- [ ] ファイルアップロードに拡張子制限がある
- [ ] ファイルパスにユーザー入力を直接使用していない
- [ ] HTMLタグがサニタイズされている

### セキュリティヘッダー

- [ ] CORS が適切に設定されている
- [ ] Content-Security-Policy が設定されている
- [ ] X-Content-Type-Options: nosniff が設定されている
- [ ] X-Frame-Options: DENY が設定されている
- [ ] Cookie に HttpOnly, Secure, SameSite 属性が設定されている

### 依存関係管理

- [ ] Poetry / npm による依存関係管理を使用している
- [ ] lockファイルがコミットされている
- [ ] 依存関係のセキュリティスキャンを実施している（pip-audit / npm audit）
- [ ] 脆弱性のある依存関係を更新している

### コード品質

- [ ] 静的解析ツールを使用している（Bandit, ESLint）
- [ ] ハードコードされた認証情報がない
- [ ] コードレビューを実施している
- [ ] テストカバレッジが十分である（70%以上推奨）

---

## 本番デプロイチェックリスト

### インフラ設定

- [ ] HTTPS / TLS が有効化されている
- [ ] SSL証明書が有効である（Let's Encrypt / 商用証明書）
- [ ] HSTS ヘッダーが設定されている
- [ ] データベース SSL 接続が有効化されている
- [ ] Redis TLS 接続が有効化されている（推奨）

### ネットワークセキュリティ

- [ ] ファイアウォールルールが設定されている
- [ ] データベースポートが外部公開されていない
- [ ] Redis ポートが外部公開されていない
- [ ] API サービスが内部ネットワークに配置されている
- [ ] セキュリティグループが最小権限で設定されている

### アプリケーション設定

- [ ] CORS の allow_origins が具体的なオリジンに制限されている
- [ ] JWT の iss, aud が本番環境用に設定されている
- [ ] bcrypt のコストファクターが 12 以上に設定されている
- [ ] デバッグモードが無効化されている
- [ ] セキュリティヘッダーがすべて設定されている

### 認証情報管理

- [ ] シークレット管理サービスを使用している（AWS Secrets Manager, Vault等）
- [ ] 環境変数が適切に設定されている
- [ ] デフォルトパスワードが変更されている
- [ ] SSH鍵が適切に管理されている
- [ ] APIキーが適切に保護されている

### ログとモニタリング

- [ ] アプリケーションログが収集されている
- [ ] セキュリティイベントログが記録されている
- [ ] ログイン失敗・成功がログに記録されている
- [ ] アラート設定が有効化されている
- [ ] ログローテーションが設定されている

### バックアップとリカバリ

- [ ] データベースの定期バックアップが設定されている
- [ ] バックアップが暗号化されている
- [ ] リストア手順が文書化されている
- [ ] バックアップのテストを実施している
- [ ] ディザスタリカバリ計画がある

---

## セキュリティ監査チェックリスト

### 定期監査（月次）

#### 認証・認可

- [ ] ユーザーアカウントの棚卸し
- [ ] 不要なアカウントの削除
- [ ] 権限の見直し（最小権限の原則）
- [ ] 管理者アカウントの確認
- [ ] パスワードポリシーの遵守確認

#### アクセスログ

- [ ] 異常なログインパターンの確認
- [ ] 失敗したログイン試行の分析
- [ ] IPアドレスの地理的分析
- [ ] アカウントロックアウトの確認
- [ ] 不正アクセスの兆候確認

#### 依存関係

- [ ] セキュリティスキャンの実施
- [ ] 脆弱性レポートの確認
- [ ] 必要なアップデートの適用
- [ ] 依存関係の最新化
- [ ] EOL（End of Life）パッケージの確認

#### 設定

- [ ] ファイアウォールルールの確認
- [ ] セキュリティグループの確認
- [ ] SSL証明書の有効期限確認
- [ ] 環境変数の確認
- [ ] CORS設定の確認

### 四半期監査

- [ ] 脆弱性診断の実施
- [ ] ペネトレーションテストの実施（外部委託推奨）
- [ ] コードの静的解析
- [ ] セキュリティポリシーの見直し
- [ ] インシデント対応計画の見直し
- [ ] 災害復旧計画のテスト
- [ ] セキュリティトレーニングの実施

### 年次監査

- [ ] 包括的なセキュリティ監査
- [ ] コンプライアンス確認（GDPR, PCI DSS等）
- [ ] セキュリティポリシーの全面見直し
- [ ] インフラの見直し
- [ ] 暗号化アルゴリズムの見直し
- [ ] 鍵のローテーション
- [ ] セキュリティ投資の評価

---

## インシデント対応チェックリスト

### 検出フェーズ

- [ ] インシデントの検出と報告
- [ ] 初期評価の実施
- [ ] インシデント対応チームの招集
- [ ] 影響範囲の特定
- [ ] 重要度の判定

### 封じ込めフェーズ

- [ ] 攻撃の一時的な封じ込め
  - [ ] 不正アカウントの無効化
  - [ ] ファイアウォールルールの追加
  - [ ] サービスの一時停止（必要に応じて）
- [ ] 証拠の保全
  - [ ] ログの保存
  - [ ] スナップショットの作成
  - [ ] メモリダンプの取得（必要に応じて）
- [ ] 攻撃の完全な封じ込め
  - [ ] 脆弱性のパッチ適用
  - [ ] 侵害されたシステムの隔離

### 根絶フェーズ

- [ ] 攻撃者のアクセスポイントの削除
- [ ] マルウェアの除去
- [ ] 侵害されたアカウントのリセット
- [ ] すべてのパスワードの変更
- [ ] SSH鍵のローテーション
- [ ] APIキーのローテーション

### 復旧フェーズ

- [ ] システムの復旧
- [ ] バックアップからのリストア（必要に応じて）
- [ ] サービスの再開
- [ ] 監視の強化
- [ ] ユーザーへの通知

### 事後分析フェーズ

- [ ] インシデントレポートの作成
  - [ ] タイムライン
  - [ ] 根本原因
  - [ ] 影響範囲
  - [ ] 対応内容
- [ ] 教訓の抽出
- [ ] 再発防止策の策定
- [ ] セキュリティポリシーの更新
- [ ] システムの改善実施

---

## クイックチェック（日次）

### 自動化推奨

```bash
#!/bin/bash
# daily-security-check.sh

echo "===== Daily Security Check ====="
echo "Date: $(date)"
echo ""

# サービス稼働確認
echo "1. Service Health Check"
curl -s https://api.example.com/healthz | jq .
echo ""

# SSL証明書有効期限
echo "2. SSL Certificate Expiry"
echo | openssl s_client -servername api.example.com -connect api.example.com:443 2>/dev/null | openssl x509 -noout -dates
echo ""

# ディスク使用率
echo "3. Disk Usage"
df -h | grep -E '^/dev/'
echo ""

# 失敗したログイン試行
echo "4. Failed Login Attempts (last 24h)"
docker exec ai-micro-postgres psql -U postgres -d authdb -c \
  "SELECT COUNT(*) FROM login_logs WHERE success = false AND created_at > NOW() - INTERVAL '24 hours';"
echo ""

# ロックされたアカウント
echo "5. Locked Accounts"
docker exec ai-micro-postgres psql -U postgres -d authdb -c \
  "SELECT email, locked_until FROM users WHERE locked_until > NOW();"
echo ""

echo "===== Check Complete ====="
```

---

## セキュリティツールスイート

### 推奨ツール

| カテゴリ | ツール | 用途 |
|---------|--------|------|
| 依存関係スキャン | pip-audit, npm audit, Snyk | 脆弱性検出 |
| 静的解析 | Bandit, ESLint Security | コード品質 |
| 動的解析 | OWASP ZAP | ペネトレーションテスト |
| シークレット検出 | git-secrets, TruffleHog | 認証情報漏洩検出 |
| コンテナスキャン | Trivy, Clair | Docker イメージ脆弱性 |
| 監視 | Prometheus, Grafana, AWS CloudWatch | リアルタイム監視 |

### CI/CD統合

```yaml
# .github/workflows/security.yml
name: Security Checks

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      # Secret scanning
      - name: TruffleHog
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD

      # Python security
      - name: Bandit
        run: |
          pip install bandit
          bandit -r app/ -f json -o bandit-report.json

      # Dependency check
      - name: pip-audit
        run: |
          pip install pip-audit
          pip-audit

      # Container scanning
      - name: Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'myimage:latest'
          format: 'sarif'
          output: 'trivy-results.sarif'
```

---

## セキュリティ評価スコア

### 評価基準

各項目を以下の基準で評価:

- ✅ **実装済み**: 完全に実装・設定済み
- ⚠️ **部分実装**: 一部実装されているが改善の余地あり
- ❌ **未実装**: 未実装または設定されていない

### 現在のステータス（ai-micro-service）

#### 認証・認可（85%）

- ✅ JWT認証（RS256）
- ✅ パスワードハッシング（bcrypt）
- ✅ トークンブラックリスト
- ✅ ロールベースアクセス制御
- ✅ アカウントロックアウト
- ⚠️ 多要素認証（未実装）

#### データ保護（70%）

- ✅ パスワードハッシング
- ✅ 環境変数管理
- ✅ Redis認証
- ⚠️ データベース暗号化（推奨）
- ⚠️ TLS/HTTPS（本番環境で必要）

#### ネットワークセキュリティ（60%）

- ✅ Docker ネットワーク分離
- ✅ ポート制限
- ⚠️ HTTPS未設定（開発環境）
- ⚠️ ファイアウォールルール（本番環境で必要）

#### セキュリティヘッダー（50%）

- ✅ CORS設定
- ⚠️ CSP設定（推奨）
- ⚠️ その他のセキュリティヘッダー（推奨）

#### 脆弱性管理（40%）

- ✅ ORM使用（SQLインジェクション対策）
- ✅ 入力検証
- ⚠️ 定期的な依存関係スキャン（推奨）
- ❌ 自動化されたセキュリティテスト（未実装）

### 改善優先度

1. **高**: HTTPS/TLS設定（本番環境）
2. **高**: セキュリティヘッダー実装
3. **中**: 依存関係スキャン自動化
4. **中**: データベース暗号化
5. **低**: 多要素認証（MFA）

---

## 緊急連絡先

### インシデント発生時

**社内連絡先**:
- セキュリティ責任者: [連絡先]
- インフラ担当: [連絡先]
- 開発リード: [連絡先]

**外部連絡先**:
- ホスティングプロバイダー: [連絡先]
- セキュリティベンダー: [連絡先]

---

## 関連ドキュメント

### セキュリティドキュメント
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [02-authentication-security.md](./02-authentication-security.md) - 認証セキュリティ
- [03-authorization-security.md](./03-authorization-security.md) - 認可セキュリティ
- [04-data-protection.md](./04-data-protection.md) - データ保護
- [05-network-security.md](./05-network-security.md) - ネットワークセキュリティ
- [06-cors-and-headers.md](./06-cors-and-headers.md) - CORS とセキュリティヘッダー
- [07-password-policy.md](./07-password-policy.md) - パスワードポリシー
- [08-token-security.md](./08-token-security.md) - トークンセキュリティ
- [09-vulnerability-management.md](./09-vulnerability-management.md) - 脆弱性管理

---

**定期的にこのチェックリストを確認し、セキュリティ態勢を維持・向上させてください。**
