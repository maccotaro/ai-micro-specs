# Admin API - プロンプトテンプレートAPI仕様

**カテゴリ**: Backend Service API
**バージョン**: 1.0.0
**最終更新**: 2025-10-01

## 目次
- [概要](#概要)
- [プロンプトテンプレート管理](#プロンプトテンプレート管理)
- [アクティブテンプレート取得](#アクティブテンプレート取得)

---

## 概要

プロンプトテンプレートAPIは、システム全体で再利用可能なAIプロンプトテンプレートの管理を提供します。

**ベースURL**: `/admin/prompt-templates`

**主要機能**:
- プロンプトテンプレートのCRUD操作
- カテゴリ別・ステータス別フィルタリング
- アクティブテンプレートの取得
- システムテンプレートと通常ユーザーテンプレートの区別

---

## データ型定義

### PromptTemplate

```typescript
interface PromptTemplate {
  id: string;                    // UUID
  name: string;                  // テンプレート名
  description?: string;          // 説明
  content: string;               // プロンプト内容
  category: string;              // カテゴリ（例: "chat", "summarization", "qa"）
  is_active: boolean;            // アクティブフラグ
  is_system: boolean;            // システムテンプレートフラグ
  user_id?: string;              // 作成者ID（通常ユーザーテンプレートの場合）
  variables?: string[];          // 変数名配列（例: ["{context}", "{query}"]）
  metadata?: Record<string, any>; // 追加メタデータ
  created_at: string;            // 作成日時（ISO）
  updated_at: string;            // 更新日時（ISO）
}
```

---

## プロンプトテンプレート管理

### POST /admin/prompt-templates

プロンプトテンプレートを作成します。

**認証**: `admin` 必須

#### リクエストボディ

```typescript
interface PromptTemplateCreate {
  name: string;                  // 必須: テンプレート名
  description?: string;          // 説明
  content: string;               // 必須: プロンプト内容
  category: string;              // 必須: カテゴリ
  is_active?: boolean;           // デフォルト: true
  is_system?: boolean;           // デフォルト: false（管理者のみtrue設定可）
  variables?: string[];          // 変数名配列
  metadata?: Record<string, any>;
}

// 使用例
const template = await fetch('/api/admin/prompt-templates', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: '技術文書Q&A',
    description: '技術文書に対する質問応答用プロンプト',
    content: `あなたは技術文書の専門家です。

提供されたコンテキスト:
{context}

ユーザーの質問:
{query}

上記のコンテキストに基づいて、正確かつ詳細に質問に答えてください。`,
    category: 'qa',
    is_active: true,
    is_system: false,
    variables: ['{context}', '{query}']
  })
}).then(r => r.json()) as PromptTemplate;
```

#### レスポンス例

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "name": "技術文書Q&A",
  "description": "技術文書に対する質問応答用プロンプト",
  "content": "あなたは技術文書の専門家です。\n\n提供されたコンテキスト:\n{context}\n\nユーザーの質問:\n{query}\n\n上記のコンテキストに基づいて、正確かつ詳細に質問に答えてください。",
  "category": "qa",
  "is_active": true,
  "is_system": false,
  "variables": ["{context}", "{query}"],
  "created_at": "2025-10-01T14:30:00Z",
  "updated_at": "2025-10-01T14:30:00Z"
}
```

### GET /admin/prompt-templates

プロンプトテンプレート一覧を取得します（ページネーション・フィルタリング対応）。

**認証**: `admin` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `category` | string | - | カテゴリでフィルタ |
| `is_active` | boolean | - | アクティブ状態でフィルタ |
| `is_system` | boolean | - | システムテンプレートでフィルタ |
| `page` | number | 1 | ページ番号 |
| `limit` | number | 50 | 1ページあたりの件数（最大100） |

#### レスポンス

```typescript
interface PromptTemplateListResponse {
  templates: PromptTemplate[];
  total: number;                 // 総件数
  page: number;                  // 現在のページ
  limit: number;                 // ページサイズ
}

// 使用例
const templates = await fetch(
  '/api/admin/prompt-templates?category=qa&is_active=true&page=1&limit=50'
).then(r => r.json()) as PromptTemplateListResponse;

templates.templates.forEach(t => {
  console.log(`[${t.category}] ${t.name}`);
});
```

### GET /admin/prompt-templates/{template_id}

特定のプロンプトテンプレートを取得します。

**認証**: `admin` 必須

**パスパラメータ**: `template_id` (UUID)

```typescript
const template = await fetch(`/api/admin/prompt-templates/${templateId}`)
  .then(r => r.json()) as PromptTemplate;
```

### PUT /admin/prompt-templates/{template_id}

プロンプトテンプレートを更新します。

**認証**: `admin` 必須

#### リクエストボディ

```typescript
interface PromptTemplateUpdate {
  name?: string;
  description?: string;
  content?: string;
  category?: string;
  is_active?: boolean;
  is_system?: boolean;           // 管理者のみ変更可
  variables?: string[];
  metadata?: Record<string, any>;
}

// 使用例
await fetch(`/api/admin/prompt-templates/${templateId}`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    description: '更新された説明',
    is_active: true,
    content: '更新されたプロンプト内容...'
  })
});
```

### DELETE /admin/prompt-templates/{template_id}

プロンプトテンプレートを削除します。

**認証**: `admin` 必須

**パスパラメータ**: `template_id` (UUID)

**注意**: システムテンプレート（`is_system: true`）は削除できません。

```typescript
await fetch(`/api/admin/prompt-templates/${templateId}`, {
  method: 'DELETE'
});
```

---

## アクティブテンプレート取得

### GET /admin/prompt-templates/active

アクティブなプロンプトテンプレートのみを取得します（一般ユーザーもアクセス可能）。

**認証**: `get_current_user` 必須

#### クエリパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|-----------|------|
| `category` | string | - | カテゴリでフィルタ |

#### レスポンス

```typescript
// レスポンスは PromptTemplate[] の配列
const activeTemplates = await fetch(
  '/api/admin/prompt-templates/active?category=qa'
).then(r => r.json()) as PromptTemplate[];

