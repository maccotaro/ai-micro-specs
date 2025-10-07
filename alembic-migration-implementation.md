# Alembic自動マイグレーション実装サマリー

実装日: 2025-10-07

## 概要

ai-micro-serviceシステムの3つのバックエンドサービス（api-auth, api-user, api-admin）にAlembicマイグレーション機能を統合し、Docker Compose起動時に自動的にデータベーススキーマを初期化・更新する仕組みを実装しました。

## 実装内容

### 1. ai-micro-api-auth (新規導入)

**追加ファイル**:
- `alembic.ini` - Alembic設定ファイル
- `app/db/__init__.py` - dbパッケージ初期化
- `app/db/migrations/env.py` - Alembic環境設定
- `app/db/migrations/script.py.mako` - マイグレーションテンプレート
- `app/db/migrations/versions/001_initial_users_table.py` - 初期usersテーブル作成

**変更ファイル**:
- `docker-compose.yml` - 起動コマンドに`alembic upgrade head`を追加
- `CLAUDE.md` - Alembicコマンド説明を追加

**マイグレーション内容**:
- UUID extension有効化
- usersテーブル作成 (id, email, password_hash, roles, is_active等)
- emailカラムにユニーク制約とインデックス作成

### 2. ai-micro-api-admin (新規導入)

**追加ファイル**:
- `alembic.ini` - Alembic設定ファイル
- `app/db/migrations/env.py` - Alembic環境設定 (全モデルインポート)
- `app/db/migrations/script.py.mako` - マイグレーションテンプレート
- `app/db/migrations/versions/001_initial_schema.py` - 初期スキーマ作成
- `app/db/migrations/versions/002_add_kb_summary_features.py` - KB要約機能追加
- `app/db/migrations/versions/003_seed_default_prompt_templates.py` - 初期データ投入

**変更ファイル**:
- `docker-compose.yml` - 起動コマンドに`alembic upgrade head`を追加
- `CLAUDE.md` - Alembicコマンド説明を追加

**マイグレーション内容**:

**001_initial_schema.py**:
- pgvector extension有効化
- system_logs, login_logs, system_settings テーブル作成
- knowledge_bases, collections, documents テーブル作成
- prompt_templates テーブル作成
- langchain_pg_collection, langchain_pg_embedding テーブル作成
- トリガー関数 (update_updated_at_column) 作成

**002_add_kb_summary_features.py**:
- knowledge_basesに要約関連カラム追加 (meta_summary, meta_statistics等)
- query_classificationsテーブル作成

**003_seed_default_prompt_templates.py**:
- デフォルトプロンプトテンプレート2件投入
- デフォルトLangChainコレクション作成

### 3. ai-micro-api-user (既存改善)

**変更ファイル**:
- `docker-compose.yml` - 起動コマンドに`alembic upgrade head`を追加
- `CLAUDE.md` - Alembicコマンド説明を追加

**注**: このサービスはすでにAlembicが導入されていたため、Docker統合のみ実施。

## Docker統合パターン

全サービスで共通のパターンを適用:

```yaml
services:
  service-name:
    command: sh -c "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"
```

このコマンドにより:
1. コンテナ起動時にAlembicマイグレーションが自動実行される
2. マイグレーション完了後、FastAPIサーバーが起動する
3. 初回起動時にデータベースが自動的に初期化される

## Alembic設定の共通パターン

### alembic.ini
- `script_location = app/db/migrations`
- `sqlalchemy.url` - 各サービスのDB接続文字列 (authdb, apidb, admindb)

### env.py
- Base.metadataをtarget_metadataに設定
- 全モデルを明示的にインポート
- offline/online両モードに対応

### マイグレーションバージョン管理
- 3桁の連番 (001, 002, 003...)
- ファイル名: `{version}_{description}.py`

## 旧システムとの比較

### 旧システム (init.sql方式)
❌ 手動でSQLファイルを実行する必要がある
❌ スキーマ変更の履歴管理が困難
❌ ロールバックができない
❌ 初期データ投入と構造変更が混在
❌ サービス間で方式が統一されていない

### 新システム (Alembic方式)
✅ Docker Compose起動時に自動実行
✅ マイグレーション履歴がGitで管理される
✅ `alembic downgrade`でロールバック可能
✅ データ投入専用のマイグレーションファイルを作成可能
✅ 全サービスで統一された方式

## 開発者向け運用ガイド

### 新しいマイグレーションを作成する場合

```bash
# 各サービスディレクトリで実行

# 1. 空のマイグレーションを作成
poetry run alembic revision -m "add new column"

# 2. モデルから自動生成 (推奨)
poetry run alembic revision --autogenerate -m "add new table"

# 3. 生成されたファイルを確認・編集
# app/db/migrations/versions/XXX_*.py

# 4. マイグレーションをテスト
poetry run alembic upgrade head

# 5. 問題があればロールバック
poetry run alembic downgrade -1
```

### マイグレーション状態の確認

```bash
# 現在のバージョン
alembic current

# マイグレーション履歴
alembic history

# 未適用のマイグレーション
alembic heads
```

### データ投入用マイグレーション作成例

```python
def upgrade() -> None:
    """Insert seed data."""
    op.execute("""
        INSERT INTO table_name (column1, column2)
        VALUES ('value1', 'value2')
        ON CONFLICT (unique_column) DO NOTHING;
    """)

def downgrade() -> None:
    """Remove seed data."""
    op.execute("DELETE FROM table_name WHERE column1 = 'value1';")
```

## トラブルシューティング

### マイグレーションが実行されない
```bash
# コンテナログを確認
docker compose logs -f [service-name]

# データベース接続を確認
docker exec [service-name] alembic current
```

### マイグレーションのリセット
```bash
# 全てロールバック
docker exec -it [service-name] alembic downgrade base

# 再度適用
docker exec -it [service-name] alembic upgrade head
```

### 手動でデータベースを初期化したい場合
```bash
# PostgreSQLコンテナに接続
docker exec -it postgres psql -U postgres

# データベース削除・再作成
DROP DATABASE authdb;
CREATE DATABASE authdb;

# サービスを再起動（マイグレーションが自動実行される）
docker compose restart ai-micro-api-auth
```

## 今後の拡張

1. **CI/CDパイプライン統合**
   - デプロイ前にマイグレーションのdry-runを実行
   - マイグレーション適用の自動テスト

2. **本番環境向けの安全策**
   - マイグレーション適用前のバックアップ
   - ダウンタイムなしのマイグレーション戦略

3. **モニタリング**
   - マイグレーション実行時間の計測
   - 失敗時のアラート通知

## 参考リンク

- [Alembic公式ドキュメント](https://alembic.sqlalchemy.org/)
- [SQLAlchemy公式ドキュメント](https://www.sqlalchemy.org/)
- 各サービスのCLAUDE.md - Alembicコマンド詳細

## 実装完了チェックリスト

- [x] ai-micro-api-auth: Alembic環境セットアップ
- [x] ai-micro-api-auth: 初期マイグレーション作成
- [x] ai-micro-api-auth: Docker統合
- [x] ai-micro-api-admin: Alembic環境セットアップ
- [x] ai-micro-api-admin: init.sql→Alembicマイグレーション変換
- [x] ai-micro-api-admin: Docker統合
- [x] ai-micro-api-user: Docker統合
- [x] 全サービスのCLAUDE.md更新
- [x] 実装サマリードキュメント作成
