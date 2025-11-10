# テナント管理API

**最終更新**: 2025-11-08

## 概要

マルチテナント対応のテナント管理APIです。エンタープライズRAGシステムにおけるテナント（組織・企業単位）の作成、更新、削除、一覧表示機能を提供します。

## エンドポイント一覧

| メソッド | エンドポイント | 説明 |
|---------|---------------|------|
| GET | `/api/tenants` | テナント一覧取得 |
| POST | `/api/tenants` | 新規テナント作成 |
| GET | `/api/tenants/{id}` | テナント詳細取得 |
| PUT | `/api/tenants/{id}` | テナント更新 |
| DELETE | `/api/tenants/{id}` | テナント削除 |

**認証**: 全エンドポイントでJWT（admin_access_token）必須

**権限**: super_admin権限が必要

## データモデル

### Tenant

```typescript
interface Tenant {
  id: string;                    // UUID
  name: string;                  // テナント名（最大255文字）
  display_name: string;          // 表示名（最大255文字）
  is_active: boolean;            // アクティブ状態
  settings: {
    max_storage_gb?: number;     // 最大ストレージ容量（GB）
    max_users?: number;          // 最大ユーザー数
    allowed_features?: string[]; // 利用可能機能リスト
  };
  created_at: string;            // ISO 8601
  updated_at: string;            // ISO 8601
}
```

## API詳細

### 1. テナント一覧取得

```
GET /api/tenants
```

**クエリパラメータ**:
- `page` (optional, default: 1): ページ番号
- `page_size` (optional, default: 20): 1ページあたりの件数
- `is_active` (optional): アクティブ状態フィルタ（true/false）

**レスポンス**:
```json
{
  "tenants": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "name": "default_tenant",
      "display_name": "Default Tenant",
      "is_active": true,
      "settings": {
        "max_storage_gb": 100,
        "max_users": 50
      },
      "created_at": "2025-10-24T12:00:00Z",
      "updated_at": "2025-10-24T12:00:00Z"
    }
  ],
  "total": 1,
  "page": 1,
  "page_size": 20,
  "total_pages": 1
}
```

### 2. テナント作成

```
POST /api/tenants
```

**リクエスト**:
```json
{
  "name": "acme_corp",
  "display_name": "Acme Corporation",
  "settings": {
    "max_storage_gb": 500,
    "max_users": 200,
    "allowed_features": ["rag", "ocr", "chat"]
  }
}
```

**バリデーション**:
- `name`: 必須、最大255文字、英数字とアンダースコアのみ、テナント間で一意
- `display_name`: 必須、最大255文字
- `settings`: 任意、JSON形式

**レスポンス**: Tenantオブジェクト（201 Created）

**エラーレスポンス**:
- 400: バリデーションエラー
- 409: 同名テナントが既に存在

### 3. テナント詳細取得

```
GET /api/tenants/{id}
```

**パラメータ**:
- `id` (path): テナントUUID

**レスポンス**: Tenantオブジェクト

**エラーレスポンス**:
- 404: テナントが見つからない

### 4. テナント更新

```
PUT /api/tenants/{id}
```

**パラメータ**:
- `id` (path): テナントUUID

**リクエスト**:
```json
{
  "display_name": "Acme Corporation (Updated)",
  "is_active": false,
  "settings": {
    "max_storage_gb": 1000,
    "max_users": 500
  }
}
```

**更新可能フィールド**:
- `display_name`: 表示名
- `is_active`: アクティブ状態
- `settings`: 設定情報

**更新不可フィールド**:
- `name`: テナントID（変更不可）
- `id`: UUID（変更不可）

**レスポンス**: 更新後のTenantオブジェクト

**エラーレスポンス**:
- 400: バリデーションエラー
- 404: テナントが見つからない

### 5. テナント削除

```
DELETE /api/tenants/{id}
```

**パラメータ**:
- `id` (path): テナントUUID

**削除制約**:
- デフォルトテナント（`00000000-0000-0000-0000-000000000000`）は削除不可
- 関連データ（KB、ドキュメント、ユーザー等）がある場合は削除不可

**レスポンス**:
```json
{
  "message": "Tenant deleted successfully"
}
```

**エラーレスポンス**:
- 400: デフォルトテナント削除試行
- 404: テナントが見つからない
- 409: 関連データが存在

## テナント分離

### データ分離

エンタープライズRAGシステムでは、以下のデータがテナント単位で分離されます：

**分離対象テーブル**:
- `knowledge_bases`: ナレッジベース
- `collections`: コレクション
- `documents`: ドキュメント
- `langchain_pg_embedding`: チャンク埋め込みベクトル
- `chat_sessions`: チャットセッション
- `chat_messages`: チャットメッセージ
- `rag_audit_logs`: 監査ログ

### テナント自動設定

**ミドルウェア**: `TenantMiddleware`
- リクエストヘッダー `X-Tenant-ID` からテナントID取得
- JWTトークンの `tenant_id` クレームから取得（フォールバック）
- デフォルトテナント（`00000000-0000-0000-0000-000000000000`）へフォールバック

