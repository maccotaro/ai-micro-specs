# トラブルシューティング

**バージョン**: 1.0
**最終更新**: 2025-09-30
**ステータス**: ✅ 確定

## 概要

本ドキュメントでは、ai-micro-service システムで発生する一般的な問題とその解決方法を提供します。

## トラブルシューティングの基本フロー

```
1. 症状の確認
   └→ 何が起きているか？
   └→ いつから起きているか？
   └→ 誰が影響を受けているか？

2. ログの確認
   └→ エラーメッセージは？
   └→ スタックトレースは？

3. メトリクスの確認
   └→ リソース使用状況は？
   └→ エラー率は？

4. 原因の特定
   └→ 最近の変更は？
   └→ 外部依存は正常か？

5. 対処
   └→ 一時対応（ワークアラウンド）
   └→ 恒久対応（根本解決）

6. 記録
   └→ インシデントレポート作成
   └→ 再発防止策の検討
```

---

## インフラストラクチャ問題

### PostgreSQL

#### 問題: PostgreSQL に接続できない

**症状**:

```
sqlalchemy.exc.OperationalError: could not connect to server
FATAL: password authentication failed
```

**確認手順**:

```bash
# 1. PostgreSQLコンテナの状態確認
docker ps | grep postgres
docker logs postgres --tail 50

# 2. PostgreSQL接続テスト
docker exec postgres psql -U postgres -c "SELECT 1"

# 3. 環境変数確認
docker exec <service-name> env | grep DATABASE_URL

# 4. ネットワーク確認
docker exec <service-name> ping postgres
docker exec <service-name> nc -zv postgres 5432
```

**原因と対処法**:

| 原因 | 対処法 |
|------|--------|
| PostgreSQLコンテナが停止 | `docker compose up -d` で再起動 |
| パスワードが間違っている | `.env`ファイルの`POSTGRES_PASSWORD`を確認 |
| DATABASE_URLが間違っている | 正しいフォーマットを確認: `postgresql://user:pass@host:5432/db` |
| ネットワーク分離 | Dockerネットワーク設定を確認 |

#### 問題: PostgreSQL接続数上限に達する

**症状**:

```
FATAL: sorry, too many clients already
remaining connection slots are reserved for non-replication superuser connections
```

**確認手順**:

```bash
# 現在の接続数確認
docker exec postgres psql -U postgres -c \
  "SELECT count(*) FROM pg_stat_activity;"

# 最大接続数確認
docker exec postgres psql -U postgres -c \
  "SHOW max_connections;"

# 接続の詳細
docker exec postgres psql -U postgres -c \
  "SELECT datname, usename, state, count(*) FROM pg_stat_activity GROUP BY datname, usename, state;"
```

**原因と対処法**:

| 原因 | 対処法 |
|------|--------|
| コネクションリークがある | アプリケーションで接続をクローズしているか確認 |
| max_connectionsが少ない | `postgresql.conf`で`max_connections=200`に増やす |
| 不要な接続が残っている | `SELECT pg_terminate_backend(pid)` でアイドル接続を終了 |

```sql
-- アイドル接続を終了（5分以上）
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < now() - interval '5 minutes'
  AND pid != pg_backend_pid();
```

#### 問題: スロークエリが多い

**症状**:

- レスポンスタイムが遅い
- データベースCPU使用率が高い

**確認手順**:

```bash
# スロークエリログの確認
docker exec postgres tail -f /var/log/postgresql/postgresql.log

# 実行中のクエリ確認
docker exec postgres psql -U postgres -c \
  "SELECT pid, now() - query_start as duration, query
   FROM pg_stat_activity
   WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%'
   ORDER BY duration DESC;"

# クエリ統計（pg_stat_statementsが有効な場合）
docker exec postgres psql -U postgres -d authdb -c \
  "SELECT query, calls, mean_exec_time, total_exec_time
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;"
```

**対処法**:

```sql
-- インデックス作成
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_profiles_user_id ON profiles(user_id);

-- 統計情報更新
ANALYZE users;
ANALYZE profiles;

-- バキューム実行
VACUUM ANALYZE;
```

#### 問題: データベース接続が突然切れる

**症状**:

```
lost connection to database server
server closed the connection unexpectedly
```

**確認手順**:

```bash
# PostgreSQLログ確認
docker logs postgres --tail 100 | grep -i "error\|fatal\|crash"

# OOM Killerのログ確認（メモリ不足）
dmesg | grep -i "out of memory"

# システムリソース確認
docker stats postgres
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| メモリ不足でOOM Killed | メモリ制限を増やす、不要なクエリを削減 |
| idle_in_transaction_session_timeout | タイムアウト設定を調整 |
| ネットワーク不安定 | ネットワーク設定を確認 |

---

### Redis

#### 問題: Redis に接続できない

**症状**:

```
redis.exceptions.ConnectionError: Error connecting to Redis
Connection refused
```

**確認手順**:

```bash
# 1. Redisコンテナの状態確認
docker ps | grep redis
docker logs redis --tail 50

# 2. Redis接続テスト
docker exec redis redis-cli -a "${REDIS_PASSWORD}" ping

# 3. 環境変数確認
docker exec <service-name> env | grep REDIS_URL

# 4. ネットワーク確認
docker exec <service-name> ping redis
docker exec <service-name> nc -zv redis 6379
```

**対処法**:

```bash
# Redisコンテナ再起動
cd ai-micro-redis
docker compose restart

# パスワード確認
echo $REDIS_PASSWORD

# 接続文字列確認
# 正しい形式: redis://:password@host:6379
```

#### 問題: Redis メモリ不足

**症状**:

```
OOM command not allowed when used memory > 'maxmemory'
```

**確認手順**:

```bash
# メモリ使用状況確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory

# 主要メトリクス
# - used_memory_human: 現在の使用量
# - maxmemory_human: 最大メモリ
# - mem_fragmentation_ratio: フラグメンテーション率

# キー数確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" DBSIZE

# 大きいキーを特定
docker exec redis redis-cli -a "${REDIS_PASSWORD}" --bigkeys
```

**対処法**:

```bash
# 1. maxmemoryを増やす（redis.conf）
docker exec redis redis-cli -a "${REDIS_PASSWORD}" CONFIG SET maxmemory 2gb

# 2. 削除ポリシーを設定
docker exec redis redis-cli -a "${REDIS_PASSWORD}" CONFIG SET maxmemory-policy allkeys-lru

# 3. 不要なキーを削除
docker exec redis redis-cli -a "${REDIS_PASSWORD}" FLUSHDB

# 4. TTLを短くする（アプリケーション側）
# キャッシュのTTLを1時間 → 30分に短縮
```

#### 問題: キャッシュヒット率が低い

**症状**:

- データベースへのクエリが増加
- レスポンスタイムが遅い

**確認手順**:

```bash
# キャッシュヒット率確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO stats | grep keyspace

# 計算: hit_rate = keyspace_hits / (keyspace_hits + keyspace_misses)
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| TTLが短すぎる | TTLを延長（例: 5分 → 15分） |
| キャッシュウォームアップ不足 | アプリケーション起動時にキャッシュを事前ロード |
| キャッシュキーの設計が悪い | キャッシュ戦略を見直す |
| メモリ不足で削除されている | maxmemoryを増やす |

---

## アプリケーション問題

### Auth Service

#### 問題: ログインできない

**症状**:

- 401 Unauthorized
- Invalid credentials

**確認手順**:

