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
# Git writes progress and warnings to stderr. In PS 5.1 with $ErrorActionPreference=Stop,
# `2>&1` wraps each stderr line as an ErrorRecord which terminates the script. We have to
# downgrade ErrorActionPreference locally so the wrapper can convert ErrorRecord -> string.
function Invoke-Git {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @args 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { "$_" } else { $_ }
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}
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
  sync [--delete] [--force]         Push then pull (full round-trip)
  push [--delete] [--force]         Push local memories to sync repo (additive by default)
  pull [--delete] [--force]         Pull memories from sync repo to local (additive by default)
  status                            Show sync status
  doctor                            Run health checks against config, aliases, and repo state
  list                              List discovered projects and aliases
  alias <mangled-name> <canonical>  Set a manual alias
  alias --detect [project-path]     Auto-detect alias from git remote

Push/pull flags:
  --delete                          Propagate deletions (push: to repo; pull: from local). Files move to .trash/ for recovery.
  --force                           Skip the 3-file safety threshold for --delete

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

function Move-ToTrash {
    # Soft-delete: move a file into <syncRepo>/.trash/<canonical>/<timestamp>-<name>
    # so a botched sync run can be recovered without git surgery. Used by both
    # push --delete (repo-side) and pull --delete (local-side).
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$SyncRepo,
        [Parameter(Mandatory)][string]$Canonical
    )
    $ts = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $trashDir = Join-Path (Join-Path $SyncRepo ".trash") $Canonical
    if (-not (Test-Path $trashDir)) { New-Item -ItemType Directory -Path $trashDir -Force | Out-Null }
    $fileName = Split-Path $FilePath -Leaf
    $dest = Join-Path $trashDir "$ts-$fileName"
    Move-Item -Path $FilePath -Destination $dest -Force

    # Ensure .trash/ is gitignored. Lazy-create .gitignore on first trash usage.
    $gitignore = Join-Path $SyncRepo ".gitignore"
    $line = ".trash/"
    if (-not (Test-Path $gitignore)) {
        Write-Utf8NoBom $gitignore "$line`n"
    } elseif (-not ((Get-Content $gitignore -ErrorAction SilentlyContinue) -contains $line)) {
        Add-Content -Path $gitignore -Value $line -Encoding UTF8
    }
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

    # Push is additive by default; deletion is opt-in.
    $allowDelete = $Arguments -contains "--delete"
    $force = $Arguments -contains "--force"
    $script:DeleteThreshold = 3

    # Pull latest
    Write-Info "Pulling latest from remote..."
    try { Invoke-Git -C $syncRepo pull --rebase } catch { Write-Warn "Pull failed -- continuing with local state" }

    $projects = Get-DiscoveredProjects
    $count = 0

    if ($projects.Count -eq 0) {
        Write-Info "No project memories found."
        return
    }

    # Phase 1: gather pending deletions across all projects so we can threshold-check
    # BEFORE moving anything. Aborting mid-run would leave the repo half-modified.
    $pendingDeletes = @()
    foreach ($mangled in $projects) {
        $canonical = Resolve-Canonical $mangled
        $localMemory = Join-Path (Join-Path $script:ProjectsDir $mangled) "memory"
        $repoMemory = Join-Path (Join-Path (Join-Path $syncRepo "projects") $canonical) "memory"
        if (-not (Test-Path $repoMemory)) { continue }

        $mdFiles = Get-ChildItem $localMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        $localNames = @($mdFiles | ForEach-Object { $_.Name })

        $repoFiles = Get-ChildItem $repoMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        foreach ($rf in $repoFiles) {
            if ($localNames -notcontains $rf.Name) {
                $pendingDeletes += [PSCustomObject]@{
                    Canonical = $canonical
                    FilePath  = $rf.FullName
                    Name      = $rf.Name
                }
            }
        }
    }

    if ($pendingDeletes.Count -gt 0) {
        if (-not $allowDelete) {
            Write-Warn "Push is additive by default. $($pendingDeletes.Count) file(s) exist in the repo but not locally:"
            foreach ($d in $pendingDeletes) { Write-Host "    $($d.Canonical)/$($d.Name)" }
            Write-Warn "To propagate these deletions, re-run with --delete (files move to .trash/ for recovery)."
        } elseif ($pendingDeletes.Count -gt $script:DeleteThreshold -and -not $force) {
            Stop-Fatal ("Refusing to delete $($pendingDeletes.Count) files (threshold: $script:DeleteThreshold). " +
                       "This usually means a misconfigured alias or empty local dir. " +
                       "Inspect the list above, then re-run with --delete --force if you're sure.")
        }
    }

    foreach ($mangled in $projects) {
        $canonical = Resolve-Canonical $mangled
        $localMemory = Join-Path (Join-Path $script:ProjectsDir $mangled) "memory"
        $repoMemory = Join-Path (Join-Path (Join-Path $syncRepo "projects") $canonical) "memory"

        # Collect local .md files (excluding MEMORY.md)
        $mdFiles = Get-ChildItem $localMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }

        Write-Info "Syncing $mangled → $canonical"
        if (-not (Test-Path $repoMemory)) { New-Item -ItemType Directory -Path $repoMemory -Force | Out-Null }

        # Copy local files to sync repo
        foreach ($f in $mdFiles) {
            Copy-Item $f.FullName -Destination $repoMemory -Force
        }

        # Soft-delete to .trash/ — only when user explicitly opted in via --delete.
        if ($allowDelete) {
            $projectDeletes = $pendingDeletes | Where-Object { $_.Canonical -eq $canonical }
            foreach ($d in $projectDeletes) {
                Move-ToTrash -FilePath $d.FilePath -SyncRepo $syncRepo -Canonical $canonical
                Write-Info "  Trashed (removed locally): $($d.Name)"
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
        Invoke-Git -C $syncRepo push
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Push failed -- changes committed locally"
        } else {
            Write-Info "Pushed $count project(s)."
        }
    }
}

