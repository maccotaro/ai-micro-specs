# Git ワークフロー

## ブランチ戦略

```
main (本番)
  ↑
  └─ develop (開発統合)
       ├─ feature/<issue>-<description>
       ├─ bugfix/<issue>-<description>
       └─ hotfix/<issue>-<description>
```

## 新機能開発フロー

```bash
# 1. develop から分岐
git checkout develop
git pull origin develop
git checkout -b feature/123-user-profile

# 2. 開発とコミット
git add .
git commit -m "feat(profile): add user profile page"

# 3. プッシュとPR作成
git push origin feature/123-user-profile
```

## コミットメッセージ規約

### Type

- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメント変更
- `style`: コードスタイル変更
- `refactor`: リファクタリング
- `test`: テスト追加・修正
- `chore`: ビルド・ツール関連

### 例

```
feat(auth): implement JWT refresh token mechanism

- Add refresh token endpoint
- Update token validation logic
- Add Redis token blacklist

Closes #123
```

## 便利なエイリアス

```bash
# .gitconfig
[alias]
    st = status
    co = checkout
    cm = commit -m
    lg = log --oneline --graph --all
```

## トラブルシューティング

### コミットを修正

```bash
# 直前のコミットメッセージ修正
git commit --amend -m "新しいメッセージ"

# 直前のコミット取り消し
git reset --soft HEAD~1
```

### マージコンフリクト

```bash
# コンフリクト解決後
git add <resolved-files>
git commit

# マージ中止
git merge --abort
```

---

**関連**: [コーディング規約](./02-coding-standards.md), [コントリビューションガイド](./06-contribution-guide.md)