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

## Step 2: Load Both Files

For each path (global, then project), produce a `cfg` object **and** a `had_parse_error` boolean as follows. (`<role>` is "Project" or "Global" depending on which file is being loaded.)

1. **File missing** → `cfg = {}`, `had_parse_error = false`. No warning.
2. **Parse the file** with `jq . "<path>" >/dev/null 2>&1` (note: plain `jq .`, not `jq -e .` — the latter exits non-zero for valid JSON values like `null` or `false`). If it fails (malformed JSON) → emit warning `⚠ <role> config <path> failed to parse: <jq error>; ignoring.`, set `cfg = {}`, `had_parse_error = true`. Skip the remaining substeps.
3. **Root-type guard.** If the parsed root is not a JSON object — i.e. `jq -e 'type == "object"' "<path>"` exits non-zero (root is `null`, an array, a number, a string, or a boolean) → emit warning `⚠ <role> config <path> has non-object root (got <jq type>); ignoring.`, set `cfg = {}`, `had_parse_error = true`. Skip the remaining substeps.
4. **Drop unknown keys**. Walk the parsed object; for any key not in the known-key list (below), emit warning `⚠ Unknown key '<dotted-path>' in <path>; ignored.` and exclude it.
5. **Type-check known keys**. For any known key whose value type does not match the expected type (below), emit warning `⚠ Invalid value for '<dotted-path>' in <path> (expected <type>); ignored.` and exclude it.

After Step 2 you have `project_cfg` and `global_cfg`, each a (possibly empty) object containing only valid known keys, plus the per-file `project_had_parse_error` / `global_had_parse_error` flags used by Step 3.

### Known keys

| Dotted path | Expected type |
|---|---|
| `review_provider` | string |
| `coding` | object |
| `coding.enabled` | boolean |
| `coding.default_provider` | string |
| `coding.rules` | array |
| `coding.rules[]` | object with exactly `category: string` and `provider: string` (extra fields treated as unknown) |

For each `coding.rules[]` entry: drop unknown sub-keys with a warning of the form `⚠ Unknown sub-key 'coding.rules[<i>].<key>' in <path>; ignored.` and keep the entry. If `category` or `provider` is missing or wrong-typed, drop the entire entry with a single warning `⚠ Invalid 'coding.rules[<i>]' in <path>; ignored.`.

## Step 3: Bootstrap Detection

If `project_cfg == {}` AND `global_cfg == {}`:

- If `project_had_parse_error` AND `global_had_parse_error` (both files were on disk and both failed to parse or had a non-object root) → emit the notice `Both configs unreadable. Falling back to interactive setup.` then go to **Step 6 (Setup UX)**.
- Otherwise (any combination of: missing, valid `{}`, all-unknown-keys-after-stripping, or one-side-only parse-error) → go to **Step 6 (Setup UX)** silently. Per-file warnings already emitted in Step 2 are sufficient context; no additional notice is needed.

If at least one of `project_cfg` or `global_cfg` has any valid keys → go to **Step 4 (Merge)**.

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

3. **Provider selection.** Present the `available` list (name + description from each provider JSON). Ask the user to pick one. Treat any of these as cancellation: an explicit "cancel" / "abort" / "no" reply, an empty input, or Ctrl-C. On cancellation → return `{ merged_config: {}, source: "user-declined" }`.

4. **Build the delta.** Start with `delta = { "review_provider": "<picked>" }`.

   **If `caller_intent == "coding"`**, extend the delta with a `coding` block by asking the user, in order:
   a. Default provider for coding (default: the provider picked in step 3).
   b. Whether to add category-specific rules. If yes, prompt for `category → provider` pairs (e.g., `frontend → claude-code`, `backend → codex`) until the user says "done".
   c. Set `delta.coding = { "enabled": true, "default_provider": "<chosen>", "rules": [<entries or empty>] }`.

   At this point the delta represents the complete config the user wants to persist.

5. **Save-location prompt.** Call the **Save-Location Helper** below with the full `delta` from step 4. The helper returns either a written file path (string) or the literal `"session-only"`.

6. Return based on the helper's return value:
   - If the helper returned a path (saved to global or project): `{ merged_config: <delta>, source: "merged" }`.
   - If the helper returned `"session-only"`: `{ merged_config: <delta>, source: "session-only" }`.

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

2. Read the user's choice (A / B / C). If the input is anything else (empty, "D", arbitrary text), reprint the three choices and ask again. Treat an explicit "cancel" / "abort" reply or Ctrl-C as choice C (session-only).

3. **A or B:**
   a. Resolve target path (`global_path` for A, `project_path` for B).
   b. `mkdir -p "$(dirname "<path>")"`.
   c. **Compute the new file content.** Read the existing file (or treat as `{}` if missing). Apply `delta` using the same merge rules as Step 4 (read-side merge), but with `delta` taking the role of `project_cfg` (override) and the existing file content taking the role of `global_cfg` (defaults). In particular:
      - Top-level scalar keys (`review_provider`): replace if present in `delta`; otherwise preserve existing.
      - If `delta` has no `coding` key, leave the existing `coding` block untouched.
      - `coding.enabled` and `coding.default_provider`: replace if present in `delta`; otherwise preserve existing.
      - `coding.rules`: apply Level 3's category-keyed merge. The empty-array exception (`delta.coding.rules == []`) explicitly clears global rules in the on-disk file.
   d. Write the result. If the write fails (permission, disk), emit `⚠ Could not write to <path>: <reason>. Choose another location.` and re-prompt from step 1.
   e. Return the path.

4. **C:** return `"session-only"` without touching disk.

## Error Handling Summary

| Event | Behavior |
|---|---|
| Project JSON parse failure | Warn; treat as `{}` with `had_parse_error = true`; continue with global. |
| Global JSON parse failure | Warn; treat as `{}` with `had_parse_error = true`; continue with project. |
| Non-object root (e.g. `null`, `[…]`, `42`) | Warn; treat as `{}` with `had_parse_error = true`; continue. |
| Both files had a parse or root-type failure | Warn each; treat both as `{}`; emit notice `Both configs unreadable. Falling back to interactive setup.`; bootstrap to Setup UX. |
| Both files empty / unknown-keys-only / mixed-with-one-error | Bootstrap to Setup UX silently (per-file warnings already shown in Step 2). |
| Unknown key | Warn; drop key; continue. |
| Type validation failure | Warn; drop key; continue. |
| Setup UX cancelled | Return `source: "user-declined"`; caller decides fallback. |
| Save-time permission error | Warn; re-prompt save-location choices. |

## Caller Integration Notes

- `review-dispatch.md` Step 2 calls this procedure with `caller_intent="review"` and uses `merged_config.review_provider` for downstream provider resolution. If `source == "user-declined"` or `merged_config.review_provider` is undefined after a non-bootstrap merge, the dispatcher proceeds to its existing scan-and-prompt fallback.
- `coding-dispatch.md` Step 1 calls this procedure with `caller_intent="coding"` and uses `merged_config.coding` for downstream routing. Treat `coding` absent as "needs setup" (prompt the user) and `coding.enabled === false` as "disabled" (silent fallback). When `coding` is present but `coding.enabled` is absent, treat it as `true` (backward compatibility with configs that only set `default_provider` or `rules`).
