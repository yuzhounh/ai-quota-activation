param(
    [string]$AI = 'Codex,Claude,Antigravity',
    [string]$CodexPath,
    [string]$ClaudePath,
    [string]$AntigravityPath,
    [string]$CodexModel,
    [string]$ClaudeModel,
    [string]$AntigravityModel,
    [string]$LogDirectory = (Join-Path $PSScriptRoot 'logs'),
    [string]$StateDirectory = (Join-Path $PSScriptRoot 'state'),
    [string]$TaskName = 'AI Quota Activation',
    [int]$NetworkWaitSeconds = 45,
    [int]$PostWaitSeconds = 20,
    [int]$SleepIfIdleMinutes = 5,
    [int]$RecentWakeMinutes = 5,
    [switch]$CheckOnly,
    [switch]$DryRun,
    [switch]$NoSleep,
    [switch]$ShowVersion
)

$ErrorActionPreference = 'Stop'
$scriptVersion = '0.2'

if ($ShowVersion) {
    Write-Output "AI Quota Activation $scriptVersion"
    exit 0
}

if (-not $IsWindows) {
    throw 'This activation engine currently supports Windows only.'
}
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Run this script with PowerShell 7.4 or later (pwsh.exe).'
}

$supportedProviders = @('Codex', 'Claude', 'Antigravity')
$providers = @(
    $AI -split '[,;\s]+' |
        ForEach-Object {
            $candidate = $_.Trim()
            $match = $supportedProviders | Where-Object {
                [string]::Equals($_, $candidate, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
            if (-not $match) {
                throw "Unsupported AI '$candidate'. Supported values: $($supportedProviders -join ', ')."
            }
            $match
        } |
        Select-Object -Unique
)
if ($providers.Count -eq 0) {
    throw 'Select at least one AI with -AI, for example: -AI Codex,Claude.'
}

function Get-ProviderMetadata {
    param([Parameter(Mandatory)][string]$Provider)

    switch ($Provider) {
        'Codex' {
            return [pscustomobject]@{
                CommandNames = @('codex.exe', 'codex.cmd', 'codex')
                KnownPaths   = @(
                    (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'),
                    (Join-Path $env:APPDATA 'npm\codex.cmd')
                )
                InstallHint  = 'npm install -g @openai/codex@latest'
                Docs         = 'https://developers.openai.com/codex/cli'
            }
        }
        'Claude' {
            return [pscustomobject]@{
                CommandNames = @('claude.exe', 'claude.cmd', 'claude.ps1', 'claude')
                KnownPaths   = @(
                    (Join-Path $HOME '.local\bin\claude.exe'),
                    (Join-Path $env:APPDATA 'npm\claude.cmd'),
                    (Join-Path $env:APPDATA 'npm\claude.ps1'),
                    (Join-Path $env:APPDATA 'npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe'),
                    (Join-Path $env:LOCALAPPDATA 'Programs\Claude\bin\claude.exe')
                )
                InstallHint  = 'npm install -g @anthropic-ai/claude-code'
                Docs         = 'https://docs.anthropic.com/en/docs/claude-code/getting-started'
            }
        }
        'Antigravity' {
            return [pscustomobject]@{
                CommandNames = @('agy.exe', 'agy.cmd', 'agy')
                KnownPaths   = @(
                    (Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'),
                    (Join-Path $HOME '.local\bin\agy.exe')
                )
                InstallHint  = 'irm https://antigravity.google/cli/install.ps1 | iex'
                Docs         = 'https://antigravity.google/docs/cli-install'
            }
        }
    }
}

function Resolve-ProviderExecutable {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [string]$PreferredPath
    )

    if ($PreferredPath) {
        if (Test-Path -LiteralPath $PreferredPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $PreferredPath).Path
        }
        return $null
    }

    $metadata = Get-ProviderMetadata -Provider $Provider
    foreach ($commandName in $metadata.CommandNames) {
        $command = Get-Command $commandName -CommandType Application,ExternalScript -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }
    foreach ($candidate in $metadata.KnownPaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

$preferredPaths = @{
    Codex       = $CodexPath
    Claude      = $ClaudePath
    Antigravity = $AntigravityPath
}
$resolvedExecutables = @{}
$missingProviders = @()
foreach ($provider in $providers) {
    $resolved = Resolve-ProviderExecutable -Provider $provider -PreferredPath $preferredPaths[$provider]
    if ($resolved) {
        $resolvedExecutables[$provider] = $resolved
    }
    else {
        $missingProviders += $provider
    }
}

if ($missingProviders.Count -gt 0) {
    Write-Host ''
    Write-Host 'Missing required AI CLI(s):' -ForegroundColor Red
    foreach ($provider in $missingProviders) {
        $metadata = Get-ProviderMetadata -Provider $provider
        Write-Host "  $provider" -ForegroundColor Yellow
        Write-Host "    Install: $($metadata.InstallHint)"
        Write-Host "    Docs:    $($metadata.Docs)"
        if ($preferredPaths[$provider]) {
            Write-Host "    Configured path was not found: $($preferredPaths[$provider])"
        }
    }
    Write-Host ''
    Write-Host 'After installation, launch each CLI once interactively to finish sign-in, then rerun this script.'
    exit 2
}

if ($CheckOnly) {
    $providers | ForEach-Object {
        [pscustomobject]@{
            AI     = $_
            Status = 'Installed'
            Path   = $resolvedExecutables[$_]
        }
    } | Format-Table -AutoSize
    exit 0
}

New-Item -ItemType Directory -Force -Path $LogDirectory, $StateDirectory | Out-Null
$logPath = Join-Path $LogDirectory ('activation-{0:yyyy-MM-dd}.log' -f (Get-Date))

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-ProviderStatePath {
    param([Parameter(Mandatory)][string]$Provider)

    return Join-Path $StateDirectory ('{0}-weekly-block.json' -f $Provider.ToLowerInvariant())
}

function Get-WeeklyBlockState {
    param([Parameter(Mandatory)][string]$Provider)

    $statePath = Get-ProviderStatePath -Provider $Provider
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($state.status -ne 'WeeklyQuotaExhausted' -or -not $state.blockedUntil) {
            throw 'State file does not contain a valid weekly quota block.'
        }
        $blockedUntil = [DateTimeOffset]::Parse(
            [string]$state.blockedUntil,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
        return [pscustomobject]@{
            Path         = $statePath
            BlockedUntil = $blockedUntil
            DetectedAt   = $state.detectedAt
        }
    }
    catch {
        Write-Log "Ignoring invalid quota state for ${Provider}: $($_.Exception.Message)"
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Set-WeeklyBlockState {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][DateTimeOffset]$BlockedUntil
    )

    $statePath = Get-ProviderStatePath -Provider $Provider
    $state = [ordered]@{
        version      = 1
        provider     = $Provider
        status       = 'WeeklyQuotaExhausted'
        detectedAt   = [DateTimeOffset]::Now.ToString('o')
        blockedUntil = $BlockedUntil.ToUniversalTime().ToString('o')
    }
    $json = $state | ConvertTo-Json
    [IO.File]::WriteAllText($statePath, $json, [Text.UTF8Encoding]::new($false))
}

function Clear-WeeklyBlockState {
    param([Parameter(Mandatory)][string]$Provider)

    $statePath = Get-ProviderStatePath -Provider $Provider
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        Remove-Item -LiteralPath $statePath -Force
    }
}

function Find-QuotaResetTime {
    param([Parameter(Mandatory)][string]$Text)

    $isoMatch = [regex]::Match(
        $Text,
        '(?<!\d)(?<value>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($isoMatch.Success) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse(
                $isoMatch.Groups['value'].Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$parsed
            )) {
            return $parsed
        }
    }

    $epochMatch = [regex]::Match(
        $Text,
        '(?i)["'']?(?:reset_at|reset_time|resets_at)["'']?\s*[:=]\s*["'']?(?<value>\d{10,13})'
    )
    if ($epochMatch.Success) {
        $epoch = [long]$epochMatch.Groups['value'].Value
        if ($epochMatch.Groups['value'].Value.Length -eq 13) {
            return [DateTimeOffset]::FromUnixTimeMilliseconds($epoch)
        }
        return [DateTimeOffset]::FromUnixTimeSeconds($epoch)
    }

    $humanMatch = [regex]::Match(
        $Text,
        '(?im)\breset(?:s|ting)?(?:\s+at|\s+on|_at|_time)\s*[:=]?\s*(?<value>[^\r\n;}]+)'
    )
    if ($humanMatch.Success) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse(
                $humanMatch.Groups['value'].Value.Trim(),
                [Globalization.CultureInfo]::CurrentCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$parsed
            )) {
            return $parsed
        }
    }

    return $null
}

