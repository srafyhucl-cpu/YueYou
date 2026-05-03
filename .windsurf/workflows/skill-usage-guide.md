---
description: 技能使用指南，定义阅游项目各技能的调用优先级和使用场景
---

# 技能使用指南

## 技能调用优先级

### 🥇 第一优先级（核心架构）

1. **yueyou-architecture-guard** - 架构边界约束
   - 触发：修改 lib/core、lib/features、Provider、Service、domain、presentation
   - 职责：确保 Clean Architecture 分层合规
   - 检查：UI 库违规导入、Provider 使用规范、模块依赖

### 🥈 第二优先级（代码质量）

1. **yueyou-code-quality-guard** - 代码质量规范
   - 触发：修改业务逻辑、新增调试代码、处理异常
   - 职责：日志规范、硬编码检测、异常处理统一
   - 检查：debugPrint 使用、魔法数字、异常上报

2. **yueyou-config-constants-guard** - 配置常量管理
   - 触发：修改配置文件、新增硬编码值、环境配置
   - 职责：配置管理、常量定义、环境变量使用
   - 检查：环境变量、常量抽取、配置完整性

### 🥉 第三优先级（专项领域）

1. **yueyou-test-ci-guard** - 测试与 CI
   - 触发：新增功能、修复 bug、调整异步逻辑、平台插件
   - 职责：测试规范、CI 排查、覆盖率维护
   - 检查：测试隔离、mock 设置、CI 失败排查

2. **yueyou-tts-audio-guard** - TTS 音频专项
   - 触发：修改 TTS 相关功能、音频播放、缓存、预加载
   - 职责：TTS 契约、状态机、音频资源管理
   - 检查：两步下载、竞态处理、缓存清理

3. **yueyou-ui-performance-expert** - UI 性能优化
   - 触发：UI 构建、动画优化、大文件处理、性能问题
   - 职责：赛博朋克 UI、60FPS 渲染、Isolate 计算
   - 检查：重绘隔离、硬件加速、内存管理

### 🔧 第四优先级（特殊场景）

1. **yueyou-domain-pure-logic** - 纯业务逻辑开发
   - 触发：开发 domain 层算法、2048 核心逻辑
   - 职责：纯 Dart 业务逻辑、无 UI 依赖
   - 约束：严禁导入 Flutter 库

2. **yueyou-strict-migration** - 代码迁移
   - 触发：旧代码迁移到新架构
   - 职责：1:1 逻辑复刻、视觉映射
   - 约束：禁止创造性修改

3. **yueyou-docs-encoding-guard** - 文档编码
   - 触发：创建或更新文档、修复 Markdown 警告
   - 职责：UTF-8 编码、DevelopmentPlan 规范
   - 检查：文档格式、编码问题

4. **yueyou-release-readiness-guard** - 发布就绪守卫
   - 触发：发版、打包、上线、交付验收、生产环境配置
   - 职责：发布门禁、APK 构建规范、环境变量、零警告验收
   - 检查：arm64 APK、`--dart-define`、TTS 契约、发布拒绝条件

5. **yueyou-task-steward** - 任务收口管理
   - 触发：任务完成、代码提交、推送管理
   - 职责：任务收口、文档更新、提交规范
   - 检查：开发日志、README 更新、Git 规范

## 技能协作关系

### 🔄 协作模式

```text
架构检查 → 代码质量 → 测试验证 → 发布验收 → 任务收口
    ↓         ↓         ↓         ↓         ↓
domain   → constants → test   → release  → docs
```

### 🚫 冲突解决

- **日志规范冲突**：以 `yueyou-code-quality-guard` 为准
- **架构边界冲突**：以 `yueyou-architecture-guard` 为准
- **配置管理冲突**：以 `yueyou-config-constants-guard` 为准
- **发布门禁冲突**：以 `yueyou-release-readiness-guard` 为准

## 工作流集成

### 开发新功能

1. `yueyou-architecture-guard` - 确保架构合规
2. `yueyou-code-quality-guard` - 代码质量检查
3. `yueyou-test-ci-guard` - 测试验证
4. `yueyou-task-steward` - 任务收口

### 修复 Bug

1. `yueyou-code-quality-guard` - 问题分析
2. `yueyou-test-ci-guard` - 测试修复
3. `yueyou-task-steward` - 提交管理

### 性能优化

1. `yueyou-ui-performance-expert` - 性能分析
2. `yueyou-code-quality-guard` - 代码规范
3. `yueyou-test-ci-guard` - 性能测试

### TTS 功能开发

1. `yueyou-tts-audio-guard` - TTS 专项检查
2. `yueyou-code-quality-guard` - 代码质量
3. `yueyou-test-ci-guard` - 功能测试

### 发布打包

1. `yueyou-release-readiness-guard` - 发布门禁
2. `yueyou-config-constants-guard` - 环境配置
3. `yueyou-test-ci-guard` - 验证测试
4. `yueyou-task-steward` - 文档提交推送

## 技能选择决策树

```text
开始开发
    ↓
是否涉及架构变更？ → 是 → yueyou-architecture-guard
    ↓ 否
是否涉及配置/常量？ → 是 → yueyou-config-constants-guard
    ↓ 否
是否涉及代码质量？ → 是 → yueyou-code-quality-guard
    ↓ 否
是否涉及 TTS/音频？ → 是 → yueyou-tts-audio-guard
    ↓ 否
是否涉及 UI/性能？ → 是 → yueyou-ui-performance-expert
    ↓ 否
是否涉及测试？ → 是 → yueyou-test-ci-guard
    ↓ 否
是否涉及文档？ → 是 → yueyou-docs-encoding-guard
    ↓ 否
是否涉及发布？ → 是 → yueyou-release-readiness-guard
    ↓ 否
是否任务完成？ → 是 → yueyou-task-steward
    ↓ 否
根据具体需求选择专项技能
```

## 最佳实践

### ✅ 推荐做法

1. **按优先级顺序调用技能**
2. **一次开发任务调用多个相关技能**
3. **技能检查失败时，先解决核心问题**
4. **记录技能调用结果和修复措施**

### ❌ 避免做法

1. **跳过优先级高的技能**
2. **同时调用冲突的技能**
3. **忽略技能检查结果**
4. **重复调用相同技能**

## 技能状态管理

### 激活状态

- 技能被调用时进入激活状态
- 完成检查后自动退出
- 异常时提供错误信息

### 结果记录

- 检查通过：记录验证结果
- 检查失败：提供修复建议
- 部分通过：标记待改进项

## 持续改进

### 技能优化

- 根据使用反馈调整技能规则
- 优化检查算法和性能
- 补充新的检查场景

### 工作流优化

- 根据项目发展调整工作流
- 集成新的自动化检查
- 优化技能调用顺序
