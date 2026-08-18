"""
Runs inside UnrealEditor via:  -ExecCmds="py <this file>"

Read-only survey of a level: actor class histogram, light inventory, fog /
Niagara / decal inventory, PlayerStarts, bounds - PLUS ground-traced camera
positions for the before/after screenshot set. One boot instead of two.

Writes two files and quits:
    UEPERF_RECON_INFO   full analysis JSON
    UEPERF_RECON_CAMS   camera list JSON consumable by capture.py

Camera placement traces every candidate XY down onto real collision, so no
camera ends up buried in terrain or floating over a pit. A reference camera
matching a known-good in-game vantage can be injected via UEPERF_RECON_REF.

Env:
    UEPERF_RECON_MAP     expected world name
    UEPERF_RECON_INFO    output path for the analysis JSON
    UEPERF_RECON_CAMS    output path for the camera JSON
    UEPERF_RECON_REF     "x,y,z,pitch,yaw" reference vantage (optional)
    UEPERF_RECON_RADIUS  eye-level ring radius; 0 = derive from playspace
    UEPERF_RECON_COUNT   eye-level ring positions
    UEPERF_RECON_EYE     camera height above traced ground
    UEPERF_RECON_ORBIT   aerial orbit positions
"""
import json
import math
import os

import unreal

MAP_NAME = os.environ.get("UEPERF_RECON_MAP", "")

# The world-ready check below tests `MAP_NAME in world.get_name()`. An empty
# MAP_NAME is a substring of every name, so it would match the transient
# startup world and the script would run against nothing. Require it.
if not MAP_NAME:
    unreal.log_error("[UEPERF-RECON] UEPERF_RECON_MAP is required (the expected world name)")
    unreal.SystemLibrary.quit_editor()
    raise SystemExit("UEPERF_RECON_MAP not set")
INFO_OUT = os.environ.get("UEPERF_RECON_INFO", "")
CAMS_OUT = os.environ.get("UEPERF_RECON_CAMS", "")
REF = os.environ.get("UEPERF_RECON_REF", "").strip()
RING_R = float(os.environ.get("UEPERF_RECON_RADIUS", "0"))
RING_N = int(os.environ.get("UEPERF_RECON_COUNT", "8"))
EYE = float(os.environ.get("UEPERF_RECON_EYE", "165"))
ORBIT_N = int(os.environ.get("UEPERF_RECON_ORBIT", "6"))

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

S = {"frame": 0, "handle": None, "done": False}


def log(msg):
    unreal.log("[UEPERF-RECON] %s" % msg)


def prop(obj, name, default=None):
    """Property access that never raises - UE class layouts vary by version."""
    try:
        v = getattr(obj, name)
        return v() if callable(v) else v
    except Exception:
        try:
            return obj.get_editor_property(name)
        except Exception:
            return default


def num(v, default=None):
    try:
        return round(float(v), 3)
    except Exception:
        return default


def ground_z(world, x, y):
    """Trace straight down; return the impact Z or None if nothing was hit."""
    hit = unreal.SystemLibrary.line_trace_single(
        world, unreal.Vector(x, y, 30000.0), unreal.Vector(x, y, -10000.0),
        unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,   # Visibility
        True, [], unreal.DrawDebugTrace.NONE, True,
    )
    if not hit:
        return None
    try:
        return float(hit.to_tuple()[4].z)          # impact_point
    except Exception:
        try:
            return float(hit.impact_point.z)
        except Exception:
            return None


def aim_yaw(fx, fy, tx, ty):
    return math.degrees(math.atan2(ty - fy, tx - fx)) % 360.0


def occupied(world, x, y, z, radius=70.0):
    """True if the point is inside geometry - terrain, a prop, or an NPC.

    A line trace cannot detect this: a ray that STARTS inside a collider
    reports no hit, which is exactly how a camera ends up rendering the inside
    of a character's head. A sphere trace reports bStartPenetrating instead.
    """
    try:
        hit = unreal.SystemLibrary.sphere_trace_single(
            world, unreal.Vector(x, y, z), unreal.Vector(x, y, z + 1.0), radius,
            unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,
            True, [], unreal.DrawDebugTrace.NONE, True,
        )
    except Exception:
        return False
    if not hit:
        return False
    t = hit.to_tuple()
    return bool(t[0]) or bool(t[1])       # blocking_hit or initial_overlap


