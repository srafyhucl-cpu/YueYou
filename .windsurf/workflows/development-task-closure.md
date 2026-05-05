---
description: 开发任务收口工作流，用于阅游项目的任务完成检查、文档更新和代码提交
---

# 开发任务收口工作流

## 触发场景

当一次开发任务进入收尾阶段时使用此工作流，确保交付闭环符合阅游项目规范。

## 收口检查清单

### 1. 代码质量验证

```bash
# 静态分析（必须零警告）
flutter analyze

# AI 工程门禁（必须通过）
dart scripts/ai_code_checker.dart

# 规范检查（调用 code-standardization-check 工作流）
/code-standardization-check
```

- **控制台必须完全清洁，无任何警告信息**

### 2. 测试验证

```bash
# 根据修改范围选择测试
flutter test test/features/[相关模块]
flutter test --coverage
```

### 3. 任务文档检查

- 检查 `DevelopmentPlan/YYYYMMDD_中文概要.md` 是否存在
- 确保同一天只保留一个任务汇总文件
- 验证任务内容完整性：目标、变更点、验证结果

### 4. 开发日志更新

更新 `development_log.md`，记录：

- 日期和任务类型
- 核心变更内容
- 验证命令和结果
- 相关文件路径

### 5. README 更新判断

仅在以下情况更新 README.md：

- 用户可见能力变化
- 启动、构建、测试命令变更
- 技术栈或依赖版本更新
- 核心功能或架构事实变化

## 技能调用顺序

1. **yueyou-test-ci-guard** - 测试验证
2. **yueyou-code-quality-guard** - 代码质量检查
3. **yueyou-architecture-guard** - 架构合规性验证
4. **yueyou-task-steward** - 任务收口管理

## Git 提交规范

### 提交前检查

```bash
git status --short
```

### 提交信息格式

使用中文 Conventional Commits：

- `feat: 新功能描述`
- `fix: 修复问题描述`
- `refactor: 重构描述`
- `test: 测试相关`
- `docs: 文档更新`

### 提交后推送

按项目约定推送到远程分支

## 验收标准

- [ ] `flutter analyze` **零错误零警告（控制台完全清洁）**
- [ ] 相关测试通过
- [ ] 代码规范检查通过
- [ ] 任务文档已更新
- [ ] 开发日志已记录
- [ ] Git 提交符合规范
- [ ] 已推送到远程分支
- [ ] **运行时控制台无任何警告信息输出**

## 常见问题处理

### 测试失败

1. 先运行 `flutter test --concurrency=1` 排除竞态
2. 检查是否需要更新测试工具
3. 确认 mock 设置是否正确

### 代码规范问题

1. 调用 `yueyou-code-quality-guard` 技能分析
2. 根据建议逐项修复
3. 重新运行检查直到通过

### 文档冲突

1. 检查是否有多个今日任务文件
2. 合并相关内容到单一文件
3. 确保文件名和内容一致

## 注意事项

1. **顺序重要性**：严格按照检查清单顺序执行
2. **完整性要求**：每个步骤都必须完成，不可跳过
3. **质量优先**：不为赶时间而降低验收标准
4. **文档同步**：代码和文档必须同步更新
