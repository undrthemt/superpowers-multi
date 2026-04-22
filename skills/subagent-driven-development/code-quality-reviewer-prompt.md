# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

## Dispatch Order: Codex First, Claude Fallback

**Step 1 — Preflight:** Attempt to dispatch `codex:codex-rescue` subagent with a minimal probe (e.g., `echo ok`). If the Agent tool returns an error or the subagent type is not recognized, skip to Claude fallback.

**Step 2 — Codex dispatch (primary):**

```
codex:codex-rescue subagent:
  Use template at requesting-code-review/codex-review-prompt.md

  WHAT_WAS_IMPLEMENTED: [from implementer's report]
  PLAN_OR_REQUIREMENTS: Task N from [plan-file]
  BASE_SHA: [commit before task]
  HEAD_SHA: [current commit]
  DESCRIPTION: [task summary]
```

**Validate response:** Must contain Strengths, Issues, and Assessment sections. If missing, fall back to Claude.

**Step 3 — Claude fallback:**

```
Task tool (superpowers-multi:code-reviewer):
  Use template at requesting-code-review/code-reviewer.md

  WHAT_WAS_IMPLEMENTED: [from implementer's report]
  PLAN_OR_REQUIREMENTS: Task N from [plan-file]
  BASE_SHA: [commit before task]
  HEAD_SHA: [current commit]
  DESCRIPTION: [task summary]
```

## Additional Checks (subagent-driven-development specific)

In addition to standard code quality concerns, the reviewer should check:
- Does each file have one clear responsibility with a well-defined interface?
- Are units decomposed so they can be understood and tested independently?
- Is the implementation following the file structure from the plan?
- Did this implementation create new files that are already large, or significantly grow existing files? (Don't flag pre-existing file sizes — focus on what this change contributed.)

**Code reviewer returns:** Strengths, Issues (Critical/Important/Minor), Assessment
