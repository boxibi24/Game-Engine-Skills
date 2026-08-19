# gamedev

A Claude Code plugin marketplace for game engine tooling. Two plugins, installed
and toggled independently, so an Unreal project does not carry Unity's notes and
vice versa.

| Plugin | Skills | What it covers |
|---|---|---|
| [`unreal`](plugins/unreal) | 4 | Stat baselines, bottleneck diagnosis, ranked optimizations, automated before/after screenshot comparison |
| [`unity`](plugins/unity) | 2 | Driving a project through the Unity CLI and the `com.unity.pipeline` Editor bridge, and keeping those notes current |

Both are written out of real work rather than from the docs, so the emphasis is
on the traps — the failure modes that return exit code 0, the caps that are not
where you would look for them.

## Install

From an interactive `claude` terminal:

```
/plugin marketplace add C:\Users\ASUS\claude-plugins
```

Then install whichever you want:

```
/plugin install unreal@gamedev
/plugin install unity@gamedev
```

`/plugin` toggles each one off again, which removes its skill descriptions from
context entirely. That is the whole reason these are plugins rather than
user-level skills: skills under `~/.claude/skills/` load in every session on
every project with no off switch, at roughly 170 tokens of always-resident
metadata each.

**Fallback**, if the marketplace route does not work:

```powershell
.\install.ps1 unreal              # copy that plugin's skills to ~/.claude/skills
.\install.ps1 unity -Uninstall    # take them out again
.\install.ps1                     # both plugins
```

Same caveat: that scope has no off switch. `-WhatIf` previews either direction.
For a middle ground, copy a plugin's `skills/*` into one project's
`.claude/skills/` so they load only there.

## Layout

```
.claude-plugin/marketplace.json    both plugins registered here
plugins/
  unreal/
    .claude-plugin/plugin.json
    commands/                      /ue-perf, /ue-shots
    skills/<skill>/SKILL.md
                  /references/     background the skill pulls in on demand
                  /scripts/        PowerShell + Python runners
  unity/
    .claude-plugin/plugin.json
    skills/<skill>/SKILL.md
                  /references/
```

## Adding a skill

1. `mkdir plugins/<plugin>/skills/<skill-name>` and write `SKILL.md` with
   `name` and `description` frontmatter. The description is the only part
   resident in context — it has to say *when to reach for this*, not just what
   it is, or the skill never fires.
2. Bulk goes in `references/` and is read on demand. Runnable things go in
   `scripts/`.
3. Commit, then `/plugin update <plugin>@gamedev`.

No marketplace edit is needed — skills are discovered from the plugin directory.
`marketplace.json` only changes when a whole plugin is added.

## Requirements

- Windows, PowerShell 5.1+ (the bundled runners; the written guidance is
  platform-independent)
- `unreal`: Unreal Engine 5.x, developed against 5.6, target project is a git
  repo
- `unity`: the `unity` CLI and `com.unity.pipeline`, both pre-1.0 and moving

## Backup

This repo has no remote. Four commits of it exist only on this disk.
