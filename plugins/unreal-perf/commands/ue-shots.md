---
description: Capture and compare before/after screenshots of an Unreal level across two git commits
---

Capture a before/after screenshot set for this project using the
`ue-perf-shots` skill.

Work out the two commits to compare — usually the change commit and its parent —
and the set of tracked files that commit touched. Confirm both with the user
before capturing, since a wrong file list silently produces a comparison of the
wrong thing.

Then:

1. Make sure Unreal Editor is closed.
2. Generate cameras with `Invoke-UERecon.ps1` if no camera list exists yet for
   this map. Report any rejected positions and why.
3. Capture both states with `Invoke-UECapture.ps1`.
4. Build the comparison with `New-UEPerfCompare.ps1`.
5. Read `difference-report.txt` first, then inspect the highest-difference pairs
   directly. Report what actually degraded, not just the aggregate number — a
   consistently negative delta across most cameras means the change darkened the
   scene systematically rather than altering one effect.

Re-shoot any camera that dropped out rather than accepting an incomplete set.

Arguments, if given, name the map or the commits to compare: $ARGUMENTS
