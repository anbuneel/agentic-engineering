function Update-SyncMeta {
    param(
        [hashtable]$Config,
        [string]$Action
    )

    $metaPath = Get-SyncMetaPath -Config $Config
    $meta = Read-JsonFile -Path $metaPath
    $meta.last_sync = @{
        action     = $Action
        machine_id = $Config.machine_id
        timestamp  = Get-IsoTimestamp
    }
    Write-JsonFile -Path $metaPath -Value $meta
}

function Initialize-SyncRepo {
    param(
        [hashtable]$Config,
        [string]$SetupArgument
    )

    $repoPath = $Config.sync_repo
    if (Test-Path -LiteralPath (Join-Path $repoPath ".git")) {
        Write-WarnMessage ("Sync repo already exists at {0}" -f $repoPath)
        return
    }

    if ($SetupArgument -eq "--init") {
        Write-Info ("Initializing sync repo at {0}" -f $repoPath)
        Git-InitRepository -RepoPath $repoPath
    } else {
        Write-Info ("Cloning sync repo to {0}" -f $repoPath)
        Git-CloneRepository -RepoUrl $SetupArgument -Destination $repoPath
    }
}

function Get-ResolvedConfigAndPaths {
    $config = Get-ResolvedToolConfig -RequireExisting
    $paths = Get-ProviderPaths -Config $config
    return @{
        config = $config
        paths  = $paths
    }
}

function Invoke-SetupCommand {
    param([string[]]$Arguments)

    if (-not $Arguments -or -not $Arguments[0]) {
        Throw-ToolError "Usage: codex-setup-sync setup <repo-url> OR setup --init" 1
    }

    $config = Get-ResolvedToolConfig
    Save-ToolConfig -Config $config

    Initialize-SyncRepo -Config $config -SetupArgument $Arguments[0]
    Initialize-ProviderRepoLayout -Config $config

    $paths = Get-ProviderPaths -Config $config
    if (Test-ProviderHasSharedState -Config $config) {
        Write-Info "Existing shared state detected in sync repo. Importing locally."
        Import-ProviderPortableState -Config $config -Paths $paths
        if ($config.components.sessions_import) {
            Import-ProviderSessions -Config $config -Paths $paths | Out-Null
        }
    } else {
        Write-Info "No shared state detected. Bootstrapping sync repo from local machine."
        Export-ProviderPortableState -Config $config -Paths $paths
        Export-ProviderSessions -Config $config -Paths $paths | Out-Null
        Update-SyncMeta -Config $config -Action "bootstrap"
        Git-CommitIfDirty -RepoPath $config.sync_repo -Message "Bootstrap codex setup state" | Out-Null
    }

    Export-ProviderWrappers -Config $config
    Write-Info "Setup complete."
}

function Invoke-StatusCommand {
    $resolved = Get-ResolvedConfigAndPaths
    $config = $resolved.config
    $paths = $resolved.paths

    Write-Host "codex-setup-sync"
    Write-Info ("config: {0}" -f (Get-ToolConfigPath))
    Write-Info ("sync repo: {0}" -f $config.sync_repo)
    Write-Info ("provider: {0}" -f $config.provider)
    Write-Info ("machine: {0}" -f $config.machine_id)

    $meta = Read-JsonFile -Path (Get-SyncMetaPath -Config $config)
    if ($meta.last_sync) {
        Write-Info ("last sync: {0} by {1} at {2}" -f $meta.last_sync.action, $meta.last_sync.machine_id, $meta.last_sync.timestamp)
    }

    if (Test-Path -LiteralPath (Join-Path $config.sync_repo ".git")) {
        $gitStatus = Get-GitStatusShort -RepoPath $config.sync_repo
        if ($gitStatus) {
            Write-Host ""
            Write-Host "Pending repo changes"
            Write-Host $gitStatus
        } else {
            Write-Info "sync repo working tree is clean"
        }
    }

    if ($config.components.sessions_export) {
        $pending = Get-ProviderPendingSessionExports -Config $config -Paths $paths
        if ($pending.Count -gt 0) {
            Write-WarnMessage ("{0} completed session file(s) are pending export." -f $pending.Count)
        } else {
            Write-Info "no new completed session exports detected"
        }
    }
}

