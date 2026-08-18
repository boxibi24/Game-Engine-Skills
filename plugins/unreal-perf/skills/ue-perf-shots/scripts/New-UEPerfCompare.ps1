#requires -Version 5.1
<#
    New-UEPerfCompare.ps1 - build labelled side-by-side BEFORE|AFTER composites
    from a before/ + after/ pair of folders, a contact sheet of every pair, and
    a quantitative difference report.

    The difference report is the point. Eyeballing 40 image pairs does not
    reliably surface a regression, but a per-pair luminance delta ranks them for
    you: a large negative delta across many cameras means the change is
    systematically darkening the scene, which is what losing GI bounce or
    reflections looks like numerically.

    Example:
      .\New-UEPerfCompare.ps1 -ShotDir "D:\Proj\Saved\PerfShots\Arena"
#>

param(
    [Parameter(Mandatory = $true)][string]$ShotDir,
    [string]$OutDir     = '',
    [int]   $SheetCols  = 3,
    [int]   $SheetPaneW = 400,
    [switch]$SkipSheet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$beforeDir = Join-Path $ShotDir 'before'
$afterDir  = Join-Path $ShotDir 'after'
foreach ($d in @($beforeDir, $afterDir)) {
    if (-not (Test-Path $d)) { throw "expected '$d' - point -ShotDir at the folder containing before/ and after/" }
}
if (-not $OutDir) { $OutDir = Join-Path $ShotDir 'compare' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$names = Get-ChildItem $beforeDir -Filter '*.png' | ForEach-Object { $_.BaseName } | Sort-Object
if (-not $names) { throw "no PNGs in $beforeDir" }

$labelH = 46
$gap    = 8
$pairs  = New-Object System.Collections.Generic.List[object]
$rows   = New-Object System.Collections.Generic.List[object]

foreach ($n in $names) {
    $bPath = Join-Path $beforeDir "$n.png"
    $aPath = Join-Path $afterDir  "$n.png"
    if (-not (Test-Path $aPath)) {
        Write-Host "  !! no 'after' for $n - skipping" -ForegroundColor Yellow
        continue
    }

    $b = [System.Drawing.Bitmap]::FromFile($bPath)
    $a = [System.Drawing.Bitmap]::FromFile($aPath)
    try {
        # Sampled rather than per-pixel: a 24px stride over 1920x1080 is ~3600
        # samples, plenty to rank pairs, and orders of magnitude faster than
        # GetPixel over two million pixels per image.
        $sum = 0.0; $cnt = 0; $bSum = 0.0; $aSum = 0.0
        for ($y = 8; $y -lt [Math]::Min($b.Height, $a.Height); $y += 24) {
            for ($x = 8; $x -lt [Math]::Min($b.Width, $a.Width); $x += 24) {
                $pb = $b.GetPixel($x, $y); $pa = $a.GetPixel($x, $y)
                $lb = ($pb.R + $pb.G + $pb.B) / 3.0
                $la = ($pa.R + $pa.G + $pa.B) / 3.0
                $sum += [Math]::Abs($lb - $la); $bSum += $lb; $aSum += $la; $cnt++
            }
        }
        if ($cnt -gt 0) {
            $rows.Add([pscustomobject]@{
                camera     = $n
                diff       = [Math]::Round($sum / $cnt, 2)
                beforeLum  = [Math]::Round($bSum / $cnt, 1)
                afterLum   = [Math]::Round($aSum / $cnt, 1)
                delta      = [Math]::Round(($aSum - $bSum) / $cnt, 1)
            })
        }

        $w = $b.Width; $h = $b.Height
        $out = New-Object System.Drawing.Bitmap (($w * 2 + $gap), ($h + $labelH))
        $g   = [System.Drawing.Graphics]::FromImage($out)
        try {
            $g.Clear([System.Drawing.Color]::FromArgb(18, 18, 20))
            $g.DrawImage($b, 0, $labelH, $w, $h)
            $g.DrawImage($a, ($w + $gap), $labelH, $w, $h)
            $f1 = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
            $f2 = New-Object System.Drawing.Font('Segoe UI', 14)
            $wh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $gr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 170, 175))
            $g.DrawString('BEFORE', $f1, $wh, 14, 8)
            $g.DrawString('AFTER',  $f1, $wh, ($w + $gap + 14), 8)
            $g.DrawString($n, $f2, $gr, ($w - 240), 12)
            $f1.Dispose(); $f2.Dispose(); $wh.Dispose(); $gr.Dispose()
        } finally { $g.Dispose() }

        $dest = Join-Path $OutDir "cmp_$n.png"
        $out.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
        $out.Dispose()
        $pairs.Add($n)
    } finally { $b.Dispose(); $a.Dispose() }
}

