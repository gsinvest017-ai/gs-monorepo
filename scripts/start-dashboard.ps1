#Requires -Version 5
# scripts/start-dashboard.ps1 — 啟動 GS Service Monitor Dashboard
#
# 用法：
#   .\scripts\start-dashboard.ps1                       # http://0.0.0.0:9000
#   .\scripts\start-dashboard.ps1 -Port 9001
#   .\scripts\start-dashboard.ps1 -BindHost 127.0.0.1  # 僅本機
#   .\scripts\start-dashboard.ps1 -Open                 # 啟動後自動開瀏覽器
#   .\scripts\start-dashboard.ps1 -Detach               # 背景執行（記錄 PID）
# Note: $Host 是 PowerShell 內建唯讀變數，故用 -BindHost。

[CmdletBinding()]
param(
    [int]$Port        = 9000,
    [string]$BindHost = "0.0.0.0",
    [switch]$Open,
    [switch]$Detach
)

$ErrorActionPreference = "Stop"
$MonoRoot   = Split-Path -Parent $PSScriptRoot
$ServerPy   = Join-Path $MonoRoot "dashboard\server.py"
$RunDir     = Join-Path $MonoRoot "run"

# locate python
$py = $null
foreach ($cand in @("python", "python3", "py")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) {
    Write-Error "Python not found on PATH."
    exit 1
}

$pyArgs = @($ServerPy, "--port", $Port, "--host", $BindHost)

$localUrl = "http://127.0.0.1:$Port/"
$lanUrl   = "http://192.168.0.249:$Port/"

Write-Host ""
Write-Host "  ◆ GS Service Monitor" -ForegroundColor DarkYellow
Write-Host ("  local   : " + $localUrl)
Write-Host ("  LAN     : " + ($BindHost -eq "0.0.0.0" ? $lanUrl : "(loopback-only)"))
Write-Host "  (Ctrl-C to stop)"
Write-Host ""

if ($Detach) {
    New-Item -ItemType Directory -Force -Path "$RunDir\meta" | Out-Null
    $log = "$RunDir\meta\dashboard.log"
    $err = "$RunDir\meta\dashboard.err"
    $pid_f = "$RunDir\meta\dashboard.pid"
    $proc = Start-Process -FilePath $py -ArgumentList $pyArgs `
                          -WorkingDirectory $MonoRoot -PassThru `
                          -RedirectStandardOutput $log -RedirectStandardError $err
    $proc.Id | Set-Content $pid_f -Encoding utf8
    Write-Host "  PID $($proc.Id) → $pid_f" -ForegroundColor Green
    if ($Open) { Start-Process $localUrl }
} else {
    if ($Open) {
        Start-Sleep -Seconds 1
        Start-Process $localUrl
    }
    & $py @pyArgs
}
