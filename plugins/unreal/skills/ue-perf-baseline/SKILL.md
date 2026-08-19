---
name: ue-perf-baseline
description: Capture a trustworthy Unreal Engine performance baseline before optimizing anything - which stat commands to run, how to pin a repeatable camera vantage, and how to prove the frame rate is not being artificially capped. Use this whenever someone shares UE stat screenshots or numbers, says a level or game runs slow, asks about FPS, frame time, ms per frame, GPU time, draw calls or hitching, wants to profile or measure an Unreal project, or is about to change render settings for performance. Use it BEFORE proposing any optimization, because an unreproducible or cap-limited baseline makes every later comparison meaningless.
---

# Capturing a performance baseline that means something

An optimization is only provable against a baseline you can reproduce. Most
wasted profiling effort comes from measuring under conditions that quietly
differ between the before and after run, so establish those conditions first.

## Get the conditions right before reading any number

**Let shaders finish compiling.** Changing renderer settings — ray tracing,
Lumen, reflections, shadow method — changes shader permutations and triggers a
recompile. Anything measured while the compile counter is ticking is inflated on
both the game thread and RHI thread. Wait for it to reach zero.

**Pin the vantage.** Frame cost varies enormously across a level. A number from
"roughly where I was standing" is not comparable to anything. The stat overlay
prints the camera as `Loc=(x, y, z) Rot=(pitch, yaw, roll)`; record those six
numbers, and return to them exactly with:

```
BugItGo <x> <y> <z> <pitch> <yaw> <roll>
```

Note the ordering: `Rot=` displays pitch first, and pitch is shown in the
0-360 form, so `354.9` is `-5.1`.

**Note how it is being run.** PIE, standalone and a packaged build differ
substantially — PIE carries editor overhead, and a packaged Development build
differs again from Shipping. Record which one, and compare like with like.

## Confirm the frame rate is not capped

This is the step people skip, and it invalidates everything downstream. If frame
time sits at a suspiciously round value while GPU and game thread times are much
lower, the engine is idling against a limiter and you are measuring the limiter,
not the project.

Compare the numbers against each other. If `Frame` is 16.67 ms while `GPU` is
8.4 ms and `Game` is 8.0 ms, roughly 8 ms per frame is idle — the work would
support far more frames than are being delivered.

Distinguishing which limiter is responsible is possible from the number alone:

| Frame time | Implies |
|---|---|
| exactly 16.67 ms | 60.000 Hz — vsync or a display/driver cap |
| ~16.13 ms | 62 FPS — engine frame smoothing (`SmoothedFrameRateRange` upper bound defaults to 62, not 60) |
| some other round value | an explicit `t.MaxFPS` or `FrameRateLimit` |

That 62-versus-60 distinction is genuinely useful: it tells you whether to go
looking in the project config or at the display.

Check, in order:

1. `Config/DefaultEngine.ini` under `[/Script/Engine.Engine]` for
   `bSmoothFrameRate` and `bUseFixedFrameRate`.
2. `Saved/Config/<Platform>/GameUserSettings.ini` for `FrameRateLimit`,
   `bUseVSync`, and the variants some projects add (`FrameRateLimit_OnBattery`,
   `_InMenu`, `_WhenBackgrounded`). A desktop should not apply the battery
   limit, but it is worth ruling out when it is the only 60 in the file.
3. Any `[ConsoleVariables]` section, and `Saved/Config/` generally — a saved
   config can shadow a project setting, so a value in `DefaultEngine.ini` is not
   proof of what is actually active.
4. In session: `r.VSync 0` and `t.MaxFPS 0`, then re-read. If frame time drops,
   that was it.

To remove engine frame smoothing project-wide, set `bSmoothFrameRate=False`
under `[/Script/Engine.Engine]` in `Config/DefaultEngine.ini`.

## What to capture

Run these and screenshot or record each:

| Command | What it gives you |
|---|---|
| `stat unit` | Frame, Game, Draw, GPU, RHIT — the top-level split that tells you what to blame |
| `stat fps` | frame rate alongside frame time |
| `stat gpu` | per-pass GPU cost on the graphics and compute queues |
| `stat scenerendering` | render-thread breakdown plus scene-wide counters (lights, decals, ray-tracing instances, mesh draw calls) |
| `stat game` | game-thread breakdown — tick, blueprint, character movement |

Also record from the overlay: `Draws`, `Prims`, `Mem`, and `RenderRes` (the
resolution actually being rendered — upscalers mean this is often well below the
output resolution, and it must match between runs).

For a deeper capture, `Unreal Insights` via `-trace=default` gives a timeline
rather than averages. Reach for it when the `stat` numbers are stable but you
need to explain a spike or a hitch, since averages hide those by construction.

## Record it so it can be compared

Write the baseline down with everything needed to reproduce it — vantage,
run mode, resolution, engine version, and any caps found. A number without those
cannot be compared to a later number, and you will not remember them.

Note which counters are view-dependent and which are scene-wide, because it
changes what a later comparison can claim. `Draws`, `Prims`, `Decals in view`
and `Mesh draw calls` all change if the camera moves even slightly. `Lights in
scene`, `Decals in scene` and `Ray tracing total instances` do not — those stay
comparable even if the vantage drifts, which makes them the honest evidence when
a follow-up capture was taken from a different spot.

## Next

With a baseline in hand, use the `ue-perf-analyze` skill to work out what is
actually costing the time, and `ue-perf-shots` to capture before/after imagery
proving what the change did to the look.
