# SDD/Review Dispatch HARD-GATE — Design

**Date:** 2026-05-13
**Status:** Approved (skipping clarifying questions per user instruction)
**Author:** dev@movefast.xyz
**Driver:** Real-world feedback file
`~/Desktop/superpowers-multi-dispatch-bypass-feedback-2026-05-13.md`
**Related:**
- `docs/superpowers/specs/2026-05-08-sdd-enforce-coding-dispatch-design.md` (v5.0.11 — the previous attempt at this fix)
- `docs/superpowers/specs/2026-05-07-user-global-review-config-design.md` (v5.0.10 — global/project config layering)

---

## 1. Context

### 1.1 The bypass that happened under v5.0.11

A user with `~/.config/superpowers/review-config.json` containing
`review_provider: codex` and `coding.rules` routing `backend → codex`
ran SDD on a Rails/Sidekiq backend task. The host Claude:

- Dispatched implementation as `Agent(subagent_type: 'general-purpose')` — **never read `coding-dispatch.md`**.
- Dispatched per-task spec and code review as `Agent(subagent_type: 'superpowers-multi:code-reviewer')` — **never read `spec-review-prompt.md`, `code-quality-reviewer-prompt.md`, or `review-dispatch.md`**.
- The user's configured provider (`codex`) was **silently bypassed for the entire branch**. The user only discovered this by asking afterwards.

### 1.2 Why v5.0.11's fix was insufficient

v5.0.11 added a "Task Implementation: Always Through coding-dispatch.md" section and renamed `implementer-prompt.md` → `coding-fallback-prompt.md` to make direct dispatch obviously wrong. But:

1. The instruction still reads as a *preference* the host AI can paraphrase ("conceptually delegate to dispatcher") rather than a *literal* `Read` action.
2. Nothing forces a config detection step *before* the host AI starts dispatching. By the time the host AI is in the dispatch loop, it has already committed to a wrong mental model.
3. The word "invoke" collides with the `Agent` tool's "dispatch" verb. The host AI under context pressure conflates them.
4. The brainstorming skill's `<HARD-GATE>` block is respected by the same model; SDD has no equivalent gate.

### 1.3 What the feedback recommends

Six changes, in expected-impact order. This design adopts five outright and partially adopts the sixth.

---

## 2. Goals & Non-Goals

### Goals

- Make it structurally hard for a host AI to dispatch implementation or review work without first reading the corresponding dispatch file.
- Force an explicit early branch point ("is multi-AI dispatch configured for this session?") before any task work begins.
- Apply the same defense to both SDD's coding dispatch *and* the review-dispatch path (the feedback shows both were bypassed).
- Keep the no-config path (no `review-config.json` anywhere) noise-free: no extra prompts, no extra reads.

### Non-Goals

- Changing the routing logic in `coding-dispatch.md` or `review-dispatch.md`. Those are correct; the problem is upstream of them.
- Adding new providers or rules schema fields.
- Restructuring `coding-dispatch.md` to be smaller. (Considered; rejected because the routing is genuinely complex and inlining it would create a drift surface.)
- Behavioral changes in `executing-plans` (the parallel-session skill). The feedback was specifically about same-session SDD; executing-plans uses a different control flow and is out of scope here.
- Domain-specific carve-outs. The fix has to work for any project the user runs SDD in.

---

## 3. Approach

The fix is layered: a hard, unmistakable gate at the *top* of each affected skill, a mandatory Step 0 that forces the host AI to detect configuration *before* it can rationalize away the dispatch path, and consistent re-wording downstream so the gate's instruction is reinforced everywhere the host AI looks.

### 3.1 Change A — HARD-GATE block at top of SKILL.md (both skills)

Insert a `<HARD-GATE>` immediately after the frontmatter and one-paragraph intro of:

- `skills/subagent-driven-development/SKILL.md`
- `skills/requesting-code-review/SKILL.md`

The SDD gate covers both coding and review dispatch (since SDD invokes both). The requesting-code-review gate covers review dispatch (for callers who use the review skill standalone, outside of SDD).

**SDD gate text (verbatim):**

```markdown
<HARD-GATE>
Do NOT use the Agent tool directly for task implementation, spec
review, or code-quality review while executing this skill.

For implementation: you MUST `Read` `./coding-dispatch.md` and follow
its logic. Direct `Agent` dispatch bypasses the user's `coding.rules`
configuration and silently ignores their chosen provider.

For review (spec or code quality): you MUST `Read`
`./spec-review-prompt.md` and `./code-quality-reviewer-prompt.md`,
which delegate to `skills/requesting-code-review/review-dispatch.md`.
Direct review-agent dispatch bypasses the user's `review_provider`
configuration.

These files exist in the same directory as this SKILL.md (or one
directory over for review-dispatch.md). If you have not read them yet
in this session, do so before any task work — every session, no
exceptions.
</HARD-GATE>
```

