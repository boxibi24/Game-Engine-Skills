# gamedev

A Claude Code plugin marketplace for game engine tooling.

**One plugin per engine, not per topic.** Each plugin is a container for
whatever skills that engine accumulates, so a new skill is a directory drop —
no renaming, no re-scoping, no marketplace edit. The marketplace itself only
changes when a new *engine* does.

They install and toggle independently, so an Unreal project does not carry
Unity's notes and vice versa.

| Plugin | Skills | What is in it today |
|---|---|---|
| [`unreal`](plugins/unreal) | 4 | Performance — stat baselines, bottleneck diagnosis, ranked optimizations, before/after screenshot comparison. Plus the editor-automation harness they sit on. |
| [`unity`](plugins/unity) | 2 | Editor control through the Unity CLI and the `com.unity.pipeline` bridge, and a routine for refreshing those notes when the pre-1.0 tool surface moves. |

Both are written out of real work rather than from the docs, so the emphasis is
on the traps — the failure modes that return exit code 0, the caps that are not
where you would look for them.

## Install

From an interactive `claude` terminal:

```
/plugin marketplace add boxibi24/Game-Engine-Skills
```

Then install whichever you want:

```
/plugin install unreal@gamedev
/plugin install unity@gamedev
```

The same thing without the interactive panel, e.g. over SSH or in a script:

```bash
claude plugin marketplace add boxibi24/Game-Engine-Skills
claude plugin install unreal@gamedev
```

**If you are editing skills**, point the marketplace at a local clone instead —
`claude plugin marketplace add /path/to/Game-Engine-Skills` — so changes are one
`claude plugin update` away rather than a commit-push-pull round trip. Both
sources cannot be registered at once; they collide on the marketplace name.

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
.claude-plugin/marketplace.json    one entry per engine
plugins/
  <engine>/
    .claude-plugin/plugin.json     generic: named for the engine, not its contents
    commands/                      optional
    skills/<skill>/SKILL.md        the specific part lives here
                  /references/     background pulled in on demand
                  /scripts/        runnable things
```

The engine plugin stays deliberately vague about what it holds. The skills carry
the specificity — that is the level where triggering is decided, and the level
that can be added to without disturbing anything else.

## Adding a skill

1. `mkdir plugins/<engine>/skills/<skill-name>` and write `SKILL.md` with
   `name` and `description` frontmatter. The description is the only part
   resident in context — it has to say *when to reach for this*, not just what
   it is, or the skill never fires.
2. Bulk goes in `references/` and is read on demand. Runnable things go in
   `scripts/`.
3. Commit, then `/plugin update <engine>@gamedev`.

Skills are discovered from the plugin directory, so nothing above the skill
needs editing. The plugin's own README lists what it currently holds; that is
documentation, not registration, and going stale costs nothing but clarity.

Adding a whole engine does mean a `marketplace.json` entry plus a
`plugins/<engine>/.claude-plugin/plugin.json`.

## Requirements

Stated per skill in each plugin's README rather than assumed plugin-wide.
Broadly: the bundled runners are Windows/PowerShell 5.1+, `unreal` was developed
against UE 5.6, and `unity` tracks two pre-1.0 components that move.

---

<https://github.com/boxibi24/Game-Engine-Skills>
