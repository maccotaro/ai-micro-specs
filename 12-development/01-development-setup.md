# 開発環境セットアップ

## 必要なツール

- **Docker Desktop**: 24.0以上
- **Node.js**: 20.x LTS
- **Python**: 3.11以上
- **Poetry**: 1.7以上
- **Git**: 2.40以上

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/your-org/ai-micro-service.git
cd ai-micro-service
```

### 2. インフラサービスの起動

```bash
# PostgreSQL
cd ai-micro-postgres
docker compose up -d

# Redis
cd ../ai-micro-redis
docker compose up -d
```

### 3. バックエンドサービス

#### 認証サービス

```bash
cd ai-micro-api-auth
poetry install
cp .env.example .env
poetry run uvicorn app.main:app --reload --port 8002
```

#### ユーザーAPIサービス

```bash
cd ai-micro-api-user
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8001
```

#### 管理APIサービス

```bash
cd ai-micro-api-admin
poetry install
cp .env.example .env
poetry run uvicorn app.main:app --reload --port 8003
```

### 4. フロントエンドサービス

#### ユーザーフロントエンド

```bash
cd ai-micro-front-user
npm install
cp .env.example .env.local
npm run dev
```

#### 管理フロントエンド

```bash
cd ai-micro-front-admin
npm install
cp .env.example .env.local
npm run dev
```

## アクセスURL

- User Frontend: http://localhost:3002
- Admin Frontend: http://localhost:3003
- Auth API: http://localhost:8002/docs
- User API: http://localhost:8001/docs
- Admin API: http://localhost:8003/docs

## トラブルシューティング

### ポート競合

```bash
# ポート使用状況確認
lsof -i :8002
kill -9 <PID>
```

### データベース接続エラー

```bash
# PostgreSQL 起動確認
docker ps | grep postgres
docker logs postgres
```

---

**関連**: [コーディング規約](./02-coding-standards.md), [デバッグガイド](./05-debugging-guide.md)