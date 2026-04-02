function Test-GitInstalled {
    return [bool](Get-CommandPathOrNull -Name "git")
}

function Invoke-GitCommand {
    param(
        [string[]]$Args,
        [string]$WorkingDirectory,
        [switch]$AllowFailure,
        [switch]$PassThru
    )

    if (-not (Test-GitInstalled)) {
        Throw-ToolError "git is required but was not found on PATH." 4
    }

    $gitArgs = @()
    if ($WorkingDirectory -and (Test-Path -LiteralPath (Join-Path $WorkingDirectory ".git"))) {
        $gitArgs += "-c"
        $gitArgs += "safe.directory=$WorkingDirectory"
    }
    if ($WorkingDirectory) {
        $gitArgs += "-C"
        $gitArgs += $WorkingDirectory
    }
    $gitArgs += $Args

    $lines = @()
    & git @gitArgs 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $lines += $_.ToString()
        } else {
            $lines += "$_"
        }
    }
    $exitCode = $LASTEXITCODE
    $output = ($lines | Where-Object { $_ -ne $null }) -join "`n"

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $suffix = if ($output) { ": $output" } else { "" }
        Throw-ToolError ("git {0} failed{1}" -f ($Args -join " "), $suffix) 3
    }

    if ($PassThru) {
        return @{
            ExitCode = $exitCode
            Output   = $output
        }
    }

    return $output
}

function Test-GitRemoteConfigured {
    param([string]$RepoPath)

    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("remote") -AllowFailure -PassThru
    if ($result.ExitCode -ne 0) {
        return $false
    }

    return -not [string]::IsNullOrWhiteSpace($result.Output)
}

function Get-GitStatusShort {
    param([string]$RepoPath)
    return Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("status", "--short")
}

function Test-GitDirty {
    param([string]$RepoPath)
    return -not [string]::IsNullOrWhiteSpace((Get-GitStatusShort -RepoPath $RepoPath))
}

function Get-GitRemoteUrl {
    param([string]$Path)
    $result = Invoke-GitCommand -WorkingDirectory $Path -Args @("remote", "get-url", "origin") -AllowFailure -PassThru
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    return ($result.Output -split "`r?`n" | Select-Object -First 1).Trim()
}

function Git-InitRepository {
    param([string]$RepoPath)

    Ensure-Directory $RepoPath
    Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("init") | Out-Null
}

function Git-CloneRepository {
    param(
        [string]$RepoUrl,
        [string]$Destination
    )

    Ensure-Directory (Split-Path -Parent $Destination)
    Invoke-GitCommand -Args @("clone", $RepoUrl, $Destination) | Out-Null
}

function Git-StageAll {
    param([string]$RepoPath)
    Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("add", "-A") | Out-Null
}

function Git-CommitIfDirty {
    param(
        [string]$RepoPath,
        [string]$Message
    )

    if (-not (Test-GitDirty -RepoPath $RepoPath)) {
        return $false
    }

    Git-StageAll -RepoPath $RepoPath
    Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("commit", "-m", $Message) | Out-Null
    return $true
}

function Git-PullRebaseIfRemote {
    param([string]$RepoPath)
    if (-not (Test-GitRemoteConfigured -RepoPath $RepoPath)) {
        return $false
    }

    Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("pull", "--rebase") | Out-Null
    return $true
}

function Git-PushIfRemote {
    param([string]$RepoPath)
    if (-not (Test-GitRemoteConfigured -RepoPath $RepoPath)) {
        return $false
    }

    Invoke-GitCommand -WorkingDirectory $RepoPath -Args @("push") | Out-Null
    return $true
}
