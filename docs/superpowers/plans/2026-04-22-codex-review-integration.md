# Codex-First Code Review Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all code reviews through Codex (via `codex:codex-rescue` subagent) first, with Claude fallback when Codex is unavailable.

**Architecture:** Each review dispatch point follows a preflight → dispatch → validate → fallback pattern. Codex-specific prompt templates sit alongside existing Claude templates. The `requesting-code-review` skill is the central routing point; `subagent-driven-development` and `executing-plans` both flow through it or follow the same pattern.

**Tech Stack:** Markdown skill files, bash (git commands)

**Spec:** `docs/superpowers/specs/2026-04-22-codex-review-integration-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `skills/requesting-code-review/SKILL.md` | Modify | Central review orchestration with Codex-first routing |
| `skills/requesting-code-review/codex-review-prompt.md` | Create | Codex-optimized code quality review prompt template |
| `skills/subagent-driven-development/SKILL.md` | Modify | Two-stage + final review with Codex-first routing |
| `skills/subagent-driven-development/codex-spec-reviewer-prompt.md` | Create | Codex-optimized spec compliance review prompt template |
| `skills/subagent-driven-development/code-quality-reviewer-prompt.md` | Modify | Codex-first dispatch instructions |
| `skills/executing-plans/SKILL.md` | Modify | Add batch review checkpoint |
| `README.md` | Modify | Codex plugin prerequisite |
| `RELEASE-NOTES.md` | Modify | Change log entry |

---

### Task 1: Create Codex Code Quality Review Prompt Template

**Files:**
- Create: `skills/requesting-code-review/codex-review-prompt.md`

- [ ] **Step 1: Create the Codex review prompt template**

Create `skills/requesting-code-review/codex-review-prompt.md` with the following content. This mirrors `code-reviewer.md` but is optimized for Codex dispatch via `codex:codex-rescue`:

```markdown
# Codex Code Review Prompt Template

Use this template when dispatching a code review via `codex:codex-rescue` subagent.
Falls back to `code-reviewer.md` (Claude subagent) if Codex is unavailable.

```
codex:codex-rescue subagent:
  description: "Code quality review for {DESCRIPTION}"
  prompt: |
    You are reviewing code changes for production readiness.

    **Your task:**
    1. Review {WHAT_WAS_IMPLEMENTED}
    2. Compare against {PLAN_OR_REQUIREMENTS}
    3. Check code quality, architecture, testing
    4. Categorize issues by severity
    5. Assess production readiness

    ## What Was Implemented

    {DESCRIPTION}

    ## Requirements/Plan

    {PLAN_REFERENCE}

    ## Git Range to Review

    **Base:** {BASE_SHA}
    **Head:** {HEAD_SHA}

    Run these commands to see the changes:
    ```bash
    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}
    ```

    ## Review Checklist

    **Code Quality:**
    - Clean separation of concerns?
    - Proper error handling?
    - Type safety (if applicable)?
    - DRY principle followed?
    - Edge cases handled?

    **Architecture:**
    - Sound design decisions?
    - Scalability considerations?
    - Performance implications?
    - Security concerns?

    **Testing:**
    - Tests actually test logic (not mocks)?
    - Edge cases covered?
    - Integration tests where needed?
    - All tests passing?

    **Requirements:**
    - All plan requirements met?
    - Implementation matches spec?
    - No scope creep?
    - Breaking changes documented?

    **Production Readiness:**
    - Migration strategy (if schema changes)?
    - Backward compatibility considered?
    - Documentation complete?
    - No obvious bugs?

    ## REQUIRED Output Format

    You MUST use exactly this structure. Missing sections will cause a fallback to Claude review.

    ### Strengths
    [What's well done? Be specific with file:line references.]

    ### Issues

    #### Critical (Must Fix)
    [Bugs, security issues, data loss risks, broken functionality]

    #### Important (Should Fix)
    [Architecture problems, missing features, poor error handling, test gaps]

    #### Minor (Nice to Have)
    [Code style, optimization opportunities, documentation improvements]

    **For each issue:**
    - File:line reference
    - What's wrong
    - Why it matters
    - How to fix (if not obvious)

    ### Recommendations
    [Improvements for code quality, architecture, or process]

    ### Assessment

    **Ready to merge?** [Yes/No/With fixes]

    **Reasoning:** [Technical assessment in 1-2 sentences]

    ## Critical Rules

    **DO:**
    - Categorize by actual severity (not everything is Critical)
    - Be specific (file:line, not vague)
    - Explain WHY issues matter
    - Acknowledge strengths
    - Give clear verdict

    **DON'T:**
    - Say "looks good" without checking
    - Mark nitpicks as Critical
    - Give feedback on code you didn't review
    - Be vague ("improve error handling")
    - Avoid giving a clear verdict
```
```

- [ ] **Step 2: Verify the file was created correctly**

Run:
```bash
cat skills/requesting-code-review/codex-review-prompt.md | head -5
```
Expected: First 5 lines of the template showing the title and description.

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/codex-review-prompt.md
git commit -m "feat: add Codex code quality review prompt template"
```

