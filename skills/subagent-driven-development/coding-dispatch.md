# Coding Dispatch Guide

Centralized dispatch logic for routing implementation tasks to external AI providers.
Mirrors the review dispatch pattern (`skills/requesting-code-review/review-dispatch.md`).

> **Caller contract:** If you reached this file as a host AI executing
> SDD or another dispatch flow, you MUST follow the steps below from
> Step 1 onward. Do not skim and then call the `Agent` tool with what
> you remember — the routing logic (session state, disk checks,
> fallbacks) is load-bearing. Direct `Agent` dispatch silently bypasses
> the user's `coding.rules` configuration.

## Parameters

The caller provides:
- **task_name**: Name of the task being implemented
- **task_description**: Full text of the task from the plan
- **task_category**: Classified category (frontend / backend / fullstack / etc.)
- **context**: Scene-setting, dependencies, working directory
- **plan_content**: Full plan text for reference

## Step 1: Check Coding Enabled

### Session State

This dispatcher maintains two pieces of session-level state across dispatches in the same conversation:

- `session_coding_decline = true` — set when the user declined coding setup, or cancelled the bootstrap setup in `config-loading.md`; suppresses re-prompting.
- `session_coding_cache = { enabled, default_provider, rules }` — set when the user agreed to coding setup but chose `"session-only"` save (in case 2 of this dispatcher, or in `config-loading.md` Step 6); provides the in-memory coding block for subsequent dispatches.

`session_coding_decline` and `session_coding_cache` are mutually exclusive: setting one clears the other.

- `session_dispatch_log = []` — append-only list of all external dispatches in this session. Shared with `review-dispatch.md`. Each entry: `{ type: "coding" | "review", task_name: string, provider: string }`. Initialize to `[]` if not already set; never cleared within a session.

### Pre-load short-circuit (runs BEFORE calling config-loading)

**Disk authority principle:** session state (cache or decline) only short-circuits when the disk has nothing to say. If any config file exists on disk, defer to config-loading so disk edits are respected.

Run this bash check now:

```bash
test -e ".superpowers/review-config.json" \
  && echo "project_exists=yes" || echo "project_exists=no"
test -e "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \
  && echo "global_exists=yes" || echo "global_exists=no"
```

Set `project_exists` and `global_exists` from the output above.

If **neither** file exists (config-loading would otherwise enter Setup UX):
- `session_coding_cache` set → set `merged_config = { coding: <session_coding_cache> }`, skip the config-loading call, and proceed to Step 2.
- `session_coding_decline` is `true` → skip to Step 7 (Fallback) silently. The config-loading call is also skipped to avoid re-prompting via Setup UX.
- Neither set → fall through to "Load config" below.

If **at least one** file exists → fall through to "Load config" below regardless of session state. Disk is authoritative; session state acts only as a fallback inside Cases (case 2) when the loaded config has no coding block.

### Load config

Follow `skills/requesting-code-review/config-loading.md` with `caller_intent="coding"`. It returns `{ merged_config, source }`.

### Cases

Decide what to do based on `source` and the presence/value of `merged_config.coding`. Check in order; first match wins:

1. **`source == "user-declined"`** → set `session_coding_decline = true`, clear `session_coding_cache`, then skip to Step 7 (Fallback) silently. The user cancelled during config-loading's Setup UX; do not prompt again this session.

2. **`merged_config.coding` is absent** (at least one config exists on disk but lacks a `coding` block) → consult session state, then prompt only if neither is set:

   - If `session_coding_cache` is set → use it as the effective `merged_config.coding` and proceed to Step 2 silently. (No re-prompt; user already configured coding earlier in this session.)
   - Else if `session_coding_decline` is `true` → skip to Step 7 (Fallback) silently. (User already declined this session.)
   - Else → prompt the user:

     > "Multi-AI coding dispatch is available but not configured. To route implementation tasks to external AI providers (e.g., different providers for frontend vs backend), set up a `coding` section now. Would you like to?"

     - If user **declines** → set `session_coding_decline = true`, clear `session_coding_cache`, and skip to Step 7 (Fallback). Do not prompt again this session.
     - If user **agrees** → guide them through setup:
       a. Ask which default provider to use (scan `skills/requesting-code-review/providers/` for available CLIs).
       b. Ask if they want category-specific rules (e.g., frontend → claude-code, backend → codex).
       c. Build the coding delta from the user's answers:
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
       d. Call the **Save-Location Helper** in `skills/requesting-code-review/config-loading.md` with the delta. The helper returns either a written file path or the literal `"session-only"`.
       e. Set `merged_config.coding` to the delta's `coding` block in memory and clear `session_coding_decline`. Then:
          - If the helper returned a path → the next dispatch's call to config-loading will pick it up from disk; clear `session_coding_cache`.
          - If the helper returned `"session-only"` → set `session_coding_cache` to the delta's `coding` block so subsequent dispatches reuse it without re-prompting.

          Either way, proceed to Step 2 with the in-memory `coding` block.

3. **`merged_config.coding.enabled === false`** → skip to Step 7 silently. The user has opted out. (Disk wins over any session cache; do not clear session state — the user may revert the disk edit later.)

4. **Otherwise** (`merged_config.coding` is present and `enabled` is `true` or absent — treat absent as `true` for backward compatibility with configs that only set `default_provider` or `rules`) → before proceeding to Step 2, populate the session cache for next time: if `source == "session-only"` AND `session_coding_cache` is unset → set `session_coding_cache` to `merged_config.coding` and clear `session_coding_decline`. (No-op when `source == "merged"`, since disk is authoritative.) Then proceed to Step 2.

