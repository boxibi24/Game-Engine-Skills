---
description: Profile an Unreal project end to end - baseline, bottleneck analysis, ranked optimization proposals
---

Run the full Unreal performance workflow for this project.

1. Establish a trustworthy baseline using the `ue-perf-baseline` skill. Before
   reading any number, confirm shaders have finished compiling and that the
   frame rate is not being capped — check `bSmoothFrameRate`, `FrameRateLimit`,
   `bUseVSync`, and whether `Saved/Config/` shadows the project config. Pin the
   camera vantage so the measurement is repeatable.

2. Diagnose with the `ue-perf-analyze` skill. Determine which thread is the
   bottleneck first, then attribute cost per pass. Consult that skill's
   `references/cost-centers.md` rather than working from memory.

3. Survey the level with `Invoke-UERecon.ps1` from the `ue-perf-shots` skill to
   get an actor class histogram and light inventory — the level-side costs are
   not visible from stat output alone.

4. Present ranked candidates grouped by visual risk: free wins, cheap wins,
   trade-offs, and things that need art-direction sign-off. Recommend where to
   stop, but let the user decide. Do not apply a change that alters the look
   without asking.

If the user supplied arguments, treat them as the target map or a specific area
of concern: $ARGUMENTS
