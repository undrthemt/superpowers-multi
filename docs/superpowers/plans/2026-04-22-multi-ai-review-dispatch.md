# Multi-AI Review Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hard-coded Codex-first review routing with a provider-based dispatch mechanism that supports any CLI-based AI as a code reviewer.

**Architecture:** Provider definition JSON files describe how to invoke each reviewer CLI. A centralized `review-dispatch.md` contains the dispatch logic (provider resolution → plugin override check → CLI invocation → response validation → fallback). All skills reference this single dispatch file instead of containing their own Codex-specific routing.

**Tech Stack:** Markdown (skill files), JSON (provider definitions), Shell commands (CLI invocation)

**Spec:** `docs/superpowers/specs/2026-04-22-multi-ai-review-dispatch-design.md`

---

### Task 1: Create provider definition files

**Files:**
- Create: `skills/requesting-code-review/providers/codex.json`
- Create: `skills/requesting-code-review/providers/claude-code.json`

- [ ] **Step 1: Create providers directory**

Run:
```bash
mkdir -p skills/requesting-code-review/providers
```

- [ ] **Step 2: Create codex.json**

Create `skills/requesting-code-review/providers/codex.json`:

```json
{
  "name": "codex",
  "description": "OpenAI Codex CLI",
  "detect": "which codex",
  "invoke": {
    "command": "codex",
    "args": ["--quiet", "--prompt-file", "{{prompt_file}}"],
    "input_method": "file",
    "timeout_seconds": 300
  },
  "plugin_override": {
    "host": "claude-code",
    "subagent": "codex:codex-rescue"
  }
}
```

- [ ] **Step 3: Create claude-code.json**

Create `skills/requesting-code-review/providers/claude-code.json`:

```json
{
  "name": "claude-code",
  "description": "Anthropic Claude Code CLI",
  "detect": "which claude",
  "invoke": {
    "command": "claude",
    "args": ["-p", "--output-format", "text"],
    "input_method": "stdin",
    "timeout_seconds": 300
  },
  "plugin_override": null
}
```

- [ ] **Step 4: Verify JSON validity**

Run:
```bash
python3 -c "import json; json.load(open('skills/requesting-code-review/providers/codex.json')); print('codex.json: valid')"
python3 -c "import json; json.load(open('skills/requesting-code-review/providers/claude-code.json')); print('claude-code.json: valid')"
```
Expected: Both print "valid"

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/providers/codex.json skills/requesting-code-review/providers/claude-code.json
git commit -m "feat: add provider definition files for Codex and Claude Code CLI"
```

---

### Task 2: Refactor code quality review template to provider-agnostic format

**Files:**
- Remove: `skills/requesting-code-review/codex-review-prompt.md`
- Remove: `skills/requesting-code-review/code-reviewer.md`
- Create: `skills/requesting-code-review/review-prompt.md`

The current `codex-review-prompt.md` wraps the review prompt in a `codex:codex-rescue subagent:` block. The current `code-reviewer.md` has identical inner content with slightly different placeholder names (`{PLAN_REFERENCE}` instead of `{PLAN_OR_REQUIREMENTS}`). Both are replaced by a single provider-agnostic `review-prompt.md`.

- [ ] **Step 1: Create review-prompt.md with extracted inner content**

Create `skills/requesting-code-review/review-prompt.md` with the inner prompt content from `codex-review-prompt.md`, removing the Codex wrapper and normalizing placeholders:

```markdown
# Code Quality Review Prompt Template

This template is provider-agnostic. Dispatch is handled by review-dispatch.md.

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

{PLAN_OR_REQUIREMENTS}

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

You MUST use exactly this structure. Missing sections will cause a fallback to host AI review.

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

## Example Output