---

### Task 2: Create Codex Spec Compliance Review Prompt Template

**Files:**
- Create: `skills/subagent-driven-development/codex-spec-reviewer-prompt.md`

- [ ] **Step 1: Create the Codex spec compliance prompt template**

Create `skills/subagent-driven-development/codex-spec-reviewer-prompt.md` with the following content. This mirrors `spec-reviewer-prompt.md` but is optimized for Codex dispatch:

```markdown
# Codex Spec Compliance Reviewer Prompt Template

Use this template when dispatching a spec compliance reviewer via `codex:codex-rescue` subagent.
Falls back to `spec-reviewer-prompt.md` (Claude subagent) if Codex is unavailable.

**Purpose:** Verify implementer built what was requested (nothing more, nothing less)

```
codex:codex-rescue subagent:
  description: "Review spec compliance for Task N"
  prompt: |
    You are reviewing whether an implementation matches its specification.

    ## What Was Requested

    [FULL TEXT of task requirements]

    ## What Implementer Claims They Built

    [From implementer's report]

    ## CRITICAL: Do Not Trust the Report

    The implementer finished suspiciously quickly. Their report may be incomplete,
    inaccurate, or optimistic. You MUST verify everything independently.

    **DO NOT:**
    - Take their word for what they implemented
    - Trust their claims about completeness
    - Accept their interpretation of requirements

    **DO:**
    - Read the actual code by running: `cat <file>` or `git diff` for each changed file
    - Compare actual implementation to requirements line by line
    - Check for missing pieces they claimed to implement
    - Look for extra features they didn't mention

    ## Your Job

    Read the implementation code and verify:

    **Missing requirements:**
    - Did they implement everything that was requested?
    - Are there requirements they skipped or missed?
    - Did they claim something works but didn't actually implement it?

    **Extra/unneeded work:**
    - Did they build things that weren't requested?
    - Did they over-engineer or add unnecessary features?
    - Did they add "nice to haves" that weren't in spec?

    **Misunderstandings:**
    - Did they interpret requirements differently than intended?
    - Did they solve the wrong problem?
    - Did they implement the right feature but wrong way?

    **Verify by reading code, not by trusting report.**

    ## REQUIRED Output Format

    You MUST output one of these two verdicts. Missing verdict will cause fallback to Claude review.

    Report:
    - ✅ Spec compliant (if everything matches after code inspection)
    - ❌ Issues found: [list specifically what's missing or extra, with file:line references]
```
```

- [ ] **Step 2: Verify the file was created correctly**

Run:
```bash
cat skills/subagent-driven-development/codex-spec-reviewer-prompt.md | head -5
```
Expected: First 5 lines of the template showing the title and description.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/codex-spec-reviewer-prompt.md
git commit -m "feat: add Codex spec compliance review prompt template"
```

---

### Task 3: Update requesting-code-review Skill with Codex-First Routing

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

- [ ] **Step 1: Replace the "How to Request" section**

In `skills/requesting-code-review/SKILL.md`, replace the entire "How to Request" section (lines 26-47) with the Codex-first routing flow. The new section should be:

```markdown
## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Preflight check:**

Before dispatching, check whether the `codex:codex-rescue` subagent type is available via the Agent tool. If the subagent type is not recognized or unavailable, skip directly to step 4 (Claude fallback).

**3. Dispatch Codex review (primary):**

Dispatch `codex:codex-rescue` subagent using the template at `codex-review-prompt.md`

**Placeholders:**
- `{WHAT_WAS_IMPLEMENTED}` - What you just built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit
- `{DESCRIPTION}` - Brief summary

**Validate the response:** The Codex review output must contain all three sections:
- `### Strengths` or equivalent
- `### Issues` with severity categorization
- `### Assessment` with a merge verdict

If all sections are present, proceed to step 5.

**4. Claude fallback:**

If the preflight check fails, Codex returns an error, or the response is missing required sections — dispatch existing `superpowers:code-reviewer` subagent using the template at `code-reviewer.md` with the same placeholders.

**5. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)
```

- [ ] **Step 2: Update the "See template at" line at the end of the file**

Replace line 105:
```
See template at: requesting-code-review/code-reviewer.md
```

With:
```
See templates at:
- `codex-review-prompt.md` - Codex review (primary)
- `code-reviewer.md` - Claude review (fallback)
```

- [ ] **Step 3: Verify the changes look correct**

Run:
```bash
cat skills/requesting-code-review/SKILL.md
```
Expected: Updated SKILL.md with Codex-first routing flow, preflight check, validation, and fallback.

- [ ] **Step 4: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "feat: update requesting-code-review with Codex-first routing"
```

---

### Task 4: Update code-quality-reviewer-prompt.md with Codex-First Dispatch

**Files:**
- Modify: `skills/subagent-driven-development/code-quality-reviewer-prompt.md`

- [ ] **Step 1: Replace the entire file content**

Replace the content of `skills/subagent-driven-development/code-quality-reviewer-prompt.md` with:

```markdown
# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

## Dispatch Order: Codex First, Claude Fallback

**Step 1 — Preflight:** Check whether `codex:codex-rescue` subagent is available. If not, skip to Claude fallback.

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
Task tool (superpowers:code-reviewer):
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
```

- [ ] **Step 2: Verify the changes**

Run:
```bash
cat skills/subagent-driven-development/code-quality-reviewer-prompt.md
```
Expected: Updated file with Codex-first dispatch instructions and Claude fallback.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/code-quality-reviewer-prompt.md
git commit -m "feat: update code-quality-reviewer-prompt with Codex-first dispatch"
```

---

### Task 5: Update subagent-driven-development SKILL.md

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

- [ ] **Step 1: Update the core principle sentence (line 7)**

Replace line 7:
```
Execute plan by dispatching fresh subagent per task, with two-stage review after each: spec compliance review first, then code quality review.
```

With:
```
Execute plan by dispatching fresh subagent per task, with two-stage Codex-first review after each: spec compliance review first, then code quality review. Reviews dispatch via `codex:codex-rescue` with Claude fallback.
```

- [ ] **Step 2: Update the process diagram dispatch nodes**

In the process diagram (lines 42-85), update the three review dispatch node labels:

Replace:
```
"Dispatch spec reviewer subagent (./spec-reviewer-prompt.md)" [shape=box];
```
With:
```
"Dispatch spec reviewer (Codex → Claude fallback, ./codex-spec-reviewer-prompt.md)" [shape=box];
```

Replace:
```
"Dispatch code quality reviewer subagent (./code-quality-reviewer-prompt.md)" [shape=box];
```
With:
```
"Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)" [shape=box];
```

Replace:
```
"Dispatch final code reviewer subagent for entire implementation" [shape=box];
```
With:
```
"Dispatch final code reviewer (Codex → Claude fallback)" [shape=box];
```

Also update all edge references that mention these old node labels to use the new labels.

- [ ] **Step 3: Update the Prompt Templates section (lines 120-124)**

Replace:
```markdown
## Prompt Templates

- `./implementer-prompt.md` - Dispatch implementer subagent
- `./spec-reviewer-prompt.md` - Dispatch spec compliance reviewer subagent
- `./code-quality-reviewer-prompt.md` - Dispatch code quality reviewer subagent
```

With:
```markdown
## Prompt Templates

- `./implementer-prompt.md` - Dispatch implementer subagent
- `./codex-spec-reviewer-prompt.md` - Dispatch spec compliance reviewer (Codex, primary)
- `./spec-reviewer-prompt.md` - Dispatch spec compliance reviewer (Claude, fallback)
- `./code-quality-reviewer-prompt.md` - Dispatch code quality reviewer (Codex primary, Claude fallback)
```

- [ ] **Step 4: Add final review Codex-first instructions**

After the "Example Workflow" section (after line 200), before the "Advantages" section, add:

```markdown
## Final Review: Codex-First

After all tasks complete, dispatch the final whole-implementation review using the Codex-first pattern:

1. **Determine BASE_SHA dynamically:**
```bash
BASE_SHA=$(git merge-base HEAD $(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo main))
```
If no upstream is configured, fall back to `main`. If `main` does not exist, use the first commit of the branch.

2. **Preflight check** for `codex:codex-rescue`
3. **Dispatch Codex** with `requesting-code-review/codex-review-prompt.md`, using the resolved BASE_SHA and HEAD
4. **Validate response** against success criteria (Strengths/Issues/Assessment)
5. **Fallback** to `superpowers:code-reviewer` if needed
```

- [ ] **Step 5: Update the Integration section**

In the Integration section (lines 266-277), add `codex:codex-rescue` to the required workflow skills. After the line:
```
- **superpowers:requesting-code-review** - Code review template for reviewer subagents
```

Add:
```
- **codex:codex-rescue** (Codex plugin) - Primary review dispatcher; falls back to Claude subagents if unavailable
```

- [ ] **Step 6: Verify the changes**

Run:
```bash
cat skills/subagent-driven-development/SKILL.md
```
Expected: Updated SKILL.md with Codex-first references throughout.

- [ ] **Step 7: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: update subagent-driven-development with Codex-first review"
```

---

### Task 6: Update executing-plans SKILL.md with Review Checkpoint

**Files:**
- Modify: `skills/executing-plans/SKILL.md`

- [ ] **Step 1: Add review checkpoint to Step 2**

In `skills/executing-plans/SKILL.md`, replace the Step 2 section (lines 24-31):

```markdown
### Step 2: Execute Tasks

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed
```

With:

```markdown
### Step 2: Execute Tasks

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

**Review checkpoint:** After every 3 completed tasks (or after the final task if fewer than 3 remain), invoke `superpowers:requesting-code-review` to review the batch. Fix any Critical or Important issues before continuing to the next batch.
```

- [ ] **Step 2: Update the Integration section**

Replace the Integration section (lines 65-71):

```markdown
## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:finishing-a-development-branch** - Complete development after all tasks
```

With:

```markdown
## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:requesting-code-review** - Batch review every 3 tasks (Codex-first with Claude fallback)
- **superpowers:finishing-a-development-branch** - Complete development after all tasks
```

- [ ] **Step 3: Verify the changes**

Run:
```bash
cat skills/executing-plans/SKILL.md
```
Expected: Updated SKILL.md with review checkpoint in Step 2 and `requesting-code-review` in Integration.

- [ ] **Step 4: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "feat: add batch review checkpoint to executing-plans"
```

---

### Task 7: Update README.md with Codex Plugin Prerequisite

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add prerequisites section**

In `README.md`, after the "How it works" section (after line 15) and before the "Sponsorship" section, add:

```markdown
## Prerequisites

Superpowers works out of the box with no additional dependencies. For enhanced code review capabilities:

- **Codex Plugin (recommended):** When the [Codex plugin](https://github.com/openai/codex) for Claude Code is installed, code reviews are dispatched via Codex for an independent perspective. Without the plugin, reviews fall back to Claude subagents (fully functional).
```

- [ ] **Step 2: Verify the change**

Run:
```bash
head -25 README.md
```
Expected: New Prerequisites section visible between "How it works" and "Sponsorship".

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Codex plugin prerequisite to README"
```

---

### Task 8: Update RELEASE-NOTES.md

**Files:**
- Modify: `RELEASE-NOTES.md`

- [ ] **Step 1: Add release entry**

In `RELEASE-NOTES.md`, add the following entry at the top of the file, before the existing `## v5.0.7` entry (after line 1):

```markdown

## v5.0.8 (2026-04-22)

### Codex-First Code Review

- **requesting-code-review** — reviews now dispatch via `codex:codex-rescue` subagent (Codex plugin) as the primary reviewer, with automatic fallback to Claude subagents when Codex is unavailable. Includes preflight capability check and response validation (Strengths/Issues/Assessment sections required).
- **subagent-driven-development** — both stages of the two-stage review (spec compliance and code quality) and the final whole-implementation review now use Codex-first dispatch with Claude fallback. Final review uses dynamic `git merge-base` for stable diff boundaries across forks and worktrees.
- **executing-plans** — added explicit batch review checkpoint every 3 tasks via `superpowers:requesting-code-review`, ensuring Codex-first reviews apply to this execution path as well.
- **New templates** — added `codex-review-prompt.md` (code quality) and `codex-spec-reviewer-prompt.md` (spec compliance) for Codex-optimized review dispatch. Existing Claude templates retained as fallback.
- **Prerequisite** — Codex plugin for Claude Code is recommended but not required. Without it, all reviews fall back to Claude subagents (existing behavior).

```

- [ ] **Step 2: Verify the change**

Run:
```bash
head -20 RELEASE-NOTES.md
```
Expected: New v5.0.8 entry at the top with Codex-First Code Review section.

- [ ] **Step 3: Commit**

```bash
git add RELEASE-NOTES.md
git commit -m "docs: add v5.0.8 release notes for Codex-first review"
```
