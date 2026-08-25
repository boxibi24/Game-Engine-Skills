---
name: unity-pipeline
description: Drive a live Unity Editor through the com.unity.pipeline bridge — its ~142 typed tools called via `unity cmd` or MCP — to read or mutate scenes, GameObjects, prefabs, components, materials, animation, lighting and NavMesh, run C# with eval, poll recompiles, read the console, and capture views. Use when working inside an already-open Unity project, when Pipeline tools are missing or `unity mcp` returns zero tools, or when a Pipeline call behaves differently than documented. For installing the CLI itself, editors, licensing, project creation, UPM packages or CI builds, use the `unity-cli` skill instead.
---

# com.unity.pipeline — driving a live Editor

## Scope: this skill and Unity's `unity-cli` skill

Unity ships an official `unity-cli` skill covering the CLI as a whole: installation, global flags, environment variables, exit codes, editor installs, licensing and auth, project and template creation, source control setup, UPM packages, builds and tests, `mcp configure`, and `unity pipeline install/upgrade`. **That skill is the reference for all of it. Do not duplicate or contradict it here.**

This skill covers the one area Unity's deliberately leaves open: what the connected Editor actually *exposes* and how those tools behave in practice. Unity's own note explains why — "the commands a connected Editor exposes are usable without a CLI update", so they document the mechanism, not the catalog.

| Question | Skill |
|---|---|
| How do I install the CLI / an editor / a licence? | `unity-cli` |
| How do I create a project, set up git, run CI builds? | `unity-cli` |
| What are `unity test` exit codes? Which clients does `mcp configure` write? | `unity-cli` |
| How do I install or upgrade `com.unity.pipeline`? | `unity-cli` (`integration-advanced.md`) |
| **What tools does a connected Editor expose, with what parameters?** | **here** — `references/pipeline-tools.md` |
| **Why did my Pipeline call fail / behave oddly?** | **here** — `references/gotchas.md` |
| **Which CLI + package + tool-count combination was last verified?** | **here** — `references/baseline.json` |

## The mental model

`unity mcp` and `unity cmd` are two front doors onto the **same** Pipeline server running inside the Editor. Same tools, same semantics, same safety rails. MCP is for agents; `unity cmd` is for shells and CI. Neither works without an Editor open and the package imported.

## Orientation — run this first

```bash
unity status
```

`State: ready` with a port means the Pipeline server is up. An empty table means no Editor with the package, and every tool below will fail until that is fixed.

Careful reading `tasklist`: the Editor is `Unity.exe` (multi-GB resident), the CLI is `unity.exe`. Seeing the latter does not mean an Editor is open.

Then `unity list` for the live catalog, or `references/pipeline-tools.md` for the annotated set with parameters.

## If tools are missing

**`unity mcp` returns 0 tools** — the single most common failure. The MCP server is fine; it has no tool source. Check `unity pipeline list`:

- `Pipeline: false` → the package isn't installed. Install it (see the `unity-cli` skill).
- `Pipeline: true`, `Server Reachable: false` → the Editor hasn't imported it yet. It imports **on focus**. See the bootstrap-deadlock entry in `references/gotchas.md` — on a first install `package_resolve` cannot start the server it needs, so something outside the Editor has to focus it.

**`unity list` errors about Pipeline servers** — same root cause, same fix.

## Registering the MCP server for Claude Code

`unity mcp configure` handles most clients, but **`claude-code` is registered as `(no file — delegation/manual)`**, so write `.mcp.json` yourself. Pin `--project-path` so it can't bind to the wrong Editor when several are open:

```json
{
  "mcpServers": {
    "unity": {
      "type": "stdio",
      "command": "C:\\Users\\<you>\\AppData\\Local\\Unity\\bin\\unity.exe",
      "args": ["mcp", "--project-path", "<ABSOLUTE_PROJECT_PATH>"]
    }
  }
}
```

Requires a session restart. Cost: ~142 tool schemas in context. If that's too heavy, skip MCP entirely and shell out to `unity cmd <tool> --flag value` — identical capability, zero standing context, and it works in the session you are already in.

## Working loops

