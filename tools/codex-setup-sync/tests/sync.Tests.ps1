$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\config.ps1")
. (Join-Path $toolRoot "lib\\git.ps1")
. (Join-Path $toolRoot "lib\\identity.ps1")
. (Join-Path $toolRoot "lib\\sessions.ps1")
. (Join-Path $toolRoot "lib\\render.ps1")
. (Join-Path $toolRoot "providers\\codex.ps1")

function New-TestComponents {
    return @{
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
}

function New-TestConfig {
    param(
        [string]$Root,
        [hashtable]$Components,
        [hashtable]$Launch = @{ codex_cli = "codex"; codex_app = $null }
    )

    $userRoot = Join-Path $Root "user"
    return Expand-ToolConfigPaths -Config @{
        provider   = "codex"
        sync_repo  = (Join-Path $Root "sync-repo")
        machine_id = "desktop-win"
        components = $Components
        paths      = @{
            codex_home         = (Join-Path $userRoot ".codex")
            agents_home        = (Join-Path $userRoot ".agents")
            powershell_profile = (Join-Path $userRoot "Documents\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1")
            git_config         = (Join-Path $userRoot ".gitconfig")
        }
        identities = @{
            strategy = "git_remote_slug"
            aliases  = @{}
        }
        launch     = $Launch
    }
}

Describe "codex-setup-sync codex provider" {
    It "does not treat seeded empty files as shared state" {
        $components = New-TestComponents
        $components.codex_config = $false
        $components.rules = $false
        $components.skills = $false
        $components.memories = $false
        $components.sessions_export = $false

        $config = New-TestConfig -Root $TestDrive -Components $components

        Initialize-CodexRepoLayout -Config $config

        (Test-CodexSharedStatePresent -Config $config) | Should Be $false
    }

    It "does not move frontend-skill when skills sync is disabled" {
        $components = New-TestComponents
        $components.codex_config = $false
        $components.rules = $false
        $components.skills = $false
        $components.memories = $false
        $components.sessions_export = $false

        $config = New-TestConfig -Root $TestDrive -Components $components
        $paths = Get-CodexProviderPaths -Config $config
        Write-Utf8NoBom -Path (Join-Path $paths.codex_frontend_skill "SKILL.md") -Text "# Frontend Skill`n"

        Export-CodexPortableState -Config $config -Paths $paths

        (Test-Path -LiteralPath (Join-Path $paths.codex_frontend_skill "SKILL.md")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $paths.agents_skills "frontend-skill\\SKILL.md")) | Should Be $false
    }

    It "generates portable launch wrappers that parse without embedded local paths" {
        $components = New-TestComponents
        $components.codex_config = $false
        $components.rules = $false
        $components.skills = $false
        $components.memories = $false
        $components.sessions_export = $false
        $components.launch_wrappers = $true

        $config = New-TestConfig -Root $TestDrive -Components $components -Launch @{
            codex_cli = "C:\\Program Files\\O'Brien\\codex.cmd"
            codex_app = "C:\\Users\\O'Brien\\Codex.exe"
        }

        Export-CodexLaunchWrappers -Config $config

        $cliWrapperPath = Join-Path $config.sync_repo "Open-CodexCLI.ps1"
        $appWrapperPath = Join-Path $config.sync_repo "Open-CodexApp.ps1"
        $cliWrapper = Get-Content -LiteralPath $cliWrapperPath -Raw
        $appWrapper = Get-Content -LiteralPath $appWrapperPath -Raw

        [scriptblock]::Create($cliWrapper) | Should Not BeNullOrEmpty
        [scriptblock]::Create($appWrapper) | Should Not BeNullOrEmpty
        $cliWrapper | Should Match "Get-Command 'codex-setup-sync\.ps1'"
        $appWrapper | Should Match ([regex]::Escape(".codex-setup-sync.json"))
        $cliWrapper | Should Not Match ([regex]::Escape($TestDrive))
        $appWrapper | Should Not Match ([regex]::Escape($TestDrive))
        $cliWrapper | Should Not Match "O''Brien"
        $appWrapper | Should Not Match "O''Brien"
    }

    It "exports and reimports portable state plus completed sessions" {
        $config = New-TestConfig -Root $TestDrive -Components @{
            codex_config    = $true
            rules           = $true
            skills          = $true
            memories        = $true
            sessions_export = $true
            sessions_import = $true
            shell_profile   = $false
            git_config      = $false
            launch_wrappers = $true
        } -Launch @{
            codex_cli = "codex"
            codex_app = "C:\\Codex\\Codex.exe"
        }

        $syncRepo = $config.sync_repo
        $paths = Get-CodexProviderPaths -Config $config
        Ensure-Directory $paths.codex_rules
        Ensure-Directory $paths.codex_memories
        Ensure-Directory $paths.codex_sessions
        Ensure-Directory $paths.codex_skill_root
        Ensure-Directory $paths.agents_skills

        Write-Utf8NoBom -Path $paths.codex_config -Text @"
model = "gpt-5"

[projects.'D:\\anbs-dev\\agentic-engineering']
trust_level = "trusted"
"@
        Write-Utf8NoBom -Path (Join-Path $paths.codex_rules "default.rules") -Text "Always be explicit.`n"
        Write-Utf8NoBom -Path (Join-Path $paths.codex_memories "memory.md") -Text "Remember this.`n"
        Write-Utf8NoBom -Path (Join-Path $paths.agents_skills "custom-skill\\SKILL.md") -Text "# Custom Skill`n"
        Write-Utf8NoBom -Path $paths.agents_skill_lock -Text "{}`n"
        Write-Utf8NoBom -Path (Join-Path $paths.codex_frontend_skill "SKILL.md") -Text "# Frontend Skill`n"

        $sessionPath = Join-Path $paths.codex_sessions "2026\\03\\29\\rollout-test.jsonl"
        Write-Utf8NoBom -Path $sessionPath -Text ((@{
            type    = "session_meta"
            payload = @{
                id          = "session-sync-1"
                cwd         = (Join-Path $TestDrive "Project Alpha")
                timestamp   = "2026-03-29T20:00:00Z"
                originator  = "Codex Desktop"
                cli_version = "0.115.0"
            }
        } | ConvertTo-Json -Compress) + "`n")
        Ensure-Directory (Join-Path $TestDrive "Project Alpha")
        (Get-Item -LiteralPath $sessionPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-5)

        Initialize-CodexRepoLayout -Config $config
        Export-CodexPortableState -Config $config -Paths $paths
        $exportedSessions = Export-CodexSessions -Config $config -Paths $paths
        Export-CodexLaunchWrappers -Config $config

        Test-Path -LiteralPath (Get-CodexSharedConfigPath -Config $config) | Should Be $true
        (Get-Content -LiteralPath (Get-CodexSharedConfigPath -Config $config) -Raw) | Should Match 'model = "gpt-5"'
        (Get-Content -LiteralPath (Get-MachineConfigTomlPath -Config $config) -Raw) | Should Match 'trust_level = "trusted"'
        Test-Path -LiteralPath (Join-Path $paths.agents_skills "frontend-skill\\SKILL.md") | Should Be $true
        $exportedSessions.Count | Should Be 1
        Test-Path -LiteralPath (Join-Path $syncRepo "Open-CodexCLI.ps1") | Should Be $true

        Remove-Item -LiteralPath $paths.codex_config -Force
        Remove-Item -LiteralPath $paths.codex_rules -Recurse -Force
        Remove-Item -LiteralPath $paths.codex_memories -Recurse -Force
        Remove-Item -LiteralPath $paths.agents_skills -Recurse -Force
        Remove-Item -LiteralPath $paths.agents_skill_lock -Force
        Remove-Item -LiteralPath $paths.codex_sessions -Recurse -Force

        Import-CodexPortableState -Config $config -Paths $paths
        $importedSessions = Import-CodexSessions -Config $config -Paths $paths

        Test-Path -LiteralPath $paths.codex_config | Should Be $true
        Test-Path -LiteralPath (Join-Path $paths.codex_rules "default.rules") | Should Be $true
        Test-Path -LiteralPath (Join-Path $paths.codex_memories "memory.md") | Should Be $true
        Test-Path -LiteralPath (Join-Path $paths.agents_skills "custom-skill\\SKILL.md") | Should Be $true
        $importedSessions.Count | Should Be 1
        (Get-Content -LiteralPath $paths.codex_config -Raw) | Should Match 'model = "gpt-5"'
    }
}