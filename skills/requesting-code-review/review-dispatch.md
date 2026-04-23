# Review Dispatch Guide

Centralized dispatch logic for routing code reviews to external AI providers.
All review skills reference this file instead of containing their own dispatch logic.

## Parameters

The caller provides:
- **review_type**: `code-quality` or `spec-compliance`
- **additional_checks** (optional): markdown block appended to the prompt before dispatch
- **template_placeholders**: key-value pairs to fill in the template (e.g. DESCRIPTION, BASE_SHA, HEAD_SHA, PLAN_OR_REQUIREMENTS, WHAT_WAS_IMPLEMENTED)

## Step 1: Select Template

Based on review_type:
- `code-quality` → read `skills/requesting-code-review/review-prompt.md`
- `spec-compliance` → read `skills/subagent-driven-development/spec-review-prompt.md`

## Step 2: Resolve Provider

Check in this order (first match wins):

1. **User explicitly named a provider** in the current request (e.g. "review with gemini") → use that provider name
2. **Config file exists** at `.superpowers/review-config.json` → use the `review_provider` value
3. **No config, no explicit request** → discover and ask:
   a. Scan `skills/requesting-code-review/providers/` for all `*.json` files
   b. For each provider, run its `detect` command to check if the CLI is installed
   c. Present the user with available providers: name + description
   d. User selects one. Remember this choice for the rest of the session (do not write to disk)

## Step 3: Load Provider Definition

Read `skills/requesting-code-review/providers/<provider-name>.json`.

If the file does not exist: notify the user "Unknown review provider '<name>'. Available providers: [list names from providers/ directory]." Ask the user to choose from available providers. Remember the choice for the session.

## Step 4: Check Plugin Override

If `plugin_override` is non-null AND the current host AI matches `plugin_override.host`:

1. Fill template placeholders with caller-provided values
2. If `additional_checks` is provided, append it to the filled template
3. Dispatch as a subagent via `plugin_override.subagent` type with the filled prompt
4. Validate the response (see Step 7)
5. If validation passes → return the result (done)
6. If validation fails → continue to Step 6 (Fallback)

If `plugin_override` is null or host does not match → continue to Step 5.

## Step 5: CLI Dispatch

1. Run the provider's `detect` command via Bash
   - If it fails (non-zero exit) → go to Step 6 (Fallback)

2. Fill template placeholders with caller-provided values

3. If `additional_checks` is provided, append it to the filled template

4. Write the filled prompt to a temporary file (e.g. `/tmp/review-prompt-<timestamp>.md`)

5. Build and execute the CLI command:
   - If `input_method` is `"file"`: replace `{{prompt_file}}` in `args` with the temp file path, then run `timeout <timeout_seconds> <command> <args...>`
   - If `input_method` is `"stdin"`: run `timeout <timeout_seconds> <command> <args...> < <temp_file>`

6. Capture stdout as the review response

7. Clean up the temporary file

8. Validate the response (see Step 7)
   - If valid → return the result (done)
   - If invalid or execution error (including timeout) → go to Step 6 (Fallback)

## Step 6: Fallback

The external provider failed. Fall back to the host AI's own review capability:

1. Notify the user: "External review via <provider-name> failed: <reason>. Falling back to host review."

2. Dispatch based on review_type:
   - `code-quality` → dispatch a `code-reviewer` subagent (or host AI equivalent) with the filled template as the prompt
   - `spec-compliance` → dispatch a `general-purpose` subagent (or host AI equivalent) with the filled template as the prompt

## Step 7: Response Validation

Validation criteria depend on review_type:

**code-quality** — response must contain ALL of:
- A "Strengths" section
- An "Issues" section with severity categorization
- An "Assessment" section with a merge verdict

**spec-compliance** — response must contain one of:
- "✅ Spec compliant"
- "❌ Issues found:" followed by a list

If required sections are missing, the response is invalid.
