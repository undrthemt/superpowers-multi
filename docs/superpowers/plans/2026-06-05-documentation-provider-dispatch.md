# Documentation Provider Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `documentation_provider` config key and dispatch logic so plan-file creation and other documentation tasks route to a user-configured AI provider, independent of coding and review providers.

**Architecture:** Extend `config-loading.md` with a new `documentation_provider` key and `"documentation"` caller intent; create `documentation-dispatch.md` (mirroring `coding-dispatch.md`'s session-state and disk-authority pattern); wire `writing-plans/SKILL.md` and `subagent-driven-development/SKILL.md` to call the new dispatcher via HARD-GATEs.

**Tech Stack:** Bash, Markdown skill files, Claude Code plugin system

---

## File Structure

**New files:**
- `skills/subagent-driven-development/documentation-dispatch.md` — centralized dispatcher (mirrors `coding-dispatch.md`)
- `tests/claude-code/test-documentation-dispatch.sh` — behavioral tests for the dispatcher

**Modified files:**
- `skills/requesting-code-review/config-loading.md` — add `documentation_provider` key, merge rule, Setup UX intent
- `skills/writing-plans/SKILL.md` — HARD-GATE between `## File Structure` and `## Bite-Sized Task Granularity`
- `skills/subagent-driven-development/SKILL.md` — HARD-GATE paragraph + routing rule + digraph node label
- `tests/claude-code/run-skill-tests.sh` — add new test to `tests` array

---

### Task 1: Update `config-loading.md` — add `documentation_provider` support
category: backend

**Files:**
- Modify: `skills/requesting-code-review/config-loading.md`

- [ ] **Step 1: Update the Inputs block (line 7)**

  Current line 7:
  ```
  - **caller_intent**: `"review"` or `"coding"`. Used only to tailor the setup-UX intro message.
  ```

  Replace with:
  ```
  - **caller_intent**: `"review"`, `"coding"`, or `"documentation"`. Used only to tailor the setup-UX intro message.
  ```

- [ ] **Step 2: Add `documentation_provider` to the Known-key table (after line 42)**

  Current lines 38–47:
  ```markdown
  ### Known keys

  | Dotted path | Expected type |
  |---|---|
  | `review_provider` | string |
  | `coding` | object |
  | `coding.enabled` | boolean |
  | `coding.default_provider` | string |
  | `coding.rules` | array |
  | `coding.rules[]` | object with exactly `category: string` and `provider: string` (extra fields treated as unknown) |
  ```

  Add one row after `review_provider`:
  ```markdown
  | `documentation_provider` | string |
  ```

  Resulting table (lines 38–48):
  ```markdown
  ### Known keys

  | Dotted path | Expected type |
  |---|---|
  | `review_provider` | string |
  | `documentation_provider` | string |
  | `coding` | object |
  | `coding.enabled` | boolean |
  | `coding.default_provider` | string |
  | `coding.rules` | array |
  | `coding.rules[]` | object with exactly `category: string` and `provider: string` (extra fields treated as unknown) |
  ```

  Type-validation warning to add in the surrounding prose (after the table):
  > If `documentation_provider` is not a string, emit `⚠ Invalid value for 'documentation_provider' in <path> (expected string); ignored.` and exclude it.

  Locate the existing warning text for `review_provider` in the paragraph below the table and add the analogous sentence for `documentation_provider`.

- [ ] **Step 3: Add `documentation_provider` to the Level 1 merge rules (after line 66)**

  Current lines 64–67:
  ```markdown
  ### Level 1 — top-level keys

  - `review_provider`: simple replace. If `project_cfg.review_provider` is present, use it; else use `global_cfg.review_provider`; else leave undefined.
  - `coding`: if either side has a `coding` object, recurse into Level 2 to produce `merged.coding`. If neither has it, leave undefined.
  ```

  Add one bullet after `review_provider`:
  ```markdown
  - `documentation_provider`: simple replace. If `project_cfg.documentation_provider` is present, use it; else if `global_cfg.documentation_provider` is present, use it; else leave undefined.
  ```

- [ ] **Step 4: Add `documentation` intro message to Setup UX Step 6.2 (after line 118)**

  Current lines 116–118:
  ```markdown
  2. **Show intro** based on `caller_intent`:
     - `review`: `Code review provider is not configured. Pick one to use.`
     - `coding`: `Multi-AI coding dispatch is not configured. Pick a provider to set up.`
  ```

  Add one bullet:
  ```markdown
     - `documentation`: `Documentation provider is not configured. Pick one to use.`
  ```

- [ ] **Step 5: Make Step 6.4 delta initialization intent-aware (line 122)**

  Current line 122:
  ```
  4. **Build the delta.** Start with `delta = { "review_provider": "<picked>" }`.
  ```

  Replace with:
  ```markdown
  4. **Build the delta** based on `caller_intent`:
     - If `caller_intent == "review"` or `caller_intent == "coding"`: `delta = { "review_provider": "<picked>" }` (existing behavior; extend with the `coding` block below if `caller_intent == "coding"`).
     - If `caller_intent == "documentation"`: `delta = { "documentation_provider": "<picked>" }` (no `review_provider` key). No additional prompting is needed.
  ```

  The remainder of Step 6.4 (the `coding` block extension) stays unchanged — it only fires when `caller_intent == "coding"`.

- [ ] **Step 6: Add Caller Integration Note for documentation dispatch (after line 186)**

  Current lines 183–186:
  ```markdown
  ## Caller Integration Notes

  - `review-dispatch.md` Step 2 calls this procedure with `caller_intent="review"` …
  - `coding-dispatch.md` Step 1 calls this procedure with `caller_intent="coding"` …
  ```

  Append a third bullet:
  ```markdown
  - `documentation-dispatch.md` Step 1 calls this procedure with `caller_intent="documentation"` and uses `merged_config.documentation_provider` for downstream provider resolution. If `source == "user-declined"` or `merged_config.documentation_provider` is undefined, the dispatcher falls back to root AI silently (no secondary prompt). When `source == "session-only"` and `merged_config.documentation_provider` is a non-empty string, the dispatcher caches the value in `session_documentation_provider` for the session.
  ```

- [ ] **Step 7: Verify all 6 edits look correct**

  ```bash
  grep -n "documentation_provider\|documentation.*intent\|documentation.*provider" \
    skills/requesting-code-review/config-loading.md
  ```

  Expected: lines appear in the Known-key table, Level 1 merge rules, Step 6.2, Step 6.4, and Caller Integration Notes.

- [ ] **Step 8: Commit**

  ```bash
  git add skills/requesting-code-review/config-loading.md
  git commit -m "feat: add documentation_provider key and intent to config-loading"
  ```

---

### Task 2: Create `documentation-dispatch.md`
category: backend

**Files:**
- Create: `skills/subagent-driven-development/documentation-dispatch.md`

- [ ] **Step 1: Create the file with full content**

  ```bash
  cat > skills/subagent-driven-development/documentation-dispatch.md << 'ENDOFFILE'
  # Documentation Dispatch Guide

  Centralized dispatch logic for routing documentation-authoring tasks to external AI providers.
  Mirrors the coding dispatch pattern (`./coding-dispatch.md`).

  > **Caller contract:** If you reached this file as a host AI executing
  > writing-plans or SDD documentation tasks, you MUST follow the steps below
  > from Step 1 onward. Do not skim and then generate documentation directly —
  > the routing logic (session state, disk checks, fallbacks) is load-bearing.
  > Direct generation bypasses the user's `documentation_provider` configuration.

  ## Parameters

  The caller provides:
  - **`prompt_content`**: the full documentation prompt to send to the provider.
  - **`doc_type`**: `"plan"` | `"design"` | `"documentation"` — used only for human-readable status and log messages. Does not affect provider selection or dispatch behavior. Unknown values are treated as `"documentation"`.

  ## Session State

  This dispatcher maintains two pieces of session-level state across dispatches in the same conversation:

  - **`session_documentation_decline`** (boolean, default `false`): set when the user declined configuration during the Setup UX, or when `source == "session-only"` but `merged_config.documentation_provider` was absent/empty. Suppresses re-prompting.
  - **`session_documentation_provider`** (string, default `undefined`): set when the user picked a provider but chose "session only" (no disk write). Provides the in-memory provider for subsequent dispatches.

  These are mutually exclusive: setting one clears the other.

  ## Step 1: Load Config

  ### Pre-load disk check (runs BEFORE calling config-loading)

  **Disk authority principle:** session state only short-circuits when the disk has nothing to say.

  Quick disk check:
  - `project_exists = test -e <repo>/.superpowers/review-config.json`
  - `global_exists  = test -e ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`

  **If neither file exists:**
  - `session_documentation_decline == true` → skip to Step 7 silently.
  - `session_documentation_provider` is set → assign `provider_name = session_documentation_provider`, skip to Step 3 directly. Step 2's undefined check does not apply — Step 3's provider-not-found path handles any invalid cached value.
  - Neither set → fall through to config-loading.

  **If at least one file exists** → clear `session_documentation_provider` (set to `undefined`), then fall through to config-loading. Disk is authoritative. Do not check or clear `session_documentation_decline` on this path — config-loading governs the interaction completely.

  ### Load config

  Call `skills/requesting-code-review/config-loading.md` with `caller_intent="documentation"`. It returns `{ merged_config, source }`.

  ### Handle result

  - `source == "user-declined"` → set `session_documentation_decline = true`, clear `session_documentation_provider`, skip to Step 7 silently.
  - `source == "session-only"`:
    - If `merged_config.documentation_provider` is a non-empty string → set `session_documentation_provider = merged_config.documentation_provider` (unconditional; the pre-load cleared it). Proceed to Step 2.
    - If `merged_config.documentation_provider` is absent or empty → set `session_documentation_decline = true`, clear `session_documentation_provider`, skip to Step 7. Prevents a re-prompt loop.
  - `source == "merged"` → proceed to Step 2.

  ## Step 2: Resolve Provider

  **This step is reached only when `config-loading.md` was called in Step 1 and returned a `merged_config`.** When `provider_name` was already assigned by the Step 1 pre-load short-circuit, execution continues from Step 3 — this step is skipped.

  ```
  provider_name = merged_config.documentation_provider
  ```

  If `provider_name` is undefined or empty → skip to Step 7 (root AI fallback, silently).

  ## Step 3: Load Provider Definition

  Load `skills/requesting-code-review/providers/<provider_name>.json`.

  If the file does not exist → warn `⚠ Provider '<provider_name>' not found. Falling back to root AI.` → Step 7.

  ## Step 4: Plugin Override Check

  Resolve the override field using the following priority chain:

  1. If `plugin_override_documentation` is present in the provider definition → use it.
  2. Else if `plugin_override` is present → use it.
  3. Else → no override; proceed to Step 5.

  **Rationale:** `plugin_override_coding` is not used because documentation is not a coding task. `plugin_override` as fallback means providers with a single override work out of the box. Providers that want documentation-specific subagent dispatch can add `plugin_override_documentation` in a future update.

  If an override is resolved AND the current host matches `override.host` AND the plugin is available:
  - Dispatch via `override.subagent` with `prompt_content` as the prompt.
  - On success → return output to caller.
  - On failure → proceed to Step 5.

  ## Step 5: CLI Dispatch

  Resolve the invocation config using the following priority chain:

  1. If `invoke_documentation` is present in the provider definition → use it.
  2. Else use `invoke`.

  **Rationale:** `invoke_coding` is not used because documentation is a distinct dispatch type. `invoke` is the appropriate default for non-coding generative tasks. Providers that need a higher timeout for long docs can add `invoke_documentation`.

  Steps:
  1. Run the provider's `detect` command. If it fails (non-zero exit) → warn `⚠ Provider '<provider_name>' CLI not installed. Falling back to root AI.` → Step 7.
  2. Write `prompt_content` to a temp file (e.g. `/tmp/doc-prompt-<timestamp>.md`).
  3. Build and execute the CLI command:
     - If `input_method` is `"file"`: replace `{{prompt_file}}` in resolved `args` with the temp file path, then run `timeout <timeout_seconds> <command> <args...>`
     - If `input_method` is `"stdin"`: run `timeout <timeout_seconds> <command> <args...> < <temp_file>`
  4. Capture stdout as the documentation response.
  5. Clean up the temporary file.

  On exit 0 → proceed to Step 6.

  On non-zero exit or timeout → warn `⚠ Provider '<provider_name>' failed. Falling back to root AI.` → Step 7.

  ## Step 6: Response Validation

  Check that output is non-empty. If empty → warn `⚠ Provider '<provider_name>' returned empty output. Falling back to root AI.` → Step 7.

  No structural validation (no required sections). Documentation output format varies by `doc_type`.

  **Note:** Git-diff validation (used in `coding-dispatch.md`) does not apply here — the documentation provider returns content as a string to the caller; it does not write files or commit changes.

  If non-empty → return output to caller.

  ## Step 7: Root AI Fallback

  Run the documentation task directly on the root AI using `prompt_content`. This is the baseline behavior that existed before this feature.

  If fallback was triggered by a provider failure (Steps 3–6), prefix the task with:

  > `[documentation-dispatch: falling back to root AI after provider failure]`

  If fallback was triggered by missing config (Step 2) or session decline (Step 1), proceed silently with no prefix.
  ENDOFFILE
  ```

- [ ] **Step 2: Verify the file was created**

  ```bash
  wc -l skills/subagent-driven-development/documentation-dispatch.md
  grep -c "Step [1-7]" skills/subagent-driven-development/documentation-dispatch.md
  ```

  Expected: file exists with 7 step headers.

- [ ] **Step 3: Commit**

  ```bash
  git add skills/subagent-driven-development/documentation-dispatch.md
  git commit -m "feat: add documentation-dispatch.md dispatcher"
  ```

---

### Task 3: Add HARD-GATE to `writing-plans/SKILL.md`
category: backend

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

- [ ] **Step 1: Locate the insertion point**

  ```bash
  grep -n "## File Structure\|## Bite-Sized" skills/writing-plans/SKILL.md
  ```

  Expected output (approximate line numbers):
  ```
  26:## File Structure
  50:## Bite-Sized Task Granularity
  ```

- [ ] **Step 2: Insert the HARD-GATE block between `## File Structure` and `## Bite-Sized Task Granularity`**

  After the entire `## File Structure` section body ends (just before `## Bite-Sized Task Granularity`), insert:

  ```markdown
  <HARD-GATE>
  Do NOT generate plan body content directly while executing this skill.
  For plan body generation: you MUST `Read`
  `skills/subagent-driven-development/documentation-dispatch.md` and
  follow its logic. Direct generation bypasses the user's
  `documentation_provider` configuration and silently ignores their
  chosen provider.

  The plan body is everything from the Plan Document Header through to the
  end of the task list. File Structure analysis and Scope Check are
  performed by the root AI before invoking the dispatcher.

  Assemble `prompt_content` as:
  1. The spec or requirements (from the input provided by the user)
  2. The file structure analysis completed above
  3. The task granularity guidelines (Bite-Sized Task Granularity section)
  4. The plan document header template (Plan Document Header section)

  Pass to documentation-dispatch.md with doc_type="plan".
  The returned content string is written to the plan file by the root AI.
  </HARD-GATE>
  ```

- [ ] **Step 3: Verify the block appears between the two sections**

  ```bash
  grep -n "HARD-GATE\|## File Structure\|## Bite-Sized" skills/writing-plans/SKILL.md
  ```

  Expected: `## File Structure` line number < `HARD-GATE` line number < `## Bite-Sized Task Granularity` line number.

- [ ] **Step 4: Commit**

  ```bash
  git add skills/writing-plans/SKILL.md
  git commit -m "feat: add HARD-GATE for documentation-dispatch in writing-plans"
  ```

---

### Task 4: Update `subagent-driven-development/SKILL.md`
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

- [ ] **Step 1: Add documentation dispatch paragraph to the HARD-GATE block**

  Current HARD-GATE block (lines 16–34) ends with:
  ```
  These files exist in the same directory as this SKILL.md (or one
  directory over for review-dispatch.md). If you have not read them yet
  in this session, do so before any task work — every session, no
  exceptions.
  </HARD-GATE>
  ```

  Insert one new paragraph before `</HARD-GATE>`:
  ```
  For documentation tasks (plan files, design documents, Confluence pages,
  READMEs, architecture docs): you MUST `Read` `./documentation-dispatch.md`
  and follow its logic. Direct Agent dispatch bypasses the user's
  `documentation_provider` configuration and silently ignores their chosen
  provider.

  A task is a documentation task when it explicitly produces a document
  artifact (plan file, design document, Confluence page, README, architecture
  doc). Tasks that write source code files (.js, .py, .ts, config, test files)
  are not documentation tasks even if their description mentions writing.
  ```

- [ ] **Step 2: Update the `digraph process` node label**

  Current (line 96):
  ```
  "Read & follow coding-dispatch.md (the only entry point)" [shape=box];
  ```

  Replace with:
  ```
  "Classify task: doc artifact? → documentation-dispatch.md, else → coding-dispatch.md" [shape=box];
  ```

  Also update the two `->` lines that reference this node label (lines 116–117, 120):
  - `"Classify task category (plan tag → AI auto-classification)" -> "Read & follow coding-dispatch.md (the only entry point)";`
  - `"Read & follow coding-dispatch.md (the only entry point)" -> "Implementation result (provider OR internal fallback)";`
  - `"Answer questions, provide context" -> "Read & follow coding-dispatch.md (the only entry point)";`

  Replace `"Read & follow coding-dispatch.md (the only entry point)"` with `"Classify task: doc artifact? → documentation-dispatch.md, else → coding-dispatch.md"` in all three `->` lines.

- [ ] **Step 3: Add routing rule prose after Step 0 config detection**

  Find the section that says "You MUST go through `./coding-dispatch.md` (for implementation)" (around line 77). After the existing bullet points about file existence checks, add:

  ```markdown
  - Note `documentation_provider` value (if present) — documentation tasks will route through `./documentation-dispatch.md`.
  ```

  And add to the "Templates and dispatchers" section (around line 218), after the `./coding-dispatch.md` entry:
  ```markdown
  - `./documentation-dispatch.md` — Documentation task routing logic. **Always use this for documentation task authoring (plan files, design docs, Confluence pages, READMEs).** Honors `documentation_provider` configuration; falls back to root AI when unconfigured.
  ```

- [ ] **Step 4: Verify changes**

  ```bash
  grep -n "documentation-dispatch\|documentation_provider\|doc artifact" \
    skills/subagent-driven-development/SKILL.md
  ```

  Expected: lines in HARD-GATE block, digraph, and templates section.

- [ ] **Step 5: Commit**

  ```bash
  git add skills/subagent-driven-development/SKILL.md
  git commit -m "feat: add documentation-dispatch routing to SDD HARD-GATE and templates"
  ```

---

### Task 5: Create `test-documentation-dispatch.sh`
category: backend

**Files:**
- Create: `tests/claude-code/test-documentation-dispatch.sh`

- [ ] **Step 1: Create the test file**

  ```bash
  cat > tests/claude-code/test-documentation-dispatch.sh << 'ENDOFFILE'
  #!/usr/bin/env bash
  # Test: documentation-dispatch skill
  # Verifies dispatcher behavior: provider config, fallback, session state
  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  source "$SCRIPT_DIR/test-helpers.sh"

  echo "=== Test: documentation-dispatch ==="
  echo ""

  # Test 1: Dispatcher file exists and has correct structure
  echo "Test 1: Dispatcher file structure..."

  output=$(run_claude "Read skills/subagent-driven-development/documentation-dispatch.md and list its step numbers (Step 1 through Step 7)." 30 "Read")

  if assert_contains "$output" "Step 1\|Step1" "Has Step 1"; then : ; else exit 1; fi
  if assert_contains "$output" "Step 7\|Step7" "Has Step 7"; then : ; else exit 1; fi
  echo ""

  # Test 2: Fallback behavior when documentation_provider is not configured
  echo "Test 2: Unconfigured provider falls back silently to root AI..."

  output=$(run_claude "According to documentation-dispatch.md, what happens when documentation_provider is not set in the config (undefined or empty)? Does it warn the user?" 30 "Read")

  if assert_contains "$output" "silent\|silently\|no.*warn\|without.*warn\|root.*AI\|fallback" "Falls back silently"; then : ; else exit 1; fi
  if assert_not_contains "$output" "prompt.*user\|ask.*user\|setup.*UX" "Does not prompt user"; then : ; else exit 1; fi
  echo ""

  # Test 3: User-declined sets session_documentation_decline
  echo "Test 3: User-declined sets session_documentation_decline flag..."

  output=$(run_claude "In documentation-dispatch.md, when config-loading returns source='user-declined', what session state variable is set and to what value?" 30 "Read")

  if assert_contains "$output" "session_documentation_decline" "Sets session_documentation_decline"; then : ; else exit 1; fi
  if assert_contains "$output" "true" "Sets to true"; then : ; else exit 1; fi
  echo ""

  # Test 4: session_documentation_decline suppresses re-prompting
  echo "Test 4: session_documentation_decline prevents Setup UX on second dispatch..."

  output=$(run_claude "In documentation-dispatch.md Step 1, when session_documentation_decline is true AND no config files exist on disk, what does the dispatcher do?" 30 "Read")

  if assert_contains "$output" "Step 7\|fallback\|skip" "Skips to fallback"; then : ; else exit 1; fi
  if assert_not_contains "$output" "config-loading\|Setup UX\|prompt" "Does not call config-loading"; then : ; else exit 1; fi
  echo ""

  # Test 5: Provider-not-found warns and falls back
  echo "Test 5: Unknown provider name warns and falls back..."

  output=$(run_claude "In documentation-dispatch.md Step 3, what happens when the provider JSON file does not exist?" 30 "Read")

  if assert_contains "$output" "warn\|⚠\|warning\|not found" "Emits warning"; then : ; else exit 1; fi
  if assert_contains "$output" "Step 7\|fallback\|root.*AI" "Falls back to root AI"; then : ; else exit 1; fi
  echo ""

  # Test 6: Empty output triggers Step 6 warning and fallback
  echo "Test 6: Empty CLI output triggers Step 6 warning and fallback..."

  output=$(run_claude "In documentation-dispatch.md, if the CLI exits 0 but stdout is empty, which step catches this and what happens?" 30 "Read")

  if assert_contains "$output" "Step 6\|validation\|empty" "Step 6 catches empty output"; then : ; else exit 1; fi
  if assert_contains "$output" "warn\|⚠\|warning" "Emits warning"; then : ; else exit 1; fi
  echo ""

  # Test 7: session-only provider is cached for next dispatch
  echo "Test 7: session-only path caches provider in session_documentation_provider..."

  output=$(run_claude "In documentation-dispatch.md Step 1, when config-loading returns source='session-only' and documentation_provider is a non-empty string, what session variable is set?" 30 "Read")

  if assert_contains "$output" "session_documentation_provider" "Sets session_documentation_provider"; then : ; else exit 1; fi
  echo ""

  # Test 8: Plugin override uses plugin_override field
  echo "Test 8: Plugin override priority chain uses plugin_override (not plugin_override_coding)..."

  output=$(run_claude "In documentation-dispatch.md Step 4, what is the plugin override priority chain? Which field is checked first, and what is the fallback?" 30 "Read")

  if assert_contains "$output" "plugin_override_documentation" "Checks plugin_override_documentation first"; then : ; else exit 1; fi
  if assert_contains "$output" "plugin_override[^_].*fallback\|fallback.*plugin_override[^_]\|else.*plugin_override[^_c]" "Falls back to plugin_override"; then : ; else exit 1; fi
  if assert_not_contains "$output" "plugin_override_coding" "Does not use plugin_override_coding"; then : ; else exit 1; fi
  echo ""

  # Test 9: Plugin override failure falls through to CLI (Step 5), not Step 7
  echo "Test 9: Plugin override failure falls through to CLI dispatch..."

  output=$(run_claude "In documentation-dispatch.md Step 4, when plugin override dispatch fails, does it go to Step 5 (CLI) or Step 7 (fallback)?" 30 "Read")

  if assert_contains "$output" "Step 5\|CLI" "Falls through to Step 5 / CLI"; then : ; else exit 1; fi
  if assert_not_contains "$output" "directly.*Step 7\|Step 7.*directly" "Not directly to Step 7"; then : ; else exit 1; fi
  echo ""

  echo "=== All documentation-dispatch tests passed ==="
  ENDOFFILE

  chmod +x tests/claude-code/test-documentation-dispatch.sh
  ```

- [ ] **Step 2: Verify the file is executable and has 9 test cases**

  ```bash
  ls -la tests/claude-code/test-documentation-dispatch.sh
  grep -c 'echo "Test [0-9]' tests/claude-code/test-documentation-dispatch.sh
  ```

  Expected: file exists with executable bit, count is 9.

- [ ] **Step 3: Commit**

  ```bash
  git add tests/claude-code/test-documentation-dispatch.sh
  git commit -m "test: add test-documentation-dispatch.sh with 9 scenarios"
  ```

---

### Task 6: Register test in `run-skill-tests.sh`
category: backend

**Files:**
- Modify: `tests/claude-code/run-skill-tests.sh`

- [ ] **Step 1: Locate the `tests` array**

  ```bash
  grep -n 'tests=\|"test-' tests/claude-code/run-skill-tests.sh
  ```

  Expected: see `tests=(` at approximately line 75, with `"test-subagent-driven-development.sh"` inside.

- [ ] **Step 2: Add the new test after `test-subagent-driven-development.sh`**

  Current `tests` array:
  ```bash
  tests=(
  "test-subagent-driven-development.sh"
  )
  ```

  Replace with:
  ```bash
  tests=(
  "test-subagent-driven-development.sh"
  "test-documentation-dispatch.sh"
  )
  ```

- [ ] **Step 3: Also update the `--help` display list**

  Locate the `--help` section (around line 60) that lists test names:
  ```bash
  echo "  test-subagent-driven-development.sh  Test skill loading and requirements"
  ```

  Add after it:
  ```bash
  echo "  test-documentation-dispatch.sh       Test documentation provider dispatch behavior"
  ```

- [ ] **Step 4: Verify both changes**

  ```bash
  grep -n "test-documentation-dispatch\|tests=" tests/claude-code/run-skill-tests.sh
  ```

  Expected: appears in both the help section and the `tests` array.

- [ ] **Step 5: Commit**

  ```bash
  git add tests/claude-code/run-skill-tests.sh
  git commit -m "test: register test-documentation-dispatch.sh in run-skill-tests.sh"
  ```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task that implements it |
|---|---|
| Add `documentation_provider` key to config schema | Task 1 (Steps 1–3) |
| Add `"documentation"` caller_intent to Setup UX | Task 1 (Step 4) |
| Make Step 6.4 delta intent-aware | Task 1 (Step 5) |
| Add Caller Integration Note | Task 1 (Step 6) |
| Create `documentation-dispatch.md` with 7-step flow | Task 2 |
| Session state: `session_documentation_decline` + `session_documentation_provider` | Task 2 |
| Disk-authority pre-load check | Task 2 |
| Plugin override priority chain (`plugin_override_documentation` → `plugin_override`) | Task 2 |
| CLI dispatch with `detect` substep | Task 2 |
| `invoke_documentation` priority chain | Task 2 |
| Root AI fallback (silent for missing config, warned for provider failure) | Task 2 |
| HARD-GATE in `writing-plans/SKILL.md` | Task 3 |
| HARD-GATE in `subagent-driven-development/SKILL.md` | Task 4 |
| Digraph node label update | Task 4 |
| `documentation-dispatch.md` in Templates section | Task 4 |
| Test file with 9 scenarios | Task 5 |
| `run-skill-tests.sh` registration | Task 6 |

All spec requirements have a corresponding task. No placeholders remain.
