---
name: unity-cli-update
description: Refresh the Unity CLI and com.unity.pipeline package, then diff the tool surface against the recorded baseline and update the unity-cli skill notes. Use periodically (roughly monthly), whenever Unity tooling behaves differently than the unity-cli skill documents, when a documented tool or flag is missing or rejects its parameters, or when the user asks to update/check the Unity CLI, Unity MCP, or Pipeline tools.
---

# Update the Unity toolchain and re-read what changed

Both halves are pre-1.0 and ship breaking changes: the CLI is `beta`, `com.unity.pipeline` is `-exp` (experimental). Tools get renamed, parameters change, new domains appear. The `unity-cli` skill's notes go stale silently — nothing warns you until a call fails.

Recorded baseline lives beside the `unity-cli` skill, at
`references/baseline.json`.

**Write findings back to the plugin source repo, not to the copy you are reading
from.** Installing a plugin caches it under
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and that cache is
replaced wholesale on the next plugin update — edits made there are silently
lost. The source of truth is the marketplace working tree, by default
`~/claude-plugins/plugins/unity/skills/unity-cli/`. If it is not there, find it:

```bash
git -C ~/claude-plugins rev-parse --show-toplevel
```

Edit and commit there, then `/plugin update unity@gamedev` to pick the changes
back up.

Run this end to end. Report what changed; don't just say "updated".

## 1. Record the current state before touching anything

```bash
unity --version
unity pipeline list
```

Needs an Editor open with the project, or the tool diff in step 4 is impossible. If `Server Reachable` is `false`, fix that first — see the `unity-cli` skill.

## 2. Check for updates without installing

```bash
unity upgrade --check
unity upgrade --changelog
unity pipeline list-versions
```

Read the changelog before upgrading. If it names removed or renamed commands, expect the diff in step 4 to be large and expect existing scripts to break.

## 3. Upgrade

```bash
unity upgrade -y
unity pipeline upgrade
```

Pipeline's upgrade triggers a package resolve and domain reload — poll `unity cmd recompile_status` until `completed`, then confirm `unity status` reports `ready` again. If the CLI upgrade goes wrong, `unity upgrade --rollback` restores the previous binary.

Staying on a known-good pin is a legitimate choice for an experimental package. `unity pipeline install --package-version <v>` pins; skip the upgrade and note why.

## 4. Diff the tool surface against the baseline

```bash
unity list --json --no-banner > /tmp/tools-new.json
```

Compare `data.tools[].name` against `baseline.json`'s `tools` array. Report three buckets explicitly:

- **Added** — new capability; consider whether it replaces a workaround documented in `gotchas.md`
- **Removed** — anything referencing these in the skill notes is now wrong and must be fixed
- **Renamed** — usually shows up as one addition plus one removal with related names

Then spot-check parameters on tools the notes lean on most: `eval_file`, `create_gameobject`, `delete_gameobject`, `package_remove`, `recompile_status`, `console`, `run_tests`. A tool keeping its name while changing its parameters is the failure mode that silently breaks scripts.

## 5. Write the findings back

Update in the source repo's `plugins/unity/skills/unity-cli/`:

- `references/pipeline-tools.md` — regenerate from `unity list --json` (see the generator note at the bottom)
- `references/baseline.json` — new versions, count, tool list, and `verified` date
- `references/cli-commands.md` — if `unity --help` gained or lost commands
- `references/gotchas.md` — **delete entries the upgrade fixed.** A stale workaround is worse than no note; it sends the next session down a path that is no longer necessary.
- `SKILL.md` — the Baseline block at the bottom

Verify at least one real call still works before declaring success, e.g. `unity cmd editor_status`. Version numbers agreeing is not evidence the bridge works.

## 6. Report

State old → new versions for both components, the three diff buckets with actual tool names, which reference files you edited, and anything that broke. If nothing changed, say that plainly and update only the `verified` date.

## Regenerating the tool catalog

`references/pipeline-tools.md` is generated, not hand-written. Group the 140-odd tools by domain (Scene/GameObject, Prefab, Component, Asset, Script/Compile, Animation/Timeline, Material/Shader, Lighting/NavMesh/Occlusion, Play/Editor, Build/Test, Package, Settings), and for each emit the name, description, and required/optional parameters. Keep the conventions preamble — the `confirm`/`dry_run`, async-polling, `objectref`, and authoring-root rules are the load-bearing part of that file.
