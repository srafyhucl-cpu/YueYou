# 阅游 (YueYou) - 开发日志

## **2026-04-27**
- **迁移(Flutter 3.41 API)**: 完成了从 `MaterialState` 到 `WidgetState` 的全量底层迁移。
  - 全局替换 `MaterialStateProperty` -> `WidgetStateProperty`。
  - 重点加固了 `cyber_import_button.dart` 等自定义 UI 组件，消除了所有废弃 API 警告。
  - `flutter analyze` 达成 100% 零警告。
- **加固(全量测试通过)**: 修复了遗留的测试失败项，达成 67/67 测试用例全绿通过。
  - **TTS 引擎**: 引入了异步生命周期守卫（Disposed Check）与 1ms 调度缓冲，解决了时序竞态导致的测试不稳定性。
  - **业务逻辑**: 优化了 WakeLock 持有逻辑，支持在 buffering 状态下自动常亮，提升了阅读器在弱网环境下的体验。
  - **UI 组件**: 修复了 2048 棋盘手势冲突与提词器自动淡出计时器泄露问题。

---

## **2026-04-23**
- **迁移(Flutter 3.41 兼容性审计)**: 执行全库范围的 `MaterialState` API 审计，通过大规模替换 `WidgetStateProperty` 实现了与 Flutter 3.41 的完美对齐。
  - `flutter analyze` 输出全量零警告，完成零技术债务平滑过滤。

- **优化(Impeller 渲染性能)**: 针对 Impeller 引擎完成 `BackdropFilter` 渲染裁剪约束。
  - 在 `cyber_toast.dart` 与 `cyber_modal.dart` 中，将模糊滤镜与透明颜色图层嵌套分离，并确保内部图层的 `borderRadius` 严格对齐外部 `ClipRRect` 的 `CyberDimensions.radiusL` 约束，避免全屏重绘及边缘溢出引发的 GPU 功耗飙升。

---

## **2026-04-22**
- **重构(Dart 3 模式匹配)**: 全面引入 Dart 3.11 最新的穷尽式 Switch 表达式（Switch Expressions）与模式匹配语法：
  - 重构 `CyberToast` 中的 `_getBorderColor()` 方法，将传统的 `switch-case` 简化为单行表达式。
  - 重构 `TtsEngineService` 中的 `_setLastError()`，利用类型模式与关系模式（如 `>= 500`）替代冗长的 `if-else` 分支。
  - 提升了代码紧凑度与可读性，并获得编译期的穷尽性检查（Exhaustiveness checking）安全保障。

- **修正(Android 构建系统与 IDE 环境)**: 彻底解决了 IDE 中的 Java 17 环境缺失报错及 Gradle 构建链路漏洞。
  - **环境对齐**: 识别到系统 PATH 默认 JDK 为 1.8 导致现代 AGP 同步失败，已通过 `.vscode/settings.json` 及 `gradle.properties` 强制指定 `D:\Work\Android Studio\jbr` (JDK 21) 为工程构建环境。
  - **构建协议升级**: 将 Android Gradle Plugin (AGP) 从 8.4.2 升级至 8.7.3，完美适配 Gradle 8.7，消除了过期警告。
  - **SDK 合规性**: 针对 `package_info_plus` 等插件的最新要求，将 `compileSdk` 升级至 36，并同步更新了 `suppressUnsupportedCompileSdk` 配置。

---

### **2026-03-23**

- **重构**: 引入了 `Provider` 状态管理，并对 `ReaderProvider` 和 `TtsEngineService` 进行了大规模优化，解耦了 UI 与业务逻辑。 (commits: `7626d14`, `8df113e`)
- **功能**: 实现了书籍导入进度显示和全局 Toast 通知系统。 (commits: `215b39c`, `48b14a4`)

### **2026-03-13**

- **国际化**: 全面汉化了 UI 界面，移除了所有可见的英文文本。 (commit: `9626d14`)
- **UI/UX**: 优化了 UI 布局，修复了数值面板溢出和底部控件拥挤的问题。 (commit: `bdf113e`)
- **重构**: 按照规范对前后端项目结构进行了大规模重构，实现了模块化，并添加了详细的中文注释。 (commits: `315b39c`, `78b14a4`, `2b78d99`, `5235ddf`, `18dba57`, `d1f3138`, `314e98e`)
- **配置**: 将硬编码的服务器 IP 迁移到配置文件中进行统一管理。 (commit: `25ad232`)
- **安全**: 将 CORS策略改为 white名单制，并从版本控制中移除了二进制文件和数据库文件。 (commits: `4563aeb`, `b2768ec`)
- **文档**: 添加了项目 README 文件。 (commit: `383d88a`)
- **初始提交**: 初始化阅游项目独立仓库。 (commit: `9ce088a`)

---
