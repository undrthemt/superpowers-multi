# Multi-AI Review Dispatch: Generic Provider-Based Code Review Routing

Enable users to designate any CLI-based AI as their code review provider, regardless of which AI harness they are working in. Replace the current hard-coded Codex-first routing with a provider-definition architecture that supports arbitrary CLI reviewers.

## Motivation

The current code review system (v5.0.8) is hard-coded to a Codex-first + Claude fallback pattern. This works well for Claude Code users with the Codex plugin, but creates two limitations:

1. **Users on other harnesses** (Codex CLI, Gemini CLI, Copilot CLI) cannot easily route reviews to a different AI for an independent perspective.
2. **Adding a new review AI** requires modifying skill files directly — there is no declarative way to register a new reviewer.

The goal is a provider-based dispatch mechanism where:
- The user specifies one external AI as their reviewer
- The fallback is always the host AI itself (no cascading fallback chains)
- Adding a new AI reviewer is a single JSON file, no skill code changes
- The existing Codex plugin path on Claude Code is preserved as a priority optimization

## Design Constraints

- **CLI only.** Every review provider must have a CLI tool. Direct API calls are out of scope.
- **Zero external dependencies.** No new tools, packages, or services required beyond the AI CLIs themselves.
- **Backward compatible.** Claude Code users with the Codex plugin see no change in behavior.
- **Initial scope.** Codex CLI and Claude Code CLI as the first two providers. Architecture supports adding Gemini CLI, Copilot CLI, and others via JSON files.

## Review Types

The dispatch mechanism serves two distinct review types used across multiple skills:

| Review Type | Purpose | Current Codex Template | Current Claude Template |
|-------------|---------|----------------------|------------------------|
| **Code quality** | Is the code well-built? (clean, tested, maintainable) | `requesting-code-review/codex-review-prompt.md` | `requesting-code-review/code-reviewer.md` |
| **Spec compliance** | Did the implementer build what was requested? | `subagent-driven-development/codex-spec-reviewer-prompt.md` | `subagent-driven-development/spec-reviewer-prompt.md` |

Each Codex template wraps its prompt content in a `codex:codex-rescue subagent:` dispatch block. Each Claude template wraps identical content in a `Task tool (general-purpose):` or `Task tool (superpowers-multi:code-reviewer):` block. The inner prompt content is provider-agnostic — only the dispatch wrapper differs.

The new architecture extracts the inner prompt content into provider-agnostic templates and moves all dispatch logic to `review-dispatch.md`.

## Architecture

### File Layout

```
.superpowers/
└── review-config.json                        # User setting (provider name)

skills/requesting-code-review/
├── SKILL.md                                  # Modified: references review-dispatch.md
├── review-dispatch.md                        # New: centralized dispatch logic
├── providers/
│   ├── codex.json                            # New: Codex provider definition
│   └── claude-code.json                      # New: Claude Code provider definition
├── review-prompt.md                          # Renamed from codex-review-prompt.md: provider-agnostic code quality template
└── code-reviewer.md                          # Removed: redundant; merged into review-prompt.md

skills/subagent-driven-development/
├── SKILL.md                                  # Modified: generic dispatch references
├── code-quality-reviewer-prompt.md           # Modified: replaced with dispatch reference
├── spec-review-prompt.md                     # Renamed from codex-spec-reviewer-prompt.md: provider-agnostic spec compliance template
└── spec-reviewer-prompt.md                   # Removed: merged into spec-review-prompt.md

skills/executing-plans/
└── SKILL.md                                  # Modified: update parenthetical description
```

### Provider Definition Schema

Each provider is a JSON file in `skills/requesting-code-review/providers/`.

```json
{
  "name": "<identifier>",
  "description": "<human-readable name>",
  "detect": "<shell command that succeeds if CLI is installed>",
  "invoke": {
    "command": "<CLI executable>",
    "args": ["<arg1>", "{{prompt_file}}", "<arg2>"],
    "input_method": "<'file' or 'stdin'>",
    "timeout_seconds": 300
  },
  "plugin_override": {
    "host": "<harness where plugin is available>",
    "subagent": "<subagent type to dispatch>"
  }
}
```

