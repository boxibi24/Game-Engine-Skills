---
name: ue-editor-automation
description: Run Python inside Unreal Editor headlessly from the command line to inspect or mutate a level - enumerate actors, read component properties, line-trace collision, delete actors, save maps, take screenshots. Use this whenever a task needs the editor to do something without a human clicking in it, whenever you are writing or debugging a script launched with UnrealEditor.exe, and whenever an editor automation run mysteriously exits early, produces no output, or appears to hang. Also use it when someone asks whether Unreal can be scripted or automated at all, or mentions PythonScriptPlugin, ExecCmds, ExecutePythonScript, unreal.log, or the Unreal Python API.
---

# Driving Unreal Editor from the command line

Unreal ships a full Python API inside the editor. You can enumerate every actor
in a level, read component properties, trace against real collision, delete
things, save packages and take screenshots, all without a human touching the UI.
The API only exists *inside* a running editor, so every task becomes: boot the
editor, run a script in it, have the script write its results to disk and quit.

This skill is the harness. The traps below cost real debugging time to find, and
none of them announce themselves clearly when you hit them.

## The launch line

```
UnrealEditor.exe "<path.uproject>" <MapPath> -ExecCmds="py <script.py>" \
  -EnablePlugins=PythonScriptPlugin -nosplash -NoLiveCoding -windowed -ResX=1920 -ResY=1080
```

`PythonScriptPlugin` is an engine plugin that ships disabled by default, so pass
`-EnablePlugins=PythonScriptPlugin` rather than assuming the project enabled it.

**Use `-ExecCmds="py <script>"`, never `-ExecutePythonScript`.** This is the
single most expensive mistake in this workflow. `-ExecutePythonScript` routes
through `FEditorPythonExecuter`, which requests editor exit the moment your
script *returns*. Any script that does its work from a tick callback returns
immediately after registering that callback, so the editor shuts down a handful
of frames later having rendered nothing and written nothing. The symptom is an
editor that starts, sits briefly, and exits cleanly with no output and no error
— which reads like your script never ran. `-ExecCmds` leaves the editor alive
and lets the script own its own lifetime.

Build the whole command as one string so the quoting inside `-ExecCmds`
survives the process launcher.

**Close the editor first.** A second editor on the same project fights over file
locks and the derived data cache, and these scripts rewrite `.umap` files a
running editor may hold open. Check for a running `UnrealEditor*` process and
refuse rather than producing a confusing failure later.

## Why work happens in a tick callback

The world is not loaded when your script first runs. Actors, collision and
streaming are not ready for many frames. So register a callback and drive a
small state machine from it:

```python
import unreal

S = {"frame": 0, "handle": None, "done": False}
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

def tick(delta_seconds):
    S["frame"] += 1
    if S["done"]:
        return
    # A stall must never wedge the editor forever - cap total frames.
    if S["frame"] > 6000:
        S["done"] = True
        unreal.SystemLibrary.quit_editor()
        return
    try:
        world = ues.get_editor_world()
        if not (world and MAP_NAME in world.get_name()):
            return                      # not our world yet
        if S["frame"] < 180:
            return                      # let streaming and physics settle
        S["done"] = True
        do_the_work(world)
        unreal.unregister_slate_post_tick_callback(S["handle"])
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        # Never let an error escape the tick: an unhandled exception leaves the
        # editor running with no one to quit it, and the run hangs to deadline.
        S["done"] = True
        unreal.log_error("FAILED: %s" % exc)
        unreal.SystemLibrary.quit_editor()

S["handle"] = unreal.register_slate_post_tick_callback(tick)
unreal.log("[MYSCRIPT] armed")
```

Waiting on a frame count rather than a "is it loaded" flag is deliberate: there
is no single reliable readiness signal covering streaming, physics and
collision, and a trace issued too early silently returns no hit, which looks
identical to "there is no floor here".

Log an `armed` line immediately. When a run produces nothing, the first question
is always whether the script armed at all — if that line is absent from
`Saved/Logs/*.log`, the script died at import and never registered anything.

## Talking to the outside

The launcher cannot see Python return values, so use files:

- **Inputs** via environment variables set before launching, and JSON files for
  anything structured.
- **Outputs** as a JSON file the script writes.
- **Completion** as a sentinel file written only on full success. The launcher
  polls for it. Distinguish "sentinel appeared" from "process exited" — the
  latter alone does not mean the work succeeded.

Give the editor a generous shutdown grace period after the sentinel appears.
Shutdown flushes async tasks and the DDC and legitimately takes upwards of a
minute; killing at 20 seconds produces spurious "timeout" reports for runs that
actually succeeded.

## Traps that bite

**UTF-8 BOM in JSON input.** PowerShell 5.1's `Set-Content -Encoding utf8`
writes a BOM. Python's `json.load` rejects it outright with
`Unexpected UTF-8 BOM`. Because that happens at module import, the tick callback
never registers and the editor idles until the launcher's deadline — the symptom
is a hang, not a parse error. Read with `encoding="utf-8-sig"`, which accepts
the file with or without a BOM, and write from PowerShell with
`[System.IO.File]::WriteAllText(path, text, New-Object System.Text.UTF8Encoding($false))`.

**Anything that can fail at import must quit the editor.** A module-level
exception means no callback is ever registered, so nothing will ever call
`quit_editor`. Wrap import-time setup and call `quit_editor()` in the handler
before re-raising.

**A line trace that starts inside a collider reports no hit.** This is how a
camera ends up rendering the inside of a character's head: the check said
"nothing in front of me" because the ray began within the mesh. Use
`sphere_trace_single` and test `initial_overlap` (the second element of
`hit.to_tuple()`) to detect occupancy at a point.

**`.umap` files stay memory-mapped briefly after the editor exits.** A copy
issued immediately after a run can fail with *"cannot be performed on a file
with a user-mapped section open"* even though nothing owns the file any more.
Retry with a short backoff.

**Property names vary across engine versions.** Reading component properties by
a single hardcoded name is brittle. Probe several spellings and fall back to
`get_editor_property`, returning a default rather than raising.

**Screenshots bake in editor overlays.** `HighResShot` from an editor viewport
includes volume wireframes, actor billboards and the corner axis gizmo unless
you enter Game View first via
`unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).editor_set_game_view(True)`.
Those overlays read as a visual difference between two captures when they are
nothing of the sort.

## Bundled scripts

Working implementations of all of this live in the `ue-perf-shots` skill's
`scripts/` directory — `UECommon.ps1` provides engine/project discovery and the
launcher, and `recon.py` / `capture.py` / `optimize.py` are complete examples of
the tick-callback pattern for surveying, screenshotting and mutating a level.
Read those before writing a new one from scratch.
