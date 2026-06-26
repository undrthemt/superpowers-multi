# Provider Visibility Design

> **Status:** Draft — approved for implementation

## 1. Problem

When the multi-AI dispatch system routes tasks to external providers (codex, claude-code, etc.), nothing is shown to the user. Dispatch occurs silently; only failures produce output ("External coding via \<provider\> failed…"). This makes it impossible to know:

- Which provider is handling a given task right now
- Which providers were used across the entire branch's work after the fact

## 2. Goals

1. **Dispatch-time announcement**: immediately before dispatching a coding or review task, emit a one-line notification showing the dispatch type, task description, and target provider.
2. **Post-work summary**: at the start of `finishing-a-development-branch`, display a full dispatch log (ordered) and an aggregate provider breakdown.

## 3. Non-Goals

- No changes to dispatch _logic_ or fallback behavior
- No file-based persistence (log lives in session memory only)
- No announcement for host-AI fallback dispatches (user already sees fallback message)
- No changes to config schema or provider JSON files

## 4. Session Variable: `session_dispatch_log`

A new session-level variable maintained by the host AI alongside the existing `session_coding_decline` and `session_coding_cache` variables.

```
session_dispatch_log: Array of {
  type:      "coding" | "review"
  task_name: string   // task_name param (coding) or {DESCRIPTION} param (review)
  provider:  string   // resolved provider name (from provider JSON's "name" field)
}
```

**Lifecycle:**
- Initialized to `[]` at session start (implicit; no special init step needed)
- Appended to by both `coding-dispatch.md` and `review-dispatch.md` before each dispatch
- Read once by `finishing-a-development-branch` to produce the summary
- Not cleared between tasks (cumulative across entire session)

## 5. Announcement Line

### Format

```
[<type>] <task_name_or_description> → <provider_name>
```

Examples:
```
[coding] Task 3: Add user authentication → codex
[review] Task 3: Add user authentication → codex
[coding] Task 1: DB schema migration → claude-code
[review] code-quality review of Task 1 → codex
```

### Placement in both dispatcher files

The announcement is added at **two points** in both `coding-dispatch.md` and `review-dispatch.md`:

- **Step 4 (Plugin Override):** Immediately before dispatching via the plugin override subagent (after the override is confirmed non-null and host matches, and after the prompt template is filled).
- **Step 5 (CLI Dispatch):** Immediately before executing the CLI command (after `detect` succeeds and the prompt file is written).

Only one of Step 4 or Step 5 executes per dispatch, so no duplicate announcements occur.

After announcing, append an entry to `session_dispatch_log`.

### What is NOT announced

- Fallback dispatches (Steps 6/7): the existing failure message is sufficient; no redundant log entry
- Config-loading and setup UX: not a dispatch

## 6. Post-Work Summary

### Trigger

`finishing-a-development-branch` SKILL.md, immediately after the current Step 1 (Verify Tests) and before the current Step 2 (Determine Base Branch). Becomes new Step 2; existing steps shift by one.

### Condition

Skip this step entirely if `session_dispatch_log` is empty (no external dispatches occurred this session).

### Output Format

```
## Dispatch Summary

| # | Type    | Task / Description                        | Provider     |
|---|---------|-------------------------------------------|--------------|
| 1 | coding  | Task 1: DB schema migration               | codex        |
| 2 | review  | Task 1: DB schema migration               | codex        |
| 3 | coding  | Task 2: Auth endpoints                    | claude-code  |
| 4 | review  | Task 2: Auth endpoints                    | codex        |

Provider breakdown:
  codex        ×3  (1 coding, 2 review)
  claude-code  ×1  (1 coding)
```

The breakdown lists each provider that appeared, with total count and a `(N coding, M review)` split. Ordered by first appearance in the log.

## 7. Files Changed

| File | Change |
|------|--------|
| `skills/subagent-driven-development/coding-dispatch.md` | Add `session_dispatch_log` to Session State; add announcement + append at Steps 4 and 5 |
| `skills/requesting-code-review/review-dispatch.md` | Add `session_dispatch_log` note + announcement + append at Steps 4 and 5 |
| `skills/finishing-a-development-branch/SKILL.md` | Add new Step 2 (Dispatch Summary), renumber existing steps 2→3, 3→4, 4→5, 5→6 |

Three files, no schema changes, no new files.

## 8. Worked Example

Session: SDD with codex for coding (backend category) and codex for review.

**During Task 1:**
```
[coding] Task 1: Add users table migration → codex
[subagent executes]
[review] Task 1: Add users table migration → codex
[subagent executes]
```

**During Task 2 (claude-code coding, codex review):**
```
[coding] Task 2: Auth middleware → claude-code
[subagent executes]
[review] Task 2: Auth middleware → codex
[subagent executes]
```

**At finishing-a-development-branch:**

Dispatch Summary table (4 rows) followed by:
```
Provider breakdown:
  codex        ×3  (1 coding, 2 review)
  claude-code  ×1  (1 coding)
```

Then the standard 4-option completion prompt.

## 9. Edge Cases

| Case | Behavior |
|------|----------|
| `session_dispatch_log` is empty | Skip Dispatch Summary entirely |
| Only one provider used for everything | Breakdown shows one line: `codex ×N (M coding, K review)` |
| Fallback triggered (provider failed) | No log entry; fallback message already visible |
| Q&A re-dispatch (coding) | Each re-dispatch that succeeds adds a new log entry (same task_name, same provider) |
| Review dispatched without SDD (standalone review skill) | Still appended to log; summary shown at finishing-a-development-branch |
