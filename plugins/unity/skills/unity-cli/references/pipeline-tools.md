# Pipeline tool catalog (com.unity.pipeline 0.5.0-exp.1)

142 tools, verified 2026-08-24. Regenerate with `unity list --json`.

Conventions seen across the set:

- Destructive tools require `confirm=true` and usually accept `dry_run=true`.
- Async tools return `in_progress`; poll the matching `*_status` tool.
- GameObjects/assets are addressed by an opaque handle (`objectref`): `globalId`, `guid`, `instanceId`, or `hierarchyPath`. Prefer `globalId`.
- Writes are confined to the *authoring root* (`get_authoring_root` / `set_authoring_root`), which defaults to a subfolder of `Assets/`. Set it to `Assets` for full project access.

## Scene/GameObject (27)

- `add_animator_layer` — Add a layer to an AnimatorController.
  - **required:** `controller`, `name` · optional: `weight`, `blendingMode`, `dry_run`
- `add_scene_to_build` — Add a scene to the Build Settings scene list (idempotent). Optionally enable it.
  - **required:** `path` · optional: `enabled`
- `capture_scene_view` — Render the active Scene View to a PNG. Returns it inline as base64, unless save_path is set (path-only result; pass include_inline_image=true to get both).
  - optional: `width`, `height`, `save_path`, `include_inline_image`, `max_resolution`
- `create_gameobject` — Create an empty GameObject or a built-in primitive (cube/sphere/capsule/cylinder/plane/quad) in the active scene.
  - optional: `name`, `primitive`, `parent`
- `create_gameobjects` — Batch-create N empty GameObjects or primitives in one call. Optional positions/rotations/scales are arrays of [x,y,z] (length must equal count). Returns the created identities.
  - optional: `name`, `primitive`, `parent`, `count`, `positions`, `rotations`, `scales`
- `create_scene` — Create a new scene and save it to the given path under the authoring root.
  - **required:** `path` · optional: `additive`, `template`
- `delete_gameobject` — Delete a GameObject from the scene (reversible via Undo).
  - **required:** `target`
- `find_gameobjects` — Find GameObjects in loaded scenes by name, tag, component type, and/or hierarchy path (filters are combined). Returns structured identities.
  - optional: `name`, `tag`, `type`, `hierarchy_path`, `include_inactive`
- `get_player_settings` — Read PlayerSettings (company/product/version, scripting backend, API level).
- `get_scene_hierarchy` — Return the GameObject tree of an open scene (or the active scene). Each node carries instanceId + hierarchyPath usable by GameObject commands.
  - optional: `path`
- `get_selection` — Read the current Editor selection as structured object identities.
- `get_tags_layers` — Read the project's tags and (named) layers.
- `instantiate_prefab` — Instantiate a prefab asset into a loaded scene and return the created instance.
  - **required:** `prefab` · optional: `scene_path`, `name`
- `list_open_scenes` — List all currently open scenes with their load/active/dirty state.
- `open_scene` — Open an existing scene from the given path.
  - **required:** `path` · optional: `additive`
- `remove_scene_from_build` — Remove a scene from the Build Settings scene list (idempotent).
  - **required:** `path`
- `rename_gameobject` — Rename a GameObject.
  - **required:** `target`, `name`
- `save_scene` — Save an open scene. Saves the active scene when no path is given.
  - optional: `path`
- `set_active` — Set a GameObject's active self-state (activeSelf).
  - **required:** `target`, `active`
- `set_active_scene` — Set which open scene is the active scene (new objects are created in the active scene).
  - **required:** `path`
- `set_layer` — Set a GameObject's layer by name or numeric index (0-31).
  - **required:** `target`, `layer`
- `set_parent` — Reparent a GameObject under a new parent, or detach it to scene root when no parent is given.
  - **required:** `target` · optional: `parent`, `world_position_stays`
- `set_player_settings` — Change PlayerSettings. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z. Scripting backend / API level changes trigger a domain reload.
  - optional: `settings`, `confirm`, `dry_run`
