# Documentation Provider Dispatch — Design

**Date:** 2026-06-05
**Status:** Draft
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
- Integrate dispatch into `subagent-driven-development/SKILL.md` for documentation-typed tasks.
- Fall back silently to the root AI when `documentation_provider` is not configured.
- Follow existing provider-definition files (`providers/*.json`) without modification.

### Non-Goals

- Per-doc-type routing rules (e.g. `spec → codex`, `plan → claude-code`). A single provider covers all documentation tasks. Category rules can be added in a future design.
- New provider definitions. Existing provider JSON files are used as-is.
- Modifying `review-dispatch.md` or `coding-dispatch.md`. Documentation dispatch is an independent file.
- Routing document-review tasks (spec compliance, code quality review). Those remain under `review-dispatch.md`.
- Adding `invoke_documentation` fields to existing provider JSON files. Providers fall back to `invoke` for now; `invoke_documentation` support is deferred to a follow-up.
- Adding `plugin_override_documentation` fields to existing provider JSON files. The field is recognized by the dispatch logic (Step 4 of `documentation-dispatch.md`) but not present in any current provider definition. Providers that want documentation-specific plugin dispatch can add it in a future update.

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
- `documentation_provider` in neither → `undefined`; dispatcher falls back to root AI silently.

The Level 1 merge logic in `config-loading.md` Step 4 must include `documentation_provider` as a simple-replace scalar key (see Section 4.3).

## 4. Changes to `config-loading.md`

### 4.1 Known-Key List

Add one row to the known-key table:

| Dotted path | Expected type |
|---|---|
| `documentation_provider` | string |

Validation: if the value is not a string, emit `⚠ Invalid value for 'documentation_provider' in <path> (expected string); ignored.` and exclude it.

### 4.2 `caller_intent` Values

`caller_intent` gains a third value: `"documentation"`.

Update the Inputs block from:
> `caller_intent: "review" or "coding"`

To:
> `caller_intent: "review"`, `"coding"`, or `"documentation"`

The only current use of `caller_intent` inside `config-loading.md` is the Setup UX intro message (Step 6.2). Add:

- `documentation`: `Documentation provider is not configured. Pick one to use.`

**Important:** The Setup UX (Step 6) is triggered when both config files yield no valid keys — whether because they are absent, corrupt, or contain only unknown keys. Users who already have a config file with `review_provider` or `coding` set, but no `documentation_provider` key, will not enter the Setup UX — `config-loading.md` Step 3 detects valid keys and routes directly to Step 4 (Merge), returning `merged_config` without `documentation_provider`. In that case, `documentation-dispatch.md` Step 2 falls back to root AI silently. No interactive setup path exists for partially-configured users; this is intentional per Section 2's Goals.

### 4.3 Step 4 — Level 1 Merge Logic

The existing Level 1 merge logic handles `review_provider` as a simple-replace scalar. Add the same rule for `documentation_provider`:

> `documentation_provider`: simple replace. If `project_cfg.documentation_provider` is present, use it; else if `global_cfg.documentation_provider` is present, use it; else leave undefined.

This ensures the dispatcher receives the correct value from the merged config.

### 4.4 Setup UX — Step 6.4 Delta

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

**Exact replacement text for `config-loading.md` Step 6.4, first sentence:**

Replace:
> `Start with delta = { "review_provider": "<picked>" }.`

With:
> `Build the delta based on caller_intent:`
> `- If caller_intent == "review" or "coding": delta = { "review_provider": "<picked>" } (existing behavior; extend with the coding block if caller_intent == "coding" per existing logic).`
> `- If caller_intent == "documentation": delta = { "documentation_provider": "<picked>" } (no review_provider key).`

Step 6.3 (the provider selection flow: discover available providers, list them, user picks one) requires no structural modification — it is intent-agnostic. Only Step 6.2 (intro message) and Step 6.4 (delta initialization) are intent-specific and require the changes described in this section.

### 4.5 Save-Location Helper — Merge Rules