function Invoke-Pull {
    Test-ConfigExists
    $syncRepo = Get-SyncRepo

    if (-not (Test-Path (Join-Path $syncRepo ".git"))) { Stop-Fatal "Sync repo not found at $syncRepo" }

    # Pull is additive by default; deletion is opt-in (symmetric with push).
    $allowDelete = $Arguments -contains "--delete"
    $force = $Arguments -contains "--force"
    $script:DeleteThreshold = 3

    Write-Info "Pulling from remote..."
    Invoke-Git -C $syncRepo pull --rebase
    if ($LASTEXITCODE -ne 0) { Stop-Fatal "Pull failed" }

    $count = 0
    $projectsPath = Join-Path $syncRepo "projects"
    if (-not (Test-Path $projectsPath)) { Write-Info "No projects in sync repo."; return }

    # Phase 1: gather pending local deletions across all projects.
    $pendingDeletes = @()
    foreach ($canonicalDir in Get-ChildItem $projectsPath -Directory) {
        $canonical = $canonicalDir.Name
        $repoMemory = Join-Path $canonicalDir.FullName "memory"
        if (-not (Test-Path $repoMemory)) { continue }
        $mangled = Find-LocalForCanonical $canonical
        if (-not $mangled) { continue }
        $localMemory = Join-Path (Join-Path $script:ProjectsDir $mangled) "memory"
        if (-not (Test-Path $localMemory)) { continue }

        $repoFiles = Get-ChildItem $repoMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        $repoNames = @($repoFiles | ForEach-Object { $_.Name })

        $localFiles = Get-ChildItem $localMemory -Filter "*.md" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "MEMORY.md" }
        foreach ($lf in $localFiles) {
            if ($repoNames -notcontains $lf.Name) {
                $pendingDeletes += [PSCustomObject]@{
                    Canonical = $canonical
                    FilePath  = $lf.FullName
                    Name      = $lf.Name
                }
            }
        }
    }

    if ($pendingDeletes.Count -gt 0) {
        if (-not $allowDelete) {
            Write-Warn "Pull is additive by default. $($pendingDeletes.Count) local file(s) are not in the repo:"
            foreach ($d in $pendingDeletes) { Write-Host "    $($d.Canonical)/$($d.Name)" }
            Write-Warn "To accept upstream deletions, re-run with --delete (files move to .trash/ for recovery)."
        } elseif ($pendingDeletes.Count -gt $script:DeleteThreshold -and -not $force) {
            Stop-Fatal ("Refusing to delete $($pendingDeletes.Count) local files (threshold: $script:DeleteThreshold). " +
                       "Inspect the list above, then re-run with --delete --force if you're sure.")
        }
    }

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

        # Copy files from sync repo to local
        $repoFiles = Get-ChildItem $repoMemory -Filter "*.md" -File |
            Where-Object { $_.Name -ne "MEMORY.md" }
        foreach ($f in $repoFiles) {
            Copy-Item $f.FullName -Destination $localMemory -Force
        }

        # Soft-delete to .trash/ — only when user explicitly opted in via --delete.
        if ($allowDelete) {
            $projectDeletes = $pendingDeletes | Where-Object { $_.Canonical -eq $canonical }
            foreach ($d in $projectDeletes) {
                Move-ToTrash -FilePath $d.FilePath -SyncRepo $syncRepo -Canonical $canonical
                Write-Info "  Trashed (removed upstream): $($d.Name)"
            }
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

function Invoke-Doctor {
    Test-ConfigExists
    $syncRepo = Get-SyncRepo
    $machineId = Get-MachineId
    $config = Read-Config
    $issues = 0

    function Write-Check { param([string]$Status, [string]$Msg)
        $color = switch ($Status) { "ok" {"Green"} "warn" {"Yellow"} "fail" {"Red"} default {"White"} }
        $glyph = switch ($Status) { "ok" {"[ok]"} "warn" {"[!! ]"} "fail" {"[XX]"} default {"[--]"} }
        Write-Host "  $glyph $Msg" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Config" -ForegroundColor Cyan
    Write-Check ok "Config file: $script:ConfigFile"
    if ($machineId) { Write-Check ok "machine_id: $machineId" } else { Write-Check fail "machine_id missing"; $issues++ }
    if (Test-Path (Join-Path $syncRepo ".git")) {
        Write-Check ok "sync_repo: $syncRepo"
    } else {
        Write-Check fail "sync_repo missing or not a git repo: $syncRepo"; $issues++
    }

    Write-Host ""
    Write-Host "Aliases" -ForegroundColor Cyan
    $aliasCount = 0
    $valueCounts = @{}
    if ($config.aliases) {
        foreach ($prop in $config.aliases.PSObject.Properties) {
            $aliasCount++
            if ($valueCounts.ContainsKey($prop.Value)) { $valueCounts[$prop.Value] += @($prop.Name) }
            else { $valueCounts[$prop.Value] = @($prop.Name) }
            $localDir = Join-Path $script:ProjectsDir $prop.Name
            if (Test-Path $localDir) {
                Write-Check ok "$($prop.Name) -> $($prop.Value)"
            } else {
                Write-Check warn "$($prop.Name) -> $($prop.Value): local dir does not exist"; $issues++
            }
        }
    }
    if ($aliasCount -eq 0) { Write-Check warn "No aliases defined" }

    foreach ($k in $valueCounts.Keys) {
        if ($valueCounts[$k].Count -gt 1) {
            Write-Check warn "Multiple aliases -> '$k': $($valueCounts[$k] -join ', ') (reverse lookup may pick the wrong one)"
            $issues++
        }
    }

    Write-Host ""
    Write-Host "Local projects" -ForegroundColor Cyan
    if (Test-Path $script:ProjectsDir) {
        $unaliased = @()
        foreach ($dir in Get-ChildItem $script:ProjectsDir -Directory -ErrorAction SilentlyContinue) {
            $memDir = Join-Path $dir.FullName "memory"
            if (-not (Test-Path $memDir)) { continue }
            $isAliased = $config.aliases -and ($config.aliases.PSObject.Properties.Name -contains $dir.Name)
            $canonical = Resolve-Canonical $dir.Name
            if (-not $isAliased -and $canonical -eq $dir.Name) {
                $unaliased += $dir.Name
            }
        }
        if ($unaliased.Count -eq 0) {
            Write-Check ok "All local projects with memory/ are aliased"
        } else {
            foreach ($n in $unaliased) {
                Write-Check warn "$n has memory/ but no alias (will sync under raw name)"
                $issues++
            }
        }
    }

    Write-Host ""
    Write-Host "Canonical names in repo" -ForegroundColor Cyan
    $repoProjects = Join-Path $syncRepo "projects"
    if (Test-Path $repoProjects) {
        $unmapped = @()
        foreach ($dir in Get-ChildItem $repoProjects -Directory -ErrorAction SilentlyContinue) {
            $local = Find-LocalForCanonical $dir.Name
            if (-not $local) { $unmapped += $dir.Name }
        }
        if ($unmapped.Count -eq 0) {
            Write-Check ok "All canonical names resolve to a local dir"
        } else {
            foreach ($n in $unmapped) {
                Write-Check warn "Canonical '$n' has no local mapping (next pull will create '$n' locally)"
                $issues++
            }
        }
    }

    Write-Host ""
    Write-Host "Sync repo state" -ForegroundColor Cyan
    $branch = (Invoke-Git -C $syncRepo rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch -eq "main" -or $branch -eq "master") {
        Write-Check ok "On branch $branch"
    } else {
        Write-Check warn "On non-default branch '$branch' (expected main/master)"; $issues++
    }
    Invoke-Git -C $syncRepo fetch --quiet 2>$null
    $ahead = (Invoke-Git -C $syncRepo rev-list --count "@{u}..HEAD" 2>$null)
    $behind = (Invoke-Git -C $syncRepo rev-list --count "HEAD..@{u}" 2>$null)
    if ($ahead -and [int]$ahead -gt 0) { Write-Check warn "$ahead commit(s) ahead of remote (unpushed)"; $issues++ }
    if ($behind -and [int]$behind -gt 0) { Write-Check warn "$behind commit(s) behind remote (unpulled)"; $issues++ }
    if ((-not $ahead -or [int]$ahead -eq 0) -and (-not $behind -or [int]$behind -eq 0)) {
        Write-Check ok "In sync with remote"
    }

    Write-Host ""
    Write-Host "Trash" -ForegroundColor Cyan
    $trashDir = Join-Path $syncRepo ".trash"
    if (Test-Path $trashDir) {
        $trashFiles = Get-ChildItem $trashDir -Recurse -File -ErrorAction SilentlyContinue
        if ($trashFiles.Count -gt 0) {
            $oldest = ($trashFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime.ToString("yyyy-MM-dd")
            Write-Check warn "$($trashFiles.Count) recoverable file(s) in .trash/ (oldest: $oldest)"
        } else {
            Write-Check ok ".trash/ is empty"
        }
    } else {
        Write-Check ok ".trash/ does not exist (nothing has been deleted)"
    }

    Write-Host ""
    Write-Host "Last sync" -ForegroundColor Cyan
    $metaFile = Join-Path $syncRepo ".sync-meta.json"
    if (Test-Path $metaFile) {
        $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
        if ($meta.last_sync) {
            $who = if ($meta.last_sync.machine -eq $machineId) { "this machine" } else { "another machine -- $($meta.last_sync.machine)" }
            Write-Check ok "$($meta.last_sync.timestamp) by $($meta.last_sync.machine) ($who)"
        }
    }

    Write-Host ""
    if ($issues -eq 0) {
        Write-Host "All checks passed." -ForegroundColor Green
    } else {
        Write-Host "$issues issue(s) found. Review the warnings above." -ForegroundColor Yellow
    }
}

# --- Main ---

switch ($Command) {
    "setup"     { Invoke-Setup }
    "sync"      { Invoke-Sync }
    "push"      { Invoke-Push }
    "pull"      { Invoke-Pull }
    "status"    { Invoke-Status }
    "doctor"    { Invoke-Doctor }
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
