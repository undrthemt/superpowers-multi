# SDD/Review Dispatch HARD-GATE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the silent v5.0.11 dispatch bypass by adding HARD-GATE blocks and mandatory Step 0 config detection at the top of both SDD and requesting-code-review skills, plus reinforcing language and a defense-in-depth caller-contract block in the dispatcher files.

**Architecture:** Pure documentation / skill-prose changes across four files. No code, no providers, no schema changes. The fix layers (1) an unmistakable HARD-GATE at skill entry, (2) a mandatory config-detection Step 0 that fires before any dispatch decision, (3) consistent rewording from "invoke" to "Read and follow", (4) example/template updates so the reads are visible in the canonical flow, and (5) a caller-contract block in `coding-dispatch.md` / `review-dispatch.md` that catches host AIs who partially read and then paraphrase.

**Tech Stack:** Markdown only. Verification uses `grep`, `test -f`, and a manual evaluation matrix (S1, S2, S3) run by the maintainer in fresh Claude Opus sessions.

**Source spec:** `docs/superpowers/specs/2026-05-13-sdd-dispatch-hard-gate-design.md`

---

## File Structure

Files modified:

- `skills/subagent-driven-development/SKILL.md` — HARD-GATE, Step 0, mini decision tree, verb rewording, example workflow, TodoWrite template
- `skills/requesting-code-review/SKILL.md` — HARD-GATE, Step 0 (review-only variant), verb rewording, small example update
- `skills/subagent-driven-development/coding-dispatch.md` — caller-contract block at top
- `skills/requesting-code-review/review-dispatch.md` — caller-contract block at top
- `RELEASE-NOTES.md` — v5.0.12 entry
- `.claude-plugin/plugin.json` — version bump
- `.claude-plugin/marketplace.json` — version bump
- `.cursor-plugin/plugin.json` — version bump
- `gemini-extension.json` — version bump
- `package.json` — version bump

Files NOT modified: template `.md` files (coding-prompt, coding-fallback-prompt, spec-review-prompt, code-quality-reviewer-prompt, review-prompt), provider JSON files, config-loading.md.

---

## Task 1: Add HARD-GATE + Step 0 to SDD SKILL.md
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

The HARD-GATE goes immediately after the existing one-paragraph intro and the "Coding dispatch:" / "Why subagents:" / "Core principle:" lines, but BEFORE the `## When to Use` heading. Step 0 goes at the top of the `## The Process` section, immediately before the existing flow diagram.

- [ ] **Step 1: Read the current SKILL.md to confirm insertion anchors**

Run: `grep -n "## When to Use\|## The Process\|Core principle:" skills/subagent-driven-development/SKILL.md`

Expected output includes lines for "Core principle:" (around line 14), "## When to Use" (around line 16), and "## The Process" (around line 42).

- [ ] **Step 2: Insert HARD-GATE after "Core principle:" line**

Find the existing line `**Core principle:** Fresh subagent per task + two-stage external review (spec then quality) = high quality, fast iteration` in `skills/subagent-driven-development/SKILL.md`.

Insert AFTER that line (and one blank line after it), BEFORE `## When to Use`:

```markdown
<HARD-GATE>
Do NOT use the Agent tool directly for task implementation, spec
review, or code-quality review while executing this skill.

For implementation: you MUST `Read` `./coding-dispatch.md` and follow
its logic. Direct `Agent` dispatch bypasses the user's `coding.rules`
configuration and silently ignores their chosen provider.

For review (spec or code quality): you MUST `Read`
`./spec-review-prompt.md` and `./code-quality-reviewer-prompt.md`,
which delegate to `skills/requesting-code-review/review-dispatch.md`.
Direct review-agent dispatch bypasses the user's `review_provider`
configuration.

These files exist in the same directory as this SKILL.md (or one
directory over for review-dispatch.md). If you have not read them yet
in this session, do so before any task work — every session, no
exceptions.
</HARD-GATE>
```

- [ ] **Step 3: Insert Step 0 at the top of "The Process"**

Find the heading `## The Process` in `skills/subagent-driven-development/SKILL.md`. Insert the following BETWEEN the heading and the existing flow diagram code fence:

````markdown
### Step 0 — Configuration detection (MANDATORY before any task work)

Run a single check at the very start of the session, before the flow diagram below:

```bash
ls -la .superpowers/review-config.json \
       "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \
       2>/dev/null
```

**If either file exists:**
- Read the file(s).
- Note `review_provider` and `coding.rules` values.
- You MUST go through `./coding-dispatch.md` (for implementation) and
  `../requesting-code-review/review-dispatch.md` (for review) for the
  rest of this session. Direct `Agent` dispatch is forbidden.

**If neither file exists:**
- There is no multi-AI configuration to honor.
- Dispatch still goes through `./coding-dispatch.md` and the review
  prompts — they handle the no-config case by falling through to the
  host implementer / reviewer. The HARD-GATE remains in force.

After Step 0 is complete, proceed with the flow diagram below.
````

- [ ] **Step 4: Verify both insertions present**

Run:
```bash
grep -c "<HARD-GATE>" skills/subagent-driven-development/SKILL.md
grep -c "Step 0 — Configuration detection" skills/subagent-driven-development/SKILL.md
```

Expected: both commands print `1`.

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(sdd): add HARD-GATE and Step 0 config detection to SKILL.md"
```

---

## Task 2: Add mini dispatch decision tree to SDD SKILL.md
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

The mini decision tree is a 20-line summary that follows the HARD-GATE so the host AI sees the routing logic without having to fully load `coding-dispatch.md` first. It replaces (not augments) the existing brief `## Task Implementation: Always Through coding-dispatch.md` section added in v5.0.11.

- [ ] **Step 1: Locate the existing section to replace**

Run: `grep -n "## Task Implementation: Always Through coding-dispatch.md" skills/subagent-driven-development/SKILL.md`

Expected: one line, around line 93.

- [ ] **Step 2: Replace the existing section**

Find the existing section in `skills/subagent-driven-development/SKILL.md`:

```markdown
## Task Implementation: Always Through coding-dispatch.md

For each task, **always** invoke `./coding-dispatch.md` with the
classified `task_category`. This is the only correct entry point for
task implementation in SDD.

**Do not** dispatch `./coding-fallback-prompt.md` (or its predecessor
`./implementer-prompt.md`) directly — bypassing `coding-dispatch.md`
ignores the user's `coding.rules` configuration and prevents the
configured external AI provider from being used.

The dispatcher itself decides whether to route to an external provider
or fall back to the host implementer; that decision belongs to
`coding-dispatch.md`, not to the SDD controller.
```

Replace the entire block (heading through final paragraph) with:

```markdown
## Dispatch decision summary

(Full logic lives in `./coding-dispatch.md` and
`../requesting-code-review/review-dispatch.md`. You must still `Read`
those files and follow them; this summary is only to orient you.)

**For each task (implementation):**

1. Look up `task_category` (plan tag or AI classification).
2. Check `merged_config.coding.rules` for a `category` match → use
   that rule's `provider`.
3. Otherwise use `merged_config.coding.default_provider`.
4. If no config matches → fall through to the host AI implementer
   (`./coding-fallback-prompt.md`) via the dispatcher.

**For each review (spec, then code quality):**

1. `Read` `./spec-review-prompt.md` / `./code-quality-reviewer-prompt.md`.
2. Each delegates to `../requesting-code-review/review-dispatch.md`,
   which resolves the provider from `merged_config.review_provider`.
3. If no provider matches → host AI fallback reviewer.

**Do not** short-circuit any of this by calling `Agent(...)` directly.
The dispatcher files own these decisions. Direct `Agent` dispatch
silently bypasses the user's `review-config.json`.
```

- [ ] **Step 3: Verify the new heading exists and the old one is gone**

Run:
```bash
grep -c "## Dispatch decision summary" skills/subagent-driven-development/SKILL.md
grep -c "## Task Implementation: Always Through coding-dispatch.md" skills/subagent-driven-development/SKILL.md
```

