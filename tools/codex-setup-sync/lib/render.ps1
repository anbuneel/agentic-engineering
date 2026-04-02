function Get-CodexSharedConfigPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderSharedRootPath -Config $Config) "config.base.toml"
}

function Split-TomlContentForCodex {
    param([string]$Text)

    $projectHeaderPattern = '^\s*\[projects\..+\]\s*$'
    $sectionHeaderPattern = '^\s*\[.+\]\s*$'

    $baseChunks = New-Object System.Collections.Generic.List[string]
    $localChunks = New-Object System.Collections.Generic.List[string]
    $currentLines = New-Object System.Collections.Generic.List[string]
    $target = "base"

    foreach ($line in (Split-StringIntoLines -Text $Text)) {
        if ($line -match $sectionHeaderPattern) {
            if ($currentLines.Count -gt 0) {
                if ($target -eq "local") {
                    $localChunks.Add(($currentLines -join "`n").TrimEnd())
                } else {
                    $baseChunks.Add(($currentLines -join "`n").TrimEnd())
                }
                $currentLines = New-Object System.Collections.Generic.List[string]
            }

            $target = if ($line -match $projectHeaderPattern) { "local" } else { "base" }
        }

        $currentLines.Add($line)
    }

    if ($currentLines.Count -gt 0) {
        if ($target -eq "local") {
            $localChunks.Add(($currentLines -join "`n").TrimEnd())
        } else {
            $baseChunks.Add(($currentLines -join "`n").TrimEnd())
        }
    }

    return @{
        base  = (($baseChunks | Where-Object { $_ -ne "" }) -join "`n`n").Trim()
        local = (($localChunks | Where-Object { $_ -ne "" }) -join "`n`n").Trim()
    }
}

function Export-CodexConfigFragmentsFromLive {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    $sharedConfigPath = Get-CodexSharedConfigPath -Config $Config
    $machineConfigPath = Get-MachineConfigTomlPath -Config $Config
    $liveConfigPath = $Paths.codex_config

    if (-not (Test-Path -LiteralPath $liveConfigPath)) {
        if (-not (Test-Path -LiteralPath $sharedConfigPath)) {
            Write-Utf8NoBom -Path $sharedConfigPath -Text ""
        }
        if (-not (Test-Path -LiteralPath $machineConfigPath)) {
            Write-Utf8NoBom -Path $machineConfigPath -Text ""
        }
        return
    }

    $split = Split-TomlContentForCodex -Text (Get-Content -LiteralPath $liveConfigPath -Raw)
    Write-Utf8NoBom -Path $sharedConfigPath -Text ($split.base + "`n")
    Write-Utf8NoBom -Path $machineConfigPath -Text ($split.local + "`n")
}

function Render-LiveCodexConfig {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    $parts = @()
    foreach ($path in @((Get-CodexSharedConfigPath -Config $Config), (Get-MachineConfigTomlPath -Config $Config))) {
        if (Test-Path -LiteralPath $path) {
            $content = (Get-Content -LiteralPath $path -Raw).Trim()
            if ($content) {
                $parts += $content
            }
        }
    }

    $rendered = ($parts -join "`n`n").Trim()
    if ($rendered) {
        Write-Utf8NoBom -Path $Paths.codex_config -Text ($rendered + "`n")
    } elseif (Test-Path -LiteralPath $Paths.codex_config) {
        Remove-Item -LiteralPath $Paths.codex_config -Force
    }
}

function Get-CodexSharedShellProfilePath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderSharedRootPath -Config $Config) "shell\profile.ps1"
}

function Get-CodexSharedGitConfigPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderSharedRootPath -Config $Config) "git\gitconfig.shared"
}

function Get-CodexMachineGitConfigPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderMachineRootPath -Config $Config) "git.local.ini"
}

function Test-ManagedShellProfile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    return [bool](Select-String -Path $Path -Pattern "Managed by codex-setup-sync" -SimpleMatch -ErrorAction SilentlyContinue)
}