function Get-WeeklyQuotaStatus {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Output,
        [int]$ExitCode
    )

    $text = ($Output | ForEach-Object { [string]$_ }) -join "`n"
    $quotaFailure = $text -match '(?is)\b(quota|usage|rate\s*limit|limit)\b.{0,160}\b(exhausted|exceeded|reached|used\s*up|try\s*again|reset)' -or
        $text -match '(?is)\b(hit|reached|exceeded)\b.{0,80}\b(quota|usage|rate\s*limit|limit)\b'
    if (-not $quotaFailure -and $ExitCode -eq 0) {
        return [pscustomobject]@{ IsWeekly = $false; ResetAt = $null }
    }

    $resetAt = Find-QuotaResetTime -Text $text
    $explicitWeekly = $text -match '(?is)\b(weekly|week)\b.{0,120}\b(quota|usage|limit|reset)' -or
        $text -match '(?is)\b(quota|usage|limit|reset)\b.{0,120}\b(weekly|week)\b'
    $longCooldown = $null -ne $resetAt -and $resetAt -gt [DateTimeOffset]::Now.AddHours(6)

    return [pscustomobject]@{
        IsWeekly = $quotaFailure -and ($explicitWeekly -or $longCooldown)
        ResetAt  = $resetAt
    }
}