```
### Strengths
- Clean database schema with proper migrations (db.ts:15-42)
- Comprehensive test coverage (18 tests, all edge cases)
- Good error handling with fallbacks (summarizer.ts:85-92)

### Issues

#### Important
1. **Missing help text in CLI wrapper**
   - File: index-conversations:1-31
   - Issue: No --help flag, users won't discover --concurrency
   - Fix: Add --help case with usage examples

2. **Date validation missing**
   - File: search.ts:25-27
   - Issue: Invalid dates silently return no results
   - Fix: Validate ISO format, throw error with example

#### Minor
1. **Progress indicators**
   - File: indexer.ts:130
   - Issue: No "X of Y" counter for long operations
   - Impact: Users don't know how long to wait

### Recommendations
- Add progress reporting for user experience
- Consider config file for excluded projects (portability)

### Assessment

**Ready to merge: With fixes**

**Reasoning:** Core implementation is solid with good architecture and tests. Important issues (help text, date validation) are easily fixed and don't affect core functionality.
```
```

- [ ] **Step 2: Delete codex-review-prompt.md**

Run:
```bash
git rm skills/requesting-code-review/codex-review-prompt.md
```

- [ ] **Step 3: Delete code-reviewer.md**

Run:
```bash
git rm skills/requesting-code-review/code-reviewer.md
```

- [ ] **Step 4: Verify review-prompt.md has all required sections**

Run:
```bash
grep -c "## Review Checklist\|## REQUIRED Output Format\|### Strengths\|### Issues\|### Assessment\|## Critical Rules" skills/requesting-code-review/review-prompt.md
```
Expected: 6 (all sections present)

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/review-prompt.md
git commit -m "refactor: replace Codex/Claude review templates with provider-agnostic review-prompt.md"
```

---

### Task 3: Refactor spec compliance review template to provider-agnostic format

**Files:**
- Remove: `skills/subagent-driven-development/codex-spec-reviewer-prompt.md`
- Remove: `skills/subagent-driven-development/spec-reviewer-prompt.md`
- Create: `skills/subagent-driven-development/spec-review-prompt.md`

The current `codex-spec-reviewer-prompt.md` wraps the spec review prompt in a `codex:codex-rescue subagent:` block. The current `spec-reviewer-prompt.md` wraps identical content in a `Task tool (general-purpose):` block. Both are replaced by a single provider-agnostic `spec-review-prompt.md`.

- [ ] **Step 1: Create spec-review-prompt.md with extracted inner content**

Create `skills/subagent-driven-development/spec-review-prompt.md` with the inner prompt content, removing both wrappers:

```markdown
# Spec Compliance Review Prompt Template

This template is provider-agnostic. Dispatch is handled by review-dispatch.md.

**Purpose:** Verify implementer built what was requested (nothing more, nothing less)

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

You MUST output one of these two verdicts. Missing verdict will cause fallback to host AI review.

Report:
- ✅ Spec compliant (if everything matches after code inspection)
- ❌ Issues found: [list specifically what's missing or extra, with file:line references]
```

- [ ] **Step 2: Delete codex-spec-reviewer-prompt.md**

Run:
```bash
git rm skills/subagent-driven-development/codex-spec-reviewer-prompt.md
```

- [ ] **Step 3: Delete spec-reviewer-prompt.md**

Run:
```bash
git rm skills/subagent-driven-development/spec-reviewer-prompt.md
```

- [ ] **Step 4: Verify spec-review-prompt.md has required sections**

Run:
```bash
grep -c "Do Not Trust the Report\|REQUIRED Output Format\|Spec compliant\|Issues found" skills/subagent-driven-development/spec-review-prompt.md
```
Expected: 4 (all key sections present)

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/spec-review-prompt.md
git commit -m "refactor: replace Codex/Claude spec review templates with provider-agnostic spec-review-prompt.md"
```

---

### Task 4: Create review-dispatch.md

**Files:**
- Create: `skills/requesting-code-review/review-dispatch.md`

This is the centralized dispatch logic file — the single source of truth for how reviews are routed to external providers.

- [ ] **Step 1: Create review-dispatch.md**

Create `skills/requesting-code-review/review-dispatch.md`:

```markdown
# Review Dispatch Guide

