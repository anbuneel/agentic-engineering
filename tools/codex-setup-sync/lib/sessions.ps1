function Get-SessionMetadata {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1
    if (-not $firstLine) {
        return $null
    }

    try {
        $record = $firstLine | ConvertFrom-Json
    } catch {
        return $null
    }

    if ($record.type -ne "session_meta") {
        return $null
    }

    return @{
        session_id  = "$($record.payload.id)"
        cwd         = "$($record.payload.cwd)"
        timestamp   = "$($record.payload.timestamp)"
        originator  = "$($record.payload.originator)"
        cli_version = "$($record.payload.cli_version)"
    }
}

function Test-SessionEligible {
    param(
        [string]$Path,
        [int]$MinimumAgeMinutes = 2
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        return $null
    }

    if ($item.LastWriteTimeUtc -gt ([DateTime]::UtcNow.AddMinutes(-1 * $MinimumAgeMinutes))) {
        return $null
    }

    $metadata = Get-SessionMetadata -Path $Path
    if (-not $metadata) {
        return $null
    }

    return @{
        path     = $item.FullName
        metadata = $metadata
        sha256   = Get-FileHashString -Path $item.FullName
    }
}

function Get-DatePartsFromSessionPath {
    param(
        [string]$SessionsRoot,
        [string]$Path
    )

    $relative = Get-RelativePathSafe -BasePath $SessionsRoot -FullPath $Path
    if ($relative -match '^(?<year>\d{4})[\\/](?<month>\d{2})[\\/](?<day>\d{2})[\\/]') {
        return @{
            year  = $Matches["year"]
            month = $Matches["month"]
            day   = $Matches["day"]
        }
    }

    $item = Get-Item -LiteralPath $Path
    return @{
        year  = $item.LastWriteTimeUtc.ToString("yyyy")
        month = $item.LastWriteTimeUtc.ToString("MM")
        day   = $item.LastWriteTimeUtc.ToString("dd")
    }
}

function New-SessionManifest {
    param(
        [hashtable]$Metadata,
        [hashtable]$Identity,
        [string]$MachineId,
        [string]$SourcePath,
        [string]$Sha256
    )

    return @{
        provider          = "codex"
        session_id        = $Metadata.session_id
        canonical_project = $Identity.canonical_project
        identity_source   = $Identity.identity_source
        source_machine    = $MachineId
        source_path       = $SourcePath
        exported_at       = Get-IsoTimestamp
        sha256            = $Sha256
    }
}