def blocked_yaws(world, x, y, z, yaws, dist):
    """How many of these view directions hit something within `dist`."""
    n = 0
    for yaw in yaws:
        r = math.radians(yaw)
        end = unreal.Vector(x + dist * math.cos(r), y + dist * math.sin(r), z)
        hit = unreal.SystemLibrary.line_trace_single(
            world, unreal.Vector(x, y, z), end,
            unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,
            True, [], unreal.DrawDebugTrace.NONE, True,
        )
        if hit:
            n += 1
    return n


def clear_eye_z(world, x, y, gz, yaws):
    """Pick the lowest eye height at this XY that is neither inside geometry
    nor hemmed in on most sides. Returns None if nothing works."""
    for lift in (EYE, EYE + 110.0, EYE + 240.0, EYE + 420.0):
        z = gz + lift
        if occupied(world, x, y, z):
            continue
        if blocked_yaws(world, x, y, z, yaws, 700.0) > len(yaws) - 3:
            continue                      # walled in; nothing to look at
        return z
    return None


# --------------------------------------------------------------------------
# analysis
# --------------------------------------------------------------------------
def survey(world, actors):
    classes = {}
    starts, lights, fog, niagara, decals, pp, other = [], [], [], [], [], [], []

    for a in actors:
        cls = a.get_class().get_name()
        classes[cls] = classes.get(cls, 0) + 1
        try:
            loc = a.get_actor_location()
            pos = [num(loc.x), num(loc.y), num(loc.z)]
        except Exception:
            pos = None

        low = cls.lower()

        if isinstance(a, unreal.PlayerStart):
            rot = a.get_actor_rotation()
            starts.append({"name": a.get_actor_label(), "class": cls,
                           "pos": pos, "yaw": num(rot.yaw)})

        # Lights: native ALight subclasses and anything BP-named like a light.
        lc = None
        try:
            lc = a.get_component_by_class(unreal.LightComponent)
        except Exception:
            lc = None
        if lc is not None:
            lights.append({
                "name": a.get_actor_label(), "class": cls, "pos": pos,
                "comp": lc.get_class().get_name(),
                "mobility": str(prop(lc, "mobility", "")),
                "intensity": num(prop(lc, "intensity")),
                "attenuation": num(prop(lc, "attenuation_radius")),
                "cast_shadows": bool(prop(lc, "cast_shadows", False)),
                "cast_volumetric_shadow": bool(prop(lc, "cast_volumetric_shadow", False)),
                "volumetric_scattering": num(prop(lc, "volumetric_scattering_intensity")),
                "light_shafts": bool(prop(lc, "light_shaft_bloom", False)),
                "cast_ray_traced_shadow": bool(prop(lc, "cast_ray_traced_shadow", False)),
            })
        elif "light" in low and not isinstance(a, unreal.PlayerStart):
            lights.append({"name": a.get_actor_label(), "class": cls,
                           "pos": pos, "comp": "(blueprint)"})

        if isinstance(a, unreal.ExponentialHeightFog):
            c = a.get_component_by_class(unreal.ExponentialHeightFogComponent)
            fog.append({
                "name": a.get_actor_label(), "class": cls, "pos": pos,
                "volumetric": bool(prop(c, "volumetric_fog", False)),
                "vol_distance": num(prop(c, "volumetric_fog_distance")),
                "vol_quality": num(prop(c, "volumetric_fog_grid_pixel_size")),
            })
        elif isinstance(a, unreal.PostProcessVolume):
            entry = {"name": a.get_actor_label(), "class": cls, "pos": pos,
                     "unbound": bool(prop(a, "unbound", False)),
                     "enabled": bool(prop(a, "enabled", True))}
            entry.update(pp_settings(a))
            pp.append(entry)
        elif "fog" in low or "atmosphe" in low or "cloud" in low:
            fog.append({"name": a.get_actor_label(), "class": cls, "pos": pos})

        try:
            ncs = a.get_components_by_class(unreal.NiagaraComponent)
        except Exception:
            ncs = []
        if ncs:
            systems = []
            for nc in ncs:
                asset = prop(nc, "asset")
                systems.append(asset.get_name() if asset else "?")
            niagara.append({"name": a.get_actor_label(), "class": cls,
                            "pos": pos, "count": len(ncs), "systems": systems})

        try:
            dcs = a.get_components_by_class(unreal.DecalComponent)
        except Exception:
            dcs = []
        if dcs:
            decals.append({"name": a.get_actor_label(), "class": cls,
                           "pos": pos, "count": len(dcs)})

    return {
        "classes": classes, "player_starts": starts, "lights": lights,
        "fog": fog, "niagara": niagara, "decals": decals, "postprocess": pp,
        "other": other,
    }



