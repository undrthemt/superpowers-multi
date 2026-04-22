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
- Did this implementation create new files that are already large, or significantly grow existing files? (Don't flag pre-existing file sizes — focus on what this change contributed.)

**Code reviewer returns:** Strengths, Issues (Critical/Important/Minor), Assessment
