---
name: unity-cli
description: Drive a Unity project from the command line or over MCP using the Unity CLI (`unity`) and the com.unity.pipeline Editor bridge. Use when working in any Unity project — reading or mutating scenes, GameObjects, prefabs, components, materials, animation, lighting or NavMesh; running Unity tests; triggering builds; reading the Editor console; managing UPM packages; or when the user mentions Unity, the Unity Editor, Unity MCP, the Pipeline package, or asks why Unity tools are missing/returning zero tools.
---

# Unity CLI, Pipeline, and MCP

Three things, two of which are the same thing wearing different clothes.

| Piece | What it is | Needs Editor running? |
|---|---|---|
| `unity` CLI | Standalone binary. Hub/editor/project management, builds, tests. | No |
| `com.unity.pipeline` | UPM package. Runs an HTTP server *inside* the Editor exposing 140 typed tools. | Yes |
| `unity mcp` | Wraps the Pipeline server as an MCP stdio server. | Yes |

`unity mcp` and `unity cmd` are two front doors onto the **same** Pipeline server. Same tools, same semantics. MCP is for agents; `unity cmd` is for shells and CI.

## Orientation — run this first

```bash
unity status
```

`State: ready` with a port means the Pipeline server is up. Empty table means no Editor with the package, and every live-Editor feature will fail until you fix that.

If no Editor is running, `unity open <project>` launches it — but **it stays attached to the Editor process and never returns**, so run it backgrounded. Cold start to `ready` is ~15s. Don't mistake the non-returning call for a hang.

Careful reading `tasklist`: the Editor is `Unity.exe` (multi-GB resident), the CLI is `unity.exe`. Seeing the latter does not mean an Editor is open.

Then `unity list` for the tool catalog, or read `references/pipeline-tools.md` for the full annotated set.

## If tools are missing

**`unity mcp` returns 0 tools** — the single most common failure. The MCP server is fine; it has no tool source. Pipeline isn't installed or isn't reachable. Check `unity pipeline list`: if `Pipeline` is `false`, run `unity pipeline install`. If `Pipeline` is `true` but `Server Reachable` is `false`, the Editor hasn't imported the package yet — it imports on focus, or force it with `unity cmd package_resolve`, then poll `unity cmd recompile_status` until `completed`. Import plus domain reload takes ~60s.

**`unity list` errors about Pipeline servers** — same root cause, same fix.

## Registering the MCP server

Per-project `.mcp.json`. Pin `--project-path` so it can't bind to the wrong Editor when several are open:

```json
{
  "mcpServers": {
    "unity": {
      "type": "stdio",
      "command": "C:\\Users\\ASUS\\AppData\\Local\\Unity\\bin\\unity.exe",
      "args": ["mcp", "--project-path", "<ABSOLUTE_PROJECT_PATH>"]
    }
  }
}
```

Requires a session restart. Cost: 140 tool schemas in context. If that's too heavy for a session, skip MCP and shell out to `unity cmd <tool> --flag value` — identical capability, zero standing context.

## Working loops

**Code change:** `create_script` / `write_text_file` → `recompile` → poll `recompile_status` until `completed` → `console --level error` to check. A type does not exist until recompile completes; `attach_script` before that fails with a recoverable error telling you to recompile and retry.

**Tests:** `list_tests` → `run_tests` → poll `test_status`. Or headless via `unity test --mode EditMode --output results.xml`.

**Visual check:** `capture_scene_view` / `capture_game_view` return PNG inline as base64 — pass `max_resolution` to keep it small, or `save_path` to write to disk instead.

**Console:** `console --tail N --level error`. It takes a `since` cursor, so subsequent reads fetch only new entries. Use it — re-reading the whole log every turn is wasteful.

## Safety rails, and their limits

Destructive tools refuse without `confirm=true`, and most accept `dry_run=true` to preview. Always dry-run `package_remove`, `set_player_settings`, `delete_asset`, and the `clear_*` bake tools first.

These rails live in the **Pipeline server**, not the CLI wrapper — verified by calling `delete_asset` on a scene over MCP with no `confirm` and getting a 400 refusal with the file untouched. They hold identically whether an agent calls over MCP or a shell calls `unity cmd`.

Undo coverage is uneven: `delete_gameobject` is Undo-able, `set_player_settings` explicitly is not. Do not assume Ctrl+Z will save you.

Writes are confined to the authoring root. **Verify it with `get_authoring_root` rather than assuming** — on this setup it reports `Assets`, i.e. the whole project is already writable, with no narrower sandbox in effect. Treat asset writes as unsandboxed unless you have checked otherwise.

Scene edits leave the scene **dirty but unsaved**. Either call `save_scene` or tell the user it's unsaved. Never silently save a scene you dirtied — that rewrites a file they didn't ask you to touch.

## Reference files

- `references/pipeline-tools.md` — all 140 tools by domain, with parameters
- `references/cli-commands.md` — the `unity` command surface, build/test/CI flags
- `references/gotchas.md` — Windows path mangling, `eval` syntax, batch-mode limits

## Baseline (verified 2026-07-30)

Unity CLI `1.0.0-beta.3` · `com.unity.pipeline` `0.4.0-exp.1` · Editor `6000.3.13f1` · **140 tools**

Verified end to end over MCP stdio, not just by listing tools: `initialize` → `tools/list` (140) → `tools/call editor_status` → `tools/call get_scene_hierarchy` → destructive call correctly refused. Also verified the full write loop via `unity cmd`: `create_folder` → `create_script` → `recompile` → poll `recompile_status` → `eval_file` confirming `typeLoaded=True` → `delete_asset` cleanup.

Both the CLI (beta) and Pipeline (experimental) move fast and break compatibility. If tool names or parameters here don't match reality, trust `unity list --json` and run the `unity-cli-update` skill to refresh these notes.

`com.unity.ai.assistant` is **not** required and is not part of this setup. It shipped a separate MCP bridge via a relay binary in `~/.unity/relay/` exposing 7 coarse tools; Pipeline supersedes all of them (`eval`/`eval_file` replaces `Unity_RunCommand` without the `IRunCommand` boilerplate). The only capability lost with it is multi-angle scene capture.
