#Requires -Version 5.1

<#
.SYNOPSIS
    Sync Claude Code memories across machines via git.

.DESCRIPTION
    claude-memory-sync - push/pull Claude Code project memories to a git-backed sync repo.
    Supports cross-machine alias mapping so different paths resolve to the same canonical project.

.EXAMPLE
    .\claude-memory-sync.ps1 setup https://github.com/user/claude-memories.git
    .\claude-memory-sync.ps1 alias --detect
    .\claude-memory-sync.ps1 push
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
# Git writes progress to stderr which PowerShell treats as errors — suppress for git calls
function Invoke-Git { git @args 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { "$_" } else { $_ } } }
$script:VERSION = "1.0.0"
$script:ConfigFile = if ($env:CLAUDE_MEMORY_SYNC_CONFIG) { $env:CLAUDE_MEMORY_SYNC_CONFIG } else { Join-Path $HOME ".claude-memory-sync.json" }
$script:ClaudeDir = Join-Path $HOME ".claude"
$script:ProjectsDir = Join-Path $script:ClaudeDir "projects"

# --- Output helpers ---

function Write-Info  { param([string]$Msg) Write-Host "  $Msg" }
function Write-Warn  { param([string]$Msg) Write-Host "warning: $Msg" -ForegroundColor Yellow }
function Stop-Fatal  { param([string]$Msg) Write-Host "error: $Msg" -ForegroundColor Red; exit 1 }

function Show-Usage {
    Write-Host @"
claude-memory-sync $script:VERSION -- Sync Claude Code memories across machines via git

Usage: claude-memory-sync.ps1 <command> [options]

Commands:
  setup <repo-url>                  Clone sync repo and create config
  setup --init                      Initialize a new local sync repo
  sync                              Push then pull (full round-trip)
  push                              Push local memories to sync repo
  pull                              Pull memories from sync repo to local
  status                            Show sync status
  list                              List discovered projects and aliases
  alias <mangled-name> <canonical>  Set a manual alias
  alias --detect [project-path]     Auto-detect alias from git remote

Options:
  --help     Show this help
  --version  Show version
"@
}

# --- Config helpers ---

function Test-ConfigExists {
    if (-not (Test-Path $script:ConfigFile)) {
        Stop-Fatal "Not set up. Run: claude-memory-sync setup <repo-url>"
    }
}

