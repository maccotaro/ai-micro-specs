# AI Micro Service - 設計書ドキュメント

マイクロサービスベースの認証、ユーザー管理、ドキュメント処理システムの設計書リポジトリ

## 📚 ドキュメント索引

### 🌐 システム全体
- **[00-overview/](./00-overview/)** - システム全体のアーキテクチャと連携
  - システム全体アーキテクチャ設計書
  - マイクロサービス連携設計書
  - インフラ構成設計書
  - 技術スタック一覧

### 🔐 バックエンドサービス
- **[01-auth-service/](./01-auth-service/)** - 認証サービス（ai-micro-api-auth）
  - 認証API仕様書
  - JWT設計書
  - authdb データベース設計書

- **[02-user-api/](./02-user-api/)** - ユーザーAPI（ai-micro-api-user）
  - ユーザーAPI仕様書
  - apidb データベース設計書
  - データ整合性設計書

- **[03-admin-api/](./03-admin-api/)** - 管理API（ai-micro-api-admin）
  - 管理API仕様書
  - ドキュメント処理設計書
  - OCR機能設計書
  - admindb データベース設計書

- **[04-mcp-server/](./04-mcp-server/)** - MCP Admin Service（ai-micro-mcp-admin）
  - MCPサーバー概要・アーキテクチャ
  - MCPツール仕様書（search_documents、get_knowledge_base_summary、normalize_ocr_text）
  - api-admin統合設計書
  - JWT認証・RBAC設計
  - パフォーマンス最適化（並行処理・接続プール）

### 🖥️ フロントエンドサービス
- **[05-user-frontend/](./05-user-frontend/)** - ユーザーフロントエンド（ai-micro-front-user）
  - 画面設計書
  - BFF API連携設計書
  - コンポーネント設計書

- **[06-admin-frontend/](./06-admin-frontend/)** - 管理フロントエンド（ai-micro-front-admin）
  - 画面設計書
  - ドキュメント管理機能設計書
  - OCR結果表示UI設計書

### 🗄️ インフラサービス
- **[07-database/](./07-database/)** - PostgreSQLデータベース（ai-micro-postgres）
  - データベース構成設計書
  - スキーマ設計書（authdb/apidb/admindb）
  - ER図
  - マイグレーション管理

- **[08-redis/](./08-redis/)** - Redisキャッシュ（ai-micro-redis）
  - データ構造設計書
  - キャッシュ戦略設計書
  - セッション管理設計書

### 🔗 横断的設計
- **[09-integration/](./09-integration/)** - サービス間連携
  - サービス間通信設計書
  - 認証フロー統合設計書
  - データ整合性設計書
  - エラー伝播設計書

- **[10-api-contracts/](./10-api-contracts/)** - APIインターフェース定義
  - エンドポイント対応表
  - データモデル定義
  - OpenAPI仕様書
  - 契約テスト仕様

- **[11-security/](./11-security/)** - セキュリティ設計
  - セキュリティ全体方針
  - 認証・認可セキュリティ
  - データ保護設計
  - 脆弱性管理

- **[12-operations/](./12-operations/)** - 運用ガイド
  - システム起動・停止手順
  - 監視設計書
  - トラブルシューティング
  - バックアップ・リストア

### 🛠️ 開発・運用
- **[13-development/](./13-development/)** - 開発ガイド
  - 開発環境セットアップ
  - コーディング規約
  - Gitワークフロー
  - テストガイド

- **[14-deployment/](./14-deployment/)** - デプロイガイド
  - デプロイ概要
  - Docker Compose設定
  - 環境変数一覧
  - CI/CDパイプライン

- **[15-performance/](./15-performance/)** - パフォーマンス設計
  - パフォーマンス全体方針
  - 負荷テスト
  - 最適化ガイド
  - スケーラビリティ設計

### 📝 その他
- **[16-testing/](./16-testing/)** - テスト設計
  - テスト戦略
  - ユニットテスト・統合テスト
  - E2Eテスト
  - 契約テスト

- **[17-rag-system/](./17-rag-system/)** - エンタープライズRAGシステム
  - 7段階パイプライン設計
  - Atlas層・スパース層・Dense層設計
  - ハイブリッド検索（RRF統合）
  - Re-ranker設計（BM25 + Cross-Encoder）
  - MCPサーバー統合

- **[18-changelog/](./18-changelog/)** - 変更履歴
  - システム変更履歴
  - 重要な修正の記録

- **[templates/](./templates/)** - ドキュメントテンプレート
  - 各種設計書のテンプレート

---

## 📖 推奨読書順序

