# Superpowers Multi

A fork of [obra/superpowers](https://github.com/obra/superpowers).

For the core concepts, workflow, skills library, and design philosophy, see the [upstream README](https://github.com/obra/superpowers#readme).

## What This Fork Adds

### Multi-AI Code Review Dispatch

Adds a configurable mechanism to dispatch code reviews to different AI providers (Codex CLI, Claude Code, etc.). The provider is selected via `review_provider` in either `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` (user global; recommended for personal defaults) or `.superpowers/review-config.json` (project; overrides global per-project). Both files are optional; when both exist, project keys override global by key — with `coding.rules` as the documented exception (merged by `category`; see below). Provider definitions live in `skills/requesting-code-review/providers/*.json`. Falls back to host-AI subagents when the configured provider is unavailable.

- **requesting-code-review** — reviews dispatch to the configured provider with automatic host-AI fallback
- **subagent-driven-development** — both stages of the two-stage review (spec compliance + code quality) and the final whole-implementation review go through the same dispatch. Final review uses `git merge-base` for stable diff boundaries
- **executing-plans** — batch review checkpoint every 3 tasks via `superpowers-multi:requesting-code-review`
- **Provider-agnostic templates** — `review-prompt.md` (code quality) and `spec-review-prompt.md` (spec compliance) replace the previous Codex/Claude-specific pair

### Multi-AI Coding Dispatch

Routes implementation tasks to AI providers by task category, so frontend and backend work can be handled by different providers. Configured via the `coding` key in the same `review-config.json` files described above (global at `${XDG_CONFIG_HOME:-~/.config}/superpowers/`, project at `<repo>/.superpowers/`). The `coding.rules` array merges by `category`: a project override of `backend` keeps the global `frontend` entry intact. An empty `rules: []` in the project config explicitly disables global rules for that project.

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

- **subagent-driven-development** — before the host implementer runs, each task is classified (`frontend` / `backend` / `fullstack`) via plan tag or AI auto-classification, then routed to the configured provider. Results are validated (file changes, non-empty output, no timeout) before passing into the existing two-stage review. On failure or when disabled, falls back to the existing host implementer
- **writing-plans** — plan tasks can include an optional `category:` field that overrides auto-classification
- **Provider-agnostic coding template** — `coding-prompt.md` is used by all providers; provider JSON files may add `invoke_coding` / `plugin_override_coding` for coding-specific CLI args
- **Backward compatible** — when the `coding` block is absent or `coding.enabled` is `false`, the existing implementer flow is unchanged. (`coding.enabled` defaults to `true` when omitted from a `coding` block, so configs that only set `default_provider` or `rules` remain active.)

## Prerequisites

Works out of the box with no additional dependencies. For enhanced multi-AI dispatch:

- **Codex Plugin (recommended):** When the [Codex plugin](https://github.com/openai/codex) for Claude Code is installed, reviews and coding tasks can be dispatched via Codex for an independent perspective. Without the plugin, both fall back to host-AI subagents (fully functional).
- **Optional global config** at `${XDG_CONFIG_HOME:-~/.config}/superpowers/review-config.json` (recommended for personal defaults across all projects) **and/or project config** at `.superpowers/review-config.json` (overrides global per-project). Both are optional. Without either, the system prompts to set one up the first time it runs and asks where to save (global / project / session-only).

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
