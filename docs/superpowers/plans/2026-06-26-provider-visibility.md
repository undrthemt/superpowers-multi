# Provider Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display which AI provider is being used when sub-agents are dispatched, and list all providers used at session end.

**Architecture:** Three targeted prose edits to existing skill files. `session_dispatch_log` is a session-level array variable maintained by the host AI; both `coding-dispatch.md` and `review-dispatch.md` append to it before each external dispatch; `finishing-a-development-branch` reads it to produce a summary table. No new files, no schema changes.

**Tech Stack:** Markdown instruction files (AI skill prose)

---

## File Map

| File | Change |
|------|--------|
| `skills/subagent-driven-development/coding-dispatch.md` | Add `session_dispatch_log` to Session State; add announcement + append at Steps 4 and 5 |
| `skills/requesting-code-review/review-dispatch.md` | Add `session_dispatch_log` note + announcement + append at Steps 4 and 5 |
| `skills/finishing-a-development-branch/SKILL.md` | Insert new Step 2 (Dispatch Summary); renumber Steps 2→3, 3→4, 4→5, 5→6; update 3 cross-references |

---

### Task 1: coding-dispatch.md — Session State + Steps 4 & 5
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/coding-dispatch.md`

- [ ] **Step 1: Read the current Session State section**

Open `skills/subagent-driven-development/coding-dispatch.md` and confirm the Session State section (~lines 26–31) currently ends with:

```
These are mutually exclusive: setting one clears the other.
```

- [ ] **Step 2: Add `session_dispatch_log` to the Session State section**

Find the exact text:

```
These are mutually exclusive: setting one clears the other.
```

Replace it with:

```
`session_coding_decline` and `session_coding_cache` are mutually exclusive: setting one clears the other.

- `session_dispatch_log = []` — append-only list of all external dispatches in this session. Shared with `review-dispatch.md`. Each entry: `{ type: "coding" | "review", task_name: string, provider: string }`. Initialize to `[]` if not already set; never cleared within a session.
```

- [ ] **Step 3: Read the current Step 4 numbered list**

Confirm Step 4 of `coding-dispatch.md` contains this numbered list:

```
1. Save current HEAD SHA as `pre_dispatch_sha`: `git rev-parse HEAD`
2. Fill `./coding-prompt.md` template placeholders with caller-provided values
3. Dispatch as a subagent via the override's `subagent` type with the filled prompt
4. Validate the response (see Step 6)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 5 (CLI Dispatch)
```

- [ ] **Step 4: Add announcement to Step 4 (Plugin Override) — between items 2 and 3**

Find inside Step 4:

```
2. Fill `./coding-prompt.md` template placeholders with caller-provided values
3. Dispatch as a subagent via the override's `subagent` type with the filled prompt
4. Validate the response (see Step 6)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 5 (CLI Dispatch)
```

Replace with:

```
2. Fill `./coding-prompt.md` template placeholders with caller-provided values
3. Announce to the user: `[coding] <task_name> → <provider_name>` and append `{ type: "coding", task_name: task_name, provider: provider_name }` to `session_dispatch_log`.
4. Dispatch as a subagent via the override's `subagent` type with the filled prompt
5. Validate the response (see Step 6)
6. If validation passes → return the result (done)
7. If validation fails → continue to Step 5 (CLI Dispatch)
```

- [ ] **Step 5: Read Step 5 items 4–5**

Confirm Step 5 of `coding-dispatch.md` contains:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/coding-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
```

- [ ] **Step 6: Add announcement to Step 5 (CLI Dispatch) — between items 4 and 5**

Find inside Step 5:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/coding-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
```

Replace with:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/coding-prompt-<timestamp>.md`)

5. Announce to the user: `[coding] <task_name> → <provider_name>` and append `{ type: "coding", task_name: task_name, provider: provider_name }` to `session_dispatch_log`.