**Field reference:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | yes | — | Unique identifier, matches config file value |
| `description` | string | yes | — | Human-readable label |
| `detect` | string | yes | — | Shell command; exit 0 = CLI available |
| `invoke.command` | string | yes | — | CLI executable name |
| `invoke.args` | string[] | yes | — | Arguments; `{{prompt_file}}` replaced with temp file path |
| `invoke.input_method` | string | yes | — | `"file"`: prompt file path in args. `"stdin"`: pipe prompt to stdin |
| `invoke.timeout_seconds` | number | no | 300 | Max seconds to wait for CLI response. On timeout, treat as execution error and fall back |
| `plugin_override` | object or null | yes | — | When non-null, use subagent dispatch if running on the specified host |
| `plugin_override.host` | string | — | — | Harness identifier (e.g. `"claude-code"`) |
| `plugin_override.subagent` | string | — | — | Subagent type (e.g. `"codex:codex-rescue"`) |

### Initial Provider Definitions

**`providers/codex.json`:**

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
  "plugin_override": {
    "host": "claude-code",
    "subagent": "codex:codex-rescue"
  }
}
```

**`providers/claude-code.json`:**

```json
{
  "name": "claude-code",
  "description": "Anthropic Claude Code CLI",
  "detect": "which claude",
  "invoke": {
    "command": "claude",
    "args": ["-p", "--output-format", "text"],
    "input_method": "stdin",
    "timeout_seconds": 300
  },
  "plugin_override": null
}
```

### User Configuration

**File:** `.superpowers/review-config.json` (project root)

```json
{
  "review_provider": "codex"
}
```

- Single field: the provider name matching a `providers/*.json` file.
- Users decide whether to commit or gitignore this file.
- Natural language override at skill invocation time (e.g. "Review with Gemini") takes precedence over the config file for that invocation.

**When the config file does not exist:**

1. Scan `skills/requesting-code-review/providers/` for all `*.json` files.
2. For each, run the `detect` command to check availability.
3. Present the user with the list of available providers (name + description).
4. User selects one. This choice is remembered for the remainder of the current session (stored in the agent's working memory, not written to disk).
5. Each subsequent review dispatch in the same session uses this choice without re-asking.

### Prompt Template Refactoring

The current templates embed dispatch wrappers (`codex:codex-rescue subagent:` or `Task tool (...):`). The new architecture separates prompt content from dispatch.

**Code quality template** — `skills/requesting-code-review/review-prompt.md`:
- Renamed from `codex-review-prompt.md`
- Remove the `codex:codex-rescue subagent:` wrapper and frontmatter dispatch instructions
- Keep only the inner prompt content: review checklist, output format, critical rules
- The `{{DESCRIPTION}}`, `{{PLAN_OR_REQUIREMENTS}}`, `{{BASE_SHA}}`, `{{HEAD_SHA}}` placeholders remain

**Spec compliance template** — `skills/subagent-driven-development/spec-review-prompt.md`:
- Renamed from `codex-spec-reviewer-prompt.md`
- Remove the `codex:codex-rescue subagent:` wrapper and frontmatter dispatch instructions
- Keep only the inner prompt content: verification checklist, "Do Not Trust the Report" rules, output format
- The existing `spec-reviewer-prompt.md` (Claude fallback version) is removed — its inner content is identical; having one provider-agnostic template replaces both

**How dispatch uses these templates:**

| Dispatch Path | Prompt Construction |
|---------------|-------------------|
| **plugin_override (subagent)** | Read template → fill placeholders → append caller's additional checks (if any) → dispatch as subagent prompt via `plugin_override.subagent` type |
| **CLI** | Read template → fill placeholders → append caller's additional checks (if any) → write to temp file → invoke CLI with temp file |
| **Fallback (host AI)** | Read template → fill placeholders → append caller's additional checks (if any) → dispatch as `code-reviewer` subagent (code quality) or `general-purpose` subagent (spec compliance) |

The dispatch path determines HOW the prompt is delivered; the template determines WHAT the prompt says. These concerns are fully separated.

**Additional checks parameter:** Some callers (e.g. `subagent-driven-development`) define extra review criteria specific to their workflow. These are passed to `review-dispatch.md` as an `additional_checks` parameter — a markdown block appended to the template after placeholder filling but before dispatch. This allows workflow-specific review criteria without modifying the base templates.

### Dispatch Flow

The following flow is executed whenever a code review is requested, from any skill. The caller specifies the review type (`code-quality` or `spec-compliance`), which determines the template used.

```
Review requested (with review_type parameter)
  │
  ├─ Select template:
  │   ├─ code-quality → requesting-code-review/review-prompt.md
  │   └─ spec-compliance → subagent-driven-development/spec-review-prompt.md
  │
  ├─ Resolve provider:
  │   ├─ User explicitly named a provider? → use that provider
  │   └─ No → read .superpowers/review-config.json
  │            ├─ exists → use configured provider
  │            └─ missing → discover available providers, ask user, remember for session
  │
  ├─ Load providers/<name>.json
  │   ├─ File exists → continue
  │   └─ File not found → notify user: "Unknown review provider '<name>'.
  │                        Available providers: [list from providers/ directory]."
  │                        Ask user to choose. Remember for session.
  │
  ▼
Provider resolved
  │
  ├─ plugin_override is non-null AND current host matches plugin_override.host?
  │   ├─ YES → fill template placeholders
  │   │         → dispatch as subagent via plugin_override.subagent
  │   │         → validate response → if invalid, go to Fallback
  │   └─ NO  → continue to CLI dispatch
  │
  ▼
CLI dispatch
  │
  ├─ Run provider.detect → CLI installed?
  │   ├─ NO  → go to Fallback
  │   └─ YES → fill template placeholders
  │             → write filled prompt to temporary file
  │             │
  │             ├─ input_method == "file"?
  │             │   → replace {{prompt_file}} in args, execute command
  │             ├─ input_method == "stdin"?
  │             │   → pipe temp file contents to command stdin
  │             │
  │             ├─ Timeout: provider.invoke.timeout_seconds (default 300s)
  │             │   enforced via Bash timeout command prefix
  │             │   on timeout → treat as execution error → go to Fallback
  │             │
  │             ├─ Validate response (see Response Validation)
  │             │   ├─ valid → clean up temp file → return result
  │             │   └─ invalid or execution error → clean up temp file → go to Fallback
  │
  ▼
Fallback
  ├─ code-quality review → dispatch to code-reviewer subagent (or host AI equivalent)
  ├─ spec-compliance review → dispatch to general-purpose subagent (or host AI equivalent)
  └─ Notify user: "External review via <provider> failed: <reason>. Falling back to host review."
```

### Response Validation

Validation criteria depend on the review type:

**Code quality review** — response must contain all three sections:
- **Strengths** — what the code does well
- **Issues** — categorized as Critical / Important / Minor
- **Assessment** — merge verdict with reasoning

**Spec compliance review** — response must contain a verdict:
- `✅ Spec compliant` or `❌ Issues found: [list]`

A response missing required sections triggers fallback.

## Skill Modifications

### `skills/requesting-code-review/SKILL.md`

Replace the current Codex-first preflight/dispatch/fallback sections with:

```markdown
## Code Review Dispatch
Read `review-dispatch.md` in this skill directory and follow its dispatch instructions
with review_type = code-quality.
```

All other content (review checklist, output format, when to request reviews) remains unchanged.

### `skills/requesting-code-review/review-dispatch.md` (new)

Contains the full dispatch logic described in the Dispatch Flow section above. This is the single source of truth for how reviews are routed. Written as step-by-step instructions that the AI agent follows. Includes:
- Provider resolution (config file → user question → session memory)
- Plugin override check
- CLI detection, prompt preparation, invocation
- Response validation (type-aware)
- Fallback logic with user notification

### `skills/requesting-code-review/review-prompt.md` (renamed)

Renamed from `codex-review-prompt.md`. Changes:
- Remove lines 1-6 (Codex-specific header and dispatch instructions)
- Remove the `codex:codex-rescue subagent:` wrapper indentation
- Keep header as `# Code Quality Review Prompt Template`
- Add note: `This template is provider-agnostic. Dispatch is handled by review-dispatch.md.`
- Normalize placeholder names to match: `{PLAN_OR_REQUIREMENTS}` (not `{PLAN_REFERENCE}`)
- All inner content (review checklist, output format, critical rules, placeholders) preserved as-is

### `skills/requesting-code-review/code-reviewer.md` (removed)

This file is the Claude-specific version of the code quality review prompt. Its inner content (review checklist, output format, critical rules) is identical to `codex-review-prompt.md`, differing only in placeholder names (`{PLAN_REFERENCE}` vs `{PLAN_OR_REQUIREMENTS}`) and lacking the Codex dispatch wrapper. With the new provider-agnostic `review-prompt.md`, this file is redundant and should be deleted.

Note: `agents/code-reviewer.md` (the named subagent definition) is NOT removed — it defines the subagent type used for fallback dispatch on Claude Code.

### `skills/subagent-driven-development/SKILL.md`

This file has extensive Codex-specific content that needs updating:

**Opening description (line ~8):** Change "two-stage Codex-first review" to "two-stage external review"

**Graphviz diagram (lines ~52-83):** Replace Codex-specific node labels:
- `"Codex -> Claude fallback"` → `"External provider -> host fallback"`
- Node names referencing Codex → generic provider references

**Spec compliance review section:** Replace the inline Codex-first dispatch with:
```markdown
For spec compliance review dispatch, read `skills/requesting-code-review/review-dispatch.md`
and follow its instructions with review_type = spec-compliance.
Use template: `spec-review-prompt.md` in this skill directory.
```

**Code quality review section:** Replace the inline Codex-first dispatch with:
```markdown
For code quality review dispatch, read `skills/requesting-code-review/review-dispatch.md`
and follow its instructions with review_type = code-quality.
```

**Final Review section (lines ~203-216):** Replace the step-by-step Codex-first dispatch instructions with a reference to `review-dispatch.md` with `review_type = code-quality`.

**Prompt Templates section (lines ~122-125):** Update template references:
- `codex-spec-reviewer-prompt.md` → `spec-review-prompt.md`
- Remove references to `codex:codex-rescue` as the primary dispatch target
- Add reference to `review-dispatch.md` as the dispatch mechanism

**Integration section (line ~287):** Replace `codex:codex-rescue` dependency with `review-dispatch.md (configurable external review provider)`

### `skills/subagent-driven-development/spec-review-prompt.md` (renamed)

Renamed from `codex-spec-reviewer-prompt.md`. Changes:
- Remove lines 1-4 (Codex-specific header and dispatch instructions)
- Remove the `codex:codex-rescue subagent:` wrapper indentation
- Keep header as `# Spec Compliance Review Prompt Template`
- Add note: `This template is provider-agnostic. Dispatch is handled by review-dispatch.md.`
- All inner content (verification checklist, "Do Not Trust the Report" rules, output format) preserved as-is

### `skills/subagent-driven-development/spec-reviewer-prompt.md` (removed)

This file is the Claude-specific version of the spec compliance review prompt. Its inner content is identical to `codex-spec-reviewer-prompt.md`. With the new provider-agnostic `spec-review-prompt.md`, this file is redundant and should be deleted.

### `skills/subagent-driven-development/code-quality-reviewer-prompt.md`

Replace the entire file content with a dispatch reference:

```markdown
# Code Quality Reviewer Dispatch

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

For code quality review dispatch, read `skills/requesting-code-review/review-dispatch.md`
and follow its instructions with:
- review_type = code-quality
- additional_checks = the "Additional Checks" block below

## Additional Checks (subagent-driven-development specific)

In addition to standard code quality concerns, the reviewer should check:
- Does each file have one clear responsibility with a well-defined interface?
- Are units decomposed so they can be understood and tested independently?
- Is the implementation following the file structure from the plan?
- Did this implementation create new files that are already large, or significantly grow existing files?
```

The Codex-first / Claude fallback dispatch logic currently in this file is fully replaced by the generic dispatch in `review-dispatch.md`. The "Additional Checks" section is appended to the review prompt via the `additional_checks` parameter.

### `skills/executing-plans/SKILL.md`

Minimal change. This file already delegates review to `superpowers-multi:requesting-code-review`. The only change is in the Integration section:

**Before:** `superpowers-multi:requesting-code-review - Batch review every 3 tasks (Codex-first with Claude fallback)`

**After:** `superpowers-multi:requesting-code-review - Batch review every 3 tasks (configurable external provider with host fallback)`

### Files NOT Modified

| File | Reason |
|------|--------|
| `skills/receiving-code-review/SKILL.md` | Concerns receiving and acting on review feedback, not dispatching reviews |
| `agents/code-reviewer.md` | Named subagent definition for Claude Code; defines the subagent type used for fallback dispatch. Unchanged |

## Adding a New Provider

To add support for a new CLI reviewer (e.g. Gemini CLI):

1. Create `skills/requesting-code-review/providers/gemini.json`:
   ```json
   {
     "name": "gemini",
     "description": "Google Gemini CLI",
     "detect": "which gemini",
     "invoke": {
       "command": "gemini",
       "args": ["-p"],
       "input_method": "stdin",
       "timeout_seconds": 300
     },
     "plugin_override": null
   }
   ```
2. User sets `"review_provider": "gemini"` in `.superpowers/review-config.json`.
3. No skill file changes required.

## Change Summary

| Category | File | Action |
|----------|------|--------|
| Modified | `skills/requesting-code-review/SKILL.md` | Replace Codex-first routing with dispatch reference |
| Modified | `skills/subagent-driven-development/SKILL.md` | Replace all Codex-specific references with generic dispatch |
| Modified | `skills/subagent-driven-development/code-quality-reviewer-prompt.md` | Replace Codex/Claude dispatch with generic reference + additional_checks parameter |
| Modified | `skills/executing-plans/SKILL.md` | Update parenthetical description in Integration section |
| Renamed | `skills/requesting-code-review/codex-review-prompt.md` → `review-prompt.md` | Extract inner prompt, remove Codex wrapper, normalize placeholders |
| Renamed | `skills/subagent-driven-development/codex-spec-reviewer-prompt.md` → `spec-review-prompt.md` | Extract inner prompt, remove Codex wrapper |
| Removed | `skills/requesting-code-review/code-reviewer.md` | Redundant; merged into provider-agnostic `review-prompt.md` |
| Removed | `skills/subagent-driven-development/spec-reviewer-prompt.md` | Redundant; merged into provider-agnostic `spec-review-prompt.md` |
| New | `skills/requesting-code-review/review-dispatch.md` | Centralized dispatch logic with review_type and additional_checks parameters |
| New | `skills/requesting-code-review/providers/codex.json` | Codex provider definition |
| New | `skills/requesting-code-review/providers/claude-code.json` | Claude Code provider definition |
| Template | `.superpowers/review-config.json` | User configuration (not committed to plugin repo) |

**Total: 4 files modified, 2 files renamed, 2 files removed, 3 files created, 1 config template documented.**

## Test Plan

### Manual Verification

Each scenario should be tested in at least one session:

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1 | **Config-based Codex dispatch on Claude Code** | Set `review_provider: codex` in config; request code review | Uses `codex:codex-rescue` subagent (plugin_override path) |
| 2 | **Config-based Claude CLI dispatch on Codex** | Set `review_provider: claude-code`; request code review from Codex CLI | Runs `claude -p --output-format text` via Bash |
| 3 | **No config file, first review** | Delete config file; request code review | Agent scans providers, presents list, asks user to choose |
| 4 | **Session memory** | After scenario 3, request another review in same session | Uses previously chosen provider without re-asking |
| 5 | **Natural language override** | Config says `codex`; user says "Review with Claude Code" | Uses `claude-code` provider for this review only |
| 6 | **CLI not installed** | Set provider to one whose CLI is missing | Detect fails; falls back to host AI review with notification |
| 7 | **Invalid response** | Provider returns response missing Assessment section | Validation fails; falls back to host AI review |
| 8 | **Spec compliance review** | Run subagent-driven-development with external provider | Spec compliance review dispatches through review-dispatch.md |
| 9 | **Code quality review in SDD** | Complete spec compliance; code quality review triggers | Code quality review dispatches through review-dispatch.md |
| 10 | **Executing-plans batch review** | Execute plan with 3+ tasks | Review checkpoint at task 3 uses configured provider |
| 11 | **Backward compatibility** | Claude Code + Codex plugin + `review_provider: codex` | Identical behavior to current v5.0.8 |