```bash
# 1. Auth Serviceのログ確認
docker logs auth-service --tail 50

# 2. データベース接続確認
docker exec auth-service curl -f http://localhost:8002/health

# 3. ユーザーが存在するか確認
docker exec postgres psql -U postgres -d authdb -c \
  "SELECT id, username, is_active FROM users WHERE username='testuser';"

# 4. 手動でログインテスト
curl -X POST http://localhost:8002/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}'
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| パスワードが間違っている | パスワードリセット |
| ユーザーが無効化されている | `is_active=true`に更新 |
| データベース接続エラー | PostgreSQL接続を確認 |
| Redis接続エラー | Redis接続を確認 |

#### 問題: JWT 検証失敗

**症状**:

```
JWT verification failed
Invalid signature
Token expired
```

**確認手順**:

```bash
# 1. JWKS エンドポイント確認
curl http://localhost:8002/.well-known/jwks.json

# 2. RSA鍵ペア確認
docker exec auth-service ls -la /app/keys/
# private_key.pem と public_key.pem が存在するか

# 3. JWT設定確認
docker exec auth-service env | grep JWT_

# 4. トークンをデコード（jwt.ioなどで）
# - exp（有効期限）が切れていないか
# - iss（発行者）が正しいか
# - aud（対象）が正しいか
```

**対処法**:

```bash
# RSA鍵ペアが存在しない場合は生成
cd ai-micro-api-auth/keys/

openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# コンテナ再起動
docker compose restart
```

#### 問題: トークンリフレッシュ失敗

**症状**:

```
Refresh token is invalid or expired
Refresh token not found in database
```

**確認手順**:

```bash
# リフレッシュトークンの確認（Redis）
docker exec redis redis-cli -a "${REDIS_PASSWORD}" KEYS "refresh_token:*"

# 特定トークンの確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" GET "refresh_token:<token_id>"

# データベースのトークン確認
docker exec postgres psql -U postgres -d authdb -c \
  "SELECT id, user_id, expires_at FROM refresh_tokens WHERE token='<token>' LIMIT 1;"
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| トークンが期限切れ | 再ログインが必要 |
| Redisからトークンが削除された | Redisの永続化設定を確認 |
| トークンがブラックリスト化されている | ログアウト後は再ログイン必要 |

---

### User API / Admin API

#### 問題: API が応答しない（タイムアウト）

**症状**:

```
Request timeout
504 Gateway Timeout
```

**確認手順**:

```bash
# 1. サービスの状態確認
docker ps | grep -E "user-api|admin-api"

# 2. ヘルスチェック
curl -f http://localhost:8001/health
curl -f http://localhost:8003/health

# 3. ログ確認
docker logs user-api --tail 100
docker logs admin-api --tail 100

# 4. リソース使用状況
docker stats user-api admin-api

# 5. 処理中のリクエスト確認（メトリクスエンドポイント）
curl http://localhost:8001/metrics | grep http_requests_in_progress
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| データベースクエリが遅い | スロークエリを最適化 |
| 外部API呼び出しが遅い | タイムアウト設定を追加 |
| メモリ不足 | メモリ制限を増やす、メモリリークを確認 |
| CPU負荷が高い | スケーリング、非効率な処理の改善 |

#### 問題: プロフィール取得でエラー

**症状**:

```
Profile not found
Database connection error
```

**確認手順**:

```bash
# 1. プロフィールがDBに存在するか確認
docker exec postgres psql -U postgres -d apidb -c \
  "SELECT id, user_id, first_name, last_name FROM profiles WHERE user_id='<user_id>';"

# 2. キャッシュ確認
docker exec redis redis-cli -a "${REDIS_PASSWORD}" GET "profile:<user_id>"

# 3. ログ確認
docker logs user-api --tail 50 | grep -i "profile"
```

**対処法**:

```bash
# プロフィールが存在しない場合は作成
docker exec postgres psql -U postgres -d apidb -c \
  "INSERT INTO profiles (user_id, first_name, last_name) VALUES ('<user_id>', 'First', 'Last');"

