$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\config.ps1")
. (Join-Path $toolRoot "lib\\git.ps1")
. (Join-Path $toolRoot "lib\\identity.ps1")
. (Join-Path $toolRoot "lib\\sessions.ps1")
. (Join-Path $toolRoot "lib\\render.ps1")
. (Join-Path $toolRoot "providers\\codex.ps1")

Describe "codex-setup-sync codex provider" {
    It "exports and reimports portable state plus completed sessions" {
        $syncRepo = Join-Path $TestDrive "sync-repo"
        $userRoot = Join-Path $TestDrive "user"
        $codexHome = Join-Path $userRoot ".codex"
        $agentsHome = Join-Path $userRoot ".agents"

        $config = Expand-ToolConfigPaths -Config @{
            provider   = "codex"
            sync_repo  = $syncRepo
            machine_id = "desktop-win"
            components = @{
                codex_config    = $true
                rules           = $true
                skills          = $true
                memories        = $true
                sessions_export = $true
                sessions_import = $true
                shell_profile   = $false
                git_config      = $false
                launch_wrappers = $true
            }
            paths      = @{
                codex_home         = $codexHome
                agents_home        = $agentsHome
                powershell_profile = (Join-Path $userRoot "Documents\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1")
                git_config         = (Join-Path $userRoot ".gitconfig")
            }
            identities = @{
                strategy = "git_remote_slug"
                aliases  = @{}
            }
            launch     = @{
                codex_cli = "codex"
                codex_app = "C:\\Codex\\Codex.exe"
            }
        }

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
        (Get-Content -LiteralPath (Get-MachineConfigTomlPath -Config $config) -Raw) | Should Match "trust_level = ""trusted"""
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