Expected: first command prints `1`, second prints `0`.

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(sdd): replace 'Always Through' section with mini dispatch decision tree"
```

---

## Task 3: Reword "invoke" → "Read and follow" in SDD SKILL.md
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

The verb "invoke" collides with the `Agent` tool's "dispatch" semantics in the host AI's mental model. This task rewords those collisions in the existing text (not the new HARD-GATE or decision tree, which already use the correct verbs).

- [ ] **Step 1: Locate every remaining "invoke" reference**

Run: `grep -n "invoke\|Invoke" skills/subagent-driven-development/SKILL.md`

Expected hits (approximate, exact line numbers will vary after Task 1 & 2's insertions):

- The flow diagram's `"Dispatch coding-dispatch.md ..."` node label
- `## Templates and dispatchers` section: `host AI invokes these directly` line and the `Internal templates (invoked by coding-dispatch.md, not directly)` line

- [ ] **Step 2: Reword the flow diagram node**

Find the line in the flow diagram inside `## The Process`:

```
"Dispatch coding-dispatch.md (the only entry point)" [shape=box];
```

and the corresponding two arrow references using the same string. Replace **all three occurrences** of `"Dispatch coding-dispatch.md (the only entry point)"` with `"Read & follow coding-dispatch.md (the only entry point)"`.

- [ ] **Step 3: Reword the Templates and dispatchers section**

Find the section header `## Templates and dispatchers` and the line:

```markdown
**Entry points (host AI invokes these directly):**
```

Replace with:

```markdown
**Entry points (host AI `Read`s these and follows their instructions — do NOT call `Agent` directly with these as references):**
```

Find the line:

```markdown
**Internal templates (invoked by `coding-dispatch.md`, not directly):**
```

Replace with:

```markdown
**Internal templates (used by `coding-dispatch.md` from its dispatch logic, not invoked directly by the host AI):**
```

- [ ] **Step 4: Verify no top-level "invoke X.md" instruction remains**

Run:
```bash
grep -nE "invoke .*\.md|invoke \`\./" skills/subagent-driven-development/SKILL.md
```

Expected: zero matches. (The strings "the implementer subagent invokes the test runner" or similar non-dispatch uses of "invoke" are fine if present, but no remaining `invoke X.md` instruction.)

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(sdd): replace 'invoke X.md' with 'Read & follow X.md' in SKILL.md"
```

---

## Task 4: Update example workflow and TodoWrite template in SDD SKILL.md
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

The current example workflow narrates dispatches without showing the host AI `Read`ing the dispatcher files first. This task makes the read sequence the canonical opening of the example, and revises the implicit todo structure.

- [ ] **Step 1: Locate the example workflow**

Run: `grep -n "## Example Workflow" skills/subagent-driven-development/SKILL.md`

Expected: one line.

- [ ] **Step 2: Replace the example's opening block**

Find the existing opening of the `## Example Workflow` code block:

```
You: I'm using Subagent-Driven Development to execute this plan.

[Read plan file once: docs/superpowers/plans/feature-plan.md]
[Extract all 5 tasks with full text and context]
[Create TodoWrite with all tasks]
```

Replace with:

```
You: I'm using Subagent-Driven Development to execute this plan.

[Step 0: Check for review-config.json]
[ls -la .superpowers/review-config.json ~/.config/superpowers/review-config.json 2>/dev/null]
[Found ~/.config/superpowers/review-config.json: review_provider=codex, coding.rules: backend→codex]

[Load dispatch logic — once per session:]
[Read ./coding-dispatch.md]
[Read ./spec-review-prompt.md]
[Read ./code-quality-reviewer-prompt.md]
[Read ../requesting-code-review/review-dispatch.md]

[Read plan file once: docs/superpowers/plans/feature-plan.md]
[Extract all 5 tasks with full text and context]
[Create TodoWrite with all tasks — per-task template:
  - Classify task category
  - Dispatch implementation via coding-dispatch.md
  - Dispatch spec review via spec-review-prompt.md
  - Dispatch code quality review via code-quality-reviewer-prompt.md
  - Mark task complete]
```

- [ ] **Step 3: Verify the example shows the reads**

Run: `grep -c "Read ./coding-dispatch.md" skills/subagent-driven-development/SKILL.md`