**Review-skill gate text (verbatim):**

```markdown
<HARD-GATE>
Do NOT use the Agent tool directly to dispatch a code review while
executing this skill.

You MUST `Read` `./review-dispatch.md` and follow its dispatch logic.
Direct `Agent` dispatch bypasses the user's `review_provider`
configuration and silently ignores their chosen review provider.

If you have not read `./review-dispatch.md` yet in this session, do so
before requesting any review.
</HARD-GATE>
```

**Why this is the highest-impact change:** the feedback explicitly cites the brainstorming skill's HARD-GATE as "the one I respected because the gate was unmistakable." We are copying a pattern proven to work on the same model under the same conditions.

### 3.2 Change B — Mandatory Step 0 configuration detection

Insert a new "Step 0 — Configuration detection" subsection at the top of "The Process" in `subagent-driven-development/SKILL.md` and the top of "How to Request" in `requesting-code-review/SKILL.md`. Body (adapted from the feedback proposal, with concrete commands):

```markdown
## Step 0 — Configuration detection (MANDATORY before any task work)

Run a single check:

\`\`\`bash
ls -la .superpowers/review-config.json \\
       "${XDG_CONFIG_HOME:-$HOME/.config}/superpowers/review-config.json" \\
       2>/dev/null
\`\`\`

**If either file exists:**
  - Read the file(s).
  - Note `review_provider` and `coding.rules` values (whichever apply
    to this skill).
  - You MUST go through `coding-dispatch.md` (for implementation) and
    `review-dispatch.md` (for review) for the rest of this session.
    Direct `Agent` dispatch is forbidden.

**If neither file exists:**
  - There is no multi-AI configuration to honor. You MAY fall back to
    the host AI dispatch path described later in this skill (the same
    behavior SDD had before v5.0.10).
  - Even in this case, dispatch still goes through the
    coding-dispatch.md / review-dispatch.md flow — they handle the
    no-config case by falling through to the host implementer /
    reviewer. The HARD-GATE remains in force.
```

**Why this is the second-highest-impact change:** the feedback's key insight is that the host AI's drift happens *before* the dispatch loop starts. Step 0 makes config detection happen earlier than any drift can take hold, and the gate's "you MUST go through coding-dispatch.md" attaches to a state the host AI has just verified.

### 3.3 Change C — Language: "invoke" → "Read and follow"

The word "invoke" appears in SDD's templates section, the example workflow, and the existing "Always Through coding-dispatch.md" section. It collides with the `Agent` tool's "dispatch" verb in the host AI's mental model.

Replace the verb consistently:

| Before | After |
|---|---|
| "invoke `./coding-dispatch.md`" | "`Read` `./coding-dispatch.md` and execute its instructions" |
| "Dispatch via `./spec-review-prompt.md`" | "`Read` `./spec-review-prompt.md` and follow its dispatch logic" |
| "host AI invokes these directly" | "host AI `Read`s these directly and follows their instructions" |
| "Dispatch coding-dispatch.md" (flow diagram node) | "Read & follow coding-dispatch.md" |

This is a mechanical sweep through `subagent-driven-development/SKILL.md` and `requesting-code-review/SKILL.md`. No semantic change — only verb disambiguation.

### 3.4 Change D — Example workflow shows the reads

The current SDD example workflow narrates implementer / spec reviewer / code reviewer dispatches as if the host AI already knows how. Add the reads as the first lines:

```
You: I'm using Subagent-Driven Development to execute this plan.

[Step 0: Check for review-config.json — found ~/.config/superpowers/review-config.json]
[Read it: review_provider=codex, coding.rules: backend→codex]

[Read ./coding-dispatch.md once at session start]
[Read ./spec-review-prompt.md and ./code-quality-reviewer-prompt.md]
[Read ../requesting-code-review/review-dispatch.md]

[Read plan file once: docs/superpowers/plans/feature-plan.md]
[Extract all 5 tasks with full text and context]
[Create TodoWrite with all tasks]

Task 1: ...
```

The example becomes the canonical sequence. Host AIs imitate examples more reliably than they obey rules.

### 3.5 Change E — Mini decision tree inlined in SKILL.md (partial adoption of feedback #5)

Full inlining of `coding-dispatch.md` (11KB) into SKILL.md is rejected: it creates a drift surface where the SKILL.md copy and the canonical file disagree, and the routing logic involves session state that doesn't compress well.

Instead, inline a **20-line decision summary** in SKILL.md right after the HARD-GATE, with a "for full logic, see `./coding-dispatch.md`" pointer:

```markdown
## Dispatch decision summary (full logic in coding-dispatch.md)

For each task:

1. Look up `task_category` (from plan tag or AI classification).
2. Check `merged_config.coding.rules` for a matching `category` →
   use that rule's `provider`.
3. Otherwise use `merged_config.coding.default_provider`.
4. If no config matches → fall through to host AI implementer
   (`./coding-fallback-prompt.md`) via the dispatcher.

For each review (spec, then code quality):

1. Read `review-dispatch.md`.
2. It resolves provider from `merged_config.review_provider`.
3. If no provider matches → host AI fallback reviewer.

**Do not** short-circuit any of this by calling `Agent(...)` directly.
The dispatcher files own these decisions.
```

This gives the host AI enough context to verify it's on the right path without having to fully load the dispatcher file's content into its working set. If the summary turns out to drift, we delete it — `coding-dispatch.md` remains canonical.

### 3.6 Change F — TodoWrite template includes "load dispatch logic" sub-steps

The current example uses higher-level todos ("Dispatch implementation subagent") that encourage skipping the load step. New canonical per-task todo template:

```
- [ ] Classify task category
- [ ] Load dispatch logic (if not loaded this session):
      - Read ./coding-dispatch.md
      - Read ./spec-review-prompt.md
      - Read ./code-quality-reviewer-prompt.md
- [ ] Dispatch implementation via coding-dispatch.md
- [ ] Dispatch spec review via spec-review-prompt.md
- [ ] Dispatch code quality review via code-quality-reviewer-prompt.md
- [ ] Mark task complete
```

The "if not loaded this session" qualifier keeps the cost amortized: reads happen once per session, not once per task.

### 3.7 Change G (defense in depth) — Dispatcher files restate the contract

Add a one-paragraph block at the very top of both `coding-dispatch.md` and `review-dispatch.md`, immediately under the existing one-line intro:

```markdown
> **Caller contract:** If you reached this file as a host AI executing
> SDD or requesting-code-review, you MUST follow the steps below from
> Step 1 onward. Do not skim and then call the `Agent` tool with what
> you remember — the routing logic (session state, disk checks,
> fallbacks) is load-bearing.
```

This catches the case where a host AI partially reads the file and then thinks it can paraphrase. The block is short enough not to disturb existing readers.

---

## 4. Architecture & Components

The changes touch only documentation and skill-prose. No code, no providers, no schema.

### 4.1 Files modified

| File | Changes | Rough size delta |
|---|---|---|
| `skills/subagent-driven-development/SKILL.md` | Add HARD-GATE, Step 0, mini decision tree, reword "invoke", rewrite example workflow, new TodoWrite template | +60 lines, −5 lines |
| `skills/requesting-code-review/SKILL.md` | Add HARD-GATE, Step 0 (review-only variant), reword "invoke", small example workflow update | +35 lines, −2 lines |
| `skills/subagent-driven-development/coding-dispatch.md` | Add caller-contract block at top | +6 lines |
| `skills/requesting-code-review/review-dispatch.md` | Add caller-contract block at top | +6 lines |

### 4.2 Files NOT modified

- `coding-fallback-prompt.md`, `coding-prompt.md`, `spec-review-prompt.md`, `code-quality-reviewer-prompt.md`, `review-prompt.md` — these are templates dispatched into subagents and do not benefit from the gate.
- `config-loading.md` — already correct; the bypass is upstream of config loading, not within it.
- Provider JSON files — unaffected.
- `plugin.json` / version manifests — bumped in the implementation plan, not modified semantically.

### 4.3 Affected skills' user-visible behavior

- **No config present:** identical behavior to today. The Step 0 check returns "neither file exists" in one ls invocation, and execution proceeds through the dispatcher (which falls back to host AI). One added line of output: the `ls` result.
- **Config present, dispatch path already followed correctly:** identical behavior. The gate fires once at session start, the host AI reads the dispatcher files (one-time cost), and downstream is unchanged.
- **Config present, host AI would have bypassed (the bug today):** the gate forbids the bypass. The host AI reads the dispatcher files. Configuration is honored. This is the bug fix.

---

## 5. Validation Plan

### 5.1 Static checks

- Grep for `Agent(subagent_type:` inside `skills/subagent-driven-development/` and `skills/requesting-code-review/` — should appear only in commentary contexts, not as recommended usage.
- Grep for `invoke ./` and `invoke \`./` — should be zero hits in both SKILL.md files after the rewording sweep.
- Confirm both SKILL.md files contain a `<HARD-GATE>` block.
- Confirm both SKILL.md files contain a `## Step 0` section.
- Confirm both dispatcher files contain a `> **Caller contract:**` block.

### 5.2 Behavioral checks (manual eval matrix)

Adapted from the v5.0.11 fix's eval pattern (S1–S5):

