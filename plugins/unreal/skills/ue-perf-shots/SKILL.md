---
name: ue-perf-shots
description: Capture automated before/after screenshot sets from an Unreal Engine level across two pinned git commits, then compare them quantitatively to prove what a change did to the look. Use this whenever someone wants to see the visual impact of an optimization or any render-setting change, asks for before/after or side-by-side comparison images of a level, wants to check whether a performance change degraded the art, needs many camera angles captured reproducibly, or asks to screenshot an Unreal map without clicking through the editor by hand. Also use it when validating that removing actors, disabling Lumen, or changing reflections did not break the scene.
---

# Before/after visual proof for a level change

A performance win that quietly ruins the art is not a win. This skill captures
the same set of camera angles under two states of the repository and measures
what changed, so the visual cost of an optimization is evidence rather than an
impression.

The design decisions worth understanding before running it:

- **Both states come from git commits**, not scratch copies. The pair is
  reproducible from the repo alone later, and the pairing is provable.
- **One editor boot per state**, not per angle. Booting is by far the slowest
  part, so 40 angles cost two boots rather than eighty.
- **Camera positions are validated against real collision**, not assumed. A
  fixed eye height over a ring of positions reliably buries some cameras in
  terrain and floats others over pits.
- **Shots are taken in Game View**, so editor overlays never get baked in.
- **The comparison is measured, not eyeballed.** Forty image pairs do not get
  reliably reviewed by eye; a ranked per-pair difference does the triage.

This depends on running Python inside the editor. If anything about the harness
misbehaves — the editor exits early, produces nothing, or hangs — read the
`ue-editor-automation` skill, which covers those failure modes specifically.

## Prerequisites

- The project is a git repository and the change to compare is committed.
- Unreal Editor is **closed**. Every script refuses to run otherwise.
- Windows with PowerShell 5.1 or later.

Engine and project are discovered from the `.uproject` (via `EngineAssociation`
and the registry), so normally nothing needs to be passed. Override with
`-Project` and `-Engine` if discovery fails.

## The workflow

### 1. Survey the level and generate cameras

```powershell
.\scripts\Invoke-UERecon.ps1 -Map /Game/Maps/Arena -Count 12 -Orbit 6
```

One read-only editor boot. Writes two files into `Saved/PerfShots/`:

- `level-<Map>.json` — actor class histogram, light inventory (with shadow
  casting and volumetric scattering per light), fog, Niagara, decals,
  PlayerStarts, PostProcessVolume settings. This is also the input for deciding
  *what* to optimize, so read it even if you only wanted cameras.
- `cameras-<Map>.json` — the validated camera list.

Camera generation produces an aerial orbit, a full circle of eye-level yaws from
each PlayerStart, and a ring of positions shot both inward across the play space
and outward at the background. Every position is traced down onto real
collision, sphere-traced for occupancy, and rejected with a stated reason if it
is inside geometry, far below the play space, or walled in. Read
`camera_misses` in the output — a rejection is information about the level, not
just a dropped camera.

Pass `-Ref "x,y,z,pitch,yaw"` to add a specific vantage — typically the one a
stat baseline was captured from, so one image pair lines up with those numbers.

### 2. Make and commit the change

Keep project config and level content in one focused commit, with the specific
settings and actor counts in the message.

To delete actors by class:

```powershell
.\scripts\Invoke-UEOptimize.ps1 -Map /Game/Maps/Arena -Classes BP_Fog_C,BP_Light_C -DryRun
.\scripts\Invoke-UEOptimize.ps1 -Map /Game/Maps/Arena -Classes BP_Fog_C,BP_Light_C
```

Always dry-run first. It reports per-class match counts and — more usefully —
which requested class names matched *nothing*, which is how a typo or a wrong
assumption about a class name surfaces instead of silently doing less than
asked. The real run refuses unless the `.umap` is at HEAD, so deletions can
never stack on an already-modified level.

### 3. Capture both states

```powershell
.\scripts\Invoke-UECapture.ps1 -Map /Game/Maps/Arena `
    -BeforeSha <parent-sha> -AfterSha <change-sha> `
    -Files 'Config/DefaultEngine.ini','Content/Maps/Arena.umap'
```

`-Files` is the set of tracked files the change touches — the same files the
commit modified. The state flipper checks each out of the relevant commit,
guarded by blob identity: it refuses to overwrite a file matching neither
commit, since that is your own uncommitted edit.

Output lands in `Saved/PerfShots/<Map>/before/` and `.../after/`, one PNG per
camera. Filenames drop the state prefix because the folder carries it, so the
two directories sort identically and flipping between them in any viewer lines
up.

### 4. Compare

```powershell
.\scripts\New-UEPerfCompare.ps1 -ShotDir "<Project>\Saved\PerfShots\Arena"
```

Produces labelled side-by-side composites, a contact sheet, and
`difference-report.txt` ranking every pair by luminance difference.

Read the report before the images. It tells you which pairs to look at, and the
aggregate tells you something no single image does: **a consistently negative
delta across most cameras means the change darkened the scene systematically**,
which is what losing global illumination bounce looks like numerically. A large
difference concentrated in a few pairs is a localized change; spread evenly, it
is a lighting-model change.

Then inspect the highest-difference pairs directly, and say plainly what
degraded rather than only reporting the aggregate.

## When a camera drops out

`HighResShot` occasionally produces no file within the wait window and that
camera is skipped — per-camera and usually transient. Re-shoot just that one
rather than the whole set: build a one-element camera JSON and run with
`-Only before` (or `after`) and `-Cameras` pointing at it.

Note that `ConvertTo-Json` unwraps a single-element array into a bare object,
which breaks the script that indexes it as a list. `UECommon.ps1` provides
`ConvertTo-JsonArray` to force the brackets.

## Reading the results honestly

Camera transforms are replayed identically in both states, so geometry is
directly comparable. What differs is shading.

If a follow-up capture came from a different vantage than the baseline, say so
and separate view-dependent counters from scene-wide ones. A comparison table
that quietly spans two viewpoints is worse than one that admits the gap.

## Files

| Script | Purpose |
|---|---|
| `scripts/UECommon.ps1` | Engine/project discovery, editor launcher, BOM-safe JSON, retrying copy |
| `scripts/Invoke-UERecon.ps1` + `recon.py` | Level survey and validated camera generation |
| `scripts/Invoke-UECapture.ps1` + `capture.py` | Two-state screenshot capture |
| `scripts/Invoke-UEOptimize.ps1` + `optimize.py` | Delete actors by class and save |
| `scripts/Set-UEPerfState.ps1` | Flip tracked files between two pinned commits |
| `scripts/New-UEPerfCompare.ps1` | Composites, contact sheet, difference report |
