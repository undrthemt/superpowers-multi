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