function Get-ActivationArguments {
    param([Parameter(Mandatory)][string]$Provider)

    $prompt = 'Reply only OK. Do not inspect files, use tools, execute commands, or modify anything.'
    switch ($Provider) {
        'Codex' {
            $arguments = @(
                'exec',
                '--skip-git-repo-check',
                '--ephemeral',
                '--ignore-user-config',
                '--ignore-rules',
                '--sandbox', 'read-only',
                '--config', 'model_reasoning_effort="low"'
            )
            if ($CodexModel) {
                $arguments += @('--model', $CodexModel)
            }
            $arguments += $prompt
            return $arguments
        }
        'Claude' {
            $arguments = @(
                '--print',
                '--output-format', 'json',
                '--restricted',
                '--safe-mode',
                '--strict-mcp-config',
                '--no-session-persistence',
                '--disable-slash-commands',
                '--tools', '',
                '--permission-mode', 'plan',
                '--permission-prompts', 'none',
                '--max-budget-usd', '0.10'
            )
            if ($ClaudeModel) {
                $arguments += @('--model', $ClaudeModel)
            }
            $arguments += $prompt
            return $arguments
        }
        'Antigravity' {
            $arguments = @(
                '--output-format', 'json',
                '--sandbox',
                '--disable-slash-commands',
                '--effort', 'low',
                '--print-timeout', '2m'
            )
            if ($AntigravityModel) {
                $arguments += @('--model', $AntigravityModel)
            }
            $arguments += "--print=$prompt"
            return $arguments
        }
    }
}

