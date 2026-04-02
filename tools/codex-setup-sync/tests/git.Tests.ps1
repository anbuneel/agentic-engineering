$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\git.ps1")

Describe "codex-setup-sync git helpers" {
    It "initializes repositories through Invoke-GitCommand" {
        $repoPath = Join-Path $TestDrive "repo"

        Git-InitRepository -RepoPath $repoPath

        (Test-Path -LiteralPath (Join-Path $repoPath ".git")) | Should Be $true
    }
}