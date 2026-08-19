# unreal

Unreal Engine tooling for Claude Code.

The plugin is scoped to the **engine**, not to a topic. It holds whatever
Unreal skills turn out to be worth keeping; performance is simply what is in it
today. New skills drop into `skills/` without renaming or re-scoping anything.

## Skills

### Performance

| Skill | Use it for |
|---|---|
| `ue-perf-baseline` | Capturing a measurement that can actually be reproduced and compared. Includes frame-cap detection, which is the step people skip. |
| `ue-perf-analyze` | Working out which thread is the bottleneck and mapping stat rows to causes, with a settings reference. |
| `ue-perf-shots` | Automated before/after screenshot capture across two commits, plus a quantitative difference report. |

### Editor automation

| Skill | Use it for |
|---|---|
| `ue-editor-automation` | The harness: running Python inside UnrealEditor headlessly, and every failure mode that does not announce itself. Useful on its own, not only for perf work. |

## Commands

- `/ue-perf` — full performance workflow: baseline, diagnosis, ranked proposals
- `/ue-shots` — before/after screenshot capture and comparison

## Install

```
/plugin marketplace add boxibi24/Game-Engine-Skills
/plugin install unreal@gamedev
```

See the [marketplace README](../../README.md) for the fallback install, the
reasoning behind the plugin scope, and how to add a skill.

## Requirements

Per skill, not plugin-wide — a new skill here is under no obligation to need any
of this:

| Requires | Skills |
|---|---|
| Unreal Engine 5.x (developed against 5.6) | all |
| `PythonScriptPlugin` — enabled per-run via `-EnablePlugins`, no project change needed | `ue-editor-automation`, `ue-perf-shots` |
| The target project is a git repository | `ue-perf-shots` |
| Windows + PowerShell 5.1+ | the bundled runners under `ue-perf-shots/scripts/` only |

Engine and project paths are discovered from the `.uproject` and the registry,
so the scripts are not tied to a particular install location or project.

The written guidance is platform-independent; only the runners would need
porting off Windows.

## A caveat on the screenshots

`ue-perf-shots` drives the editor viewport, so it reflects editor rendering.
That is the right tool for comparing how a change affects the look. It is not a
substitute for measuring frame cost in a packaged build.
