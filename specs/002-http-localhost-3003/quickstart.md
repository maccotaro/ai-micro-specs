# Quickstart: Layout Consistency Validation

**Feature**: Collection Edit Page Layout Consistency
**Date**: 2025-10-07
**Test Type**: Visual Regression / Integration Tests

## Prerequisites

1. ai-micro-front-admin service running at `http://localhost:3003`
2. Test knowledge base and collection created in database
3. Playwright installed and configured
4. Admin authentication working

## Test Environment Setup

```bash
# Navigate to admin frontend
cd ai-micro-front-admin

# Install dependencies (if needed)
npm install

# Install Playwright browsers
npx playwright install

# Start development server
npm run dev
```

## Test Scenarios

### Scenario 1: Header Margin Consistency

**Objective**: Verify identical header margins between KB edit and collection edit pages

**Test Steps**:
1. Navigate to KB edit page: `http://localhost:3003/knowledgebase/{test_kb_id}/edit`
2. Capture screenshot of header area
3. Measure header margins using Playwright's bounding box API
4. Navigate to collection edit page: `http://localhost:3003/knowledgebase/{test_kb_id}/collections/{test_collection_id}/edit`
5. Capture screenshot of header area
6. Measure header margins
7. Assert: margins match within 1px tolerance

**Expected Result**: Header margins identical (top, bottom, left, right)

**Pass Criteria**:
```typescript
expect(collectionHeaderMargins).toEqual(kbHeaderMargins);
```

### Scenario 2: Tab Structure Visual Parity

**Objective**: Verify tab layout, spacing, and visual hierarchy match

**Test Steps**:
1. Navigate to KB edit page tabs section
2. Capture tab container screenshot
3. Measure: tab heights, spacing between tabs, border thickness
4. Navigate to collection edit page tabs section
5. Capture tab container screenshot
6. Measure same properties
7. Assert: all measurements match

**Expected Result**: Tab visual structure identical

**Pass Criteria**:
```typescript
expect(collectionTabMetrics.height).toBe(kbTabMetrics.height);
expect(collectionTabMetrics.spacing).toBe(kbTabMetrics.spacing);
expect(collectionTabMetrics.borderWidth).toBe(kbTabMetrics.borderWidth);
```

### Scenario 3: Tab Interaction States

**Objective**: Verify all 5 interaction states styled identically

**Test Steps** (for each state):

**3a. Default State**:
1. Capture non-active tab on both pages
2. Compare background color, text color, border
3. Assert: styles match

**3b. Hover State**:
1. Hover over non-active tab on KB page, capture
2. Hover over non-active tab on collection page, capture
3. Assert: hover styles match

**3c. Active State**:
1. Capture active (selected) tab on both pages
2. Compare background, text, border, indicator
3. Assert: active styles match

**3d. Focus State**:
1. Tab to tabs using keyboard on both pages
2. Capture focus indicator
3. Assert: focus styles match

**3e. Disabled State** (if applicable):
1. If disabled tabs exist, capture on both pages
2. Assert: disabled styles match

**Expected Result**: All 5 interaction states visually identical

**Pass Criteria**:
```typescript
for (const state of ['default', 'hover', 'active', 'focus', 'disabled']) {
  expect(collectionTabStyles[state]).toEqual(kbTabStyles[state]);
}
```

### Scenario 4: Content Width Consistency

**Objective**: Verify identical content width constraints

**Test Steps**:
1. Measure content area max-width on KB edit page
2. Measure content area max-width on collection edit page
3. Assert: widths identical
4. Verify padding matches on both sides

**Expected Result**: Content containers have identical max-width and padding

**Pass Criteria**:
```typescript
expect(collectionContentWidth).toBe(kbContentWidth);
expect(collectionContentPadding).toEqual(kbContentPadding);
```

### Scenario 5: Responsive Behavior Consistency

**Objective**: Verify consistency across mobile, tablet, desktop viewports

**Test Steps** (repeat for each viewport):