# Property spellings differ between UE versions and between the struct field and
# its bOverride_ companion, so probe several and report whatever answers.
PP_FIELDS = [
    ("gi_method", ["dynamic_global_illumination_method"]),
    ("gi_override", ["b_override_dynamic_global_illumination_method",
                     "bOverride_DynamicGlobalIlluminationMethod"]),
    ("reflection_method", ["reflection_method"]),
    ("reflection_override", ["b_override_reflection_method",
                             "bOverride_ReflectionMethod"]),
    ("motion_blur_amount", ["motion_blur_amount"]),
    ("motion_blur_override", ["b_override_motion_blur_amount",
                              "bOverride_MotionBlurAmount"]),
    ("lumen_reflection_quality", ["lumen_reflection_quality"]),
    ("bloom_intensity", ["bloom_intensity"]),
]


def pp_settings(volume):
    """Read the renderer-relevant fields off a PostProcessVolume's settings."""
    out = {}
    try:
        st = volume.get_editor_property("settings")
    except Exception as exc:  # noqa: BLE001
        return {"settings_error": str(exc)}
    for key, names in PP_FIELDS:
        val = None
        for n in names:
            try:
                val = st.get_editor_property(n)
                break
            except Exception:
                continue
        if val is not None:
            out[key] = str(val) if not isinstance(val, (int, float, bool)) else val
    return out


def playspace(info, ref):
    """Best guess at where players actually stand, in XY."""
    pts = [s["pos"][:2] for s in info["player_starts"] if s.get("pos")]
    if ref:
        pts.append(ref[:2])
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    half = max(max(xs) - min(xs), max(ys) - min(ys)) / 2.0
    return {"center": [round(cx, 2), round(cy, 2)],
            "half_extent": round(half, 2), "samples": len(pts)}


# --------------------------------------------------------------------------
# cameras
# --------------------------------------------------------------------------
def build_cameras(world, ps, ref):
    cams, misses = [], []
    cx, cy = ps["center"]
    r = RING_R if RING_R > 0 else max(2200.0, ps["half_extent"] * 0.85)
    fan_yaws = [45.0 * i for i in range(8)]

    # Reference ground level, from the spawn. Ring positions whose traced
    # ground sits far below this are pits and voids under the play space -
    # a camera there renders the underside of the map.
    starts = [s for s in info["player_starts"] if s.get("pos")]
    ref_ground = ground_z(world, starts[0]["pos"][0], starts[0]["pos"][1]) if starts else None
    if ref_ground is None:
        ref_ground = ground_z(world, cx, cy)
    MAX_DROP = 900.0

    # The exact vantage the baseline stats were taken from, so at least one
    # pair is directly comparable against the numbers already on record.
    if ref:
        cams.append({"name": "ref_stat", "x": round(ref[0], 3), "y": round(ref[1], 3),
                     "z": round(ref[2], 3), "pitch": round(ref[3], 3),
                     "yaw": round(ref[4], 3), "roll": 0.0})

    # Aerial orbit - whole-level look, catches fog and skyline changes.
    orbit_r = max(r * 1.5, 4000.0)
    gz = ground_z(world, cx, cy)
    base = gz if gz is not None else 0.0
    for i in range(ORBIT_N):
        a = (360.0 / ORBIT_N) * i
        px = cx + orbit_r * math.cos(math.radians(a))
        py = cy + orbit_r * math.sin(math.radians(a))
        cams.append({
            "name": "orbit%d" % i,
            "x": round(px, 3), "y": round(py, 3),
            "z": round(base + orbit_r * 0.8, 3),
            "pitch": -34.0, "yaw": round(aim_yaw(px, py, cx, cy), 4), "roll": 0.0,
        })

    # Eye-level fans: a full circle of yaws from each vantage the level itself
    # endorses - every PlayerStart, plus the reference view. NPCs stand on the
    # spawn point, so the height is chosen by clearance rather than assumed.
    origins = [(s["pos"][0], s["pos"][1], "s%d" % i) for i, s in enumerate(starts[:3])]
    if ref:
        origins.append((ref[0], ref[1], "ref"))

    for ox, oy, tag in origins:
        gz = ground_z(world, ox, oy)
        if gz is None:
            misses.append("fan_%s:no_ground" % tag)
            continue
        z = clear_eye_z(world, ox, oy, gz, fan_yaws)
        if z is None:
            misses.append("fan_%s:no_clear_height" % tag)
            continue
        for yaw in fan_yaws:
            cams.append({
                "name": "eye_%s_%03d" % (tag, int(yaw)),
                "x": round(ox, 3), "y": round(oy, 3), "z": round(z, 3),
                "pitch": -3.0, "yaw": round(yaw, 4), "roll": 0.0,
            })

    # Ring - each valid position looks inward across the play space and
    # outward at the background, which is where fog and skybox changes read.
    for i in range(RING_N):
        a = (360.0 / RING_N) * i
        px = cx + r * math.cos(math.radians(a))
        py = cy + r * math.sin(math.radians(a))
        gz = ground_z(world, px, py)
        if gz is None:
            misses.append("ring%02d:no_ground" % i)
            continue
        if ref_ground is not None and gz < ref_ground - MAX_DROP:
            misses.append("ring%02d:below_play_space(%.0f)" % (i, gz))
            continue
        z = clear_eye_z(world, px, py, gz, fan_yaws)
        if z is None:
            misses.append("ring%02d:no_clear_height" % i)
            continue
        inward = aim_yaw(px, py, cx, cy)
        cams.append({"name": "eye_in_%02d" % i, "x": round(px, 3), "y": round(py, 3),
                     "z": round(z, 3), "pitch": -4.0,
                     "yaw": round(inward, 4), "roll": 0.0})
        cams.append({"name": "eye_out_%02d" % i, "x": round(px, 3), "y": round(py, 3),
                     "z": round(z, 3), "pitch": 3.0,
                     "yaw": round((inward + 180.0) % 360.0, 4), "roll": 0.0})

    return cams, misses, r