Expected: at least `1` (the example block).

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(sdd): show config detection and dispatcher reads in example workflow"
```

---

## Task 5: Add HARD-GATE + Step 0 to requesting-code-review SKILL.md
category: backend

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

The review skill is used both inside SDD (where the SDD gate already covers it) and standalone (where it needs its own gate).

- [ ] **Step 1: Locate the existing intro and "How to Request" heading**

Run: `grep -n "## When to Request Review\|## How to Request\|^Dispatch code review" skills/requesting-code-review/SKILL.md`

Expected: lines for the intro paragraph (starting "Dispatch code review..."), `## When to Request Review`, and `## How to Request`.

- [ ] **Step 2: Insert HARD-GATE after the intro paragraph**

Find the line `**Core principle:** Review early, review often.` in `skills/requesting-code-review/SKILL.md`.

Insert AFTER that line (with one blank line before and after), BEFORE `## When to Request Review`:

```markdown
<HARD-GATE>
Do NOT use the Agent tool directly to dispatch a code review while
executing this skill.

You MUST `Read` `./review-dispatch.md` and follow its dispatch logic.
Direct `Agent` dispatch (e.g. `Agent(subagent_type: 'code-reviewer')`)
bypasses the user's `review_provider` configuration and silently
ignores their chosen review provider.

If you have not read `./review-dispatch.md` yet in this session, do so
before requesting any review. Every session, no exceptions.
</HARD-GATE>
```

- [ ] **Step 3: Insert Step 0 at the top of "How to Request"**

Find the heading `## How to Request` in `skills/requesting-code-review/SKILL.md`. Insert IMMEDIATELY AFTER the heading, BEFORE the existing `**1. Get git SHAs:**` step:

````markdown
**0. Configuration detection (MANDATORY before any review dispatch):**

```bash
ls -la .superpowers/review-config.json \
       "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \
       2>/dev/null
```

- If either file exists → read it, note `review_provider`, then go
  through `./review-dispatch.md`. Direct `Agent` dispatch is
  forbidden for this session.
- If neither exists → review still flows through `./review-dispatch.md`,
  which falls through to the host AI reviewer.

````

- [ ] **Step 4: Verify both insertions**

Run:
```bash
grep -c "<HARD-GATE>" skills/requesting-code-review/SKILL.md
grep -c "^\*\*0\. Configuration detection" skills/requesting-code-review/SKILL.md
```

Expected: both commands print `1`.

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "feat(review): add HARD-GATE and Step 0 config detection to requesting-code-review"
```

---

## Task 6: Reword "invoke" → "Read and follow" in requesting-code-review SKILL.md
category: backend

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

- [ ] **Step 1: Locate any "invoke" / dispatch-verb collisions**

Run: `grep -n "invoke\|Invoke\|Dispatch superpowers-multi:code-reviewer" skills/requesting-code-review/SKILL.md`

Expected hits include the example block line `[Dispatch superpowers-multi:code-reviewer subagent]`.

- [ ] **Step 2: Reword the example block**

Find the line in the `## Example` section:

```
[Dispatch superpowers-multi:code-reviewer subagent]
```

Replace with:

```
[Read ./review-dispatch.md → it resolves provider from review-config.json → dispatches via that provider's CLI or falls back to a host code-reviewer subagent]
```

- [ ] **Step 3: Reword the "How to Request" step 2 heading wording**

Find the line:

```markdown
**2. Dispatch review:**

Read `review-dispatch.md` in this skill directory and follow its dispatch instructions with:
```

The text already says "Read ... and follow" — keep that. But change the heading to remove the bare "Dispatch" verb that could be confused with `Agent` dispatch:

```markdown
**2. Read `./review-dispatch.md` and follow its dispatch logic:**

Pass these template_placeholders:
```

- [ ] **Step 4: Verify the rewording**

Run:
```bash
grep -nE "Dispatch superpowers-multi:code-reviewer" skills/requesting-code-review/SKILL.md
```

Expected: zero matches.

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "feat(review): rephrase 'Dispatch' references to 'Read and follow review-dispatch.md'"
```

---

## Task 7: Add caller-contract block to coding-dispatch.md
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/coding-dispatch.md`

Defense in depth: a one-paragraph block at the top catches host AIs that partially read the file and then paraphrase the routing logic.