| # | Scenario | Pass criterion |
|---|---|---|
| S1 | Cold session, project config exists with `coding.rules` for backend | Host AI reads coding-dispatch.md before first task and routes the backend task to the configured provider |
| S2 | Cold session, only global config exists with `review_provider: codex` | Host AI reads review-dispatch.md before first review and routes review to codex |
| S3 | Cold session, no config files exist | Host AI does Step 0, sees nothing, falls through to host fallback. No noise. |
| S4 | Mid-session config edit (user adds project config after task 1) | `coding-dispatch.md`'s "disk authority" logic picks up the new config on the next dispatch (already implemented in v5.0.10). This design does not require re-running Step 0 mid-session — the existing dispatcher behavior covers it. |
| S5 | Host AI is told "skip the dispatcher, just use Agent" by a malicious or buggy prompt | The HARD-GATE language refuses; host AI explicitly says it cannot bypass the dispatcher |

S1, S2, S3 are minimum gating. S4 and S5 are recommended but not gating (S4 catches an edge case rare in practice; S5 is a robustness test).

### 5.3 What we're NOT validating

- That every external CLI provider's `detect` command still works (unchanged code path).
- That `coding-dispatch.md`'s session-state caching is correct (unchanged code path).
- Performance — the added reads happen once per session and are bounded (<30 KB total).

---

## 6. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| HARD-GATE language is too strict and breaks the no-config path | Step 0 explicitly carves out the no-config case; gate language says "follow the dispatcher", and the dispatcher itself handles no-config by falling through |
| Mini decision tree (Change E) drifts from `coding-dispatch.md` | Keep it short (20 lines) and explicitly labeled "summary, see canonical file." If drift is observed in practice, delete the summary — the gate alone is enough |
| Adding 60+ lines to SKILL.md crosses some token budget for the host AI | The added content is concentrated near the top, where load-bearing context belongs. Total SKILL.md remains ~25 KB, well within capacity |
| Caller-contract block in dispatcher files gets stale | Block is generic ("follow Step 1 onward, don't skim and paraphrase"). No specific file paths or step numbers — drift-resistant |
| Some host AI still bypasses despite the gate | Documented as known-residual risk. The HARD-GATE is best-effort behavior shaping, not a runtime enforcement. A future-future fix could add a hook that blocks `Agent(...)` calls during SDD execution, but that's out of scope |

---

## 7. Out of Scope (future work)

- **Runtime enforcement via hook:** a `PreToolUse` hook on `Agent` that checks whether the host AI is mid-SDD and the subagent type is `general-purpose` or `code-reviewer` could *block* the bypass instead of just discouraging it. Mentioned in the feedback's "Caveat" — would defend against the silent-miss failure mode entirely. Out of scope here because: (a) it's a different layer of fix (hooks, not prose), (b) it requires coordination with the harness, (c) the gate-only approach should reduce the failure rate to a level where the hook is no longer urgent.
- **Telemetry:** logging when the dispatch path is followed vs. bypassed would tell us whether the gate is working. Requires a hook or wrapper. Out of scope.
- **`executing-plans` skill:** uses a parallel-session control flow with different bypass risk surface. Worth a follow-up review but out of scope here.
- **Domain-specific overrides** (e.g., "for Rails projects, always use codex"): the existing `coding.rules` is sufficient. No new schema needed.

---

## 8. Acceptance Criteria

A maintainer merging this work can verify success by:

1. Both `SKILL.md` files contain a HARD-GATE block at the top and a Step 0 section.
2. Both dispatcher files contain the caller-contract block.
3. Grep for `invoke ./` returns zero hits in either SKILL.md.
4. The example workflow in SDD's SKILL.md shows the `Read ./coding-dispatch.md` step explicitly.
5. The S1, S2, S3 manual eval scenarios pass in a fresh Claude Opus session (the same model that produced the bypass).
6. Version bumped (5.0.11 → 5.0.12) with a release-note entry.

---

## 9. Appendix: source of recommendations

This design is a direct response to the feedback file at
`~/Desktop/superpowers-multi-dispatch-bypass-feedback-2026-05-13.md`.
Mapping of feedback's six proposals onto this design's seven changes:

| Feedback # | Design change | Notes |
|---|---|---|
| 1 (HARD-GATE) | Change A | Adopted verbatim, then extended to the review skill |
| 2 (Step 0 config detection) | Change B | Adopted with concrete `ls` command |
| 3 (verb rewording) | Change C | Adopted as a sweep |
| 4 (example workflow shows reads) | Change D | Adopted |
| 5 (inline dispatch tree) | Change E | Partial — 20-line summary, not full inlining |
| 6 (TodoWrite template) | Change F | Adopted |
| — | Change G (caller-contract in dispatchers) | New, defense in depth |
