"""
Runs inside UnrealEditor via:  -ExecCmds="py <this file>"

Captures a HighResShot from EVERY camera in cameras.json within a SINGLE editor
session, then quits. One boot per state instead of one boot per angle.

IMPORTANT: do NOT launch this with -ExecutePythonScript. That flag routes through
FEditorPythonExecuter, which requests editor exit as soon as the script returns.
Because this script works from a deferred tick callback, the editor would shut
down ~4 frames in and never render. -ExecCmds keeps the editor alive and lets the
script own its own lifetime.

Env:
    UEPERF_SHOT_LABEL  before | after
    UEPERF_SHOT_CAMS   path to cameras.json  (list of {name,x,y,z,pitch,yaw,roll})
    UEPERF_SHOT_MANIFEST  path to write {camera_name: png_filename}
    UEPERF_SHOT_DONE   marker file written on success
    UEPERF_SHOT_DIR    directory HighResShot writes into (watched for new pngs)
    UEPERF_SHOT_MAP    expected world name, to confirm the level finished loading
    UEPERF_SHOT_WARM   frames to settle before the FIRST shot
    UEPERF_SHOT_REWARM frames to settle between later shots (level already loaded)
"""
import json
import os

import unreal

LABEL = os.environ.get("UEPERF_SHOT_LABEL", "shot")
CAMS_JSON = os.environ.get("UEPERF_SHOT_CAMS", "")
MANIFEST = os.environ.get("UEPERF_SHOT_MANIFEST", "")
DONE = os.environ.get("UEPERF_SHOT_DONE", "")
SHOT_DIR = os.environ.get("UEPERF_SHOT_DIR", "")
MAP_NAME = os.environ.get("UEPERF_SHOT_MAP", "")

# The world-ready check below tests `MAP_NAME in world.get_name()`. An empty
# MAP_NAME is a substring of every name, so it would match the transient
# startup world and the script would run against nothing. Require it.
if not MAP_NAME:
    unreal.log_error("[UEPERF-SHOT] UEPERF_SHOT_MAP is required (the expected world name)")
    unreal.SystemLibrary.quit_editor()
    raise SystemExit("UEPERF_SHOT_MAP not set")
WARM = int(os.environ.get("UEPERF_SHOT_WARM", "300"))
REWARM = int(os.environ.get("UEPERF_SHOT_REWARM", "150"))

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

# Read as utf-8-sig, not utf-8: PowerShell 5.1's `Set-Content -Encoding utf8`
# emits a BOM, and json.load rejects it outright ("Unexpected UTF-8 BOM").
# utf-8-sig accepts the file with or without one.
#
# If this fails we must quit the editor immediately - a module-level exception
# means the tick callback below never registers, so the editor would otherwise
# sit idle until the launcher's deadline expires.
try:
    with open(CAMS_JSON, "r", encoding="utf-8-sig") as fh:
        CAMS = json.load(fh)
    if not CAMS:
        raise ValueError("camera list is empty")
except Exception as _exc:
    unreal.log_error("[UEPERF-SHOT/%s] cannot read cameras from %r: %s"
                     % (LABEL, CAMS_JSON, _exc))
    unreal.SystemLibrary.quit_editor()
    raise

S = {
    "frame": 0,
    "handle": None,
    "phase": "wait_world",
    "idx": 0,
    "mark": 0,
    "baseline": set(),
    "results": {},
    "finished": False,
}

# Never let a stall wedge the editor: cap total frames across all cameras.
HARD_CAP = WARM + (REWARM + 2400) * max(1, len(CAMS)) + 3000


def log(msg):
    unreal.log("[UEPERF-SHOT/%s] %s" % (LABEL, msg))


def pngs():
    if not SHOT_DIR or not os.path.isdir(SHOT_DIR):
        return set()
    return set(f for f in os.listdir(SHOT_DIR) if f.lower().endswith(".png"))


def set_camera(c):
    ues.set_level_viewport_camera_info(
        unreal.Vector(c["x"], c["y"], c["z"]),
        unreal.Rotator(roll=c.get("roll", 0.0), pitch=c["pitch"], yaw=c["yaw"]),
    )


