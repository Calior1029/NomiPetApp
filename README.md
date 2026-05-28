# NomiPetApp

> A tiny macOS desktop pet that makes your AI work feel alive.
>
> 一个会读懂 Codex / Claude 工作状态的 macOS 桌面宠物。

<p align="center">
  <img src="nomi-standing.png" alt="Nomi standing" width="280">
</p>

[Download DMG](https://github.com/Calior1029/NomiPetApp/releases/latest) · [Source Code](https://github.com/Calior1029/NomiPetApp) · [English](#english) · [中文](#中文介绍)

Nomi is a native macOS desktop companion built for people who spend long hours with AI coding agents. Instead of leaving Codex or Claude running silently in the background, Nomi turns their progress into a visible, emotional, low-pressure desktop presence.

Nomi floats quietly on your screen, reacts to activity, shows readable progress bubbles, and gives your workspace a small sense of life without becoming another noisy app.

---

## English

### Not just a desktop pet. A progress companion for AI work.

NomiPetApp is a native macOS desktop pet designed for people who work with AI agents every day. It watches local Codex and Claude activity, translates progress into clear desktop feedback, and gives your workspace a small, calm, living presence.

When your AI agent is thinking, running, waiting, failing, completing, or stalling, Nomi can reflect that state through animation and readable bubbles. You no longer need to keep switching windows just to check whether a background AI task is still alive.

In one sentence: **Nomi makes invisible AI progress visible.**

### Why Nomi stands out

- **Built for AI-heavy workflows**  
  Nomi is not a generic toy. It is designed around real Codex and Claude work sessions, where tasks can run for minutes and progress needs to stay visible.

- **Quiet by design**  
  No noisy dashboards. No giant control panel. No constant interruption. Nomi floats on your desktop, reacts when useful, and stays out of the way when you are focused.

- **Native macOS feel**  
  Built with SwiftPM and AppKit, Nomi uses a transparent floating window, menu bar controls, draggable positioning, double-click settings, and mouse passthrough on transparent areas.

- **Readable long-running status bubbles**  
  AI tasks are not always instant. Nomi keeps work-state bubbles visible while Codex or Claude is active, so the latest project status does not disappear before you see it.

- **Cute, restrained, and usable**  
  Nomi is expressive without being loud. The visual style is soft, minimal, and suitable for keeping on screen all day.

- **Works without an API key**  
  Nomi runs with local fallback personality lines by default. DeepSeek can be configured later for richer responses, but it is optional.

- **Local-first behavior**  
  Nomi primarily reads local Codex / Claude activity files and stores its own settings locally. Cloud AI is only used when you configure an API key.

### Features

- Transparent floating desktop pet window
- Draggable pet position
- Minimal menu bar controls
- Double-click Nomi to open settings
- Adjustable pet size, bubble size, font size, line spacing, and bubble offset
- Codex progress monitoring
- Claude progress monitoring
- Status normalization: thinking, running, waiting, failed, completed, stalled
- Persistent work-state bubbles while tasks are active
- Sparse idle interactions when no task is active
- Hover, drag, and right-click interaction animations
- Bundled animation assets and Codex pet spritesheet fallback
- Optional DeepSeek integration
- Local settings, memory, user memory, and chat history storage

### Who it is for

Nomi is made for:

- Developers and creators who run Codex or Claude for real work
- People who want a calm, minimal desktop companion
- Users who dislike constantly checking whether an AI task has finished
- Anyone who wants AI progress to feel more visible and less lonely
- Desktop pet fans who still care about utility, polish, and speed

### Download and Install

Download the DMG from GitHub Releases:

1. Open the **Releases** page of this repository.
2. Download `NomiPetApp-v4.0.dmg`.
3. Open the DMG.
4. Drag `NomiPetApp.app` into `Applications`.
5. Launch Nomi.

> The current build uses ad-hoc signing. macOS may show a security confirmation on first launch because the app is not notarized yet.

### Run from Source

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM target, creates `dist/NomiPetApp.app`, stops any old running copy, and launches the fresh app.

### Optional DeepSeek Configuration

Nomi works without an API key.  
To enable richer AI responses, create:

```json
{
  "apiKey": "your-deepseek-key",
  "baseURL": "https://api.deepseek.com/chat/completions",
  "model": "deepseek-chat"
}
```

at:

```text
~/.nomi-pet/config.json
```

Environment variables override the file:

```bash
DEEPSEEK_API_KEY=your-key ./script/build_and_run.sh
```

Optional variables:

- `DEEPSEEK_BASE_URL`
- `DEEPSEEK_MODEL`

### Local Data and Privacy

Nomi reads local progress sources:

- Codex: `~/.codex/state_5.sqlite`
- Codex fallback: `~/.codex/session_index.jsonl`
- Claude: newest `*.jsonl` session under `~/.claude/projects`

Nomi stores its own local data in:

- `~/.nomi-pet/settings.json`
- `~/.nomi-pet/memory.json`
- `~/.nomi-pet/user_memory.json`
- `~/.nomi-pet/chat_history.json`

Without a configured DeepSeek API key, Nomi uses local fallback lines instead of cloud AI responses.

### Project Goal

NomiPetApp focuses on one clear idea:

**Turn background AI-agent progress into a lightweight, readable, emotionally expressive macOS desktop experience.**

It is small enough to keep open all day, useful enough to earn its spot on your desktop, and quiet enough not to become another distraction.

---

## 中文介绍

### 这不是普通桌宠，是你的 AI 工作状态陪跑员

NomiPetApp 是一个原生 macOS 桌宠应用。它不是单纯卖萌，也不是又一个聊天窗口，而是专门为高频使用 Codex、Claude、AI 编程工具的人设计的桌面工作伙伴。

当你的 AI 工具在思考、运行、等待、失败、完成任务时，Nomi 会把这些状态变成更直观的动画和气泡。你不用反复切窗口确认进度，也不用盯着终端干等。Nomi 会安静地待在桌面上，用很轻的方式告诉你：现在任务还在跑、已经卡住、还是已经完成。

一句话：**让看不见的 AI 工作进度，变成桌面上看得见的陪伴感。**

### 为什么它值得装

- **为 AI 工作流而生**  
  Nomi 会读取本地 Codex 和 Claude 的活动状态，把后台任务变成清晰的桌面反馈。对经常开多个 AI 任务的人来说，这比反复翻窗口省心很多。

- **不打扰，但有存在感**  
  它不是弹窗轰炸，也不是复杂 dashboard。Nomi 只是浮在桌面上，在你需要的时候显示状态，在你专注的时候保持克制。

- **真正原生 macOS 体验**  
  SwiftPM + AppKit 构建，透明悬浮窗口、菜单栏控制、拖拽位置、双击设置、透明区域鼠标穿透，体验接近系统级小工具。

- **状态气泡更适合长期任务**  
  普通提示看一眼就没了，但 Codex / Claude 的任务经常需要几分钟甚至更久。Nomi 的工作状态气泡会在任务活跃时保持可读，不会让你错过关键进度。

- **可爱，但不幼稚**  
  Nomi 的角色风格是克制、柔和、有一点机灵。它不是大面积占屏的玩具，而是桌面角落里一个轻量、稳定、可长期挂着的小助手。

- **没有 API key 也能用**  
  Nomi 默认可以离线使用本地人格和提示。配置 DeepSeek key 后，可以启用更智能的聊天和表达，但这不是启动应用的前提。

- **本地优先，边界清楚**  
  应用主要读取你本机的 Codex / Claude 活动文件和 Nomi 自己的设置文件。DeepSeek 只在你主动配置 API key 后使用。

### 核心功能

- 透明悬浮桌宠窗口
- 可拖拽桌宠位置
- 菜单栏快速控制
- 双击 Nomi 打开设置
- 可调整桌宠大小、气泡尺寸、字体、行距和偏移
- Codex 进度监控
- Claude 进度监控
- 状态识别：thinking、running、waiting、failed、completed、stalled
- 工作状态气泡持续显示
- 空闲时随机轻量互动
- 鼠标悬停、拖拽、右键等交互动画
- 支持本地动画资源和 Codex pet spritesheet
- 可选 DeepSeek 配置
- 本地记忆、聊天历史和用户设置存储

### 适合谁

Nomi 特别适合这些人：

- 经常使用 Codex / Claude 做代码、文档、自动化任务的人
- 喜欢极简桌面，但又希望工作空间有一点生命感的人
- 不想频繁切窗口看 AI 有没有跑完的人
- 想让 AI 工作流更可感知、更有反馈、更不孤独的人
- 喜欢桌宠，但不想要臃肿娱乐软件的人

### 下载与安装

推荐从 GitHub Releases 下载 DMG 安装包：

1. 打开本仓库的 **Releases** 页面。
2. 下载 `NomiPetApp-v4.0.dmg`。
3. 打开 DMG。
4. 将 `NomiPetApp.app` 拖入 `Applications`。
5. 启动 Nomi。

> 当前安装包是 ad-hoc 签名版本。首次打开时，macOS 可能提示安全确认，这是未 notarized 的独立 macOS 应用常见情况。

### 从源码运行

```bash
./script/build_and_run.sh
```

脚本会构建 SwiftPM target，生成 `dist/NomiPetApp.app`，关闭旧实例，然后启动新的 Nomi。

### DeepSeek 配置，可选

Nomi 不配置 API key 也能运行。  
如果你想启用更智能的表达，可以创建：

```json
{
  "apiKey": "your-deepseek-key",
  "baseURL": "https://api.deepseek.com/chat/completions",
  "model": "deepseek-chat"
}
```

保存到：

```text
~/.nomi-pet/config.json
```

也可以用环境变量覆盖：

```bash
DEEPSEEK_API_KEY=your-key ./script/build_and_run.sh
```

可选变量：

- `DEEPSEEK_BASE_URL`
- `DEEPSEEK_MODEL`

### 本地数据与隐私

Nomi 会读取这些本地位置来判断工作状态：

- Codex: `~/.codex/state_5.sqlite`
- Codex fallback: `~/.codex/session_index.jsonl`
- Claude: `~/.claude/projects` 下最新的 `*.jsonl` session

Nomi 会把自己的设置和记忆写入：

- `~/.nomi-pet/settings.json`
- `~/.nomi-pet/memory.json`
- `~/.nomi-pet/user_memory.json`
- `~/.nomi-pet/chat_history.json`

如果没有配置 DeepSeek API key，Nomi 使用本地 fallback 文案，不需要云端模型。

### 项目定位

NomiPetApp 的目标不是做一个全能 AI 助手，而是做一件很具体的事：

**把 AI agent 的后台工作状态，变成一个轻量、清晰、有情绪反馈的 macOS 桌面体验。**

它适合长期开着，不抢注意力，不增加操作负担，只在需要的时候给你反馈。

---
## Requirements

- macOS 14 or later
- Swift 6 toolchain for source builds

## Repository Notes

- Source code lives in this repository.
- DMG builds should be distributed through GitHub Releases.
- Generated `dist/` output is ignored by git.
