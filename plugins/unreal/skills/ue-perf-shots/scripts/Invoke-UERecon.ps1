#requires -Version 5.1
<#
    Invoke-UERecon.ps1 - one read-only editor boot that surveys a level and
    emits both an analysis JSON and a ground-traced camera list.

    Never writes to the project. Safe to run against whatever state the repo is
    in - it only reads actors and line-traces collision.

    Camera placement is validated rather than assumed: every candidate position
    is traced down onto real collision, sphere-traced for occupancy (so no
    camera ends up inside an NPC or a rock), and rejected if it sits far below
    the play space or is walled in on most sides.

    Example:
      .\Invoke-UERecon.ps1 -Map /Game/Maps/Arena
      .\Invoke-UERecon.ps1 -Map /Game/Maps/Arena -Ref "871,-5218,1081,-5.1,54.4" -Count 12
#>

param(
    [Parameter(Mandatory = $true)][string]$Map,
    [string]$Project = '',
    [string]$Engine  = '',
    [string]$OutDir  = '',
    # "x,y,z,pitch,yaw" - a known-good vantage, e.g. the one a stat capture was
    # taken from, so at least one before/after pair lines up with those numbers.
    [string]$Ref     = '',
    [double]$Radius  = 0,      # 0 = derive from the play space
    [int]   $Count   = 8,      # eye-level ring positions
    [double]$Eye     = 165,    # camera height above traced ground
    [int]   $Orbit   = 6,      # aerial orbit positions
    [int]   $TimeoutMin = 15
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\UECommon.ps1"

$ctx  = Resolve-UEContext -Project $Project -Engine $Engine
$slug = ($Map -split '/')[-1]
if (-not $OutDir) { $OutDir = Join-Path $ctx.Root 'Saved\PerfShots' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script = Join-Path $PSScriptRoot 'recon.py'
$info   = Join-Path $OutDir "level-$slug.json"
$cams   = Join-Path $OutDir "cameras-$slug.json"

Assert-UEEditorClosed
Remove-Item $info, $cams -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "  project : $($ctx.Project)"   -ForegroundColor Cyan
Write-Host "  engine  : $($ctx.Engine)"    -ForegroundColor Cyan
Write-Host "  map     : $slug"             -ForegroundColor Cyan

$env:UEPERF_RECON_MAP    = $slug
$env:UEPERF_RECON_INFO   = $info
$env:UEPERF_RECON_CAMS   = $cams
$env:UEPERF_RECON_REF    = $Ref
$env:UEPERF_RECON_RADIUS = "$Radius"
$env:UEPERF_RECON_COUNT  = "$Count"
$env:UEPERF_RECON_EYE    = "$Eye"
$env:UEPERF_RECON_ORBIT  = "$Orbit"

Write-Host '  booting editor to survey the level...' -ForegroundColor DarkGray
Invoke-UEEditorScript -EditorExe $ctx.EditorExe -Project $ctx.Project -Map $Map `
    -PyScript $script -WaitForFile $info -TimeoutMin $TimeoutMin `
    -ResX 1280 -ResY 720 -GraceSec 90 | Out-Null

if (-not ((Test-Path $info) -and (Test-Path $cams))) {
    Write-Host '  !! recon produced no output.' -ForegroundColor Red
    Write-Host '     Check Saved/Logs for [UEPERF-RECON] lines - if there are none,' -ForegroundColor Red
    Write-Host '     the script never armed (usually a bad map path).' -ForegroundColor Red
    exit 1
}

$j = Get-Content $info -Raw | ConvertFrom-Json
Write-Host ''
Write-Host "  actors  : $($j.actor_count)"     -ForegroundColor Green
Write-Host "  cameras : $($j.camera_count)"    -ForegroundColor Green
if ($j.camera_misses) {
    Write-Host "  rejected: $($j.camera_misses -join ', ')" -ForegroundColor Yellow
}
Write-Host ''
Write-Host "  $info"
Write-Host "  $cams"