function Invoke-PushCommand {
    $resolved = Get-ResolvedConfigAndPaths
    $config = $resolved.config
    $paths = $resolved.paths

    Initialize-ProviderRepoLayout -Config $config
    Export-ProviderPortableState -Config $config -Paths $paths
    $exportedSessions = Export-ProviderSessions -Config $config -Paths $paths
    Export-ProviderWrappers -Config $config
    Update-SyncMeta -Config $config -Action "push"

    $committed = Git-CommitIfDirty -RepoPath $config.sync_repo -Message ("Sync from {0}" -f $config.machine_id)
    if ($committed) {
        Write-Info "Committed sync repo changes."
    } else {
        Write-Info "No sync repo changes to commit."
    }

    if (Git-PullRebaseIfRemote -RepoPath $config.sync_repo) {
        Write-Info "Pulled remote changes with rebase."
    } else {
        Write-WarnMessage "No remote configured for sync repo. Skipping git pull/push."
    }

    if (Git-PushIfRemote -RepoPath $config.sync_repo) {
        Write-Info "Pushed sync repo changes."
    }

    if ($exportedSessions.Count -gt 0) {
        Write-Info ("Exported {0} session file(s)." -f $exportedSessions.Count)
    }
}

function Invoke-PullCommand {
    $resolved = Get-ResolvedConfigAndPaths
    $config = $resolved.config
    $paths = $resolved.paths

    Initialize-ProviderRepoLayout -Config $config
    if (Git-PullRebaseIfRemote -RepoPath $config.sync_repo) {
        Write-Info "Pulled latest sync repo changes."
    } else {
        Write-WarnMessage "No remote configured for sync repo. Using local sync repo state only."
    }

    Import-ProviderPortableState -Config $config -Paths $paths
    $importedSessions = Import-ProviderSessions -Config $config -Paths $paths
    Export-ProviderWrappers -Config $config
    Update-SyncMeta -Config $config -Action "pull"
    if ($importedSessions.Count -gt 0) {
        Write-Info ("Imported {0} session file(s)." -f $importedSessions.Count)
    }
}

function Invoke-SyncCommand {
    Invoke-PushCommand
    Invoke-PullCommand
}

function Invoke-AliasCommand {
    param([string[]]$Arguments)

    if (-not $Arguments -or -not $Arguments[0]) {
        Throw-ToolError "Usage: codex-setup-sync alias add <local-path> <id> OR alias detect [path]" 1
    }

    $config = Get-ResolvedToolConfig -RequireExisting
    Initialize-ProviderRepoLayout -Config $config

    switch ($Arguments[0]) {
        "add" {
            if ($Arguments.Count -lt 3) {
                Throw-ToolError "Usage: codex-setup-sync alias add <local-path> <canonical-id>" 1
            }

            Set-ProjectAlias -Config $config -LocalPath $Arguments[1] -CanonicalProject $Arguments[2]
            Write-Info ("Saved alias for {0} -> {1}" -f (Get-NormalizedFullPath -Path $Arguments[1]), $Arguments[2].ToLowerInvariant())
        }

        "detect" {
            $path = if ($Arguments.Count -gt 1) { $Arguments[1] } else { (Get-Location).Path }
            $remoteUrl = Get-GitRemoteUrl -Path $path
            if (-not $remoteUrl) {
                Throw-ToolError ("No git remote found for path: {0}" -f $path) 1
            }

            $canonical = Convert-GitRemoteToCanonicalProject -Url $remoteUrl
            if (-not $canonical) {
                Throw-ToolError ("Could not derive canonical project from remote: {0}" -f $remoteUrl) 1
            }

            Set-ProjectAlias -Config $config -LocalPath $path -CanonicalProject $canonical
            Write-Info ("Saved alias for {0} -> {1}" -f (Get-NormalizedFullPath -Path $path), $canonical)
        }

        default {
            Throw-ToolError ("Unknown alias subcommand '{0}'." -f $Arguments[0]) 1
        }
    }
}

function Invoke-ConfigCommand {
    param([string[]]$Arguments)

    if ($Arguments.Count -lt 1 -or $Arguments[0] -ne "print") {
        Throw-ToolError "Usage: codex-setup-sync config print" 1
    }

    Get-ResolvedToolConfig -RequireExisting | ConvertTo-Json -Depth 20
}

function Invoke-SessionCommand {
    param([string[]]$Arguments)

    if (-not $Arguments -or -not $Arguments[0]) {
        Throw-ToolError "Usage: codex-setup-sync session export|import" 1
    }

    $resolved = Get-ResolvedConfigAndPaths
    $config = $resolved.config
    $paths = $resolved.paths

    switch ($Arguments[0]) {
        "export" {
            $exported = Export-ProviderSessions -Config $config -Paths $paths
            Write-Info ("Exported {0} session file(s)." -f $exported.Count)
        }

        "import" {
            $imported = Import-ProviderSessions -Config $config -Paths $paths
            Write-Info ("Imported {0} session file(s)." -f $imported.Count)
        }

        default {
            Throw-ToolError ("Unknown session subcommand '{0}'." -f $Arguments[0]) 1
        }
    }
}
