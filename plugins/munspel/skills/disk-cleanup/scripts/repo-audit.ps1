<#
.SYNOPSIS
  Git state of every project folder under a directory: is it safe to remove the local copy?
.DESCRIPTION
  Read-only. Uses `git -c safe.directory=*` so repos owned by an old Windows SID can be read
  without touching the global git config, and --no-optional-locks so the index is not rewritten.

  Verdict:
    safe        - has a remote, no uncommitted changes, no unpushed commits, no stash
    local-work  - something exists only locally (see Dirty / Unpushed / Stash / Remote)
    no-git      - not a git repo: everything in it exists only here
  Gitignored files (.env, local dumps) are never on the remote - check HasEnv before removing.
  Dirty can be inflated by CRLF / filemode differences when Windows git reads repos made elsewhere.
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

"== Summary by verdict"
$rows | Group-Object Verdict | ForEach-Object {
    [pscustomobject]@{ Verdict = $_.Name; Count = $_.Count; GB = [math]::Round(($_.Group | Measure-Object GB -Sum).Sum, 2) }
} | Format-Table -AutoSize | Out-String -Width 250

$rows | Sort-Object GB -Descending | Format-Table -AutoSize | Out-String -Width 250
