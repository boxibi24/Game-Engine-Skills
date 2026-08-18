#requires -Version 5.1
<#
    Invoke-UEOptimize.ps1 - delete every actor of the named classes from a level
    and save it.

    This is the only script here that WRITES to the project. It refuses to run
    unless the target .umap is currently at HEAD, so a second run can never
    stack deletions on top of an already-modified level and leave you unsure
    what the baseline was.

    Always -DryRun first. The dry run reports match counts per class and, more
    usefully, which requested class names matched NOTHING - a typo or a wrong
    assumption about the class name is otherwise silent.

    Example:
      .\Invoke-UEOptimize.ps1 -Map /Game/Maps/Arena -Classes BP_Fog_C,BP_Light_C -DryRun
      .\Invoke-UEOptimize.ps1 -Map /Game/Maps/Arena -Classes BP_Fog_C,BP_Light_C
#>

param(
    [Parameter(Mandatory = $true)][string]$Map,
    [Parameter(Mandatory = $true)][string[]]$Classes,
    [string]$Project = '',
    [string]$Engine  = '',
    [string]$UmapPath = '',        # repo-relative; derived from -Map if omitted
    [switch]$DryRun,
    [int]$TimeoutMin = 20
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\UECommon.ps1"

$ctx  = Resolve-UEContext -Project $Project -Engine $Engine
$slug = ($Map -split '/')[-1]

# /Game/... maps to Content/... on disk.
if (-not $UmapPath) {
    $UmapPath = ($Map -replace '^/Game/', 'Content/') + '.umap'
}

Assert-UEEditorClosed
Set-Location $ctx.Root

if (-not (Test-Path $UmapPath)) { throw "map file not found: $UmapPath (pass -UmapPath)" }

if (-not $DryRun) {
    $cur  = (& git hash-object $UmapPath).Trim()
    $head = (& git rev-parse "HEAD:$UmapPath" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $cur -ne $head.Trim()) {
        throw "$UmapPath is already modified relative to HEAD. Restore it first:`n  git checkout HEAD -- $UmapPath"
    }
}

$report = Join-Path $ctx.Root "Saved\PerfShots\optimize-$slug.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $report) | Out-Null
Remove-Item $report -Force -ErrorAction SilentlyContinue

$env:UEPERF_OPT_MAP     = $slug
$env:UEPERF_OPT_CLASSES = ($Classes -join ',')
$env:UEPERF_OPT_REPORT  = $report
$env:UEPERF_OPT_DRYRUN  = if ($DryRun) { '1' } else { '0' }

$mode = if ($DryRun) { 'DRY RUN' } else { 'DELETING' }
Write-Host ("  {0} on {1}: {2}" -f $mode, $slug, ($Classes -join ', ')) -ForegroundColor Cyan
$before = (Get-Item $UmapPath).Length

Invoke-UEEditorScript -EditorExe $ctx.EditorExe -Project $ctx.Project -Map $Map `
    -PyScript (Join-Path $PSScriptRoot 'optimize.py') -WaitForFile $report `
    -TimeoutMin $TimeoutMin -ResX 1280 -ResY 720 | Out-Null

if (-not (Test-Path $report)) {
    Write-Host '  !! no report written - check Saved/Logs for [UEPERF-OPT] lines' -ForegroundColor Red
    exit 1
}

$j = Get-Content $report -Raw | ConvertFrom-Json
Get-Content $report -Raw | Write-Host

if ($j.unmatched_classes -and @($j.unmatched_classes).Count -gt 0) {
    Write-Host ("  !! these class names matched nothing: {0}" -f ($j.unmatched_classes -join ', ')) -ForegroundColor Yellow
    Write-Host '     Check the exact class name in the recon output (classes histogram).' -ForegroundColor Yellow
}

$after = (Get-Item $UmapPath).Length
Write-Host ("  {0}: {1:N0} -> {2:N0} bytes" -f $slug, $before, $after) -ForegroundColor Green
