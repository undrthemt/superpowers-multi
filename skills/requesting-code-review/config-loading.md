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
