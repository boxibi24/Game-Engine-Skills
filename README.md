# unreal-perf

Claude Code plugin for Unreal Engine performance work: capture a trustworthy
stat baseline, find what is actually costing frame time, propose ranked
optimizations, and prove the visual result with automated before/after
screenshots captured from pinned git commits.

Built out of a real optimization pass on a UE 5.6 competitive shooter, so the
guidance is mostly about the traps rather than the happy path.

## Skills

| Skill | Use it for |
|---|---|
| `ue-perf-baseline` | Capturing a measurement that can actually be reproduced and compared. Includes frame-cap detection, which is the step people skip. |
| `ue-perf-analyze` | Working out which thread is the bottleneck and mapping stat rows to causes, with a settings reference. |
| `ue-perf-shots` | Automated before/after screenshot capture across two commits, plus a quantitative difference report. |
| `ue-editor-automation` | The harness: running Python inside UnrealEditor headlessly, and every failure mode that does not announce itself. |

## Commands

- `/ue-perf` — full workflow: baseline, diagnosis, ranked proposals
- `/ue-shots` — before/after screenshot capture and comparison

## Install

As a plugin, from an interactive `claude` terminal:

```
/plugin marketplace add C:\Users\ASUS\claude-plugins\unreal-perf
/plugin install unreal-perf@unreal-perf
```

Or install the skills directly to the user-level skills directory, which makes
them global across every project without registering a marketplace:

```powershell
.\install.ps1
```

Re-run `install.ps1` after editing anything under `plugins/unreal-perf/skills/`
to sync the copies.

## Requirements

- Windows, PowerShell 5.1+
- Unreal Engine 5.x (developed against 5.6)
- The project is a git repository
- `PythonScriptPlugin` — enabled per-run via `-EnablePlugins`, no project change needed

Engine and project paths are discovered from the `.uproject` and the registry,
so the scripts are not tied to a particular install location or project.

## Scope

The bundled scripts are Windows/PowerShell. The knowledge in the skills applies
to any platform; only the runners would need porting.

Screenshot capture drives the editor viewport, which means it reflects editor
rendering. That is the right tool for comparing how a change affects the look.
It is not a substitute for measuring frame cost in a packaged build.