- `set_selection` — Set the Editor selection to the given assets/scene objects.
  - optional: `instance_ids`, `paths`
- `set_tag` — Set a GameObject's tag (the tag must already exist in the project).
  - **required:** `target`, `tag`
- `set_tags_layers` — Add/remove tags and assign user layer names (index 8-31). Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_transform` — Set a GameObject's local position/rotation(euler)/scale. Omitted channels are left unchanged.
  - **required:** `target` · optional: `position`, `rotation`, `scale`

## Prefab (6)

- `apply_prefab_overrides` — Apply a prefab instance's overrides back to its source prefab asset.
  - **required:** `instance`
- `create_prefab` — Save a GameObject as a prefab asset at a project path; the source becomes a connected instance.
  - **required:** `source`, `path`
- `create_prefab_variant` — Create a prefab variant asset that inherits from a base prefab.
  - **required:** `base`, `path`
- `revert_prefab_overrides` — Revert a prefab instance's overrides so it matches its source prefab asset.
  - **required:** `instance`
- `save_prefab_contents` — Open a prefab asset in an isolated prefab stage, apply a declarative edit, and save it back (nested-prefab safe).
  - **required:** `prefab` · optional: `rename_child`, `new_name`, `set_active_child`, `active`
- `unpack_prefab` — Unpack a prefab instance into plain GameObjects (outermost level or completely).
  - **required:** `instance` · optional: `completely`

## Component/Serialization (6)

- `add_component` — Add a component (by type name) to a GameObject.
  - **required:** `target`, `type`
- `get_component_properties` — Get a component's serialized properties as a JSON map. Address the component by handle, or by GameObject handle + type.
  - **required:** `target` · optional: `type`
- `get_serialized_fields` — Read serialized fields of a component/asset. Returns each top-level field's name, type and value (object references are returned as re-usable handles). Pass 'field' to read a single SerializedProperty path.
  - **required:** `target` · optional: `field`, `component`
- `remove_component` — Remove a component from a GameObject. Provide either a component handle (target) or a GameObject handle (target) plus a type name.
  - **required:** `target` · optional: `type`
- `set_component_properties` — Set serialized properties on a component (one Undo step). 'properties' maps property name -> value; object references accept an ObjectRef handle.
  - **required:** `target`, `properties` · optional: `type`
- `set_serialized_field` — Set a serialized field on a component/asset. Supports primitives, enums, Vector/Color/Rect/Bounds, object references (value = an ObjectRef: asset by guid/fileId/path or scene object by instanceId/hierarchyPath), and array elements via 'name.Array.data[i]' (or 'name.Array.size' to resize).
  - **required:** `target`, `field`, `value` · optional: `component`

## Asset (14)

- `copy_asset` — Copy an asset to a new path under the authoring root. The copy gets a fresh GUID.
  - **required:** `asset`, `destination` · optional: `confirm`, `dry_run`
- `create_asset` — Create a new ScriptableObject (or other UnityEngine.Object) asset of the given type at a path under the authoring root.
  - **required:** `path`, `type` · optional: `shader`, `confirm`, `dry_run`
- `create_folder` — Create a folder under the authoring root (creates intermediate folders).
  - **required:** `path`
- `delete_asset` — Delete an asset from the project. Destructive: requires confirm=true.
  - **required:** `asset` · optional: `confirm`, `dry_run`
- `find_assets` — Find assets by type and/or name and/or label, returning their path, GUID and type. At least one filter is required.
  - optional: `type`, `name`, `label`, `search_in`, `limit`
- `get_import_settings` — Read an asset's import settings, structured by importer type (texture/model/audio), including the default-platform fields and (for textures/audio) one platform override block.
  - **required:** `asset` · optional: `platform`
- `import_asset` — Import an external file (e.g. a texture, model, audio clip) into the project by copying it to a path under the authoring root, then importing it.
  - **required:** `source`, `path` · optional: `confirm`, `dry_run`
- `move_asset` — Move (or rename via a new path) an asset to a new location under the authoring root. Preserves the asset's GUID.
  - **required:** `asset`, `destination` · optional: `dry_run`
- `package_search` — Search packages available in the registry. Provide a name (e.g. com.unity.foo) or omit to list all. Returns the full result synchronously (blocks until the registry query completes).
  - optional: `query`, `offline`
- `read_text_file` — Read a UTF-8 text file under the authoring root and return its contents.
  - **required:** `path` · optional: `max_bytes`
- `rename_asset` — Rename an asset in place (keeps it in the same folder, keeps its GUID).
  - **required:** `asset`, `new_name` · optional: `dry_run`
- `search` — Run a Unity Search query and return structured results.
  - **required:** `query` · optional: `limit`
- `set_import_settings` — Set import settings on an asset's AssetImporter (default platform top-level properties, or a texture/audio per-platform override) and re-import it.
  - **required:** `asset`, `settings` · optional: `platform`, `dry_run`
- `write_text_file` — Write UTF-8 text to a file under the authoring root, then import it. Overwriting an existing file requires confirm=true.
  - **required:** `path`, `contents` · optional: `confirm`, `dry_run`

## Script/Compile (8)

- `attach_script` — Add a MonoBehaviour to a GameObject by its (compiled) type name OR by its script asset path. Provide exactly one of 'type' or 'script'. If the type isn't compiled yet, returns a recoverable error: recompile, poll recompile_status, then retry.
  - **required:** `target` · optional: `type`, `script`
- `create_script` — Create a new C# script (default base class MonoBehaviour) from a template under the authoring root. NOTE: the type does not exist until a recompile completes — to attach it, call recompile, poll recompile_status, then attach_script.
  - **required:** `name` · optional: `path`, `namespace`, `base_class`, `overwrite`
- `eval` — Evaluate C# code dynamically using Roslyn compiler
  - **required:** `code` · optional: `timeout`
- `eval_file` — Evaluate C# code read from a .cs file on disk
  - **required:** `file` · optional: `timeout`
- `recompile` — Force a script recompile (works while unfocused/minimized). Poll recompile_status for completion.
  - optional: `focus`
- `recompile_status` — Get the status of the last recompile: idle | triggered | compiling | completed | up_to_date.
- `reload_file` — Compile and apply in-place [HotReload] edits from a source file
  - **required:** `filename` · optional: `timeout`, `assemblyDir`, `pdb`
- `reload_file_override` — Compile and apply hot reload file changes immediately
  - **required:** `filename` · optional: `timeout`, `assemblyDir`

## Animation/Timeline (13)

- `add_animator_parameter` — Add a parameter (Float | Int | Bool | Trigger) to an AnimatorController. A duplicate name returns code 'duplicate_parameter'.
  - **required:** `controller`, `name`, `type` · optional: `defaultValue`, `dry_run`
- `add_animator_state` — Add a state to a layer, optionally with a motion (AnimationClip or BlendTree) and as the layer default. A layer name with no match returns code 'layer_not_found'.
  - **required:** `controller`, `name` · optional: `layer`, `motion`, `isDefault`, `position`, `dry_run`
- `add_animator_transition` — Add a transition between two states (or from AnyState/Entry, to Exit) on a layer, with optional conditions. Validates that the states exist and each condition's parameter exists and its mode matches the parameter type.
  - **required:** `controller`, `fromState`, `toState` · optional: `layer`, `conditions`, `hasExitTime`, `exitTime`, `duration`, `hasFixedDuration`, `dry_run`
- `add_timeline_clip` — Add a clip to a named track on a TimelineAsset. For Animation tracks pass an AnimationClip asset; for Audio tracks an AudioClip. Requires the com.unity.timeline package.
  - **required:** `timeline`, `track`, `start`, `duration` · optional: `asset`, `dry_run`
- `add_timeline_track` — Add a track (Animation | Audio | Activation | Control | Playable | Signal | Marker) to a TimelineAsset, optionally nested under a parent group/track. Requires the com.unity.timeline package.
  - **required:** `timeline`, `trackType` · optional: `name`, `parentTrack`, `dry_run`
- `create_animation_clip` — Create an empty .anim AnimationClip asset under the authoring root, with an optional frame rate and loop flag.
  - **required:** `path` · optional: `frameRate`, `loop`, `confirm`, `dry_run`
- `create_animator_controller` — Create an .controller AnimatorController asset (with a default Base Layer) under the authoring root.
  - **required:** `path` · optional: `confirm`, `dry_run`
- `create_timeline` — Create a .playable TimelineAsset under the authoring root (optional frame rate). Requires the com.unity.timeline package.
  - **required:** `path` · optional: `frameRate`, `confirm`, `dry_run`
- `get_animation_clip` — Read an AnimationClip's metadata and all float curve bindings (optionally with keyframes).
  - **required:** `clip` · optional: `includeKeys`
- `get_animator_controller` — Read an AnimatorController's full structure: parameters, layers, states (with motion / default), and transitions (with conditions).
  - **required:** `controller`
- `get_timeline` — Read a TimelineAsset's structure: frame rate, duration, and its tracks with their clips. Requires the com.unity.timeline package.
  - **required:** `timeline`
- `remove_animation_curve` — Remove a float curve binding from an AnimationClip (SetEditorCurve(clip, binding, null)). Destructive: requires confirm=true.
  - **required:** `clip`, `type`, `property` · optional: `path`, `confirm`, `dry_run`
- `set_animation_curve` — Add or replace a single float curve binding on an AnimationClip (via AnimationUtility.SetEditorCurve). Replacing an existing binding overwrites it rather than duplicating.
  - **required:** `clip`, `type`, `property`, `keys` · optional: `path`, `dry_run`

## Material/Shader (4)

- `get_material_properties` — Read a material's shader, render queue, enabled keywords, and all shader properties with their current values (Color as [r,g,b,a], Vector as [x,y,z,w], Texture as an object reference).
  - **required:** `material`
- `get_shader_properties` — Introspect a shader's declared property list (name, description, type Color|Vector|Float|Range|TexEnv|Int, range, textureDimension, flags). Provide 'shader' (by name) OR 'material' (read the shader off that material).
  - optional: `shader`, `material`
- `list_shaders` — Discover available shaders so an agent can pick a valid name for set_material_properties / create_asset. Returns [{ name, assetPath|null, isBuiltin, isSupported }].
  - optional: `filter`, `includeBuiltin`, `limit`
- `set_material_properties` — Set shader properties on a material (Float/Range/Int=number; Color=[r,g,b,a] or "#RRGGBBAA" hex; Vector=[x,y,z,w]; Texture=an object reference or null to clear), optionally reassign the shader, set the render queue, and toggle keywords. Unknown names / type mismatches are reported in unknown[].
  - **required:** `material` · optional: `shader`, `properties`, `renderQueue`, `enableKeywords`, `disableKeywords`, `confirm`, `dry_run`

## Lighting/NavMesh/Occlusion (17)

- `bake_lighting` — Trigger an async lightmap bake of the open scene(s) via Lightmapping.BakeAsync(). Returns immediately; poll lighting_bake_status until completed.
  - optional: `confirm`, `dry_run`
- `bake_navmesh` — Trigger an async legacy NavMesh bake of the open scene(s) via UnityEditor.AI.NavMeshBuilder. Returns immediately; poll navmesh_bake_status until completed.
  - optional: `confirm`, `dry_run`
- `bake_navmesh_surfaces` — Bake NavMeshSurface components (AI Navigation package). v1 stub: returns package_not_found when the package is absent.
- `bake_occlusion_culling` — Trigger an async occlusion-culling bake of the open scene(s) via StaticOcclusionCulling.GenerateInBackground(). Returns immediately; poll occlusion_bake_status until completed.
  - optional: `smallest_occluder`, `smallest_hole`, `backface_threshold`, `confirm`, `dry_run`
- `cancel_lighting_bake` — Cancel an in-progress lighting bake (Lightmapping.Cancel()).
- `cancel_navmesh_bake` — Cancel an in-progress NavMesh bake (NavMeshBuilder.Cancel()).
- `cancel_occlusion_bake` — Cancel an in-progress occlusion bake (StaticOcclusionCulling.Cancel()).
- `clear_baked_lighting` — Clear baked lightmap data for the open scene(s). Destructive: requires confirm=true.
  - optional: `confirm`, `include_disk_cache`, `dry_run`
- `clear_navmesh` — Clear the baked NavMesh for the open scene(s). Destructive: requires confirm=true.
  - optional: `confirm`, `dry_run`
- `clear_occlusion_culling` — Clear baked occlusion-culling data for the open scene(s). Destructive: requires confirm=true.
  - optional: `confirm`, `dry_run`
- `get_lighting_settings` — Read the active LightingSettings (lightmapper, bounces, resolution, directional mode, AO, etc.).
- `get_navmesh_settings` — Read the default agent's legacy NavMesh bake settings (agentRadius/Height/Slope/Climb, minRegionArea, voxelSize).
- `lighting_bake_status` — Get the status of the last lighting bake: idle | baking | completed.
- `navmesh_bake_status` — Get the status of the last NavMesh bake: idle | baking | completed.
- `occlusion_bake_status` — Get the status of the last occlusion bake: idle | baking | completed.
- `set_lighting_settings` — Apply a subset of lighting settings to the active LightingSettings. Returns { applied[], unknown[] }.
  - **required:** `settings` · optional: `dry_run`
- `set_navmesh_settings` — Apply a subset of legacy NavMesh bake settings to the default agent. Returns { applied[], unknown[] }.
  - **required:** `settings` · optional: `dry_run`

## Play/Editor (12)

- `capture_game_view` — Render the game view to a PNG. source=camera (default) renders a camera and misses Screen Space - Overlay UI; source=screen captures the composited backbuffer incl. overlay canvases (Play Mode only). Returns it inline as base64, unless save_path is set (path-only result; pass include_inline_image=true to get both).
  - optional: `width`, `height`, `camera`, `save_path`, `include_inline_image`, `max_resolution`, `source`
- `clear_console` — Clear the captured log buffer and the Unity Editor console.
- `console` — Get captured Unity console output (Editor or Player; supports tail, level filtering, and follow via a cursor)
  - optional: `tail`, `level`, `since`
- `editor_focus` — Bring the Unity Editor window to the foreground
- `editor_pause` — Toggle pause state of Unity Editor play mode
- `editor_play` — Enter Unity Editor play mode
- `editor_status` — Get detailed Unity Editor status and state information
- `editor_stop` — Exit Unity Editor play mode
- `get_console_logs` — Read recently captured Editor console logs (structured).
  - optional: `severity`, `limit`
- `menu` — Execute an Editor menu item by path, or list available items when no path is given
  - optional: `path`
- `screenshot` — Capture the Scene or Game view as a PNG and return its file path
  - optional: `view`, `output`, `width`, `height`
- `set_autotick` — Keep the editor ticking while unfocused by forcing EditorApplication.SignalTick at a throttled rate
  - optional: `enable`, `interval_ms`, `persist`

## Build/Test (14)

- `audit` — Run a Project Auditor static-analysis scan. Returns immediately; poll audit_status until status is 'completed', then read the CSV.
  - optional: `categories`, `output`
- `audit_status` — Get the status of the last audit: idle | scanning | completed | failed | interrupted | unavailable.
- `build` — Trigger an async Player build and report the full BuildReport. Returns immediately (queued); poll build_status until status is 'completed'. DetailedBuildReport is included by default unless 'options' is supplied. Use dry_run to validate without building.
  - optional: `target`, `outputPath`, `profileName`, `options`, `scenes`, `confirm`, `dry_run`
- `build_status` — Status of the current/most recent build: idle | queued | building | completed, with the full BuildReport (files, packedAssets, buildSteps, errors, warnings) once completed. Retained until the next build.
- `cancel_tests` — Cancel running test execution
- `get_build_settings` — Read the current build configuration from EditorUserBuildSettings / EditorBuildSettings.
- `list_build_profiles` — List Build Profile assets in the project (Unity 6 only). Returns feature_unavailable on earlier versions.
- `list_build_targets` — List the known BuildTarget values with their group and whether build support is installed.
- `list_tests` — List all available tests (EditMode and/or PlayMode) without running them
  - optional: `mode`
- `run_tests` — Execute Unity tests with filtering options
  - optional: `mode`, `filter`, `filter_type`, `include_explicit`, `async_tests`, `timeout`
- `set_build_settings` — Set mutable EditorUserBuildSettings fields. Does NOT manage scenes (use add_scene_to_build / remove_scene_from_build) or switch target (use switch_build_target). Use dry_run to preview.
  - optional: `settings`, `confirm`, `dry_run`
- `switch_build_target` — Switch the active build target (destructive, long-running: triggers a full reimport + domain reload). Requires confirm=true. Returns immediately; poll switch_build_target_status.
  - **required:** `target` · optional: `confirm`
- `switch_build_target_status` — Status of the last target switch: idle | switching | completed (with success + activeBuildTarget).
- `test_status` — Get status of running async test execution

## Package (5)

- `package_add` — Add a UPM package by name@version, git URL, or 'file:' local path. Async by default (returns in_progress; poll package_status); pass wait=true to block until added. A recompile/domain reload follows — poll recompile_status. Requires confirm=true; use dry_run to preview.
  - **required:** `identifier` · optional: `confirm`, `dry_run`, `wait`
- `package_list` — List packages by scope: installed (default) | available (registry) | all (both). Returns the full result synchronously — available/all block until the registry query completes.
  - optional: `scope`, `include_indirect`, `offline`
- `package_remove` — Remove a UPM package by name. Async by default (returns in_progress; poll package_status); pass wait=true to block until removed. A recompile/domain reload follows — poll recompile_status. Requires confirm=true; use dry_run to preview.
  - **required:** `name` · optional: `confirm`, `dry_run`, `wait`
- `package_resolve` — Resolve/refresh packages from the manifest (re-fetch and re-link). May trigger a recompile/domain reload — poll recompile_status. Its outcome is recorded for package_status.
- `package_status` — Status of the last async package operation (add/remove/resolve): idle | in_progress | completed | failed, with the added package, manifest, and any error.

## Settings (15)

- `get_audio_settings` — Read project Audio settings (volume, rolloff scale, doppler factor).
- `get_authoring_root` — Get the base folder (under Assets/) that bare authoring paths resolve against.
- `get_graphics_settings` — Read GraphicsSettings (default render pipeline).
- `get_input_settings` — Read the legacy Input Manager axes (names and count).
- `get_performance_stats` — Read render, memory, and frame-timing stats (structured, read-only).
- `get_physics_settings` — Read Physics settings (gravity, solver iterations, bounce threshold).
- `get_quality_settings` — Read QualitySettings (current level, level names, vSync, anti-aliasing).
- `get_time_settings` — Read Time settings (fixedDeltaTime, maximumDeltaTime, timeScale).
- `set_audio_settings` — Change project Audio settings. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_authoring_root` — Set the base folder (under Assets/) that bare authoring paths resolve against and are confined to. Use 'Assets' for full project access.
  - **required:** `root`
- `set_graphics_settings` — Set the default render pipeline asset. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_input_settings` — Tune a legacy Input Manager axis (sensitivity/gravity/dead) by name. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_physics_settings` — Change Physics settings. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_quality_settings` — Change QualitySettings. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`
- `set_time_settings` — Change Time settings. Requires confirm=true; use dry_run to preview. Not undoable via Ctrl+Z.
  - optional: `settings`, `confirm`, `dry_run`

## Other (1)

- `save_all` — Save all open scenes that have unsaved changes.
