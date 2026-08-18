"""
Runs inside UnrealEditor via:  -ExecCmds="py <this file>"

Deletes every actor whose class name is in UEPERF_OPT_CLASSES from the loaded
level, saves the level, writes a report, and quits.

This is the level half of the optimization. The config half (Lumen, ray
tracing, frame smoothing) is a plain text edit made outside the editor.

Env:
    UEPERF_OPT_MAP      expected world name
    UEPERF_OPT_CLASSES  comma-separated class names to delete, e.g. "BP_EasyFog_C"
    UEPERF_OPT_REPORT   path to write the report JSON
    UEPERF_OPT_DRYRUN   "1" to count without deleting or saving
"""
import json
import os

import unreal

MAP_NAME = os.environ.get("UEPERF_OPT_MAP", "")

# The world-ready check below tests `MAP_NAME in world.get_name()`. An empty
# MAP_NAME is a substring of every name, so it would match the transient
# startup world and the script would run against nothing. Require it.
if not MAP_NAME:
    unreal.log_error("[UEPERF-OPT] UEPERF_OPT_MAP is required (the expected world name)")
    unreal.SystemLibrary.quit_editor()
    raise SystemExit("UEPERF_OPT_MAP not set")
CLASSES = [c.strip() for c in os.environ.get("UEPERF_OPT_CLASSES", "").split(",") if c.strip()]
REPORT = os.environ.get("UEPERF_OPT_REPORT", "")
DRYRUN = os.environ.get("UEPERF_OPT_DRYRUN", "") == "1"

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

S = {"frame": 0, "handle": None, "done": False}


def log(msg):
    unreal.log("[UEPERF-OPT] %s" % msg)


def save_level():
    """Try the modern subsystem first, fall back to the utility library."""
    errs = []
    try:
        les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
        if les.save_current_level():
            return True, "LevelEditorSubsystem.save_current_level"
        errs.append("save_current_level returned False")
    except Exception as exc:  # noqa: BLE001
        errs.append("save_current_level: %s" % exc)
    try:
        ok = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, False)
        if ok:
            return True, "save_dirty_packages"
        errs.append("save_dirty_packages returned False")
    except Exception as exc:  # noqa: BLE001
        errs.append("save_dirty_packages: %s" % exc)
    return False, "; ".join(errs)


def run(world):
    report = {"world": world.get_name(), "requested": CLASSES, "dry_run": DRYRUN}

    try:
        report["is_partitioned"] = bool(world.get_editor_property("is_partitioned_world"))
    except Exception:
        report["is_partitioned"] = None

    if not CLASSES:
        report["error"] = "UEPERF_OPT_CLASSES was empty - nothing to do"
        log(report["error"])
        return report

    actors = eas.get_all_level_actors()
    report["actors_before"] = len(actors)

    wanted = set(CLASSES)
    targets = []
    for a in actors:
        if a.get_class().get_name() in wanted:
            targets.append(a)

    counts = {}
    for a in targets:
        n = a.get_class().get_name()
        counts[n] = counts.get(n, 0) + 1
    report["matched"] = counts
    report["matched_total"] = len(targets)
    # A requested class that matched nothing is a typo or a wrong assumption -
    # surface it rather than silently doing less work than asked.
    report["unmatched_classes"] = sorted(wanted - set(counts))

    if DRYRUN:
        log("DRY RUN: would delete %d actor(s): %s" % (len(targets), counts))
        return report

    deleted, failed = 0, 0
    for a in targets:
        try:
            label = a.get_actor_label()
            if eas.destroy_actor(a):
                deleted += 1
            else:
                failed += 1
                log("destroy_actor returned False for %s" % label)
        except Exception as exc:  # noqa: BLE001
            failed += 1
            log("destroy failed: %s" % exc)

    report["deleted"] = deleted
    report["failed"] = failed
    report["actors_after"] = len(eas.get_all_level_actors())

    ok, how = save_level()
    report["saved"] = ok
    report["save_method"] = how
    log("deleted %d (failed %d); saved=%s via %s" % (deleted, failed, ok, how))
    return report


def tick(delta_seconds):
    S["frame"] += 1
    if S["done"]:
        return
    if S["frame"] > 6000:
        S["done"] = True
        log("hard cap; quitting")
        unreal.SystemLibrary.quit_editor()
        return
    try:
        world = ues.get_editor_world()
        if not (world and MAP_NAME in world.get_name()):
            return
        if S["frame"] < 180:      # let streaming finish before enumerating
            return
        S["done"] = True
        report = run(world)
        if REPORT:
            with open(REPORT, "w") as fh:
                json.dump(report, fh, indent=1, sort_keys=True)
            log("wrote %s" % REPORT)
        unreal.unregister_slate_post_tick_callback(S["handle"])
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:  # noqa: BLE001
        S["done"] = True
        log("FAILED: %s" % exc)
        if REPORT:
            try:
                with open(REPORT, "w") as fh:
                    json.dump({"error": str(exc)}, fh, indent=1)
            except Exception:
                pass
        unreal.SystemLibrary.quit_editor()


S["handle"] = unreal.register_slate_post_tick_callback(tick)
log("armed: map=%s classes=%s dryrun=%s" % (MAP_NAME, CLASSES, DRYRUN))
