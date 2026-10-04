# Install the repo Tabby config over the live one, carrying over the machine-local
# default profile and known hosts. Run in PowerShell 7:
#   irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex
#
# Optional environment overrides (used for testing):
#   TABBY_CONFIG_PATH       live Tabby config to read and write
#   SSH_CONFIG_PATH         ssh config to list Host aliases from
#   TABBY_REPO_CONFIG_PATH  local file to read the repo config from instead of downloading
& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $RepoConfigUrl = 'https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/config.yaml'
    $OpensshProfilePrefix = 'openssh-config:'
    $LocalProfilePrefix = 'local:'
    $TerminalSection = 'terminal'
    $SshSection = 'ssh'
    $LocalShellChoice = 0

    function Get-LiveConfigPath {
        if ($env:TABBY_CONFIG_PATH) { return $env:TABBY_CONFIG_PATH }
        return Join-Path $env:APPDATA 'tabby\config.yaml'
    }

    function Get-SshConfigPath {
        if ($env:SSH_CONFIG_PATH) { return $env:SSH_CONFIG_PATH }
        return Join-Path $env:USERPROFILE '.ssh\config'
    }

    function Assert-TabbyNotRunning {
        if (Get-Process -Name Tabby -ErrorAction SilentlyContinue) {
            throw 'Tabby is running. Quit it fully (including the tray icon) and run again.'
        }
    }

    function Split-Lines([string]$text) {
        $lines = $text -split "`r?`n"
        if ($lines[-1] -eq '') { return $lines[0..($lines.Count - 2)] }
        return $lines
    }

    function Read-RepoConfigLines {
        if ($env:TABBY_REPO_CONFIG_PATH) {
            return Split-Lines (Get-Content -Path $env:TABBY_REPO_CONFIG_PATH -Raw -Encoding UTF8)
        }
        return Split-Lines (Invoke-RestMethod -Uri $RepoConfigUrl)
    }

    function Get-SectionLines([string[]]$configLines, [string]$sectionName) {
        $isInside = $false
        foreach ($line in $configLines) {
            if ($line -eq "${sectionName}:") { $isInside = $true; continue }
            if ($isInside -and $line -match '^\S') { return }
            if ($isInside) { $line }
        }
    }

    function Get-DefaultProfile([string[]]$configLines) {
        foreach ($line in @(Get-SectionLines $configLines $TerminalSection)) {
            if ($line -match '^  profile: *(.+?)\s*$') { return $Matches[1] }
        }
        return ''
    }

    function Get-KnownHostsBlock([string[]]$configLines) {
        $block = @()
        $isCapturing = $false
        foreach ($line in @(Get-SectionLines $configLines $SshSection)) {
            if ($isCapturing -and $line -match '^   ') { $block += $line; continue }
            if ($isCapturing) { break }
            if ($line -notmatch '^  knownHosts:') { continue }
            if ($line -match '\[\]') { break }
            $isCapturing = $true
            $block += $line
        }
        return $block
    }

    function Get-HostAliases([string]$sshConfigPath) {
        foreach ($line in Get-Content -Path $sshConfigPath) {
            $tokens = $line.Trim() -split '\s+'
            if ($tokens.Count -lt 2 -or $tokens[0] -ne 'Host') { continue }
            $tokens[1..($tokens.Count - 1)] | Where-Object { $_ -notmatch '[*?]' -and $_ -notlike '!*' }
        }
    }

    function Get-OpensshProfileId([string]$hostAlias) {
        $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($hostAlias))
        return $OpensshProfilePrefix + [System.Convert]::ToHexString($hashBytes).ToLowerInvariant()
    }

    function Show-ProfileMenu([string[]]$hostAliases) {
        Write-Host 'Choose the default profile:'
        Write-Host "  $LocalShellChoice) Local shell (Tabby default)"
        for ($position = 0; $position -lt $hostAliases.Count; $position++) {
            Write-Host "  $($position + 1)) $($hostAliases[$position])"
        }
    }

    function Test-ValidChoice([string]$choice, [int]$choiceCount) {
        return $choice -match '^\d+$' -and [int]$choice -le $choiceCount
    }

    function Read-ProfileChoice([int]$choiceCount) {
        while ($true) {
            $choice = Read-Host 'Choice'
            if ($null -eq $choice) { throw 'No input available.' }
            if (Test-ValidChoice $choice $choiceCount) { return [int]$choice }
            Write-Host "Invalid choice, enter a number between 0 and $choiceCount."
        }
    }

    function Read-HostAliases {
        $sshConfigPath = Get-SshConfigPath
        if (-not (Test-Path -Path $sshConfigPath)) { return }
        Get-HostAliases $sshConfigPath
    }

    function Prompt-DefaultProfile([string[]]$hostAliases) {
        $sshConfigPath = Get-SshConfigPath
        if (-not (Test-Path -Path $sshConfigPath)) {
            Write-Host "No ssh config at $sshConfigPath, using the local shell."
            return ''
        }
        if ($hostAliases.Count -eq 0) {
            Write-Host "No Host aliases in $sshConfigPath, using the local shell."
            return ''
        }
        Show-ProfileMenu $hostAliases
        $choice = Read-ProfileChoice $hostAliases.Count
        if ($choice -eq $LocalShellChoice) { return '' }
        return Get-OpensshProfileId $hostAliases[$choice - 1]
    }

    function Test-SurvivingProfile([string]$existingProfile, [string[]]$hostAliases) {
        if (-not $existingProfile.StartsWith($OpensshProfilePrefix)) { return $false }
        foreach ($hostAlias in $hostAliases) {
            if ((Get-OpensshProfileId $hostAlias) -eq $existingProfile) { return $true }
        }
        return $false
    }

    function Write-DiscardedProfileWarning([string]$existingProfile) {
        if (-not $existingProfile -or $existingProfile.StartsWith($LocalProfilePrefix)) { return }
        Write-Host "Default profile $existingProfile will not exist after install, choose a new one."
    }

    function Select-DefaultProfile([string]$existingProfile, [string[]]$hostAliases) {
        if (Test-SurvivingProfile $existingProfile $hostAliases) {
            Write-Host "Default profile kept: $existingProfile"
            return $existingProfile
        }
        Write-DiscardedProfileWarning $existingProfile
        return Prompt-DefaultProfile $hostAliases
    }

    function Assert-RepoConfigValid([string[]]$repoLines) {
        if ($repoLines -notcontains "${TerminalSection}:") { throw "Repo config has no '${TerminalSection}:' line." }
        if ($repoLines -notcontains "${SshSection}:") { throw "Repo config has no '${SshSection}:' line." }
    }

    function Build-Config([string[]]$repoLines, [string]$profileId, [string[]]$knownHostsBlock) {
        foreach ($line in $repoLines) {
            $line
            if ($line -eq "${TerminalSection}:" -and $profileId) { "  profile: $profileId" }
            if ($line -eq "${SshSection}:" -and $knownHostsBlock.Count -gt 0) { $knownHostsBlock }
        }
    }

    function Backup-LiveConfig([string]$liveConfigPath) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = Join-Path (Split-Path -Parent $liveConfigPath) "config.backup-$timestamp.yaml"
        Copy-Item -Path $liveConfigPath -Destination $backupPath
        return $backupPath
    }

    function Write-ConfigFile([string]$configPath, [string[]]$configLines) {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, ($configLines -join "`n") + "`n", $utf8WithoutBom)
    }

    function Install-TabbyConfig {
        Assert-TabbyNotRunning
        $liveConfigPath = Get-LiveConfigPath
        $repoLines = @(Read-RepoConfigLines)
        Assert-RepoConfigValid $repoLines
        $existingProfile = ''
        $knownHostsBlock = @()
        $hasLiveConfig = Test-Path -Path $liveConfigPath
        if ($hasLiveConfig) {
            $liveLines = @(Split-Lines (Get-Content -Path $liveConfigPath -Raw -Encoding UTF8))
            $existingProfile = Get-DefaultProfile $liveLines
            $knownHostsBlock = @(Get-KnownHostsBlock $liveLines)
        }

        $profileId = Select-DefaultProfile $existingProfile @(Read-HostAliases)

        $newLines = @(Build-Config $repoLines $profileId $knownHostsBlock)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $liveConfigPath) | Out-Null
        $backupPath = 'none'
        if ($hasLiveConfig) {
            $backupPath = Backup-LiveConfig $liveConfigPath
            Write-Host "Backup written: $backupPath"
        }
        Write-ConfigFile $liveConfigPath $newLines

        $knownHostCount = @($knownHostsBlock | Where-Object { $_ -match '^\s*- host:' }).Count
        Write-Host "Tabby config installed: $liveConfigPath"
        Write-Host "  Default profile: $(if ($profileId) { $profileId } else { 'Tabby default local shell' })"
        Write-Host "  Known hosts kept: $knownHostCount"
        Write-Host "  Backup: $backupPath"
    }

    Install-TabbyConfig
}
