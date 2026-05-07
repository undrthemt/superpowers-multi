# User Global Review/Coding Config — Design

**Date:** 2026-05-07
**Status:** Approved (brainstorming)
**Author:** dev@movefast.xyz
**Related:** `docs/superpowers/specs/2026-04-22-multi-ai-review-dispatch-design.md`, `docs/superpowers/plans/2026-04-28-multi-ai-coding-dispatch.md`

## 1. Context

Today the review/coding dispatch system reads a single config file at `.superpowers/review-config.json` (project root). Users with stable personal preferences across many projects (e.g., "always use codex for review") cannot express that without copying the same file into every project. There is no user-level (`$HOME`-based) global config.

This design adds a user global config file that acts as defaults across all projects, while preserving the existing project-level config as a per-project override layer. Both files are optional. When both exist, they merge at key level (project overrides global).

**Goal:** Let users put personal preferences in `~/.config/superpowers/review-config.json` and override only what's project-specific in `.superpowers/review-config.json`.

## 2. Goals & Non-Goals

### Goals

- Read a user global config from `${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json`.
- Merge global (defaults) with project (overrides) at key level.
- Keep existing project-only configs working with no change.
- Update the first-time setup UX to ask where to save (global / project / session-only).
- Provide a single shared config-loading procedure that both review and coding dispatchers reuse.

### Non-Goals

- Schema versioning. The current schema has none; we do not introduce one in this change.
- Encryption or permission hardening for the global file (it is meant for non-secret routing preferences).
- XDG migration of unrelated `~/.config/superpowers/` paths (worktrees, hooks). Out of scope.
- Server-side or team-shared config sources. Local files only.

## 3. Resolution Model

The merged config is computed as:

```
merged = global_defaults ⊕ project_overrides
```

Resolution order for callers:

1. Explicit user request in the current session (e.g., "review with gemini") — wins.
2. `merged` config (project keys override global keys at every nesting level).
3. If both files are absent (or empty), interactive setup with three save-location choices.

This replaces the current "project file only → otherwise interactive scan" two-step.

## 4. File Layout

```
${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json   # NEW: user global, optional
<repo>/.superpowers/review-config.json                              # existing: project, optional

skills/requesting-code-review/
├── config-loading.md          # NEW: shared config loading procedure
├── review-dispatch.md         # MODIFIED: Step 2 delegates to config-loading.md
├── review-prompt.md           # unchanged
└── providers/                 # unchanged

skills/subagent-driven-development/
├── coding-dispatch.md         # MODIFIED: Step 1 delegates to config-loading.md
└── ...                        # unchanged
```

## 5. Schema

Both files share the same schema. All fields are optional.

```jsonc
{
  "review_provider": "codex",
  "coding": {
    "enabled": true,
    "default_provider": "codex",
    "rules": [
      { "category": "frontend", "provider": "claude-code" },
      { "category": "backend",  "provider": "codex" }
    ]
  }
}
```

### Known keys

- `review_provider`: string. Provider name; must match a `skills/requesting-code-review/providers/<name>.json`.
- `coding.enabled`: boolean. When `false`, coding dispatch is disabled and the host implementer is used directly.
- `coding.default_provider`: string. Used when no rule matches the task category.
- `coding.rules`: array of `{ category: string, provider: string }`.

Any other key is **unknown**. Unknown keys produce a warning and are excluded from the merged result.

## 6. Merge Semantics

### Level 1 — Top-level

- `review_provider`: simple replace (project value wins if present, else global, else undefined).
- `coding`: object — recurse to Level 2.

### Level 2 — `coding.*`

- `coding.enabled`: simple replace.
- `coding.default_provider`: simple replace.
- `coding.rules`: array — recurse to Level 3.

### Level 3 — `coding.rules`

Treat the array as a dictionary keyed by `category`:

1. Convert `global.coding.rules` to `Map<category, rule>`.
2. Convert `project.coding.rules` to `Map<category, rule>`.
3. Merge: project entries overwrite global entries with the same category.
4. Emit back as an array. Order: original global order first, then project-only categories appended.

#### Empty-array exception

If `project.coding.rules` is **explicitly present and an empty array**, the merged `coding.rules` is `[]` (global rules are dropped entirely). This gives users a way to disable category routing per-project without flipping `enabled` to `false`.

If `project.coding.rules` is absent (key not present), normal dictionary merge applies.

### Worked example

