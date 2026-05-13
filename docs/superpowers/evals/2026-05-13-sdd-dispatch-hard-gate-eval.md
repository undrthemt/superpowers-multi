# SDD/Review Dispatch HARD-GATE — Manual Eval Log

**Design:** `docs/superpowers/specs/2026-05-13-sdd-dispatch-hard-gate-design.md`
**Plan:** `docs/superpowers/plans/2026-05-13-sdd-dispatch-hard-gate.md`
**Evaluator:** [name]
**Date:** [YYYY-MM-DD]
**Model:** Claude Opus 4.7

## S1 — Cold session, project config exists, backend task

**Setup:**
- Create `.superpowers/review-config.json` with `coding.rules: [{category: backend, provider: codex}]` in a test repo.
- Start a fresh Claude Code session.
- Hand it a 1-task plan with `category: backend`.

**Pass criterion:** Host AI reads `coding-dispatch.md` before first dispatch AND routes the task to codex (visible in tool calls).

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## S2 — Cold session, only global config, review skill standalone

**Setup:**
- Create `~/.config/superpowers/review-config.json` with `review_provider: codex`.
- Start a fresh Claude Code session, no project config.
- Ask host AI to "review the changes on this branch" (triggering requesting-code-review skill).

**Pass criterion:** Host AI reads `review-dispatch.md` before dispatch AND routes review to codex.

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## S3 — Cold session, no config files

**Setup:**
- Delete (or rename out of the way) both `.superpowers/review-config.json` and `~/.config/superpowers/review-config.json`.
- Start a fresh Claude Code session.
- Hand it a 1-task plan.

**Pass criterion:** Host AI does Step 0, sees no config, proceeds through `coding-dispatch.md` to the host AI fallback path. No prompts. No noise beyond a single `ls` line.

**Result:** [PASS / FAIL]
**Notes:** [observed behavior]

## Summary

- S1: [PASS / FAIL]
- S2: [PASS / FAIL]
- S3: [PASS / FAIL]

Gating: S1, S2, S3 all PASS → ready to merge. Any FAIL → return to design.
