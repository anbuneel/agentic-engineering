function Get-ProviderPaths {
    param([hashtable]$Config)

    switch ($Config.provider) {
        "codex" { return Get-CodexProviderPaths -Config $Config }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Initialize-ProviderRepoLayout {
    param([hashtable]$Config)

    switch ($Config.provider) {
        "codex" { Initialize-CodexRepoLayout -Config $Config }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Test-ProviderHasSharedState {
    param([hashtable]$Config)

    switch ($Config.provider) {
        "codex" { return Test-CodexSharedStatePresent -Config $Config }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Export-ProviderPortableState {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    switch ($Config.provider) {
        "codex" { Export-CodexPortableState -Config $Config -Paths $Paths }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Import-ProviderPortableState {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    switch ($Config.provider) {
        "codex" { Import-CodexPortableState -Config $Config -Paths $Paths }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Export-ProviderSessions {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    switch ($Config.provider) {
        "codex" { return Export-CodexSessions -Config $Config -Paths $Paths }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Get-ProviderPendingSessionExports {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    switch ($Config.provider) {
        "codex" { return Get-CodexPendingSessionExports -Config $Config -Paths $Paths }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Import-ProviderSessions {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    switch ($Config.provider) {
        "codex" { return Import-CodexSessions -Config $Config -Paths $Paths }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Export-ProviderWrappers {
    param([hashtable]$Config)

    switch ($Config.provider) {
        "codex" { Export-CodexLaunchWrappers -Config $Config }
        default { Throw-ToolError ("Unsupported provider '{0}'." -f $Config.provider) 4 }
    }
}

function Get-CodexProviderPaths {
    param([hashtable]$Config)

    $codexHome = Get-NormalizedFullPath -Path $Config.paths.codex_home
    $agentsHome = Get-NormalizedFullPath -Path $Config.paths.agents_home
    $roamingCodex = if ($env:APPDATA) { Join-Path $env:APPDATA "Codex" } else { $null }
    $localCodex = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Codex" } else { $null }

    return @{
        codex_home           = $codexHome
        agents_home          = $agentsHome
        codex_config         = Join-Path $codexHome "config.toml"
        codex_rules          = Join-Path $codexHome "rules"
        codex_memories       = Join-Path $codexHome "memories"
        codex_sessions       = Join-Path $codexHome "sessions"
        codex_skill_root     = Join-Path $codexHome "skills"
        codex_frontend_skill = Join-Path (Join-Path $codexHome "skills") "frontend-skill"
        agents_skills        = Join-Path $agentsHome "skills"
        agents_skill_lock    = Join-Path $agentsHome ".skill-lock.json"
        agents_plugins       = Join-Path $agentsHome "plugins"
        shell_profile        = Get-NormalizedFullPath -Path $Config.paths.powershell_profile
        git_config           = Get-NormalizedFullPath -Path $Config.paths.git_config
        excluded_paths       = @(
            Join-Path $codexHome "auth.json"
            Join-Path $codexHome "cap_sid"
            Join-Path $codexHome "cache"
            Join-Path $codexHome ".sandbox"
            Join-Path $codexHome ".sandbox-bin"
            Join-Path $codexHome ".sandbox-secrets"
            $roamingCodex
            $localCodex
        ) | Where-Object { $_ }
    }
}

function Get-CodexSharedRulesPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderSharedRootPath -Config $Config) "rules"
}

function Get-CodexSharedMemoriesPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderSharedRootPath -Config $Config) "memories"
}

function Get-CodexSharedSkillsPath {
    param([hashtable]$Config)
    return Join-Path (Join-Path (Get-ProviderSharedRootPath -Config $Config) "agents") "skills"
}

function Get-CodexSharedSkillLockPath {
    param([hashtable]$Config)
    return Join-Path (Join-Path (Get-ProviderSharedRootPath -Config $Config) "agents") ".skill-lock.json"
}

function Get-CodexSharedPluginMarketplacePath {
    param([hashtable]$Config)
    return Join-Path (Join-Path (Join-Path (Get-ProviderSharedRootPath -Config $Config) "agents") "plugins") "marketplace.json"
}

function Initialize-CodexRepoLayout {
    param([hashtable]$Config)

    Ensure-Directory $Config.sync_repo
    Ensure-Directory (Get-ProviderRootPath -Config $Config)
    Ensure-Directory (Get-ProviderSharedRootPath -Config $Config)
    Ensure-Directory (Get-ProviderMachineRootPath -Config $Config)
    Ensure-Directory (Get-ProviderSessionsRootPath -Config $Config)
    Ensure-Directory (Get-CodexSharedRulesPath -Config $Config)
    Ensure-Directory (Get-CodexSharedMemoriesPath -Config $Config)
    Ensure-Directory (Get-CodexSharedSkillsPath -Config $Config)
    Ensure-Directory (Split-Path -Parent (Get-CodexSharedSkillLockPath -Config $Config))
    Ensure-Directory (Split-Path -Parent (Get-CodexSharedPluginMarketplacePath -Config $Config))
    Ensure-Directory (Split-Path -Parent (Get-CodexSharedShellProfilePath -Config $Config))
    Ensure-Directory (Split-Path -Parent (Get-CodexSharedGitConfigPath -Config $Config))

    if (-not (Test-Path -LiteralPath (Get-SyncMetaPath -Config $Config))) {
        Write-JsonFile -Path (Get-SyncMetaPath -Config $Config) -Value @{}
    }

    if (-not (Test-Path -LiteralPath (Get-MachineAliasesPath -Config $Config))) {
        Write-JsonFile -Path (Get-MachineAliasesPath -Config $Config) -Value @{}
    }

    if (-not (Test-Path -LiteralPath (Get-MachineDescriptorPath -Config $Config))) {
        Write-JsonFile -Path (Get-MachineDescriptorPath -Config $Config) -Value @{
            machine_id = $Config.machine_id
            provider   = $Config.provider
            created_at = Get-IsoTimestamp
        }
    }

    foreach ($path in @((Get-CodexSharedConfigPath -Config $Config), (Get-MachineConfigTomlPath -Config $Config))) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Utf8NoBom -Path $path -Text ""
        }
    }
}

function Test-CodexSharedStatePresent {
    param([hashtable]$Config)

    foreach ($path in @(
        (Get-CodexSharedConfigPath -Config $Config),
        (Get-CodexSharedRulesPath -Config $Config),
        (Get-CodexSharedMemoriesPath -Config $Config),
        (Get-CodexSharedSkillsPath -Config $Config)
    )) {
        if (Test-DirectoryHasFiles -Path $path) {
            return $true
        }
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).PSIsContainer -eq $false -and (Get-Item -LiteralPath $path).Length -gt 0) {
            return $true
        }
    }

    return $false
}

function Move-CodexFrontendSkillIfNeeded {
    param([hashtable]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.codex_frontend_skill)) {
        return
    }

    $destination = Join-Path $Paths.agents_skills "frontend-skill"
    if (Test-Path -LiteralPath $destination) {
        return
    }

    Ensure-Directory $Paths.agents_skills
    Move-Item -LiteralPath $Paths.codex_frontend_skill -Destination $destination
    Write-Notice "Moved frontend-skill into ~/.agents/skills for syncability."
}

function Export-CodexPortableState {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    Initialize-CodexRepoLayout -Config $Config
    if ($Config.components.skills) {
        Move-CodexFrontendSkillIfNeeded -Paths $Paths
    }

    if ($Config.components.codex_config) {
        Export-CodexConfigFragmentsFromLive -Config $Config -Paths $Paths
    }

    if ($Config.components.rules) {
        Sync-DirectoryMirror -Source $Paths.codex_rules -Destination (Get-CodexSharedRulesPath -Config $Config)
    }

    if ($Config.components.memories) {
        Sync-DirectoryMirror -Source $Paths.codex_memories -Destination (Get-CodexSharedMemoriesPath -Config $Config)
    }

    if ($Config.components.skills) {
        Sync-DirectoryMirror -Source $Paths.agents_skills -Destination (Get-CodexSharedSkillsPath -Config $Config)
        Sync-OptionalFile -Source $Paths.agents_skill_lock -Destination (Get-CodexSharedSkillLockPath -Config $Config)
    }

    $pluginMarketplaceSource = Join-Path $Paths.agents_plugins "marketplace.json"
    Sync-OptionalFile -Source $pluginMarketplaceSource -Destination (Get-CodexSharedPluginMarketplacePath -Config $Config)

    Export-ShellProfileIfEnabled -Config $Config -Paths $Paths
    Export-GitConfigIfEnabled -Config $Config -Paths $Paths
}

function Import-CodexPortableState {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    Initialize-CodexRepoLayout -Config $Config
    Ensure-Directory $Paths.codex_home
    Ensure-Directory $Paths.agents_home

    if ($Config.components.rules) {
        Sync-DirectoryMirror -Source (Get-CodexSharedRulesPath -Config $Config) -Destination $Paths.codex_rules
    }

    if ($Config.components.memories) {
        Sync-DirectoryMirror -Source (Get-CodexSharedMemoriesPath -Config $Config) -Destination $Paths.codex_memories
    }

    if ($Config.components.skills) {
        Sync-DirectoryMirror -Source (Get-CodexSharedSkillsPath -Config $Config) -Destination $Paths.agents_skills
        Sync-OptionalFile -Source (Get-CodexSharedSkillLockPath -Config $Config) -Destination $Paths.agents_skill_lock
    }

    $pluginMarketplaceSource = Get-CodexSharedPluginMarketplacePath -Config $Config
    $pluginMarketplaceDestination = Join-Path $Paths.agents_plugins "marketplace.json"
    Sync-OptionalFile -Source $pluginMarketplaceSource -Destination $pluginMarketplaceDestination

    if ($Config.components.codex_config) {
        Render-LiveCodexConfig -Config $Config -Paths $Paths
    }

    if ($Config.components.shell_profile) {
        Install-ManagedShellProfile -Config $Config -Paths $Paths
    }

    if ($Config.components.git_config) {
        Install-ManagedGitIncludes -Config $Config -Paths $Paths
    }
}

function Get-CodexSessionExportTarget {
    param(
        [hashtable]$Config,
        [hashtable]$Identity,
        [hashtable]$DateParts,
        [string]$FileName
    )

    $targetRoot = Get-ProviderSessionsRootPath -Config $Config
    foreach ($segment in ($Identity.canonical_project -split '/')) {
        if ($segment) {
            $targetRoot = Join-Path $targetRoot $segment
        }
    }

    $targetRoot = Join-Path (Join-Path (Join-Path $targetRoot $DateParts.year) $DateParts.month) $DateParts.day
    $sessionPath = Join-Path $targetRoot $FileName
    $manifestFile = ("{0}.manifest.json" -f [System.IO.Path]::GetFileNameWithoutExtension($FileName))

    return @{
        session_path  = $sessionPath
        manifest_path = Join-Path $targetRoot $manifestFile
    }
}

function Get-DatePartsFromExportPath {
    param(
        [string]$SessionsRoot,
        [string]$Path,
        [hashtable]$Manifest
    )

    $relative = Get-RelativePathSafe -BasePath $SessionsRoot -FullPath $Path
    if ($relative -match '(?:^|[\\/])(?<year>\d{4})[\\/](?<month>\d{2})[\\/](?<day>\d{2})[\\/][^\\/]+$') {
        return @{
            year  = $Matches["year"]
            month = $Matches["month"]
            day   = $Matches["day"]
        }
    }

    if ($Manifest.exported_at) {
        try {
            $parsed = [DateTime]::Parse($Manifest.exported_at).ToUniversalTime()
            return @{
                year  = $parsed.ToString("yyyy")
                month = $parsed.ToString("MM")
                day   = $parsed.ToString("dd")
            }
        } catch {
        }
    }

    $item = Get-Item -LiteralPath $Path
    return @{
        year  = $item.LastWriteTimeUtc.ToString("yyyy")
        month = $item.LastWriteTimeUtc.ToString("MM")
        day   = $item.LastWriteTimeUtc.ToString("dd")
    }
}

function Find-ExistingSessionById {
    param(
        [string]$SessionsRoot,
        [string]$SessionId
    )

    if (-not $SessionId -or -not (Test-Path -LiteralPath $SessionsRoot)) {
        return $null
    }

    $manifestFiles = @(Get-ChildItem -LiteralPath $SessionsRoot -Filter *.manifest.json -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($manifestFile in $manifestFiles) {
        $manifest = Read-JsonFile -Path $manifestFile.FullName
        if ($manifest.session_id -eq $SessionId) {
            $sessionName = $manifestFile.Name -replace '\.manifest\.json$', '.jsonl'
            return @{
                SessionPath  = Join-Path $manifestFile.DirectoryName $sessionName
                ManifestPath = $manifestFile.FullName
                Metadata     = $manifest
            }
        }
    }

    foreach ($sessionFile in (Get-ChildItem -LiteralPath $SessionsRoot -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue)) {
        $metadata = Get-SessionMetadata -Path $sessionFile.FullName
        if ($metadata -and $metadata.session_id -eq $SessionId) {
            return @{
                SessionPath  = $sessionFile.FullName
                ManifestPath = $null
                Metadata     = $metadata
            }
        }
    }

    return $null
}

function Get-CodexPendingSessionExports {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    if (-not $Config.components.sessions_export) {
        return @()
    }

    $pending = @()
    if (-not (Test-Path -LiteralPath $Paths.codex_sessions)) {
        return $pending
    }

    foreach ($sessionFile in (Get-ChildItem -LiteralPath $Paths.codex_sessions -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue)) {
        $eligible = Test-SessionEligible -Path $sessionFile.FullName
        if (-not $eligible) {
            continue
        }

        $existing = Find-ExistingSessionById -SessionsRoot (Get-ProviderSessionsRootPath -Config $Config) -SessionId $eligible.metadata.session_id
        if (-not $existing) {
            $pending += $sessionFile.FullName
            continue
        }

        if ((Get-FileHashString -Path $existing.SessionPath) -ne $eligible.sha256) {
            $pending += $sessionFile.FullName
        }
    }

    return $pending
}

function Export-CodexSessions {
    param(
        [hashtable]$Config,
        [hashtable]$Paths,
        [switch]$DryRun
    )

    if (-not $Config.components.sessions_export) {
        return @()
    }

    Initialize-CodexRepoLayout -Config $Config
    $exported = @()

    if (-not (Test-Path -LiteralPath $Paths.codex_sessions)) {
        return $exported
    }

    foreach ($sessionFile in (Get-ChildItem -LiteralPath $Paths.codex_sessions -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $eligible = Test-SessionEligible -Path $sessionFile.FullName
        if (-not $eligible) {
            continue
        }

        $identityPath = if ($eligible.metadata.cwd) { $eligible.metadata.cwd } else { Split-Path -Parent $eligible.path }
        $identity = Resolve-ProjectIdentity -Path $identityPath -Config $Config
        $existing = Find-ExistingSessionById -SessionsRoot (Get-ProviderSessionsRootPath -Config $Config) -SessionId $eligible.metadata.session_id

        if ($existing) {
            $targetSessionPath = $existing.SessionPath
            $targetManifestPath = $existing.ManifestPath
        } else {
            $dateParts = Get-DatePartsFromSessionPath -SessionsRoot $Paths.codex_sessions -Path $eligible.path
            $target = Get-CodexSessionExportTarget -Config $Config -Identity $identity -DateParts $dateParts -FileName $sessionFile.Name
            $targetSessionPath = $target.session_path
            $targetManifestPath = $target.manifest_path
        }

        $targetHash = Get-FileHashString -Path $targetSessionPath
        $needsWrite = (-not (Test-Path -LiteralPath $targetSessionPath)) -or ($targetHash -ne $eligible.sha256)
        if ($needsWrite) {
            $exported += $targetSessionPath
            if (-not $DryRun) {
                Copy-FileIfChanged -Source $sessionFile.FullName -Destination $targetSessionPath
            }
        }

        if (-not $DryRun) {
            $manifest = New-SessionManifest -Metadata $eligible.metadata -Identity $identity -MachineId $Config.machine_id -SourcePath $identityPath -Sha256 $eligible.sha256
            Write-JsonFile -Path $targetManifestPath -Value $manifest
        }
    }

    return $exported
}

function Import-CodexSessions {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    if (-not $Config.components.sessions_import) {
        return @()
    }

    $sessionsRoot = Get-ProviderSessionsRootPath -Config $Config
    if (-not (Test-Path -LiteralPath $sessionsRoot)) {
        return @()
    }

    Ensure-Directory $Paths.codex_sessions
    $imported = @()

    foreach ($sessionFile in (Get-ChildItem -LiteralPath $sessionsRoot -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $manifestPath = Join-Path $sessionFile.DirectoryName ("{0}.manifest.json" -f [System.IO.Path]::GetFileNameWithoutExtension($sessionFile.Name))
        $manifest = Read-JsonFile -Path $manifestPath
        $sourceHash = Get-FileHashString -Path $sessionFile.FullName
        $sessionId = if ($manifest.session_id) { "$($manifest.session_id)" } else { (Get-SessionMetadata -Path $sessionFile.FullName).session_id }
        if (-not $sessionId) {
            continue
        }

        if (Find-ExistingSessionById -SessionsRoot $Paths.codex_sessions -SessionId $sessionId) {
            continue
        }

        $dateParts = Get-DatePartsFromExportPath -SessionsRoot $sessionsRoot -Path $sessionFile.FullName -Manifest $manifest
        $targetDirectory = Join-Path (Join-Path (Join-Path $Paths.codex_sessions $dateParts.year) $dateParts.month) $dateParts.day
        $targetPath = Join-Path $targetDirectory $sessionFile.Name
        Ensure-Directory $targetDirectory

        if (Test-Path -LiteralPath $targetPath) {
            if ((Get-FileHashString -Path $targetPath) -eq $sourceHash) {
                continue
            }

            Write-WarnMessage ("Skipping import because local target already exists with different content: {0}" -f $targetPath)
            continue
        }

        Copy-FileIfChanged -Source $sessionFile.FullName -Destination $targetPath
        $imported += $targetPath
    }

    return $imported
}

function Export-CodexLaunchWrappers {
    param([hashtable]$Config)

    if (-not $Config.components.launch_wrappers) {
        return
    }

    $cliWrapperPath = Join-Path $Config.sync_repo "Open-CodexCLI.ps1"
    $appWrapperPath = Join-Path $Config.sync_repo "Open-CodexApp.ps1"

    $cliWrapper = @"
# Generated by codex-setup-sync. Re-run setup to refresh this launcher.
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$CodexArgs
)

`$syncCommand = Get-Command 'codex-setup-sync.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not `$syncCommand) {
    `$syncCommand = Get-Command 'codex-setup-sync' -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not `$syncCommand) {
    Write-Host 'Install codex-setup-sync and add it to PATH before using this wrapper.' -ForegroundColor Yellow
    exit 1
}

`$syncInvoker = if (`$syncCommand.CommandType -in @('ExternalScript', 'Application')) { `$syncCommand.Source } else { `$syncCommand.Name }
& `$syncInvoker sync
if (`$LASTEXITCODE -ne 0) {
    exit `$LASTEXITCODE
}

`$configPath = if (`$env:CODEX_SETUP_SYNC_CONFIG) { `$env:CODEX_SETUP_SYNC_CONFIG } else { Join-Path `$HOME '.codex-setup-sync.json' }
`$codexCommand = 'codex'
if (Test-Path -LiteralPath `$configPath) {
    try {
        `$config = Get-Content -LiteralPath `$configPath -Raw | ConvertFrom-Json
        if (`$config.launch -and `$config.launch.codex_cli) {
            `$codexCommand = "`$(`$config.launch.codex_cli)"
        }
    } catch {
    }
}

& `$codexCommand @CodexArgs
exit `$LASTEXITCODE
"@

    $appWrapper = @"
# Generated by codex-setup-sync. Re-run setup to refresh this launcher.
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$AppArgs
)

`$syncCommand = Get-Command 'codex-setup-sync.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not `$syncCommand) {
    `$syncCommand = Get-Command 'codex-setup-sync' -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not `$syncCommand) {
    Write-Host 'Install codex-setup-sync and add it to PATH before using this wrapper.' -ForegroundColor Yellow
    exit 1
}

`$syncInvoker = if (`$syncCommand.CommandType -in @('ExternalScript', 'Application')) { `$syncCommand.Source } else { `$syncCommand.Name }
& `$syncInvoker sync
if (`$LASTEXITCODE -ne 0) {
    exit `$LASTEXITCODE
}

`$configPath = if (`$env:CODEX_SETUP_SYNC_CONFIG) { `$env:CODEX_SETUP_SYNC_CONFIG } else { Join-Path `$HOME '.codex-setup-sync.json' }
`$appCommand = $null
if (Test-Path -LiteralPath `$configPath) {
    try {
        `$config = Get-Content -LiteralPath `$configPath -Raw | ConvertFrom-Json
        if (`$config.launch -and `$config.launch.codex_app) {
            `$appCommand = "`$(`$config.launch.codex_app)"
        }
    } catch {
    }
}

if (-not `$appCommand -and `$env:CODEX_SETUP_SYNC_APP) {
    `$appCommand = `$env:CODEX_SETUP_SYNC_APP
}

if (-not `$appCommand) {
    Write-Host 'Set launch.codex_app in your local codex-setup-sync config before using this wrapper.' -ForegroundColor Yellow
    exit 1
}

if (`$AppArgs.Count -gt 0) {
    Start-Process -FilePath `$appCommand -ArgumentList `$AppArgs | Out-Null
} else {
    Start-Process -FilePath `$appCommand | Out-Null
}
"@

    Write-Utf8NoBom -Path $cliWrapperPath -Text $cliWrapper
    Write-Utf8NoBom -Path $appWrapperPath -Text $appWrapper
}