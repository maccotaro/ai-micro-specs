# Phase 0: Research & Technical Decisions

**Feature**: Collection Edit Page Layout Consistency
**Date**: 2025-10-07

## Overview

This feature requires aligning the visual layout between two existing Next.js pages in the ai-micro-front-admin application. No technical unknowns exist as all technologies and patterns are already established in the codebase.

## Research Areas

### 1. Layout Analysis: Knowledge Base Edit Page

**Decision**: Use KB edit page as the reference implementation for layout consistency

**Current Implementation** (from `knowledgebase/[id]/edit.tsx`):
- File size: 1,184 lines (exceeds 500-line constitutional limit)
- Contains: Header with margins, tab structure, content area with fixed width
- Uses TailwindCSS utility classes for styling
- Responsive design with breakpoints

**Key Layout Elements to Extract**:
- Header container class names and margin values
- Tab component styling (default, hover, active, focus, disabled states)
- Content width constraints (max-width, padding)
- Responsive breakpoint adjustments

**Rationale**: KB edit page is the established pattern that users are accustomed to. Collection edit page should mirror this for consistency.

**Alternatives Considered**:
- Create entirely new shared layout component → Rejected: Increases scope unnecessarily
- Redesign both pages → Rejected: Not in scope, would require new specification

### 2. Component Extraction Strategy

**Decision**: Extract shared layout wrapper component only if file size approaches 500 lines during modification

**Rationale**:
- Constitution Legacy Code Migration Policy allows gradual refactoring
- Current file (1,184 lines) already violates limit
- If modifications push collection edit page toward limit, extract layout component
- Otherwise, apply styling directly to maintain minimal scope

**Alternatives Considered**:
- Immediate full refactoring of both pages → Rejected: Outside scope, requires separate specification
- No component extraction → Rejected: Would violate constitution if file grows

### 3. Testing Strategy

**Decision**: Visual regression testing with Playwright + Percy/Chromatic (if available) or screenshot comparison

**Implementation Approach**:
1. Capture baseline screenshots of KB edit page layout
2. Apply layout changes to collection edit page
3. Compare collection edit page screenshots against KB baseline
4. Assert: header margins, tab styling, content width match within acceptable pixel tolerance

**Test Scenarios** (from spec acceptance criteria):
1. Header margin consistency across both pages
2. Tab structure visual parity (layout, spacing, hierarchy)
3. Content width identical between pages
4. Responsive behavior consistent across mobile/tablet/desktop viewports

**Rationale**: Visual regression is the most reliable way to verify pixel-perfect layout consistency.

**Alternatives Considered**:
- Manual testing only → Rejected: Not repeatable, no TDD compliance
- Unit tests on CSS classes → Rejected: Doesn't verify actual rendered output
- DOM structure comparison → Rejected: Classes can match but render differently

### 4. TailwindCSS Best Practices

**Decision**: Use existing TailwindCSS utility classes from KB edit page, consolidate into shared CSS module if patterns repeat

**Pattern**:
```css
/* Example pattern (to be extracted from actual code) */
.page-header {
  @apply mx-6 mt-4 mb-6;
}

.tab-container {
  @apply flex space-x-2 border-b border-gray-200;
}

.content-wrapper {
  @apply max-w-7xl mx-auto px-4 sm:px-6 lg:px-8;
}
```

**Rationale**: TailwindCSS utility-first approach is already established in codebase. Consistent class usage ensures visual parity.

**Alternatives Considered**:
- CSS-in-JS (styled-components) → Rejected: Not used in current codebase
- Inline styles → Rejected: Less maintainable, harder to ensure consistency

### 5. Responsive Design Implementation

**Decision**: Apply identical responsive breakpoints and behaviors from KB edit page

**Tailwind Breakpoints** (standard):
- `sm`: 640px (tablet portrait)
- `md`: 768px (tablet landscape)
- `lg`: 1024px (desktop)
- `xl`: 1280px (wide desktop)

**Requirements** (from clarifications):
- Maintain consistency across all viewports
- Apply responsive adaptations identically to both pages

**Rationale**: Tailwind provides predictable responsive behavior. Mirroring KB page ensures consistency.

**Alternatives Considered**:
- Custom breakpoints → Rejected: Increases complexity unnecessarily
- Mobile-first from scratch → Rejected: KB page already has working responsive design

### 6. Tab State Management

**Decision**: Use existing tab component/pattern from KB edit page, ensuring all interaction states styled identically

**Required States** (from clarifications):
- Default: Base styling
- Hover: Interactive feedback
- Active: Currently selected tab
- Focus: Keyboard navigation indicator
- Disabled: Non-interactive state (if applicable)

**Implementation**:
- If ShadcnUI tabs component used: Configure with identical props
- If custom tabs: Copy state styling classes exactly

**Rationale**: Tab state styling is already implemented in KB page. Reusing ensures consistency and reduces effort.

**Alternatives Considered**:
- Create new tab component from scratch → Rejected: Duplicates existing work
- Use different tab library → Rejected: Introduces inconsistency

## Technical Decisions Summary

| Area | Decision | Rationale |
|------|----------|-----------|
| Reference Layout | KB edit page | Established user expectation |
| Component Extraction | On-demand (if file size approaches limit) | Constitution compliance with gradual migration |
| Testing | Visual regression (Playwright + screenshots) | Ensures pixel-perfect consistency |
| Styling | TailwindCSS utilities from KB page | Existing codebase pattern |
| Responsive Design | Mirror KB breakpoints exactly | Proven responsive behavior |
| Tab States | Copy KB tab styling for all 5 states | Complete interaction parity |

## Phase 0 Completion Checklist

- [x] No NEEDS CLARIFICATION items remain (all resolved in spec)
- [x] Reference implementation identified (KB edit page)
- [x] Component strategy decided (extract only if needed)
- [x] Testing approach defined (visual regression)
- [x] Styling pattern confirmed (TailwindCSS utilities)
- [x] Responsive strategy established (mirror KB breakpoints)
- [x] All technical decisions documented with rationale

## API Dependencies

This feature relies on existing API endpoints (no modifications):

### Knowledge Base APIs
- `GET /api/knowledgebase/{id}` - Fetch KB details for edit page
- `PUT /api/knowledgebase/{id}` - Update KB settings (unchanged)

### Collection APIs
- `GET /api/collections/{id}` - Fetch collection details for edit page
- `PUT /api/collections/{id}` - Update collection settings (unchanged)

**Note**: These endpoints are already implemented in ai-micro-api-admin and require no changes for this UI-only feature.

## Next Phase

Proceed to **Phase 1: Design & Contracts** to define data model (N/A for UI-only), contracts (N/A), and test structure.
