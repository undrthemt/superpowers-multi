# User Global Review/Coding Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-multi:subagent-driven-development (recommended) or superpowers-multi:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user global config layer at `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` that provides defaults for `review_provider` and `coding.*`, while the existing project config `.superpowers/review-config.json` continues to act as per-project override.

**Architecture:** Both review-dispatch.md (Step 2) and coding-dispatch.md (Step 1) delegate config loading to a new shared procedure at `skills/requesting-code-review/config-loading.md`. The shared procedure resolves both file paths (XDG-aware), loads them with permissive error handling, performs key-level merge (with category-keyed merge for `coding.rules` and an empty-array exception), and runs an interactive setup UX with three save-location choices when no config exists.

**Tech Stack:** Markdown (skill files), JSON (config + provider definitions)

**Spec:** `docs/superpowers/specs/2026-05-07-user-global-review-config-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `skills/requesting-code-review/config-loading.md` | Create | Shared config loading: path resolution, load with error handling, merge, setup UX, save-location helper |
| `skills/requesting-code-review/review-dispatch.md` | Modify | Step 2 delegates to `config-loading.md` |
| `skills/subagent-driven-development/coding-dispatch.md` | Modify | Step 1 delegates to `config-loading.md`; coding-only setup uses save-location helper |
| `skills/requesting-code-review/SKILL.md` | Modify | Add `config-loading.md` to `See:` list |
| `skills/subagent-driven-development/SKILL.md` | Modify | Update config-location wording (global or project) |
| `skills/writing-plans/SKILL.md` | Modify | Update line 109 reference (global or project) |
| `README.md` | Modify | Document global + project layering with example |
| `RELEASE-NOTES.md` | Modify | Add v5.0.10 entry |
| `.claude-plugin/plugin.json` | Modify | Bump version 5.0.9 → 5.0.10 |
| `.claude-plugin/marketplace.json` | Modify | Bump version 5.0.9 → 5.0.10 |
| `gemini-extension.json` | Modify | Bump version 5.0.9 → 5.0.10 |
| `package.json` | Modify | Bump version 5.0.9 → 5.0.10 |
| `.cursor-plugin/plugin.json` | Modify | Bump version 5.0.9 → 5.0.10 |

---

### Task 1: Create config-loading.md
category: backend

**Files:**
- Create: `skills/requesting-code-review/config-loading.md`

- [ ] **Step 1: Verify the file does not exist yet**

Run:
```bash
test ! -e skills/requesting-code-review/config-loading.md && echo "ok: not yet created" || echo "FAIL: already exists"
```
Expected: `ok: not yet created`

- [ ] **Step 2: Create the shared procedure file**

Create `skills/requesting-code-review/config-loading.md` with the following exact content:

````markdown
# Config Loading Procedure

Centralized config loader shared by `review-dispatch.md` (Step 2) and `coding-dispatch.md` (Step 1). Resolves a user global config and a project config, merges them, and runs an interactive setup UX when neither exists.

## Inputs

- **caller_intent**: `"review"` or `"coding"`. Used only to tailor the setup-UX intro message.

## Outputs

Return an object with:
- **merged_config**: the resolved config (may be empty if user declined).
- **source**: one of `"merged"` (loaded from disk and/or written this run), `"session-only"` (chose not to persist), `"user-declined"` (aborted).

## Step 1: Resolve Paths

- `project_path = "<repo>/.superpowers/review-config.json"` — resolved against the current working directory's repo root.
- `global_path  = "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"` — honor `XDG_CONFIG_HOME` if set, otherwise fall back to `$HOME/.config`.

Bash one-liner used internally:
```bash
GLOBAL_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"
PROJECT_PATH=".superpowers/review-config.json"
```

## Step 2: Load Both Files

For each path (global, then project), produce a `cfg` object as follows:

1. **File missing** → `cfg = {}`. No warning.
2. **Read file**. If `jq -e . "<path>" >/dev/null 2>&1` fails (malformed JSON) → emit warning `⚠ <role> config <path> failed to parse: <jq error>; ignoring.` (where `<role>` is "Project" or "Global") and set `cfg = {}`.
3. **Drop unknown keys**. Walk the parsed object; for any key not in the known-key list (below), emit warning `⚠ Unknown key '<dotted-path>' in <path>; ignored.` and exclude it.
4. **Type-check known keys**. For any known key whose value type does not match the expected type (below), emit warning `⚠ Invalid value for '<dotted-path>' in <path> (expected <type>); ignored.` and exclude it.

After Step 2 you have `project_cfg` and `global_cfg`, each a (possibly empty) object containing only valid known keys.

### Known keys

| Dotted path | Expected type |
|---|---|
| `review_provider` | string |
| `coding` | object |
| `coding.enabled` | boolean |
| `coding.default_provider` | string |
| `coding.rules` | array |
| `coding.rules[]` | object with exactly `category: string` and `provider: string` (extra fields treated as unknown) |

Invalid `coding.rules[]` entries are dropped individually with the same warning format.

## Step 3: Bootstrap Detection

If both `project_cfg` and `global_cfg` are completely empty objects (no valid keys after Step 2) → go to **Step 6 (Setup UX)**.

Otherwise → go to **Step 4 (Merge)**.

## Step 4: Merge

Compute `merged_config` by combining `global_cfg` (defaults) with `project_cfg` (overrides):

### Level 1 — top-level keys

- `review_provider`: simple replace. If `project_cfg.review_provider` is present, use it; else use `global_cfg.review_provider`; else leave undefined.
- `coding`: if either side has a `coding` object, recurse into Level 2 to produce `merged.coding`. If neither has it, leave undefined.

### Level 2 — `coding.*`

- `coding.enabled`: simple replace (project wins if present).
- `coding.default_provider`: simple replace (project wins if present).
- `coding.rules`: recurse into Level 3.

### Level 3 — `coding.rules`

**Empty-array exception (check first):** If `project_cfg.coding.rules` is *explicitly present* and is an empty array `[]`, set `merged.coding.rules = []` and skip the rest of Level 3. (This is how a user disables global rules per-project without flipping `enabled`.)

Otherwise, treat the arrays as dictionaries keyed by `category`:

1. Initialize `merged_rules_map` from `global_cfg.coding.rules` in order: each entry becomes `{ category → rule_object }`.
2. For each entry in `project_cfg.coding.rules` (in order), set `merged_rules_map[entry.category] = entry`. This overwrites any global entry with the same category.
3. Emit `merged.coding.rules` as an array. Order: original global order first (for categories present in global), then project-only categories appended in their project order.

### Worked example

```jsonc
// global
{ "coding": { "rules": [
  { "category": "frontend", "provider": "claude-code" },
  { "category": "backend",  "provider": "codex" }
]}}

