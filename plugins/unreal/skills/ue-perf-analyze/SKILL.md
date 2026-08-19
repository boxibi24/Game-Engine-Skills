---
name: ue-perf-analyze
description: Diagnose what is actually costing frame time in an Unreal Engine project and propose ranked, reversible optimizations. Use this whenever someone shares UE stat output (stat unit, stat gpu, stat scenerendering, stat game), asks why their level or game is slow, asks what to turn off to hit a frame rate target, mentions Lumen, Nanite, ray tracing, virtual shadow maps, volumetric fog, translucency or draw call costs, or wants a competitive/high-refresh frame budget. Use it before changing any render setting, so the change is aimed at a measured cost rather than a guess.
---

# Finding what actually costs the frame

The goal is to spend effort where the time is. Unreal makes that tractable
because the stat commands attribute cost fairly precisely — the discipline is to
read them in the right order and resist changing things that are not on the
critical path.

Start from a baseline captured under controlled conditions. If you do not have
one, or you are unsure the frame rate was uncapped, use the `ue-perf-baseline`
skill first — analysis of a cap-limited capture will send you after phantom
costs, because everything looks like it fits in the budget when the engine is
idling to hit a limiter.

## Step 1: find which thread is the bottleneck

`stat unit` gives the whole story at the top level:

| Reading | Meaning |
|---|---|
| `Frame` ≈ `GPU`, both >> `Game`/`Draw` | GPU bound — attack render cost |
| `Frame` ≈ `Game` | game-thread bound — ticks, blueprints, AI, physics |
| `Frame` ≈ `Draw` | render-thread bound — usually draw call submission or state changes |
| `RHIT` high | RHI thread — command translation, often driven by draw count or acceleration-structure rebuilds |
| `Frame` >> all of them | not bound by work at all — a cap. Go back to the baseline skill |

Only after this is settled does per-pass detail mean anything. Optimizing GPU
passes on a game-thread-bound project changes nothing you can measure.

## Step 2: attribute the cost

Read `references/cost-centers.md` for how to map specific `stat gpu` and
`stat scenerendering` rows to their causes, what each typically costs, and what
turning it off actually does to the image. That file is the substance of this
skill — consult it rather than working from memory, because the mapping from
pass name to underlying feature is not always obvious (`RenderDeferredLighting`
and `LumenSceneLighting` are different things with different fixes).

Read `references/config-knobs.md` for the specific settings, their valid values
and where they live.

Two counters deserve attention because they are cheap to check and often
enormous:

- **Ray tracing instances.** `stat scenerendering` reports `Ray tracing active
  instances` and `Ray tracing dynamic update primitives`. If ray tracing is
  enabled project-wide but nothing consumes it — Lumen configured for software
  tracing, no ray-traced shadows or reflections — the project pays acceleration
  structure builds, shader permutations and memory for no visual return. A count
  in the hundreds of thousands of dynamic update primitives is a strong signal.
- **Lights in scene.** A handful of shadow-casting lights with volumetric
  scattering enabled can dominate `Shadow Depths` and `VolumetricFog`. Blueprint
  actors that wrap a light multiply this quietly — the actor count looks small
  while the light count is large.

## Step 3: rank the candidates

Order by cost recovered against visual risk, and be explicit about the risk. A
useful framing:

1. **Free wins** — cost with no visual consequence. Ray tracing enabled but
   unused. A frame rate cap. Settings that do nothing on the target platform.
2. **Cheap wins** — cost for negligible visual change. Culling distant or
   occluded decorative actors, disabling shadow casting on small props,
   trimming volumetric fog quality.
3. **Trade-offs** — real cost recovered for a real visual change. Lumen GI off,
   reflections downgraded or off, shadow method changes. These need
   before/after imagery and someone's sign-off.
4. **Do not touch without asking** — anything that defines the art direction.
   Post-processing in particular often carries meaningful cost, and cutting it
   is usually the wrong call because it degrades the look everywhere at once.

Present the ranking and let the person decide where to stop. Do not silently
apply a category 3 change because the numbers justified it — the numbers cannot
see the art direction.

## Step 4: make the change reversible and provable

- Change **project config and level content separately**, so a regression can be
  attributed. Config settings are project-wide; actor deletions are per-level.
- Commit the change on its own, with the specific settings and counts in the
  message. A later "why is this off?" is answered by `git log` rather than
  memory.
- Capture before/after imagery from pinned commits with the `ue-perf-shots`
  skill. A per-pair difference measurement across many angles catches
  regressions that spot-checking one screenshot does not — in particular, a
  systematic darkening across every camera is the signature of losing global
  illumination bounce, and it is easy to miss by eye on any single image.
- Re-measure from the same pinned vantage as the baseline.

## Reporting

State what was measured, what changed, and what it cost visually. Keep
view-dependent counters (`Draws`, `Prims`, `Decals in view`) separate from
scene-wide ones (`Lights in scene`, ray-tracing instance counts) — if the
follow-up capture came from a different vantage, only the scene-wide ones
support a claim, and saying so plainly is more useful than a table that quietly
compares two different viewpoints.

Attribute per-item savings only when they were measured in isolation. Turning
off four things at once and dividing the total between them is a guess wearing a
number's clothing.
