if (-not $script:ToolRoot) {
    $script:ToolRoot = Split-Path -Parent $PSScriptRoot
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message"
}

function Write-Notice {
    param([string]$Message)
    Write-Host "note: $Message" -ForegroundColor Cyan
}

function Write-WarnMessage {
    param([string]$Message)
    Write-Host "warning: $Message" -ForegroundColor Yellow
}

function New-ToolException {
    param(
        [string]$Message,
        [int]$ExitCode = 1
    )

    $exception = New-Object System.Exception($Message)
    $exception.Data["ExitCode"] = $ExitCode
    return $exception
}

function Throw-ToolError {
    param(
        [string]$Message,
        [int]$ExitCode = 1
    )

    throw (New-ToolException -Message $Message -ExitCode $ExitCode)
}

function Get-ToolExitCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.Data.Contains("ExitCode")) {
        return [int]$ErrorRecord.Exception.Data["ExitCode"]
    }

    return 1
}

function Resolve-HomePath {
    param([string]$Path)

    if (-not $Path) {
        return $Path
    }

    if ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) {
        $suffix = $Path.Substring(2) -replace '/', '\'
        return Join-Path $HOME $suffix
    }

    if ($Path -eq "~") {
        return $HOME
    }

    return $Path
}

function Ensure-Directory {
    param([string]$Path)

    if (-not $Path) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )

    Ensure-Directory (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function ConvertTo-PlainObject {
    param([Parameter(ValueFromPipeline = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) {
            $result[$key] = ConvertTo-PlainObject $Value[$key]
        }
        return $result
    }

    if ($Value -is [pscustomobject] -or $Value -is [System.Management.Automation.PSObject]) {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-PlainObject $property.Value
        }
        return $result
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-PlainObject $item)
        }
        return $items
    }

    return $Value
}

function Merge-Hashtable {
    param(
        [hashtable]$Base,
        [hashtable]$Overlay
    )

    $result = @{}

    foreach ($key in $Base.Keys) {
        $result[$key] = ConvertTo-PlainObject $Base[$key]
    }

    foreach ($key in $Overlay.Keys) {
        if (
            $result.ContainsKey($key) -and
            $result[$key] -is [System.Collections.IDictionary] -and
            $Overlay[$key] -is [System.Collections.IDictionary]
        ) {
            $result[$key] = Merge-Hashtable -Base (ConvertTo-PlainObject $result[$key]) -Overlay (ConvertTo-PlainObject $Overlay[$key])
        } else {
            $result[$key] = ConvertTo-PlainObject $Overlay[$key]
        }
    }

    return $result
}

function Read-JsonFile {
    param(
        [string]$Path,
        [hashtable]$Default = @{}
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ConvertTo-PlainObject $Default
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return ConvertTo-PlainObject $Default
    }

    return ConvertTo-PlainObject ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Value
    )

    $json = ConvertTo-PlainObject $Value | ConvertTo-Json -Depth 20
    Write-Utf8NoBom -Path $Path -Text ($json + "`n")
}

function Get-NormalizedFullPath {
    param([string]$Path)

    $expanded = Resolve-HomePath $Path
    try {
        $resolved = Resolve-Path -LiteralPath $expanded -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Path
    } catch {
        $resolved = [System.IO.Path]::GetFullPath($expanded)
    }

    return $resolved.TrimEnd("\", "/")
}

function Get-NormalizedPathKey {
    param([string]$Path)
    return (Get-NormalizedFullPath -Path $Path).ToLowerInvariant()
}

function Get-RelativePathSafe {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = (Get-NormalizedFullPath -Path $BasePath) + "\"
    $full = Get-NormalizedFullPath -Path $FullPath

    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length)
    }

    return $full
}

function Get-FileHashString {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Copy-FileIfChanged {
    param(
        [string]$Source,
        [string]$Destination
    )

    Ensure-Directory (Split-Path -Parent $Destination)

    $sourceHash = Get-FileHashString -Path $Source
    $destinationHash = Get-FileHashString -Path $Destination

    if ($sourceHash -and $sourceHash -ne $destinationHash) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    } elseif (-not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Sync-OptionalFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Source) {
        Copy-FileIfChanged -Source $Source -Destination $Destination
    } elseif (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }
}

function Remove-EmptyDirectories {
    param([string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return
    }

    Get-ChildItem -LiteralPath $RootPath -Directory -Recurse |
        Sort-Object FullName -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        }
}

function Sync-DirectoryMirror {
    param(
        [string]$Source,
        [string]$Destination
    )

    Ensure-Directory $Destination

    $sourceMap = @{}
    if (Test-Path -LiteralPath $Source) {
        Get-ChildItem -LiteralPath $Source -File -Recurse | ForEach-Object {
            $relative = Get-RelativePathSafe -BasePath $Source -FullPath $_.FullName
            $sourceMap[$relative] = $_.FullName
            $targetPath = Join-Path $Destination $relative
            Copy-FileIfChanged -Source $_.FullName -Destination $targetPath
        }
    }

    Get-ChildItem -LiteralPath $Destination -File -Recurse | ForEach-Object {
        $relative = Get-RelativePathSafe -BasePath $Destination -FullPath $_.FullName
        if (-not $sourceMap.ContainsKey($relative)) {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }

    Remove-EmptyDirectories -RootPath $Destination
}

function Test-DirectoryHasFiles {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    return [bool](Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-IsoTimestamp {
    return [DateTime]::UtcNow.ToString("o")
}

function Get-CommandPathOrNull {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Split-StringIntoLines {
    param([string]$Text)

    if ($null -eq $Text) {
        return @()
    }

    return [regex]::Split($Text, "`r?`n")
}
