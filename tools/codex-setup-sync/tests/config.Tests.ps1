$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\config.ps1")

Describe "codex-setup-sync config" {
    It "defaults session import to disabled" {
        $config = Get-DefaultToolConfig
        $config.components.sessions_import | Should Be $false
    }

    It "expands tilde slash paths on Windows" {
        Resolve-HomePath "~/.codex" | Should Be (Join-Path $HOME ".codex")
        Resolve-HomePath "~\\Documents" | Should Be (Join-Path $HOME "Documents")
    }

    It "expands configured paths" {
        $expanded = Expand-ToolConfigPaths -Config (Get-DefaultToolConfig)
        $expanded.sync_repo | Should Be (Join-Path $HOME ".codex-setup-sync")
        $expanded.paths.codex_home | Should Be (Join-Path $HOME ".codex")
        $expanded.paths.agents_home | Should Be (Join-Path $HOME ".agents")
    }
}
