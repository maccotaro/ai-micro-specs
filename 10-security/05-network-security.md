# ネットワークセキュリティ

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [Dockerネットワーク分離](#dockerネットワーク分離)
- [ポート公開戦略](#ポート公開戦略)
- [host.docker.internal通信](#hostdockerinternal通信)
- [ファイアウォールルール](#ファイアウォールルール)
- [VPC/サブネット設計](#vpcサブネット設計)

---

## 概要

### ネットワークセキュリティの重要性

マイクロサービスアーキテクチャでは、複数のサービスがネットワーク経由で通信します。適切なネットワークセキュリティは、以下を実現します:

1. **サービス分離**: 各サービスを論理的・物理的に分離
2. **最小権限の原則**: 必要な通信のみを許可
3. **攻撃面の縮小**: 不要なポート・プロトコルを閉鎖
4. **通信の暗号化**: TLS/HTTPSによる盗聴防止

### ネットワークアーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  外部ネットワーク（インターネット）                             │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS (443)
                         ↓
        ┌────────────────────────────────┐
        │  ロードバランサー / リバースプロキシ  │
        │  (Nginx, AWS ALB, etc.)        │
        └────────┬───────────────┬────────┘
                 │               │
        ┌────────┴────┐    ┌────┴─────────┐
        │User Frontend│    │Admin Frontend│
        │  (Port 3002)│    │  (Port 3003) │
        └────────┬────┘    └─────┬────────┘
                 │               │
                 ↓               ↓
        ┌─────────────────────────────────┐
        │  Docker Network (ai-micro-net)  │
        ├─────────────────────────────────┤
        │                                 │
        │  ┌──────────┐  ┌──────────┐   │
        │  │Auth API  │  │User API  │   │
        │  │(8002)    │  │(8001)    │   │
        │  └────┬─────┘  └────┬─────┘   │
        │       │             │          │
        │       │  ┌──────────┴─────┐   │
        │       │  │Admin API       │   │
        │       │  │(8003)          │   │
        │       │  └────┬───────────┘   │
        │       │       │               │
        │  ┌────┴───────┴─────┐         │
        │  │    PostgreSQL    │         │
        │  │    (5432)        │         │
        │  └──────────────────┘         │
        │                               │
        │  ┌──────────────────┐         │
        │  │      Redis       │         │
        │  │     (6379)       │         │
        │  └──────────────────┘         │
        │                               │
        └─────────────────────────────────┘
```

---

## Dockerネットワーク分離

### Dockerネットワークの種類

ai-micro-service システムは、Docker のブリッジネットワークを使用してサービスを分離します。

**ネットワーク種類**:

| 種類 | 説明 | 使用状況 |
|-----|------|---------|
| bridge | デフォルトブリッジネットワーク | ❌ 使用しない |
| user-defined bridge | カスタムブリッジネットワーク | ✅ 推奨 |
| host | ホストネットワーク直接使用 | ❌ セキュリティリスク |
| none | ネットワーク無効 | ❌ 通信不可 |

### カスタムネットワーク作成

**推奨設定**:

```bash
# カスタムネットワーク作成
docker network create ai-micro-net

# ネットワーク確認
docker network ls
docker network inspect ai-micro-net
```

### docker-compose ネットワーク設定

**ファイル**: `docker-compose.yml`

```yaml
version: '3.9'

services:
  postgres:
    image: postgres:15
    container_name: ai-micro-postgres
    networks:
      - ai-micro-net
    ports:
      - "5432:5432"  # 開発環境のみ公開

  redis:
    image: redis:7
    container_name: ai-micro-redis
    networks:
      - ai-micro-net
    ports:
      - "6379:6379"  # 開発環境のみ公開

  auth-service:
    build: ./ai-micro-api-auth
    container_name: ai-micro-api-auth
    networks:
      - ai-micro-net
    ports:
      - "8002:8000"
    depends_on:
      - postgres
      - redis

networks:
  ai-micro-net:
    driver: bridge
```

### ネットワーク分離のメリット

1. **サービス間通信の制限**:
   - 同じネットワーク内のサービスのみ通信可能
   - 外部からの直接アクセスを防止

2. **DNS解決**:
   - コンテナ名で相互解決可能
   - `http://auth-service:8000` で接続

3. **セキュリティ境界**:
   - ネットワーク単位でファイアウォールルール適用可能

---

## ポート公開戦略

### ポートマッピング原則

**開発環境**:
- ✅ デバッグ用にポート公開
- ✅ 直接接続でのテスト容易

**本番環境**:
- ❌ データベース・Redisポートを公開しない
- ✅ APIサービスのみロードバランサー経由で公開

### ポート構成

| サービス | コンテナポート | ホストポート | 公開範囲 |
|---------|------------|-----------|---------|
| User Frontend | 3000 | 3002 | ✅ インターネット |
| Admin Frontend | 3000 | 3003 | ✅ インターネット |
| Auth Service | 8000 | 8002 | ⚠️ 内部のみ |
| User API | 8000 | 8001 | ⚠️ 内部のみ |
| Admin API | 8000 | 8003 | ⚠️ 内部のみ |
| PostgreSQL | 5432 | 5432 | ❌ 公開しない |
| Redis | 6379 | 6379 | ❌ 公開しない |

### 本番環境ポート設定

```yaml
# 本番環境用 docker-compose.prod.yml
version: '3.9'

services:
  postgres:
    image: postgres:15
    networks:
      - ai-micro-net
    # ポート公開しない
    expose:
      - "5432"

  redis:
    image: redis:7
    networks:
      - ai-micro-net
    # ポート公開しない
    expose:
      - "6379"

  auth-service:
    image: auth-service:latest
    networks:
      - ai-micro-net
    # 内部ポートのみ
    expose:
      - "8000"

networks:
  ai-micro-net:
    driver: bridge
```

---

## host.docker.internal通信

### host.docker.internal の使用

Docker コンテナからホストマシン上のサービスにアクセスする際に使用します。

**使用例**:

```bash
# Auth Service から PostgreSQL に接続
DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/authdb

# User API Service から Auth Service の JWKS を取得
JWKS_URL=http://host.docker.internal:8002/.well-known/jwks.json
```

### セキュリティ考慮事項

**開発環境**:
- ✅ ホストとコンテナ間の簡単な通信
- ✅ デバッグが容易

**本番環境**:
- ❌ `host.docker.internal` は使用しない
- ✅ サービス名で直接通信

**本番環境設定**:

```bash
# コンテナ名で接続
DATABASE_URL=postgresql://postgres:password@postgres:5432/authdb
REDIS_URL=redis://:password@redis:6379
JWKS_URL=http://auth-service:8000/.well-known/jwks.json
```

### Docker Compose での名前解決

```yaml
services:
  auth-service:
    container_name: auth-service
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/authdb
      REDIS_URL: redis://:password@redis:6379

  user-api:
    container_name: user-api
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/apidb
      JWKS_URL: http://auth-service:8000/.well-known/jwks.json
```

---

## ファイアウォールルール

### iptables ルール（Linux）

**基本ポリシー**:

```bash
# デフォルトポリシー
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ループバック許可
iptables -A INPUT -i lo -j ACCEPT

# 確立済み接続許可
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH 許可（管理用）
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# HTTPS 許可（フロントエンド）
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# HTTP 許可（開発環境のみ）
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# Docker ネットワーク許可
iptables -A INPUT -i docker0 -j ACCEPT

# データベース・Redis へのホストからのアクセス拒否（開発環境除く）
iptables -A INPUT -p tcp --dport 5432 -s 0.0.0.0/0 -j DROP
iptables -A INPUT -p tcp --dport 6379 -s 0.0.0.0/0 -j DROP
```

### AWS Security Group ルール

**フロントエンドセキュリティグループ**:

| タイプ | プロトコル | ポート範囲 | ソース | 説明 |
|-------|----------|----------|--------|------|
| HTTPS | TCP | 443 | 0.0.0.0/0 | インターネットからのHTTPS |
| HTTP | TCP | 80 | 0.0.0.0/0 | HTTPからHTTPSへリダイレクト |

**APIサービスセキュリティグループ**:

| タイプ | プロトコル | ポート範囲 | ソース | 説明 |
|-------|----------|----------|--------|------|
| Custom TCP | TCP | 8000-8003 | フロントエンドSG | BFFからのAPI呼び出し |

**データベースセキュリティグループ**:

| タイプ | プロトコル | ポート範囲 | ソース | 説明 |
|-------|----------|----------|--------|------|
| PostgreSQL | TCP | 5432 | APISG | APIサービスからの接続のみ |

**Redisセキュリティグループ**:

| タイプ | プロトコル | ポート範囲 | ソース | 説明 |
|-------|----------|----------|--------|------|
| Custom TCP | TCP | 6379 | APISG | APIサービスからの接続のみ |

---

## VPC/サブネット設計

### 本番環境ネットワークアーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│  VPC: 10.0.0.0/16                                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │  パブリックサブネット（10.0.1.0/24）            │     │
│  │  ┌─────────────────────────────────────┐      │     │
│  │  │  Application Load Balancer (ALB)    │      │     │
│  │  │  Internet Gateway                   │      │     │
│  │  └─────────────────────────────────────┘      │     │
│  └───────────┬───────────────────────────────────┘     │
│              │                                          │
│  ┌───────────┴───────────────────────────────────┐     │
│  │  プライベートサブネット（10.0.2.0/24）          │     │
│  │  ┌─────────────────────────────────────┐      │     │
│  │  │  User Frontend (ECS/Fargate)        │      │     │
│  │  │  Admin Frontend (ECS/Fargate)       │      │     │
│  │  └─────────────────────────────────────┘      │     │
│  └───────────┬───────────────────────────────────┘     │
│              │                                          │
│  ┌───────────┴───────────────────────────────────┐     │
│  │  プライベートサブネット（10.0.3.0/24）          │     │
│  │  ┌─────────────────────────────────────┐      │     │
│  │  │  Auth Service (ECS/Fargate)         │      │     │
│  │  │  User API Service (ECS/Fargate)     │      │     │
│  │  │  Admin API Service (ECS/Fargate)    │      │     │
│  │  └─────────────────────────────────────┘      │     │
│  └───────────┬───────────────────────────────────┘     │
│              │                                          │
│  ┌───────────┴───────────────────────────────────┐     │
│  │  データベースサブネット（10.0.4.0/24）          │     │
│  │  ┌─────────────────────────────────────┐      │     │
│  │  │  RDS PostgreSQL (Multi-AZ)          │      │     │
│  │  │  ElastiCache Redis (Multi-AZ)       │      │     │
│  │  └─────────────────────────────────────┘      │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### サブネット分離の利点

1. **パブリックサブネット**:
   - インターネットゲートウェイ経由で外部アクセス
   - ロードバランサーのみ配置

2. **フロントエンドプライベートサブネット**:
   - NAT Gateway 経由で外部API呼び出し可能
   - 直接のインターネットアクセスは不可

3. **APIプライベートサブネット**:
   - 内部通信のみ
   - インターネットアクセス不可

4. **データベースプライベートサブネット**:
   - 完全に分離
   - API層からのみアクセス可能

### Terraform 設定例

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "ai-micro-vpc"
  }
}

# パブリックサブネット
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ai-micro-public-subnet"
  }
}

# プライベートサブネット（フロントエンド）
resource "aws_subnet" "private_frontend" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ai-micro-private-frontend-subnet"
  }
}