Centralized dispatch logic for routing code reviews to external AI providers.
All review skills reference this file instead of containing their own dispatch logic.

## Parameters

The caller provides:
- **review_type**: `code-quality` or `spec-compliance`
- **additional_checks** (optional): markdown block appended to the prompt before dispatch
- **template_placeholders**: key-value pairs to fill in the template (e.g. DESCRIPTION, BASE_SHA, HEAD_SHA, PLAN_OR_REQUIREMENTS, WHAT_WAS_IMPLEMENTED)

## Step 1: Select Template

Based on review_type:
- `code-quality` → read `skills/requesting-code-review/review-prompt.md`
- `spec-compliance` → read `skills/subagent-driven-development/spec-review-prompt.md`

## Step 2: Resolve Provider

Check in this order (first match wins):

1. **User explicitly named a provider** in the current request (e.g. "review with gemini") → use that provider name
2. **Config file exists** at `.superpowers/review-config.json` → use the `review_provider` value
3. **No config, no explicit request** → discover and ask:
   a. Scan `skills/requesting-code-review/providers/` for all `*.json` files
   b. For each provider, run its `detect` command to check if the CLI is installed
   c. Present the user with available providers: name + description
   d. User selects one. Remember this choice for the rest of the session (do not write to disk)

## Step 3: Load Provider Definition

Read `skills/requesting-code-review/providers/<provider-name>.json`.

If the file does not exist: notify the user "Unknown review provider '<name>'. Available providers: [list names from providers/ directory]." Ask the user to choose from available providers. Remember the choice for the session.

## Step 4: Check Plugin Override

If `plugin_override` is non-null AND the current host AI matches `plugin_override.host`:

1. Fill template placeholders with caller-provided values
2. If `additional_checks` is provided, append it to the filled template
3. Dispatch as a subagent via `plugin_override.subagent` type with the filled prompt
4. Validate the response (see Step 7)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 6 (Fallback)

If `plugin_override` is null or host does not match → continue to Step 5.

## Step 5: CLI Dispatch

1. Run the provider's `detect` command via Bash
   - If it fails (non-zero exit) → go to Step 6 (Fallback)

2. Fill template placeholders with caller-provided values

3. If `additional_checks` is provided, append it to the filled template

