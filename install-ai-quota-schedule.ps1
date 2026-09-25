param(
    [string]$FiveHourAI = 'Claude,Antigravity',
    [string]$WeeklyOnlyAI = 'Codex',
    [string[]]$Times = @('05:00', '10:03', '15:06', '20:09'),
    [DayOfWeek]$DayOfWeek = [DayOfWeek]::Friday,
    [string]$WeeklyTime = '08:08',
    [string]$TaskNamePrefix = 'AI Quota',
    [string]$CodexPath,
    [string]$ClaudePath,
    [string]$AntigravityPath,
    [string]$CodexModel,
    [string]$ClaudeModel,
    [string]$AntigravityModel,
    [switch]$CheckOnly,
    [switch]$ShowVersion
)

$ErrorActionPreference = 'Stop'
$scriptVersion = '0.3'
$supportedProviders = @('Codex', 'Claude', 'Antigravity')

if ($ShowVersion) {
    Write-Output "AI Quota Schedule Installer $scriptVersion"
    exit 0
}
if (-not $IsWindows) {
    throw 'This installer currently supports Windows only.'
}
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Run this installer with PowerShell 7.4 or later (pwsh.exe).'
}

function ConvertTo-ProviderList {
    param(
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split '[,;\s]+' |
            Where-Object { $_ } |
            ForEach-Object {
                $candidate = $_.Trim()
                $match = $supportedProviders | Where-Object {
                    [string]::Equals($_, $candidate, [StringComparison]::OrdinalIgnoreCase)
                } | Select-Object -First 1
                if (-not $match) {
                    throw "Unsupported AI '$candidate' in -$ParameterName. Supported values: $($supportedProviders -join ', ')."
                }
                $match
            } |
            Select-Object -Unique
    )
}

$fiveHourProviders = @(ConvertTo-ProviderList -Value $FiveHourAI -ParameterName 'FiveHourAI')
$weeklyProviders = @(ConvertTo-ProviderList -Value $WeeklyOnlyAI -ParameterName 'WeeklyOnlyAI')
$overlap = @($fiveHourProviders | Where-Object { $weeklyProviders -contains $_ })
if ($overlap.Count -gt 0) {
    throw "An AI cannot use both schedules. Remove $($overlap -join ', ') from either -FiveHourAI or -WeeklyOnlyAI."
}
$allProviders = @($fiveHourProviders + $weeklyProviders | Select-Object -Unique)
if ($allProviders.Count -eq 0) {
    throw 'Assign at least one AI to -FiveHourAI or -WeeklyOnlyAI.'
}

$parsedTimes = @()
foreach ($timeText in $Times) {
    try {
        $parsedTimes += [datetime]::ParseExact($timeText, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "Invalid time '$timeText'. Use 24-hour HH:mm format, for example 05:00."
    }
}
if ($fiveHourProviders.Count -gt 0 -and $parsedTimes.Count -eq 0) {
    throw 'Five-hour scheduling requires at least one value in -Times.'
}
$weeklyFormats = @(
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm',
    'HH:mm',
    'H:mm'
)
$parsedWeeklyTime = [datetime]::MinValue
$matchedWeeklyFormat = $null
foreach ($formatCandidate in $weeklyFormats) {
    if ([datetime]::TryParseExact(
            $WeeklyTime,
            $formatCandidate,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsedWeeklyTime
        )) {
        $matchedWeeklyFormat = $formatCandidate
        break
    }
}
if ($null -eq $matchedWeeklyFormat) {
    throw "Invalid weekly time '$WeeklyTime'. Use 'HH:mm' (e.g. 08:08) or 'yyyy-MM-dd HH:mm' (e.g. 2026-10-02 08:08)."
}

if ($matchedWeeklyFormat -like 'yyyy*') {
    $DayOfWeek = $parsedWeeklyTime.DayOfWeek
}
else {
    $targetDate = [datetime]::Today
    while ($targetDate.DayOfWeek -ne $DayOfWeek -or $targetDate.Add($parsedWeeklyTime.TimeOfDay) -le [datetime]::Now) {
        $targetDate = $targetDate.AddDays(1)
    }
    $parsedWeeklyTime = $targetDate.Add($parsedWeeklyTime.TimeOfDay)
}

$pwshCommand = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $pwshCommand) {
    throw 'PowerShell 7 (pwsh.exe) was not found in PATH. Install PowerShell 7.4 or later first.'
}
$powerShellPath = $pwshCommand.Source

