# AI Microservices Specification Constitution
<!--
Sync Impact (v1.1.0 → v1.2.0 MINOR - Context Optimization):
- Restructured project-context.md → project-context-core.md (150 lines) + services/*.md (on-demand)
- Simplified constitution (163→100 lines, 39% reduction)
- Updated refs: constitution, plan-template, spec-template
- Total context reduction: 9,000→2,500 tokens (72%)
-->

## Core Principles

### I. Specification-First Development

Every feature begins with a non-technical specification describing WHAT users need and WHY, never HOW. Specifications MUST be stakeholder-readable, free of implementation details, with testable acceptance criteria. Mark ambiguities as `[NEEDS CLARIFICATION: question]`.

### II. Test-Driven Development (NON-NEGOTIABLE)

TDD is mandatory: Tests first → User approves → Tests fail → Implement. Red-Green-Refactor cycle strictly enforced. Contract tests before implementation. Integration tests validate user stories. All tests MUST fail initially.

### III. Template-Driven Consistency

All artifacts (spec, plan, tasks) MUST follow standardized templates with executable workflows. Templates are self-contained with execution flow, error handling, and validation gates. Replace all placeholders with concrete values.

### IV. Phased Implementation Workflow

Strict phases: Phase 0 (Research) → Phase 1 (Design & Contracts) → Phase 2 (Task Planning) → Phase 3 (Tests) → Phase 4 (Implementation) → Phase 5 (Validation). Constitution checks before Phase 0 and after Phase 1. No phase starts until prerequisites complete.

### V. Parallel Execution Optimization

Tasks on different files without dependencies MUST be marked `[P]`. Task descriptions MUST include exact file paths. Same-file modifications are sequential (no `[P]`). Dependency graph MUST be explicit.

### VI. Microservices Architecture Alignment

For microservices: Consider distributed architecture (BFF, JWT auth, service-specific DBs, Redis cache). Services communicate via well-defined APIs with contract tests.

**Context**: See `.specify/memory/project-context-core.md` (details: `services/*.md`). New features MUST identify target service(s) or justify new service.

### VII. File Size Limit

Source code files MUST NOT exceed 500 lines (.py, .ts, .tsx, .js, .jsx). Documentation/config/test fixtures exempt. Approaching limit → AUTOMATICALLY refactor. NEVER complete tasks violating this without refactoring.

## Workflow Requirements

### Legacy Code Migration Policy

NEW code: Strict compliance. EXISTING code: Gradual migration.

**New Code**: Follow all principles. 500-line limit enforced. TDD mandatory.

**Existing Code**: Refactor when (1) adding features, (2) bug fixes >50 lines, (3) flagged in technical debt.

**Mixed Changes**: New code compliant. Existing code refactored opportunistically. File >500 lines after changes → split before commit.

**Timeline**: Phase 1 (now): New only. Phase 2 (3mo): Touched files comply. Phase 3 (6mo): Zero tolerance.

### Clarification-First Principle

Run `/clarify` before planning to identify underspecified areas. Ambiguous requirements MUST be clarified before design. Plan command checks for `## Clarifications` section and pauses if missing.

### Agent-File Context Management

Update agent files (CLAUDE.md, etc.) using `.specify/scripts/bash/update-agent-context.sh <agent>`. O(1) updates: add NEW tech only, preserve manual additions, keep last 3 changes, stay under 150 lines.

### Documentation-Code Sync

Update CLAUDE.md after changes affecting: structure, tech versions, APIs, env vars, architecture, or major functionality. 2-tier: root CLAUDE.md (system-wide), service CLAUDE.md (service-specific). No deeper CLAUDE.md files.

## Quality Gates

### Constitution Compliance

Plans MUST pass checks before Phase 0 (step 4) and after Phase 1 (step 7). Violations documented in Complexity Tracking with justification. Unjustifiable complexity → ERROR, simplify first.

### Testability Validation

Functional requirements: testable, unambiguous. Acceptance scenarios: Given-When-Then. Success criteria: measurable. Edge cases: explicit. Spec template enforces (step 7).

### Artifact Completeness

Task generation validates: contracts have tests, entities have models, tests precede implementation, parallel tasks independent, exact file paths. Phase 0-1 artifacts complete before task planning.

## Governance

### Amendment Process

Amendments require: (1) rationale, (2) semantic version bump, (3) Sync Impact Report, (4) no bracketed placeholders, (5) propagate to templates/agent files.

### Versioning

MAJOR: Breaking changes. MINOR: New principles/sections. PATCH: Clarifications.

### Compliance Review

PRs verify compliance. Complexity justified in plan.md. Follow template execution flows. Use slash commands only.

### Runtime Guidance

Constitution: non-negotiable principles. CLAUDE.md: runtime guidance. Constitution supersedes all.

**Version**: 1.2.0 | **Ratified**: 2025-10-05 | **Last Amended**: 2025-10-05
