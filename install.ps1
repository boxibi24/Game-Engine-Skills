#requires -Version 5.1
<#
    install.ps1 - copy the plugin's skills into the user-level skills directory
    so they are available in every project without registering a marketplace.

    The plugin directory stays the source of truth; this only syncs copies.
    Re-run after editing anything under plugins/unreal-perf/skills/.

    Use -WhatIf to see what would change without touching anything.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SkillsDir = (Join-Path $env:USERPROFILE '.claude\skills'),
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'plugins\unreal-perf\skills'
if (-not (Test-Path $src)) { throw "skills directory not found at $src" }

$skills = Get-ChildItem $src -Directory
if (-not $skills) { throw "no skills found under $src" }

New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null

foreach ($s in $skills) {
    $dest = Join-Path $SkillsDir $s.Name

    if ($Uninstall) {
        if (Test-Path $dest) {
            if ($PSCmdlet.ShouldProcess($dest, 'Remove')) {
                Remove-Item $dest -Recurse -Force
                Write-Host "  removed  $($s.Name)" -ForegroundColor Yellow
            }
        }
        continue
    }

    if ($PSCmdlet.ShouldProcess($dest, 'Install')) {
        # Replace wholesale rather than merging, so a file deleted from the
        # source does not linger in the installed copy.
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item $s.FullName $dest -Recurse -Force
        $n = (Get-ChildItem $dest -Recurse -File).Count
        Write-Host ("  installed {0,-24} {1,3} files" -f $s.Name, $n) -ForegroundColor Green
    }
}

if (-not $Uninstall) {
    Write-Host ''
    Write-Host "  -> $SkillsDir" -ForegroundColor Cyan
    Write-Host '  Start a new Claude Code session to pick them up.' -ForegroundColor DarkGray
}
