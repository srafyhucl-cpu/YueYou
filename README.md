# 阅游 (YueYou) - 赛博 2048 与沉浸式全息听书系统

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Frontend](https://img.shields.io/badge/Frontend-Vanilla_JS_ES6-f39f37.svg)
![Backend](https://img.shields.io/badge/Backend-Gin_(Go)-00add8.svg)
![Database](https://img.shields.io/badge/Database-SQLite_&_IndexedDB-003B57.svg)
![Mobile](https://img.shields.io/badge/Mobile-Capacitor_5.0-60a5fa.svg)

> **"在这里，滑动手势将操纵数字物质，每一本书都是一次向更高维度的跨越。"**

**阅游**是一个将经典的「2048」数字解谜与「沉浸式有声书/白噪音」完美融合的超感官应用程序。项目核心围绕“维度跨越”与“神经接入”展开，内置了灵动岛级的 UI 交互引擎与 Web Audio API 全息声场。

玩家在游玩 2048 的碎片时间里，可以聆听由 Azure 神经语音驱动的高质量文本播报，享受赛博暗雨、竹林远笛等环境背景音，实现真正的“心流状态”。

---

## 🌟 核心特性

- **🎮 赛博脉冲 2048**：纯净、丝滑的经典 2048 棋盘，配合 3D 物理惯性倾斜与机械翻页动画。
- **🌑 灵动岛 (Dynamic Island) 交互引擎**：顶部的胶囊化控播中心，支持动态实时频谱、进度环监控、以及一键倍速切换。
- **🎧 全息混响声场 (Web Audio API)**：内置 `Wuxia`（武侠风云）、`Standard`（默认）等声场，支持实时卷积混响与动态滤波，营造极致的听觉包围感。
- **📚 高维进度引擎 (Progress Manager)**：独立于业务逻辑的进度持久化系统，精准记录每一份本地档案的阅读节点（百分比、行号、章节）。
- **🗣️ 神经语音脉冲 (TTS)**：连接 Azure 神经语音服务，支持多发音人（晓晓、云希等）切换及 0.7x - 2.5x 灵活调速。
- **💾 双轨持久化架构**：前端采用原生 IndexedDB 存储超大容量 TXT 文本，后端通过 SQLite WAL 模式维护云端同步。

---

## 🏗️ 架构与技术栈

项目采用极简、高效的前后端分离架构，特别针对移动端原生环境进行了深度适配。

### 前端工程 (yueyou-app)
- **核心逻辑**：Vanilla JS (ES6 模块化) - 彻底解耦 `AudioManager`, `GameEngine`, `Renderer`, `LocalDB`。
- **UI & 动效**：原生 CSS3 (Grid/Flex) + 滤镜/混合模式 + 自研 Odometer 数字翻页引擎。
- **存储机制**：IndexedDB (存放小说原文) + localStorage (存放配置与进度锚点)。
- **原生桥接**：Capacitor 5.0，支持编译为 Android/iOS 独立安装包。

### 后端服务 (yueyou-server)
- **底层框架**：Go 1.20+ & Gin Web Framework。
- **数据核心**：CGO-Free SQLite (`modernc.org/sqlite`)，支持多端并发安全。
- **鉴权体系**：JWT (JSON Web Token) + Bcrypt 密码安全算法。
- **功能模块**：用户账户系统、进度云端迁移、公共书库检索。

---

## 🚀 快速启动

### 1. 后端服务 (API & Database)
```bash
cd yueyou-server
# 运行服务端（自动初始化 2048.db）
go run cmd/server/main.go
# 默认监听地址：http://localhost:8080
```

### 2. 前端开发 (Web / Mobile)
```bash
cd yueyou-app/www
# 使用任何静态服务器运行
# 推荐使用：npx http-server 或 VSCode Live Server
npx http-server -p 3000
```
*提示：环境配置位于 `www/js/config.js`，可自动识别移动端/Web端切换后端请求前缀。*

---

## 📂 项目结构指南

```text
YueYou-Project/
├── yueyou-app/                     # 前端工程 & Capacitor 打包环境
│   ├── android/                    # Android 原生工程目录
│   └── www/                        # 核心发版源码区
│       ├── css/                    # 视觉系统 (style.css, toast.css)
│       ├── js/                     # 核心驱动引擎
│       │   ├── modules/            # 模块化逻辑 (AudioManager, GameEngine, Renderer, LocalDB)
│       │   ├── config.js           # 神经中枢：全局静态配置与域名映射
│       │   └── main.js             # 系统总控：初始化与事件调度
│       └── index.html              # 宿主页面：灵动岛与游戏容器
│
├── yueyou-server/                  # Go 语言后端服务
│   ├── cmd/server/main.go          # 服务入口与路由分发
│   ├── internal/                   # 内部业务逻辑
│   │   ├── handlers/               # 控制器 (Auth, Novel, State, Middleware)
│   │   └── models/                 # 数据模型 (SQLite, DB Init)
│   └── go.mod                      # 依赖管理
│
└── README.md                       # 项目启动手册
```

---

## 📜 开源协议

MIT License.
请注意：本项目仅作为技术交流与学术研究使用。项目内涉及的 TTS 接口及小说内容版权归原作者及企业所有，请勿用于非法用途。