def enter_game_view():
    """Hide editor-only overlays so the shots show the level, not the tooling.

    Without this, HighResShot bakes in volume wireframes, actor billboard
    icons and the corner axis gizmo - noise that reads as a visual difference
    between before and after when it is nothing of the sort.
    """
    try:
        les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
        les.editor_set_game_view(True)
        log("game view enabled")
        return
    except Exception as exc:  # noqa: BLE001
        log("editor_set_game_view unavailable (%s); falling back to show flags" % exc)
    world = ues.get_editor_world()
    for cmd in ("show Volumes", "show Sprites", "show BillboardSprites",
                "show Grid", "show Selection"):
        try:
            unreal.SystemLibrary.execute_console_command(world, cmd)
        except Exception:
            pass


def finish(ok, why):
    if S["finished"]:
        return
    S["finished"] = True
    log("%s - %s  (captured %d/%d)" % ("DONE" if ok else "GIVING UP", why,
                                       len(S["results"]), len(CAMS)))
    if MANIFEST:
        try:
            with open(MANIFEST, "w") as fh:
                json.dump(S["results"], fh, indent=1)
        except Exception as exc:  # noqa: BLE001
            log("manifest write failed: %s" % exc)
    # Only claim success if every camera produced a file.
    if ok and DONE and len(S["results"]) == len(CAMS):
        with open(DONE, "w") as fh:
            fh.write("ok\n")
    try:
        unreal.unregister_slate_post_tick_callback(S["handle"])
    except Exception:
        pass
    unreal.SystemLibrary.quit_editor()


def tick(delta_seconds):
    S["frame"] += 1
    f = S["frame"]

    if f > HARD_CAP:
        finish(False, "hard frame cap at %d" % HARD_CAP)
        return

    try:
        if S["phase"] == "wait_world":
            world = ues.get_editor_world()
            if world and MAP_NAME in world.get_name():
                log("world '%s' ready at frame %d; %d cameras queued"
                    % (world.get_name(), f, len(CAMS)))
                enter_game_view()
                S["phase"] = "arm"

        elif S["phase"] == "arm":
            c = CAMS[S["idx"]]
            S["baseline"] = pngs()
            set_camera(c)
            S["mark"] = f
            S["phase"] = "warming"
            log("[%d/%d] %s -> pos(%.1f, %.1f, %.1f) yaw %.2f"
                % (S["idx"] + 1, len(CAMS), c["name"], c["x"], c["y"], c["z"], c["yaw"]))

        elif S["phase"] == "warming":
            need = WARM if S["idx"] == 0 else REWARM
            if f - S["mark"] >= need:
                unreal.SystemLibrary.execute_console_command(
                    ues.get_editor_world(), "HighResShot 1920x1080"
                )
                S["mark"] = f
                S["phase"] = "wait_file"

        elif S["phase"] == "wait_file":
            new = pngs() - S["baseline"]
            if new:
                fn = sorted(new)[0]
                S["results"][CAMS[S["idx"]]["name"]] = fn
                log("[%d/%d] captured %s" % (S["idx"] + 1, len(CAMS), fn))
                S["idx"] += 1
                if S["idx"] >= len(CAMS):
                    finish(True, "all cameras captured")
                else:
                    S["phase"] = "arm"
            elif f - S["mark"] > 2400:
                log("[%d/%d] no png appeared; skipping"
                    % (S["idx"] + 1, len(CAMS)))
                S["idx"] += 1
                if S["idx"] >= len(CAMS):
                    finish(False, "ran out of cameras with shots missing")
                else:
                    S["phase"] = "arm"

    except Exception as exc:  # noqa: BLE001 - never let an error wedge the editor
        finish(False, "exception: %s" % exc)


S["handle"] = unreal.register_slate_post_tick_callback(tick)
log("armed: map=%s cams=%d warm=%d rewarm=%d" % (MAP_NAME, len(CAMS), WARM, REWARM))
