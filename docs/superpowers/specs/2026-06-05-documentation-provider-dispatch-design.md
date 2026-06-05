# Documentation Provider Dispatch — Design

**Date:** 2026-06-05
**Status:** Approved (brainstorming)
**Author:** masahiro@ichigo.com
**Related:** `docs/superpowers/specs/2026-04-22-multi-ai-review-dispatch-design.md`, `docs/superpowers/specs/2026-05-07-user-global-review-config-design.md`

## 1. Context

The existing dispatch system routes coding tasks and code reviews to configurable AI providers. Documentation-authoring tasks — plan file creation, Confluence pages, design documents — have no equivalent routing. They always run on the root AI regardless of user preference.

This design adds a `documentation_provider` config key that routes documentation-writing subagents to a user-selected provider, using the same config file, load procedure, and provider definitions already used for review and coding dispatch.

## 2. Goals & Non-Goals

### Goals

- Add `documentation_provider` to `review-config.json` (global and project).
- Create `documentation-dispatch.md` as the single dispatcher for all documentation-writing tasks.
- Integrate dispatch into `writing-plans/SKILL.md` as the primary entry point.
- Integrate dispatch into `subagent-driven-development/SKILL.md` for `documentation`-typed tasks.
- Fall back silently to the root AI when `documentation_provider` is not configured.
- Follow existing provider-definition files (`providers/*.json`) without modification.

### Non-Goals

- Per-doc-type routing rules (e.g. `spec → codex`, `plan → claude-code`). A single provider covers all documentation tasks. Category rules can be added in a future design.
- New provider definitions. Existing provider JSON files are used as-is.
- Modifying `review-dispatch.md` or `coding-dispatch.md`. Documentation dispatch is an independent file.
- Routing document-review tasks (spec compliance, code quality review). Those remain under `review-dispatch.md`.

## 3. Config Schema

`documentation_provider` is added as a top-level string key alongside the existing `review_provider`:

```json
{
  "review_provider": "codex",
  "documentation_provider": "codex",
  "coding": {
    "enabled": true,
    "default_provider": "codex",
    "rules": [
      { "category": "frontend", "provider": "claude-code" }
    ]
  }
}
```

`documentation_provider` is optional. When absent, all documentation tasks run on the root AI.

### Merge Semantics

Project config overrides global config at key level, identical to `review_provider`:

- `documentation_provider` in project config → use project value.
- `documentation_provider` only in global config → use global value.
- `documentation_provider` in neither → `undefined`; dispatcher falls back to root AI.

## 4. Changes to `config-loading.md`

### 4.1 Known-Key List

Add one row to the known-key table:

| Dotted path | Expected type |
|---|---|
| `documentation_provider` | string |

Validation: if the value is not a string, emit `⚠ Invalid value for 'documentation_provider' in <path> (expected string); ignored.` and exclude it.

### 4.2 `caller_intent` Values

`caller_intent` gains a third value: `"documentation"`. The only current use of `caller_intent` inside `config-loading.md` is the Setup UX intro message (Step 6.2). Add:

- `documentation`: `Documentation provider is not configured. Pick one to use.`

### 4.3 Setup UX — Step 6.4 Delta

**This is a change to existing behavior.** The current Step 6.4 always starts with `delta = { "review_provider": "<picked>" }` and then optionally extends it for `caller_intent == "coding"`. This delta initialization must become intent-aware:

| `caller_intent` | Initial delta |
|---|---|
| `"review"` | `{ "review_provider": "<picked>" }` (unchanged) |
| `"coding"` | `{ "review_provider": "<picked>" }` then extend with `coding` block (unchanged) |
| `"documentation"` | `{ "documentation_provider": "<picked>" }` |

When `caller_intent == "documentation"`, set only:

```json
delta = { "documentation_provider": "<picked>" }
```

No `review_provider` is set. No additional prompting is needed (no enabled flag, no rules).

### 4.4 Save-Location Helper — Merge Rules

The Save-Location Helper's merge logic (Step 3c) already applies a general "replace scalar keys present in delta, preserve others" rule. `documentation_provider` is a top-level scalar, so no change to the helper logic is needed. The new key is handled automatically.

### 4.5 Caller Integration Note

Add to the Caller Integration Notes section:

> `documentation-dispatch.md` Step 1 calls this procedure with `caller_intent="documentation"` and uses `merged_config.documentation_provider` for downstream provider resolution. If `source == "user-declined"` or `merged_config.documentation_provider` is undefined, the dispatcher falls back to root AI silently (no secondary prompt).

## 5. New File: `documentation-dispatch.md`

Location: `skills/requesting-code-review/documentation-dispatch.md`

