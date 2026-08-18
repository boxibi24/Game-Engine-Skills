# Mapping stat rows to causes

How to read specific rows from `stat gpu` and `stat scenerendering`, what drives
them, and what turning them off does to the image.

- [Global illumination and reflections](#global-illumination-and-reflections)
- [Ray tracing](#ray-tracing)
- [Shadows](#shadows)
- [Translucency, fog and particles](#translucency-fog-and-particles)
- [Geometry and draw submission](#geometry-and-draw-submission)
- [Post-processing and upscaling](#post-processing-and-upscaling)
- [Game thread](#game-thread)
- [Reading a pass list that changed](#reading-a-pass-list-that-changed)

---

## Global illumination and reflections

**Rows:** `LumenSceneUpdate`, `LumenSceneLighting`, `LumenScreenProbeGather`,
`LumenReflections`. Lumen spans both the graphics and compute queues, so add
both — reading only the graphics queue understates it substantially.

**Driven by:** scene complexity, number of emissive and lit surfaces, Lumen
quality settings, and whether it runs hardware or software tracing.

**Alternatives, in descending cost and quality:**

| GI method | Reflection method | Character |
|---|---|---|
| Lumen | Lumen | Dynamic bounce and accurate reflections. Most expensive. |
| Lumen | Screen Space | Keeps bounce, cheaper reflections that miss offscreen detail. |
| None | Screen Space | No bounce. Shadowed areas fall back to skylight ambient. |
| None | None | Cheapest. Reflective surfaces lose their character entirely. |

**Visual consequence of disabling GI:** surfaces not in direct light lose their
fill and go noticeably darker. Expect a systematic luminance drop across every
camera, not a localized change. Interiors, overhangs and anything in shadow are
hit hardest.

**Visual consequence of disabling reflections:** wet, icy, polished and metallic
surfaces flatten. Screen-space reflections are a genuine middle ground and
typically cost far less than Lumen reflections — worth measuring before jumping
straight to `None`.

When GI is disabled, `ScreenSpace AO`, `SkyLightDiffuse` and `Reflection
Environment` appear in their place. Seeing those rows arrive is confirmation the
setting actually took effect.

---

## Ray tracing

**Rows:** `RayTracingScene`, `RayTracingDynamicGeometry`, `Finish Gather Ray
Tracing Instances`, `Wait RayTracing Dynamic Bindings`.

**Counters:** `Ray tracing active instances`, `Ray tracing total instances`,
`Ray tracing dynamic update primitives`, `Ray tracing dynamic build primitives`.

The counters matter more than the GPU rows. Acceleration structures are rebuilt
per frame for dynamic geometry, and that cost lands on the render and RHI
threads as much as the GPU. Hundreds of thousands of dynamic update primitives
per frame is a large hidden cost that does not show up as one obvious expensive
GPU pass.

**The common free win:** ray tracing enabled project-wide while nothing consumes
it. Lumen defaults to software tracing in many configurations, and if there are
no ray-traced shadows, reflections or ambient occlusion, the whole subsystem is
overhead. Confirm nothing depends on it, then disable it.

**Confirming it is off:** active and total instances go to `0.00`, and the
dynamic-primitive rows disappear from the counter list entirely.

---

## Shadows

**Rows:** `Shadow Depths`, `Shadow Projection`, `Virtual Shadow Maps`.

**Driven by:** the number of shadow-casting lights, their attenuation radius,
how much geometry falls inside them, and cascade/VSM settings.

**Where the count hides:** blueprint actors that wrap a light. A level can show
a handful of light actors while `Lights in scene` reports far more, because each
blueprint contributes its own. Check `Lights in scene` in
`stat scenerendering` against the actor count.

**Cheap wins:** turn off shadow casting on small props and decorative lights;
reduce attenuation radius so fewer objects fall inside; disable
`cast_volumetric_shadow` on lights that do not need it.

---

## Translucency, fog and particles

**Rows:** `Translucency`, `Translucent Lighting`, `VolumetricFog`,
`Niagara GPU Ribbons`, `FXSystemPreRender`.

**Translucency** is overdraw-bound: cost scales with how much of the screen the
translucent surfaces cover and how many layers stack. A large number of
camera-facing fog planes or decals is a common culprit, and they are cheap to
count via an actor class histogram.

**Volumetric fog** costs whether or not it is visible from the current camera,
and is driven by `volumetric_fog_distance` and the grid pixel size on the height
fog component, plus `volumetric_scattering_intensity` on each light.

**Niagara** GPU cost scales with particle count and emitter complexity.
Ambient/decorative systems that are always resident are worth auditing —
per-instance cost is low, but instance counts creep up.

---

## Geometry and draw submission

**Rows:** `Basepass`, `Prepass`, `Nanite VisBuffer`, `Nanite BasePass`,
`Nanite Readback`.

**Counters:** `Draws`, `Prims`, `Mesh draw calls`.

High `Draws` with low GPU time points at a render-thread bottleneck rather than
a GPU one — the cost is submission, not rasterization. Instancing, HLODs and
merging static geometry address that; shrinking materials or textures does not.

Nanite changes the calculus: triangle count matters far less, but Nanite has its
own fixed overhead, so it is not automatically the right choice for simple
geometry.

`Decals in scene` versus `Decals in view` distinguishes authoring cost from
per-frame cost. A large scene count with a small view count is mostly harmless;
a large view count is real overdraw.

---

## Post-processing and upscaling

**Rows:** `Postprocessing`, `TemporalSuperResolution`, `MotionBlur`,
`LensFlare`, `Bloom`, `SkyAtmosphereLUTs`.

Post-processing frequently shows up among the most expensive passes, which makes
it a tempting target. Resist it. It defines the look everywhere at once, and
cutting it degrades every frame of the game rather than one feature. Treat it as
off-limits unless whoever owns the art direction asks for it.

`RenderRes` in the overlay shows what resolution is actually being rendered.
Upscalers mean this is often well below output resolution — and it must match
between two captures or the comparison is meaningless.

---

## Game thread

**Rows (from `stat game`):** `World Tick Time`, `Tick Time`, `Blueprint Time`,
`Char Movement Total`, `PlayerController Tick`, `GT Tickable Time`.

High `Blueprint Time` with a high call count usually means many actors ticking
every frame. Fixes: disable tick on actors that do not need it, lower tick
intervals, move hot logic to C++, or use the significance manager to scale work
by distance.

---

## Reading a pass list that changed

When comparing two `stat gpu` captures, the disappearance and appearance of
whole rows is stronger evidence than any individual timing. Timings shift with
the camera; the presence of a pass is structural.

If `LumenReflections` is gone and `Reflection Environment` has appeared, the
reflection method genuinely changed. If ray-tracing instance counts are zero and
their counter rows have vanished, ray tracing is genuinely off. Those hold even
when the two captures came from different vantages, which makes them the honest
evidence when the viewpoints do not match exactly.
