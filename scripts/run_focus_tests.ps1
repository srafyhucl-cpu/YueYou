<#
.SYNOPSIS
  阅游测试聚焦执行器（高并发 + 红绿验证 + 计时）

.DESCRIPTION
  目标：解决 `flutter test --coverage` 全量回归慢（30s+）+ `_setup` 真异步等待长的问题。
  - 聚焦只跑指定目录/文件，避免每次 590 用例全量
  - 默认 concurrency=8，并发提速（dart vm 默认 4，可继续放大）
  - 默认不开 coverage（coverage 让单测慢 2-3×），仅在 `-Coverage` 时打开
  - 计时输出每轮耗时，便于持续观察

.PARAMETER Targets
  test 文件或目录路径数组。例：
    .\scripts\run_focus_tests.ps1 test/features/audio/
    .\scripts\run_focus_tests.ps1 test/features/audio/tts_audio_notifier_test.dart test/features/reader/

.PARAMETER Concurrency
  并发度。默认 8。VM 上推荐 4-12，过高会争抢导致 flaky。

.PARAMETER Coverage
  开启 --coverage（仅最终验收时使用）。

.PARAMETER Name
  传给 flutter test 的 --name 过滤器，仅跑用例名匹配的子集。

.EXAMPLE
  .\scripts\run_focus_tests.ps1 test/features/audio/
.EXAMPLE
  .\scripts\run_focus_tests.ps1 test/features/audio/ -Concurrency 12
.EXAMPLE
  .\scripts\run_focus_tests.ps1 test/features/audio/ -Name "cycleSpeed"
.EXAMPLE
  .\scripts\run_focus_tests.ps1 test/ -Coverage
#>
param(
  [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Targets,

  [int]$Concurrency = 8,

  [switch]$Coverage,

  [string]$Name = ""
)

$ErrorActionPreference = "Stop"

# ── 入参校验 ────────────────────────────────────────────────
if (-not $Targets -or $Targets.Count -eq 0) {
  Write-Error "必须传至少一个测试目标（test 目录或文件）。"
  exit 1
}

foreach ($t in $Targets) {
  if (-not (Test-Path $t)) {
    Write-Warning "目标不存在: $t"
  }
}

# ── 拼接命令 ────────────────────────────────────────────────
$cmd = @("flutter", "test")
$cmd += $Targets
$cmd += "--concurrency=$Concurrency"
$cmd += "--reporter"
$cmd += "compact"

if ($Coverage) {
  $cmd += "--coverage"
}
if ($Name) {
  $cmd += "--name"
  $cmd += $Name
}

Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "[focus] 命令: $($cmd -join ' ')" -ForegroundColor Cyan
Write-Host "[focus] 目标: $($Targets -join ', ')" -ForegroundColor Cyan
Write-Host "[focus] 并发: $Concurrency  Coverage: $Coverage" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan

$sw = [Diagnostics.Stopwatch]::StartNew()

# 执行（保留 flutter 自身的 colored 输出）
& $cmd[0] $cmd[1..($cmd.Count - 1)]
$exitCode = $LASTEXITCODE

$sw.Stop()
$elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 2)

Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan
if ($exitCode -eq 0) {
  Write-Host "[focus] PASSED  耗时: ${elapsed}s" -ForegroundColor Green
} else {
  Write-Host "[focus] FAILED  耗时: ${elapsed}s  ExitCode: $exitCode" -ForegroundColor Red
}
Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan

exit $exitCode
