# テスト戦略

## テストピラミッド

```
       /\
      /  \  E2E Tests (10%)
     /----\
    /      \ Integration Tests (30%)
   /--------\
  /          \ Unit Tests (60%)
 /____________\
```

## テストの種類

### Unit Tests

- 個別の関数・クラスのテスト
- モックを活用
- 高速実行

### Integration Tests

- サービス間連携のテスト
- API エンドポイントのテスト
- データベース統合

### E2E Tests

- ユーザーシナリオのテスト
- ブラウザ自動化
- 本番環境に近い環境

## テストカバレッジ目標

| テストタイプ | 目標カバレッジ |
|------------|-------------|
| Unit Tests | 80%以上 |
| Integration Tests | 70%以上 |
| E2E Tests | 主要フロー全カバー |

## テスト実行タイミング

### ローカル開発

```bash
# コミット前
npm test
poetry run pytest
```

### CI/CD

```yaml
on: [push, pull_request]
jobs:
  test:
    steps:
      - run: npm test
      - run: poetry run pytest --cov=app
```

### デプロイ前

- 全テストスイート実行
- カバレッジ確認
- E2Eテスト実行

---

**関連**: [ユニットテスト](./02-unit-testing.md), [統合テスト](./03-integration-testing.md)