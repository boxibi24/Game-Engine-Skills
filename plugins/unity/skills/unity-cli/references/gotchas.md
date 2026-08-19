# Gotchas

Each of these cost real debugging time. They are not in Unity's docs.

## Git Bash rewrites hierarchy paths (Windows)

MSYS path translation turns any argument starting with `/` into a Windows filesystem path:

```
--target "/ClaudeTestCube"
  → 400 Bad Request: No GameObject at hierarchy path 'C:/Program Files/Git/ClaudeTestCube'
```

Three fixes, best first:

1. **Address objects by `globalId`**, which create/find calls return. Immune, and stable across reloads — this is the right habit regardless of shell.
2. Prefix the command: `MSYS_NO_PATHCONV=1 unity cmd ...`
3. Run it from PowerShell instead.

Bites any `objectref` taking a `hierarchyPath`, and any tool argument that is a project-absolute path.

## `eval` is statement-based, not expression-based

```bash
unity cmd eval --code 'Application.unityVersion'   # → "; expected (line 1, col N)"
```

It wants statements with a `return`. Since the code also has to survive shell quoting, **prefer `eval_file`**:

```csharp
// probe.cs
var go = UnityEngine.GameObject.Find("Main Camera");
return "unity=" + UnityEngine.Application.unityVersion + " mainCam=" + (go != null);
```

```bash
unity cmd eval_file --file probe.cs
```

Returns a typed `result` plus a `diagnostics` array. Roslyn-backed, ~0.5–1s. Use fully-qualified type names or add `using` lines; the eval context is not the same as a normal script's.

## Package install does not import itself

`unity pipeline install` edits `Packages/manifest.json` and returns immediately. A running Editor only imports on focus, so `unity status` stays empty and you will think the install failed.

Force it: `unity cmd package_resolve` (if any Pipeline server is already up), or click into the Editor. Then poll `unity cmd recompile_status` until `completed`. Budget ~60s for import plus domain reload. `unity pipeline list` is the honest progress indicator — watch `Server Port` and `Server Reachable` populate.

## Zero tools means no tool source, not a broken server

`unity mcp` will handshake happily and report `unity-mcp v1.0.0-beta.3` while exposing **0 tools**. That is not an MCP failure — Pipeline isn't installed or reachable. Diagnose with `unity pipeline list`, never by reinstalling the CLI.

## `unity build` needs your own build method

`--execute-method` is required. Unity has no built-in command-line build entry point, so you must ship a static C# method. `--output-path` is passed through as `-buildOutput` but nothing honours it unless your method reads it.

## Targeting the right Editor

With several Editors open, the MCP server binds to the *first discovered* instance. Pin it:

- `--project-path <path>` or `UNITY_PROJECT_PATH`
- `--instance-id <pid>` or `UNITY_INSTANCE_ID`

Command-line arguments win over env vars. Always pin in `.mcp.json`.

## Async tools return immediately

`package_add`, `package_remove`, `build`, `run_tests`, `bake_*`, `switch_build_target` return `in_progress`. Poll the matching `*_status` tool. Some accept `wait=true` to block instead — simpler when you have nothing else to do.

## Scripts do not exist until recompile finishes

`create_script` writes the file; the type is not loaded yet. `attach_script` immediately after fails — recoverably, with a message telling you to recompile. Sequence: `create_script` → `recompile` → poll `recompile_status` → `attach_script`.

## Output format is not stable

The default `human` format is a column-shifting table. Parse `--json` instead. Note the envelope differs by command: `unity list --json` nests under `data.tools`, while `unity cmd` returns a per-command shape.

## Scene dirty state

Mutating a scene marks it dirty without saving. Creating and deleting an object returns the scene to its original *content* but leaves the dirty flag set, so Unity still prompts on close. Either `save_scene` deliberately or tell the user it's unsaved — don't silently rewrite their scene file to tidy a flag.

## Authoring root — check it, don't assume it

Asset writes are confined to the authoring root, and paths you pass are resolved *relative to it* (the `Assets/` prefix is optional). Unexpected "path outside authoring root" errors come from this.

Observed default on this setup: **`Assets`** — the entire project, no narrower sandbox. Do not assume writes are contained. Run `get_authoring_root` before any bulk or destructive asset work; `set_authoring_root <folder>` narrows it if you want a real blast-radius limit for an agent session.

## Folders are not created implicitly

`create_script --path Scripts` fails with `Destination folder 'Assets/Scripts' does not exist. Create it first with create_folder.` The errors are precise and actionable — read them rather than guessing. Call `create_folder` first.

## Deleting a `.cs` triggers a recompile

Asset deletion of scripts kicks off another compile and domain reload. Poll `recompile_status` to `completed` after cleanup too, not just after creation, or the next command lands mid-reload.

## Unity's MCP banner omits Claude Code — ignore it

`unity mcp` prints "Connect via Claude Desktop, Cursor, VS Code, or the MCP Inspector" on startup. Claude Code's absence is just an incomplete client list, matching the `(no file — delegation/manual)` entry in `unity mcp configure --list`. The stdio transport is standard JSON-RPC and works fine — confirmed by a full `initialize` → `tools/list` → `tools/call` round trip. Don't treat the banner as an incompatibility.

## `unity mcp configure claude-code` does nothing useful

It is registered as `(no file — delegation/manual)`. Write `.mcp.json` yourself. The other 15 clients (Cursor, Codex, Copilot, Claude Desktop, VS Code, …) do get written.

## Unrelated third-party `unityMCP` servers

Several editors may carry a `unityMCP` entry pointing at `http://127.0.0.1:8080/mcp` with state in `~/.unity-mcp/`, `%LOCALAPPDATA%\UnityMCP`, `%APPDATA%\UnityMCP`. That is a **different, third-party** Unity MCP project, unrelated to `unity mcp`/Pipeline. Don't confuse the two when debugging, and don't delete one thinking it's the other.
