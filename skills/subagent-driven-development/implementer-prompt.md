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