function Read-Config {
    Test-ConfigExists
    Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Save-Config {
    param([psobject]$Config)
    Write-Utf8NoBom $script:ConfigFile ($Config | ConvertTo-Json -Depth 10)
}

function Get-SyncRepo {
    $config = Read-Config
    $repo = $config.sync_repo
    if (-not $repo) { Stop-Fatal "sync_repo not set in config" }
    $repo = $repo -replace '^~', $HOME
    return $repo
}

function Get-MachineId {
    $config = Read-Config
    return $config.machine_id
}

function Set-ProjectAlias {
    param([string]$Mangled, [string]$Canonical)
    Test-ConfigExists
    $config = Read-Config
    if (-not $config.aliases) {
        $config | Add-Member -NotePropertyName aliases -NotePropertyValue @{} -Force
    }
    $config.aliases | Add-Member -NotePropertyName $Mangled -NotePropertyValue $Canonical -Force
    Save-Config $config
}

# --- Path / alias helpers ---

function Get-MangledPath {
    param([string]$Path)
    # Replace : / \ with -
    $p = $Path -replace '[:/\\]', '-'
    # Strip leading -
    $p = $p -replace '^-', ''
    return $p
}

function Get-RemoteSlug {
    param([string]$Url)
    # SSH:   git@github.com:owner/repo.git → owner-repo
    # HTTPS: https://github.com/owner/repo.git → owner-repo
    if ($Url -match '(?:.*[:/])([^/]+)/([^/]+?)(?:\.git)?$') {
        return "$($Matches[1])-$($Matches[2])"
    }
    return $Url
}

function Resolve-Canonical {
    param([string]$Mangled)
    $config = Read-Config

    # Check aliases
    if ($config.aliases -and $config.aliases.PSObject.Properties[$Mangled]) {
        return $config.aliases.$Mangled
    }

    # Fallback
    return $Mangled
}

function Find-LocalForCanonical {
    param([string]$Canonical)
    $config = Read-Config

    # Check aliases for reverse lookup
    if ($config.aliases) {
        foreach ($prop in $config.aliases.PSObject.Properties) {
            if ($prop.Value -eq $Canonical) {
                $localDir = Join-Path $script:ProjectsDir $prop.Name
                if (Test-Path $localDir) {
                    return $prop.Name
                }
            }
        }
    }

    # Direct match
    $directDir = Join-Path $script:ProjectsDir $Canonical
    if (Test-Path $directDir) {
        return $Canonical
    }

    return $null
}

function Get-DiscoveredProjects {
    if (-not (Test-Path $script:ProjectsDir)) { return @() }

    $projects = @()
    foreach ($dir in Get-ChildItem $script:ProjectsDir -Directory) {
        $memoryDir = Join-Path $dir.FullName "memory"
        if (Test-Path $memoryDir) {
            $projects += $dir.Name
        }
    }
    return $projects
}

function Update-MemoryIndex {
    param([string]$MemoryDir)
    $indexFile = Join-Path $MemoryDir "MEMORY.md"

    $files = Get-ChildItem $MemoryDir -Filter "*.md" -File |
        Where-Object { $_.Name -ne "MEMORY.md" }

    if ($files.Count -eq 0) {
        if (Test-Path $indexFile) { Remove-Item $indexFile }
        return
    }

    $lines = @(
        "# Memory Index"
        ""
        "_Auto-generated by claude-memory-sync. Do not edit manually._"
        ""
    )

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $desc = ""
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match '(?ms)^---\s*\n.*?^description:\s*(.+?)\s*$.*?^---') {
            $desc = $Matches[1]
        }
        $link = "- [$name]($($f.Name))"
        if ($desc) {
            $lines += "$link -- $desc"
        } else {
            $lines += $link
        }
    }

    Write-Utf8NoBom $indexFile ($lines -join "`n")
}

# --- Commands ---

function Invoke-Setup {
    $arg = if ($Arguments.Count -gt 0) { $Arguments[0] } else { $null }
    if (-not $arg) { Stop-Fatal "Usage: claude-memory-sync setup <repo-url>  OR  setup --init" }

    $syncDir = Join-Path $HOME ".claude-memory-sync"

    if (Test-Path (Join-Path $syncDir ".git")) {
        Write-Warn "Sync repo already exists at $syncDir"
    } elseif ($arg -eq "--init") {
        Write-Info "Initializing new sync repo at $syncDir..."
        New-Item -ItemType Directory -Path $syncDir -Force | Out-Null
        Invoke-Git -C $syncDir init
    } else {
        Write-Info "Cloning sync repo to $syncDir..."
        Invoke-Git clone $arg $syncDir
    }

    # Generate machine ID
    $machineId = "$($env:COMPUTERNAME)-windows".ToLower()

    # Create or update config
    if (Test-Path $script:ConfigFile) {
        Write-Warn "Config already exists at $script:ConfigFile -- updating"
        $config = Read-Config
        $config.sync_repo = $syncDir
        $config.machine_id = $machineId
    } else {
        $config = [PSCustomObject]@{
            sync_repo  = $syncDir
            machine_id = $machineId
            aliases    = [PSCustomObject]@{}
        }
    }
    Save-Config $config

    # Ensure repo structure
    $projectsPath = Join-Path $syncDir "projects"
    if (-not (Test-Path $projectsPath)) { New-Item -ItemType Directory -Path $projectsPath -Force | Out-Null }
    $metaFile = Join-Path $syncDir ".sync-meta.json"
    if (-not (Test-Path $metaFile)) { Write-Utf8NoBom $metaFile '{}' }

    Write-Info ""
    Write-Info "Setup complete."
    Write-Info "  Machine ID: $machineId"
    Write-Info "  Sync repo:  $syncDir"
    Write-Info "  Config:     $script:ConfigFile"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Run 'claude-memory-sync list' to see discovered projects"
    Write-Info "  2. cd into each project and run 'claude-memory-sync alias --detect'"
    Write-Info "  3. Run 'claude-memory-sync push' to sync"
}