info = {}


def run(world):
    global info
    actors = eas.get_all_level_actors()
    info = survey(world, actors)
    info["world"] = world.get_name()
    info["actor_count"] = len(actors)

    try:
        info["is_partitioned"] = bool(world.get_editor_property("is_partitioned_world"))
    except Exception:
        info["is_partitioned"] = None

    ref = None
    if REF:
        try:
            ref = [float(v) for v in REF.split(",")]
        except Exception:
            ref = None
    info["reference_view"] = ref

    ps = playspace(info, ref)
    info["playspace"] = ps

    cams, misses, r = ([], [], 0.0)
    if ps:
        cams, misses, r = build_cameras(world, ps, ref)
    info["camera_ring_radius"] = round(r, 2)
    info["camera_misses"] = misses
    info["camera_count"] = len(cams)

    if INFO_OUT:
        with open(INFO_OUT, "w") as fh:
            json.dump(info, fh, indent=1, sort_keys=True)
    if CAMS_OUT:
        with open(CAMS_OUT, "w") as fh:
            json.dump(cams, fh, indent=1)

    top = sorted(info["classes"].items(), key=lambda kv: -kv[1])[:12]
    log("actors=%d partitioned=%s starts=%d lights=%d fog=%d niagara=%d decals=%d"
        % (info["actor_count"], info["is_partitioned"], len(info["player_starts"]),
           len(info["lights"]), len(info["fog"]), len(info["niagara"]),
           len(info["decals"])))
    log("top classes: %s" % ", ".join("%s=%d" % kv for kv in top))
    log("cameras=%d ring_r=%.0f misses=%s"
        % (len(cams), r, ", ".join(misses) if misses else "none"))
    log("wrote %s" % INFO_OUT)


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
        # Let streaming and physics settle so traces hit real collision.
        if S["frame"] < 180:
            return
        S["done"] = True
        run(world)
        unreal.unregister_slate_post_tick_callback(S["handle"])
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:  # noqa: BLE001 - never wedge the editor
        S["done"] = True
        log("FAILED: %s" % exc)
        unreal.SystemLibrary.quit_editor()


S["handle"] = unreal.register_slate_post_tick_callback(tick)
log("armed: map=%s ring=%d orbit=%d eye=%.0f ref=%s"
    % (MAP_NAME, RING_N, ORBIT_N, EYE, REF or "none"))
