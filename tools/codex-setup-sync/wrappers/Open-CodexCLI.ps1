#Requires -Version 5.1

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs
)

$toolRoot = Split-Path -Parent $PSScriptRoot
$toolScript = Join-Path $toolRoot "codex-setup-sync.ps1"

& $toolScript sync
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& codex @CodexArgs
exit $LASTEXITCODE
