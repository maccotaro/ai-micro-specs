# E2Eテスト

## Playwright

### セットアップ

```bash
npm install -D @playwright/test
npx playwright install
```

### テストシナリオ

```typescript
// tests/e2e/user-journey.spec.ts
import { test, expect } from '@playwright/test';

test.describe('User Authentication Flow', () => {
  test('user can register, login, and view profile', async ({ page }) => {
    // 登録ページに移動
    await page.goto('http://localhost:3002/register');

    // 登録フォーム入力
    await page.fill('input[name="username"]', 'newuser');
    await page.fill('input[name="email"]', 'newuser@example.com');
    await page.fill('input[name="password"]', 'SecurePass123!');
    await page.click('button[type="submit"]');

    // ログインページにリダイレクト
    await expect(page).toHaveURL('http://localhost:3002/login');

    // ログイン
    await page.fill('input[name="username"]', 'newuser');
    await page.fill('input[name="password"]', 'SecurePass123!');
    await page.click('button[type="submit"]');

    // ダッシュボードに移動
    await expect(page).toHaveURL('http://localhost:3002/dashboard');

    // プロファイルページに移動
    await page.click('a[href="/profile"]');
    await expect(page.locator('h1')).toContainText('Profile');
  });
});

test.describe('Document Upload Flow', () => {
  test.beforeEach(async ({ page }) => {
    // ログイン
    await page.goto('http://localhost:3003/login');
    await page.fill('input[name="username"]', 'admin');
    await page.fill('input[name="password"]', 'adminpass');
    await page.click('button[type="submit"]');
  });

  test('admin can upload and process document', async ({ page }) => {
    await page.goto('http://localhost:3003/documents');

    // ファイルアップロード
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles('test-document.pdf');

    // アップロードボタンクリック
    await page.click('button:has-text("Upload")');

    // 成功メッセージ確認
    await expect(page.locator('.success-message')).toBeVisible();

    // ドキュメント一覧に表示されることを確認
    await expect(page.locator('text=test-document.pdf')).toBeVisible();
  });
});
```

### テスト実行

```bash
# 全テスト実行
npx playwright test

# UI モード
npx playwright test --ui

# デバッグモード
npx playwright test --debug

# 特定のブラウザ
npx playwright test --project=chromium
```

### playwright.config.ts

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30000,
  use: {
    baseURL: 'http://localhost:3002',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
  ],
});
```

## ビジュアルリグレッションテスト

```typescript
test('homepage has correct layout', async ({ page }) => {
  await page.goto('http://localhost:3002');
  await expect(page).toHaveScreenshot('homepage.png');
});
```

---

**関連**: [統合テスト](./03-integration-testing.md), [契約テスト](./05-contract-testing.md)