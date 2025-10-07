
# Implementation Plan: Collection Edit Page Layout Consistency

**Branch**: `002-http-localhost-3003` | **Date**: 2025-10-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-http-localhost-3003/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code, or `AGENTS.md` for all other agents).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary

Fix layout inconsistencies between the knowledge base edit page (`/knowledgebase/{id}/edit`) and collection edit page (`/knowledgebase/{id}/collections/{collection_id}/edit`) in the ai-micro-front-admin application. The collection edit page currently has different header margins and tab layouts compared to the knowledge base edit page, creating a disjointed user experience. This is a frontend-only UI consistency fix with no backend changes required.

**Primary Requirement**: Apply identical visual styling, header margins, tab structure, and content width to both pages while maintaining their distinct functionality.

**Scope**: Frontend only (ai-micro-front-admin), no API changes, no database changes.

## Technical Context
**Language/Version**: TypeScript 5.x, React 18+, Next.js 14+
**Primary Dependencies**: Next.js, React, TailwindCSS, ShadcnUI components
**Storage**: N/A (UI-only changes)
**Testing**: Jest + React Testing Library (unit), Playwright (E2E)
**Target Platform**: Web browsers (Chrome, Firefox, Safari, Edge)
**Project Type**: Web (microservices - frontend only)
**Performance Goals**: 60fps UI interactions, instant page transitions (no animations per spec)
**Constraints**: Must maintain responsive design across mobile/tablet/desktop viewports
**Scale/Scope**: 2 pages affected (KB edit, collection edit), estimated 3-5 component/style files to modify

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Specification-First Development
- [x] Feature spec exists and is stakeholder-readable
- [x] No implementation details in spec
- [x] Testable acceptance criteria defined
- [x] All ambiguities resolved via `/clarify` (5 clarifications documented)

### II. Test-Driven Development (NON-NEGOTIABLE)
- [ ] Contract tests planned (N/A - no API contracts)
- [ ] Integration tests planned (visual regression tests to verify consistency)
- [ ] Unit tests planned (component-level tests for layout components)
- [ ] Tests will fail initially (TDD red-green-refactor)

### III. Template-Driven Consistency
- [x] Using standardized templates (spec, plan, tasks)
- [x] Execution flow defined
- [x] Validation gates in place

### IV. Phased Implementation Workflow
- [x] Phase 0-2 planning in progress
- [ ] Phase 3-5 to follow after task generation
- [x] Prerequisites validated (clarifications complete)

### V. Parallel Execution Optimization
- [x] Will identify parallel tasks in Phase 2 (independent component files)
- [x] File paths will be explicit in tasks
- [x] Dependency graph will be clear

### VI. Microservices Architecture Alignment
- [x] Target service identified: ai-micro-front-admin
- [x] No new services needed
- [x] No cross-service dependencies (UI-only)
- [x] No API contract changes

### VII. File Size Limit
- [x] Current violation known: `knowledgebase/[id]/edit.tsx` (1,184 lines)
- [x] Will refactor if modifications approach 500-line limit
- [x] Opportunistic refactoring during implementation per Constitution Legacy Code Policy

### Microservices Integration Check
*For microservices projects only - refer to `.specify/memory/project-context-core.md` (details: `services/*.md`)*

**Service Scope**:
- [x] Identified existing service: ai-micro-front-admin (Next.js frontend)
- [x] No new service needed (UI-only changes)
- [x] Service boundaries remain clear (frontend-only, no backend impact)

**API Contracts**:
- [x] No new API contracts (uses existing KB and collection data endpoints)
- [x] No contract tests needed (no API changes)
- [x] Authentication unchanged (existing JWT authentication continues)

**Data Flow**:
- [x] No database changes required
- [x] No cross-database operations (UI-only)
- [x] No Redis state changes

**Impact Assessment**:
- [x] Full backward compatibility (only visual changes)
- [x] No breaking changes to any contracts
- [x] Zero performance impact on backend services

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (ai-micro-front-admin repository)
```
ai-micro-front-admin/
├── src/
│   ├── pages/
│   │   ├── knowledgebase/
│   │   │   └── [id]/
│   │   │       └── edit.tsx                    # KB edit page (1,184 lines - target page)
│   │   │       └── collections/
│   │   │           └── [collection_id]/
│   │   │               └── edit.tsx            # Collection edit page (to be aligned)
│   ├── components/
│   │   └── ui/                                 # ShadcnUI components
│   │       └── tabs.tsx                        # Shared tab component (if exists)
│   └── styles/
│       └── globals.css                         # TailwindCSS global styles
└── tests/
    ├── components/                             # Component unit tests
    └── e2e/                                    # Playwright E2E tests
        └── layout-consistency.spec.ts          # Visual regression tests (to be created)
```

**Structure Decision**: Web application (microservices frontend). This feature modifies the ai-micro-front-admin service only. Pages are located in Next.js file-based routing structure. We will work with existing page files and potentially extract shared layout components if code size approaches limits.

## Phase 0: Outline & Research

✅ **Completed**: research.md created

**Key Decisions**:
1. **Reference Layout**: KB edit page serves as the reference implementation
2. **Component Extraction**: Extract layout wrapper only if file size approaches 500-line limit
3. **Testing Strategy**: Visual regression testing with Playwright
4. **Styling Approach**: TailwindCSS utilities mirrored from KB page
5. **Responsive Design**: Mirror KB breakpoints (sm/md/lg/xl)
6. **Tab States**: All 5 interaction states (default, hover, active, focus, disabled) must match