function Format-CommandPreview {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments
    )

    $quotedArguments = $Arguments | ForEach-Object {
        if ($_ -eq '') {
            '""'
        }
        elseif ($_ -match '[\s"]') {
            '"{0}"' -f $_.Replace('"', '\"')
        }
        else {
            $_
        }
    }
    return '"{0}" {1}' -f $Executable, ($quotedArguments -join ' ')
}

function Test-TaskWake {
    param(
        [int]$Minutes,
        [string]$ExpectedTaskName
    )

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Power-Troubleshooter'
            Id           = 1
            StartTime    = (Get-Date).AddMinutes(-$Minutes)
        } -MaxEvents 10 -ErrorAction Stop

        foreach ($event in $events) {
            $eventText = $event.Message
            try {
                $eventXml = [xml]$event.ToXml()
                $wakeSource = $eventXml.Event.EventData.Data |
                    Where-Object { $_.Name -eq 'WakeSourceText' } |
                    Select-Object -ExpandProperty '#text' -ErrorAction SilentlyContinue
                $eventText = "$eventText`n$wakeSource"
            }
            catch {
                # The localized event message is still useful when XML parsing fails.
            }

            $taskPattern = '\\{0}(?=[''"“”]|$)' -f [regex]::Escape($ExpectedTaskName)
            if ($eventText -match $taskPattern) {
                return $true
            }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -like '*NoMatchingEventsFound*') {
            Write-Log "No wake events were found in the last $Minutes minute(s)."
        }
        else {
            Write-Log ("Unable to inspect recent wake events: " + $_.Exception.Message)
        }
    }
    return $false
}

if (-not ('AIQuotaUserIdle' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AIQuotaUserIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    static extern uint GetTickCount();

    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        return unchecked(GetTickCount() - lii.dwTime);
    }
}
"@
}

function Start-BackgroundSleep {
    param(
        [int]$MinimumIdleMinutes,
        [string]$HelperLogPath
    )

    $pwshPath = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $encodedLogPath = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($HelperLogPath))
    $helperScript = @'
Start-Sleep -Seconds 3
$logPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__LOG_PATH__'))
function Write-HelperLog([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AIQuotaSleepHelper {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")]
    static extern uint GetTickCount();
    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        return unchecked(GetTickCount() - lii.dwTime);
    }
}
"@
$idleMinutes = [Math]::Round([AIQuotaSleepHelper]::GetIdleMilliseconds() / 60000.0, 1)
if ($idleMinutes -lt __IDLE_MINUTES__) {
    Write-HelperLog "Background sleep cancelled because recent user activity was detected ($idleMinutes minute(s) idle)."
    exit 0
}
Write-HelperLog 'Background sleep helper is suspending the computer.'
if (-not [AIQuotaSleepHelper]::SetSuspendState($false, $false, $false)) {
    Write-HelperLog 'ERROR: Windows rejected the suspend request.'
    exit 1
}
'@
    $helperScript = $helperScript.Replace('__LOG_PATH__', $encodedLogPath)
    $helperScript = $helperScript.Replace('__IDLE_MINUTES__', [string]$MinimumIdleMinutes)
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($helperScript))

    Start-Process `
        -FilePath $pwshPath `
        -ArgumentList '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand `
        -WindowStyle Hidden | Out-Null
}

$scriptExitCode = 0
$wokeForThisTask = $false
if (-not $NoSleep -and -not $DryRun) {
    $wokeForThisTask = Test-TaskWake -Minutes $RecentWakeMinutes -ExpectedTaskName $TaskName
}
Write-Log "Activation started. AI: $($providers -join ', '). Wake attributed to this task: $wokeForThisTask."