The Save-Location Helper's merge logic (Step 3c) already applies a general "replace scalar keys present in delta, preserve others" rule. `documentation_provider` is a top-level scalar, so no change to the helper logic is needed. The new key is handled automatically by the existing merge rules.

### 4.6 Caller Integration Note

Add to the Caller Integration Notes section:

> `documentation-dispatch.md` Step 1 calls this procedure with `caller_intent="documentation"` and uses `merged_config.documentation_provider` for downstream provider resolution. If `source == "user-declined"` or `merged_config.documentation_provider` is undefined, the dispatcher falls back to root AI silently (no secondary prompt).

## 5. New File: `documentation-dispatch.md`

Location: `skills/subagent-driven-development/documentation-dispatch.md`

**Rationale for location:** `coding-dispatch.md` lives in `skills/subagent-driven-development/` alongside the skill that invokes it. `documentation-dispatch.md` follows the same pattern — it is called by `writing-plans` and SDD, not by multiple unrelated callers. It is not placed in `skills/requesting-code-review/` because it has no relation to code review; that directory contains review-specific dispatch logic. Both dispatch files share the providers in `skills/requesting-code-review/providers/` regardless of where they live.

### Inputs

- **`prompt_content`**: the documentation prompt to send to the provider.
- **`doc_type`**: `"plan"` | `"design"` | `"documentation"` — used only for human-readable status and log messages. This parameter does not affect provider selection or dispatch behavior.

### Session State

Maintain two session-level variables, parallel to `session_coding_decline` and `session_coding_cache` in `coding-dispatch.md`:

- **`session_documentation_decline`** (boolean, default `false`): set to `true` when the user declines configuration during the Setup UX within this session. When `true`, skip to Step 7 silently without invoking config-loading.

- **`session_documentation_provider`** (string, default `undefined`): set when the user picks a provider and chooses "session only" (source == `"session-only"`). On subsequent dispatches within the same session, this value is used directly instead of re-entering config-loading, preventing repeated Setup UX prompts for session-only users.

### Step 1 — Load Config

