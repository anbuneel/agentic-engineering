function Get-DefaultMachineId {
    $computer = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-machine" }
    return ("{0}-windows" -f $computer).ToLowerInvariant()
}

function Get-ToolConfigPath {
    if ($env:CODEX_SETUP_SYNC_CONFIG) {
        return Resolve-HomePath $env:CODEX_SETUP_SYNC_CONFIG
    }

    return Join-Path $HOME ".codex-setup-sync.json"
}

function Get-DefaultToolConfig {
    return @{
        provider   = "codex"
        sync_repo  = "~/.codex-setup-sync"
        machine_id = (Get-DefaultMachineId)
        components = @{
            codex_config    = $true
            rules           = $true
            skills          = $true
            memories        = $true
            sessions_export = $true
            sessions_import = $false
            shell_profile   = $false
            git_config      = $false
            launch_wrappers = $false
        }
        paths      = @{
            codex_home         = "~/.codex"
            agents_home        = "~/.agents"
            powershell_profile = "~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
            git_config         = "~/.gitconfig"
        }
        identities = @{
            strategy = "git_remote_slug"
            aliases  = @{}
        }
        launch     = @{
            codex_cli = "codex"
            codex_app = $null
        }
    }
}

function Expand-ToolConfigPaths {
    param([hashtable]$Config)

    $expanded = Merge-Hashtable -Base @{} -Overlay $Config
    $expanded["sync_repo"] = Resolve-HomePath -Path $expanded["sync_repo"]

    foreach ($pathKey in @("codex_home", "agents_home", "powershell_profile", "git_config")) {
        if ($expanded["paths"].ContainsKey($pathKey) -and $expanded["paths"][$pathKey]) {
            $expanded["paths"][$pathKey] = Resolve-HomePath -Path $expanded["paths"][$pathKey]
        }
    }

    if (-not $expanded["machine_id"]) {
        $expanded["machine_id"] = Get-DefaultMachineId
    }

    return $expanded
}

function Get-ResolvedToolConfig {
    param([switch]$RequireExisting)

    $configPath = Get-ToolConfigPath
    if ($RequireExisting -and -not (Test-Path -LiteralPath $configPath)) {
        Throw-ToolError "Not set up. Run: codex-setup-sync setup <repo-url>" 2
    }

    $config = Get-DefaultToolConfig
    if (Test-Path -LiteralPath $configPath) {
        $userConfig = Read-JsonFile -Path $configPath
        $config = Merge-Hashtable -Base $config -Overlay $userConfig
    }

    return Expand-ToolConfigPaths -Config $config
}

function Save-ToolConfig {
    param([hashtable]$Config)

    $configPath = Get-ToolConfigPath
    $toWrite = Merge-Hashtable -Base @{} -Overlay $Config
    if ($toWrite["sync_repo"]) {
        $toWrite["sync_repo"] = Resolve-HomePath -Path $toWrite["sync_repo"]
    }
    Write-JsonFile -Path $configPath -Value $toWrite
}

function Get-ProviderRootPath {
    param([hashtable]$Config)
    return Join-Path $Config.sync_repo ("providers\{0}" -f $Config.provider)
}

function Get-ProviderSharedRootPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderRootPath -Config $Config) "shared"
}

function Get-ProviderMachineRootPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderRootPath -Config $Config) ("machines\{0}" -f $Config.machine_id)
}

function Get-ProviderSessionsRootPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderRootPath -Config $Config) "sessions"
}

function Get-SyncMetaPath {
    param([hashtable]$Config)
    return Join-Path $Config.sync_repo ".sync-meta.json"
}
