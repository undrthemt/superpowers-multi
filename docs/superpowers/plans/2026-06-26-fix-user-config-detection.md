# Fix User-Level Config Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bug where user-level global config (`~/.config/superpowers/review-config.json`) is almost never detected because `config-loading.md` Step 1 presents the global path as a shell variable template without requiring the AI to actually execute the bash expansion.

**Architecture:** Three targeted edits to markdown skill files:
1. `config-loading.md` — make Step 1 mandatory bash execution with echo output so the AI uses actual expanded paths for all file operations
2. All skill files — standardize `~/.config` (tilde) to `$HOME/.config` in display/description text for consistency with bash commands
3. `coding-dispatch.md` — convert pre-load pseudo-code check to explicit bash code block

**Tech Stack:** Markdown skill files only (no code, no tests, no dependencies)

---

## Root Cause Analysis

**Primary bug** (`config-loading.md` Step 1):

The bash one-liner is labeled **"Bash one-liner used internally"** — this reads as reference documentation, not as a mandatory execution step. When the AI doesn't run this bash command, it retains the unexpanded template string `${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json` as the global path.

In Step 2, the AI performs a "File missing" check before running `jq`. If the AI uses the Read tool (which does NOT perform shell variable expansion) with the unexpanded template path as a literal string, the file appears missing even when it exists at the real expanded path. This produces `global_cfg = {}` → Step 3 finds both configs empty → Setup UX fires → "not configured" message.

**"Almost never"** (not "never"): Occasionally the AI does run the bash one-liner or uses the Bash tool for the existence check (which DOES expand `$HOME`), so the config is found. But in the majority of cases it does not, causing systematic failure.

**Contributing factor** (`~/.config` vs `$HOME/.config` inconsistency):

Several description texts and the Save-Location Helper display use `${XDG_CONFIG_HOME:-~/.config}` (tilde form). In bash, `~` is NOT expanded inside `${}` parameter expansion when `XDG_CONFIG_HOME` is unset — the result is the literal string `~/.config`. An AI that uses the tilde form in bash commands (influenced by the description text) may fail to find the file. The tilde form appears only in display/descriptive text, not in actual bash code blocks, but it may influence an AI to use the wrong form when constructing bash commands.

Affected locations:
- `skills/subagent-driven-development/SKILL.md:10` — description text
- `skills/subagent-driven-development/SKILL.md:235` — example output (shows `~/.config` in expected output)
- `skills/requesting-code-review/config-loading.md:149` — Save-Location Helper display
- `skills/writing-plans/SKILL.md:109` — Category Tags description

**Secondary bug** (`coding-dispatch.md` pre-load check):

The pre-load check uses pseudo-code variable assignment style without a bash code block:
```
- `global_exists  = test -e ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`
```
This does not prompt the AI to run an actual bash command. If the AI evaluates this "mentally" and can't resolve `$HOME`, it may fall through incorrectly.

---

## Files Modified

| File | Change |
|------|--------|
| `skills/requesting-code-review/config-loading.md` | Step 1: mandatory bash block with echo output; Save-Location Helper: `~/.config` → `$HOME/.config` |
| `skills/subagent-driven-development/SKILL.md` | Line 10 description: `~/.config` → `$HOME/.config`; line 235 example output: `~/.config` → `$HOME/.config` |
| `skills/subagent-driven-development/coding-dispatch.md` | Pre-load check: add explicit bash code block |
| `skills/writing-plans/SKILL.md` | Category Tags description: `~/.config` → `$HOME/.config` |

---

## Task 1: Fix config-loading.md Step 1 (mandatory bash execution)
category: backend

**Files:**
- Modify: `skills/requesting-code-review/config-loading.md:15-24`

The key change is replacing the "Bash one-liner used internally" label with "**Run this now**" and adding `printf` output so the AI sees the actual expanded paths and existence status. A follow-up instruction then forbids re-deriving paths from the template.

- [ ] **Step 1: Open the file and locate Step 1**

Read `skills/requesting-code-review/config-loading.md` lines 15-25.

Verify current text contains:
```
Bash one-liner used internally:
```bash
GLOBAL_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"
PROJECT_PATH=".superpowers/review-config.json"
```
```

- [ ] **Step 2: Replace "used internally" section with mandatory execution block**

Replace the block from "Bash one-liner used internally:" through the closing triple-backtick with:

```markdown
**Run this now** to resolve the actual file paths for this session:

```bash
GLOBAL_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"
PROJECT_PATH=".superpowers/review-config.json"
printf "global_path=%s\nglobal_exists=%s\nproject_path=%s\nproject_exists=%s\n" \
  "$GLOBAL_PATH" \
  "$(test -e "$GLOBAL_PATH" && echo yes || echo no)" \
  "$PROJECT_PATH" \
  "$(test -e "$PROJECT_PATH" && echo yes || echo no)"
```

Note the output. For all file operations in Steps 2 and 6, use the `global_path` and `project_path` values as reported above — do **not** re-derive them from the template; the reported values are already shell-expanded.
```

- [ ] **Step 3: Verify the edit looks correct**

Read lines 15-35 of the modified file and confirm:
- "Run this now" is prominent (bold)
- The bash block includes both the path assignments AND the `printf` existence check
- The follow-up note explicitly says to use the reported values, not the template

- [ ] **Step 4: Commit**

```bash
cd /Users/yamashitamasahiro/git_workspace/superpowers/.worktrees/fix-user-config-detection
git add skills/requesting-code-review/config-loading.md
git commit -m "fix: make config-loading Step 1 mandatory bash execution with path echo

The 'Bash one-liner used internally' label was ambiguous — it read as
reference documentation rather than a required execution step. When
the AI skipped it, it retained the unexpanded template path and
subsequent file checks using the Read tool (which does not expand
shell variables) would not find the global config file.

Now: 'Run this now' + printf output reveals the actual expanded paths
and their existence status. Downstream steps are told to use the
reported values, not the template."
```

---

## Task 2: Fix `~/.config` tilde inconsistency in config-loading.md Save-Location Helper
category: backend

**Files:**
- Modify: `skills/requesting-code-review/config-loading.md:149`

- [ ] **Step 1: Locate the tilde in the Save-Location Helper display text**

In `skills/requesting-code-review/config-loading.md`, find line ~149:
```
   A. User global (recommended) — ${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json
```

- [ ] **Step 2: Replace tilde with $HOME**

Change:
```
   A. User global (recommended) — ${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json
```
To:
```
   A. User global (recommended) — ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json
```

Rationale: In bash `${}` parameter expansion, `~` is NOT expanded. `${XDG_CONFIG_HOME:-~/.config}` produces the literal string `~/.config` when XDG_CONFIG_HOME is unset. The display text should match the bash command form to avoid confusing the AI into using the wrong form.

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/config-loading.md
git commit -m "fix: use \$HOME/.config instead of tilde in Save-Location Helper display

Tilde (~) is not expanded inside \${} parameter expansion in bash.
\${XDG_CONFIG_HOME:-~/.config} produces the literal string ~./config,
not the expanded home path. Standardize display text to match the
bash command form to avoid misleading the AI."
```

---

## Task 3: Fix `~/.config` in subagent-driven-development/SKILL.md (description + example output)
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:10`
- Modify: `skills/subagent-driven-development/SKILL.md:235`

Two occurrences: the description text (line 10) and the example workflow output (line 235). Both use the tilde form and should be consistent with the bash command form.

- [ ] **Step 1: Fix line 10 — description text**

In `skills/subagent-driven-development/SKILL.md`, find line 10:
```
an optional user global config at `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json`
```

Change `${XDG_CONFIG_HOME:-~/.config}` to `${XDG_CONFIG_HOME:-$HOME/.config}` in that line.

