<#
.SYNOPSIS
Set the plugin version in every manifest that carries one.

.DESCRIPTION
Claude Code and Codex both install this repo as a plugin and only pick up
changes when the version in the manifest moves. Bump it here before tagging
a release so all four files agree:

  .claude-plugin/plugin.json
  .claude-plugin/marketplace.json   (plugins[].version)
  .codex-plugin/plugin.json
  .agents/plugins/marketplace.json  (no version field today; touched only if one appears)

.EXAMPLE
.\scripts\Set-PluginVersion.ps1 -Version 0.8.1
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Set-VersionField {
    param([string]$Path)

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $changed = $false

    if ($null -ne $json.PSObject.Properties['version']) {
        $json.version = $Version
        $changed = $true
    }

    if ($null -ne $json.PSObject.Properties['plugins']) {
        foreach ($plugin in $json.plugins) {
            if ($null -ne $plugin.PSObject.Properties['version']) {
                $plugin.version = $Version
                $changed = $true
            }
        }
    }

    if (-not $changed) {
        Write-Host "No version field: $Path"
        return
    }

    $text = ($json | ConvertTo-Json -Depth 10) + "`n"
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Set $Version in $Path"
}

$manifests = @(
    '.claude-plugin\plugin.json',
    '.claude-plugin\marketplace.json',
    '.codex-plugin\plugin.json',
    '.agents\plugins\marketplace.json'
)

foreach ($relative in $manifests) {
    $path = Join-Path $RepoRoot $relative
    if (Test-Path -LiteralPath $path) {
        Set-VersionField -Path $path
    }
}

Write-Host "Next: commit, then 'claude plugin tag' to create the release tag."
