#requires -Version 5.1
<#
    install.ps1 - fallback installer.

    Copies a plugin's skills into the user-level skills directory so they are
    available in every project without registering the marketplace.

    Prefer '/plugin install <name>@gamedev'. That scope can be switched off
    again; this one cannot - user-level skills load in every session on every
    project. Use this only if the marketplace route fails.

    The plugin directories stay the source of truth; this only syncs copies.
    Re-run after editing anything under plugins/<name>/skills/.

      .\install.ps1                    # all plugins
      .\install.ps1 unreal             # just one
      .\install.ps1 unity -Uninstall   # remove that plugin's skills again
      .\install.ps1 -WhatIf            # preview, either direction
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # Plugin names to sync. Empty means every plugin in plugins/.
    [Parameter(Position = 0)]
    [string[]]$Plugin = @(),

    [string]$SkillsDir = (Join-Path $env:USERPROFILE '.claude\skills'),
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$pluginRoot = Join-Path $PSScriptRoot 'plugins'
if (-not (Test-Path $pluginRoot)) { throw "no plugins directory at $pluginRoot" }

$available = Get-ChildItem $pluginRoot -Directory | Select-Object -ExpandProperty Name
if (-not $available) { throw "no plugins found under $pluginRoot" }

if ($Plugin.Count -eq 0) {
    $targets = $available
} else {
    # Fail on an unknown name rather than silently syncing nothing - a typo here
    # otherwise looks identical to a successful no-op run.
    $unknown = $Plugin | Where-Object { $available -notcontains $_ }
    if ($unknown) {
        throw ("unknown plugin(s): {0}. Available: {1}" -f ($unknown -join ', '), ($available -join ', '))
    }
    $targets = $Plugin
}

New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null

foreach ($name in $targets) {
    $src = Join-Path $pluginRoot "$name\skills"
    if (-not (Test-Path $src)) {
        Write-Host "  $name has no skills/ - skipping" -ForegroundColor DarkGray
        continue
    }

    Write-Host "$name" -ForegroundColor White
    foreach ($s in (Get-ChildItem $src -Directory)) {
        $dest = Join-Path $SkillsDir $s.Name

        if ($Uninstall) {
            if (Test-Path $dest) {
                if ($PSCmdlet.ShouldProcess($dest, 'Remove')) {
                    Remove-Item $dest -Recurse -Force
                    Write-Host "  removed   $($s.Name)" -ForegroundColor Yellow
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
}

if (-not $Uninstall) {
    Write-Host ''
    Write-Host "  -> $SkillsDir" -ForegroundColor Cyan
    Write-Host '  Start a new Claude Code session to pick them up.' -ForegroundColor DarkGray
}
