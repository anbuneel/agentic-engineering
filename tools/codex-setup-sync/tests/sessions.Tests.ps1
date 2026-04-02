$toolRoot = Split-Path -Parent $PSScriptRoot
$script:ToolRoot = $toolRoot

. (Join-Path $toolRoot "lib\\common.ps1")
. (Join-Path $toolRoot "lib\\sessions.ps1")

Describe "codex-setup-sync sessions" {
    It "parses session metadata and exports manifest fields" {
        $sessionsRoot = Join-Path $TestDrive "sessions"
        $sessionPath = Join-Path $sessionsRoot "2026\\03\\29\\rollout-test.jsonl"
        Ensure-Directory (Split-Path -Parent $sessionPath)

        $sessionMeta = @{
            type    = "session_meta"
            payload = @{
                id          = "session-123"
                cwd         = "D:\\work\\project"
                timestamp   = "2026-03-29T19:00:00Z"
                originator  = "Codex Desktop"
                cli_version = "0.115.0"
            }
        } | ConvertTo-Json -Compress

        Write-Utf8NoBom -Path $sessionPath -Text ($sessionMeta + "`n")
        (Get-Item -LiteralPath $sessionPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-5)

        $metadata = Get-SessionMetadata -Path $sessionPath
        $eligible = Test-SessionEligible -Path $sessionPath
        $dateParts = Get-DatePartsFromSessionPath -SessionsRoot $sessionsRoot -Path $sessionPath
        $manifest = New-SessionManifest -Metadata $metadata -Identity @{ canonical_project = "owner/project"; identity_source = "git_remote" } -MachineId "desktop-win" -SourcePath "D:\\work\\project" -Sha256 "abc123"

        $metadata.session_id | Should Be "session-123"
        $eligible | Should Not BeNullOrEmpty
        $dateParts.year | Should Be "2026"
        $dateParts.month | Should Be "03"
        $dateParts.day | Should Be "29"
        $manifest.provider | Should Be "codex"
        $manifest.canonical_project | Should Be "owner/project"
        $manifest.sha256 | Should Be "abc123"
    }
}
