# SDD: Enforce coding-dispatch routing — Design

**Status**: Draft
**Date**: 2026-05-08
**Author**: m-yamashita

## 1. Context

PR #6 (commit `28152d3`) introduced `skills/subagent-driven-development/coding-dispatch.md`, a 7-step procedure that routes implementation tasks to a configured external AI provider (Codex CLI, Claude Code, etc.) based on `coding.rules` in `review-config.json`. PR #8 added a user-global config layer for the same configuration.

The `coding.rules` configuration is intended to take effect whenever Subagent-Driven Development (SDD) dispatches an implementer for a task. In practice, it does not.

## 2. Problem Statement

When SDD is invoked for a task, the host AI bypasses `coding-dispatch.md` and dispatches `implementer-prompt.md` directly to a `general-purpose` subagent. The user's `coding.rules` setting is never consulted. The configured external AI provider (e.g., Codex for backend tasks) is never reached.

Symptoms observed:
- Setting `coding.default_provider: "codex"` has no effect — the host AI's general-purpose subagent runs every task.
- Setting `coding.enabled: false` also has no observable effect for the same reason — the path that would honor it (`coding-dispatch.md` Step 1) is never entered.

## 3. Root Cause

PR #6 added `coding-dispatch.md` and updated `SKILL.md` to describe the new routing flow, but left `implementer-prompt.md` unchanged as a self-contained "use general-purpose" template, and listed it in `SKILL.md` "Prompt Templates" alongside `coding-dispatch.md` as a sibling. Three structural issues followed:

1. **`implementer-prompt.md` is callable as a top-level entry point.** Its body says `Task tool (general-purpose):` with no awareness of routing. When a host AI follows this template, it dispatches general-purpose immediately and never consults `coding.rules`.
2. **`SKILL.md` "Prompt Templates" list shows the two as siblings.** Although the `implementer-prompt.md` line carries the parenthetical "(used as fallback when coding dispatch is disabled or fails)", the list structure invites a host AI to pick the simpler/familiar template directly.
3. **The flow diagram's "fallback to host AI" arrow is ambiguous.** It can be read as "use implementer when coding-dispatch falls back" *or* "use implementer as an alternative entry point". The diagram does not make `coding-dispatch.md` mandatory.

PR #6 added the description of routing without making routing the only path. Both entry points remained equally available, and the host AI selected the simpler one.

## 4. Goals

- Make `coding-dispatch.md` the only entry point for task implementation in SDD.
- Make the prompt template that runs when external providers are unavailable (the current `implementer-prompt.md`) clearly an internal template, not a top-level entry point.
- Honor the user's `coding.rules` configuration in every SDD task dispatch.
- Preserve backward compatibility for existing references and historical documents.

## 5. Non-Goals

- Changing `coding-dispatch.md`'s 7-step internal logic.
- Changing the `review-config.json` schema or the `coding.rules` merge semantics.
- Modifying `executing-plans` (verified to have no analogous issue — it does not dispatch subagents).
- Restructuring the SDD review path (`spec-review-prompt.md`, `code-quality-reviewer-prompt.md`).
- Adding any new wrapper procedure shared between SDD and `executing-plans`.

## 6. Approach Summary

A targeted structural fix at the SDD skill level:

1. **Rename** `skills/subagent-driven-development/implementer-prompt.md` to `coding-fallback-prompt.md`. The template body itself does not change — only the file name and a short clarifying header.
2. **Replace** the old `implementer-prompt.md` with a short "Moved" shim that points to the new file and warns against direct dispatch.
3. **Strengthen** `SKILL.md` so the host AI must always invoke `coding-dispatch.md` for each task: redraw the flow diagram, restructure the "Prompt Templates" list into "Entry points" and "Internal templates", and add an explicit imperative section.
4. **Update** `coding-dispatch.md` Step 7 references to the new filename.

## 7. File Layout Changes

### 7.1 New file: `coding-fallback-prompt.md`

Contains the existing `implementer-prompt.md` body verbatim (Task tool dispatch, Before You Begin, Self-Review, Report Format, etc.), preceded by a new header:

```markdown
# Coding Fallback Prompt Template

**Internal use only.** This template is invoked by `./coding-dispatch.md`
Step 7 (Fallback) when the configured external coding provider is
unavailable, disabled, or fails. It is not a top-level entry point —
the SDD skill must always go through `./coding-dispatch.md` for each
task to honor the user's `coding.rules` configuration.
```

### 7.2 Replaced file: `implementer-prompt.md` (shim)

Old body removed. Replaced entirely with:

```markdown
# Moved

This file was renamed to `coding-fallback-prompt.md` to clarify its role
as the fallback template inside `./coding-dispatch.md` Step 7. It is no
longer a top-level entry point.

**For SDD task implementation, always invoke `./coding-dispatch.md`** —
do not dispatch this template directly. The dispatcher will route the
task to the configured AI provider, falling back to the host implementer
template only when necessary.

See:
- `./coding-dispatch.md` — coding task routing logic
- `./coding-fallback-prompt.md` — the renamed template (internal)
```

