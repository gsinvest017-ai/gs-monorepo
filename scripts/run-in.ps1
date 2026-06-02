# Run a command inside every submodule directory
# Usage: .\run-in.ps1 "git log --oneline -1"
param(
    [Parameter(Mandatory)][string]$Command
)

$root = Split-Path $PSScriptRoot -Parent
$submodules = git -C $root submodule --quiet foreach --recursive 'echo $name'

foreach ($sm in $submodules) {
    $smPath = Join-Path $root $sm
    Write-Host "=== $sm ===" -ForegroundColor Cyan
    Push-Location $smPath
    Invoke-Expression $Command
    Pop-Location
}
