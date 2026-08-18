# Settings reference

Where the relevant settings live and what their values mean. Verify against the
engine version in use — defaults and available values do shift between releases.

## Renderer

`Config/DefaultEngine.ini`, section `[/Script/Engine.RendererSettings]`:

| Setting | Values | Notes |
|---|---|---|
| `r.DynamicGlobalIlluminationMethod` | `0` None, `1` Lumen, `2` Screen Space | `0` removes bounce light; shadowed areas fall back to skylight ambient |
| `r.ReflectionMethod` | `0` None, `1` Lumen, `2` Screen Space | `2` is the middle ground and usually much cheaper than `1` |
| `r.RayTracing` | `True` / `False` | Project-wide. Disabling removes acceleration-structure builds and shader permutations |
| `r.RayTracing.RayTracingProxies.ProjectEnabled` | `True` / `False` | Turn off alongside `r.RayTracing` |
| `r.Shadow.Virtual.Enable` | `0` / `1` | Virtual shadow maps; interacts with Nanite |
| `r.AllowStaticLighting` | `True` / `False` | `False` commits to fully dynamic lighting |
| `r.GenerateMeshDistanceFields` | `True` / `False` | Required by some Lumen and shadow features; disabling saves memory and build time but breaks anything depending on it |
| `r.DefaultFeature.MotionBlur` | `True` / `False` | Project default; a PostProcessVolume can still override per-level |
| `r.DefaultFeature.AutoExposure` | `True` / `False` | Affects perceived brightness in comparisons |

Changing GI, reflection or ray-tracing settings triggers a shader recompile on
the next editor launch. Do not measure until it finishes.

## Frame rate limiting

`Config/DefaultEngine.ini`, section `[/Script/Engine.Engine]`:

| Setting | Notes |
|---|---|
| `bSmoothFrameRate` | `False` removes the smoothing clamp. Its upper bound defaults to 62 FPS, so a smoothing-limited frame time reads ~16.13 ms, not 16.67 ms |
| `SmoothedFrameRateRange` | The clamp range itself |
| `bUseFixedFrameRate` / `FixedFrameRate` | Hard fixed-step; rare outside deterministic simulation |

`Saved/Config/<Platform>/GameUserSettings.ini`:

| Setting | Notes |
|---|---|
| `FrameRateLimit` | `0` means uncapped |
| `bUseVSync` | Presents at display refresh; exactly 16.67 ms means a 60 Hz cap |
| `FrameRateLimit_OnBattery` / `_InMenu` / `_WhenBackgrounded` | Lyra-derived projects add these; the battery one should not apply on a desktop but is worth ruling out when it is the only 60 in the file |

A saved config can shadow a project setting, so a value in `DefaultEngine.ini`
is not proof of what is active at runtime. Check `Saved/Config/` too, along with
any `[ConsoleVariables]` section.

## Useful console commands

Runtime, for confirming a diagnosis without editing files:

```
r.VSync 0
t.MaxFPS 0
r.ScreenPercentage 100
r.Lumen.DiffuseIndirect.Allow 0
r.RayTracing.ForceAllRayTracingEffects 0
```

Measurement and navigation:

```
stat unit
stat fps
stat gpu
stat scenerendering
stat game
BugItGo <x> <y> <z> <pitch> <yaw> <roll>
HighResShot 1920x1080
```

`BugItGo` takes the six numbers in the same order the stat overlay prints them
as `Loc=` and `Rot=`, with pitch first in the rotation and shown in 0-360 form
(`354.9` is `-5.1`).

## Level-side costs

Not settings, but the level-content equivalents worth auditing. Get counts from
an actor class histogram — the `ue-perf-shots` skill's `recon.py` produces one,
along with a light inventory showing shadow casting and volumetric scattering
per light.

| Thing | Why it costs | Cheap mitigation |
|---|---|---|
| Camera-facing fog / smoke planes | Translucent overdraw | Cull decorative instances, reduce coverage |
| Shadow-casting point/spot/rect lights | `Shadow Depths` scales with them | Disable shadow casting on decorative lights, cut attenuation radius |
| Lights with volumetric scattering | Feeds `VolumetricFog` whether visible or not | Set scattering intensity to 0 where not needed |
| Decals | Overdraw when in view | Compare `Decals in view` against `Decals in scene` |
| Always-on Niagara systems | Constant GPU and tick cost | Audit ambient/decorative emitters |
| Actors ticking every frame | `Blueprint Time` | Disable tick, raise tick interval, or use significance |

Blueprint actors that wrap lights are the usual reason `Lights in scene` far
exceeds the visible light-actor count.