Given:

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
```

Merged:

```jsonc
{ "coding": { "rules": [
  { "category": "frontend", "provider": "claude-code" },
  { "category": "backend",  "provider": "claude-code" }   // project override
]}}
```

### Disabling global routing per-project

| Goal | Project config |
|---|---|
| Disable coding dispatch entirely | `{ "coding": { "enabled": false } }` |
| Keep coding enabled but ignore all global category rules | `{ "coding": { "rules": [] } }` |

### Validation

- `review_provider`: must be string.
- `coding.enabled`: must be boolean.
- `coding.default_provider`: must be string.
- `coding.rules`: must be array; each entry must be object with string `category` and string `provider`.

A type violation produces a warning and the offending key is excluded.

## 7. Shared Procedure: `config-loading.md`

### Inputs

- `caller_intent`: `"review"` or `"coding"`. Used only to tailor the setup-UX intro message.

### Outputs

- `merged_config`: object with the resolved keys (or empty if user declined and chose nothing).
- `source`: `"merged"` | `"session-only"` | `"user-declined"`.

### Steps

1. **Resolve paths**
   - `project_path = "<repo>/.superpowers/review-config.json"`
   - `global_path  = "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json"`

2. **Load both files** (per-file: produce `cfg` plus a `had_parse_error` flag)
   - Missing file → treat as `{}`, `had_parse_error = false`.
   - JSON parse failure (`jq .` fails) → emit warning, treat as `{}`, `had_parse_error = true`.
   - Non-object root (parses, but root is `null` / array / number / string / boolean — caught by an explicit `jq -e 'type == "object"'` guard) → emit warning, treat as `{}`, `had_parse_error = true`.
   - Drop unknown keys (warn). Drop typed-validation failures (warn).

3. **Bootstrap detection** — if both `project_cfg` and `global_cfg` are empty after Step 2:
   - Both `had_parse_error` true → emit notice `Both configs unreadable. Falling back to interactive setup.`, then go to Step 6 (Setup UX).
   - Any other empty combination (missing / valid `{}` / unknown-keys-only / one-side-only parse-error) → go to Step 6 silently.
   - If at least one of `project_cfg` or `global_cfg` has any valid keys → Step 4.

   `config-loading.md` Step 2/3 is canonical for this partition; if this summary diverges, the procedure file wins.

4. **Merge** per Section 6 to produce `merged_config`.

5. **Return** `{ merged_config, source: "merged" }`.

6. **First-time setup UX** (see Section 8). Returns `{ merged_config, source }` where source is `"merged"` (if saved) / `"session-only"` (if user chose not to persist) / `"user-declined"` (if user aborted).

### Setup helper: choose save location

Reusable subroutine called from Step 6 and from `coding-dispatch.md`'s coding-only setup path.

- Inputs: pending config delta (keys/values to write).
- Output: written path or `"session-only"`.
- Behavior:
  1. Present three choices (A: global, B: project, C: session-only).
  2. A or B → `mkdir -p` parent, JSON-merge with existing file content (if any), write.
  3. C → keep in memory only.

## 8. First-Time Setup UX

Triggered only when both configs are empty.

```
1. Scan skills/requesting-code-review/providers/ and run each detect command.
   Build the list of available providers.

2. Show intro based on caller_intent:
   - review:  "Code review provider is not configured. Pick one to use."
   - coding:  "Multi-AI coding dispatch is not configured. Pick a provider to set up."

3. User picks a provider from the available list.

4. **Build the full delta first.** Start with `delta = { "review_provider": "<picked>" }`.
   If `caller_intent == "coding"`, continue the in-memory dialogue (default_provider, optional category rules) and add `delta.coding = { "enabled": true, "default_provider": ..., "rules": [...] }` to the delta before any disk write.

