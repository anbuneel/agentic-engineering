$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'install-skill-links.ps1'

# The installer refuses to run unless every skill it knows about exists in the
# source tree, so the fixture has to carry the full list.
$script:SkillNames = @(
    'multi-agent-code-review',
    'multi-agent-plan-review',
    'multi-agent-ideate',
    'merge',
    'security-scan',
    'security-audit',
    'security-posture'
)

function New-InstallerFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('install-skill-links-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $skills = Join-Path $root 'repo\skills'
    New-Item -ItemType Directory -Force -Path $skills | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'codex') | Out-Null
    foreach ($name in $script:SkillNames) {
        Set-Content -Path (Join-Path $skills "$name.md") -Value "# $name`r`nsource content" -Encoding utf8
    }
    return $root
}

function Test-SymlinkPermitted {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ('symlink-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $link = "$target.link"
    Set-Content -Path $target -Value 'probe' -Encoding utf8
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $link -Force
        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    }
}

$script:SymlinkOk = Test-SymlinkPermitted

Describe "install-skill-links.ps1 mode handling" {
    $fixture = $null
    $savedCodexHome = $env:CODEX_HOME

    BeforeEach {
        $fixture = New-InstallerFixture
        $env:CODEX_HOME = Join-Path $fixture 'codex'
    }

    AfterEach {
        $env:CODEX_HOME = $savedCodexHome
        if ($fixture -and (Test-Path -LiteralPath $fixture)) {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Regression: Install-File returned early on "Already linked" before looking
    # at $Mode, so an explicit -Mode Copy was silently skipped whenever the
    # destination was already a correct symlink. The install then reported
    # success while leaving a link the caller had asked to replace.
    It "replaces an existing symlink with a real copy when -Mode Copy is requested" -Skip:(-not $script:SymlinkOk) {
        $repo = Join-Path $fixture 'repo'
        $dest = Join-Path $env:CODEX_HOME 'skills\merge\SKILL.md'

        & $scriptPath -RepoRoot $repo -Targets Codex -Mode SymbolicLink | Out-Null
        (Get-Item -LiteralPath $dest).LinkType | Should Be 'SymbolicLink'

        & $scriptPath -RepoRoot $repo -Targets Codex -Mode Copy | Out-Null

        $item = Get-Item -LiteralPath $dest
        $item.LinkType | Should Not Be 'SymbolicLink'
        (Get-Content -LiteralPath $dest -Raw) | Should Match 'source content'
    }

    It "leaves a correct symlink alone in Auto mode" -Skip:(-not $script:SymlinkOk) {
        $repo = Join-Path $fixture 'repo'
        $dest = Join-Path $env:CODEX_HOME 'skills\merge\SKILL.md'

        & $scriptPath -RepoRoot $repo -Targets Codex -Mode SymbolicLink | Out-Null
        & $scriptPath -RepoRoot $repo -Targets Codex -Mode Auto | Out-Null

        (Get-Item -LiteralPath $dest).LinkType | Should Be 'SymbolicLink'
    }

    # The same regression, reached without needing a real symlink: fake the
    # "already linked" answer and confirm Copy mode still writes. Before the
    # fix this left the stale content in place. Runs on every machine, so the
    # regression stays covered where symlinks require elevation.
    It "does not skip Copy mode when the destination already reports as linked" {
        $repo = Join-Path $fixture 'repo'
        $source = Join-Path $repo 'skills\merge.md'
        $dest = Join-Path $env:CODEX_HOME 'skills\merge\SKILL.md'

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Set-Content -Path $dest -Value 'stale content from an older revision' -Encoding utf8

        # Targets @() loads the functions without installing anything.
        . $scriptPath -Targets @() -Mode Copy | Out-Null
        Mock Test-LinkTarget { return $true }

        Install-File -Source $source -Destination $dest

        (Get-Content -LiteralPath $dest -Raw) | Should Match 'source content'
    }

    # Runs everywhere, including machines without Developer Mode, so the suite
    # is never entirely skipped.
    It "refreshes a stale copy in Copy mode" {
        $repo = Join-Path $fixture 'repo'
        $dest = Join-Path $env:CODEX_HOME 'skills\merge\SKILL.md'

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Set-Content -Path $dest -Value 'stale content from an older revision' -Encoding utf8

        & $scriptPath -RepoRoot $repo -Targets Codex -Mode Copy | Out-Null

        (Get-Content -LiteralPath $dest -Raw) | Should Match 'source content'
    }

    It "installs every skill for the Codex target" {
        $repo = Join-Path $fixture 'repo'

        & $scriptPath -RepoRoot $repo -Targets Codex -Mode Copy | Out-Null

        foreach ($name in $script:SkillNames) {
            $path = Join-Path $env:CODEX_HOME "skills\$name\SKILL.md"
            Test-Path -LiteralPath $path | Should Be $true
        }
    }

    It "rejects an unknown target" {
        $repo = Join-Path $fixture 'repo'
        { & $scriptPath -RepoRoot $repo -Targets 'Nonsense' -Mode Copy } | Should Throw
    }
}
