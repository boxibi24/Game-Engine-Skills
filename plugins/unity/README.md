# unity

Unity tooling for Claude Code.

The plugin is scoped to the **engine**, not to a topic. It holds whatever Unity
skills turn out to be worth keeping; driving a live Editor from outside it is
simply what is in it today. New skills drop into `skills/` without renaming or
re-scoping anything.

## Relationship to Unity's official skills

Unity publishes its own skill set at
[`Unity-Technologies/skills`](https://github.com/Unity-Technologies/skills),
including a `unity-cli` skill that documents the CLI as a whole. **Install it —
it is the better reference for most of the surface**, and these skills defer to
it rather than competing with it:

```bash
npx skills add Unity-Technologies/skills -g -a claude-code -s '*' -y
```

| Question | Skill |
|---|---|
| Install the CLI, an editor, a licence | Unity's `unity-cli` |
| Create a project, set up git, run CI builds | Unity's `unity-cli` |
| `unity test` exit codes, `mcp configure`, `unity pipeline install` | Unity's `unity-cli` |
| **What tools does a connected Editor expose, with what parameters** | `unity-pipeline` (here) |
| **Why a Pipeline call failed or behaved oddly** | `unity-pipeline` (here) |

Unity documents the *mechanism* and deliberately not the *catalog* — their own
note is that "the commands a connected Editor exposes are usable without a CLI
update". That gap, plus the field failures, is what this plugin is for.

## Skills

### Editor control

| Skill | Use it for |
|---|---|
| `unity-pipeline` | Working inside an open Unity project. The `com.unity.pipeline` bridge and its ~142 typed tools over `unity cmd` or MCP, the working loops, the safety rails and where they stop, and why `unity mcp` returns 0 tools. |
| `unity-pipeline-update` | Upgrading the CLI, the package **and** Unity's official skills, diffing the tool surface against the recorded baseline, and pruning anything Unity now documents better. |

> Renamed from `unity-cli` / `unity-cli-update` on 2026-08-24, after Unity
> shipped an official skill under the `unity-cli` name. The old names claimed
> territory these skills do not cover.

## Install

```
/plugin marketplace add boxibi24/Game-Engine-Skills
/plugin install unity@gamedev
```

See the [marketplace README](../../README.md) for the fallback install, the
reasoning behind the plugin scope, and how to add a skill.

## Requirements

Per skill, not plugin-wide — a new skill here is under no obligation to need any
of this. For the two editor-control skills:

- The `unity` CLI on `PATH` (baseline: `1.0.0-beta.6`)
- `com.unity.pipeline` installed in the project (baseline: `0.5.0-exp.1`), and
  an Editor open — everything here touches live Editor state
- Node, for `npx skills update` in `unity-pipeline-update`

Anything that runs without an Editor (Hub, editor installs, project management,
batch builds and tests) is Unity's `unity-cli` skill, not this plugin.

`com.unity.ai.assistant` is **not** required — Pipeline supersedes it.

## Keeping it current

`skills/unity-pipeline/references/baseline.json` records the versions, tool count
and tool list those notes were verified against. When a documented tool is
missing or rejects its parameters, that is the signal to run
`unity-pipeline-update`.

Findings get written back **here**, in this repo — not into the installed copy
under `~/.claude/plugins/cache/`, which is replaced on every plugin update.