$sourceScript = Join-Path $PSScriptRoot 'ai-quota-activate.ps1'
if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "Missing activation engine: $sourceScript"
}

$checkParameters = @{
    AI        = ($allProviders -join ',')
    CheckOnly = $true
}
foreach ($entry in @(
    @{ Name = 'CodexPath'; Value = $CodexPath },
    @{ Name = 'ClaudePath'; Value = $ClaudePath },
    @{ Name = 'AntigravityPath'; Value = $AntigravityPath }
)) {
    if ($entry.Value) {
        $checkParameters[$entry.Name] = $entry.Value
    }
}

Write-Host ''
Write-Host 'Checking selected AI CLIs before scheduling...' -ForegroundColor Cyan
& $sourceScript @checkParameters
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host 'Quota policy:' -ForegroundColor Cyan
$policyRows = foreach ($provider in $allProviders) {
    $policy = if ($fiveHourProviders -contains $provider) { 'Five-hour (weekly task omitted)' } else { 'Weekly only' }
    [pscustomobject]@{ AI = $provider; Policy = $policy }
}
$policyRows | Format-Table -AutoSize
if ($CheckOnly) {
    exit 0
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'AIQuotaActivation'
$workDirectory = Join-Path $installDirectory 'work'
$stateDirectory = Join-Path $installDirectory 'state'
New-Item -ItemType Directory -Force -Path $installDirectory, $workDirectory, $stateDirectory | Out-Null
$targetScript = Join-Path $installDirectory 'ai-quota-activate.ps1'
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

function ConvertTo-TaskArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    return '"{0}"' -f $Value.Replace('"', '\"')
}

