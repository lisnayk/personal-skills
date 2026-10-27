#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Стискає VHDX-файли WSL2 і Docker Desktop, щоб звільнене всередині місце повернулося на диск хоста.
.DESCRIPTION
  Призначений для запуску САМИМ КОРИСТУВАЧЕМ у PowerShell від адміністратора. Нічого не видаляє
  всередині віртуальних дисків — лише зменшує файли. Але зупиняє WSL (wsl --shutdown), тож
  збережи роботу й спершу закрий Docker Desktop через іконку в треї (закрити вікно замало).

  Кроки: знайти VHDX -> відмовитися працювати, якщо Docker Desktop запущено -> fstrim у кожному
  дистрибутиві -> wsl --shutdown -> дочекатися, поки ВМ WSL справді зникне -> Optimize-VHD
  (або diskpart як запасний варіант) -> вивести розміри до і після.

  Пошук дисків читає HKCU, тому запускай від імені того самого облікового запису Windows,
  якому належить WSL, або передай -Paths явно.
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
        # Docker Desktop тримає диск даних поруч із папкою дистрибутива: <...>\DockerDesktopWSL\disk\docker_data.vhdx
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
    Write-Host 'Процеси, які можуть тримати WSL запущеною:' -ForegroundColor Yellow
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
        if ($LASTEXITCODE -ne 0) { throw "diskpart завершився з кодом $LASTEXITCODE" }
    } finally {
        Remove-Item $script -Force -ErrorAction SilentlyContinue
    }
}

if (-not $Paths) { $Paths = @(Get-DefaultVhdx) }
if (-not $Paths) { throw 'VHDX-файли не знайдено. Передай їх через -Paths.' }

Write-Host 'Диски для стискання:' -ForegroundColor Cyan
$Paths | ForEach-Object { Write-Host "  $_" }

if (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue) {
    Write-Warning 'Docker Desktop запущено. Закрий його через іконку в треї (Quit Docker Desktop) і запусти скрипт ще раз.'
    exit 1
}

if (-not $SkipTrim) {
    foreach ($d in Get-WslDistros | Where-Object { $_.Name -notlike 'docker-desktop*' }) {
        Write-Host "fstrim у $($d.Name)..." -ForegroundColor Cyan
        & wsl.exe -d $d.Name -u root -e fstrim -av 2>&1 | Write-Host
    }
}

Write-Host 'Зупиняю WSL (wsl --shutdown)...' -ForegroundColor Cyan
& wsl.exe --shutdown

$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Test-WslRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
if (Test-WslRunning) {
    Write-Warning "WSL усе ще працює через $WaitSeconds с — її хтось знову запустив."
    Show-WslClients
    Write-Warning 'Закрий ці клієнти (Docker Desktop, WSL-термінали, віддалені сесії IDE, Codex) і запусти скрипт ще раз.'
    exit 1
}
# Процес ВМ може зникнути на кілька секунд раніше, ніж звільняться дескриптори дисків.
Start-Sleep -Seconds 8

$useHyperV = [bool](Get-Command Optimize-VHD -ErrorAction SilentlyContinue)
if (-not $useHyperV) { Write-Host 'Optimize-VHD (модуль Hyper-V) не знайдено — використовую diskpart.' -ForegroundColor Yellow }

$results = foreach ($vhdx in $Paths) {
    $before = (Get-Item $vhdx).Length
    $status = 'ok'
    Write-Host "Стискаю $vhdx ..." -ForegroundColor Cyan
    try {
        if ($useHyperV) { Optimize-VHD -Path $vhdx -Mode Full -ErrorAction Stop } else { Compress-WithDiskpart $vhdx }
    } catch {
        $status = $_.Exception.Message
        if ($status -match '0x80070020') {
            $status = 'файл зайнятий — WSL або Docker знову запустилися'
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
Write-Host 'Готово. Можна знову запускати Docker Desktop і WSL.' -ForegroundColor Green
