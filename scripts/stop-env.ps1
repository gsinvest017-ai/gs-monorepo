#Requires -Version 7
# scripts/stop-env.ps1 — 停止指定環境的服務
#
# 用法：
#   .\scripts\stop-env.ps1 -Env prod                     # 停止全部 prod 服務
#   .\scripts\stop-env.ps1 -Env test -Service tw-news-board  # 停止單一服務
#   .\scripts\stop-env.ps1 -Env test -Force              # 強制 Kill（SIGKILL）

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("prod","test")]
    [string]$Env,

    [string]$Service = "",   # 空 = 全部

    [switch]$Force           # 強制 Kill（否則先嘗試 CloseMainWindow / graceful）
)

$ErrorActionPreference = "Stop"
$MonoRoot = Split-Path -Parent $PSScriptRoot
$RunDir   = Join-Path $MonoRoot "run\$Env"

. (Join-Path $MonoRoot "configs\services.ps1")

function Stop-GsService([string]$name) {
    $pidFile = Join-Path $RunDir "$name.pid"

    if (-not (Test-Path $pidFile)) {
        Write-Host "  $name : 無 PID 檔（未由 start-env.ps1 啟動，或已停止）" `
                   -ForegroundColor DarkGray
        return
    }

    $pidStr = (Get-Content $pidFile -Encoding utf8 -Raw).Trim()
    if (-not $pidStr) {
        Write-Host "  $name : PID 檔為空，略過" -ForegroundColor DarkGray
        Remove-Item $pidFile -Force
        return
    }

    $pid = [int]$pidStr
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue

    if (-not $proc) {
        Write-Host "  $name : PID $pid 已不存在（程序已停止）" -ForegroundColor DarkGray
        Remove-Item $pidFile -Force
        return
    }

    try {
        if ($Force) {
            $proc | Stop-Process -Force
            Write-Host "  $name : PID $pid  →  強制終止 (Kill)" -ForegroundColor Yellow
        } else {
            # 先嘗試 graceful（讓程序自行清理），等 5 秒後再 Kill
            $proc.CloseMainWindow() | Out-Null
            $exited = $proc.WaitForExit(5000)
            if (-not $exited) {
                $proc | Stop-Process -Force
                Write-Host "  $name : PID $pid  →  Graceful 超時，強制終止" `
                           -ForegroundColor Yellow
            } else {
                Write-Host "  $name : PID $pid  →  正常停止" -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "  $name : 停止失敗 — $($_.Exception.Message)"
    } finally {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "▶ stop-env : ENV=$Env $(if($Service){"SERVICE=$Service"}else{'(全部服務)'})" `
           -ForegroundColor Magenta

if ($Service) {
    if (-not $GS_SERVICES.Contains($Service)) {
        $available = $GS_SERVICES.Keys -join ", "
        Write-Error "未知服務: '$Service'。可用：$available"
    }
    Stop-GsService $Service
} else {
    foreach ($name in $GS_SERVICES.Keys) {
        Stop-GsService $name
    }
    Write-Host ""
    Write-Host "▶ 完成。" -ForegroundColor Magenta
}