function New-ActivationTaskDefinition {
    param(
        [Parameter(Mandatory)][ValidateSet('FiveHour', 'WeeklyOnly')][string]$Policy,
        [Parameter(Mandatory)][string[]]$Providers
    )

    if ($Policy -eq 'FiveHour') {
        $taskName = "$TaskNamePrefix 5h Activation"
        $logDirectory = Join-Path $installDirectory 'logs\five-hour'
        $triggers = @($parsedTimes | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })
        $scheduleSummary = 'Daily at {0}' -f ($Times -join ', ')
    }
    else {
        $taskName = "$TaskNamePrefix Weekly Activation"
        $logDirectory = Join-Path $installDirectory 'logs\weekly'
        $triggers = @(
            New-ScheduledTaskTrigger `
                -Weekly `
                -WeeksInterval 1 `
                -DaysOfWeek $DayOfWeek `
                -At $parsedWeeklyTime
        )
        $scheduleSummary = "Every $DayOfWeek at {0:HH:mm} (starts {1:yyyy-MM-dd})" -f $parsedWeeklyTime, $parsedWeeklyTime
    }
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

    $taskArgumentParts = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', (ConvertTo-TaskArgument $targetScript),
        '-AI', (ConvertTo-TaskArgument ($Providers -join ',')),
        '-LogDirectory', (ConvertTo-TaskArgument $logDirectory),
        '-StateDirectory', (ConvertTo-TaskArgument $stateDirectory),
        '-TaskName', (ConvertTo-TaskArgument $taskName)
    )
    foreach ($entry in @(
        @{ Name = '-CodexPath'; Value = $CodexPath },
        @{ Name = '-ClaudePath'; Value = $ClaudePath },
        @{ Name = '-AntigravityPath'; Value = $AntigravityPath },
        @{ Name = '-CodexModel'; Value = $CodexModel },
        @{ Name = '-ClaudeModel'; Value = $ClaudeModel },
        @{ Name = '-AntigravityModel'; Value = $AntigravityModel }
    )) {
        if ($entry.Value) {
            $taskArgumentParts += $entry.Name
            $taskArgumentParts += ConvertTo-TaskArgument $entry.Value
        }
    }

    $action = New-ScheduledTaskAction `
        -Execute $powerShellPath `
        -Argument ($taskArgumentParts -join ' ') `
        -WorkingDirectory $workDirectory

    return [pscustomobject]@{
        Policy          = $Policy
        Providers       = $Providers
        TaskName        = $taskName
        LogDirectory    = $logDirectory
        Triggers        = $triggers
        Action          = $action
        ScheduleSummary = $scheduleSummary
    }
}

$taskDefinitions = @()
if ($fiveHourProviders.Count -gt 0) {
    $taskDefinitions += New-ActivationTaskDefinition -Policy FiveHour -Providers $fiveHourProviders
}
if ($weeklyProviders.Count -gt 0) {
    $taskDefinitions += New-ActivationTaskDefinition -Policy WeeklyOnly -Providers $weeklyProviders
}

$settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host ''
Write-Host "Registering $($taskDefinitions.Count) activation task(s) for user: $user"
foreach ($definition in $taskDefinitions) {
    Write-Host "$($definition.TaskName): $($definition.Providers -join ', ') — $($definition.ScheduleSummary)" -ForegroundColor Cyan
}
Write-Host 'Windows needs the account password, not the Windows Hello PIN.' -ForegroundColor Yellow
$securePassword = Read-Host 'Enter Windows account password' -AsSecureString

$passwordPointer = [IntPtr]::Zero
$plainPassword = $null
try {
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    foreach ($definition in $taskDefinitions) {
        $description = "Send a minimal request to $($definition.Providers -join ', ') using the $($definition.Policy) quota policy, with weekly quota cooldown awareness."
        Register-ScheduledTask `
            -TaskName $definition.TaskName `
            -Action $definition.Action `
            -Trigger $definition.Triggers `
            -Settings $settings `
            -Description $description `
            -User $user `
            -Password $plainPassword `
            -Force | Out-Null
    }
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $plainPassword = $null
    $securePassword = $null
}

foreach ($inactiveTaskName in @(
    if ($fiveHourProviders.Count -eq 0) { "$TaskNamePrefix 5h Activation" }
    if ($weeklyProviders.Count -eq 0) { "$TaskNamePrefix Weekly Activation" }
)) {
    $inactiveTask = Get-ScheduledTask -TaskName $inactiveTaskName -ErrorAction SilentlyContinue
    if ($null -ne $inactiveTask -and $inactiveTask.State -ne 'Disabled') {
        Disable-ScheduledTask -InputObject $inactiveTask | Out-Null
        Write-Host "Disabled task excluded by the current quota policy: $inactiveTaskName" -ForegroundColor Yellow
    }
}

Write-Host ''
foreach ($definition in $taskDefinitions) {
    Write-Host "Created or updated: $($definition.TaskName)" -ForegroundColor Green
    Write-Host "AI: $($definition.Providers -join ', ')"
    Write-Host "Schedule: $($definition.ScheduleSummary)"
    Get-ScheduledTaskInfo -TaskName $definition.TaskName |
        Select-Object LastRunTime, NextRunTime, LastTaskResult |
        Format-List
}

Write-Host 'Wake timers:' -ForegroundColor Cyan
powercfg /waketimers
Write-Host ''
Write-Host "Installed engine: $targetScript"
Write-Host "Logs: $(Join-Path $installDirectory 'logs')"
Write-Host "Quota state: $stateDirectory"
