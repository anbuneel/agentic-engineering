#Requires -Version 5.1

<#
.SYNOPSIS
    Sync portable Codex workstation setup across Windows machines.

.DESCRIPTION
    codex-setup-sync manages a git-backed sync repository for portable Codex
    configuration, rules, memories, skills, and optional session history.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$script:ToolName = "codex-setup-sync"
$script:ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Version = "0.1.0"

. (Join-Path $script:ToolRoot "lib\common.ps1")
. (Join-Path $script:ToolRoot "lib\config.ps1")
. (Join-Path $script:ToolRoot "lib\git.ps1")
. (Join-Path $script:ToolRoot "lib\identity.ps1")
. (Join-Path $script:ToolRoot "lib\sessions.ps1")
. (Join-Path $script:ToolRoot "lib\render.ps1")
. (Join-Path $script:ToolRoot "lib\doctor.ps1")
. (Join-Path $script:ToolRoot "providers\codex.ps1")
. (Join-Path $script:ToolRoot "lib\sync.ps1")

function Show-Usage {
    Write-Host @"
$script:ToolName $script:Version -- Sync portable Codex setup across machines

Usage: $script:ToolName.ps1 <command> [options]

Commands:
  setup <repo-url>                   Clone sync repo, write config, bootstrap state
  setup --init                       Initialize a local sync repo without a remote
  doctor                             Validate config, paths, git, and exclusions
  status                             Show sync status and pending exports
  push                               Export managed state, commit, pull --rebase, push
  pull                               Pull from sync repo, import managed state locally
  sync                               Run push then pull
  alias add <local-path> <id>        Add a manual project identity alias
  alias detect [path]                Detect and save canonical ID from git remote
  config print                       Print resolved tool configuration as JSON
  session export                     Export completed session files
  session import                     Import exported session files if enabled

Options:
  --help                             Show this help
  --version                          Show version

Environment:
  CODEX_SETUP_SYNC_CONFIG            Override local config file path
"@
}

try {
    if (-not $Command -or $Command -in @("--help", "-h", "help")) {
        Show-Usage
        exit 0
    }

    if ($Command -in @("--version", "-v", "version")) {
        Write-Host $script:Version
        exit 0
    }

    switch ($Command) {
        "setup"   { Invoke-SetupCommand -Arguments $Arguments }
        "doctor"  { Invoke-DoctorCommand }
        "status"  { Invoke-StatusCommand }
        "push"    { Invoke-PushCommand }
        "pull"    { Invoke-PullCommand }
        "sync"    { Invoke-SyncCommand }
        "alias"   { Invoke-AliasCommand -Arguments $Arguments }
        "config"  { Invoke-ConfigCommand -Arguments $Arguments }
        "session" { Invoke-SessionCommand -Arguments $Arguments }
        default   { Throw-ToolError "Unknown command '$Command'. Run --help for usage." 1 }
    }
} catch {
    $message = if ($_.Exception.Message) { $_.Exception.Message } else { $_.ToString() }
    Write-Host "error: $message" -ForegroundColor Red
    exit (Get-ToolExitCode -ErrorRecord $_)
}
