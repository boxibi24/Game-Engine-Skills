#requires -Version 5.1
<#
    Set-UEPerfState.ps1 - flip a set of tracked files between two COMMITS.

    Both states come from git history, so the capture is reproducible from the
    repo alone - no scratch snapshot to lose, and the pairing is provable rather
    than remembered.

        before  -> git checkout <BeforeSha> -- <files>
        after   -> git checkout <AfterSha>  -- <files>
        status  -> report which commit each file currently matches

    Usage:
      .\Set-UEPerfState.ps1 -State status -BeforeSha abc1234 -AfterSha def5678 `
          -Files 'Config/DefaultEngine.ini','Content/Maps/Arena.umap'
#>

param(
    [Parameter(Mandatory = $true)][ValidateSet('before', 'after', 'status')]
    [string]$State,
    [Parameter(Mandatory = $true)][string]$BeforeSha,
    [Parameter(Mandatory = $true)][string]$AfterSha,
    [Parameter(Mandatory = $true)][string[]]$Files,
    [string]$Repo = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\UECommon.ps1"

if (-not $Repo) { $Repo = Split-Path -Parent (Find-UEProject) }
Set-Location $Repo

function Hash-Of([string]$f) {
    if (-not (Test-Path $f)) { return $null }
    (& git hash-object $f).Trim()
}
function Blob-At([string]$sha, [string]$f) {
    $v = (& git rev-parse "${sha}:$f" 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return $v.Trim()
}

function Describe([string]$f) {
    $cur = Hash-Of $f
    if ($null -eq $cur) { return 'MISSING' }
    if ($cur -eq (Blob-At $BeforeSha $f)) { return "before ($BeforeSha)" }
    if ($cur -eq (Blob-At $AfterSha  $f)) { return "after  ($AfterSha)" }
    return 'UNKNOWN (uncommitted local edit)'
}

# A dirty working tree mid-run is EXPECTED: sitting in 'before' while HEAD is
# the optimization commit legitimately shows every file as modified. So a plain
# `git status` guard is wrong - it would block every flip after the first.
# Compare blob identity against the two pinned commits instead, and refuse only
# when a file matches neither, which means it is the user's own edit.
function Assert-Known {
    $bad = @()
    foreach ($f in $Files) { if ((Describe $f) -like 'UNKNOWN*') { $bad += $f } }
    if ($bad.Count -gt 0) {
        Write-Host '  !! these files match neither pinned commit:' -ForegroundColor Red
        $bad | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        Write-Host '     Refusing to overwrite what looks like your own edit.' -ForegroundColor Red
        Write-Host '     Commit or stash it, then re-run.' -ForegroundColor Red
        exit 1
    }
}

function Restore-From([string]$sha, [string]$label) {
    Assert-UEEditorClosed
    Assert-Known
    foreach ($f in $Files) {
        # Idempotent: never touch a file already in the target state. That can
        # only fail against a lingering memory-mapped .umap handle.
        if ((Hash-Of $f) -ne (Blob-At $sha $f)) { & git checkout $sha -- $f }
    }
    Write-Host "  state: $label" -ForegroundColor Yellow
    foreach ($f in $Files) {
        Write-Host ("    {0,-52} {1,12:N0} bytes" -f $f, (Get-Item $f).Length)
    }
}

switch ($State) {
    'status' {
        foreach ($f in $Files) {
            $len = if (Test-Path $f) { (Get-Item $f).Length } else { 0 }
            Write-Host ("  {0,-52} {1,12:N0} bytes  {2}" -f $f, $len, (Describe $f))
        }
    }
    'before' { Restore-From $BeforeSha "BEFORE ($BeforeSha)" }
    'after'  { Restore-From $AfterSha  "AFTER  ($AfterSha)" }
}
