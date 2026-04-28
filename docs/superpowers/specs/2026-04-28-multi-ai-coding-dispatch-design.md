# Multi-AI Coding Dispatch: Provider-Based Implementation Task Routing

Enable users to designate different CLI-based AI providers for coding (implementation) tasks, with the ability to route frontend and backend work to different providers. Extends the existing multi-AI review dispatch pattern to cover the implementation phase of subagent-driven development.

## Motivation

The multi-AI review dispatch system (PR #4) successfully allows users to choose their code review provider. However, the implementation phase remains locked to the host AI's subagent system. This creates two limitations:

1. **No provider choice for coding.** Users cannot leverage a preferred AI for implementation tasks (e.g., using Codex for backend work while using Claude for frontend).
2. **No domain-specific routing.** Frontend and backend tasks have different characteristics, but the same AI handles both regardless of its strengths.

The goal is a provider-based coding dispatch mechanism where:
- Users configure AI providers per task category (frontend, backend, etc.) via rules
- Tasks are automatically classified by plan tags or AI judgment
- The fallback is always the host AI's existing implementer subagent flow
- Provider definitions are shared with the review system (no duplication)
- Coding results are validated before entering the existing review flow

## Design Constraints

- **CLI only.** Every coding provider must have a CLI tool. Direct API calls are out of scope.
- **Zero external dependencies.** No new tools, packages, or services required beyond the AI CLIs themselves.
- **Backward compatible.** When `coding.enabled` is `false` or absent, the existing SDD implementer flow is unchanged.
- **Shared providers.** Provider definition files (`providers/*.json`) are reused from the review system. An optional `invoke_coding` field allows coding-specific CLI arguments when needed.
- **Non-breaking for plans.** Existing plans without category tags continue to work via AI auto-classification.

## Provider Schema Extension

The existing provider JSON schema is extended with optional fields for coding tasks. Existing fields are unchanged; review dispatch continues to work as before.

### New Optional Fields

```json
{
  "name": "codex",
  "description": "OpenAI Codex CLI",
  "detect": "which codex",
  "invoke": {
    "command": "codex",
    "args": ["--quiet", "--prompt-file", "{{prompt_file}}"],
    "input_method": "file",
    "timeout_seconds": 300
  },
  "invoke_coding": {
    "args": ["--prompt-file", "{{prompt_file}}"],
    "input_method": "file",
    "timeout_seconds": 600
  },
  "plugin_override": {
    "host": "claude-code",
    "subagent": "codex:codex-rescue"
  },
  "plugin_override_coding": {
    "host": "claude-code",
    "subagent": "codex:codex-rescue"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `invoke_coding` | object | no | CLI invocation overrides for coding tasks. If absent, `invoke` is used |
| `invoke_coding.args` | array | no | Coding-specific CLI arguments (overrides `invoke.args`) |
| `invoke_coding.input_method` | string | no | Overrides `invoke.input_method` |
| `invoke_coding.timeout_seconds` | number | no | Overrides `invoke.timeout_seconds` (coding tasks typically need longer) |
| `plugin_override_coding` | object | no | Subagent dispatch override for coding tasks. If absent, `plugin_override` is used |
| `plugin_override_coding.host` | string | yes | Same as `plugin_override.host` |
| `plugin_override_coding.subagent` | string | yes | Subagent type for coding (may differ from review subagent) |

**Resolution logic in coding-dispatch:** For each field, check `invoke_coding.*` first; if absent, fall back to `invoke.*`. Same for `plugin_override_coding` → `plugin_override`. This allows providers to share config when review and coding use the same invocation, and override only when they differ.

## Configuration

### Config File: `.superpowers/review-config.json`

Extends the existing review config file by adding a `coding` key. The file name is unchanged to maintain backward compatibility with the existing review dispatch system (`review-dispatch.md` already reads from this file).

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

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `review_provider` | string | no | Existing review provider setting (unchanged, flat for backward compatibility) |
| `coding.enabled` | boolean | no | Enable multi-AI coding dispatch. Default: `false` |
| `coding.default_provider` | string | no | Fallback provider when no rule matches. If unset, auto-detect available CLIs |
| `coding.rules` | array | no | Category-to-provider mapping rules |
| `coding.rules[].category` | string | yes | Task category to match (e.g., `frontend`, `backend`, `fullstack`) |
| `coding.rules[].provider` | string | yes | Provider name (must match a file in `providers/`) |

### Design Notes

- **`review_provider` remains flat (not nested):** The review dispatch system already reads this field. Nesting it under a `review` object would require modifying `review-dispatch.md`, which is out of scope. The asymmetry between `review_provider` (flat) and `coding` (nested) is intentional — the `coding` key is new and benefits from structure, while `review_provider` preserves backward compatibility.
- **Coding and review provider selection are fully independent:** A user can configure Codex for backend coding and Claude for review. The two systems resolve providers separately.
- The `coding` key being absent or `coding.enabled: false` preserves existing behavior entirely

## Task Category Classification

Each implementation task is classified into a category before provider routing. Classification uses a two-tier priority system.

### Priority 1: Plan Tags

When a plan specifies a `category:` field on a task, that value is used directly.

```markdown
## Task 3: Implement user profile page
category: frontend

### Description
Build the profile page component with...
```

### Priority 2: AI Auto-Classification

When no tag is present, the host AI classifies the task based on its content. Classification criteria are documented in `coding-dispatch.md`:

| Category | Signals |
|----------|---------|
| `frontend` | UI components, styling, layout, browser APIs, frontend routing, state management (Redux/Zustand/etc.) |
| `backend` | API endpoints, DB operations, authentication/authorization, business logic, server-side processing, migrations |
| `fullstack` | Task spans both frontend and backend layers |

The classified category is then matched against `coding.rules`:
- If a matching rule exists → use that rule's provider
- If no rule matches (including `fullstack` unless explicitly configured) → use `coding.default_provider`
- If `default_provider` is also unset → auto-detect available CLIs and ask user

Users can add a `fullstack` rule if they want specific routing for cross-layer tasks. If omitted, `fullstack` tasks fall through to the default provider. This is intentional — splitting a fullstack task into frontend and backend parts is the planner's job, not the dispatcher's.

## Architecture

### File Layout

```
.superpowers/
└── review-config.json                            # User setting (extended with coding key)

skills/requesting-code-review/
├── providers/                                    # Shared provider definitions (extended with optional coding fields)
│   ├── codex.json
│   └── claude-code.json

skills/subagent-driven-development/
├── SKILL.md                                      # Modified: task loop integrates coding dispatch
├── coding-dispatch.md                            # New: coding task routing logic
├── coding-prompt.md                              # New: provider-agnostic implementation template
├── implementer-prompt.md                         # Unchanged: used as fallback
├── spec-review-prompt.md                         # Unchanged
└── code-quality-reviewer-prompt.md               # Unchanged

skills/writing-plans/
└── SKILL.md                                      # Modified: category tag guidance added
```

### Coding Dispatch Flow (`coding-dispatch.md`)

The dispatch follows a 7-step flow, mirroring the review dispatch pattern.

#### Parameters (from caller)

| Parameter | Description |
|-----------|-------------|
| `task_name` | Task name |
| `task_description` | Full task text |
| `task_category` | Classified category (frontend / backend / fullstack / etc.) |
| `context` | Scene-setting, dependencies, working directory |
| `plan_content` | Full plan text for reference |

#### Step 1: Check Coding Enabled

- Read `.superpowers/review-config.json`
- If `coding.enabled` is `false` or absent → skip to Step 7 (fallback to host AI implementer)

#### Step 2: Resolve Provider

1. Match `task_category` against `coding.rules` → use matched rule's `provider`
2. No match → use `coding.default_provider`
3. No default → scan `skills/requesting-code-review/providers/`, run `detect` commands, ask user
4. Remember selection for session

#### Step 3: Load Provider Definition

- Read `skills/requesting-code-review/providers/<provider-name>.json`
- If file doesn't exist → notify user, ask to choose from available providers

#### Step 4: Check Plugin Override

- Check `plugin_override_coding` first; if absent, fall back to `plugin_override`
- If the resolved override is non-null AND host AI matches its `host` field:
  - Fill `coding-prompt.md` template with parameters
  - Dispatch via the override's `subagent` type
  - Proceed to Step 6 (validation)
  - If validation fails → continue to Step 5 (CLI dispatch)
- If the resolved override is null → proceed to Step 5

#### Step 5: CLI Dispatch

Resolve invocation config: use `invoke_coding` fields if present, otherwise fall back to `invoke` fields (per-field resolution: e.g., `invoke_coding.args` overrides `invoke.args`, but `invoke_coding.timeout_seconds` absent falls back to `invoke.timeout_seconds`).

1. Run provider's `detect` command → if fails, go to Step 7 (fallback)
2. Fill `coding-prompt.md` template with caller parameters
3. Write filled prompt to temp file (`/tmp/coding-prompt-<timestamp>.md`)
4. Build CLI command from resolved invocation config:
   - If `input_method` is `"file"`: replace `{{prompt_file}}` in args
   - If `input_method` is `"stdin"`: pipe temp file to stdin
5. Execute with timeout: `timeout <timeout_seconds> <command> <args...>`
6. Capture stdout
7. Clean up temp file
8. Proceed to Step 6

#### Step 6: Result Validation

Before dispatching (Step 4 or 5), save the current HEAD SHA as `pre_dispatch_sha`.

- **File change check**: Run `git diff --stat <pre_dispatch_sha>..HEAD` — at least one file must be changed (covers both committed and uncommitted changes by the external AI)
- **Empty response check**: CLI output must not be empty
- **Timeout check**: CLI must have exited normally (exit code 0 or non-timeout)
- If any check fails → Step 7 (fallback)
- If all pass → return result to caller (caller proceeds to existing review flow)

#### Step 7: Fallback

- If reached from Step 1 (coding disabled): use host AI `general-purpose` subagent with `implementer-prompt.md` — this is the existing SDD behavior, not a degraded path
- If reached from Step 5/6 (external provider failed): notify user of failure, then use host AI `general-purpose` subagent with `implementer-prompt.md`

### Dispatch Flow Diagram

```
Task execution starts
    │
    ▼
coding.enabled?
├─ NO → Fallback (host AI + implementer-prompt.md) ── existing SDD behavior
└─ YES
    │
    ▼
Category → Rules → Resolve provider
    │
    ▼
Load provider definition JSON
    │
    ▼
Plugin Override?
├─ YES → Subagent dispatch → Validate
│   ├─ OK → Return result
│   └─ NG → CLI dispatch (below)
└─ NO
    │
    ▼
CLI installed? (detect)
├─ NO → Fallback (notify + host AI)
└─ YES → CLI execution with timeout
    │
    ▼
Result validation (file changes, non-empty, no timeout)
├─ OK → Return result ──→ [Caller runs spec review → code quality review]
└─ NG → Fallback (notify + host AI)
```

## SDD Integration

### Modified Task Execution Loop

The per-task loop in `SKILL.md` changes from:

```
Extract task → Dispatch implementer → Q&A → Spec review → Code quality review → Next
```

To:

```
Extract task → Classify category → Coding dispatch → Q&A handling → Result validation → Spec review → Code quality review → Next
```

### Changes to SKILL.md

Insert before the implementer dispatch step:

1. **Category classification** — check plan tag, fallback to AI judgment
2. **Coding dispatch** — reference `coding-dispatch.md` for provider routing
3. **Q&A handling for external providers** — see "Q&A Handling for External Providers" section above for detailed mechanics (detection, response, limits per dispatch method)
4. **Result validation** — file change and basic sanity checks before entering review flow

### Q&A Handling for External Providers

When an external AI needs clarification instead of producing code, the handling differs by dispatch method:

**Plugin override (subagent) dispatch:**
- Same as existing `NEEDS_CONTEXT` flow in SDD — the subagent returns a question, the host AI answers, and the subagent is re-dispatched with the answer appended to context.
- Maximum 3 Q&A rounds before falling back to host AI implementer.

**CLI dispatch:**
- **Detection:** After CLI execution, the host AI inspects the output. If the result contains no file changes (`git diff --stat <pre_dispatch_sha>..HEAD` is empty) AND the output contains question-like patterns (interrogative sentences, "I need to know", "please clarify", etc.), it is treated as a Q&A response.
- **Response:** The host AI appends the answer to the `{CONTEXT}` section of the coding prompt and re-executes the CLI with the augmented prompt.
- **Limit:** Maximum 2 CLI re-executions (3 total attempts). If the CLI still produces no file changes after the limit, fall back to host AI implementer with all accumulated Q&A context.
- **Rationale:** CLI round-trips are expensive (full process restart). The limit is lower than subagent Q&A because subagents maintain state.

### Two-Stage Post-Coding Verification

After coding dispatch returns successfully:

1. **Result validation** (in `coding-dispatch.md` Step 6): file changes exist, non-empty output, no timeout
2. **Spec compliance review** (existing): external or host AI verifies implementation matches requirements
3. **Code quality review** (existing): external or host AI reviews code quality

This ensures external AI coding results receive the same review rigor as host AI implementations.

## Coding Prompt Template (`coding-prompt.md`)

Provider-agnostic template for implementation tasks sent to external AI CLIs.

```markdown
# Implementation Task: {TASK_NAME}

## Task
{TASK_DESCRIPTION}

## Context
{CONTEXT}

## Working Directory
{WORKING_DIR}

## Requirements
- Implement the task as described
- Follow existing code patterns and conventions
- Write tests for new functionality
- Commit changes with descriptive message

## Constraints
- Only modify files relevant to this task
- Do not refactor unrelated code
- If blocked or need clarification, report what you need

## Reference: Full Plan
{PLAN_CONTENT}
```

Differences from `implementer-prompt.md`:
- No self-review checklist or status codes (external CLIs cannot follow internal conventions)
- No escalation protocol (handled by `coding-dispatch.md` fallback instead)
- Simpler structure for broad CLI compatibility

## Changes to `writing-plans`

Add guidance to the planning skill for category tag annotation:

- Recommend (not require) adding `category:` field to each task
- Suggest making task descriptions explicit about which layer they target
- Provide examples of tagged tasks

Existing plans without tags continue to work via AI auto-classification.

## Files Changed Summary

### New Files

| File | Purpose |
|------|---------|
| `skills/subagent-driven-development/coding-dispatch.md` | Coding task routing logic (7-step flow) |
| `skills/subagent-driven-development/coding-prompt.md` | Provider-agnostic implementation prompt template |

### Modified Files

| File | Change |
|------|--------|
| `skills/subagent-driven-development/SKILL.md` | Add category classification + coding dispatch to task execution loop |
| `skills/writing-plans/SKILL.md` | Add category tag guidance for plan tasks |

### Optionally Modified Files

| File | Change |
|------|--------|
| `skills/requesting-code-review/providers/codex.json` | Add optional `invoke_coding` and `plugin_override_coding` fields |
| `skills/requesting-code-review/providers/claude-code.json` | Add optional `invoke_coding` field if needed |

These changes are optional — if the existing `invoke` args work for coding tasks, no modification is needed. The coding dispatch falls back to `invoke` when `invoke_coding` is absent.

### Unchanged Files

| File | Reason |
|------|--------|
| `skills/requesting-code-review/review-dispatch.md` | Review system is independent; config file name unchanged |
| `skills/subagent-driven-development/implementer-prompt.md` | Preserved for fallback |
| `skills/subagent-driven-development/spec-review-prompt.md` | Existing review flow unchanged |
| `skills/subagent-driven-development/code-quality-reviewer-prompt.md` | Existing review flow unchanged |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| External AI produces low-quality code | Two-stage review (spec + quality) catches issues before merge |
| Category misclassification routes to wrong provider | Fallback to `default_provider` ensures task still executes; plan tags override auto-classification |
| External CLI not installed or fails | Automatic fallback to host AI implementer |
| Q&A loop with external CLI is inefficient | Hard limit: 2 re-executions for CLI, 3 rounds for subagent. Accumulated Q&A context passed to fallback |
| Same provider used as both host and coding provider | Valid configuration — CLI runs as isolated process with fresh context. No special handling needed |