### 7.3 Live references that must be updated

| File | Lines | Change |
|---|---|---|
| `skills/subagent-driven-development/SKILL.md` | flow diagram nodes & arrows; "Prompt Templates" list | See Section 8 |
| `skills/subagent-driven-development/coding-dispatch.md` | Step 7 (`./implementer-prompt.md` x2) | Replace with `./coding-fallback-prompt.md` |

### 7.4 Historical references that are intentionally NOT updated

The shim allows these to keep resolving (the file still exists, just with different content), so the historical record remains readable:

- `docs/superpowers/plans/2026-04-28-multi-ai-coding-dispatch.md`
- `docs/superpowers/plans/2026-04-22-codex-review-integration.md`
- `docs/superpowers/plans/2026-04-22-multi-ai-review-dispatch.md`
- `docs/superpowers/specs/2026-03-23-codex-app-compatibility-design.md`
- `RELEASE-NOTES.md` v5.0.9 / 5.0.8 entries

## 8. SKILL.md Changes (detail)

### 8.1 Flow diagram (current L44-94)

**Remove**: the standalone "Dispatch implementer subagent (./implementer-prompt.md)" node and its three direct-arrow edges from "Coding dispatch returns result or falls back to implementer".

**Replace** the binary diamond with a single-out diamond and a unified post-coding-dispatch arrow:

```dot
"Classify task category (plan tag → AI auto-classification)" [shape=box];
"Dispatch coding-dispatch.md (the only entry point)" [shape=box];
"Implementation result (provider OR internal fallback)" [shape=diamond];
"Implementation subagent asks questions?" [shape=diamond];
...

"Read plan, ..." -> "Classify task category ...";
"Classify task category ..." -> "Dispatch coding-dispatch.md (the only entry point)";
"Dispatch coding-dispatch.md ..." -> "Implementation result (provider OR internal fallback)";
"Implementation result ..." -> "Implementation subagent asks questions?";
...
```

Within `coding-dispatch.md`, provider selection vs. internal fallback is an implementation detail. The diagram does not need to expose it.

### 8.2 "Prompt Templates" section (current L145-152)

**Rename** the section heading from `## Prompt Templates` to `## Templates and dispatchers`.

**Restructure** the list into two sub-blocks:

```markdown
**Entry points (host AI invokes these directly):**
- `./coding-dispatch.md` — Coding task routing logic. **Always use this for task implementation.** Honors `coding.rules` configuration; falls back to the host implementer when external providers are unavailable.
- `./spec-review-prompt.md` — Spec compliance review template (provider-agnostic)
- `./code-quality-reviewer-prompt.md` — Code quality review dispatch reference (delegates to `review-dispatch.md`)
- `skills/requesting-code-review/review-dispatch.md` — Centralized dispatch logic for all review types

**Internal templates (invoked by `coding-dispatch.md`, not directly):**
- `./coding-prompt.md` — Provider-agnostic coding prompt (used by external CLI providers)
- `./coding-fallback-prompt.md` — Host AI subagent prompt (used by Step 7 fallback)
```

### 8.3 New section: "Task Implementation: Always Through coding-dispatch.md"

Inserted immediately after the flow diagram (around the current L95):

```markdown
## Task Implementation: Always Through coding-dispatch.md

For each task, **always** invoke `./coding-dispatch.md` with the
classified `task_category`. This is the only correct entry point for
task implementation in SDD.

**Do not** dispatch `./coding-fallback-prompt.md` (or its predecessor
`./implementer-prompt.md`) directly — bypassing `coding-dispatch.md`
ignores the user's `coding.rules` configuration and prevents the
configured external AI provider from being used.

The dispatcher itself decides whether to route to an external provider
or fall back to the host implementer; that decision belongs to
`coding-dispatch.md`, not to the SDD controller.
```

### 8.4 Existing sections — minor updates

- The "Coding dispatch" introductory paragraph (current L8-10): unchanged.
- The "Task Category Classification" section (current L111-125): unchanged in content; the closing line "Pass the classified category to `./coding-dispatch.md` as the `task_category` parameter." is already correct.

## 9. `coding-dispatch.md` Changes

Two mechanical replacements in Step 7 (current L180, L184):

| Line | Change |
|---|---|
| L180 | `Use host AI 'general-purpose' subagent with './implementer-prompt.md' template.` → `Use host AI 'general-purpose' subagent with './coding-fallback-prompt.md' template.` |
| L184 | `Use host AI 'general-purpose' subagent with './implementer-prompt.md' template, ...` → `Use host AI 'general-purpose' subagent with './coding-fallback-prompt.md' template, ...` |

No other logic in `coding-dispatch.md` changes.

## 10. Verification & Evaluation