6. Build and execute the CLI command:
```

Then renumber the remaining items in Step 5: old item 6 → 7, old item 7 → 8, old item 8 → 9.

- [ ] **Step 7: Verify the edits**

```bash
grep -n "session_dispatch_log" skills/subagent-driven-development/coding-dispatch.md
```

Expected: at least 3 matches (Session State definition, Step 4 item 3, Step 5 item 5).

```bash
grep -n "\[coding\]" skills/subagent-driven-development/coding-dispatch.md
```

Expected: 2 matches (Step 4 and Step 5).

- [ ] **Step 8: Commit**

```bash
git add skills/subagent-driven-development/coding-dispatch.md
git commit -m "feat: add provider announcement and session_dispatch_log to coding-dispatch"
```

---

### Task 2: review-dispatch.md — Session State note + Steps 4 & 5
category: backend

**Files:**
- Modify: `skills/requesting-code-review/review-dispatch.md`

- [ ] **Step 1: Read the section between Parameters and Step 1**

Open `skills/requesting-code-review/review-dispatch.md` and confirm there is currently no "Session State" section between the `## Parameters` section and `## Step 1: Select Template`.

- [ ] **Step 2: Insert a Session State section before Step 1**

Find the exact text:

```
## Step 1: Select Template
```

Insert the following block immediately before it:

```
## Session State

This dispatcher appends to `session_dispatch_log` — a session-level array shared with `coding-dispatch.md`. Each successful external dispatch (Step 4 or Step 5) adds one entry of the form `{ type: "review", task_name: string, provider: string }`, where `task_name` is the value of the `{DESCRIPTION}` template placeholder. If `session_dispatch_log` is not yet initialized, treat it as `[]`.

```

- [ ] **Step 3: Read the current Step 4 numbered list**

Confirm Step 4 of `review-dispatch.md` contains this numbered list:

```
1. Fill template placeholders with caller-provided values
2. If `additional_checks` is provided, append it to the filled template
3. Dispatch as a subagent via `plugin_override.subagent` type with the filled prompt
4. Validate the response (see Step 7)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 6 (Fallback)
```

- [ ] **Step 4: Add announcement to Step 4 (Plugin Override) — between items 2 and 3**

Find inside Step 4:

```
2. If `additional_checks` is provided, append it to the filled template
3. Dispatch as a subagent via `plugin_override.subagent` type with the filled prompt
4. Validate the response (see Step 7)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 6 (Fallback)
```

Replace with:

```
2. If `additional_checks` is provided, append it to the filled template
3. Announce to the user: `[review] <DESCRIPTION> → <provider_name>` and append `{ type: "review", task_name: DESCRIPTION, provider: provider_name }` to `session_dispatch_log`.
4. Dispatch as a subagent via `plugin_override.subagent` type with the filled prompt
5. Validate the response (see Step 7)
6. If validation passes → return the result (done)
7. If validation fails → continue to Step 6 (Fallback)
```

- [ ] **Step 5: Read Step 5 items 4–5**

Confirm Step 5 of `review-dispatch.md` contains:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/review-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
```

- [ ] **Step 6: Add announcement to Step 5 (CLI Dispatch) — between items 4 and 5**

Find inside Step 5:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/review-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
```

Replace with:

```
4. Write the filled prompt to a temporary file (e.g. `/tmp/review-prompt-<timestamp>.md`)

5. Announce to the user: `[review] <DESCRIPTION> → <provider_name>` and append `{ type: "review", task_name: DESCRIPTION, provider: provider_name }` to `session_dispatch_log`.

6. Build and execute the CLI command:
```

Then renumber the remaining items in Step 5: old item 6 → 7, old item 7 → 8, old item 8 → 9.

- [ ] **Step 7: Verify the edits**

```bash
grep -n "session_dispatch_log" skills/requesting-code-review/review-dispatch.md
```

Expected: at least 3 matches (Session State section, Step 4 item 3, Step 5 item 5).

```bash
grep -n "\[review\]" skills/requesting-code-review/review-dispatch.md
```

Expected: 2 matches (Step 4 and Step 5).

- [ ] **Step 8: Commit**

```bash
git add skills/requesting-code-review/review-dispatch.md
git commit -m "feat: add provider announcement and session_dispatch_log to review-dispatch"
```

---

