# Show git status for every submodule
$root = Split-Path $PSScriptRoot -Parent

git -C $root submodule foreach --recursive `
    'echo "=== $name ===" && git log --oneline -3 && git status --short'
