<#
.SYNOPSIS
  Розміри безпосередніх дочірніх елементів (папок і файлів) каталогу.
.DESCRIPTION
  Лише читання. Обходить дерево через .NET (значно швидше за Get-ChildItem -Recurse),
  не заходить у точки повторного аналізу (junction/symlink), мовчки пропускає недоступні папки.
.EXAMPLE
  .\dirsizes.ps1 -Root D:\ -Top 40
#>
param(
    [Parameter(Mandatory)][string]$Root,
    [int]$Top = 30,
    [double]$MinGB = 0
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

$items = New-Object System.Collections.Generic.List[object]
$rootInfo = New-Object System.IO.DirectoryInfo($Root)
foreach ($sd in $rootInfo.EnumerateDirectories()) {
    $isLink = ($sd.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    $size = if ($isLink) { 0 } else { Get-DirSize $sd.FullName }
    $items.Add([pscustomobject]@{ Type = 'D'; Name = $sd.Name; GB = [math]::Round($size / 1GB, 2); Link = $isLink; Modified = $sd.LastWriteTime.ToString('yyyy-MM-dd') })
}
foreach ($f in $rootInfo.EnumerateFiles()) {
    try { $items.Add([pscustomobject]@{ Type = 'F'; Name = $f.Name; GB = [math]::Round($f.Length / 1GB, 2); Link = $false; Modified = $f.LastWriteTime.ToString('yyyy-MM-dd') }) } catch { }
}

$sum = ($items | Measure-Object GB -Sum).Sum
$items | Where-Object { $_.GB -ge $MinGB } | Sort-Object GB -Descending | Select-Object -First $Top |
    Format-Table -AutoSize | Out-String -Width 250
"Разом усі дочірні елементи: {0:N2} ГБ ({1} шт.)" -f $sum, $items.Count