Write-Host ("  wrote {0} comparison image(s)" -f $pairs.Count) -ForegroundColor Green

# --- difference report ---------------------------------------------------
$sorted = $rows | Sort-Object diff -Descending
$report = Join-Path $OutDir 'difference-report.txt'
$lines  = @()
$lines += 'Per-pair visual difference (sampled luminance, 0-255)'
$lines += '======================================================'
$lines += ''
$lines += ('{0,-22} {1,>7} {2,>10} {3,>10} {4,>8}' -f 'camera', 'diff', 'before', 'after', 'delta')
foreach ($r in $sorted) {
    $lines += ('{0,-22} {1,7:N2} {2,10:N1} {3,10:N1} {4,8:N1}' -f $r.camera, $r.diff, $r.beforeLum, $r.afterLum, $r.delta)
}
$avg  = ($rows | Measure-Object diff -Average).Average
$bAvg = ($rows | Measure-Object beforeLum -Average).Average
$aAvg = ($rows | Measure-Object afterLum  -Average).Average
$lines += ''
$lines += ('pairs           : {0}' -f $rows.Count)
$lines += ('mean difference : {0:N2} / 255' -f $avg)
$lines += ('mean luminance  : {0:N1} -> {1:N1}' -f $bAvg, $aAvg)
$lines += ''
$lines += 'A large mean difference with a consistently negative delta means the'
$lines += 'change is darkening the scene across the board rather than altering'
$lines += 'one effect - typically the signature of removing GI bounce or'
$lines += 'reflections. Inspect the highest-diff pairs first.'
$lines -join "`r`n" | Set-Content $report -Encoding UTF8

$sorted | Select-Object -First 10 | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ("  mean difference : {0:N2} / 255" -f $avg) -ForegroundColor Cyan
Write-Host ("  mean luminance  : {0:N1} -> {1:N1}" -f $bAvg, $aAvg) -ForegroundColor Cyan
Write-Host "  report : $report" -ForegroundColor Green

# --- contact sheet -------------------------------------------------------
if (-not $SkipSheet -and $pairs.Count -gt 0) {
    $paneW = $SheetPaneW
    $paneH = [int]($paneW * 9 / 16)
    $cellW = $paneW * 2 + 4
    $cellH = $paneH + 28
    $cols  = [Math]::Min($SheetCols, $pairs.Count)
    $rowN  = [Math]::Ceiling($pairs.Count / $cols)

    $sheet = New-Object System.Drawing.Bitmap (($cellW * $cols), ($cellH * $rowN))
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(18, 18, 20))
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $font  = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 200, 205))
        for ($i = 0; $i -lt $pairs.Count; $i++) {
            $col = $i % $cols; $row = [int][Math]::Floor($i / $cols)
            $x = $col * $cellW; $y = $row * $cellH
            $b = [System.Drawing.Image]::FromFile((Join-Path $beforeDir "$($pairs[$i]).png"))
            $a = [System.Drawing.Image]::FromFile((Join-Path $afterDir  "$($pairs[$i]).png"))
            try {
                $g.DrawImage($b, $x, ($y + 24), $paneW, $paneH)
                $g.DrawImage($a, ($x + $paneW + 4), ($y + 24), $paneW, $paneH)
            } finally { $b.Dispose(); $a.Dispose() }
            $g.DrawString($pairs[$i], $font, $brush, ($x + 6), ($y + 4))
        }
        $font.Dispose(); $brush.Dispose()
    } finally { $g.Dispose() }

    $sheetPath = Join-Path $OutDir 'contact-sheet.png'
    $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $sheet.Dispose()
    Write-Host "  sheet  : $sheetPath" -ForegroundColor Green
}