- [ ] **Step 1: Locate the file's top intro**

Run: `head -5 skills/subagent-driven-development/coding-dispatch.md`

Expected: the heading `# Coding Dispatch Guide` followed by the existing two-line intro and a blank line.

- [ ] **Step 2: Insert caller-contract block after the intro**

In `skills/subagent-driven-development/coding-dispatch.md`, find the existing lines:

```markdown
# Coding Dispatch Guide

Centralized dispatch logic for routing implementation tasks to external AI providers.
Mirrors the review dispatch pattern (`skills/requesting-code-review/review-dispatch.md`).
```

Insert IMMEDIATELY AFTER those lines (with one blank line between), BEFORE the `## Parameters` heading:

```markdown
> **Caller contract:** If you reached this file as a host AI executing
> SDD or another dispatch flow, you MUST follow the steps below from
> Step 1 onward. Do not skim and then call the `Agent` tool with what
> you remember — the routing logic (session state, disk checks,
> fallbacks) is load-bearing. Direct `Agent` dispatch silently bypasses
> the user's `coding.rules` configuration.
```

- [ ] **Step 3: Verify the block exists**

Run: `grep -c "Caller contract" skills/subagent-driven-development/coding-dispatch.md`

Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/coding-dispatch.md
git commit -m "feat(sdd): add caller-contract block to coding-dispatch.md"
```

---

## Task 8: Add caller-contract block to review-dispatch.md
category: backend

**Files:**
- Modify: `skills/requesting-code-review/review-dispatch.md`

- [ ] **Step 1: Locate the file's top intro**

Run: `head -5 skills/requesting-code-review/review-dispatch.md`

Expected: the heading `# Review Dispatch Guide` followed by the existing two-line intro and a blank line.

- [ ] **Step 2: Insert caller-contract block after the intro**

In `skills/requesting-code-review/review-dispatch.md`, find the existing lines:

```markdown
# Review Dispatch Guide

Centralized dispatch logic for routing code reviews to external AI providers.
All review skills reference this file instead of containing their own dispatch logic.
```

Insert IMMEDIATELY AFTER those lines (with one blank line between), BEFORE the `## Parameters` heading:

```markdown
> **Caller contract:** If you reached this file as a host AI executing
> SDD or requesting-code-review, you MUST follow the steps below from
> Step 1 onward. Do not skim and then call the `Agent` tool with what
> you remember — the routing logic (provider resolution, plugin
> override, CLI dispatch, fallback) is load-bearing. Direct `Agent`
> dispatch silently bypasses the user's `review_provider` configuration.
```

- [ ] **Step 3: Verify the block exists**

Run: `grep -c "Caller contract" skills/requesting-code-review/review-dispatch.md`

Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/requesting-code-review/review-dispatch.md
git commit -m "feat(review): add caller-contract block to review-dispatch.md"
```

---

## Task 9: Static verification of all prose changes
category: backend

**Files:**
- (read-only verification across the four modified files)

- [ ] **Step 1: Run the static-check suite**

Run the following block as a single script in the repo root:

```bash
set -e

echo "=== HARD-GATE blocks present ==="
test "$(grep -c '<HARD-GATE>' skills/subagent-driven-development/SKILL.md)" -ge 1
test "$(grep -c '<HARD-GATE>' skills/requesting-code-review/SKILL.md)" -ge 1

echo "=== Step 0 present in both SKILL.md files ==="
grep -q "Step 0 — Configuration detection" skills/subagent-driven-development/SKILL.md
grep -q "^\*\*0\. Configuration detection" skills/requesting-code-review/SKILL.md

echo "=== Caller-contract present in both dispatcher files ==="
grep -q "Caller contract" skills/subagent-driven-development/coding-dispatch.md
grep -q "Caller contract" skills/requesting-code-review/review-dispatch.md

echo "=== No 'invoke X.md' instruction left in either SKILL.md ==="
! grep -nE "invoke [\`'\"]?\./.*\.md" skills/subagent-driven-development/SKILL.md
! grep -nE "invoke [\`'\"]?\./.*\.md" skills/requesting-code-review/SKILL.md

