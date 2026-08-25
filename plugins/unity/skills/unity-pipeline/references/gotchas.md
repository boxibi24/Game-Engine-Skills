# Gotchas

Each of these cost real debugging time. They are **not** in Unity's own `unity-cli` skill —
that skill documents the CLI's intended surface; this file documents where reality diverges
from it, and how the Pipeline bridge behaves once an Editor is actually connected.

Where an entry contradicts Unity's documentation, it says so explicitly and gives the
observation date, so the next reader can re-check rather than guess which is right.

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

Force it: `unity cmd package_resolve` (if any Pipeline server is already up), or click into the Editor. Then poll `unity cmd recompile_status` until `completed`. `unity pipeline list` is the honest progress indicator — watch `Server Port` and `Server Reachable` populate.

**On a first install there is no server yet, so `package_resolve` cannot bootstrap itself** — it fails with `No Unity Editor instances found with reachable Pipeline servers`, and the `editor_focus` tool is useless for the same reason. Something outside the Editor has to give it focus. On Windows, without touching the mouse:

```powershell
Add-Type '... user32 SetForegroundWindow / ShowWindow ...'
$p = Get-Process Unity; [W]::SetForegroundWindow($p.MainWindowHandle)
```

Budget more than the ~60s often quoted: on a large project (Unity 6000.0.74f1, ~40 packages) the server took **90s** to report `Server Reachable: true` after focus. Poll, don't guess.

## Zero tools means no tool source, not a broken server

`unity mcp` will handshake happily and report its own version (e.g. `unity-mcp v1.0.0-beta.6`) while exposing **0 tools**. That is not an MCP failure — Pipeline isn't installed or reachable. Diagnose with `unity pipeline list`, never by reinstalling the CLI.

## Targeting the right Editor

With several Editors open, the MCP server binds to the *first discovered* instance. Pin it:

- `--project-path <path>` or `UNITY_PROJECT_PATH`
- `--instance-id <pid>` or `UNITY_INSTANCE_ID`

Command-line arguments win over env vars. Always pin in `.mcp.json`.

## Async tools return immediately

`package_add`, `package_remove`, `build`, `run_tests`, `audit`, `bake_*`, `switch_build_target` return `in_progress`. Poll the matching `*_status` tool. Some accept `wait=true` to block instead — simpler when you have nothing else to do.

Separately, the CLI gained `unity job status|wait|cancel <job-id>` in beta.6 for *detached Editor command jobs* — a different mechanism from these in-Editor async tools, and not a way to poll them.

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

## `mcp configure` — the client list differs from Unity's docs

Unity's `unity-cli` skill (`references/integration-advanced.md`) states **16 clients** and lists them.
Observed on `1.0.0-beta.6`, 2026-08-24: `unity mcp configure --list` returns **17** — the list also
includes `kimi`, which Unity's text omits.

More importantly, four of those 17 are `(no file — delegation/manual)` and write nothing:
`claude-code`, `trae`, `openclaw`, `inspect`. The other 13 do get written.

**`claude-code` being one of the four is the trap**: it is listed as supported, so it looks like
`unity mcp configure claude-code` will register the server, and it does not. Write `.mcp.json`
by hand — see the parent SKILL.md.

Not to be confused with `unity skill install claude-code`, which *does* write something: Unity's
own CLI documentation, as a skill, into `~/.claude/skills/unity-cli/`. That is the skill this one
defers to for CLI-general questions, and it is why this skill is named `unity-pipeline` rather than
`unity-cli` — installing Unity's would otherwise collide with it.

## `audit` is exposed even when Project Auditor is missing

New in `0.5.0-exp.1`. `audit` / `audit_status` appear in `unity list` unconditionally, but on an Editor without the Project Auditor package `audit_status` returns

```json
{"status":"unavailable","message":"Project Auditor is not installed in this Editor (Unity.ProjectAuditor.Editor.ProjectAuditor not found)."}
```

Presence in the tool list is not proof a tool can run. Install `com.unity.project-auditor` first; `unavailable` is one of the documented `audit_status` states (`idle | scanning | completed | failed | interrupted | unavailable`), not an error.

## Unrelated third-party `unityMCP` servers

Several editors may carry a `unityMCP` entry with state in `~/.unity-mcp/`, `%LOCALAPPDATA%\UnityMCP`, `%APPDATA%\UnityMCP`. That is a **different, third-party** Unity MCP project — CoplayDev's `com.coplaydev.unity-mcp` (`github.com/CoplayDev/unity-mcp`) — unrelated to `unity mcp`/Pipeline. Don't confuse the two when debugging, and don't delete one thinking it's the other.

Observed on a project running both (2026-08-24): CoplayDev's Editor bridge is a **raw TCP** listener on **6400** that answers a plain `ping` with `WELCOME UNITY-MCP 1 FRAMING=1`, and writes `unity-mcp-status-*.json` / `unity-mcp-port-*.json` discovery files into `~/.unity-mcp/`. Pipeline's server is HTTP on a *different* port (7800 there). **They coexist fine** — installing Pipeline did not disturb it. Two tells for which one you are looking at:

- CoplayDev's Python server runs via `uvx mcp-for-unity`, logs to `%LOCALAPPDATA%\UnityMCP\Logs\unity_mcp_server.log`, and needs a separate `claude mcp add` registration — which, unlike `unity cmd`, only takes effect after a session restart.
- Those stale `unity-mcp-port*.json` files can point at a long-dead port from an unrelated project; they are not evidence about the project in front of you. Trust `unity pipeline list` for Pipeline, and the `unity-mcp-status-*.json` whose `project_path` matches for CoplayDev.