function Invoke-Push {
    Test-ConfigExists
    $syncRepo = Get-SyncRepo
    $machineId = Get-MachineId

    if (-not (Test-Path (Join-Path $syncRepo ".git"))) { Stop-Fatal "Sync repo not found at $syncRepo" }

    # Pull latest
    Write-Info "Pulling latest from remote..."
    try { Invoke-Git -C $syncRepo pull --rebase } catch { Write-Warn "Pull failed -- continuing with local state" }

    $projects = Get-DiscoveredProjects
    $count = 0

    if ($projects.Count -eq 0) {
        Write-Info "No project memories found."
        return
    }

    foreach ($mangled in $projects) {
        $canonical = Resolve-Canonical $mangled
        $localMemory = Join-Path (Join-Path $script:ProjectsDir $mangled) "memory"
        $repoMemory = Join-Path (Join-Path (Join-Path $syncRepo "projects") $canonical) "memory"

        # Check for .md files (excluding MEMORY.md)
        $mdFiles = Get-ChildItem $localMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        if ($mdFiles.Count -eq 0) { continue }

        Write-Info "Syncing $mangled → $canonical"
        if (-not (Test-Path $repoMemory)) { New-Item -ItemType Directory -Path $repoMemory -Force | Out-Null }

        foreach ($f in $mdFiles) {
            Copy-Item $f.FullName -Destination $repoMemory -Force
        }

        # Delete files from sync repo that no longer exist locally
        $repoFiles = Get-ChildItem $repoMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        $localNames = $mdFiles | ForEach-Object { $_.Name }
        foreach ($rf in $repoFiles) {
            if ($localNames -notcontains $rf.Name) {
                Remove-Item $rf.FullName -Force
                Write-Info "  Deleted (removed locally): $($rf.Name)"
            }
        }

        Update-MemoryIndex $repoMemory
        $count++
    }

    # Update sync metadata
    $metaFile = Join-Path $syncRepo ".sync-meta.json"
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $meta = if (Test-Path $metaFile) { Get-Content $metaFile -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
    $meta | Add-Member -NotePropertyName last_sync -NotePropertyValue ([PSCustomObject]@{ machine = $machineId; timestamp = $ts }) -Force
    Write-Utf8NoBom $metaFile ($meta | ConvertTo-Json -Depth 10)

    # Commit and push
    Invoke-Git -C $syncRepo add -A
    Invoke-Git -C $syncRepo diff --cached --quiet 2>$null
    $hasChanges = $LASTEXITCODE -ne 0
    if (-not $hasChanges) {
        Write-Info "No changes to push."
    } else {
        Invoke-Git -C $syncRepo commit -m "sync from $machineId -- $ts"
        Write-Info "Pushing..."
        try {
            Invoke-Git -C $syncRepo push
            Write-Info "Pushed $count project(s)."
        } catch {
            Write-Warn "Push failed -- changes committed locally"
        }
    }
}

function Invoke-Pull {
    Test-ConfigExists
    $syncRepo = Get-SyncRepo

    if (-not (Test-Path (Join-Path $syncRepo ".git"))) { Stop-Fatal "Sync repo not found at $syncRepo" }

    Write-Info "Pulling from remote..."
    Invoke-Git -C $syncRepo pull --rebase
    if ($LASTEXITCODE -ne 0) { Stop-Fatal "Pull failed" }

    $count = 0
    $projectsPath = Join-Path $syncRepo "projects"
    if (-not (Test-Path $projectsPath)) { Write-Info "No projects in sync repo."; return }

    foreach ($canonicalDir in Get-ChildItem $projectsPath -Directory) {
        $canonical = $canonicalDir.Name
        $repoMemory = Join-Path $canonicalDir.FullName "memory"
        if (-not (Test-Path $repoMemory)) { continue }

        $mangled = Find-LocalForCanonical $canonical
        if (-not $mangled) {
            $mangled = $canonical
            Write-Info "No local mapping for $canonical -- creating as $canonical (run 'alias' to remap)"
        }

        $localMemory = Join-Path (Join-Path $script:ProjectsDir $mangled) "memory"
        if (-not (Test-Path $localMemory)) { New-Item -ItemType Directory -Path $localMemory -Force | Out-Null }

        Write-Info "Pulling $canonical → $mangled"

        $mdFiles = Get-ChildItem $repoMemory -Filter "*.md" -File |
            Where-Object { $_.Name -ne "MEMORY.md" }
        foreach ($f in $mdFiles) {
            Copy-Item $f.FullName -Destination $localMemory -Force
        }

        Update-MemoryIndex $localMemory
        $count++
    }

    Write-Info "Pulled $count project(s)."
}

function Invoke-Status {
    Test-ConfigExists
    $syncRepo = Get-SyncRepo
    $machineId = Get-MachineId

    Write-Host "Machine:   $machineId"
    Write-Host "Sync repo: $syncRepo"
    Write-Host "Config:    $script:ConfigFile"
    Write-Host ""

    if (Test-Path (Join-Path $syncRepo ".git")) {
        $metaFile = Join-Path $syncRepo ".sync-meta.json"
        if (Test-Path $metaFile) {
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
            if ($meta.last_sync) {
                Write-Host "Last sync: by $($meta.last_sync.machine) at $($meta.last_sync.timestamp)"
            } else {
                Write-Host "Last sync: never"
            }
        } else {
            Write-Host "Last sync: never"
        }

        Write-Host ""
        Write-Host "Remote status:"
        Invoke-Git -C $syncRepo fetch --quiet 2>$null
        Invoke-Git -C $syncRepo status --short --branch
    } else {
        Write-Host "Sync repo not found at $syncRepo"
    }
}

function Invoke-List {
    Test-ConfigExists
    $projects = Get-DiscoveredProjects

    if ($projects.Count -eq 0) {
        Write-Host "No project memories found under $script:ProjectsDir"
        return
    }

    Write-Host "Discovered project memories:"
    Write-Host ""
    Write-Host ("  {0,-45} {1}" -f "LOCAL NAME", "CANONICAL ALIAS")
    Write-Host ("  {0,-45} {1}" -f "----------", "---------------")

    foreach ($mangled in $projects) {
        $canonical = Resolve-Canonical $mangled
        $marker = ""
        if ($canonical -eq $mangled) { $marker = " (no alias)" }
        Write-Host ("  {0,-45} {1}{2}" -f $mangled, $canonical, $marker)
    }
}

function Invoke-Alias {
    Test-ConfigExists

    if ($Arguments.Count -gt 0 -and $Arguments[0] -eq "--detect") {
        $projectPath = if ($Arguments.Count -gt 1) { $Arguments[1] } else { (Get-Location).Path }
        $projectPath = (Resolve-Path $projectPath).Path

        $mangled = Get-MangledPath $projectPath

        # Try git remote
        $canonical = $null
        $gitDir = Join-Path $projectPath ".git"
        if (Test-Path $gitDir) {
            try {
                $remoteUrl = Invoke-Git -C $projectPath remote get-url origin 2>$null
                if ($remoteUrl) { $canonical = Get-RemoteSlug $remoteUrl }
            } catch {}
        }

        if (-not $canonical) {
            $canonical = Split-Path $projectPath -Leaf
            Write-Warn "No git remote found -- using directory name: $canonical"
        }

        Set-ProjectAlias $mangled $canonical
        Write-Info "Alias set: $mangled → $canonical"
        return
    }

    if ($Arguments.Count -lt 2) {
        Stop-Fatal "Usage: claude-memory-sync alias <mangled-name> <canonical>  OR  alias --detect [path]"
    }

    Set-ProjectAlias $Arguments[0] $Arguments[1]
    Write-Info "Alias set: $($Arguments[0]) → $($Arguments[1])"
}

function Invoke-Sync {
    Invoke-Push
    Invoke-Pull
}

# --- Main ---

switch ($Command) {
    "setup"     { Invoke-Setup }
    "sync"      { Invoke-Sync }
    "push"      { Invoke-Push }
    "pull"      { Invoke-Pull }
    "status"    { Invoke-Status }
    "list"      { Invoke-List }
    "alias"     { Invoke-Alias }
    "--version" { Write-Host "claude-memory-sync $script:VERSION" }
    "-v"        { Write-Host "claude-memory-sync $script:VERSION" }
    "--help"    { Show-Usage }
    "-h"        { Show-Usage }
    default     {
        if (-not $Command) { Show-Usage }
        else { Stop-Fatal "Unknown command: $Command -- run --help for usage" }
    }
}
