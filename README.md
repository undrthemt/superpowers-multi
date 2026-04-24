# Superpowers Multi

A fork of [obra/superpowers](https://github.com/obra/superpowers).

For the core concepts, workflow, skills library, and design philosophy, see the [upstream README](https://github.com/obra/superpowers#readme).

## What This Fork Adds

### Generic Provider-Based Multi-AI Review Dispatch

Adds a mechanism to dispatch code reviews to multiple AI providers.

- **requesting-code-review** — Reviews are dispatched via the `codex:codex-rescue` subagent (Codex plugin) as the primary reviewer, with automatic fallback to Claude subagents when Codex is unavailable
- **subagent-driven-development** — Both stages of the two-stage review (spec compliance + code quality) and the final review use Codex-first dispatch. The final review uses `git merge-base` for stable diff boundaries
- **executing-plans** — Batch review checkpoint every 3 tasks via `superpowers-multi:requesting-code-review`, applying Codex-first reviews
- **Review templates** — Added Codex-optimized `codex-review-prompt.md` (code quality) and `codex-spec-reviewer-prompt.md` (spec compliance). Existing Claude templates are retained as fallback

## Prerequisites

Works out of the box with no additional dependencies. For enhanced code review capabilities:

- **Codex Plugin (recommended):** When the [Codex plugin](https://github.com/openai/codex) for Claude Code is installed, code reviews are dispatched via Codex for an independent perspective. Without the plugin, reviews fall back to Claude subagents (fully functional).

## Installation

### Claude Code

Register the marketplace, then install the plugin:

```bash
/plugin marketplace add undrthemt/superpowers-multi
```

```bash
/plugin install superpowers-multi@superpowers-multi
```

### OpenAI Codex CLI

Open the plugin search interface:

```bash
/plugins
```

Search for Superpowers:

```bash
superpowers
```

Select `Install Plugin`.

### OpenAI Codex App

1. In the Codex app, click on Plugins in the sidebar.
2. You should see `Superpowers` in the Coding section.
3. Click the `+` next to Superpowers and follow the prompts.

### Cursor

In Cursor Agent chat:

```text
/add-plugin superpowers-multi
```

or search for "superpowers-multi" in the plugin marketplace.

### OpenCode

Tell OpenCode:

```
Fetch and follow instructions from https://raw.githubusercontent.com/undrthemt/superpowers-multi/refs/heads/main/.opencode/INSTALL.md
```

**Detailed docs:** [docs/README.opencode.md](docs/README.opencode.md)

### GitHub Copilot CLI

```bash
copilot plugin marketplace add undrthemt/superpowers-multi
copilot plugin install superpowers-multi@superpowers-multi
```

### Gemini CLI

```bash
gemini extensions install https://github.com/undrthemt/superpowers-multi
```

To update:

```bash
gemini extensions update superpowers
```

## Release Notes

See [RELEASE-NOTES.md](RELEASE-NOTES.md) for fork-specific release information.

## License

MIT License - see LICENSE file for details

## Links

- **Fork source**: [obra/superpowers](https://github.com/obra/superpowers)
- **Issues**: https://github.com/undrthemt/superpowers-multi/issues
- **Original community (Discord)**: [Join](https://discord.gg/35wsABTejz)