# プライベートサブネット（API）
resource "aws_subnet" "private_api" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ai-micro-private-api-subnet"
  }
}

# プライベートサブネット（データベース）
resource "aws_subnet" "private_database" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ai-micro-private-database-subnet"
  }
}

# セキュリティグループ
resource "aws_security_group" "database" {
  name        = "ai-micro-database-sg"
  description = "Security group for PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## DDoS攻撃対策

### レート制限

**Redis ベースのレート制限**:

```python
from fastapi import HTTPException, Request
from app.core.redis_manager import RedisManager

async def rate_limit(request: Request, limit: int = 100, window: int = 60):
    """Rate limiting middleware"""
    client_ip = request.client.host
    key = f"rate_limit:{client_ip}"

    count = await RedisManager.incr(key)

    if count == 1:
        await RedisManager.expire(key, window)

    if count > limit:
        raise HTTPException(
            status_code=429,
            detail="Too many requests"
        )
```

### AWS WAF ルール

**推奨ルール**:

1. **IPレート制限**:
   - 1分あたり1000リクエスト

2. **地理的制限**:
   - 特定国からのアクセス制限

3. **SQLインジェクション検出**:
   - AWS Managed Rule使用

4. **XSS検出**:
   - AWS Managed Rule使用

### CloudFlare 保護

**機能**:
- DDoS Protection
- CDN
- WAF
- Bot Management
- Rate Limiting

---

## セキュリティベストプラクティス

### 1. 最小権限ネットワーク

**原則**: 必要な通信のみを許可

**チェックリスト**:
- [ ] 本番環境でデータベースポートを公開していないか
- [ ] 本番環境でRedisポートを公開していないか
- [ ] APIサービスは内部通信のみか
- [ ] セキュリティグループは最小限か

### 2. ネットワーク監視

**監視項目**:
- 異常なトラフィックパターン
- 未承認のポート使用
- 大量のエラーレスポンス

**ツール**:
- AWS CloudWatch
- AWS VPC Flow Logs
- Prometheus + Grafana

### 3. 定期的なセキュリティ監査

**監査項目**:
- [ ] ファイアウォールルールの確認
- [ ] セキュリティグループの見直し
- [ ] ネットワークログの分析
- [ ] 未使用ポートの確認

---

## トラブルシューティング

### 問題: サービス間通信エラー

**原因**:
- ネットワーク分離の問題
- ファイアウォールルールの問題

**確認方法**:
```bash
# ネットワーク確認
docker network ls
docker network inspect ai-micro-net

# 接続テスト
docker exec auth-service ping postgres
docker exec auth-service curl http://redis:6379

# ポート確認
netstat -tuln | grep 5432
```

### 問題: host.docker.internal 接続エラー

**原因**:
- Docker Desktop未使用（Linux）
- ホストのファイアウォール

**解決策**:
```bash
# Linux の場合
docker run --add-host=host.docker.internal:host-gateway ...
```

---

## 関連ドキュメント

### セキュリティ関連
- [01-security-overview.md](./01-security-overview.md) - セキュリティ概要
- [04-data-protection.md](./04-data-protection.md) - データ保護
- [06-cors-and-headers.md](./06-cors-and-headers.md) - CORS とセキュリティヘッダー

### インフラ関連
- [PostgreSQL Overview](/06-database/01-overview.md)
- [Redis Overview](/07-redis/01-overview.md)

---

**次のステップ**: [06-cors-and-headers.md](./06-cors-and-headers.md) を参照して、CORS設定とセキュリティヘッダーを確認してください。