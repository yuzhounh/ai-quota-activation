param(
    [ValidateSet('FiveHour', 'Weekly')]
    [string]$Cycle = 'FiveHour',
    [string]$AI = 'Codex,Claude,Antigravity',
    [string[]]$Times = @('05:00', '10:03', '15:06', '20:09'),
    [DayOfWeek]$DayOfWeek = [DayOfWeek]::Friday,
    [string]$WeeklyTime = '08:00',
    [string]$TaskName,
    [string]$CodexPath,
    [string]$ClaudePath,
    [string]$AntigravityPath,
    [string]$CodexModel = 'gpt-6-luna',
    [string]$ClaudeModel = 'haiku',
    [string]$AntigravityModel,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'This installer currently supports Windows only.'
}
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Run this installer with PowerShell 7.4 or later (pwsh.exe).'
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
    AI        = $AI
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
if ($CheckOnly) {
    exit 0
}

if (-not $TaskName) {
    $TaskName = if ($Cycle -eq 'FiveHour') {
        'AI Quota 5h Activation'
    }
    else {
        'AI Quota Weekly Activation'
    }
}

$parsedTimes = @()
if ($Cycle -eq 'FiveHour') {
    foreach ($timeText in $Times) {
        try {
            $parsedTimes += [datetime]::ParseExact($timeText, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            throw "Invalid time '$timeText'. Use 24-hour HH:mm format, for example 05:00."
        }
    }
    if ($parsedTimes.Count -eq 0) {
        throw 'FiveHour scheduling requires at least one value in -Times.'
    }
}
else {
    try {
        $parsedWeeklyTime = [datetime]::ParseExact(
            $WeeklyTime,
            'HH:mm',
            [Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        throw "Invalid weekly time '$WeeklyTime'. Use 24-hour HH:mm format, for example 08:00."
    }
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'AIQuotaActivation'
$workDirectory = Join-Path $installDirectory 'work'
$logSubdirectory = if ($Cycle -eq 'FiveHour') { 'logs\five-hour' } else { 'logs\weekly' }
$logDirectory = Join-Path $installDirectory $logSubdirectory
New-Item -ItemType Directory -Force -Path $installDirectory, $workDirectory, $logDirectory | Out-Null

$targetScript = Join-Path $installDirectory 'ai-quota-activate.ps1'
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

function ConvertTo-TaskArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    return '"{0}"' -f $Value.Replace('"', '\"')
}

$taskArgumentParts = @(
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', (ConvertTo-TaskArgument $targetScript),
    '-AI', (ConvertTo-TaskArgument $AI),
    '-LogDirectory', (ConvertTo-TaskArgument $logDirectory),
    '-TaskName', (ConvertTo-TaskArgument $TaskName),
    '-CodexModel', (ConvertTo-TaskArgument $CodexModel),
    '-ClaudeModel', (ConvertTo-TaskArgument $ClaudeModel)
)
foreach ($entry in @(
    @{ Name = '-CodexPath'; Value = $CodexPath },
    @{ Name = '-ClaudePath'; Value = $ClaudePath },
    @{ Name = '-AntigravityPath'; Value = $AntigravityPath },
    @{ Name = '-AntigravityModel'; Value = $AntigravityModel }
)) {
    if ($entry.Value) {
        $taskArgumentParts += $entry.Name
        $taskArgumentParts += ConvertTo-TaskArgument $entry.Value
    }
}
$taskArguments = $taskArgumentParts -join ' '

$action = New-ScheduledTaskAction `
    -Execute $powerShellPath `
    -Argument $taskArguments `
    -WorkingDirectory $workDirectory

if ($Cycle -eq 'FiveHour') {
    $triggers = @($parsedTimes | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })
    $scheduleSummary = 'Daily at {0}' -f ($Times -join ', ')
}
else {
    $triggers = @(
        New-ScheduledTaskTrigger `
            -Weekly `
            -WeeksInterval 1 `
            -DaysOfWeek $DayOfWeek `
            -At $parsedWeeklyTime
    )
    $scheduleSummary = "Every $DayOfWeek at $WeeklyTime"
}

$settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$description = "Wake if needed and send a minimal request to $AI for $Cycle quota activation. Return to sleep only when this task woke the PC and the user remains idle."

Write-Host ''
Write-Host "Registering '$TaskName' for user: $user"
Write-Host "AI: $AI" -ForegroundColor Cyan
Write-Host "Schedule: $scheduleSummary (local time)" -ForegroundColor Cyan
Write-Host 'Windows needs the account password, not the Windows Hello PIN.' -ForegroundColor Yellow
$securePassword = Read-Host 'Enter Windows account password' -AsSecureString

$passwordPointer = [IntPtr]::Zero
$plainPassword = $null
try {
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $triggers `
        -Settings $settings `
        -Description $description `
        -User $user `
        -Password $plainPassword `
        -Force | Out-Null
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $plainPassword = $null
    $securePassword = $null
}

Write-Host ''
Write-Host "Created or updated: $TaskName" -ForegroundColor Green
Write-Host "Schedule: $scheduleSummary" -ForegroundColor Green
Write-Host ''
Write-Host 'Next run:' -ForegroundColor Cyan
Get-ScheduledTaskInfo -TaskName $TaskName |
    Select-Object LastRunTime, NextRunTime, LastTaskResult |
    Format-List

Write-Host 'Wake timers:' -ForegroundColor Cyan
powercfg /waketimers

Write-Host ''
Write-Host "Installed engine: $targetScript"
Write-Host "Logs: $logDirectory"