echo "=== Dispatch decision summary section present in SDD ==="
grep -q "## Dispatch decision summary" skills/subagent-driven-development/SKILL.md

echo "=== Old 'Always Through coding-dispatch.md' heading removed ==="
! grep -q "## Task Implementation: Always Through coding-dispatch.md" skills/subagent-driven-development/SKILL.md

echo "=== Example workflow shows the read sequence ==="
grep -q "Read \./coding-dispatch.md" skills/subagent-driven-development/SKILL.md

echo "All static checks passed."
```

Expected output: a series of `===` lines followed by `All static checks passed.` Exit code 0.

- [ ] **Step 2: If any check fails, fix it and rerun**

If a check fails, identify which file is missing the expected change, return to the corresponding earlier task, and apply the missing edit. Then rerun the full block. Do not modify the check script itself.

- [ ] **Step 3: No commit required if all checks pass**

This task does not modify any files. Move on once the script exits 0.

---

## Task 10: Bump version 5.0.11 → 5.0.12 and add release notes
category: backend

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.cursor-plugin/plugin.json`
- Modify: `gemini-extension.json`
- Modify: `package.json`
- Modify: `RELEASE-NOTES.md`

- [ ] **Step 1: Identify every place "5.0.11" appears in version manifests**

Run:
```bash
grep -n "5\.0\.11" \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .cursor-plugin/plugin.json \
  gemini-extension.json \
  package.json
```

Expected: at least one match per file. Note the exact JSON key (`"version"`) for each.

- [ ] **Step 2: Update each manifest's version field from 5.0.11 to 5.0.12**

In each of the five files above, replace the single `"version": "5.0.11"` line (or equivalent — exact JSON quoting varies by file) with `"version": "5.0.12"`. Do not change any other field.

- [ ] **Step 3: Add v5.0.12 release notes entry**

