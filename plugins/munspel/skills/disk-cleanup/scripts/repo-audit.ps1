<#
.SYNOPSIS
  Стан git для кожної папки проєкту в каталозі: чи можна безпечно видалити локальну копію?
.DESCRIPTION
  Лише читання. Використовує `git -c safe.directory=*`, щоб читати репозиторії, які належать
  SID старої інсталяції Windows, не чіпаючи глобальний конфіг git, і --no-optional-locks,
  щоб не переписувати index.

  Вердикт:
    safe        - є remote, немає незакомічених змін, незапушених комітів і stash
    local-work  - щось існує лише локально (див. Dirty / Unpushed / Stash / Remote)
    no-git      - не git-репозиторій: усе в ньому існує лише тут
  Файли з .gitignore (.env, локальні дампи) ніколи не потрапляють на remote — перед видаленням
  перевір HasEnv. Dirty може бути завищене через різницю CRLF / filemode, коли Windows git
  читає репозиторії, створені деінде.
.EXAMPLE
  .\repo-audit.ps1 -Root D:\OS\domains -CompareWith \\wsl.localhost\Ubuntu\home\me\projects -Csv C:\tmp\repos.csv
#>
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$CompareWith,
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

function Invoke-Git([string]$repo, [string[]]$gitArgs) {
    & git -c 'safe.directory=*' -C $repo --no-optional-locks @gitArgs 2>$null
}

$twins = @{}
if ($CompareWith) {
    Get-ChildItem $CompareWith -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $twins[$_.Name] = $true }
}

$rows = foreach ($d in Get-ChildItem $Root -Directory -Force) {
    $p = $d.FullName
    $isGit = Test-Path (Join-Path $p '.git')
    $remote = ''; $dirty = ''; $unpushed = ''; $stash = ''; $last = ''; $verdict = 'no-git'
    if ($isGit) {
        $remote   = if (Invoke-Git $p @('remote')) { 'yes' } else { 'no' }
        $dirty    = @(Invoke-Git $p @('status', '--porcelain')).Count
        $unpushed = @(Invoke-Git $p @('log', '--branches', '--not', '--remotes', '--oneline')).Count
        $stash    = @(Invoke-Git $p @('stash', 'list')).Count
        $last     = Invoke-Git $p @('log', '-1', '--format=%cs')
        $verdict  = if ($remote -eq 'yes' -and $dirty -eq 0 -and $unpushed -eq 0 -and $stash -eq 0) { 'safe' } else { 'local-work' }
    }
    [pscustomobject]@{
        Name       = $d.Name
        GB         = [math]::Round((Get-DirSize $p) / 1GB, 2)
        Verdict    = $verdict
        Remote     = $remote
        Dirty      = $dirty
        Unpushed   = $unpushed
        Stash      = $stash
        HasEnv     = [bool](Get-ChildItem $p -Filter '.env*' -File -Force -ErrorAction SilentlyContinue | Where-Object Name -notmatch '\.example$|\.dist$|\.sample$')
        LastCommit = $last
        Twin       = if ($CompareWith) { $twins.ContainsKey($d.Name) } else { '' }
    }
}

if ($Csv) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 $Csv }

"== Підсумок за вердиктом"
$rows | Group-Object Verdict | ForEach-Object {
    [pscustomobject]@{ Verdict = $_.Name; Count = $_.Count; GB = [math]::Round(($_.Group | Measure-Object GB -Sum).Sum, 2) }
} | Format-Table -AutoSize | Out-String -Width 250

$rows | Sort-Object GB -Descending | Format-Table -AutoSize | Out-String -Width 250
