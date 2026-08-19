#requires -Version 5.1
<#
    Invoke-UECapture.ps1 - before/after screenshot set for an optimization,
    captured from two pinned git commits.

    For each state it checks the tracked files out of that commit, boots the
    editor ONCE, walks every camera taking a HighResShot, then quits. One boot
    per state rather than one per angle - 2 boots instead of 2N.

    Shots are taken in editor Game View, so no volume wireframes, actor
    billboards or the corner axis gizmo end up baked into the image. Those
    would read as a visual difference between before and after when they are
    nothing of the sort.

    The editor MUST be closed before running this.

    Example:
      .\Invoke-UECapture.ps1 -Map /Game/Maps/Arena `
          -BeforeSha abc1234 -AfterSha def5678 `
          -Files 'Config/DefaultEngine.ini','Content/Maps/Arena.umap'
#>

param(
    [Parameter(Mandatory = $true)][string]$Map,
    [Parameter(Mandatory = $true)][string]$BeforeSha,
    [Parameter(Mandatory = $true)][string]$AfterSha,
    [Parameter(Mandatory = $true)][string[]]$Files,
    [string]$Project = '',
    [string]$Engine  = '',
    [string]$Cameras = '',
    [string]$OutDir  = '',
    [int]   $WarmFrames   = 300,   # settle frames before the FIRST shot
    [int]   $ReWarmFrames = 120,   # settle frames between later shots
    [int]   $TimeoutMin   = 60,
    [ValidateSet('both', 'before', 'after')][string]$Only = 'both'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\UECommon.ps1"

$ctx   = Resolve-UEContext -Project $Project -Engine $Engine
$slug  = ($Map -split '/')[-1]
$base  = Join-Path $ctx.Root 'Saved\PerfShots'
if (-not $Cameras) { $Cameras = Join-Path $base "cameras-$slug.json" }
if (-not $OutDir)  { $OutDir  = Join-Path $base $slug }

$capturePy = Join-Path $PSScriptRoot 'capture.py'
$flip      = Join-Path $PSScriptRoot 'Set-UEPerfState.ps1'

foreach ($p in @($capturePy, $flip, $Cameras)) {
    if (-not (Test-Path $p)) { throw "missing required path: $p" }
}
foreach ($sub in 'before', 'after') {
    New-Item -ItemType Directory -Force -Path (Join-Path $OutDir $sub) | Out-Null
}
New-Item -ItemType Directory -Force -Path $ctx.ShotDir | Out-Null

# ConvertFrom-Json emits a JSON array as ONE pipeline object in PS 5.1, so wrap
# with @() at the point of counting - never around the parse itself.
$camList  = Get-Content $Cameras -Raw | ConvertFrom-Json
$camCount = @($camList).Count

Write-Host ''
Write-Host "  project : $($ctx.Project)" -ForegroundColor Cyan
Write-Host "  map     : $slug"           -ForegroundColor Cyan
Write-Host "  before  : $BeforeSha"      -ForegroundColor Cyan
Write-Host "  after   : $AfterSha"       -ForegroundColor Cyan
Write-Host "  cameras : $camCount"       -ForegroundColor Cyan

Assert-UEEditorClosed

function Invoke-OneState {
    param([string]$Label)

    Write-Host ''
    Write-Host "=== $Label ".PadRight(70, '=') -ForegroundColor Cyan

    & $flip -State $Label -Repo $ctx.Root -BeforeSha $BeforeSha -AfterSha $AfterSha -Files $Files
    if ($LASTEXITCODE -ne 0) { throw "state flip to '$Label' failed" }

    $done     = Join-Path $base "$slug.$Label.done"
    $manifest = Join-Path $base "$slug.$Label.manifest.json"
    Remove-Item $done, $manifest -Force -ErrorAction SilentlyContinue

    $env:UEPERF_SHOT_LABEL    = $Label
    $env:UEPERF_SHOT_CAMS     = $Cameras
    $env:UEPERF_SHOT_MANIFEST = $manifest
    $env:UEPERF_SHOT_DONE     = $done
    $env:UEPERF_SHOT_DIR      = $ctx.ShotDir
    $env:UEPERF_SHOT_MAP      = $slug
    $env:UEPERF_SHOT_WARM     = "$WarmFrames"
    $env:UEPERF_SHOT_REWARM   = "$ReWarmFrames"

    Write-Host "  booting editor for $camCount camera(s)..." -ForegroundColor DarkGray
    Invoke-UEEditorScript -EditorExe $ctx.EditorExe -Project $ctx.Project -Map $Map `
        -PyScript $capturePy -WaitForFile $done -TimeoutMin $TimeoutMin | Out-Null

    if (-not (Test-Path $manifest)) {
        Write-Host "  !! no manifest written for '$Label'" -ForegroundColor Red
        return @{}
    }

    # Filenames drop the state prefix because the folder already carries it -
    # before/<cam>.png and after/<cam>.png then sort identically, which is what
    # makes them easy to flip between in any viewer.
    $map = Get-Content $manifest -Raw | ConvertFrom-Json
    $got = @{}
    foreach ($p in $map.PSObject.Properties) {
        $src = Join-Path $ctx.ShotDir $p.Value
        if (-not (Test-Path $src)) {
            Write-Host "  !! manifest names a missing file: $($p.Value)" -ForegroundColor Red
            continue
        }
        $dest = Join-Path $OutDir "$Label\$($p.Name).png"
        Copy-WithRetry -From $src -To $dest
        $got[$p.Name] = $dest
    }
    Write-Host ("  captured {0}/{1}" -f $got.Count, $camCount) -ForegroundColor Green
    return $got
}

$results = @{}
if ($Only -eq 'both' -or $Only -eq 'before') { $results['before'] = Invoke-OneState -Label 'before' }
if ($Only -eq 'both' -or $Only -eq 'after')  { $results['after']  = Invoke-OneState -Label 'after' }

Write-Host ''
Write-Host '=== RESULT ===' -ForegroundColor Cyan
$missing = @()
foreach ($cam in $camList) {
    $b = if (Test-Path (Join-Path $OutDir "before\$($cam.name).png")) { 'ok' } else { '--' }
    $a = if (Test-Path (Join-Path $OutDir "after\$($cam.name).png"))  { 'ok' } else { '--' }
    if ($b -eq '--' -or $a -eq '--') { $missing += $cam.name }
}
Write-Host ("  complete pairs : {0}/{1}" -f ($camCount - $missing.Count), $camCount)
if ($missing.Count -gt 0) {
    # A camera can drop out when HighResShot produces no file inside the wait
    # window. It is per-camera and usually transient, so re-shoot just that one
    # with -Only and a single-camera list rather than redoing the whole set.
    Write-Host ("  incomplete     : {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
}
Write-Host ''
Write-Host "  output : $OutDir"
Write-Host ''
& $flip -State status -Repo $ctx.Root -BeforeSha $BeforeSha -AfterSha $AfterSha -Files $Files