**Output**: `research.md` (151 lines) - All technical decisions documented with rationale

## Phase 1: Design & Contracts

✅ **Completed**: All Phase 1 artifacts created

**1. Data Model** (`data-model.md`):
- **Result**: No data model required (UI-only feature)
- **UI Component Structure**: Documented EditPageLayout props (TypeScript interface)
- **State Management**: No changes required to existing state

**2. API Contracts** (`contracts/README.md`):
- **Result**: No API contracts (frontend-only changes)
- **Existing APIs**: Uses current KB and collection endpoints unchanged
- **Contract Tests**: N/A (visual regression tests instead)

**3. Test Scenarios** (`quickstart.md`):
- **6 Test Scenarios Created**:
  1. Header margin consistency
  2. Tab structure visual parity
  3. Tab interaction states (5 states)
  4. Content width consistency
  5. Responsive behavior (3 viewports)
  6. Page navigation flow
- **Test Type**: Playwright E2E with visual regression
- **Test File**: `tests/e2e/layout-consistency.spec.ts` (to be created)

**4. Agent Context Update**:
- ✅ Executed: `.specify/scripts/bash/update-agent-context.sh claude`
- ✅ Updated: `CLAUDE.md` with TypeScript 5.x, React 18+, Next.js 14+, TailwindCSS
- ✅ Feature 002 technologies added to Active Technologies section

**Outputs Created**:
- ✅ `data-model.md` (73 lines)
- ✅ `contracts/README.md` (15 lines)
- ✅ `quickstart.md` (244 lines)
- ✅ `CLAUDE.md` updated (27 lines total)

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:

1. **Phase 0: Test Creation** (TDD - Tests First)
   - Create E2E test file: `layout-consistency.spec.ts`
   - Implement 6 test scenarios from quickstart.md
   - Tests will FAIL initially (no implementation)
   - Mark test creation tasks as [P] (parallelizable by scenario)

2. **Phase 1: Layout Analysis**
   - Analyze KB edit page layout (`knowledgebase/[id]/edit.tsx`)
   - Extract: header margins, tab styling, content width classes
   - Document TailwindCSS classes used
   - Sequential task (must complete before implementation)

3. **Phase 2: Implementation**
   - Apply extracted layout to collection edit page
   - Modify: header, tabs, content wrapper
   - Match all 5 tab interaction states
   - Ensure responsive breakpoints consistent
   - Sequential tasks (order: header → tabs → content → responsive)

4. **Phase 3: Component Extraction** (Conditional)
   - IF collection edit file approaches 500 lines:
     - Extract EditPageLayout component
     - Refactor both pages to use shared component
   - ELSE: Skip (apply styles directly)

5. **Phase 4: Test Validation**
   - Run E2E tests (all 6 scenarios)
   - Fix any layout discrepancies
   - Iterate until all tests pass
   - Sequential tasks (test → fix → retest)

**Ordering Strategy**:
- **TDD Compliance**: Tests created first (Phase 0), implementation after (Phase 2-3)
- **Dependency Order**: Analysis → Implementation → Testing
- **Parallel Execution**: Test scenarios independent [P], implementation tasks sequential
- **File Paths**: All tasks include exact file paths for clarity

**Estimated Task Count**: 12-15 tasks
- Phase 0 (Tests): 6 tasks [P]
- Phase 1 (Analysis): 1 task
- Phase 2 (Implementation): 4-5 tasks
- Phase 3 (Extraction): 0-2 tasks (conditional)
- Phase 4 (Validation): 2 tasks

**Parallelization Opportunities**:
- [P] Test scenario 1-6 creation (independent)
- Sequential: Layout analysis, implementation, validation

**IMPORTANT**: This phase is executed by the `/tasks` command, NOT by `/plan`

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

**No violations detected**. All constitutional principles followed:

- ✅ Specification-first: Spec complete with clarifications
- ✅ TDD: Tests planned before implementation
- ✅ Templates used: Following standardized templates
- ✅ Phased workflow: Proper phase progression
- ✅ Parallel execution: Identified in Phase 2 plan
- ✅ Microservices alignment: Single service, no cross-service dependencies
- ✅ File size limit: Will refactor if approaching 500 lines (Legacy Code Policy applied)

**Known Pre-existing Violation**:
| File | Current Size | Plan |
|------|--------------|------|
| `knowledgebase/[id]/edit.tsx` | 1,184 lines | Opportunistic refactoring during modification per Constitution §VII Legacy Code Migration Policy |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command) - research.md created
- [x] Phase 1: Design complete (/plan command) - data-model.md, contracts/, quickstart.md, CLAUDE.md updated
- [x] Phase 2: Task planning complete (/plan command - approach described)
- [ ] Phase 3: Tasks generated (/tasks command) - **NEXT STEP**
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS (all 7 principles verified)
- [x] Post-Design Constitution Check: PASS (no violations introduced)
- [x] All NEEDS CLARIFICATION resolved (5 clarifications in spec)
- [x] Complexity deviations documented (none - using Legacy Code Policy for existing violation)

---
*Based on Constitution v1.2.0 - See `/memory/constitution.md`*
