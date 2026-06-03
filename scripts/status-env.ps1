#Requires -Version 7
# scripts/status-env.ps1 — 查看所有服務的 prod / test 狀態
#
# 輸出欄位對齊 gs-gh-summary repo_paths panel：
#   Service / Path / HostIP / Port / Status / PID
#
# 用法：
#   .\scripts\status-env.ps1           # prod + test 並排
#   .\scripts\status-env.ps1 -Env prod # 只看 prod
#   .\scripts\status-env.ps1 -Env test # 只看 test

[CmdletBinding()]
param(
    [ValidateSet("prod","test","both")]
    [string]$Env = "both"
)

$ErrorActionPreference = "Stop"
$MonoRoot = Split-Path -Parent $PSScriptRoot
$RunDir   = Join-Path $MonoRoot "run"

. (Join-Path $MonoRoot "configs\services.ps1")

function Get-ServiceStatus([string]$name, [hashtable]$svcDef, [string]$env) {
    $envCfg  = $svcDef[$env]
    $pidFile = Join-Path $RunDir "$env\$name.pid"

    if ($null -eq $envCfg) {
        return [pscustomobject]@{
            Service = $name
            Env     = $env
            Port    = "—"
            HostIP  = "—"
            Status  = "N/A"
            PID     = "—"
            Path    = $svcDef.SubPath
        }
    }

    $port   = $envCfg.Port
    $hostIP = $envCfg.HostIP
    $path   = $svcDef.SubPath

    # PID / Status
    $status = "stopped"
    $pidStr = "—"

    if (Test-Path $pidFile) {
        $raw = (Get-Content $pidFile -Encoding utf8 -Raw).Trim()
        if ($raw) {
            $pidVal = [int]$raw
            $proc   = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($proc) {
                $status = "running"
                $pidStr = "$pidVal"
            } else {
                $status = "dead (stale pid)"
                $pidStr = "$pidVal"
            }
        }
    }

    return [pscustomobject]@{
        Service = $name
        Env     = $env
        Port    = $port
        HostIP  = $hostIP
        Status  = $status
        PID     = $pidStr
        Path    = $path
    }
}

function Write-StatusTable([string[]]$envs) {
    $rows = @()
    foreach ($env in $envs) {
        foreach ($kv in $GS_SERVICES.GetEnumerator()) {
            $rows += Get-ServiceStatus $kv.Key $kv.Value $env
        }
    }

    # 欄寬計算
    $w = @{
        Service = ($rows | ForEach-Object { $_.Service.Length } | Measure-Object -Max).Maximum
        Env     = 5
        Port    = ($rows | ForEach-Object { "$($_.Port)".Length } | Measure-Object -Max).Maximum
        HostIP  = ($rows | ForEach-Object { $_.HostIP.Length    } | Measure-Object -Max).Maximum
        Status  = ($rows | ForEach-Object { $_.Status.Length    } | Measure-Object -Max).Maximum
        PID     = 7
        Path    = 30
    }
    $w.Service = [Math]::Max($w.Service, 7)
    $w.Port    = [Math]::Max($w.Port,    4)
    $w.HostIP  = [Math]::Max($w.HostIP,  6)
    $w.Status  = [Math]::Max($w.Status,  6)

    function PadR([string]$s, [int]$n) { $s.PadRight($n) }

    $hdr = "  {0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
        (PadR "Service" $w.Service), `
        (PadR "Env"     $w.Env), `
        (PadR "Port"    $w.Port), `
        (PadR "HostIP"  $w.HostIP), `
        (PadR "Status"  $w.Status), `
        (PadR "PID"     $w.PID), `
        "Path"
    $sep = "  " + ("-" * ($w.Service + $w.Env + $w.Port + $w.HostIP + $w.Status + $w.PID + 30 + 12))

    Write-Host ""
    Write-Host $hdr -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor DarkGray

    $prevSvc = ""
    foreach ($r in $rows) {
        if ($r.Service -ne $prevSvc -and $prevSvc -ne "") {
            Write-Host ""  # 每個服務間空一行
        }
        $prevSvc = $r.Service

        $color = switch ($r.Status) {
            "running"         { "Green" }
            "stopped"         { "DarkGray" }
            "dead (stale pid)"{ "Yellow" }
            "N/A"             { "DarkGray" }
            default           { "White" }
        }
        $line = "  {0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
            (PadR $r.Service $w.Service), `
            (PadR $r.Env     $w.Env), `
            (PadR "$($r.Port)"   $w.Port), `
            (PadR $r.HostIP  $w.HostIP), `
            (PadR $r.Status  $w.Status), `
            (PadR $r.PID     $w.PID), `
            $r.Path

        Write-Host $line -ForegroundColor $color
    }

    Write-Host $sep -ForegroundColor DarkGray
    Write-Host ""

    # 圖例
    Write-Host "  圖例：" -ForegroundColor DarkGray
    Write-Host "    running          — PID 存活，服務正常" -ForegroundColor Green
    Write-Host "    stopped          — 未啟動或已正常停止" -ForegroundColor DarkGray
    Write-Host "    dead (stale pid) — PID 已消失，請手動刪除 run/{env}/{name}.pid" -ForegroundColor Yellow
    Write-Host "    N/A              — 此環境不支援（如 gs-scraper test）" -ForegroundColor DarkGray
    Write-Host ""
}

$envList = switch ($Env) {
    "both" { @("prod","test") }
    "prod" { @("prod") }
    "test" { @("test") }
}

Write-Host ""
Write-Host "▶ status-env : $($envList -join ' + ')" -ForegroundColor Magenta
Write-StatusTable $envList
