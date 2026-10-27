#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Compacts WSL2 and Docker Desktop VHDX files so space freed inside them goes back to the host drive.
.DESCRIPTION
  Meant to be run BY THE USER in an elevated PowerShell. It does not delete anything inside the
  virtual disks - it only shrinks the files. It does stop WSL (wsl --shutdown), so save your work
  and quit Docker Desktop from the tray icon first (closing its window is not enough).

  Steps: find VHDX files -> refuse to run while Docker Desktop is up -> fstrim each distro ->
  wsl --shutdown -> wait until the WSL VM is really gone -> Optimize-VHD (or diskpart fallback)
  -> print sizes before/after.

  Disk discovery reads HKCU, so run it elevated from the same Windows account that owns WSL,
  or pass -Paths explicitly.
.EXAMPLE
  .\compact-vhdx.ps1
.EXAMPLE
  .\compact-vhdx.ps1 -Paths D:\wsl\Ubuntu\ext4.vhdx -SkipTrim
#>
param(
    [string[]]$Paths,
    [switch]$SkipTrim,
    [int]$WaitSeconds = 60
)

function Get-WslDistros {
    Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        [pscustomobject]@{ Name = $p.DistributionName; BasePath = ($p.BasePath -replace '^\\\\\?\\', '') }
    }
}

function Get-DefaultVhdx {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($d in Get-WslDistros) {
        $own = Join-Path $d.BasePath 'ext4.vhdx'
        if ($d.Name -notlike 'docker-desktop*' -and (Test-Path $own)) { $list.Add($own) }
        # Docker Desktop keeps its data disk next to the distro folder: <...>\DockerDesktopWSL\disk\docker_data.vhdx
        $dockerData = Join-Path (Split-Path $d.BasePath -Parent) 'disk\docker_data.vhdx'
        if (Test-Path $dockerData) { $list.Add($dockerData) }
    }
    $defaultDocker = Join-Path $env:LOCALAPPDATA 'Docker\wsl\disk\docker_data.vhdx'
    if (Test-Path $defaultDocker) { $list.Add($defaultDocker) }
    $list | ForEach-Object { (Resolve-Path $_).Path } | Sort-Object -Unique
}

function Test-WslRunning {
    if (Get-Process vmmemWSL -ErrorAction SilentlyContinue) { return $true }
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $out = (& wsl.exe --list --verbose 2>$null) -join "`n"
    } finally {
        [Console]::OutputEncoding = $prev
    }
    return $out -match '\bRunning\b'
}

function Show-WslClients {
    Write-Host 'Processes that may keep WSL alive:' -ForegroundColor Yellow
    $all = Get-CimInstance Win32_Process
    $byId = @{}
    foreach ($p in $all) { $byId[$p.ProcessId] = $p }
    $all | Where-Object { $_.Name -in 'wsl.exe', 'wslhost.exe', 'wslrelay.exe' -or $_.Name -like 'Docker Desktop*' -or $_.Name -like 'com.docker*' } |
        ForEach-Object {
            $parent = $byId[$_.ParentProcessId]
            [pscustomobject]@{ Pid = $_.ProcessId; Name = $_.Name; Parent = if ($parent) { "$($parent.Name) ($($parent.ProcessId))" } else { '-' } }
        } | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}

function Compress-WithDiskpart([string]$vhdx) {
    $script = New-TemporaryFile
    try {
        @(
            "select vdisk file=`"$vhdx`""
            'attach vdisk readonly'
            'compact vdisk'
            'detach vdisk'
        ) | Set-Content -Path $script -Encoding ASCII
        & diskpart.exe /s $script | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "diskpart exited with code $LASTEXITCODE" }
    } finally {
        Remove-Item $script -Force -ErrorAction SilentlyContinue
    }
}

if (-not $Paths) { $Paths = @(Get-DefaultVhdx) }
if (-not $Paths) { throw 'No VHDX files found. Pass them with -Paths.' }

Write-Host 'Disks to compact:' -ForegroundColor Cyan
$Paths | ForEach-Object { Write-Host "  $_" }

if (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue) {
    Write-Warning 'Docker Desktop is running. Quit it from the tray icon (Quit Docker Desktop) and run this script again.'
    exit 1
}

if (-not $SkipTrim) {
    foreach ($d in Get-WslDistros | Where-Object { $_.Name -notlike 'docker-desktop*' }) {
        Write-Host "fstrim in $($d.Name)..." -ForegroundColor Cyan
        & wsl.exe -d $d.Name -u root -e fstrim -av 2>&1 | Write-Host
    }
}

Write-Host 'Stopping WSL (wsl --shutdown)...' -ForegroundColor Cyan
& wsl.exe --shutdown

$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Test-WslRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
if (Test-WslRunning) {
    Write-Warning "WSL is still running after $WaitSeconds s - something restarted it."
    Show-WslClients
    Write-Warning 'Close those clients (Docker Desktop, WSL terminals, IDE remote sessions, Codex), then run the script again.'
    exit 1
}
# The VM process can be gone a few seconds before the disk handles are released.
Start-Sleep -Seconds 8

$useHyperV = [bool](Get-Command Optimize-VHD -ErrorAction SilentlyContinue)
if (-not $useHyperV) { Write-Host 'Optimize-VHD (Hyper-V module) not found - using diskpart.' -ForegroundColor Yellow }

$results = foreach ($vhdx in $Paths) {
    $before = (Get-Item $vhdx).Length
    $status = 'ok'
    Write-Host "Compacting $vhdx ..." -ForegroundColor Cyan
    try {
        if ($useHyperV) { Optimize-VHD -Path $vhdx -Mode Full -ErrorAction Stop } else { Compress-WithDiskpart $vhdx }
    } catch {
        $status = $_.Exception.Message
        if ($status -match '0x80070020') {
            $status = 'file is in use - WSL or Docker started again'
            Show-WslClients
        }
        Write-Warning $status
    }
    $after = (Get-Item $vhdx).Length
    [pscustomobject]@{
        Disk     = $vhdx
        BeforeGB = [math]::Round($before / 1GB, 2)
        AfterGB  = [math]::Round($after / 1GB, 2)
        FreedGB  = [math]::Round(($before - $after) / 1GB, 2)
        Status   = $status
    }
}

$results | Format-Table -AutoSize | Out-String -Width 250 | Write-Host
Write-Host 'Done. You can start Docker Desktop and WSL again.' -ForegroundColor Green