**Viewports to Test**:
- Mobile: 375×667 (iPhone SE)
- Tablet: 768×1024 (iPad portrait)
- Desktop: 1920×1080

**For Each Viewport**:
1. Set viewport size
2. Navigate to KB edit page
3. Capture full page screenshot
4. Measure: header margins, tab layout, content width
5. Navigate to collection edit page
6. Capture full page screenshot
7. Measure same properties
8. Assert: all measurements match for this viewport

**Expected Result**: Layout consistency maintained at all breakpoints

**Pass Criteria**:
```typescript
for (const viewport of [mobile, tablet, desktop]) {
  const kbMetrics = await measureLayout(kbPage, viewport);
  const collectionMetrics = await measureLayout(collectionPage, viewport);
  expect(collectionMetrics).toEqual(kbMetrics);
}
```

### Scenario 6: Page Navigation Flow

**Objective**: Verify instant page transitions (no animations)

**Test Steps**:
1. Navigate from KB edit to collection edit page
2. Measure navigation time
3. Assert: transition completes in <100ms (instant, no animation delay)
4. Navigate back to KB edit
5. Measure navigation time
6. Assert: transition completes in <100ms

**Expected Result**: Instant navigation without transition animations

**Pass Criteria**:
```typescript
expect(navigationTime).toBeLessThan(100); // ms
```

## Automated Test Implementation

**Test File Location**: `ai-micro-front-admin/tests/e2e/layout-consistency.spec.ts`

**Test Structure**:
```typescript
import { test, expect } from '@playwright/test';

test.describe('Layout Consistency: KB Edit vs Collection Edit', () => {
  test.beforeEach(async ({ page }) => {
    // Setup: Login, create test KB and collection
  });

  test('Scenario 1: Header margin consistency', async ({ page }) => {
    // Implementation
  });

  test('Scenario 2: Tab structure visual parity', async ({ page }) => {
    // Implementation
  });

  test('Scenario 3a-e: Tab interaction states', async ({ page }) => {
    // Implementation for all 5 states
  });

  test('Scenario 4: Content width consistency', async ({ page }) => {
    // Implementation
  });

  test('Scenario 5: Responsive behavior', async ({ page }) => {
    // Implementation for 3 viewports
  });

  test('Scenario 6: Page navigation flow', async ({ page }) => {
    // Implementation
  });

  test.afterEach(async () => {
    // Cleanup: Remove test data
  });
});
```

## Manual Validation Checklist

After automated tests pass, manually verify:

- [ ] Visual inspection: Pages look identical side-by-side
- [ ] Header margins appear equal
- [ ] Tabs visually aligned and styled the same
- [ ] Content width consistent
- [ ] All tab interaction states work identically
- [ ] Responsive design behaves the same on mobile
- [ ] Responsive design behaves the same on tablet
- [ ] Responsive design behaves the same on desktop
- [ ] Navigation feels instant (no animation lag)
- [ ] No console errors or warnings
- [ ] Accessibility: keyboard navigation works identically

## Success Criteria

**All tests must PASS**:
1. ✅ Automated Playwright tests (6 scenarios)
2. ✅ Manual validation checklist complete
3. ✅ No visual regressions detected
4. ✅ No console errors
5. ✅ Accessibility maintained

**Acceptance**: Feature ready for production when all criteria met.

## Test Execution

```bash
# Run all E2E tests
npm run test:e2e

# Run only layout consistency tests
npx playwright test layout-consistency.spec.ts

# Run with UI mode for debugging
npx playwright test layout-consistency.spec.ts --ui

# Generate HTML report
npx playwright test layout-consistency.spec.ts --reporter=html
```

## Troubleshooting

**Issue**: Screenshots don't match
- **Solution**: Check pixel tolerance settings, ensure consistent browser rendering

**Issue**: Measurements vary slightly
- **Solution**: Allow 1-2px tolerance for sub-pixel rendering differences

**Issue**: Viewport tests flaky
- **Solution**: Add wait for stable layout, disable animations globally in test config