try {
    $providersToRun = @()
    foreach ($provider in $providers) {
        if (-not $DryRun) {
            $weeklyBlock = Get-WeeklyBlockState -Provider $provider
            if ($null -ne $weeklyBlock) {
                if ($weeklyBlock.BlockedUntil -gt [DateTimeOffset]::Now) {
                    Write-Log "$provider weekly quota is exhausted; skipping requests until $($weeklyBlock.BlockedUntil.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz'))."
                    continue
                }
                Write-Log "$provider weekly quota cooldown has expired; retrying on this scheduled run."
                Clear-WeeklyBlockState -Provider $provider
            }
        }
        $providersToRun += $provider
    }

    if ($providersToRun.Count -gt 0 -and -not $DryRun -and $NetworkWaitSeconds -gt 0) {
        Write-Log "Waiting $NetworkWaitSeconds second(s) for network and services."
        Start-Sleep -Seconds $NetworkWaitSeconds
    }

    foreach ($provider in $providersToRun) {
        $executable = $resolvedExecutables[$provider]
        $arguments = @(Get-ActivationArguments -Provider $provider)
        Write-Log "$provider executable: $executable"

        if ($DryRun) {
            Write-Log ("DRY RUN: " + (Format-CommandPreview -Executable $executable -Arguments $arguments))
            continue
        }

        try {
            Write-Log "Launching $provider activation request."
            $output = $null | & $executable @arguments 2>&1
            $providerExitCode = $LASTEXITCODE
            foreach ($line in $output) {
                Write-Log ("${provider}: " + [string]$line)
            }
            Write-Log "$provider exit code: $providerExitCode"

            $quotaStatus = Get-WeeklyQuotaStatus -Output @($output) -ExitCode $providerExitCode
            if ($quotaStatus.IsWeekly) {
                $scriptExitCode = 1
                if ($null -ne $quotaStatus.ResetAt -and $quotaStatus.ResetAt -gt [DateTimeOffset]::Now) {
                    Set-WeeklyBlockState -Provider $provider -BlockedUntil $quotaStatus.ResetAt
                    Write-Log "WEEKLY QUOTA [$provider]: pausing activation attempts until $($quotaStatus.ResetAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz'))."
                }
                else {
                    Write-Log "WEEKLY QUOTA [$provider]: no usable reset time was returned; the next normal schedule will make one fallback attempt."
                }
                Write-Log "WARNING [$provider]: account-level credits or overage settings can turn quota failures into paid usage; disable paid fallback if that is not intended."
                continue
            }

            if ($providerExitCode -ne 0) {
                throw "$provider activation request failed with exit code $providerExitCode."
            }
            Clear-WeeklyBlockState -Provider $provider
        }
        catch {
            $scriptExitCode = 1
            Write-Log ("ERROR [$provider]: " + $_.Exception.Message)
        }
    }

    if ($providersToRun.Count -gt 0 -and -not $DryRun -and $PostWaitSeconds -gt 0) {
        Start-Sleep -Seconds $PostWaitSeconds
    }
}
catch {
    $scriptExitCode = 1
    Write-Log ("ERROR: " + $_.Exception.Message)
}
finally {
    if ($DryRun -or $NoSleep) {
        Write-Log 'Automatic sleep is disabled for this run.'
    }
    else {
        $idleMinutes = [Math]::Round([AIQuotaUserIdle]::GetIdleMilliseconds() / 60000.0, 1)
        Write-Log "User idle time: $idleMinutes minute(s)."

        if ($wokeForThisTask -and $idleMinutes -ge $SleepIfIdleMinutes) {
            try {
                Write-Log 'This task woke the computer and the user is idle; queuing background sleep.'
                Start-BackgroundSleep -MinimumIdleMinutes $SleepIfIdleMinutes -HelperLogPath $logPath
            }
            catch {
                $scriptExitCode = 1
                Write-Log ("ERROR: Unable to start background sleep helper: " + $_.Exception.Message)
            }
        }
        else {
            Write-Log 'Leaving the computer awake.'
        }
    }
}

exit $scriptExitCode
