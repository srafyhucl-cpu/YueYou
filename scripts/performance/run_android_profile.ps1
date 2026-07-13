[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [Parameter(Mandatory = $true)]
    [string]$DeviceLabel,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 240)]
    [double]$RefreshRateHz,

    [ValidateRange(1, 20)]
    [int]$ColdRuns = 10,

    [string]$Scenario = 'collector_smoke',

    [string]$PackageId = 'cn.hclstudio.yueyou',

    [string]$OutputRoot = 'build/performance'
)

$ErrorActionPreference = 'Stop'

function Invoke-AdbText {
    param([string[]]$Arguments)

    $output = & adb -s $DeviceId @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb 命令失败：$($Arguments -join ' ')"
    }
    return ($output -join "`n")
}

function Get-IntegerFromText {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        return $null
    }
    return [int64]$match.Groups[1].Value
}

function Get-PssMb {
    param([string]$Text)

    $kilobytes = Get-IntegerFromText -Text $Text -Pattern 'TOTAL(?:\s+PSS)?\s*:?\s+(\d+)'
    if ($null -eq $kilobytes) {
        return $null
    }
    return [math]::Round($kilobytes / 1024, 2)
}

function Get-GfxSummary {
    param([string]$Text)

    $totalFrames = Get-IntegerFromText -Text $Text -Pattern 'Total frames rendered:\s+(\d+)'
    $jankyFrames = Get-IntegerFromText -Text $Text -Pattern 'Janky frames:\s+(\d+)'
    $jankyRate = $null
    if ($null -ne $totalFrames -and $totalFrames -gt 0 -and $null -ne $jankyFrames) {
        $jankyRate = [math]::Round($jankyFrames / $totalFrames, 6)
    }
    return [ordered]@{
        totalFrames = $totalFrames
        jankyFrames = $jankyFrames
        jankyFrameRate = $jankyRate
    }
}

function Read-DriverReport {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Flutter 驱动未生成报告：$Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($raw -is [array]) {
        $report = @($raw | Where-Object { $_.schemaVersion -eq 1 }) | Select-Object -Last 1
    } else {
        $report = $raw
    }
    if ($null -eq $report -or $null -eq $report.frames) {
        throw "报告缺少 schemaVersion=1 或 frames：$Path"
    }
    return $report
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb not found; configure the Android SDK platform tools first.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter not found; configure the Flutter SDK first.'
}

$deviceState = Invoke-AdbText -Arguments @('get-state')
if ($deviceState.Trim() -ne 'device') {
    throw "设备未处于可测试状态：$DeviceLabel"
}

$commit = (git rev-parse HEAD).Trim()
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$apiLevel = Get-IntegerFromText -Text (Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.build.version.sdk')) -Pattern '(\d+)'
$memInfo = Invoke-AdbText -Arguments @('shell', 'cat', '/proc/meminfo')
$totalRamKb = Get-IntegerFromText -Text $memInfo -Pattern 'MemTotal:\s+(\d+)'
$totalRamMb = if ($null -eq $totalRamKb) { $null } else { [math]::Round($totalRamKb / 1024, 2) }
$runs = [System.Collections.Generic.List[object]]::new()

for ($index = 1; $index -le $ColdRuns; $index++) {
    $runName = 'run-{0:d2}' -f $index
    $runDirectory = Join-Path $runRoot $runName
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $env:PERF_OUTPUT_DIR = $runDirectory

    Invoke-AdbText -Arguments @('shell', 'am', 'force-stop', $PackageId) | Out-Null
    $startPssMb = Get-PssMb -Text (Invoke-AdbText -Arguments @('shell', 'dumpsys', 'meminfo', $PackageId))

    $driverArguments = @(
        'drive',
        '--profile',
        '--driver=test_driver/performance_driver.dart',
        '--target=integration_test/performance/performance_baseline_test.dart',
        '-d', $DeviceId,
        "--dart-define=PERF_COMMIT=$commit",
        "--dart-define=PERF_DEVICE_CLASS=$DeviceLabel",
        '--dart-define=PERF_BUILD_MODE=profile',
        "--dart-define=PERF_REFRESH_RATE_HZ=$RefreshRateHz"
    )
    & flutter @driverArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Profile 第 $index 轮失败：$DeviceLabel"
    }

    $endPssMb = Get-PssMb -Text (Invoke-AdbText -Arguments @('shell', 'dumpsys', 'meminfo', $PackageId))
    $gfxText = Invoke-AdbText -Arguments @('shell', 'dumpsys', 'gfxinfo', $PackageId)
    $driverReport = Read-DriverReport -Path (Join-Path $runDirectory 'summary.json')
    $observedPss = @($startPssMb, $endPssMb) |
        Where-Object { $null -ne $_ } |
        ForEach-Object { [double]$_ }
    $maxObservedPssMb = if ($observedPss.Count -eq 0) {
        $null
    } else {
        ($observedPss | Measure-Object -Maximum).Maximum
    }
    $runs.Add([ordered]@{
        run = $index
        frames = $driverReport.frames
        memory = [ordered]@{
            startPssMb = $startPssMb
            endPssMb = $endPssMb
            maxObservedPssMb = $maxObservedPssMb
        }
        graphics = Get-GfxSummary -Text $gfxText
    })
}

$manifest = [ordered]@{
    schemaVersion = 1
    commit = $commit
    scenario = $Scenario
    deviceClass = $DeviceLabel
    buildMode = 'profile'
    refreshRateHz = $RefreshRateHz
    device = [ordered]@{
        androidApi = $apiLevel
        totalRamMb = $totalRamMb
    }
    runs = $runs
    privacy = [ordered]@{
        containsDeviceId = $false
        containsUserContent = $false
    }
}

$manifestPath = Join-Path $runRoot 'summary.json'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Remove-Item Env:PERF_OUTPUT_DIR -ErrorAction SilentlyContinue
Write-Output "PERF-0-B 已生成脱敏基线：$manifestPath"
