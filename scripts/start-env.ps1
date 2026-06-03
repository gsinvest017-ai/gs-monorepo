#Requires -Version 7
# scripts/start-env.ps1 — 啟動指定環境的服務（不觸碰任何 submodule 檔案）
#
# 用法：
#   .\scripts\start-env.ps1 -Env prod                    # 全部 prod 服務（背景）
#   .\scripts\start-env.ps1 -Env test                    # 全部 test 服務（背景）
#   .\scripts\start-env.ps1 -Env test -Service tw-news-board          # 單一（前景）
#   .\scripts\start-env.ps1 -Env test -Service tw-news-board -Detach  # 單一（背景）
#   .\scripts\start-env.ps1 -Env prod -DryRun             # 只印指令，不執行
#
# PID 與 log 存於 run/{env}/{service}.pid / .log（已加進 .gitignore）

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("prod","test")]
    [string]$Env,

    [string]$Service = "",   # 空 = 全部；指定名稱 = 單一服務

    [switch]$Detach,         # 強制背景執行（預設：單服務前景，多服務背景）

    [switch]$DryRun          # 僅印出會執行的指令，不真正啟動
)

$ErrorActionPreference = "Stop"
$MonoRoot  = Split-Path -Parent $PSScriptRoot
$RunDir    = Join-Path $MonoRoot "run\$Env"

# ── 載入服務定義表 ──────────────────────────────────────────────────────────
. (Join-Path $MonoRoot "configs\services.ps1")

# ── 工具函式：載入 .env 檔為 hashtable ─────────────────────────────────────
function Read-EnvFile([string]$path) {
    $vars = @{}
    if (-not (Test-Path $path)) { return $vars }
    foreach ($line in (Get-Content $path -Encoding utf8)) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -gt 0) {
            $k = $line.Substring(0, $idx).Trim()
            $v = $line.Substring($idx + 1).Trim()
            $vars[$k] = $v
        }
    }
    return $vars
}

# ── 核心：啟動單一服務 ────────────────────────────────────────────────────
function Start-GsService([string]$name, [hashtable]$svcDef) {
    $envCfg = $svcDef[$Env]

    # Test = $null 表示此服務不支援測試環境
    if ($null -eq $envCfg) {
        $note = if ($svcDef.ContainsKey("Note")) { "  Note: $($svcDef.Note)" } else { "" }
        Write-Host "  SKIP  $name ($Env 環境不支援)$note" -ForegroundColor DarkYellow
        return
    }

    $port    = $envCfg.Port
    $hostIP  = $envCfg.HostIP
    $cmd     = $envCfg.Cmd          # string[] — Cmd[0] = exe, Cmd[1..] = args
    $exeRaw  = $cmd[0]
    $argList = if ($cmd.Count -gt 1) { $cmd[1..($cmd.Count - 1)] } else { @() }

    # ── 設定 env vars（優先順序：services.ps1 EnvVars → .env 檔覆蓋） ──
    foreach ($kv in $envCfg.EnvVars.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
    }
    $envFile = Join-Path $MonoRoot "envs\$Env\$name.env"
    foreach ($kv in (Read-EnvFile $envFile).GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
    }

    # ── 解析 exe 路徑（相對路徑以 submodule 目錄為基準） ───────────────
    $subDir = Join-Path $MonoRoot $svcDef.SubPath
    $exeAbs = if ([System.IO.Path]::IsPathRooted($exeRaw)) {
        $exeRaw
    } else {
        Join-Path $subDir $exeRaw
    }

    $portLabel = "port $port"
    $addrLabel = "$hostIP`:$port"

    Write-Host ""
    Write-Host "  [$Env] $name" -ForegroundColor Cyan
    Write-Host "    dir  : $subDir"
    Write-Host "    addr : $addrLabel"
    Write-Host "    cmd  : $exeAbs $($argList -join ' ')"

    if ($DryRun) {
        Write-Host "    (DryRun — 不執行)" -ForegroundColor DarkGray
        return
    }

    # ── 確認 exe 存在（相對路徑才檢查，外部指令如 python/pwsh 略過） ────
    if ($exeRaw -match '\\' -and -not (Test-Path $exeAbs)) {
        Write-Warning "    exe 不存在：$exeAbs  （請先在 $($svcDef.SubPath) 建立 venv）"
        return
    }

    # ── 決定前景或背景 ───────────────────────────────────────────────────
    $runInBg = $Detach -or ($Service -eq "")   # 全部服務 → 強制背景

    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $pidFile = Join-Path $RunDir "$name.pid"
    $logFile = Join-Path $RunDir "$name.log"
    $errFile = Join-Path $RunDir "$name.err"

    if ($runInBg) {
        # ── 背景啟動，寫 PID 檔 ─────────────────────────────────────────
        $proc = Start-Process `
            -FilePath       $exeAbs `
            -ArgumentList   $argList `
            -WorkingDirectory $subDir `
            -PassThru `
            -RedirectStandardOutput $logFile `
            -RedirectStandardError  $errFile
        $proc.Id | Set-Content $pidFile -Encoding utf8
        Write-Host "    PID  : $($proc.Id)  →  $pidFile" -ForegroundColor Green
        Write-Host "    log  : $logFile"
    } else {
        # ── 前景啟動（Ctrl-C 結束） ─────────────────────────────────────
        Write-Host "    (前景執行，Ctrl-C 結束)" -ForegroundColor DarkGray
        Push-Location $subDir
        try { & $exeAbs @argList }
        finally { Pop-Location }
    }
}

# ── 主流程 ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ start-env : ENV=$Env $(if($Service){"SERVICE=$Service"}else{'(全部服務)'})" `
           -ForegroundColor Magenta

if ($Service) {
    # 單一服務
    if (-not $GS_SERVICES.Contains($Service)) {
        $available = $GS_SERVICES.Keys -join ", "
        Write-Error "未知服務: '$Service'。可用：$available"
    }
    Start-GsService $Service $GS_SERVICES[$Service]
} else {
    # 全部服務（依定義順序）
    foreach ($kv in $GS_SERVICES.GetEnumerator()) {
        Start-GsService $kv.Key $kv.Value
    }
    Write-Host ""
    Write-Host "▶ 全部服務已啟動（背景）。使用 .\scripts\status-env.ps1 查看狀態。" `
               -ForegroundColor Magenta
}
