#Requires -Version 5.1

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs
)

$toolRoot = Split-Path -Parent $PSScriptRoot
$toolScript = Join-Path $toolRoot "codex-setup-sync.ps1"

& $toolScript sync
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$appCommand = $env:CODEX_SETUP_SYNC_APP
if (-not $appCommand) {
    Write-Host "Set CODEX_SETUP_SYNC_APP or enable generated launch wrappers in your sync config." -ForegroundColor Yellow
    exit 1
}

if ($AppArgs.Count -gt 0) {
    Start-Process -FilePath $appCommand -ArgumentList $AppArgs | Out-Null
} else {
    Start-Process -FilePath $appCommand | Out-Null
}
