# チャット履歴管理API

**最終更新**: 2025-11-08

## 概要

ナレッジベースとのチャット対話の履歴を管理するAPIです。ユーザーは複数のチャットセッションを作成し、各セッションに紐づくメッセージを保存・取得できます。お気に入り機能やタイトル編集も提供します。

## エンドポイント一覧

| メソッド | エンドポイント | 説明 |
|---------|---------------|------|
| GET | `/api/knowledge-bases/{kb_id}/chat/sessions` | セッション一覧取得 |
| POST | `/api/knowledge-bases/{kb_id}/chat/sessions` | 新規セッション作成 |
| GET | `/api/sessions/{session_id}` | セッション詳細取得 |
| PUT | `/api/sessions/{session_id}` | セッション更新（タイトル編集） |
| DELETE | `/api/sessions/{session_id}` | セッション削除 |
| GET | `/api/sessions/{session_id}/messages` | メッセージ一覧取得 |
| POST | `/api/messages` | メッセージ追加 |
| PUT | `/api/sessions/{session_id}/favorite` | お気に入り切り替え |

## データモデル

### ChatSession

```typescript
interface ChatSession {
  id: string;                    // UUID
  knowledge_base_id: string;      // UUID
  user_id: string;                // UUID
  title: string;                  // セッションタイトル（最大50文字）
  is_favorite: boolean;           // お気に入りフラグ
  message_count: number;          // メッセージ数
  created_at: string;             // ISO 8601
  updated_at: string;             // ISO 8601
}
```

### ChatMessage

```typescript
interface ChatMessage {
  id: string;                    // UUID
  session_id: string;            // UUID
  role: 'user' | 'assistant';    // メッセージ種別
  content: string;               // メッセージ内容
  metadata?: {
    sources?: Array<{
      chunk_id: string;
      document_id: string;
      score: number;
    }>;
    tool_used?: string;          // 使用したMCPツール
  };
  created_at: string;            // ISO 8601
}
```

## API詳細

### 1. セッション一覧取得

```
GET /api/knowledge-bases/{kb_id}/chat/sessions
```

**パラメータ**:
- `kb_id` (path): ナレッジベースUUID

**レスポンス**:
```json
{
  "sessions": [
    {
      "id": "session-uuid",
      "knowledge_base_id": "kb-uuid",
      "user_id": "user-uuid",
      "title": "マイナビのサービスについて",
      "is_favorite": true,
      "message_count": 12,
      "created_at": "2025-11-08T10:30:00Z",
      "updated_at": "2025-11-08T11:45:00Z"
    }
  ],
  "count": 1
}
```

### 2. セッション作成

```
POST /api/knowledge-bases/{kb_id}/chat/sessions
```

**リクエスト**:
```json
{
  "title": "新規チャット"
}
```

**レスポンス**: ChatSessionオブジェクト

### 3. メッセージ一覧取得

```
GET /api/sessions/{session_id}/messages
```

**レスポンス**:
```json
{
  "messages": [
    {
      "id": "msg-uuid",
      "session_id": "session-uuid",
      "role": "user",
      "content": "マイナビのサービスは？",
      "created_at": "2025-11-08T10:31:00Z"
    },
    {
      "id": "msg-uuid-2",
      "session_id": "session-uuid",
      "role": "assistant",
      "content": "マイナビバイトは...",
      "metadata": {
        "sources": [{"chunk_id": "...", "score": 0.92}],
        "tool_used": "search_documents"
      },
      "created_at": "2025-11-08T10:31:05Z"
    }
  ],
  "count": 2
}
```

### 4. メッセージ追加

```
POST /api/messages
```

**リクエスト**:
```json
{
  "session_id": "session-uuid",
  "role": "user",
  "content": "追加の質問",
  "metadata": {}
}
```

### 5. お気に入り切り替え

```
PUT /api/sessions/{session_id}/favorite
```

**リクエスト**:
```json
{
  "is_favorite": true
}
```

## 自動タイトル生成

最初のユーザーメッセージから自動的にタイトルを生成します（最大50文字）。

**ロジック**:
```python
def generate_title(first_message: str) -> str:
    # 最初の50文字を切り出し
    title = first_message[:50]
    # 50文字で切れた場合は "..." を追加
    if len(first_message) > 50:
        title += "..."
    return title
```

## データベーススキーマ

### chat_sessions テーブル

```sql
CREATE TABLE chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_base_id UUID NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    title VARCHAR(50) NOT NULL,
    is_favorite BOOLEAN DEFAULT FALSE,
    message_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_sessions_kb_user ON chat_sessions(knowledge_base_id, user_id);
CREATE INDEX idx_chat_sessions_user ON chat_sessions(user_id);
```

### chat_messages テーブル

```sql
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_messages_session ON chat_messages(session_id, created_at);
```

## 実装状況

- ✅ Phase 1-8完了（2025-11-01）
- ✅ 全8エンドポイント実装済み
- ✅ データベーストリガーによる自動message_count更新
- ✅ CASCADE削除（セッション削除時にメッセージも自動削除）

## 関連ドキュメント

- [02-api-knowledge-bases.md](./02-api-knowledge-bases.md) - ナレッジベースAPI
- [11-api-mcp-integration.md](./11-api-mcp-integration.md) - MCP統合（メッセージ生成）
- [../04-mcp-server/README.md](../04-mcp-server/README.md) - MCPサーバー