**Pre-load disk check** (mirrors `coding-dispatch.md`'s disk-authority principle):

```
project_exists = test -e <repo>/.superpowers/review-config.json
global_exists  = test -e ${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json
```

**If neither file exists** (disk authority: session state governs):
- `session_documentation_decline == true` → skip to Step 7 silently.
- `session_documentation_provider` is set → assign `provider_name = session_documentation_provider`, skip to Step 3. Step 2's undefined check does not apply — Step 3's provider-not-found path handles any invalid cached value.
- Neither set → fall through to config-loading.

**If at least one file exists** → fall through to config-loading regardless of session state (disk authority: config file governs; mid-session disk edits are respected). Do not update or consult `session_documentation_provider` — discard any cached value for this dispatch and use only what `config-loading.md` returns.

Call `config-loading.md` with `caller_intent="documentation"`.

If `source == "user-declined"` → set `session_documentation_decline = true`, skip to Step 7.

If `source == "session-only"` AND `session_documentation_provider` is unset → set `session_documentation_provider = merged_config.documentation_provider`. (On the next dispatch, no config file will exist, so the pre-load disk check will short-circuit to the cached value above.)

### Step 2 — Resolve Provider

**This step is reached only when `config-loading.md` was called in Step 1 and returned a `merged_config`.** When `provider_name` was already assigned by the Step 1 pre-load short-circuit, execution continues from Step 3 — this step is skipped.

```
provider_name = merged_config.documentation_provider
```

If `provider_name` is undefined or empty → skip to Step 7 (root AI fallback, silently).

### Step 3 — Load Provider Definition

Load `skills/requesting-code-review/providers/<provider_name>.json`.

If the file does not exist → warn `⚠ Provider '<provider_name>' not found. Falling back to root AI.` → Step 7.

### Step 4 — Plugin Override Check

Resolve the override field using the same priority chain as `coding-dispatch.md`:

1. If `plugin_override_documentation` is present → use it.
2. Else if `plugin_override` is present → use it.
3. Else → no override; proceed to Step 5.

**Rationale:** Documentation is not a coding task, so `plugin_override_coding` is not used. Using `plugin_override` as the fallback means providers that only define a single override (e.g., Claude Code → Codex rescue) work out of the box. When providers want to customize documentation invocation specifically, they can add `plugin_override_documentation`.

If an override is resolved AND the current host matches `override.host` AND the plugin is available:
- Dispatch via `override.subagent` with `prompt_content` as the prompt.
- On success → return output.
- On failure → proceed to Step 5.

### Step 5 — CLI Dispatch

Resolve the invocation config using the same priority chain as plugin override:

1. If `invoke_documentation` is present in the provider definition → use it.
2. Else use `invoke`.

**Rationale:** `invoke_coding` is not used because documentation is a distinct dispatch type. `invoke` is the appropriate default for non-coding generative tasks. When a provider's `invoke` timeout (currently 300s for Codex) proves insufficient for long documentation tasks, providers can add an `invoke_documentation` entry with a higher timeout — this is deferred to a future provider update per Non-Goals.

Steps:
1. Write `prompt_content` to a temp file.
2. Run the CLI command with the resolved args.
3. Capture output.
4. Clean up the temporary file.

On exit 0 → proceed to Step 6 (Response Validation).

On non-zero exit or timeout → warn `⚠ Provider '<provider_name>' failed. Falling back to root AI.` → Step 7.

### Step 6 — Response Validation

Check that output is non-empty. If empty → warn `⚠ Provider '<provider_name>' returned empty output. Falling back to root AI.` → Step 7.

No structural validation (no required sections). Documentation output format varies by `doc_type`. If non-empty → return output.

### Step 7 — Root AI Fallback

Run the documentation task directly on the root AI using `prompt_content`. This is the baseline behavior that existed before this feature.

If fallback was triggered by a provider failure (Steps 3–6), prefix the task with:

> `[documentation-dispatch: falling back to root AI after provider failure]`

If fallback was triggered by missing config (Step 2) or session decline (Step 1), proceed silently with no prefix.

## 6. Integration: `writing-plans/SKILL.md`

The plan-writing skill currently generates plan content directly (inline) and saves it to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`. Change the plan generation step to delegate through `documentation-dispatch.md`.

**HARD-GATE required:** Add the following `<HARD-GATE>` block to `writing-plans/SKILL.md` at the integration point:

```
<HARD-GATE>
Do NOT generate plan body content directly while executing this skill.
For plan body generation: you MUST `Read`
`skills/subagent-driven-development/documentation-dispatch.md` and
follow its logic. Direct generation bypasses the user's
`documentation_provider` configuration and silently ignores their
chosen provider.
</HARD-GATE>
```

**Insertion point:** After the "File Structure" section of `writing-plans/SKILL.md` (where files and responsibilities are mapped out), before the skill proceeds to produce the task list. The File Structure analysis and Scope Check can be performed by the root AI. The documentation provider generates the plan body (tasks, steps, code blocks) starting from the Plan Document Header through to the end of the task list.

**Specifically:** After the AI has mapped out which files will be created or modified (File Structure), it assembles the full plan generation prompt incorporating:
- The spec or requirements
- The file structure analysis
- The task granularity guidelines from the skill
- The plan document header template

It then invokes `documentation-dispatch.md` with:
```
prompt_content = <assembled plan prompt including all of the above>
doc_type = "plan"
```

The returned content is written to the plan file. The self-review and Execution Handoff steps proceed as normal, run by the root AI.

**No change to plan file location (`docs/superpowers/plans/`), naming conventions, or commit behavior.**

## 7. Integration: `subagent-driven-development/SKILL.md`

### 7.1 HARD-GATE Update

The existing HARD-GATE in SDD currently reads:

```
Do NOT use the Agent tool directly for task implementation, spec
review, or code-quality review while executing this skill.

For implementation: you MUST `Read` `./coding-dispatch.md` and follow
its logic. ...

For review (spec or code quality): you MUST `Read`
`./spec-review-prompt.md` and `./code-quality-reviewer-prompt.md`,
which delegate to `../requesting-code-review/review-dispatch.md`. ...
```

Add a third paragraph to the HARD-GATE:

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

Also add `./documentation-dispatch.md` to the "See" reference list at the bottom of the skill file.

### 7.2 Task Routing Logic

When SDD identifies that a task is primarily about writing a document (not code), it routes through `documentation-dispatch.md`.

**How documentation tasks are identified:** A task is treated as a documentation task when its description explicitly involves writing or creating a document artifact — examples: "Write a plan file for X", "Create a Confluence page for Y", "Draft the design document". Tasks that involve writing files that are code (`.js`, `.py`, `.ts`, etc.) are not documentation tasks regardless of description.

**Routing rule:**

```
Task type determination:
  - task produces document artifacts (plan, design doc, Confluence page) → Read & follow ./documentation-dispatch.md
  - all other tasks (code files, configuration, tests, etc.) → Read & follow ./coding-dispatch.md (existing behavior)
```

In practice, all SDD tasks produce either document artifacts or code/config/test files. The "otherwise" escape hatch is removed — every task routes through one of the two dispatchers, consistent with the HARD-GATE's principle that direct Agent dispatch is never permitted.

The `doc_type` value passed to `documentation-dispatch.md` is inferred from the task description:
- `"plan"` for plan files
- `"design"` for design documents
- `"documentation"` for all other document types (Confluence pages, READMEs, etc.)

## 8. Fallback Summary

| Condition | Behavior |
|---|---|
| `documentation_provider` not configured | Silent fallback to root AI |
| Provider JSON file not found | Warn + fallback to root AI |
| Plugin override available | Use subagent dispatch; on failure fall to CLI |
| CLI fails or times out | Warn + fallback to root AI |
| `user-declined` from config setup | Set `session_documentation_decline`; fallback to root AI |
| `session_documentation_decline` is true | Silent fallback to root AI (no re-prompt) |

## 9. Files Changed

| File | Change |
|---|---|
| `skills/subagent-driven-development/documentation-dispatch.md` | New file |
| `skills/requesting-code-review/config-loading.md` | Add `documentation_provider` key; add `"documentation"` intent; add Level 1 merge rule |
| `skills/writing-plans/SKILL.md` | Delegate plan generation to documentation-dispatch |
| `skills/subagent-driven-development/SKILL.md` | Add HARD-GATE entry + doc task routing to documentation-dispatch |
| `tests/claude-code/test-documentation-dispatch.sh` | New test file |
| `tests/claude-code/run-skill-tests.sh` | Add `"test-documentation-dispatch.sh"` to the `tests` array (not `integration_tests`); all scenarios use mocked CLI commands per `test-helpers.sh` conventions |

No changes to provider JSON files, `review-dispatch.md`, `coding-dispatch.md`, or config file schemas beyond the single new key.

### Test Scenarios for `test-documentation-dispatch.sh`

The test file must follow the patterns established in `tests/claude-code/test-helpers.sh` and `run-skill-tests.sh`. Minimum scenarios:

1. **Happy path** — `documentation_provider` configured, provider CLI installed → dispatch succeeds, output returned, root AI not invoked.
2. **User declines Setup UX** — no config files present, user declines → `session_documentation_decline` set, root AI fallback on first invocation.
3. **Session-decline suppression** — second dispatch call in same session after decline → Step 7 reached silently without re-entering config-loading or showing Setup UX again.
4. **Provider not found** — `documentation_provider` set to an unknown name → warn + root AI fallback.
5. **Provider CLI fails** — `documentation_provider` configured but CLI exits non-zero → warn + root AI fallback.
6. **Provider returns empty output** — CLI exits 0 but output is empty → Step 6 warns + root AI fallback.
7. **Session-only cache** — user picks provider, chooses "session only" → `session_documentation_provider` set, second invocation (no config file on disk) skips Setup UX and uses cached provider.
