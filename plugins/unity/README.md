# unity

Unity tooling for Claude Code.

The plugin is scoped to the **engine**, not to a topic. It holds whatever Unity
skills turn out to be worth keeping; driving the Editor from outside it is
simply what is in it today. New skills drop into `skills/` without renaming or
re-scoping anything.

## Skills

### Editor control

| Skill | Use it for |
|---|---|
| `unity-cli` | Working in any Unity project. The three-front-doors model (CLI / Pipeline / MCP), the working loops, the safety rails and where they stop, and why `unity mcp` returns 0 tools. |
| `unity-cli-update` | Upgrading both halves and diffing the tool surface against the recorded baseline, then writing the findings back into these notes. |

## Install

```
/plugin marketplace add C:\Users\ASUS\claude-plugins
/plugin install unity@gamedev
```

See the [marketplace README](../../README.md) for the fallback install, the
reasoning behind the plugin scope, and how to add a skill.

## Requirements

Per skill, not plugin-wide — a new skill here is under no obligation to need any
of this. For the two editor-control skills:

- The `unity` CLI on `PATH` (baseline: `1.0.0-beta.3`)
- `com.unity.pipeline` installed in the project (baseline: `0.4.0-exp.1`), and
  an Editor open, for anything touching live scene state
- The CLI alone handles Hub/editor/project management, builds and tests with no
  Editor running

`com.unity.ai.assistant` is **not** required — Pipeline supersedes it.

## Keeping it current

`skills/unity-cli/references/baseline.json` records the versions, tool count and
tool list those notes were verified against. When a documented tool is missing
or rejects its parameters, that is the signal to run `unity-cli-update`.

Findings get written back **here**, in this repo — not into the installed copy
under `~/.claude/plugins/cache/`, which is replaced on every plugin update.