5. Save-location prompt (3 choices via setup helper) — runs **once**, with the complete delta:
   A. User global (recommended) — uses ${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json
   B. This project only         — uses <repo>/.superpowers/review-config.json
   C. Don't save (session only) — remembers for this session only

6. Apply choice:
   - A → merge `delta` into the existing global file (Step 4 read-side merge rules; `delta` plays the role of the override side).
   - B → same as A but to the project path.
   - C → store the delta in memory; no file write.

7. Return { merged_config, source }.

**Note:** `config-loading.md` is the canonical source of truth for this flow. If this section diverges from `config-loading.md`, the procedure file wins.
```

### Cancellation handling

If the user cancels (e.g., declines provider list, Ctrl-C):

- caller `"review"` → return `source = "user-declined"`. `review-dispatch.md` reports an error and falls back to host AI review.
- caller `"coding"` → return `source = "user-declined"`. `coding-dispatch.md` proceeds to its existing Step 7 (host implementer fallback).

### Interaction with `coding-dispatch.md` existing setup

Three states:

| State | Handler |
|---|---|
| Both configs entirely missing | `config-loading.md` setup UX (provider + save location, optionally + coding section if caller is coding). |
| One config present but `coding` key absent (when `caller_intent="coding"`) | `coding-dispatch.md`'s existing coding-only setup flow, updated to use the **save-location helper** (3 choices) instead of unconditionally writing to project path. |
| Both configs present and `coding` defined | Merge and proceed; no setup UX. |

## 9. Error Handling

`config-loading.md` is the canonical source for these states; if this table diverges, the procedure file wins.

| Event | Location | Behavior | User-visible message |
|---|---|---|---|
| Project config JSON parse failure | config-loading Step 2 | Treat as `{}` with `had_parse_error = true`; continue with global | `⚠ Project config <path> failed to parse: <reason>; ignoring.` |
| Global config JSON parse failure | config-loading Step 2 | Treat as `{}` with `had_parse_error = true`; continue with project | `⚠ Global config <path> failed to parse: <reason>; ignoring.` |
| Non-object root (e.g. `null`, `[…]`, `42`, `"x"`) | config-loading Step 2 (root-type guard) | Treat as `{}` with `had_parse_error = true`; continue | `⚠ <role> config <path> has non-object root (got <jq type>); ignoring.` |
| Both files had a parse or root-type failure | config-loading Step 2 → Step 3 → Step 6 | Both treated as `{}`; bootstrap to setup UX with explicit notice | Both per-file warnings + `Both configs unreadable. Falling back to interactive setup.` |
| Both files empty after Step 2 (any non-loud combination: missing / valid `{}` / unknown-keys-only / one-side-only parse-error) | config-loading Step 2 → Step 3 → Step 6 | Both treated as `{}`; bootstrap to setup UX silently | Per-file warnings already shown in Step 2; no extra notice |
| Unknown key | config-loading Step 2 | Drop key; continue | `⚠ Unknown key '<dotted-path>' in <file>; ignored.` |
| Typed validation failure | config-loading Step 2 | Drop key; continue | `⚠ Invalid value for '<dotted-path>' in <file> (expected <type>); ignored.` |
| `review_provider` value lacks matching `providers/<name>.json` | review-dispatch.md Step 3 (existing) | Show "Unknown review provider"; reselect (session) | Existing |
| `coding.rules[].provider` lacks matching `providers/<name>.json` | coding-dispatch.md Step 3 (existing) | Show "Unknown coding provider"; reselect | Existing |
| Global directory does not exist (read) | config-loading Step 2 | Treat as missing file (no warning) | none |
| Save-time directory missing | Setup helper | `mkdir -p` | none |
| Save-time permission error | Setup helper | Show error; ask to pick another save location | `⚠ Could not write to <path>: <reason>. Choose another location.` |

## 10. Backward Compatibility

- **Existing project-only users**: behavior unchanged. With no global file present, `global_cfg = {}` and merge is identity over `project_cfg`. No new prompts. Unknown-key warnings will fire only against malformed-but-tolerated files; valid existing configs produce nothing new.
- **Existing setup-on-the-fly users (no project file, scan-and-select each session)**: bootstrap UX is now richer (asks save location). Choosing C (session-only) keeps the prior behavior exactly.
- No data migration required.

## 11. Documentation Updates

| File | Change |
|---|---|
| `README.md` | Replace single-config description with "global + project; both optional; key-level merge". Add example showing global defaults + project override. |
| `RELEASE-NOTES.md` | New entry for the version that ships this change. Brief: precedence, location, backward compat. |
| `skills/requesting-code-review/SKILL.md` | Add `config-loading.md` to the `See:` list. |
| `skills/requesting-code-review/review-dispatch.md` | Rewrite Step 2 to delegate to `config-loading.md`. |
| `skills/subagent-driven-development/SKILL.md` | Note that `.superpowers/review-config.json` reference now means "global or project". |
| `skills/subagent-driven-development/coding-dispatch.md` | Rewrite Step 1 to delegate to `config-loading.md`. Update internal coding-only setup to use the save-location helper. |
| `skills/writing-plans/SKILL.md` | Update line 109 reference from "the project uses multi-AI coding dispatch" to allow both locations. |

New files:

- `skills/requesting-code-review/config-loading.md` — content per Sections 6–9.
- `docs/superpowers/specs/2026-05-07-user-global-review-config-design.md` — this document.

## 12. Test Strategy

### Static checks (automatable)

- Reference integrity: `review-dispatch.md` and `coding-dispatch.md` must `grep -q "config-loading.md"`. `config-loading.md` must reference real `providers/*.json`.
- Sample JSON in `config-loading.md` and the spec must parse with `jq`.

### Behavior checks (manual scenarios; included in plan)

| # | Scenario | Expected |
|---|---|---|
| 1 | Project-only config | Identical to current behavior, no warnings |
| 2 | Global-only config | Global `review_provider` is used |
| 3 | Both, `review_provider` only in project | Project value wins |
| 4 | Both, `coding.rules` overrides only `backend` | `frontend` from global, `backend` from project |
| 5 | Project `"coding": { "rules": [] }` | Empty-array exception fires, global rules dropped |
| 6 | Project `"coding": { "enabled": false }` | Dispatcher skips to Fallback |
| 7 | Global JSON malformed | Warn; ignore global; project still works |
| 8 | Unknown key in global | Warn; key dropped; rest works |
| 9 | Both missing → setup UX | 3-choice prompt appears |
| 10 | Setup UX → "session only" | No file write; next session prompts again |
| 11 | `XDG_CONFIG_HOME=/tmp/xdg` set, file at `${XDG_CONFIG_HOME}/superpowers/review-config.json` | Read from XDG path |

CI integration is left to the implementation plan: reuse existing markdown lint / link-check workflows where present.

## 13. Out of Scope

- Schema version field.
- Encryption or restrictive permissions on the global file.
- XDG support for other `~/.config/superpowers/` consumers (worktrees, hooks).
- Team/shared config sources.

## 14. Open Questions

None at design time.