**データアクセス**:
- 全データ取得クエリに `tenant_id` フィルタ自動適用
- 新規データ作成時に現在のテナントID自動設定

### テナント切り替え

**super_admin権限**:
- `X-Tenant-ID` ヘッダーで任意のテナントへ切り替え可能
- クロステナント操作が可能（監査ログ記録）

**admin/user権限**:
- 所属テナントのみアクセス可能
- テナント切り替え不可

## デフォルトテナント

### 概要

**UUID**: `00000000-0000-0000-0000-000000000000`

**名前**: `default_tenant`

**用途**:
- 初期セットアップ時のフォールバック
- テナント未設定データの受け皿
- 開発・テスト環境での簡易運用

### 制約

- **削除不可**: システム運用に必須のため削除不可
- **名前変更不可**: `name` フィールドは固定
- **is_active**: 常に `true`（変更不可）

## データベーススキーマ

### tenants テーブル

```sql
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,  -- テナントID（英数字_のみ）
    display_name VARCHAR(255) NOT NULL,  -- 表示名
    is_active BOOLEAN DEFAULT TRUE,      -- アクティブ状態
    settings JSONB DEFAULT '{}',         -- 設定情報
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenants_active ON tenants(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_tenants_name ON tenants(name);
CREATE INDEX idx_tenants_settings_gin ON tenants USING GIN (settings);
```

### 外部キー関係

```sql
-- knowledge_bases テーブル
ALTER TABLE knowledge_bases
ADD COLUMN tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT;

-- documents テーブル
ALTER TABLE documents
ADD COLUMN tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT;

-- collections テーブル
ALTER TABLE collections
ADD COLUMN tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT;

-- langchain_pg_embedding テーブル（メタデータ）
-- cmetadata JSONB に tenant_id を含める
```

## 実装状況

- ✅ Phase 1-1完了（2025-10-24）: テナントテーブル作成
- ✅ Phase 1-2完了（2025-10-24）: 既存データマイグレーション
- ✅ Phase 1-3完了（2025-10-24）: テナントミドルウェア実装
- ✅ Phase 1-5完了（2025-10-24）: CRUD API実装

## セキュリティ考慮事項

### 権限チェック

**テナント作成・削除**:
- super_admin権限のみ許可
- 監査ログに記録

**テナント更新**:
- super_admin権限のみ許可
- is_active変更時は監査ログ記録

**テナント参照**:
- super_admin: 全テナント参照可能
- admin: 所属テナントのみ参照可能

### 監査ログ

**記録イベント**:
- テナント作成（tenant_created）
- テナント更新（tenant_updated）
- テナント削除（tenant_deleted）
- テナント無効化（tenant_deactivated）
- クロステナントアクセス（cross_tenant_access）

**ログ内容**:
```json
{
  "event_type": "tenant_created",
  "tenant_id": "tenant-uuid",
  "user_id": "admin-user-uuid",
  "details": {
    "tenant_name": "acme_corp",
    "display_name": "Acme Corporation"
  },
  "timestamp": "2025-11-08T10:00:00Z"
}
```

## 関連ドキュメント

- [02-api-knowledge-bases.md](./02-api-knowledge-bases.md) - ナレッジベースAPI（テナント分離）
- [06-database-design.md](./06-database-design.md) - データベース設計（テナント外部キー）
- [../17-rag-system/README.md](../17-rag-system/README.md) - エンタープライズRAGシステム
- [../06-database/06-admindb-schema.md](../06-database/06-admindb-schema.md) - admindbスキーマ

## 運用ガイド

### 新規テナント追加手順

1. **テナント作成**:
   ```bash
   curl -X POST http://localhost:8003/api/tenants \
     -H "Authorization: Bearer ${SUPER_ADMIN_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "new_tenant",
       "display_name": "New Tenant",
       "settings": {"max_storage_gb": 100}
     }'
   ```

2. **管理者ユーザー作成**: auth-service経由でテナント管理者を作成

3. **初期ナレッジベース作成**: 必要に応じてKBを作成

### テナント無効化手順

1. **テナント無効化**:
   ```bash
   curl -X PUT http://localhost:8003/api/tenants/{id} \
     -H "Authorization: Bearer ${SUPER_ADMIN_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"is_active": false}'
   ```

2. **影響確認**: 該当テナントのユーザーはログイン不可・API呼び出し不可

3. **データ保持**: データは削除されず保持（再有効化可能）

### テナント削除前チェック

```sql
-- KB数確認
SELECT COUNT(*) FROM knowledge_bases WHERE tenant_id = 'tenant-uuid';

-- ドキュメント数確認
SELECT COUNT(*) FROM documents WHERE tenant_id = 'tenant-uuid';

-- ユーザー数確認（auth-service側）
SELECT COUNT(*) FROM users WHERE tenant_id = 'tenant-uuid';
```

全て0件の場合のみ削除可能。
