# Pull all submodules to their latest remote HEAD
param(
    [switch]$Rebase
)

$flag = if ($Rebase) { "--rebase" } else { "--merge" }
Write-Host "Updating all submodules ($flag)..." -ForegroundColor Cyan
git submodule update --remote $flag --recursive
Write-Host "Done." -ForegroundColor Green