## Step 2: Resolve Provider

Check in this order (first match wins):

1. **Category rule match** → scan `coding.rules` for an entry where `category` equals `task_category`. Use that rule's `provider` value.
2. **Default provider** → use `coding.default_provider` if set.
3. **No config, no match** → discover and ask:
   a. Scan `skills/requesting-code-review/providers/` for all `*.json` files
   b. For each provider, run its `detect` command to check if the CLI is installed
   c. Present the user with available providers: name + description
   d. User selects one. Remember this choice for the rest of the session (do not write to disk)

## Step 3: Load Provider Definition

Read `skills/requesting-code-review/providers/<provider-name>.json`.

If the file does not exist: notify the user "Unknown coding provider '<name>'. Available providers: [list names from providers/ directory]." Ask the user to choose from available providers. Remember the choice for the session.

## Step 4: Check Plugin Override

Resolve the override: use `plugin_override_coding` if present; otherwise fall back to `plugin_override`.

If the resolved override is non-null AND the current host AI matches its `host` field:

1. Save current HEAD SHA as `pre_dispatch_sha`: `git rev-parse HEAD`
2. Fill `./coding-prompt.md` template placeholders with caller-provided values
3. Announce to the user: `[coding] <task_name> → <provider_name>` and append `{ type: "coding", task_name: task_name, provider: provider_name }` to `session_dispatch_log`.
4. Dispatch as a subagent via the override's `subagent` type with the filled prompt
5. Validate the response (see Step 6)
6. If validation passes → return the result (done)
7. If validation fails → continue to Step 5 (CLI Dispatch)

If the resolved override is null or host does not match → continue to Step 5.

## Step 5: CLI Dispatch

Resolve invocation config: for each field (`command`, `args`, `input_method`, `timeout_seconds`), use `invoke_coding.<field>` if present; otherwise fall back to `invoke.<field>`. The `command` field is almost always inherited from `invoke` since the CLI executable is the same for review and coding.

1. Save current HEAD SHA as `pre_dispatch_sha` (if not already saved in Step 4): `git rev-parse HEAD`

2. Run the provider's `detect` command via Bash
   - If it fails (non-zero exit) → go to Step 7 (Fallback)

3. Fill `./coding-prompt.md` template placeholders with caller-provided values

4. Write the filled prompt to a temporary file (e.g. `/tmp/coding-prompt-<timestamp>.md`)

5. Announce to the user: `[coding] <task_name> → <provider_name>` and append `{ type: "coding", task_name: task_name, provider: provider_name }` to `session_dispatch_log`.

6. Build and execute the CLI command:
   - If `input_method` is `"file"`: replace `{{prompt_file}}` in resolved `args` with the temp file path, then run `timeout <timeout_seconds> <command> <args...>`
   - If `input_method` is `"stdin"`: run `timeout <timeout_seconds> <command> <args...> < <temp_file>`

7. Capture stdout as the coding response

8. Clean up the temporary file

9. Validate the response (see Step 6)
   - If valid → return the result (done)
   - If invalid or execution error (including timeout) → check for Q&A (see Q&A Handling), then go to Step 7 (Fallback)

## Step 6: Result Validation

Validation uses the `pre_dispatch_sha` saved before dispatch.

- **File change check**: Check for both committed and uncommitted changes:
  1. `git diff --stat <pre_dispatch_sha>..HEAD` — detects committed changes since dispatch
  2. `git diff --stat` — detects uncommitted changes in the working tree
  At least one of these must show changed files
- **Empty response check**: CLI output must not be empty
- **Timeout check**: CLI must have exited normally (exit code 0, not killed by timeout)

If any check fails → proceed to Q&A Handling or Step 7 (Fallback).
If all pass → return the result to the caller.

## Q&A Handling

When result validation fails due to **no file changes** (but the CLI produced non-empty output), check if the external AI is asking questions:

**Detection:** If both `git diff --stat <pre_dispatch_sha>..HEAD` and `git diff --stat` are empty (no committed or uncommitted changes) AND the output contains question-like patterns (interrogative sentences, "I need to know", "please clarify", "could you provide", etc.), treat it as a Q&A response.

**Plugin override (subagent) dispatch:**
- Same as the existing NEEDS_CONTEXT flow — the subagent returns a question, the host AI answers, and the subagent is re-dispatched with the answer appended to context.
- Maximum 3 Q&A rounds before falling back to Step 7.

**CLI dispatch:**
- The host AI appends its answer to the `{CONTEXT}` section of the coding prompt and re-executes the CLI with the augmented prompt.
- Maximum 2 CLI re-executions (3 total attempts including the original).
- If still no file changes after the limit → fall back to Step 7 with all accumulated Q&A context.

**Rationale:** CLI round-trips are expensive (full process restart). The limit is lower than subagent Q&A because subagents maintain conversational state.

## Step 7: Fallback

If reached from Step 1 (coding not configured and user declined, or explicitly disabled):
- This is the existing SDD behavior, not a degraded path.
- Use host AI `general-purpose` subagent with `./coding-fallback-prompt.md` template.

If reached from Steps 5/6/Q&A (external provider failed):
1. Notify the user: "External coding via <provider-name> failed: <reason>. Falling back to host implementer."
2. Use host AI `general-purpose` subagent with `./coding-fallback-prompt.md` template, passing all accumulated Q&A context (if any) in the Context section.
