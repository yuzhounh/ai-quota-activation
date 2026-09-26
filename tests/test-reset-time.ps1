$ErrorActionPreference = 'Stop'

# Load only the parser function; do not execute the activation engine.
$engine = Join-Path (Split-Path -Parent $PSScriptRoot) 'ai-quota-activate.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($engine, [ref]$null, [ref]$null)
$function = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Find-QuotaResetTime'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

$expected = [DateTimeOffset]'2099-01-02T05:00:00+08:00'
$examples = @(
    '2026-09-26T00:00:00Z Weekly quota exhausted. Usage resets at 2099-01-02T05:00:00+08:00.',
    '{"timestamp":"2026-09-26T00:00:00Z","reset_at":"2099-01-02T05:00:00+08:00"}',
    ('{"timestamp":"2026-09-26T00:00:00Z","reset_time":' + $expected.ToUnixTimeSeconds() + '}'),
    ('{"resets_at":' + $expected.ToUnixTimeMilliseconds() + '}'),
    ('Usage resets on ' + $expected.ToString('r'))
)
foreach ($example in $examples) {
    $actual = Find-QuotaResetTime -Text $example
    if ($actual -ne $expected) {
        throw "Incorrect reset time for '$example': $actual"
    }
}
if ($null -ne (Find-QuotaResetTime -Text '2099-01-02T05:00:00+08:00 Weekly quota exhausted.')) {
    throw 'An unrelated timestamp must not be used as a quota reset time.'
}
Write-Host 'PASS: only reset times are parsed; ISO, Unix seconds/milliseconds and human-readable formats are supported.' -ForegroundColor Green