Mirrors the structure of `review-dispatch.md`. All seven steps are present; differences from the review dispatcher are noted.

### Inputs

- **`prompt_content`**: the documentation prompt to send to the provider.
- **`doc_type`**: `"plan"` | `"design"` | `"documentation"` — used only in log/status messages.

### Step 1 — Load Config

Call `config-loading.md` with `caller_intent="documentation"`.

If `source == "user-declined"` → skip to Step 7 (root AI fallback).

### Step 2 — Resolve Provider

```
provider_name = merged_config.documentation_provider
```

If `provider_name` is undefined or empty → skip to Step 7 (root AI fallback, silently).

### Step 3 — Load Provider Definition

Load `skills/requesting-code-review/providers/<provider_name>.json`.

If the file does not exist → warn `⚠ Provider '<provider_name>' not found. Falling back to root AI.` → Step 7.

### Step 4 — Plugin Override Check

If the provider definition has a `plugin_override` field:

- If the current host matches `plugin_override.host` AND the plugin is available → dispatch via `plugin_override.subagent` with `prompt_content` as the prompt.
- On success → return output as the generated document.
- On failure → proceed to Step 5.

If no `plugin_override` field → proceed to Step 5.

### Step 5 — CLI Dispatch

Using the provider's `invoke` field (not `invoke_coding`):

1. Write `prompt_content` to a temp file.
2. Run the CLI command with the appropriate args.
3. Capture output.

On success (non-empty output, exit 0) → return output.

On failure (empty output, non-zero exit, timeout) → warn `⚠ Provider '<provider_name>' failed. Falling back to root AI.` → Step 7.

### Step 6 — Response Validation

Check that output is non-empty. If empty → warn and fall back to Step 7.

No structural validation (no required sections). Documentation output format varies by `doc_type`.

### Step 7 — Root AI Fallback

Run the documentation task directly on the root AI using `prompt_content`. This is the baseline behavior that existed before this feature.

If fallback was triggered by a provider failure (Steps 3–6), prefix the task with:

> `[documentation-dispatch: falling back to root AI after provider failure]`

If fallback was triggered by missing config (Step 2), proceed silently with no prefix.

## 6. Integration: `writing-plans/SKILL.md`

The plan-writing step currently generates plan files directly on the root AI. Change it to delegate through `documentation-dispatch.md`.

**Insertion point:** immediately before the step that writes the plan file content.

**Change:** replace direct plan generation with:

```
Invoke documentation-dispatch.md with:
  prompt_content = <assembled plan prompt>
  doc_type = "plan"
```

The returned content is then written to the plan file as before.

**No change to plan file location, naming conventions, or commit behavior.**

## 7. Integration: `subagent-driven-development/SKILL.md`

When SDD identifies that a task is primarily about writing a document (not code), it routes through `documentation-dispatch.md`.

**How documentation tasks are identified:** A task is treated as a documentation task when its description explicitly involves writing or creating a document artifact — examples: "Write a plan file for X", "Create a Confluence page for Y", "Draft the design document". Tasks that involve writing files that are code (`.js`, `.py`, `.ts`, etc.) are not documentation tasks regardless of description.

**Routing rule added to HARD-GATE section:**

```
Task type determination:
  - task produces code files → coding-dispatch.md
  - task produces document artifacts (plan, design doc, Confluence page) → documentation-dispatch.md
  - otherwise → host AI directly
```

The `doc_type` value passed to `documentation-dispatch.md` is inferred from the task description:
- "plan" for plan files
- "design" for design documents
- "documentation" for all other document types (Confluence pages, READMEs, etc.)

For tasks without a clear documentation purpose, default behavior (root AI) is unchanged.

## 8. Fallback Summary

| Condition | Behavior |
|---|---|
| `documentation_provider` not configured | Silent fallback to root AI |
| Provider JSON file not found | Warn + fallback to root AI |
| Plugin override available | Use subagent dispatch; on failure fall to CLI |
| CLI fails or times out | Warn + fallback to root AI |
| `user-declined` from config setup | Fallback to root AI |

## 9. Files Changed

| File | Change |
|---|---|
| `skills/requesting-code-review/documentation-dispatch.md` | New file |
| `skills/requesting-code-review/config-loading.md` | Add `documentation_provider` key, `"documentation"` intent |
| `skills/writing-plans/SKILL.md` | Delegate plan generation to documentation-dispatch |
| `skills/subagent-driven-development/SKILL.md` | Add `doc_type` routing to documentation-dispatch |
| `tests/claude-code/test-documentation-dispatch.sh` | New test file |

No changes to provider JSON files, `review-dispatch.md`, `coding-dispatch.md`, or config file schemas beyond the single new key.