// project
{ "coding": { "rules": [
  { "category": "backend", "provider": "claude-code" }
]}}

// merged
{ "coding": { "rules": [
  { "category": "frontend", "provider": "claude-code" },
  { "category": "backend",  "provider": "claude-code" }
]}}
```

## Step 5: Return (merged path)

Return `{ merged_config, source: "merged" }`.

## Step 6: First-Time Setup UX

Triggered only when both files are empty after Step 2.

1. **Discover providers.** For each `*.json` file under `skills/requesting-code-review/providers/`, run its `detect` command via Bash. Collect successes into an `available` list.

2. **Show intro** based on `caller_intent`:
   - `review`: `Code review provider is not configured. Pick one to use.`
   - `coding`: `Multi-AI coding dispatch is not configured. Pick a provider to set up.`

3. **Provider selection.** Present the `available` list (name + description from each provider JSON). Ask the user to pick one. If they cancel/abort → return `{ merged_config: {}, source: "user-declined" }`.

4. **Save-location prompt** (call the **Save-Location Helper** below with the pending delta `{ "review_provider": "<picked>" }`).

5. **If caller_intent == "coding" and the user picked a save location (not session-only):** continue with the existing coding-dispatch.md setup flow:
   a. Ask whether they want a `default_provider` (defaults to the picked provider).
   b. Ask whether they want category-specific rules. If yes, prompt for entries (e.g., `frontend → claude-code`, `backend → codex`) until they say "done".
   c. Append a `coding` section to the same file the helper just wrote:
      ```json
      "coding": {
        "enabled": true,
        "default_provider": "<chosen>",
        "rules": [ ... ]
      }
      ```

6. Return:
   - If saved (global or project): `{ merged_config: <what was written>, source: "merged" }`.
   - If session-only: `{ merged_config: { "review_provider": "<picked>", ...optional coding... }, source: "session-only" }`.

## Save-Location Helper

A reusable subroutine. Used by Step 6 above and by `coding-dispatch.md`'s coding-only setup path.

**Inputs:** `delta` — the JSON object to merge into the chosen file.

**Output:** the resolved write path (string), or the literal `"session-only"`.

**Steps:**

1. Present three choices, exactly:
   ```
   A. User global (recommended) — ${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json
   B. This project only        — <repo>/.superpowers/review-config.json
   C. Don't save (session only) — remember just for this session
   ```

2. Read the user's choice (A / B / C).

3. **A or B:**
   a. Resolve target path (`global_path` for A, `project_path` for B).
   b. `mkdir -p "$(dirname "<path>")"`.
   c. If the file exists, read it and `jq -s '.[0] * .[1]'` merge with `delta` (deep merge, project_cfg-style — for arrays use the same Level 3 rules; for the writing case here `delta` is a fresh object so simple merge is sufficient).
   d. Write the result. If the write fails (permission, disk), emit `⚠ Could not write to <path>: <reason>. Choose another location.` and re-prompt from step 1.
   e. Return the path.

4. **C:** return `"session-only"` without touching disk.

## Error Handling Summary

| Event | Behavior |
|---|---|
| Project JSON parse failure | Warn; treat as `{}`; continue with global. |
| Global JSON parse failure | Warn; treat as `{}`; continue with project. |
| Both unreadable | Warn each; treat both as `{}`; bootstrap to Setup UX. |
| Unknown key | Warn; drop key; continue. |
| Type validation failure | Warn; drop key; continue. |
| Setup UX cancelled | Return `source: "user-declined"`; caller decides fallback. |
| Save-time permission error | Warn; re-prompt save-location choices. |

## Caller Integration Notes

- `review-dispatch.md` Step 2 calls this procedure with `caller_intent="review"` and uses `merged_config.review_provider` for downstream provider resolution. If `source == "user-declined"` or `merged_config.review_provider` is undefined after a non-bootstrap merge, the dispatcher proceeds to its existing scan-and-prompt fallback.
- `coding-dispatch.md` Step 1 calls this procedure with `caller_intent="coding"` and uses `merged_config.coding` for downstream routing. Treat absent `coding` or `coding.enabled !== true` per the existing "coding disabled" path.
````

- [ ] **Step 3: Verify the file was written and parses as markdown**

Run:
```bash
test -f skills/requesting-code-review/config-loading.md && \
  head -3 skills/requesting-code-review/config-loading.md
```
Expected: file exists; first lines show `# Config Loading Procedure`.

- [ ] **Step 4: Verify embedded JSON snippets are valid**

Run:
```bash
awk '/```jsonc/,/```$/' skills/requesting-code-review/config-loading.md | grep -v '```' | jq -s . >/dev/null && echo "jsonc samples parse OK"
```
Expected: `jsonc samples parse OK` (the spec uses `jsonc` blocks; if jq is strict, fall back to visual inspection — comments after `//` are present and acceptable as design illustrations).

If the above fails because of `jsonc` comments, that is fine for documentation — verify visually that the example pairs (global, project, merged) are consistent with Section 4's worked example.

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/config-loading.md
git commit -m "feat: add shared config-loading procedure for review/coding dispatch"
```

---

### Task 2: Update review-dispatch.md Step 2 to delegate
category: backend

**Files:**
- Modify: `skills/requesting-code-review/review-dispatch.md` (Step 2 section)

- [ ] **Step 1: Verify current Step 2 wording is present (precondition)**

Run:
```bash
grep -n "Config file exists" skills/requesting-code-review/review-dispatch.md
```
Expected: a line referencing `Config file exists at .superpowers/review-config.json`.

- [ ] **Step 2: Replace the Step 2 block**

Replace the current Step 2 section (the one starting with `## Step 2: Resolve Provider` and ending just before `## Step 3: Load Provider Definition`) with this exact content:

```markdown
## Step 2: Resolve Provider

Check in this order (first match wins):

1. **User explicitly named a provider** in the current request (e.g. "review with gemini") → use that provider name. Skip to Step 3.

2. **Load merged config** by following `./config-loading.md` with `caller_intent="review"`. It returns `{ merged_config, source }`.
   - If `merged_config.review_provider` is set → use it. Skip to Step 3.
   - If `source == "user-declined"` and `merged_config.review_provider` is unset → notify "No review provider configured." and proceed to step 2.3.

3. **No provider resolved** → discover and ask:
   a. Scan `skills/requesting-code-review/providers/` for all `*.json` files
   b. For each provider, run its `detect` command to check if the CLI is installed
   c. Present the user with available providers: name + description
   d. User selects one. Remember this choice for the rest of the session (do not write to disk)
```

Use Edit to replace the existing block.

- [ ] **Step 3: Verify the new block is in place**

Run:
```bash
grep -c "config-loading.md" skills/requesting-code-review/review-dispatch.md
```
Expected: `1` (or more if the file already cross-referenced it elsewhere).

Also run:
```bash
grep -c "Config file exists at \`.superpowers/review-config.json\`" skills/requesting-code-review/review-dispatch.md
```
Expected: `0` (the old wording is gone).

- [ ] **Step 4: Commit**

```bash
git add skills/requesting-code-review/review-dispatch.md
git commit -m "feat: review-dispatch.md Step 2 delegates to config-loading.md"
```

---

### Task 3: Update coding-dispatch.md Step 1 to delegate
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/coding-dispatch.md` (Step 1 section)

- [ ] **Step 1: Verify current Step 1 wording is present (precondition)**

Run:
```bash
grep -n "Step 1: Check Coding Enabled" skills/subagent-driven-development/coding-dispatch.md
```
Expected: a line with `## Step 1: Check Coding Enabled`.

- [ ] **Step 2: Replace the Step 1 block**

Replace the current Step 1 section (everything from `## Step 1: Check Coding Enabled` up to `## Step 2: Resolve Provider`) with this exact content:

```markdown
## Step 1: Check Coding Enabled

Load the merged config by following `skills/requesting-code-review/config-loading.md` with `caller_intent="coding"`. It returns `{ merged_config, source }`.

**`merged_config.coding` is absent and `source != "merged"`** (i.e., neither file existed; setup UX did not produce a `coding` block — for example the user picked session-only for review only) → prompt the user:

> "Multi-AI coding dispatch is available but not configured. To route implementation tasks to external AI providers (e.g., different providers for frontend vs backend), set up a `coding` section now. Would you like to?"

- If user **declines** → skip to Step 7 (Fallback). Remember this choice for the session — do not prompt again.
- If user **agrees** → guide them through setup:
  1. Ask which default provider to use (scan `skills/requesting-code-review/providers/` for available CLIs).
  2. Ask if they want category-specific rules (e.g., frontend → claude-code, backend → codex).
  3. Use the **Save-Location Helper** in `skills/requesting-code-review/config-loading.md` to choose where to write (global / project / session-only). Pass the delta:
     ```json
     {
       "coding": {
         "enabled": true,
         "default_provider": "<chosen>",
         "rules": [
           { "category": "frontend", "provider": "claude-code" },
           { "category": "backend",  "provider": "codex" }
         ]
       }
     }
     ```
  4. Re-run config loading; proceed to Step 2.

**`merged_config.coding` is present but `coding.enabled` is explicitly `false`** → skip to Step 7 silently. The user has opted out.

**`merged_config.coding` is present and `coding.enabled` is `true`** (or absent — treat absent as `true` for backward compatibility with configs that only set `default_provider` or `rules`) → proceed to Step 2.
```

Use Edit to replace the existing block.

- [ ] **Step 3: Verify the new block is in place**

Run:
```bash
grep -c "config-loading.md" skills/subagent-driven-development/coding-dispatch.md
```
Expected: `1` or more.

Also run:
```bash
grep -c 'Read \`.superpowers/review-config.json\`.' skills/subagent-driven-development/coding-dispatch.md
```
Expected: `0` (old direct-read wording is gone).

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/coding-dispatch.md
git commit -m "feat: coding-dispatch.md Step 1 delegates to config-loading.md"
```

---

### Task 4: Update requesting-code-review/SKILL.md See list
category: backend

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md` (the `See:` block at the bottom)

- [ ] **Step 1: Verify current See block**

Run:
```bash
tail -10 skills/requesting-code-review/SKILL.md
```
Expected: lines listing `review-prompt.md`, `review-dispatch.md`, `providers/`.

- [ ] **Step 2: Add config-loading.md to the See list**

Replace the existing `See:` block (currently 3 bullets) with:

```markdown
See:
- `review-prompt.md` - Code quality review template (provider-agnostic)
- `review-dispatch.md` - Dispatch logic (provider resolution, CLI invocation, fallback)
- `config-loading.md` - Shared config loading: global + project layering, merge, setup UX
- `providers/` - Provider definitions (codex.json, claude-code.json)
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "config-loading.md" skills/requesting-code-review/SKILL.md
```
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "docs: link config-loading.md from requesting-code-review SKILL"
```

---

### Task 5: Update subagent-driven-development/SKILL.md config wording
category: backend

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (the "Coding dispatch" paragraph near the top)

- [ ] **Step 1: Locate current wording**

Run:
```bash
grep -n "Coding dispatch:" skills/subagent-driven-development/SKILL.md
```
Expected: a single line near the top of the file.

- [ ] **Step 2: Replace the paragraph**

Replace the current single-paragraph definition starting `**Coding dispatch:**` (the one that ends with `See `./coding-dispatch.md` for the full routing logic.`) with:

```markdown
**Coding dispatch:** Before dispatching the host AI implementer, the system can route implementation tasks to an external AI coding provider based on task category (frontend, backend, etc.). Configuration is layered: an optional user global config at `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` provides defaults, and an optional project config at `.superpowers/review-config.json` overrides per-project. Either, both, or neither may exist. When disabled or unconfigured, the existing host AI implementer flow is used. See `./coding-dispatch.md` for the full routing logic and `skills/requesting-code-review/config-loading.md` for how the two configs are loaded and merged.
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "user global config" skills/subagent-driven-development/SKILL.md
```
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "docs: clarify global+project config layering in SDD SKILL"
```

---

### Task 6: Update writing-plans/SKILL.md category-tag wording
category: backend

**Files:**
- Modify: `skills/writing-plans/SKILL.md` line ~109

- [ ] **Step 1: Locate the line**

Run:
```bash
grep -n "the project uses multi-AI coding dispatch" skills/writing-plans/SKILL.md
```
Expected: matches around line 109.

- [ ] **Step 2: Replace the wording**

Replace the line:

```markdown
When the project uses multi-AI coding dispatch (`.superpowers/review-config.json` with `coding.enabled: true`), tasks can include a `category:` field to control which AI provider handles the implementation:
```

with:

```markdown
When multi-AI coding dispatch is enabled (via `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` or `.superpowers/review-config.json`, with `coding.enabled: true`), tasks can include a `category:` field to control which AI provider handles the implementation:
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "XDG_CONFIG_HOME" skills/writing-plans/SKILL.md
```
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "docs: writing-plans references both global and project config locations"
```

---

### Task 7: Update README.md
category: backend

**Files:**
- Modify: `README.md` (the "Multi-AI Code Review Dispatch" and "Multi-AI Coding Dispatch" sections, plus the "Optional `.superpowers/review-config.json`" bullet under Prerequisites)

- [ ] **Step 1: Locate current config descriptions**

Run:
```bash
grep -n "review-config.json" README.md
```
Expected: 4 hits — line ~11 (review section description), line ~20 (coding section description), line ~46 (Prerequisites bullet).

- [ ] **Step 2: Replace the review section line**

Find:
```
Adds a configurable mechanism to dispatch code reviews to different AI providers (Codex CLI, Claude Code, etc.). The provider is selected via `.superpowers/review-config.json` (`review_provider` key) and provider definitions live in `skills/requesting-code-review/providers/*.json`. Falls back to host-AI subagents when the configured provider is unavailable.
```

Replace with:
```
Adds a configurable mechanism to dispatch code reviews to different AI providers (Codex CLI, Claude Code, etc.). The provider is selected via `review_provider` in either `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` (user global; recommended for personal defaults) or `.superpowers/review-config.json` (project; overrides global per-project). Both files are optional; when both exist, project keys override global at every nesting level. Provider definitions live in `skills/requesting-code-review/providers/*.json`. Falls back to host-AI subagents when the configured provider is unavailable.
```

- [ ] **Step 3: Replace the coding section line**

Find:
```
Routes implementation tasks to AI providers by task category, so frontend and backend work can be handled by different providers. Configured via the `coding` key in `.superpowers/review-config.json`:
```

Replace with:
```
Routes implementation tasks to AI providers by task category, so frontend and backend work can be handled by different providers. Configured via the `coding` key in the same `review-config.json` files described above (global at `${XDG_CONFIG_HOME:-~/.config}/superpowers/`, project at `<repo>/.superpowers/`). The `coding.rules` array merges by `category`: a project override of `backend` keeps the global `frontend` entry intact. An empty `rules: []` in the project config explicitly disables global rules for that project.
```

- [ ] **Step 4: Replace the Prerequisites bullet**

Find:
```
- **Optional `.superpowers/review-config.json`:** Configure `review_provider` and the `coding` section to control routing. Without a config, the system prompts to set one up the first time it runs.
```

Replace with:
```
- **Optional global config** at `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` (recommended for personal defaults across all projects) **and/or project config** at `.superpowers/review-config.json` (overrides global per-project). Both are optional. Without either, the system prompts to set one up the first time it runs and asks where to save (global / project / session-only).
```

- [ ] **Step 5: Verify**

Run:
```bash
grep -c "XDG_CONFIG_HOME" README.md && grep -c "user global" README.md
```
Expected: each at least `1`.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: README documents global+project review-config layering"
```

---

### Task 8: Update RELEASE-NOTES.md
category: backend

**Files:**
- Modify: `RELEASE-NOTES.md` (prepend new v5.0.10 section above v5.0.9)

- [ ] **Step 1: Verify file head**

Run:
```bash
head -3 RELEASE-NOTES.md
```
Expected: `# Superpowers Release Notes` then a blank line then `## v5.0.9 (2026-05-07)`.

- [ ] **Step 2: Insert the new entry**

Insert this block immediately after the `# Superpowers Release Notes` heading and the blank line that follows it (before `## v5.0.9`):

```markdown
## v5.0.10 (2026-05-07)

### User Global Review/Coding Config (fork-specific)

Adds a user global config layer so personal defaults (preferred review provider, default coding routing) can live in `$HOME` instead of being copied into every project. Project config remains the per-project override.

- **Two-layer config** — `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` (user global, optional) and `.superpowers/review-config.json` (project, optional). Both files share the same schema. When both exist, project keys override global at every nesting level. `coding.rules` merges by `category`; an explicit empty array `"rules": []` in the project config disables global rules for that project.
- **New shared procedure** — `skills/requesting-code-review/config-loading.md` centralizes path resolution, file loading, error handling (malformed JSON warns and is treated as empty; unknown keys warn and are dropped), merge semantics, and the first-time setup UX. Both `review-dispatch.md` (Step 2) and `coding-dispatch.md` (Step 1) delegate to it instead of reading `review-config.json` directly.
- **Setup UX** — when neither config exists, the user picks a provider and then a save location (global / project / session-only). Existing users with a project config see no change.
- **XDG-aware** — the global path honors `XDG_CONFIG_HOME` if set; otherwise falls back to `$HOME/.config/superpowers/`.
- **Backward compatible** — projects with only `.superpowers/review-config.json` work unchanged; the global file is purely additive.
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "## v5.0.10" RELEASE-NOTES.md
```
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add RELEASE-NOTES.md
git commit -m "docs: add v5.0.10 release notes for user global config"
```

---

### Task 9: Bump version to 5.0.10 in all manifests
category: backend

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `gemini-extension.json`
- Modify: `package.json`
- Modify: `.cursor-plugin/plugin.json`

- [ ] **Step 1: Verify all five files are at 5.0.9 (precondition)**

Run:
```bash
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json package.json .cursor-plugin/plugin.json; do
  echo -n "$f: "
  jq -r '.version // (.plugins[0].version // "no version field")' "$f"
done
```
Expected: each line ends with `5.0.9`.

- [ ] **Step 2: Bump versions**

For each of the five files, change `"version": "5.0.9"` to `"version": "5.0.10"`.

In `.claude-plugin/marketplace.json` the version is nested under `plugins[0].version` — bump it there.

In `.claude-plugin/plugin.json`, `gemini-extension.json`, `package.json`, `.cursor-plugin/plugin.json` the version is at top level — bump it there.

- [ ] **Step 3: Verify all five are now at 5.0.10**

Run:
```bash
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json package.json .cursor-plugin/plugin.json; do
  echo -n "$f: "
  jq -r '.version // (.plugins[0].version // "no version field")' "$f"
done
```
Expected: each line ends with `5.0.10`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json package.json .cursor-plugin/plugin.json
git commit -m "chore: bump version to 5.0.10"
```

---

### Task 10: Static checks and manual scenario walkthrough
category: backend

**Files:**
- (none — verification only)

- [ ] **Step 1: Reference integrity checks**

Run all of the following; each must succeed:

```bash
test -f skills/requesting-code-review/config-loading.md && echo "config-loading.md exists"
grep -q "config-loading.md" skills/requesting-code-review/review-dispatch.md && echo "review-dispatch references it"
grep -q "config-loading.md" skills/subagent-driven-development/coding-dispatch.md && echo "coding-dispatch references it"
grep -q "config-loading.md" skills/requesting-code-review/SKILL.md && echo "SKILL.md links it"
grep -q "config-loading.md" skills/subagent-driven-development/SKILL.md && echo "SDD SKILL links it"
```
Expected: five "exists" / "references it" / "links it" lines.

- [ ] **Step 2: providers/ paths in config-loading.md are real**

Run:
```bash
grep -oE 'skills/requesting-code-review/providers/[^ ]*' skills/requesting-code-review/config-loading.md | sort -u
ls skills/requesting-code-review/providers/
```
Expected: every path mentioned in `config-loading.md` resolves to a real file or directory under `skills/requesting-code-review/providers/`.

- [ ] **Step 3: JSON examples in config-loading.md are coherent**

Manually inspect the worked-example block in Section 4 (Merge) of `skills/requesting-code-review/config-loading.md`. Confirm:
- The `global` block has `frontend → claude-code` and `backend → codex`.
- The `project` block overrides `backend → claude-code`.
- The `merged` block keeps `frontend → claude-code` (from global) and shows `backend → claude-code` (overridden).

If any divergence: edit and recommit before continuing.

- [ ] **Step 4: Confirm the manual verification checklist exists at the bottom of this plan**

Run:
```bash
grep -c "## Manual Verification Checklist" docs/superpowers/plans/2026-05-07-user-global-review-config.md
```
Expected: `1` (the checklist is part of the plan file already).

The checklist itself is not run now — it is the post-implementation hand-test record. The maintainer walks through the 11 scenarios during normal use (or when a regression is suspected) and reports any divergence as a follow-up task.

No additional commit needed for this task; verification only.

---

## Manual Verification Checklist (post-implementation)

(This section is populated by Task 10 Step 4. Until Task 10 runs, the checklist below is the source.)

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 1 | Project-only config | `.superpowers/review-config.json` exists with `review_provider: "codex"`. No global file. | Existing behavior; codex used; no warnings. |
| 2 | Global-only config | `~/.config/superpowers/review-config.json` exists with `review_provider: "codex"`. No project file. | codex used. |
| 3 | Both, project overrides `review_provider` | global=`codex`, project=`claude-code`. | claude-code used. |
| 4 | Both, project overrides only `coding.rules.backend` | global has frontend+backend rules, project has only backend rule. | frontend from global, backend from project. |
| 5 | Project `"coding": { "rules": [] }` | global has rules, project sets empty array. | merged `coding.rules` is `[]` (global rules dropped). |
| 6 | Project `"coding": { "enabled": false }` | global has full coding, project disables. | dispatcher skips to Fallback. |
| 7 | Global JSON malformed | global file is invalid JSON. | warning fires, global ignored, project still works. |
| 8 | Unknown key in global | global has `"foo": 1`. | warning fires, key dropped, rest works. |
| 9 | Both missing → setup UX | no files anywhere. | 3-choice prompt appears (global / project / session-only). |
| 10 | Setup UX → "session only" | choose C. | no file written; next session prompts again. |
| 11 | XDG_CONFIG_HOME redirect | export XDG_CONFIG_HOME=/tmp/xdg; place file at /tmp/xdg/superpowers/review-config.json. | XDG path is read in preference to ~/.config. |
