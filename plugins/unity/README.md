# unity

Driving a Unity project from outside the Editor: the `unity` CLI, the
`com.unity.pipeline` Editor bridge, and the MCP server that wraps it. Reading
and mutating scenes, prefabs, components, materials, lighting and NavMesh;
running tests; triggering builds; reading the console; managing packages.

Both halves are pre-1.0 — the CLI is `beta`, Pipeline is `-exp` — so the notes
carry a recorded baseline and a routine for refreshing it when the tool surface
moves.

## Skills

| Skill | Use it for |
|---|---|
| `unity-cli` | Working in any Unity project. The three-front-doors model (CLI / Pipeline / MCP), the working loops, the safety rails and where they stop, and why `unity mcp` returns 0 tools. |
| `unity-cli-update` | Upgrading both halves and diffing the tool surface against the recorded baseline, then writing the findings back into these notes. |

## Install

```
/plugin marketplace add C:\Users\ASUS\claude-plugins
/plugin install unity@gamedev
```

See the [marketplace README](../../README.md) for the fallback install and the
reasoning behind the plugin scope.

## Requirements

- The `unity` CLI on `PATH` (baseline: `1.0.0-beta.3`)
- `com.unity.pipeline` installed in the project (baseline: `0.4.0-exp.1`), and
  an Editor open, for anything touching live scene state
- The CLI alone handles Hub/editor/project management, builds and tests with no
  Editor running

`com.unity.ai.assistant` is **not** required — Pipeline supersedes it.

## Keeping it current

`skills/unity-cli/references/baseline.json` records the versions, tool count and
tool list that these notes were verified against. When a documented tool is
missing or rejects its parameters, that is the signal to run `unity-cli-update`.

Findings get written back **here**, in this repo — not into the installed copy
under `~/.claude/plugins/cache/`, which is replaced on every plugin update.
