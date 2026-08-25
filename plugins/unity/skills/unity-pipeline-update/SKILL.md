---
name: unity-pipeline-update
description: Refresh the Unity toolchain and re-sync the notes that describe it — upgrade the Unity CLI and com.unity.pipeline, diff the Pipeline tool surface against the recorded baseline, update Unity's official skills via `npx skills update`, and prune anything in the `unity-pipeline` skill that Unity's own `unity-cli` skill now documents better. Use periodically (roughly monthly), whenever Pipeline tooling behaves differently than `unity-pipeline` documents, when a documented tool or flag is missing or rejects its parameters, or when the user asks to update or check the Unity CLI, Unity MCP, Pipeline tools, or the Unity skills.
---

# Update the Unity toolchain and re-read what changed

Three things drift independently, and nothing warns you until a call fails:

| Moving part | Why it drifts | Updated by |
|---|---|---|
| `unity` CLI | pre-1.0 `beta` | `unity upgrade` |
| `com.unity.pipeline` | `-exp`, experimental | `unity pipeline upgrade` |
| Unity's official skills | published from `Unity-Technologies/skills` | `npx skills update` |

The first two change the tool surface this plugin documents. The third changes **what is worth documenting at all** — every time Unity's `unity-cli` skill grows a section, the matching notes here become duplication, and duplication that contradicts is worse than nothing.

Recorded baseline lives at `references/baseline.json`, beside the `unity-pipeline` skill.

**Write findings back to the plugin source repo, not to the copy you are reading from.** Installing a plugin caches it under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and that cache is replaced wholesale on the next plugin update — edits made there are silently lost. The source of truth is the marketplace working tree, by default `~/claude-plugins/plugins/unity/skills/unity-pipeline/`. If it is not there, find it:

```bash
git -C ~/claude-plugins rev-parse --show-toplevel
```

Edit and commit there, then `/plugin update unity@gamedev` to pick the changes back up.

Run this end to end. Report what changed; don't just say "updated".

## 1. Record the current state before touching anything

```bash
unity --version
unity pipeline list
```

Needs an Editor open with the project, or the tool diff in step 5 is impossible. If `Server Reachable` is `false`, fix that first — see the `unity-pipeline` skill.

## 2. Check for updates without installing

```bash
unity upgrade --check
unity upgrade --changelog
unity pipeline list-versions
```

Read the changelog before upgrading. If it names removed or renamed commands, expect the diff in step 5 to be large and expect existing scripts to break. Note that `--changelog` prints only the **target** version's notes — intermediate releases are not shown, so a multi-version jump hides changes. Capture `unity --help` before upgrading if you want a reliable command-surface diff.

## 3. Upgrade the CLI and the package

```bash
unity upgrade -y
unity pipeline upgrade
```

Pipeline's upgrade triggers a package resolve and domain reload — poll `unity cmd recompile_status` until `completed`, then confirm `unity status` reports `ready` again. If the CLI upgrade goes wrong, `unity upgrade --rollback` restores the previous binary.

Staying on a known-good pin is a legitimate choice for an experimental package. `unity pipeline install --package-version <v>` pins; skip the upgrade and note why.

## 4. Update Unity's official skills

Unity publishes its own skills at `Unity-Technologies/skills`, installed through the `skills` CLI (`vercel-labs/skills`, MIT). They are the reference for the CLI as a whole; this plugin only covers the Pipeline bridge.

```bash
npx skills update -g -y          # update everything installed globally
npx skills list                  # confirm Source: Unity-Technologies/skills
```

If they are not installed at all:

```bash
npx skills add Unity-Technologies/skills -g -a claude-code -s '*' -y
```

Two things to check afterwards:

- **Skipped skills.** The CLI validates YAML frontmatter and refuses malformed skills, printing the parse error. As of 2026-08-24 `physics-3d-collision` is skipped — its `description:` begins with an unquoted `Skill:`, which YAML reads as a nested mapping. Report skips rather than silently landing a smaller set than the repo contains.
- **New overlap.** Diff what Unity's skills now cover against `unity-pipeline`. Anything they document properly should be *deleted* here and referenced instead — see step 6.

## 5. Diff the Pipeline tool surface against the baseline

```bash
unity list --json --no-banner > tools-new.json
```

Compare `data.tools[].name` against `baseline.json`'s `tools` array. Report three buckets explicitly:

- **Added** — new capability; consider whether it replaces a workaround documented in `gotchas.md`
- **Removed** — anything referencing these in the skill notes is now wrong and must be fixed
- **Renamed** — usually shows up as one addition plus one removal with related names

Then spot-check parameters on tools the notes lean on most: `eval_file`, `create_gameobject`, `delete_gameobject`, `package_remove`, `recompile_status`, `console`, `run_tests`. A tool keeping its name while changing its parameters is the failure mode that silently breaks scripts.

**Parse parameter names with `[A-Za-z_]+`, not `[a-z_]+`.** Many are camelCase (`fromState`, `trackType`, `outputPath`, `crunchedCompression`); a lowercase-only pattern silently drops them and manufactures a diff that isn't there.

## 6. Prune what Unity now owns

This is the step that keeps the two skills complementary instead of competing. For each section in `unity-pipeline`, ask: **does Unity's `unity-cli` skill document this?** Check `~/.claude/skills/unity-cli/SKILL.md` and its `references/`.

- If yes and theirs is better → delete ours, link to theirs.
- If yes and ours **contradicts** theirs → verify which is true, then either fix ours or keep it explicitly flagged as a correction with an observation date.
- If no → keep. That is the plugin's reason to exist.

Already ceded to Unity's skill (do not re-add): CLI installation, global flags, environment variables, exit codes, editor installs, licensing and auth, project and template creation, source control setup, UPM packages, builds and tests, `mcp configure`, `unity skill install`, and `unity pipeline install/upgrade`.

Retained here because Unity deliberately does not enumerate it: the tool catalog, the field gotchas, and the baseline.

## 7. Write the findings back

Update in the source repo's `plugins/unity/skills/unity-pipeline/`:

- `references/pipeline-tools.md` — regenerate from `unity list --json` (see the generator note at the bottom)
- `references/baseline.json` — new versions, count, tool list, and `verified` date
- `references/gotchas.md` — **delete entries the upgrade fixed, and entries Unity now documents.** A stale workaround is worse than no note; it sends the next session down a path that is no longer necessary.
- `SKILL.md` — the Baseline block at the bottom

Verify at least one real call still works before declaring success, e.g. `unity cmd editor_status`. Version numbers agreeing is not evidence the bridge works.

## 8. Report

State old → new versions for all three moving parts, the three diff buckets with actual tool names, which reference files you edited, what you pruned in step 6, and anything that broke. If nothing changed, say that plainly and update only the `verified` date.

## Regenerating the tool catalog

`references/pipeline-tools.md` is generated, not hand-written. `unity list --json` reports every tool's `group` as `built-in`, so it carries no domain information — **preserve the existing domain grouping by parsing the current file** and slot new tools into the right section by hand. Keep the conventions preamble; the `confirm`/`dry_run`, async-polling, `objectref`, and authoring-root rules are the load-bearing part of that file.
