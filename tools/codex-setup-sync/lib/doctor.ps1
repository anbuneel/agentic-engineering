function Invoke-DoctorCommand {
    $config = Get-ResolvedToolConfig -RequireExisting
    $paths = Get-ProviderPaths -Config $config

    Write-Host "Configuration"
    Write-Info ("config file: {0}" -f (Get-ToolConfigPath))
    Write-Info ("provider: {0}" -f $config.provider)
    Write-Info ("sync repo: {0}" -f $config.sync_repo)
    Write-Info ("machine id: {0}" -f $config.machine_id)

    if (-not (Test-GitInstalled)) {
        Throw-ToolError "git is not installed or not on PATH." 4
    }

    Write-Host ""
    Write-Host "Provider Paths"
    foreach ($key in @("codex_home", "agents_home", "codex_config", "codex_rules", "codex_memories", "codex_sessions")) {
        $value = $paths[$key]
        Write-Info ("{0}: {1}" -f $key, $value)
    }

    Write-Host ""
    Write-Host "Checks"
    if (-not (Test-Path -LiteralPath $config.sync_repo)) {
        Throw-ToolError ("sync repo path does not exist: {0}" -f $config.sync_repo) 2
    }
    Write-Info "sync repo exists"

    if (-not (Test-Path -LiteralPath (Join-Path $config.sync_repo ".git"))) {
        Throw-ToolError ("sync repo is not a git repository: {0}" -f $config.sync_repo) 3
    }
    Write-Info "sync repo is a git repository"

    if (-not (Test-Path -LiteralPath $paths.codex_home)) {
        Throw-ToolError ("codex home does not exist: {0}" -f $paths.codex_home) 4
    }
    Write-Info "codex home exists"

    if (-not (Test-Path -LiteralPath $paths.agents_home)) {
        Write-WarnMessage ("agents home does not exist yet: {0}" -f $paths.agents_home)
    } else {
        Write-Info "agents home exists"
    }

    foreach ($excluded in $paths.excluded_paths) {
        if (Test-Path -LiteralPath $excluded) {
            Write-Info ("excluded path detected: {0}" -f $excluded)
        }
    }

    Write-Host ""
    Write-Info "doctor checks passed"
}