// カテゴリ別でテンプレートを選択
const qaTemplates = activeTemplates.filter(t => t.category === 'qa');
```

---

## 使用パターン

### テンプレート変数の置換

```typescript
function applyTemplate(
  template: PromptTemplate,
  variables: Record<string, string>
): string {
  let content = template.content;

  // 変数を置換
  Object.entries(variables).forEach(([key, value]) => {
    const placeholder = `{${key}}`;
    content = content.replace(new RegExp(placeholder, 'g'), value);
  });

  return content;
}

// 使用例
const template = await fetch('/api/admin/prompt-templates/some-id')
  .then(r => r.json()) as PromptTemplate;

const finalPrompt = applyTemplate(template, {
  context: 'PDFから抽出されたテキスト...',
  query: 'このドキュメントの要約を教えてください'
});

console.log(finalPrompt);
// 出力: "あなたは技術文書の専門家です。\n\n提供されたコンテキスト:\nPDFから抽出されたテキスト...\n\nユーザーの質問:\nこのドキュメントの要約を教えてください\n\n..."
```

### React Hook使用例

```typescript
function usePromptTemplates(category?: string) {
  const [templates, setTemplates] = useState<PromptTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchTemplates = async () => {
      try {
        const url = category
          ? `/api/admin/prompt-templates/active?category=${category}`
          : '/api/admin/prompt-templates/active';

        const data = await fetch(url).then(r => r.json());
        setTemplates(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to fetch');
      } finally {
        setLoading(false);
      }
    };

    fetchTemplates();
  }, [category]);

  return { templates, loading, error };
}

// 使用例
function PromptSelector({ onSelect }: { onSelect: (template: PromptTemplate) => void }) {
  const { templates, loading, error } = usePromptTemplates('qa');

  if (loading) return <div>Loading templates...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <select onChange={e => {
      const template = templates.find(t => t.id === e.target.value);
      if (template) onSelect(template);
    }}>
      <option value="">Select a template...</option>
      {templates.map(t => (
        <option key={t.id} value={t.id}>
          {t.name}
        </option>
      ))}
    </select>
  );
}
```

### カテゴリ別テンプレート例

#### 1. Q&Aカテゴリ (`category: "qa"`)

```
あなたは専門的なアシスタントです。

コンテキスト:
{context}

質問:
{query}

上記のコンテキストに基づいて、質問に正確に答えてください。
```

#### 2. 要約カテゴリ (`category: "summarization"`)

```
以下のテキストを簡潔に要約してください。

テキスト:
{text}

要約は3〜5文で、重要なポイントを含めてください。
```

#### 3. チャットカテゴリ (`category: "chat"`)

```
あなたは親しみやすいチャットボットです。

会話履歴:
{conversation_history}

ユーザーメッセージ:
{user_message}

自然で親しみやすい口調で返答してください。
```

---

## システムテンプレートと通常ユーザーテンプレート

### システムテンプレート (`is_system: true`)

- **管理者のみが作成・編集可能**
- **削除不可**
- **全ユーザーが利用可能**
- システムの基本機能に使用されるテンプレート

### 通常ユーザーテンプレート (`is_system: false`)

- **管理者・作成者が編集可能**
- **削除可能**
- **作成者と管理者のみが管理可能**
- カスタムユースケース向けテンプレート

---

## エラーレスポンス

### 標準エラー形式

```typescript
interface APIError {
  detail: string;                // エラー詳細メッセージ
}
```

### よくあるエラー

| コード | 説明 | 対処法 |
|-------|------|-------|
| 400 | リクエスト不正 | 必須フィールド（name, content, category）が不足 |
| 403 | 権限不足 | システムテンプレートの削除を試みた |
| 404 | テンプレート未発見 | IDを確認、または既に削除された可能性 |
| 409 | 競合 | 同名のテンプレートが既に存在 |

---

## 関連ドキュメント

- [ナレッジベースAPI](./02-api-knowledge-bases.md) - ナレッジベース専用のカスタムプロンプト
- [システム管理API](./02-api-system-logs.md) - システム全体の設定管理
