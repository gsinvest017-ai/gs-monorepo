# Stage updated submodule SHAs and commit them to the monorepo
param(
    [string]$Message = "chore: sync submodule pins"
)

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$changed = git diff --name-only
if (-not $changed) {
    Write-Host "No submodule changes to sync." -ForegroundColor Yellow
    exit 0
}

git add -A
git commit -m $Message
Write-Host "Synced pins: $Message" -ForegroundColor Green