**Code change:** `create_script` / `write_text_file` → `recompile` → poll `recompile_status` until `completed` → `console --level error`. A type does not exist until recompile completes; `attach_script` before that fails with a recoverable error telling you to recompile and retry.

**Tests:** `list_tests` → `run_tests` → poll `test_status`. (For headless CI runs use `unity test` — the `unity-cli` skill documents its exit codes and retry semantics.)

**Visual check:** `capture_scene_view` / `capture_game_view` return PNG inline as base64 — pass `max_resolution` to keep it small, or `save_path` to write to disk. `capture_game_view` takes `source`: the default `camera` misses Screen-Space-Overlay UI, `screen` captures the composited backbuffer but only in Play Mode.

**Console:** `console --tail N --level error`. It takes a `since` cursor, so subsequent reads fetch only new entries. Use it — re-reading the whole log every turn is wasteful, and a busy boot can overflow the buffer (watch for `dropped: true`, which means the entries you did not see are gone).

**Arbitrary C#:** `eval_file` over `eval` — see `references/gotchas.md` for why, and for the 5s main-thread ceiling that `--timeout` does not lift.

## Safety rails, and their limits

Destructive tools refuse without `confirm=true`, and most accept `dry_run=true`. Always dry-run `package_remove`, `set_player_settings`, `delete_asset`, and the `clear_*` bake tools first.

These rails live in the **Pipeline server**, not the CLI wrapper — verified by calling `delete_asset` on a scene over MCP with no `confirm` and getting a 400 refusal with the file untouched. They hold identically over MCP and `unity cmd`.

Undo coverage is uneven: `delete_gameobject` is Undo-able, `set_player_settings` explicitly is not. Do not assume Ctrl+Z will save you.

Writes are confined to the authoring root. **Verify it with `get_authoring_root` rather than assuming** — it commonly reports `Assets`, i.e. the whole project is writable with no narrower sandbox. Paths you pass resolve *relative to it*, which is how a "save it to `Temp/`" ends up in `Assets/Temp/`.

Scene edits leave the scene **dirty but unsaved**. Either call `save_scene` deliberately or tell the user it's unsaved. Never silently save a scene you dirtied.

## Reference files

- `references/pipeline-tools.md` — every tool by domain, with required/optional parameters. Generated; regenerate with `unity list --json`.
- `references/gotchas.md` — field failures and their causes. The load-bearing file.
- `references/baseline.json` — the last verified CLI + package + tool-count combination.

## Baseline (verified 2026-08-24)

Unity CLI `1.0.0-beta.6` · `com.unity.pipeline` `0.5.0-exp.1` · Editor `6000.0.74f1` · **142 tools**

Verified end to end over MCP stdio on the 2026-07-30 pass, not just by listing tools: `initialize` → `tools/list` → `tools/call editor_status` → `tools/call get_scene_hierarchy` → destructive call correctly refused. Also verified the full write loop via `unity cmd`: `create_folder` → `create_script` → `recompile` → poll `recompile_status` → `eval_file` confirming `typeLoaded=True` → `delete_asset` cleanup.

The 2026-08-24 pass re-verified over `unity cmd` only (`editor_status`, `get_authoring_root`, `recompile_status`, `unity list` → 142) on Unity `6000.0.74f1`, i.e. a **6000.0 LTS** editor rather than 6000.3 — `0.5.0-exp.1` resolves and runs there. The MCP stdio path was not re-exercised on this pass.

Delta since 0.4.0-exp.1: **+2 tools** (`audit`, `audit_status` — Project Auditor static analysis, async), **0 removed**, **0 renamed**, and two tools gained optional parameters (`capture_game_view` → `source`, `set_autotick` → `persist`). No breaking parameter changes.

Both the CLI (beta) and Pipeline (experimental) move fast and break compatibility. If tool names or parameters here don't match reality, trust `unity list --json` and run the `unity-pipeline-update` skill to refresh these notes.

`com.unity.ai.assistant` is **not** required and is not part of this setup. It shipped a separate MCP bridge via a relay binary in `~/.unity/relay/` exposing 7 coarse tools; Pipeline supersedes all of them (`eval`/`eval_file` replaces `Unity_RunCommand` without the `IRunCommand` boilerplate). The only capability lost with it is multi-angle scene capture.
