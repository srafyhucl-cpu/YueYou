# 阅游 (YueYou) - 2048 维度越界与全息听书系统

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Vue](https://img.shields.io/badge/Frontend-Vanilla_JS-f39f37.svg)
![Gin](https://img.shields.io/badge/Backend-Gin_(Go)-00add8.svg)
![SQLite](https://img.shields.io/badge/Database-SQLite_WAL-003B57.svg)

> **"在这里，滑动手势将操纵数字物质，每一本书都是一次向更高维度的跨越。"**

**阅游**是一个将经典的「2048」解谜玩法与「沉浸式白噪音/有声书」完美融合的跨端应用程序。项目采用了赛博朋克 2048 的世界观设定，内置了程序化生成的全息水滴音效与沉浸式声场。

玩家在游玩 2048 进行“维度跨越”的碎片时间里，不仅可以沉思于冥想级白噪音（赛博暗雨、竹林远笛），还能自动同步聆听由 Azure TTS 驱动的本地与公共书库。

---

## 🌟 核心特性

- **🎮 多位面 2048 玩法**：从经典的合成 2048，到拆解降维、时间回溯（撤销）、清空场地的「开发者权限」道具系统。
- **🎧 沉浸式环境音景 (Web Audio API)**：内置 `Rain`（暗雨与深空沉雷）、`Wuxia`（竹林风与远笛）、`Relax`（云端冥想）三种环境声场，并配合游戏物理合成产生动态震动与水滴音效。
- **📚 跨端公共图书馆**：支持本地免登录导 TXT 阅读，也支持上传至云端公共书库。
- **🗣️ AI 语音神经脉冲 (TTS)**：连接 Azure 神经语音合成服务，玩游戏的同时自动将文本转化为高质量的有声演播。
- **💾 无缝断点续传**：基于 IndexedDB 与 SQLite 的双边同步机制，游戏的分数维度与阅读的段落锚点会自动云端漫游。

---

## 🏗️ 架构与技术栈

项目采用高内聚、低耦合的前后端分离架构，支持打包为 Android/iOS 独立应用包。

### 前端 (yueyou-app)
- **核心**：Vanilla JS (ES6 模块化) + 原生 CSS3 网格动画
- **存储**：IndexedDB (LocalDB) + localStorage
- **音频**：HTML5 Web Audio API (动态节点生成与滤波处理)
- **跨端环境**：Capacitor 5.0 (构建安卓/iOS 原生容器)

### 后端 (yueyou-server)
- **核心框架**：Gin Web Framework
- **数据库**：CGO-Free SQLite (`modernc.org/sqlite`) 开启 WAL 并发写入模式
- **安全体系**：Bcrypt 密码哈希 + JWT
- **运行拓扑**：单文件轻量运行与多端 CORS 白名单

---

## 🚀 本地开发指南

### 1. 启动后端数据库与 API

确保你已经安装了 Go (>= 1.20)。

```bash
cd yueyou-server
# 编译并运行服务端
go run .
# 服务端将在 http://localhost:8080 启动
```

### 2. 启动前端页面

由于跨域与音频安全策略限制（Web Audio API），前端必须通过本地服务器运行。

```bash
cd yueyou-app/www
# 使用 vite、http-server 或者 python 启动本地服务
npx http-server -p 3000
# 浏览器访问 http://localhost:3000
```
*(注意：在浏览器测试时，可通过控制台开关切换至本地或线上正式服务器集群。环境配置通过 `config.js` 全局动态调整。)*

---

## 📂 项目结构

```text
YueYou-Project/
├── yueyou-app/                     # 前端工程 & Capacitor 打包环境
│   └── www/                        # 核心发版源码
│       ├── index.html              # 主控台渲染模板
│       ├── style.css               # 样式与物理动效定义
│       ├── config.js               # 全局环境路由中心
│       └── main.js                 # 前端核心驱动模块
│
├── yueyou-server/                  # Go 语言后端服务
│   ├── main.go                     # Gin 启停与请求分发路由
│   ├── handlers_auth.go            # 账户注册/登入逻辑
│   ├── handlers_state.go           # 进度云迁移逻辑
│   ├── handlers_novel.go           # TXT 解析与图书馆检索
│   ├── middleware_auth.go          # JWT 拦截器
│   ├── utils_response.go           # 统一 JSON 返回格式化
│   └── db.go                       # SQLite 建表与 WAL 初始
│
└── .gitignore                      # 安全监控与垃圾排除
```

---

## 📜 开源协议

MIT License.
请遵守当地法律法规运行，本项目的 TTS 服务及小说版权归相关原作者及企业所有。