Result:
```
an optional user global config at `${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`
```

- [ ] **Step 2: Fix line 235 — example workflow output**

In `skills/subagent-driven-development/SKILL.md`, find line ~235 inside the Example Workflow section:
```
[Found ~/.config/superpowers/review-config.json: review_provider=codex, coding.rules: backend→codex]
```

Change `~/.config` to `$HOME/.config`:
```
[Found $HOME/.config/superpowers/review-config.json: review_provider=codex, coding.rules: backend→codex]
```

Note: This is example output text shown to the user. While it won't affect bash execution, it may influence an AI reading the example to use `~/.config` in subsequent bash commands. Standardize to `$HOME/.config` for consistency.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "fix: use \$HOME/.config in SDD skill (description + example output)

Tilde (~) is not expanded inside \${} parameter expansion in bash.
\${XDG_CONFIG_HOME:-~/.config} produces the literal string ~/.config,
not the expanded home path. Standardize both the description (line 10)
and the example workflow output (line 235) to avoid misleading the AI."
```

---

## Task 4: Fix `~/.config` in writing-plans/SKILL.md Category Tags description
category: backend

**Files:**
- Modify: `skills/writing-plans/SKILL.md:109`

- [ ] **Step 1: Locate the tilde in Category Tags**

In `skills/writing-plans/SKILL.md`, find line ~109:
```
When multi-AI coding dispatch is enabled (via `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json`
```

- [ ] **Step 2: Replace tilde with $HOME**

Change `${XDG_CONFIG_HOME:-~/.config}` to `${XDG_CONFIG_HOME:-$HOME/.config}` in that line.

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "fix: use \$HOME/.config in writing-plans Category Tags description (tilde not expanded in \${})"
```

---

## Task 5: Fix coding-dispatch.md pre-load check (add explicit bash code block)
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/coding-dispatch.md:37-39`

The pre-load check currently uses pseudo-code variable assignments that don't prompt the AI to run actual bash commands:
```
Quick disk check:
- `project_exists = test -e <repo>/.superpowers/review-config.json`
- `global_exists  = test -e ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`
```

Replace with an explicit bash code block.

- [ ] **Step 1: Locate the pre-load check section**

In `skills/subagent-driven-development/coding-dispatch.md`, find lines ~37-39:
```
Quick disk check:
- `project_exists = test -e <repo>/.superpowers/review-config.json`
- `global_exists  = test -e ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`
```

- [ ] **Step 2: Replace with explicit bash code block**

Replace the "Quick disk check:" block with:

```markdown
Run this bash check now:

```bash
test -e ".superpowers/review-config.json" \
  && echo "project_exists=yes" || echo "project_exists=no"
test -e "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \
  && echo "global_exists=yes" || echo "global_exists=no"
```

Set `project_exists` and `global_exists` from the output above.
```

- [ ] **Step 3: Verify the surrounding context still makes sense**

Read lines 33-50 of the modified `coding-dispatch.md` to confirm:
- "Run this bash check now" is clear and actionable
- The `If **neither** file exists` condition still logically follows the bash block
- The `If **at least one** file exists` case is still correct

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/coding-dispatch.md
git commit -m "fix: add explicit bash code block for pre-load disk check in coding-dispatch

The pseudo-code style 'test -e = ...' assignments did not prompt the AI
to run actual bash commands. Without running bash, the AI cannot expand
\$HOME or \$XDG_CONFIG_HOME and may fail to detect the global config.

Replace with an explicit bash code block that the AI will execute via
the Bash tool, which correctly expands shell variables."
```

---

## Task 6: Manual eval — verify global-only config is detected
category: backend

**Files:** None (verification only)

Before bumping the version, manually verify the fix works for the exact failure scenario: global config present at `$HOME/.config/superpowers/review-config.json`, no project config, `XDG_CONFIG_HOME` explicitly unset.

This eval verifies the bash commands added by Tasks 1 and 5 correctly produce the output that prevents the "both configs empty" condition (which is what triggers Setup UX). If the bash blocks report `global_exists=yes`, the AI will NOT reach the "both empty → Setup UX" branch in config-loading.md Step 3.

- [ ] **Step 1: Establish isolated test environment (XDG_CONFIG_HOME unset, global config present, no project config)**

```bash
# Confirm XDG_CONFIG_HOME is unset (test scenario requires it)
unset XDG_CONFIG_HOME

# Confirm global config exists with valid content at the expected path
GLOBAL_PATH="$HOME/.config/superpowers/review-config.json"
echo "=== Test setup ==="
echo "XDG_CONFIG_HOME: ${XDG_CONFIG_HOME:-<unset>}"
echo "GLOBAL_PATH: $GLOBAL_PATH"
test -e "$GLOBAL_PATH" && echo "global config: EXISTS (expected)" || echo "global config: MISSING (unexpected — abort)"
test -e ".superpowers/review-config.json" && echo "project config: EXISTS (unexpected)" || echo "project config: not present (expected)"
```

Expected output:
```
=== Test setup ===
XDG_CONFIG_HOME: <unset>
GLOBAL_PATH: /Users/<user>/.config/superpowers/review-config.json
global config: EXISTS (expected)
project config: not present (expected)
```

If `global config: MISSING`, stop — the test cannot proceed without the fixture.

- [ ] **Step 2: Verify config-loading.md Step 1 bash block detects the global file**

Run the mandatory bash block from the updated `config-loading.md` Step 1 with `XDG_CONFIG_HOME` unset:
```bash
unset XDG_CONFIG_HOME
GLOBAL_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"
PROJECT_PATH=".superpowers/review-config.json"
printf "global_path=%s\nglobal_exists=%s\nproject_path=%s\nproject_exists=%s\n" \
  "$GLOBAL_PATH" \
  "$(test -e "$GLOBAL_PATH" && echo yes || echo no)" \
  "$PROJECT_PATH" \
  "$(test -e "$PROJECT_PATH" && echo yes || echo no)"
```

Expected output:
```
global_path=/Users/<user>/.config/superpowers/review-config.json
global_exists=yes
project_path=.superpowers/review-config.json
project_exists=no
```

**This is the key assertion.** `global_exists=yes` means config-loading Step 3 will see a non-empty `global_cfg` and will NOT go to Setup UX. If `global_exists=no`, the fix is broken — stop and investigate.

- [ ] **Step 3: Verify config values are readable at the reported path**

Using the `global_path` value reported in Step 2, confirm jq can parse the file and extract the expected config values:
```bash
unset XDG_CONFIG_HOME
GLOBAL_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"
echo "=== Config values at $GLOBAL_PATH ==="
jq -r '.review_provider, .coding.enabled, .coding.default_provider' "$GLOBAL_PATH"
```

Expected output (matching the user's actual config):
```
=== Config values at /Users/<user>/.config/superpowers/review-config.json ===
codex
true
claude-code
```

This confirms the global config file is both detectable AND parseable — meaning config-loading Step 2 would produce a non-empty `global_cfg` with valid keys, which Step 3 would merge and return (skipping Setup UX).

- [ ] **Step 4: Verify coding-dispatch.md pre-load check also detects the global file**

```bash
unset XDG_CONFIG_HOME
test -e ".superpowers/review-config.json" \
  && echo "project_exists=yes" || echo "project_exists=no"
test -e "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \
  && echo "global_exists=yes" || echo "global_exists=no"
```

Expected output:
```
project_exists=no
global_exists=yes
```

`global_exists=yes` here means the pre-load check correctly falls through to config-loading (rather than short-circuiting on session state when no disk config is found).

- [ ] **Step 5: Regression check — "both missing" path still reports absence (Setup UX correctly fires)**

Simulate the scenario where no config exists at all, to confirm the "neither present" case still correctly reports absence:
```bash
unset XDG_CONFIG_HOME
GLOBAL_PATH="/tmp/nonexistent-superpowers-test-$$-review-config.json"
PROJECT_PATH="/tmp/nonexistent-superpowers-test-$$-project-config.json"
printf "global_path=%s\nglobal_exists=%s\nproject_path=%s\nproject_exists=%s\n" \
  "$GLOBAL_PATH" \
  "$(test -e "$GLOBAL_PATH" && echo yes || echo no)" \
  "$PROJECT_PATH" \
  "$(test -e "$PROJECT_PATH" && echo yes || echo no)"
```

Expected output: both `global_exists=no` and `project_exists=no`.

This confirms the "neither present" path still correctly reports absence — which would trigger Setup UX as expected (correct behavior when the user genuinely hasn't configured anything).

---

## Task 7: Bump patch version
category: backend

**Files:**
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.cursor-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `gemini-extension.json`

This is a bug fix (not a feature), so bump the patch version.

- [ ] **Step 1: Check current version**

```bash
cat package.json | grep '"version"'
```

Expected output shows current version like `"version": "5.0.12"`.

- [ ] **Step 2: Run version bump script**

```bash
node scripts/bump-version.sh patch 2>/dev/null || cat scripts/bump-version.sh | head -20
```

If the script doesn't exist or fails, manually bump the patch number in all version files listed above.

- [ ] **Step 3: Verify all version files updated consistently**

```bash
grep -r '"version"' package.json .claude-plugin/plugin.json .cursor-plugin/plugin.json gemini-extension.json
grep '"version"' .claude-plugin/marketplace.json
```

All files should show the same new version number.

- [ ] **Step 4: Commit**

```bash
git add package.json .claude-plugin/plugin.json .cursor-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
git commit -m "fix: detect user global config reliably (5.0.13)

Root cause: config-loading Step 1 labeled the path-resolution
bash one-liner as 'used internally', which reads as reference
documentation rather than a required execution step. When the AI
skipped running it, it retained the unexpanded shell variable template
as the path. Read tool calls with this template path would not find
the global config, causing Step 3 to see both configs empty and
triggering Setup UX — even when ~/.config/superpowers/review-config.json
existed with valid content.

Fixes:
- config-loading.md Step 1: 'Run this now' + printf output so the AI
  sees actual expanded paths and existence status; instruction to use
  reported values, not the template
- Standardize all description/display text from \${XDG_CONFIG_HOME:-~/.config}
  (tilde, not expanded inside \${}) to \${XDG_CONFIG_HOME:-\$HOME/.config}
  across config-loading.md, SDD SKILL.md, and writing-plans SKILL.md
- coding-dispatch.md pre-load check: explicit bash code block replaces
  pseudo-code variable assignments"
```
