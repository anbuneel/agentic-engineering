$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\config.ps1")
. (Join-Path $toolRoot "lib\\git.ps1")
. (Join-Path $toolRoot "lib\\identity.ps1")

Describe "codex-setup-sync identity" {
    It "normalizes HTTPS and SSH remotes into owner/repo" {
        Convert-GitRemoteToCanonicalProject "https://github.com/OpenAI/Codex.git" | Should Be "openai/codex"
        Convert-GitRemoteToCanonicalProject "git@github.com:OpenAI/Codex.git" | Should Be "openai/codex"
    }

    It "uses configured aliases when no git remote is available" {
        $projectPath = Join-Path $TestDrive "project-alpha"
        $config = Expand-ToolConfigPaths -Config @{
            provider   = "codex"
            sync_repo  = (Join-Path $TestDrive "sync")
            machine_id = "test-machine"
            components = (Get-DefaultToolConfig).components
            paths      = (Get-DefaultToolConfig).paths
            identities = @{
                strategy = "git_remote_slug"
                aliases  = @{
                    ((Get-NormalizedPathKey -Path $projectPath)) = "owner/project-alpha"
                }
            }
            launch     = (Get-DefaultToolConfig).launch
        }

        $identity = Resolve-ProjectIdentity -Path $projectPath -Config $config
        $identity.canonical_project | Should Be "owner/project-alpha"
        $identity.identity_source | Should Be "alias"
    }

    It "falls back to the folder name when no remote or alias exists" {
        $projectPath = Join-Path $TestDrive "My Project"
        $config = Expand-ToolConfigPaths -Config (Get-DefaultToolConfig)

        $identity = Resolve-ProjectIdentity -Path $projectPath -Config $config
        $identity.canonical_project | Should Be "my-project"
        $identity.identity_source | Should Be "folder_fallback"
    }
}