# キャッシュをクリア
docker exec redis redis-cli -a "${REDIS_PASSWORD}" DEL "profile:<user_id>"
```

#### 問題: ドキュメントアップロード失敗（Admin API）

**症状**:

```
File upload failed
OCR processing error
```

**確認手順**:

```bash
# 1. Admin APIのログ確認
docker logs admin-api --tail 100 | grep -i "upload\|ocr"

# 2. ディスク容量確認
docker exec admin-api df -h

# 3. アップロードディレクトリのパーミッション確認
docker exec admin-api ls -la /app/uploads/

# 4. データベース確認
docker exec postgres psql -U postgres -d admindb -c \
  "SELECT id, filename, status FROM documents ORDER BY created_at DESC LIMIT 10;"
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| ディスク容量不足 | 古いファイルを削除、ボリューム拡張 |
| パーミッションエラー | `chmod 755 /app/uploads/` |
| ファイルサイズ超過 | `MAX_FILE_SIZE`を増やす |
| OCRライブラリエラー | 依存関係を再インストール |

---

## フロントエンド問題

### User Frontend / Admin Frontend

#### 問題: ページが表示されない

**症状**:

- 500 Internal Server Error
- ページが真っ白

**確認手順**:

```bash
# 1. フロントエンドのログ確認
docker logs user-frontend --tail 100
docker logs admin-frontend --tail 100

# 2. Next.jsプロセス確認
docker exec user-frontend ps aux | grep node

# 3. バックエンド接続確認
docker exec user-frontend curl -f http://auth-service:8002/health
docker exec user-frontend curl -f http://user-api:8001/health

# 4. ブラウザのコンソールエラー確認
# DevTools → Console
```

**対処法**:

```bash
# Next.jsアプリケーション再起動
docker compose restart user-frontend

# キャッシュクリア
docker exec user-frontend rm -rf .next/cache

# 再ビルド（開発環境）
docker compose down
docker compose up -d --build
```

#### 問題: ログイン後にリダイレクトされない

**症状**:

- ログイン成功後、ページが変わらない
- クッキーが設定されない

**確認手順**:

```bash
# 1. BFFログ確認
docker logs user-frontend --tail 50 | grep -i "login\|cookie"

# 2. ブラウザのNetwork タブでレスポンス確認
# - Set-Cookie ヘッダーが含まれているか
# - httpOnly, Secure, SameSite 属性は正しいか

# 3. 手動でAPIテスト
curl -v -X POST http://localhost:3002/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}'
```

**対処法**:

| 原因 | 対処法 |
|------|--------|
| CORS設定が間違っている | `credentials: 'include'` を確認 |
| Cookie属性が間違っている | `httpOnly`, `sameSite` を確認 |
| HTTPSが必要（Secure属性） | 開発環境では`Secure`を無効化 |

#### 問題: APIリクエストが認証エラー

**症状**:

```
401 Unauthorized
JWT token is missing or invalid
```

**確認手順**:

```bash
# 1. Cookieが設定されているか確認（ブラウザ）
# DevTools → Application → Cookies

# 2. BFFがトークンを送信しているか確認
docker logs user-frontend --tail 50 | grep -i "authorization"

# 3. トークンが有効か確認
# jwt.io でトークンをデコード
```

**対処法**:

```typescript
// BFFでトークンを正しく転送
const response = await fetch(`${API_SERVER_URL}/api/users/profile`, {
  headers: {
    'Authorization': `Bearer ${accessToken}`,
  },
});
```

---

## ネットワーク問題

### サービス間通信エラー

#### 問題: サービス間で通信できない

**症状**:

```
Connection refused
Name or service not known
```

**確認手順**:

```bash
# 1. Dockerネットワーク確認
docker network ls
docker network inspect <network-name>

# 2. コンテナのネットワーク接続確認
docker inspect <container-name> | grep -A 10 Networks

# 3. 名前解決確認
docker exec <container-name> nslookup postgres
docker exec <container-name> ping postgres

# 4. ポート確認
docker exec <container-name> nc -zv postgres 5432
```

