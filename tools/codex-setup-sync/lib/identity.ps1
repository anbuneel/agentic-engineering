function Convert-GitRemoteToCanonicalProject {
    param([string]$Url)

    if (-not $Url) {
        return $null
    }

    $trimmed = $Url.Trim().TrimEnd("/")
    if ($trimmed -match '(?:[:/])([^/:]+)/([^/]+?)(?:\.git)?$') {
        return ("{0}/{1}" -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }

    return $null
}

function Get-MachineAliasesPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderMachineRootPath -Config $Config) "aliases.json"
}

function Get-MachineConfigTomlPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderMachineRootPath -Config $Config) "config.local.toml"
}

function Get-MachineDescriptorPath {
    param([hashtable]$Config)
    return Join-Path (Get-ProviderMachineRootPath -Config $Config) "machine.json"
}

function Get-EffectiveAliases {
    param([hashtable]$Config)

    $aliases = @{}
    foreach ($pair in (ConvertTo-PlainObject $Config.identities.aliases).GetEnumerator()) {
        $aliases[$pair.Key] = $pair.Value
    }

    $machineAliasPath = Get-MachineAliasesPath -Config $Config
    if (Test-Path -LiteralPath $machineAliasPath) {
        $machineAliases = Read-JsonFile -Path $machineAliasPath
        foreach ($pair in $machineAliases.GetEnumerator()) {
            $aliases[$pair.Key] = $pair.Value
        }
    }

    return $aliases
}

function Save-EffectiveAliases {
    param(
        [hashtable]$Config,
        [hashtable]$Aliases
    )

    $config.identities.aliases = ConvertTo-PlainObject $Aliases
    Save-ToolConfig -Config $Config
    Write-JsonFile -Path (Get-MachineAliasesPath -Config $Config) -Value $Aliases
}

function Set-ProjectAlias {
    param(
        [hashtable]$Config,
        [string]$LocalPath,
        [string]$CanonicalProject
    )

    $aliases = Get-EffectiveAliases -Config $Config
    $aliases[(Get-NormalizedPathKey -Path $LocalPath)] = $CanonicalProject.ToLowerInvariant()
    Save-EffectiveAliases -Config $Config -Aliases $aliases
}

function Resolve-ProjectIdentity {
    param(
        [string]$Path,
        [hashtable]$Config
    )

    $normalized = Get-NormalizedPathKey -Path $Path
    if ($Config.identities.strategy -eq "git_remote_slug") {
        $remoteUrl = Get-GitRemoteUrl -Path $Path
        $canonical = Convert-GitRemoteToCanonicalProject -Url $remoteUrl
        if ($canonical) {
            return @{
                canonical_project = $canonical
                identity_source   = "git_remote"
            }
        }
    }

    $aliases = Get-EffectiveAliases -Config $Config
    if ($aliases.ContainsKey($normalized)) {
        return @{
            canonical_project = "$($aliases[$normalized])"
            identity_source   = "alias"
        }
    }

    return @{
        canonical_project = ((Split-Path -Leaf (Get-NormalizedFullPath -Path $Path)) -replace '\s+', '-').ToLowerInvariant()
        identity_source   = "folder_fallback"
    }
}