### 🔰 初めて読む方
1. `00-overview/01-system-architecture.md` - システム全体像を把握
2. `00-overview/02-microservices-integration.md` - サービス間連携を理解
3. `09-api-contracts/02-interface-matrix.md` - API一覧を確認
4. 各サービスの `01-overview.md` - 個別サービスの概要

### 💻 バックエンド開発者
1. **システム全体**（上記の初めて読む方と同じ）
2. `01-auth-service/` - 認証の仕組みを理解
3. `09-integration/02-authentication-flow.md` - 認証フローを確認
4. `10-api-contracts/` - API仕様を確認
5. `04-mcp-server/` - MCPサーバー統合（RAG検索機能開発時）
6. `17-rag-system/` - エンタープライズRAGシステム（検索機能開発時）
7. 開発対象サービスのドキュメント

### 🎨 フロントエンド開発者
1. **システム全体**（上記の初めて読む方と同じ）
2. `05-user-frontend/03-api-integration.md` または `06-admin-frontend/03-api-integration.md` - BFFパターンを理解
3. `10-api-contracts/` - API仕様を確認
4. `09-integration/02-authentication-flow.md` - 認証フローを確認
5. フロントエンド詳細ドキュメント

### 🔧 インフラ担当者
1. `00-overview/03-infrastructure.md` - インフラ全体像
2. `07-database/` - データベース設計
3. `08-redis/` - キャッシュ設計
4. `12-operations/` - 運用手順
5. `14-deployment/` - デプロイ手順

### 🛡️ セキュリティ担当者
1. `11-security/01-security-overview.md` - セキュリティ全体方針
2. `01-auth-service/03-jwt-design.md` - JWT設計
3. `04-mcp-server/04-authentication.md` - MCPサーバーJWT認証
4. `09-integration/02-authentication-flow.md` - 認証フロー
5. `11-security/` 配下のすべてのドキュメント

---

## 🔄 ドキュメント更新ルール

### 更新が必要なタイミング
1. **コード変更時**: 対応するドキュメントも必ず更新する
2. **アーキテクチャ変更時**: 関連するすべてのドキュメントを更新
3. **API変更時**: API仕様書とインターフェース定義を更新
4. **重要な変更**: `16-changelog/` に記録を残す

### 更新手順
1. 変更内容に対応するドキュメントを特定
2. ドキュメントを更新（日本語で記述）
3. 図の更新が必要な場合は元ファイル（.drawio等）も保管
4. 変更履歴に記録（重要な変更のみ）
5. プルリクエストでレビュー

### ドキュメントバージョン管理
- 各ドキュメントに更新日を記載
- 重要なドキュメントにはバージョン番号を付与
- レビュー済みドキュメントには承認者を記載

---

## 📝 ドキュメント記述規約

### 形式
- **マークダウン形式**（GitHub Flavored Markdown）
- **言語**: 日本語で記述
- **ファイル名**: 小文字とハイフンを使用（例：`api-specification.md`）

### 構成
各ドキュメントには以下の情報を含める：
```markdown
# タイトル

**更新日**: YYYY-MM-DD
**バージョン**: X.Y
**レビュー**: 承認者名（承認日）

## 概要
...

## 詳細
...
```

### 図の作成
- **推奨ツール**: PlantUML、Mermaid、draw.io
- **保存形式**: PNG/SVG + 元ファイル（.puml, .drawio等）
- **配置**: 各カテゴリの `diagrams/` ディレクトリ

### コードサンプル
- 実際のコードから抜粋する
- シンタックスハイライトを使用
- 説明コメントを日本語で追加

---

## 🚀 クイックスタート

### ドキュメントの検索
```bash
# 特定のキーワードでドキュメントを検索
grep -r "認証フロー" .

# ファイル名で検索
find . -name "*authentication*"
```

### ドキュメントの新規作成
1. 適切なカテゴリを選択
2. `templates/` からテンプレートをコピー
3. 内容を記述
4. カテゴリのREADMEにリンクを追加

### ドキュメントのレビュー
1. 技術的正確性の確認
2. 記述の明瞭性の確認
3. 他ドキュメントとの整合性確認
4. 図の視認性確認

---

## 📞 問い合わせ・貢献

### 質問・フィードバック
- GitHubのIssueで質問や改善提案を投稿
- ドキュメントの不明点や誤りを報告

### コントリビューション
1. リポジトリをフォーク
2. 変更をコミット
3. プルリクエストを作成
4. レビューを受ける

詳細は `12-development/06-contribution-guide.md` を参照

---

## 📋 プロジェクト情報

- **プロジェクト名**: AI Micro Service
- **リポジトリ**: ai-micro-docs
- **作成日**: 2025-09-30
- **言語**: 日本語
- **ライセンス**: MIT License

---

**このドキュメントリポジトリを活用して、システムの理解を深め、開発を加速させましょう！**