### Task 3: finishing-a-development-branch/SKILL.md — Add Dispatch Summary step
category: backend

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md`

- [ ] **Step 1: Read Step 1 ending and Step 2 heading**

Confirm `skills/finishing-a-development-branch/SKILL.md` contains exactly:

```
**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch
```

- [ ] **Step 2: Insert new Step 2 (Dispatch Summary)**

Find the exact text:

```
**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch
```

Replace with the text below. The replacement spans from "**If tests pass:**" through the new "### Step 3: Determine Base Branch" heading. The inner fenced block (showing the Dispatch Summary output format) must be preserved exactly as shown:

```
**If tests pass:** Continue to Step 2.

### Step 2: Dispatch Summary

**If `session_dispatch_log` is empty or not set:** Skip to Step 3.

**If `session_dispatch_log` has entries**, emit the following (fill in actual values from the log):

```
## Dispatch Summary

| # | Type    | Task / Description                      | Provider      |
|---|---------|-----------------------------------------|---------------|
| 1 | coding  | Task 1: DB schema migration             | codex         |
| 2 | review  | Task 1: DB schema migration             | codex         |
| 3 | coding  | Task 2: Auth endpoints                  | claude-code   |
| 4 | review  | Task 2: Auth endpoints                  | codex         |

Provider breakdown:
  codex        ×3  (1 coding, 2 review)
  claude-code  ×1  (1 coding)
```

Fill the table from `session_dispatch_log` entries in order. For the breakdown, count entries by provider name; list each provider with total count and `(N coding, M review)` split; order by first appearance in the log.

Then continue to Step 3.

### Step 3: Determine Base Branch
```

(The replacement ends at "### Step 3: Determine Base Branch" — the old "### Step 2: Determine Base Branch" heading is removed and replaced with "### Step 3: Determine Base Branch".)

- [ ] **Step 3: Rename heading Step 3 → Step 4**

Find:

```
### Step 3: Present Options
```

Replace with:

```
### Step 4: Present Options
```

- [ ] **Step 4: Rename heading Step 4 → Step 5**

Find:

```
### Step 4: Execute Choice
```

Replace with:

```
### Step 5: Execute Choice
```

- [ ] **Step 5: Rename heading Step 5 → Step 6**

Find:

```
### Step 5: Cleanup Worktree
```

Replace with:

```
### Step 6: Cleanup Worktree
```

- [ ] **Step 6: Update the three "Cleanup worktree (Step 5)" cross-references**

There are exactly 3 occurrences of `Then: Cleanup worktree (Step 5)` (under Option 1, Option 2, Option 4). Replace all three with:

```
Then: Cleanup worktree (Step 6)
```

- [ ] **Step 7: Verify step structure**

```bash
grep -n "^### Step" skills/finishing-a-development-branch/SKILL.md
```

Expected (6 lines):

```
### Step 1: Verify Tests
### Step 2: Dispatch Summary
### Step 3: Determine Base Branch
### Step 4: Present Options
### Step 5: Execute Choice
### Step 6: Cleanup Worktree
```

Verify no stale Step 5 cross-references remain:

```bash
grep -n "Step 5)" skills/finishing-a-development-branch/SKILL.md
```

Expected: 0 matches.

Verify Step 6 cross-references:

```bash
grep -c "Step 6)" skills/finishing-a-development-branch/SKILL.md
```

Expected: 3.

- [ ] **Step 8: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "feat: add dispatch summary step to finishing-a-development-branch"
```

---

### Task 4: Version bump to 5.0.14
category: backend

**Files:**
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.cursor-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `gemini-extension.json`

- [ ] **Step 1: Confirm current version is 5.0.13**

```bash
grep '"version"' package.json .claude-plugin/plugin.json .cursor-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
```

All five should show `"5.0.13"`.

- [ ] **Step 2: Bump all five files to 5.0.14**

In each file, change `"version": "5.0.13"` to `"version": "5.0.14"`:

- `package.json` line 3
- `.claude-plugin/plugin.json` line 4
- `.cursor-plugin/plugin.json` line 5
- `.claude-plugin/marketplace.json` (nested under `plugins[0]`, line ~12)
- `gemini-extension.json` line 4

- [ ] **Step 3: Verify all five files are in sync**

```bash
grep '"version"' package.json .claude-plugin/plugin.json .cursor-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
```

All five must show `"5.0.14"`.

- [ ] **Step 4: Commit**

```bash
git add package.json .claude-plugin/plugin.json .cursor-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
git commit -m "chore: bump version to 5.0.14"
```
