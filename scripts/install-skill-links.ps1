param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string[]]$Targets = @('Codex'),
    [ValidateSet('Auto', 'SymbolicLink', 'Copy')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'

$validTargets = @('Claude', 'Codex', 'Agents')
$Targets = @($Targets | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($target in $Targets) {
    if ($validTargets -notcontains $target) {
        throw "Invalid target '$target'. Valid targets: $($validTargets -join ', ')"
    }
}

$skills = @(
    'multi-agent-code-review',
    'multi-agent-plan-review',
    'multi-agent-ideate',
    'merge',
    'security-scan',
    'security-audit',
    'security-posture'
)

$agents = @(
    'codebase-snapshot',
    'code-cleanup-analyst'
)

function Backup-Existing {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path.bak-$stamp"
    Move-Item -LiteralPath $Path -Destination $backup
    Write-Host "Backed up existing file: $backup"
}

function Test-LinkTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.LinkType -ne 'SymbolicLink') {
        return $false
    }

    return ((Resolve-Path -LiteralPath $item.Target).Path -eq (Resolve-Path -LiteralPath $Target).Path)
}

function Install-File {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source file not found: $Source"
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-LinkTarget -Path $Destination -Target $Source) {
        Write-Host "Already linked: $Destination -> $Source"
        return
    }

    Backup-Existing -Path $Destination

    if ($Mode -ne 'Copy') {
        try {
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Source | Out-Null
            Write-Host "Symlinked: $Destination -> $Source"
            return
        }
        catch {
            if ($Mode -eq 'SymbolicLink') {
                throw
            }
            Write-Warning "Symlink failed for $Destination ($($_.Exception.Message)). Falling back to copy. Enable Windows Developer Mode or run elevated to allow symlinks."
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "Copied: $Destination"
}

if ($Targets -contains 'Claude') {
    $claudeCommands = Join-Path $HOME '.claude\commands'
    foreach ($skill in $skills) {
        Install-File `
            -Source (Join-Path $RepoRoot "skills\$skill.md") `
            -Destination (Join-Path $claudeCommands "$skill.md")
    }

    $claudeAgents = Join-Path $HOME '.claude\agents'
    foreach ($agent in $agents) {
        Install-File `
            -Source (Join-Path $RepoRoot "agents\$agent.md") `
            -Destination (Join-Path $claudeAgents "$agent.md")
    }
}

if ($Targets -contains 'Codex') {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
    $codexSkills = Join-Path $codexHome 'skills'
    foreach ($skill in $skills) {
        Install-File `
            -Source (Join-Path $RepoRoot "skills\$skill.md") `
            -Destination (Join-Path $codexSkills "$skill\SKILL.md")
    }
}

if ($Targets -contains 'Agents') {
    $agentSkills = Join-Path $HOME '.agents\skills'
    foreach ($skill in $skills) {
        Install-File `
            -Source (Join-Path $RepoRoot "skills\$skill.md") `
            -Destination (Join-Path $agentSkills "$skill\SKILL.md")
    }
}

Write-Host 'Done. Restart Claude Code or Codex to pick up installed or relinked skills.'