### 10.1 Static checks (run as part of the implementation plan)

| Check | Command | Expected |
|---|---|---|
| New file exists | `test -f skills/subagent-driven-development/coding-fallback-prompt.md` | exit 0 |
| Shim exists with "Moved" header | `head -1 skills/subagent-driven-development/implementer-prompt.md \| grep -q '^# Moved$'` | exit 0 |
| Shim does NOT contain old prompt body | `grep -L 'Task tool (general-purpose):' skills/subagent-driven-development/implementer-prompt.md` | non-empty (file does not contain the string) |
| coding-dispatch.md updated | `grep -c 'coding-fallback-prompt.md' skills/subagent-driven-development/coding-dispatch.md` | ≥ 2 |
| coding-dispatch.md no longer references the old name | `grep -c 'implementer-prompt.md' skills/subagent-driven-development/coding-dispatch.md` | 0 |
| SKILL.md no longer references the old name | `grep -c 'implementer-prompt.md' skills/subagent-driven-development/SKILL.md` | 0 |
| SKILL.md has new section | `grep -c '## Task Implementation: Always Through coding-dispatch.md' skills/subagent-driven-development/SKILL.md` | 1 |
| SKILL.md has restructured templates section | `grep -c '## Templates and dispatchers' skills/subagent-driven-development/SKILL.md` | 1 |

### 10.2 Manual evaluation (real SDD sessions)

Per CLAUDE.md "Skill Changes Require Evaluation": skills are behavior-shaping content, and rewording may not actually achieve the desired host-AI behavior change. The implementation plan must include manual evaluation of representative scenarios.

| Scenario | Setup | Expected behavior | How to verify |
|---|---|---|---|
| **S1** Provider configured | `coding.default_provider: "codex"` in project config | Implementation tasks dispatched via Codex CLI (visible in session logs / commit author) | Run a fresh SDD session; observe whether the host AI calls `codex:codex-rescue` or invokes `coding-dispatch.md` then Codex. |
| **S2** Coding explicitly disabled | `coding.enabled: false` in project config | Tasks dispatched to host general-purpose subagent **via `coding-dispatch.md` Step 7** with `coding-fallback-prompt.md`, NOT `implementer-prompt.md` directly | Observe the file path referenced in dispatch / instructions. |
| **S3** No config | Both files absent | Setup UX prompts on first task; provider then used | Verify Setup UX appears; verify provider routing afterwards. |
| **S4** Category tag in plan | Plan task with `category: frontend`; `coding.rules` sets frontend → claude-code, backend → codex | The frontend-specific provider wins | Observe provider selected. |
| **S5** No tag, auto-classify | Plan task with no tag; same `coding.rules` as S4 | AI auto-classification → correct provider | Observe classification reasoning + provider selection. |

**Minimum gating**: S1 and S2 must pass before merge. S3-S5 are recommended for full confidence.

### 10.3 Eval evidence

The implementation plan's final verification task captures observed outcomes for each scenario. The PR description references the eval results.

## 11. Versioning

**v5.0.10 → v5.0.11 (patch bump)**.

Rationale:
- This is a bug fix to the routing introduced in v5.0.9. No new feature; no schema change.
- The internal file rename is mitigated by the shim, so existing references continue to resolve.
- Behavior change for users: their `coding.rules` configurations now actually take effect — a strict improvement in honoring documented behavior.

Manifest files to bump (5):
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.cursor-plugin/plugin.json`
- `gemini-extension.json`
- `package.json`

## 12. Backward Compatibility

- **Existing project configurations**: zero schema change. No migration required.
- **Existing references to `implementer-prompt.md`**: continue to resolve (shim still exists), but the body is now a redirect. Any consumer that reads the file will see the "Moved" notice rather than the prompt body. This is a safe-by-default behavior change: a misuse becomes visible rather than silently bypassing routing.
- **Historical plan/spec documents**: untouched. They remain accurate as historical records of what was planned at the time, even though the runtime structure has since evolved.

## 13. Out of Scope

- Removing the shim entirely. Done in a future minor (e.g., v5.1.0) once historical references are no longer relevant.
- Adding telemetry / runtime introspection of provider selection.
- Restructuring `executing-plans`.
- Changing the SDD review path.

## 14. Open Questions

- **Cache invalidation in long-lived sessions**: a host AI that has already loaded the v5.0.10 SKILL.md text into context may continue to read the old "Prompt Templates" list with `implementer-prompt.md` listed as a sibling, even after a marketplace update. This is a session-lifecycle issue, not a fix-correctness issue, and can only be resolved by ending the session and starting a fresh one. The plan and release notes must mention this explicitly.
- **Eval reporting format**: this fork follows a lightweight PR style (#4 / #6 / #7 / #8) and does not require formal eval evidence in the PR. Suggest including a short "Eval results" section in the PR description with the observed S1-S5 outcomes (pass/fail per scenario), even if not formally required.