4. Write the filled prompt to a temporary file (e.g. `/tmp/review-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
   - If `input_method` is `"file"`: replace `{{prompt_file}}` in `args` with the temp file path, then run `timeout <timeout_seconds> <command> <args...>`
   - If `input_method` is `"stdin"`: run `timeout <timeout_seconds> <command> <args...> < <temp_file>`

6. Capture stdout as the review response

7. Clean up the temporary file

8. Validate the response (see Step 7)
   - If valid → return the result (done)
   - If invalid or execution error (including timeout) → go to Step 6 (Fallback)

## Step 6: Fallback

The external provider failed. Fall back to the host AI's own review capability:

1. Notify the user: "External review via <provider-name> failed: <reason>. Falling back to host review."

2. Dispatch based on review_type:
   - `code-quality` → dispatch a `code-reviewer` subagent (or host AI equivalent) with the filled template as the prompt
   - `spec-compliance` → dispatch a `general-purpose` subagent (or host AI equivalent) with the filled template as the prompt

## Step 7: Response Validation

Validation criteria depend on review_type:

**code-quality** — response must contain ALL of:
- A "Strengths" section
- An "Issues" section with severity categorization
- An "Assessment" section with a merge verdict

**spec-compliance** — response must contain one of:
- "✅ Spec compliant"
- "❌ Issues found:" followed by a list

If required sections are missing, the response is invalid.
```

- [ ] **Step 2: Verify all dispatch steps are present**

Run:
```bash
grep -c "^## Step" skills/requesting-code-review/review-dispatch.md
```
Expected: 7

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/review-dispatch.md
git commit -m "feat: add centralized review-dispatch.md for multi-AI provider routing"
```

---

### Task 5: Update requesting-code-review/SKILL.md

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

Replace the Codex-specific dispatch logic (lines 8, 32-62, 120-122) with references to the new dispatch system.

- [ ] **Step 1: Update the opening description (line 8)**

Replace line 8:
```
Dispatch code review via `codex:codex-rescue` (primary) or `superpowers-multi:code-reviewer` (fallback) to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history. This keeps the reviewer focused on the work product, not your thought process, and preserves your own context for continued work.
```

With:
```
Dispatch code review to a configurable external AI provider (with host AI fallback) to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history. This keeps the reviewer focused on the work product, not your thought process, and preserves your own context for continued work.
```

- [ ] **Step 2: Replace the dispatch instructions (lines 24-62)**

Replace the entire "How to Request" section (from `## How to Request` through `**5. Act on feedback:**` and its bullets) with:

```markdown
## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch review:**

Read `review-dispatch.md` in this skill directory and follow its dispatch instructions with:
- review_type = code-quality
- template_placeholders:
  - `{WHAT_WAS_IMPLEMENTED}` - What you just built
  - `{PLAN_OR_REQUIREMENTS}` - What it should do
  - `{BASE_SHA}` - Starting commit
  - `{HEAD_SHA}` - Ending commit
  - `{DESCRIPTION}` - Brief summary

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)
```

- [ ] **Step 3: Update the template references at the end (lines 120-122)**

Replace:
```
See templates at:
- `codex-review-prompt.md` - Codex review (primary)
- `code-reviewer.md` - Claude review (fallback)
```

With:
```
See:
- `review-prompt.md` - Code quality review template (provider-agnostic)
- `review-dispatch.md` - Dispatch logic (provider resolution, CLI invocation, fallback)
- `providers/` - Provider definitions (codex.json, claude-code.json)
```

- [ ] **Step 4: Verify no Codex-specific references remain**

Run:
```bash
grep -i "codex\|code-reviewer\.md" skills/requesting-code-review/SKILL.md
```
Expected: No matches

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "refactor: update requesting-code-review to use generic review dispatch"
```

---

### Task 6: Update code-quality-reviewer-prompt.md

**Files:**
- Modify: `skills/subagent-driven-development/code-quality-reviewer-prompt.md`

Replace the entire file content (Codex-first/Claude fallback dispatch logic) with a reference to `review-dispatch.md` plus the additional checks.

- [ ] **Step 1: Replace entire file content**

Replace all content of `skills/subagent-driven-development/code-quality-reviewer-prompt.md` with:

```markdown
# Code Quality Reviewer Dispatch

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

For code quality review dispatch, read `skills/requesting-code-review/review-dispatch.md`
and follow its instructions with:
- review_type = code-quality
- additional_checks = the "Additional Checks" block below

## Additional Checks (subagent-driven-development specific)

In addition to standard code quality concerns, the reviewer should check:
- Does each file have one clear responsibility with a well-defined interface?
- Are units decomposed so they can be understood and tested independently?
- Is the implementation following the file structure from the plan?
- Did this implementation create new files that are already large, or significantly grow existing files? (Don't flag pre-existing file sizes — focus on what this change contributed.)

**Code reviewer returns:** Strengths, Issues (Critical/Important/Minor), Assessment
```

- [ ] **Step 2: Verify no Codex-specific references remain**

Run:
```bash
grep -i "codex\|code-reviewer\.md" skills/subagent-driven-development/code-quality-reviewer-prompt.md
```
Expected: No matches

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/code-quality-reviewer-prompt.md
git commit -m "refactor: update code-quality-reviewer-prompt to use generic review dispatch"
```

---

### Task 7: Update subagent-driven-development/SKILL.md

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

This is the largest change. Multiple sections reference Codex-specific dispatch patterns. All must be updated to reference the generic dispatch system.

- [ ] **Step 1: Update opening description (line 8)**

Replace:
```
Execute plan by dispatching fresh subagent per task, with two-stage Codex-first review after each: spec compliance review first, then code quality review. Reviews dispatch via `codex:codex-rescue` with Claude fallback.
```

With:
```
Execute plan by dispatching fresh subagent per task, with two-stage external review after each: spec compliance review first, then code quality review. Reviews dispatch via a configurable external AI provider with host AI fallback (see `skills/requesting-code-review/review-dispatch.md`).
```

- [ ] **Step 2: Update core principle (line 12)**

Replace:
```
**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration
```

With:
```
**Core principle:** Fresh subagent per task + two-stage external review (spec then quality) = high quality, fast iteration
```

- [ ] **Step 3: Update Graphviz diagram node labels (lines 52, 55, 63)**

Replace line 52:
```
        "Dispatch spec reviewer (Codex → Claude fallback, ./codex-spec-reviewer-prompt.md)" [shape=box];
```
With:
```
        "Dispatch spec reviewer (external provider → host fallback, ./spec-review-prompt.md)" [shape=box];
```

Replace line 55:
```
        "Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)" [shape=box];
```
With:
```
        "Dispatch code quality reviewer (external provider → host fallback, ./code-quality-reviewer-prompt.md)" [shape=box];
```

Replace line 63:
```
    "Dispatch final code reviewer (Codex → Claude fallback)" [shape=box];
```
With:
```
    "Dispatch final code reviewer (external provider → host fallback)" [shape=box];
```

- [ ] **Step 4: Update Graphviz diagram edge labels that reference old file names**

Replace all occurrences of `codex-spec-reviewer-prompt.md` in the diagram edges (lines 71, 72, 74) with `spec-review-prompt.md`:

Line 71:
```
    "Implementer subagent implements, tests, commits, self-reviews" -> "Dispatch spec reviewer (Codex → Claude fallback, ./codex-spec-reviewer-prompt.md)";
```
With:
```
    "Implementer subagent implements, tests, commits, self-reviews" -> "Dispatch spec reviewer (external provider → host fallback, ./spec-review-prompt.md)";
```

Line 72:
```
    "Dispatch spec reviewer (Codex → Claude fallback, ./codex-spec-reviewer-prompt.md)" -> "Spec reviewer subagent confirms code matches spec?";
```
With:
```
    "Dispatch spec reviewer (external provider → host fallback, ./spec-review-prompt.md)" -> "Spec reviewer subagent confirms code matches spec?";
```

Line 74:
```
    "Implementer subagent fixes spec gaps" -> "Dispatch spec reviewer (Codex → Claude fallback, ./codex-spec-reviewer-prompt.md)" [label="re-review"];
```
With:
```
    "Implementer subagent fixes spec gaps" -> "Dispatch spec reviewer (external provider → host fallback, ./spec-review-prompt.md)" [label="re-review"];
```

- [ ] **Step 5: Update remaining Graphviz edges that reference code quality reviewer with old label**

Replace all occurrences of `"Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)"` in edge lines (75, 76, 78) with `"Dispatch code quality reviewer (external provider → host fallback, ./code-quality-reviewer-prompt.md)"`:

Line 75:
```
    "Spec reviewer subagent confirms code matches spec?" -> "Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)" [label="yes"];
```
With:
```
    "Spec reviewer subagent confirms code matches spec?" -> "Dispatch code quality reviewer (external provider → host fallback, ./code-quality-reviewer-prompt.md)" [label="yes"];
```

Line 76:
```
    "Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)" -> "Code quality reviewer subagent approves?";
```
With:
```
    "Dispatch code quality reviewer (external provider → host fallback, ./code-quality-reviewer-prompt.md)" -> "Code quality reviewer subagent approves?";
```

Line 78:
```
    "Implementer subagent fixes quality issues" -> "Dispatch code quality reviewer (Codex → Claude fallback, ./code-quality-reviewer-prompt.md)" [label="re-review"];
```
With:
```
    "Implementer subagent fixes quality issues" -> "Dispatch code quality reviewer (external provider → host fallback, ./code-quality-reviewer-prompt.md)" [label="re-review"];
```

- [ ] **Step 6: Update Graphviz final reviewer edge (line 82)**

Replace:
```
    "More tasks remain?" -> "Dispatch final code reviewer (Codex → Claude fallback)" [label="no"];
```
With:
```
    "More tasks remain?" -> "Dispatch final code reviewer (external provider → host fallback)" [label="no"];
```

- [ ] **Step 7: Update Prompt Templates section (lines 120-125)**

Replace:
```
## Prompt Templates

- `./implementer-prompt.md` - Dispatch implementer subagent
- `./codex-spec-reviewer-prompt.md` - Dispatch spec compliance reviewer (Codex, primary)
- `./spec-reviewer-prompt.md` - Dispatch spec compliance reviewer (Claude, fallback)
- `./code-quality-reviewer-prompt.md` - Dispatch code quality reviewer (Codex primary, Claude fallback)
```

With:
```
## Prompt Templates

- `./implementer-prompt.md` - Dispatch implementer subagent
- `./spec-review-prompt.md` - Spec compliance review template (provider-agnostic)
- `./code-quality-reviewer-prompt.md` - Code quality review dispatch reference (delegates to `review-dispatch.md`)
- `skills/requesting-code-review/review-dispatch.md` - Centralized dispatch logic for all review types
```

- [ ] **Step 8: Update Final Review section (lines 203-216)**

Replace the entire "Final Review: Codex-First" section:
```
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
5. **Fallback** to `superpowers-multi:code-reviewer` if needed
```

With:
```
## Final Review

After all tasks complete, dispatch the final whole-implementation review:

1. **Determine BASE_SHA dynamically:**
```bash
BASE_SHA=$(git merge-base HEAD $(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo main))
```
If no upstream is configured, fall back to `main`. If `main` does not exist, use the first commit of the branch.

2. **Dispatch review** by reading `skills/requesting-code-review/review-dispatch.md` and following its instructions with:
   - review_type = code-quality
   - BASE_SHA = the dynamically determined value above
   - HEAD_SHA = current HEAD
   - DESCRIPTION = "Final whole-implementation review for [plan name]"
   - PLAN_OR_REQUIREMENTS = full plan content
```

- [ ] **Step 9: Update Integration section (lines 281-294)**

Replace:
```
## Integration

**Required workflow skills:**
- **superpowers-multi:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers-multi:writing-plans** - Creates the plan this skill executes
- **superpowers-multi:requesting-code-review** - Code review template for reviewer subagents
- **codex:codex-rescue** (Codex plugin) - Primary review dispatcher; falls back to Claude subagents if unavailable
- **superpowers-multi:finishing-a-development-branch** - Complete development after all tasks

**Subagents should use:**
- **superpowers-multi:test-driven-development** - Subagents follow TDD for each task

**Alternative workflow:**
- **superpowers-multi:executing-plans** - Use for parallel session instead of same-session execution
```

With:
```
## Integration

**Required workflow skills:**
- **superpowers-multi:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers-multi:writing-plans** - Creates the plan this skill executes
- **superpowers-multi:requesting-code-review** - Code review templates and dispatch logic
- **review-dispatch.md** - Configurable external review provider with host AI fallback
- **superpowers-multi:finishing-a-development-branch** - Complete development after all tasks

**Subagents should use:**
- **superpowers-multi:test-driven-development** - Subagents follow TDD for each task

**Alternative workflow:**
- **superpowers-multi:executing-plans** - Use for parallel session instead of same-session execution
```

- [ ] **Step 10: Verify no Codex-specific dispatch references remain**

Run:
```bash
grep -n "codex:codex-rescue\|Codex-First\|codex-spec-reviewer\|Codex → Claude" skills/subagent-driven-development/SKILL.md
```
Expected: No matches

- [ ] **Step 11: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "refactor: update subagent-driven-development to use generic review dispatch"
```

---

### Task 8: Update executing-plans/SKILL.md

**Files:**
- Modify: `skills/executing-plans/SKILL.md:72`

Minimal change — update the parenthetical description in the Integration section.

- [ ] **Step 1: Update Integration section (line 72)**

Replace:
```
- **superpowers-multi:requesting-code-review** - Batch review every 3 tasks (Codex-first with Claude fallback)
```

With:
```
- **superpowers-multi:requesting-code-review** - Batch review every 3 tasks (configurable external provider with host fallback)
```

- [ ] **Step 2: Verify change**

Run:
```bash
grep "requesting-code-review" skills/executing-plans/SKILL.md
```
Expected: Contains "configurable external provider with host fallback"

- [ ] **Step 3: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "refactor: update executing-plans integration description for generic review dispatch"
```

---

### Task 9: Cross-file consistency verification

**Files:** All modified files

Final verification that all references are consistent across the entire change set.

- [ ] **Step 1: Verify no remaining references to deleted files**

Run:
```bash
grep -rn "codex-review-prompt\.md\|codex-spec-reviewer-prompt\.md\|spec-reviewer-prompt\.md" skills/
```
Expected: No matches (all old file references should be removed)

- [ ] **Step 2: Verify no remaining references to code-reviewer.md in skills (excluding reference docs)**

Run:
```bash
grep -rn "code-reviewer\.md" skills/ --exclude-dir="using-superpowers"
```
Expected: No matches in skill files (only `agents/code-reviewer.md` should exist, but it's not referenced from skills/ anymore)

Note: `skills/using-superpowers/references/codex-tools.md` may still reference `code-reviewer.md` in the context of Codex tool mapping examples. That file describes how `agents/code-reviewer.md` (the subagent definition, which is preserved) maps to Codex's `spawn_agent`. This reference remains valid.

- [ ] **Step 3: Verify review-dispatch.md is referenced where expected**

Run:
```bash
grep -rn "review-dispatch\.md" skills/
```
Expected: References in:
- `skills/requesting-code-review/SKILL.md`
- `skills/subagent-driven-development/SKILL.md`
- `skills/subagent-driven-development/code-quality-reviewer-prompt.md`

- [ ] **Step 4: Verify new template files exist**

Run:
```bash
ls -la skills/requesting-code-review/review-prompt.md skills/requesting-code-review/review-dispatch.md skills/subagent-driven-development/spec-review-prompt.md skills/requesting-code-review/providers/*.json
```
Expected: All 5 files exist

- [ ] **Step 5: Verify old files are gone**

Run:
```bash
ls skills/requesting-code-review/codex-review-prompt.md skills/requesting-code-review/code-reviewer.md skills/subagent-driven-development/codex-spec-reviewer-prompt.md skills/subagent-driven-development/spec-reviewer-prompt.md 2>&1
```
Expected: All 4 files show "No such file or directory"

- [ ] **Step 6: Full grep for any remaining Codex dispatch patterns**

Run:
```bash
grep -rn "codex:codex-rescue" skills/ --include="*.md"
```
Expected: No matches (Codex dispatch is now only in `providers/codex.json` as `plugin_override.subagent`, and in `review-dispatch.md` as a generic mechanism)

Note: `codex:codex-rescue` may still appear in `review-dispatch.md` as part of the generic plugin_override explanation — that's acceptable since it's an example, not a hard-coded dispatch.

- [ ] **Step 7: Commit any remaining fixes (if Step 1-6 found issues)**

If any inconsistencies were found and fixed:
```bash
git add -A
git commit -m "fix: resolve cross-file reference inconsistencies in review dispatch"
```

If no issues found, skip this step.
