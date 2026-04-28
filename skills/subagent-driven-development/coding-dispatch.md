# Coding Dispatch Guide

Centralized dispatch logic for routing implementation tasks to external AI providers.
Mirrors the review dispatch pattern (`skills/requesting-code-review/review-dispatch.md`).

## Parameters

The caller provides:
- **task_name**: Name of the task being implemented
- **task_description**: Full text of the task from the plan
- **task_category**: Classified category (frontend / backend / fullstack / etc.)
- **context**: Scene-setting, dependencies, working directory
- **plan_content**: Full plan text for reference

## Step 1: Check Coding Enabled

Read `.superpowers/review-config.json`.

**Config file does not exist OR `coding` key is absent** → prompt the user:

> "Multi-AI coding dispatch is available but not configured. To route implementation tasks to external AI providers (e.g., different providers for frontend vs backend), add a `coding` section to `.superpowers/review-config.json`. Would you like to set it up now?"

- If user **declines** → skip to Step 7 (Fallback). Remember this choice for the session — do not prompt again.
- If user **agrees** → guide them through setup:
  1. Ask which default provider to use (scan `skills/requesting-code-review/providers/` for available CLIs)
  2. Ask if they want category-specific rules (e.g., frontend → claude-code, backend → codex)
  3. Write the `coding` section to `.superpowers/review-config.json` (create file if needed). Target structure:
     ```json
     {
       "review_provider": "codex",
       "coding": {
         "enabled": true,
         "default_provider": "codex",
         "rules": [
           { "category": "frontend", "provider": "claude-code" },
           { "category": "backend", "provider": "codex" }
         ]
       }
     }
     ```
  4. Proceed to Step 2

**`coding.enabled` is explicitly `false`** → skip to Step 7 silently. The user has opted out.

**`coding.enabled` is `true`** → proceed to Step 2.

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
3. Dispatch as a subagent via the override's `subagent` type with the filled prompt
4. Validate the response (see Step 6)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 5 (CLI Dispatch)

If the resolved override is null or host does not match → continue to Step 5.

## Step 5: CLI Dispatch

Resolve invocation config: for each field (`command`, `args`, `input_method`, `timeout_seconds`), use `invoke_coding.<field>` if present; otherwise fall back to `invoke.<field>`. The `command` field is almost always inherited from `invoke` since the CLI executable is the same for review and coding.

1. Save current HEAD SHA as `pre_dispatch_sha` (if not already saved in Step 4): `git rev-parse HEAD`

2. Run the provider's `detect` command via Bash
   - If it fails (non-zero exit) → go to Step 7 (Fallback)

3. Fill `./coding-prompt.md` template placeholders with caller-provided values

4. Write the filled prompt to a temporary file (e.g. `/tmp/coding-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
   - If `input_method` is `"file"`: replace `{{prompt_file}}` in resolved `args` with the temp file path, then run `timeout <timeout_seconds> <command> <args...>`
   - If `input_method` is `"stdin"`: run `timeout <timeout_seconds> <command> <args...> < <temp_file>`

6. Capture stdout as the coding response

7. Clean up the temporary file

8. Validate the response (see Step 6)
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
- Use host AI `general-purpose` subagent with `./implementer-prompt.md` template.

If reached from Steps 5/6/Q&A (external provider failed):
1. Notify the user: "External coding via <provider-name> failed: <reason>. Falling back to host implementer."
2. Use host AI `general-purpose` subagent with `./implementer-prompt.md` template, passing all accumulated Q&A context (if any) in the Context section.
