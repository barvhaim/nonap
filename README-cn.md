# NoNap ☕

[![Build](https://github.com/barvhaim/nonap/actions/workflows/build.yml/badge.svg)](https://github.com/barvhaim/nonap/actions/workflows/build.yml)

一个轻量的 macOS 菜单栏应用，可在长任务运行时让 Mac 保持唤醒：
**AI 编码代理**（Claude Code、Cursor、Codex）、本地模型推理、整夜运行任务，
以及你已经习惯用它保护的构建、备份和 SSH 会话。它就是 `caffeinate` 的图形界面。
启动一个长时间运行的代理任务后，你可以离开，让任务继续完成，而不会因为 Mac 睡眠导致会话中断。
你也可以让 NoNap 跟踪运行任务本身：它会一直保持唤醒，**直到任务真正结束**，然后自动停止。

**[→ nonap 网站](https://barvhaim.github.io/nonap/)** · **[下载](https://github.com/barvhaim/nonap/releases)**

<p align="center">
  <img width="307" height="320" alt="NoNap menu" src="https://github.com/user-attachments/assets/abdfb427-ace8-41b3-b690-aaa3f3be7c3e" />
</p>

- ☕ 常驻菜单栏：唤醒时显示绿色圆点，关闭时显示淡色圆环
- ⏱ 一键保持唤醒，或启动定时会话：可选预设时长（15 分钟到 8 小时），也可输入**自定义**时长，并显示实时倒计时
- 🎯 也可以保持唤醒，**直到你的任务结束**：选择一个正在运行的进程（Claude Code、Cursor、Codex、`node`、`python`、`ollama` 等）或 PID，NoNap 会在它退出时立即自动停止。无需再猜定时器要设多久
- 🎛 三种模式：阻止**系统**睡眠（默认）、阻止**显示器**睡眠，或**两者都阻止**
- 🔔 定时器结束时通知你，并支持**登录时启动**
- 🪶 使用原生 IOKit 电源断言：无守护进程、无轮询。会记住你的模式设置

## 安装

从 [**Releases**](https://github.com/barvhaim/nonap/releases) 页面下载 `NoNap.dmg`，
打开后将 **NoNap** 拖入 Applications。如果你更喜欢，也可以使用附带的 `NoNap.zip`。
仅支持 Apple Silicon（arm64）。

**首次启动。** 该构建使用 ad-hoc 签名（未公证），因此 macOS 会阻止一次。
双击 `NoNap.app`，关闭警告，然后打开**系统设置 → 隐私与安全性**，
滚动到底部并点击**仍要打开**。之后它就会正常启动。

也可以在终端中跳过这个提示：

```bash
xattr -dr com.apple.quarantine /Applications/NoNap.app
```

## 模式

| 模式 | 保持唤醒 | 类似 |
|------|----------|------|
| **阻止系统睡眠**（默认） | 系统；显示器可睡眠 | `caffeinate` |
| **阻止显示器睡眠** | 系统**和**屏幕 | `caffeinate -d` |
| **两者都阻止** | 系统**和**屏幕 | — |

## 从源码构建

需要 Xcode 16+ / Swift 6。

```bash
git clone https://github.com/barvhaim/nonap.git
cd nonap

swift run                 # 直接运行（菜单栏辅助应用，无 Dock 图标）
./Scripts/make_app.sh     # 构建 NoNap.app 应用包
./Scripts/make_dmg.sh     # 构建可拖拽安装的 NoNap.dmg
./Scripts/package_zip.sh  # 构建并打包为 NoNap.zip 以便分享
```

确认应用在启用时持有电源断言：

```bash
pmset -g assertions | grep NoNap
```

## 贡献

欢迎提交 Issues 和 PR：整个应用只有四个小型 Swift 文件，位于 `Sources/NoNap/`。
发布流程见 [RELEASING.md](RELEASING.md)。

## 许可证

[MIT](LICENSE) © barvhaim
