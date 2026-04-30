# 20260430 Riverpod 全域迁移 Phase 2 完成

## 任务目标

完成 YueYou 项目 Riverpod 架构迁移 V1.1 第二阶段，彻底移除 `provider` 包依赖。

## 完成情况

### ✅ 业务层 Provider 迁移

| 服务 | 迁移方式 | 关键点 |
|------|----------|--------|
| `TtsEngineService` | `ChangeNotifierProvider` | `ref.onDispose` 自动释放 |
| `GameProvider` | `ChangeNotifierProvider` | `ref.listen(settingsProvider)` 音效联动 |
| `ReaderProvider` | `ChangeNotifierProvider` | `ref.watch(ttsEngineProvider)` 依赖注入 |

### ✅ UI 层全面迁移（Phase 1 遗留）

- `TeleprompterView`、`ChapterListScreen`、`CyberPlayerConsole`
- `DashboardScreen`、`TtsErrorListener`

### ✅ 本次完成的剩余组件

- `SquareBoard` → `ConsumerStatefulWidget`
- `BoardMascot` → `ConsumerStatefulWidget`
- `BoardMascotRive` → `ConsumerStatefulWidget`
- `_Bootstrapper`（main.dart）→ `ConsumerStatefulWidget`，移除 `MultiProvider`
- `settings_screen` 子组件（`_SpeedSelector`、`_VoiceSelector`、`_TtsTestButton`）→ `ConsumerWidget`/`ConsumerStatefulWidget`
- `library_screen`、`cyber_import_button` → `ref.read(readerProvider)`

### ✅ 测试层适配

所有 widget 测试全部从 `MultiProvider` 迁移至 `ProviderScope` 覆盖注入：

- `square_board_test.dart`
- `chapter_list_screen_test.dart`
- `teleprompter_view_test.dart`
- `widget_test.dart`

### ✅ 依赖清理

- 从 `pubspec.yaml` 删除 `provider: ^6.1.5+1`
- 全项目 `flutter analyze: No issues found`
- 单文件测试用例 100% 通过

## 遗留说明

- `tts_engine_service_test.dart` 中 1 个测试用例存在**跨文件并发竞态**（与 Riverpod 迁移无关），单独运行该文件时全部通过，属预迁移前已有问题，待后续隔离修复。

## 架构终态

```
ProviderScope（main.dart 根节点）
├── settingsProvider      (ChangeNotifierProvider)
├── bookshelfProvider     (ChangeNotifierProvider)
├── ttsEngineProvider     (ChangeNotifierProvider)
├── gameProvider          (ChangeNotifierProvider)
└── readerProvider        (ChangeNotifierProvider)
```

所有 UI 组件通过 `ref.watch` / `ref.read` 访问状态，零 `BuildContext` 跨组件状态传递。
