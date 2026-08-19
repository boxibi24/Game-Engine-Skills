#requires -Version 5.1
<#
    UECommon.ps1 - shared helpers for driving UnrealEditor headlessly.

    Dot-source this from a runner:  . "$PSScriptRoot\UECommon.ps1"

    Everything here is project-agnostic. Engine and project are discovered from
    the .uproject rather than hardcoded, so the same scripts work across
    machines and across projects without editing.
#>

function Find-UEProject {
    <#  Locate the .uproject. Searches the given directory, then walks up.  #>
    param([string]$StartDir = (Get-Location).Path)

    $dir = (Resolve-Path $StartDir -ErrorAction SilentlyContinue).Path
    while ($dir) {
        $found = Get-ChildItem -LiteralPath $dir -Filter '*.uproject' -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "No .uproject found at or above '$StartDir'. Pass -Project explicitly."
}

function Find-UEEngine {
    <#  Resolve the engine install for a project.

        EngineAssociation is either a version string ("5.6") for a launcher
        install, or a GUID for a source/custom build. Those live in different
        registry hives, so try both before falling back to a disk scan.
    #>
    param([Parameter(Mandatory = $true)][string]$Project)

    $assoc = $null
    try { $assoc = (Get-Content $Project -Raw | ConvertFrom-Json).EngineAssociation } catch { }

    if ($assoc) {
        # Launcher install, keyed by version.
        $k = "HKLM:\SOFTWARE\EpicGames\Unreal Engine\$assoc"
        if (Test-Path $k) {
            $d = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstalledDirectory
            if ($d -and (Test-Path $d)) { return $d }
        }
        # Source or custom build, keyed by GUID.
        $b = 'HKCU:\Software\Epic Games\Unreal Engine\Builds'
        if (Test-Path $b) {
            $d = (Get-ItemProperty $b -ErrorAction SilentlyContinue).$assoc
            if ($d -and (Test-Path $d)) { return $d }
        }
    }

    # Last resort: newest UE_* under the usual install roots on any drive.
    $cands = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem).Root) {
        $p = Join-Path $drive 'Program Files\Epic Games'
        if (Test-Path $p) {
            $cands += Get-ChildItem $p -Directory -Filter 'UE_*' -ErrorAction SilentlyContinue
        }
    }
    $best = $cands | Sort-Object Name -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }

    throw "Could not resolve the engine for '$Project' (EngineAssociation='$assoc'). Pass -Engine explicitly."
}

function Get-UEEditorExe {
    param([Parameter(Mandatory = $true)][string]$Engine)
    $exe = Join-Path $Engine 'Engine\Binaries\Win64\UnrealEditor.exe'
    if (-not (Test-Path $exe)) { throw "UnrealEditor.exe not found under '$Engine'." }
    return $exe
}

function Assert-UEEditorClosed {
    <#  A second editor on the same project fights over file locks and the DDC,
        and these scripts rewrite .umap files a running editor may hold open.  #>
    $p = Get-Process -Name 'UnrealEditor*' -ErrorAction SilentlyContinue
    if ($p) {
        throw "Unreal Editor is running (PID $($p.Id -join ', ')). Close it before running this."
    }
}

function Write-Utf8NoBom {
    <#  PowerShell 5.1's Set-Content -Encoding utf8 writes a BOM, and Python's
        json.load rejects a leading BOM outright. Any JSON handed to an
        in-editor script must go through here.  #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-JsonArray {
    <#  ConvertTo-Json unwraps a single-element array into a bare object, which
        breaks any consumer that indexes it as a list. Force the brackets.  #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Items)
    if ($Items.Count -eq 0) { return '[]' }
    return "[`n" + ($Items | ConvertTo-Json -Depth 6) + "`n]"
}

function Copy-WithRetry {
    <#  Windows keeps a .umap memory-mapped briefly after the editor exits
        ("cannot be performed on a file with a user-mapped section open"), so a
        copy issued right after a run can fail with nothing actually holding
        the file any more.  #>
    param(
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To,
        [int]$Tries = 10
    )
    for ($i = 1; $i -le $Tries; $i++) {
        try { Copy-Item $From $To -Force; return }
        catch {
            if ($i -eq $Tries) { throw }
            Write-Host "    file locked, retry $i/$Tries ..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
        }
    }
}

function Invoke-UEEditorScript {
    <#  Boot the editor, run a Python script inside it, wait for a sentinel
        file, then let it shut down.

        The script is launched with -ExecCmds="py <path>", never
        -ExecutePythonScript. The latter routes through FEditorPythonExecuter,
        which requests editor exit the moment the script RETURNS - and every
        script here returns immediately after registering a tick callback, so
        the editor would die a few frames in having rendered nothing.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$EditorExe,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Map,
        [Parameter(Mandatory = $true)][string]$PyScript,
        [Parameter(Mandatory = $true)][string]$WaitForFile,
        [int]$TimeoutMin = 30,
        [int]$ResX = 1920,
        [int]$ResY = 1080,
        [int]$GraceSec = 120
    )

    # One string, so the quoting inside -ExecCmds survives Start-Process.
    $cmdline = "`"$Project`" $Map -ExecCmds=`"py $PyScript`"" +
               ' -EnablePlugins=PythonScriptPlugin' +
               " -nosplash -NoLiveCoding -windowed -ResX=$ResX -ResY=$ResY"

    $proc = Start-Process -FilePath $EditorExe -ArgumentList $cmdline -PassThru

    $deadline  = (Get-Date).AddMinutes($TimeoutMin)
    $signalled = $false
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if (Test-Path $WaitForFile) { $signalled = $true; break }
    }
    if (-not $signalled -and -not $proc.HasExited) {
        Write-Host '  !! deadline reached without a completion marker' -ForegroundColor Yellow
    }

    # Editor shutdown is slow (async tasks, DDC flush); give it room before forcing.
    $grace = (Get-Date).AddSeconds($GraceSec)
    while (-not $proc.HasExited -and (Get-Date) -lt $grace) { Start-Sleep -Seconds 5 }
    if (-not $proc.HasExited) {
        Write-Host '  editor did not exit within grace; terminating' -ForegroundColor DarkGray
        try { $proc.Kill(); Start-Sleep -Seconds 5 } catch { }
    }
    return $signalled
}

function Resolve-UEContext {
    <#  One call to get everything a runner needs.  #>
    param([string]$Project = '', [string]$Engine = '')

    if (-not $Project) { $Project = Find-UEProject }
    if (-not (Test-Path $Project)) { throw "No such .uproject: $Project" }
    if (-not $Engine)  { $Engine  = Find-UEEngine -Project $Project }

    $root = Split-Path -Parent $Project
    [pscustomobject]@{
        Project   = $Project
        Root      = $root
        Engine    = $Engine
        EditorExe = Get-UEEditorExe -Engine $Engine
        ShotDir   = Join-Path $root 'Saved\Screenshots\WindowsEditor'
    }
}