function Install-ManagedShellProfile {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    $sharedPath = Get-CodexSharedShellProfilePath -Config $Config
    $livePath = $Paths.shell_profile
    if (-not (Test-Path -LiteralPath $sharedPath)) {
        return
    }

    $stub = @"
# Managed by codex-setup-sync. Edit the shared profile in the sync repo.
$sharedProfile = '$sharedPath'
if (Test-Path -LiteralPath `$sharedProfile) {
    . `$sharedProfile
}
"@
    Write-Utf8NoBom -Path $livePath -Text $stub
}

function Export-ShellProfileIfEnabled {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    if (-not $Config.components.shell_profile) {
        return
    }

    $sharedPath = Get-CodexSharedShellProfilePath -Config $Config
    if (-not (Test-Path -LiteralPath $sharedPath) -and (Test-Path -LiteralPath $Paths.shell_profile) -and -not (Test-ManagedShellProfile -Path $Paths.shell_profile)) {
        Copy-FileIfChanged -Source $Paths.shell_profile -Destination $sharedPath
    }

    if (Test-Path -LiteralPath $sharedPath) {
        Install-ManagedShellProfile -Config $Config -Paths $Paths
    }
}

function Split-GitConfigText {
    param([string]$Text)

    $sectionPattern = '^\s*\[.+\]\s*$'
    $localPattern = '^\s*\[core\]\s*$'
    $sharedChunks = New-Object System.Collections.Generic.List[string]
    $localChunks = New-Object System.Collections.Generic.List[string]
    $currentLines = New-Object System.Collections.Generic.List[string]
    $target = "shared"

    foreach ($line in (Split-StringIntoLines -Text $Text)) {
        if ($line -match $sectionPattern) {
            if ($currentLines.Count -gt 0) {
                if ($target -eq "local") {
                    $localChunks.Add(($currentLines -join "`n").TrimEnd())
                } else {
                    $sharedChunks.Add(($currentLines -join "`n").TrimEnd())
                }
                $currentLines = New-Object System.Collections.Generic.List[string]
            }
            $target = if ($line -match $localPattern) { "local" } else { "shared" }
        }
        $currentLines.Add($line)
    }

    if ($currentLines.Count -gt 0) {
        if ($target -eq "local") {
            $localChunks.Add(($currentLines -join "`n").TrimEnd())
        } else {
            $sharedChunks.Add(($currentLines -join "`n").TrimEnd())
        }
    }

    return @{
        shared = (($sharedChunks | Where-Object { $_ -ne "" }) -join "`n`n").Trim()
        local  = (($localChunks | Where-Object { $_ -ne "" }) -join "`n`n").Trim()
    }
}

function Install-ManagedGitIncludes {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    $sharedPath = (Get-CodexSharedGitConfigPath -Config $Config) -replace '\\', '/'
    $localPath = (Get-CodexMachineGitConfigPath -Config $Config) -replace '\\', '/'

    $content = @"
# Managed by codex-setup-sync. Edit the included files instead.
[include]
    path = $sharedPath
[include]
    path = $localPath
"@
    Write-Utf8NoBom -Path $Paths.git_config -Text $content
}

function Export-GitConfigIfEnabled {
    param(
        [hashtable]$Config,
        [hashtable]$Paths
    )

    if (-not $Config.components.git_config) {
        return
    }

    $sharedPath = Get-CodexSharedGitConfigPath -Config $Config
    $localPath = Get-CodexMachineGitConfigPath -Config $Config
    $livePath = $Paths.git_config

    if (Test-Path -LiteralPath $livePath) {
        $raw = Get-Content -LiteralPath $livePath -Raw
        if ($raw -notmatch "Managed by codex-setup-sync") {
            $split = Split-GitConfigText -Text $raw
            if ($split.shared) {
                Write-Utf8NoBom -Path $sharedPath -Text ($split.shared + "`n")
            }
            if ($split.local) {
                Write-Utf8NoBom -Path $localPath -Text ($split.local + "`n")
            } elseif (-not (Test-Path -LiteralPath $localPath)) {
                Write-Utf8NoBom -Path $localPath -Text ""
            }
        }
    }

    if ((Test-Path -LiteralPath $sharedPath) -or (Test-Path -LiteralPath $localPath)) {
        Install-ManagedGitIncludes -Config $Config -Paths $Paths
    }
}