**対処法**:

```yaml
# docker-compose.ymlでネットワーク設定
networks:
  app-network:
    driver: bridge

services:
  auth-service:
    networks:
      - app-network

  postgres:
    networks:
      - app-network
```

#### 問題: ホストマシンからコンテナにアクセスできない

**症状**:

```bash
curl http://localhost:8002/health
# Connection refused
```

**確認手順**:

```bash
# 1. ポートマッピング確認
docker ps | grep auth-service
# PORTS列に "0.0.0.0:8002->8002/tcp" が表示されるか

# 2. コンテナ内からアクセス確認
docker exec auth-service curl http://localhost:8002/health

# 3. ファイアウォール確認
sudo ufw status
```

**対処法**:

```yaml
# docker-compose.yml
services:
  auth-service:
    ports:
      - "8002:8002"  # ホスト:コンテナ
```

---

## パフォーマンス問題

### レスポンスタイムが遅い

**確認手順**:

```bash
# 1. メトリクス確認（Prometheus）
curl http://localhost:9090/api/v1/query?query=http_request_duration_seconds

# 2. ボトルネック特定
# - データベースクエリ
# - 外部API呼び出し
# - CPU/メモリ使用率

# 3. トレーシング（OpenTelemetry等）
# リクエストの各ステップの処理時間を確認
```

**対処法**:

- データベースインデックス追加
- N+1クエリ問題の解決
- キャッシュの活用
- 非同期処理の導入

### メモリリーク

**症状**:

- メモリ使用量が増加し続ける
- OOM Killer でコンテナが停止

**確認手順**:

```bash
# メモリ使用状況の推移を監視
docker stats --no-stream auth-service

# Python メモリプロファイリング
pip install memory_profiler
python -m memory_profiler app/main.py
```

**対処法**:

- コネクションプールの設定確認
- グローバル変数への大きなオブジェクト保存を避ける
- ガベージコレクションの確認

---

## デバッグツール

### 有用なコマンド

```bash
# コンテナ内でシェル起動
docker exec -it <container-name> /bin/bash

# リアルタイムログ表示
docker logs -f <container-name>

# リソース使用状況
docker stats

# ネットワーク診断
docker network inspect <network-name>

# ボリューム確認
docker volume ls
docker volume inspect <volume-name>

# イメージ確認
docker images
docker history <image-name>

# すべてのコンテナ確認（停止含む）
docker ps -a

# システム全体の情報
docker system info
docker system df
```

### ログフィルタリング

```bash
# エラーのみ表示
docker logs <container-name> 2>&1 | grep -i "error"

# 特定の文字列を含む行
docker logs <container-name> | grep "login"

# 時刻指定
docker logs --since 1h <container-name>
docker logs --until 2025-09-30T12:00:00 <container-name>

# 行数指定
docker logs --tail 100 <container-name>
```

---

## 緊急対応チェックリスト

### 重大障害発生時

- [ ] インシデント管理チケットを作成
- [ ] 影響範囲を特定（全ユーザー？特定機能？）
- [ ] ステークホルダーに通知
- [ ] ログとメトリクスを確認
- [ ] 一時的な回避策を実施（再起動など）
- [ ] 根本原因を調査
- [ ] 恒久対策を実施
- [ ] ポストモーテム（振り返り）を実施
- [ ] 再発防止策を文書化

---

## 参考資料

- [01-startup-procedure.md](./01-startup-procedure.md) - システム起動手順
- [02-shutdown-procedure.md](./02-shutdown-procedure.md) - システム停止手順
- [03-monitoring.md](./03-monitoring.md) - 監視設計
- [04-logging.md](./04-logging.md) - ログ設計
- [05-alerting.md](./05-alerting.md) - アラート設計
- [../06-database/10-backup-restore.md](../06-database/10-backup-restore.md) - バックアップ・リストア

---

**変更履歴**:

- 2025-09-30: 初版作成