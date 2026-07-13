# 阅游性能基线证据

## 1. 当前范围

本目录定义 `PERF-0` 性能证据的固定口径。当前 `PERF-0-A` 只完成帧统计、
Integration Test 烟测和 host driver，不包含 Android 真机 G0 签署。

`collector_smoke` 只验证采集链可工作，不能作为应用冷启动、2048、提词器、
TTS 或大书导入的性能结论。

## 2. 固定统计规则

- build 与 raster 分别统计 P50、P95 和 P99。
- 百分位使用 nearest-rank，禁止由脚本自行更换算法。
- 慢帧定义为 build 或 raster 任一阶段严格超过当前刷新率预算。
- 60Hz 预算为 16667 微秒，120Hz 预算为 8333 微秒。
- 没有样本时百分位必须为 `null`，不得写成实测 0。

## 3. 本地验证

```powershell
$env:PUB_CACHE = 'D:\Work\PubCache'
flutter test --no-pub test/core/performance --concurrency=1
flutter analyze --no-pub
```

## 4. Android Profile 烟测

以下命令只验证采集与 JSON 输出链。设备 ID、设备档位和刷新率必须来自实际
测试设备，不得使用示例值签署 G0。

```powershell
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:PERF_OUTPUT_DIR = "build/performance/$runId"
$commit = git rev-parse HEAD

flutter drive --profile `
  --driver=test_driver/performance_driver.dart `
  --target=integration_test/performance/performance_baseline_test.dart `
  -d '<物理设备 ID>' `
  --dart-define=PERF_COMMIT=$commit `
  --dart-define=PERF_DEVICE_CLASS='<设备档位>' `
  --dart-define=PERF_BUILD_MODE=profile `
  --dart-define=PERF_REFRESH_RATE_HZ='<实际刷新率>'
```

输出文件为 `build/performance/<run-id>/summary.json`。`build/` 已被 Git 忽略，
原始 trace 和本机报告不得提交；后续只提交脱敏汇总。

## 5. 报告约束

报告 `schemaVersion` 当前为 1，至少包含：

- commit、场景、设备档位、构建模式和刷新率。
- build/raster 独立百分位、样本量、预算和慢帧率。
- 启动与内存字段；未采集时保持 `null`。

报告禁止包含：

- 设备序列号、用户姓名或账号标识。
- 书籍正文、标题、章节、阅读游标或 TTS 文本。
- Sentry DSN、服务器密钥、签名信息或本机绝对私有路径。

## 6. 后续 PERF-0-B

`PERF-0-B` 继续实现 PowerShell 真机循环、设备校验、meminfo/gfxinfo 汇总、
before/after 比较和两台物理 Android 的 G0 签署。在该切片完成前，任何性能
收益都只能标注为建议目标或待 Profile 验证。