Open `RELEASE-NOTES.md`. Find the existing heading `## v5.0.11 (2026-05-08)`. Insert the following BEFORE that heading (so v5.0.12 appears at the top, matching the file's reverse-chronological order):

```markdown
## v5.0.12 (2026-05-13)

### SDD / requesting-code-review: HARD-GATE against silent dispatch bypass (fork-specific)

Addresses a real-world bypass observed on v5.0.11: the host Claude silently used `Agent(subagent_type: 'general-purpose')` and `Agent(subagent_type: 'superpowers-multi:code-reviewer')` for an entire branch instead of reading and following `coding-dispatch.md` / `review-dispatch.md`, ignoring the user's `~/.config/superpowers/review-config.json` (`review_provider: codex`, `coding.rules: backend→codex`). The user only discovered the bypass by asking afterwards.

- **`<HARD-GATE>` block** added near the top of `skills/subagent-driven-development/SKILL.md` and `skills/requesting-code-review/SKILL.md`, copying the gate pattern proven to work in `brainstorming`.
- **`Step 0 — Configuration detection`** is now MANDATORY before any dispatch decision. A single `ls` checks for `.superpowers/review-config.json` and the global config; if either exists, direct `Agent` dispatch is forbidden for the session.
- **`## Dispatch decision summary`** replaces the v5.0.11 `## Task Implementation: Always Through coding-dispatch.md` section. The new section is a 20-line summary of the routing logic that orients the host AI without inviting it to paraphrase the canonical files.
- **Verb rewording:** every `invoke X.md` in both SKILL.md files becomes `Read X.md and follow its instructions`, removing the collision with the `Agent` tool's "dispatch" verb.
- **Example workflow** explicitly shows the Step 0 check and the `Read ./coding-dispatch.md` / `Read ./spec-review-prompt.md` / `Read ./code-quality-reviewer-prompt.md` / `Read ../requesting-code-review/review-dispatch.md` sequence as the canonical opening.
- **Caller-contract block** added at the top of `coding-dispatch.md` and `review-dispatch.md` to catch host AIs that partially read the file and then paraphrase.
- **No code, schema, or provider changes.** Pure prose changes across four skill files. No migration required. Long-lived sessions that loaded v5.0.11 SKILL.md need to be restarted for the gate to take effect.

Source: `docs/superpowers/specs/2026-05-13-sdd-dispatch-hard-gate-design.md`.

```

- [ ] **Step 4: Verify the version is consistent everywhere**

Run:
```bash
grep -l "5\.0\.11" \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .cursor-plugin/plugin.json \
  gemini-extension.json \
  package.json
```

Expected: no output (no file still contains `5.0.11` in its version line).

Also run:
```bash
grep -c "## v5.0.12" RELEASE-NOTES.md
```

Expected: `1`.

- [ ] **Step 5: Commit the version bump**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json \
        .cursor-plugin/plugin.json gemini-extension.json package.json \
        RELEASE-NOTES.md
git commit -m "chore: bump to 5.0.12 with HARD-GATE dispatch fix release notes"
```

---

## Task 11: Manual evaluation S1, S2, S3
category: backend

**Files:**
- (no files modified — this is a runtime evaluation)

These three scenarios are minimum gating per the design spec (Section 5.2). They must be run in fresh Claude Opus 4.7 sessions, not re-used from this implementation session.

- [ ] **Step 1: Prepare evaluation log file**

Create `docs/superpowers/evals/2026-05-13-sdd-dispatch-hard-gate-eval.md` with the following template:

```markdown
# SDD/Review Dispatch HARD-GATE — Manual Eval Log

**Design:** `docs/superpowers/specs/2026-05-13-sdd-dispatch-hard-gate-design.md`
**Plan:** `docs/superpowers/plans/2026-05-13-sdd-dispatch-hard-gate.md`
**Evaluator:** [name]
**Date:** [YYYY-MM-DD]
**Model:** Claude Opus 4.7

## S1 — Cold session, project config exists, backend task

**Setup:**
- Create `.superpowers/review-config.json` with `coding.rules: [{category: backend, provider: codex}]` in a test repo.
- Start a fresh Claude Code session.
- Hand it a 1-task plan with `category: backend`.

**Pass criterion:** Host AI reads `coding-dispatch.md` before first dispatch AND routes the task to codex (visible in tool calls).

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## S2 — Cold session, only global config, review skill standalone

**Setup:**
- Create `~/.config/superpowers/review-config.json` with `review_provider: codex`.
- Start a fresh Claude Code session, no project config.
- Ask host AI to "review the changes on this branch" (triggering requesting-code-review skill).

**Pass criterion:** Host AI reads `review-dispatch.md` before dispatch AND routes review to codex.

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## S3 — Cold session, no config files

**Setup:**
- Delete (or rename out of the way) both `.superpowers/review-config.json` and `~/.config/superpowers/review-config.json`.
- Start a fresh Claude Code session.
- Hand it a 1-task plan.

**Pass criterion:** Host AI does Step 0, sees no config, proceeds through `coding-dispatch.md` to the host AI fallback path. No prompts. No noise beyond a single `ls` line.

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## Summary

- S1: [PASS / FAIL]
- S2: [PASS / FAIL]
- S3: [PASS / FAIL]

Gating: S1, S2, S3 all PASS → ready to merge. Any FAIL → return to design.
```

- [ ] **Step 2: Run S1 in a fresh session**

Open a new Claude Code session (no shared context with the implementation work). Set up the S1 scenario in a scratch directory. Observe whether the host AI reads `coding-dispatch.md` before its first `Agent` call.

Record the result in the eval log file. If FAIL, do not proceed to merge — capture what the host AI did instead and surface it for the maintainer.

- [ ] **Step 3: Run S2 in a fresh session**

Same as Step 2 but for the S2 scenario. Record result.

- [ ] **Step 4: Run S3 in a fresh session**

Same as Step 2 but for the S3 scenario. Record result.

- [ ] **Step 5: Commit the eval log**

```bash
git add docs/superpowers/evals/2026-05-13-sdd-dispatch-hard-gate-eval.md
git commit -m "docs: record S1/S2/S3 manual eval results for 5.0.12 dispatch HARD-GATE"
```

- [ ] **Step 6: Branch finishing**

If all three scenarios passed, hand off to `superpowers-multi:finishing-a-development-branch` to merge or open a PR. If any scenario failed, surface the failure to the maintainer and return to the design phase — do not merge a partially-validated behavior change.
