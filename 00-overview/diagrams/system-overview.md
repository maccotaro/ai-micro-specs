# システム全体概要図

```mermaid
graph TB
    subgraph "Client Layer"
        Browser[Web Browser]
    end

    subgraph "Frontend Layer (Port 3000番台)"
        UserFE[User Frontend<br/>Next.js<br/>:3002]
        AdminFE[Admin Frontend<br/>Next.js<br/>:3003]
    end

    subgraph "Backend API Layer (Port 8000番台)"
        AuthAPI[Auth Service<br/>FastAPI<br/>:8002]
        UserAPI[User API<br/>FastAPI<br/>:8001]
        AdminAPI[Admin API<br/>FastAPI<br/>:8003]
    end

    subgraph "Data Layer"
        PostgreSQL[(PostgreSQL<br/>:5432)]
        Redis[(Redis<br/>:6379)]
    end

    subgraph "PostgreSQL Databases"
        AuthDB[(authdb)]
        ApiDB[(apidb)]
        AdminDB[(admindb)]
    end

    subgraph "External Services"
        S3[AWS S3<br/>Document Storage]
        OCR[Google Vision<br/>OCR Service]
    end

    Browser -->|HTTP| UserFE
    Browser -->|HTTP| AdminFE

    UserFE -->|JWT Auth| AuthAPI
    UserFE -->|Profile API| UserAPI

    AdminFE -->|JWT Auth| AuthAPI
    AdminFE -->|Profile API| UserAPI
    AdminFE -->|Document API| AdminAPI

    AuthAPI -->|Users/Tokens| AuthDB
    AuthAPI -->|Session/Cache| Redis

    UserAPI -->|Profiles| ApiDB
    UserAPI -->|Cache| Redis
    UserAPI -->|JWT Verify| AuthAPI

    AdminAPI -->|Documents| AdminDB
    AdminAPI -->|Cache| Redis
    AdminAPI -->|JWT Verify| AuthAPI
    AdminAPI -->|Upload| S3
    AdminAPI -->|OCR| OCR

    PostgreSQL ---|Contains| AuthDB
    PostgreSQL ---|Contains| ApiDB
    PostgreSQL ---|Contains| AdminDB

    style Browser fill:#e1f5ff
    style UserFE fill:#fff4e6
    style AdminFE fill:#fff4e6
    style AuthAPI fill:#e8f5e9
    style UserAPI fill:#e8f5e9
    style AdminAPI fill:#e8f5e9
    style PostgreSQL fill:#f3e5f5
    style Redis fill:#ffebee
    style S3 fill:#fce4ec
    style OCR fill:#fce4ec
```

## 概要

このシステムは以下の7つの主要コンポーネントで構成されています：

### フロントエンド層
- **User Frontend (Port 3002)**: エンドユーザー向けWebアプリケーション
- **Admin Frontend (Port 3003)**: 管理者向けWebアプリケーション

### バックエンドAPI層
- **Auth Service (Port 8002)**: 認証・認可サービス
- **User API (Port 8001)**: ユーザープロファイル管理
- **Admin API (Port 8003)**: ドキュメント管理・OCR処理

### データ層
- **PostgreSQL**: 3つのデータベース（authdb, apidb, admindb）
- **Redis**: セッション管理・キャッシュ

### 外部サービス
- **AWS S3**: ドキュメントストレージ
- **Google Vision API**: OCR処理

## 通信フロー

1. **認証フロー**: Frontend → Auth Service → authdb
2. **ユーザー操作**: Frontend → User API → apidb
3. **ドキュメント処理**: Admin Frontend → Admin API → admindb/S3/OCR
4. **キャッシュ**: 全APIサービス → Redis

---

**関連ドキュメント**:
- [システムアーキテクチャ](../01-system-architecture.md)
- [マイクロサービス連携](../02-microservices-integration.md)