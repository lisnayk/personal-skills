<#
.SYNOPSIS
  Finds regenerable dependency folders (node_modules, vendor, .venv, ...) and their sizes.
.DESCRIPTION
  Read-only. Does not descend into a matched folder (nested node_modules are counted once,
  as part of the outer one), skips .git, reparse points, $RECYCLE.BIN and System Volume Information.
  "Installed" is the folder's LastWriteTime - a rough hint of when dependencies were last installed.
.EXAMPLE
  .\find-deps-dirs.ps1 -Roots D:\OS\domains, D:\projects -Csv C:\tmp\deps.csv
#>
param(
    [Parameter(Mandatory)][string[]]$Roots,
    [string[]]$Names = @('node_modules', 'vendor', '.venv', 'venv'),
    [int]$Top = 25,
    [string]$Csv
)

function Get-DirSize([string]$path) {
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($path)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo($d)
            foreach ($f in $di.EnumerateFiles()) { $total += $f.Length }
            foreach ($sd in $di.EnumerateDirectories()) {
                if (($sd.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($sd.FullName) }
            }
        } catch { }
    }
    return $total
}

$skip = @('.git', '$RECYCLE.BIN', 'System Volume Information')
$found = New-Object System.Collections.Generic.List[object]

foreach ($root in $Roots) {
    $rootFull = (New-Object System.IO.DirectoryInfo($root)).FullName.TrimEnd('\')
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($rootFull)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try { $subs = (New-Object System.IO.DirectoryInfo($d)).GetDirectories() } catch { continue }
        foreach ($sd in $subs) {
            if (($sd.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($skip -contains $sd.Name) { continue }
            if ($Names -contains $sd.Name) {
                $rel = $sd.FullName.Substring($rootFull.Length).TrimStart('\')
                $found.Add([pscustomobject]@{
                    Kind      = $sd.Name
                    GB        = [math]::Round((Get-DirSize $sd.FullName) / 1GB, 2)
                    Installed = $sd.LastWriteTime.ToString('yyyy-MM-dd')
                    Area      = Join-Path $rootFull ($rel.Split('\')[0])
                    Path      = $sd.FullName
                })
            } else {
                $stack.Push($sd.FullName)
            }
        }
    }
}

if ($Csv) { $found | Export-Csv -NoTypeInformation -Encoding UTF8 $Csv }

"== By kind"
$found | Group-Object Kind | ForEach-Object {
    [pscustomobject]@{ Kind = $_.Name; Count = $_.Count; GB = [math]::Round(($_.Group | Measure-Object GB -Sum).Sum, 2) }
} | Sort-Object GB -Descending | Format-Table -AutoSize | Out-String -Width 250

"== By area (first level under each root)"
$found | Group-Object Area | ForEach-Object {
    [pscustomobject]@{ GB = [math]::Round(($_.Group | Measure-Object GB -Sum).Sum, 2); Count = $_.Count; Area = $_.Name }
} | Sort-Object GB -Descending | Select-Object -First $Top | Format-Table -AutoSize | Out-String -Width 250

"== Largest folders"
$found | Sort-Object GB -Descending | Select-Object -First $Top GB, Installed, Path | Format-Table -AutoSize | Out-String -Width 300
