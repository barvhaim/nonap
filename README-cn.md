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
- 💻 可选的**合盖时保持唤醒**：合上盖子也不中断（VPN/SSH 保持连接），电池或电源供电均可
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

## 合盖时保持唤醒

上面三种模式使用 IOKit 电源断言（与 `caffeinate` 相同），只能阻止*空闲*睡眠。
合上盖子会强制触发**合盖睡眠**，无论断言如何——Mac 会睡眠，VPN/SSH 会话随之中断。
唯一能阻止它的办法是 `pmset disablesleep`，而这需要 root 权限。

**合盖时保持唤醒**是一个可选设置，它会在 **NoNap 开启期间**生效。它运行
`pmset -a disablesleep`，因此在**电池和电源**供电下都有效（电池电量低于 20% 时
会跳过，以免合盖的 MacBook 过热）。会话启动时 NoNap 应用它，并在你 Stop、定时器
结束、被监视的进程退出或退出应用时释放它。

由于 `pmset` 需要 root 权限，首次启用时 NoNap 会执行一次**一次性设置**（输入一次
密码），添加一条 `sudoers` 条目，仅授权这两条 `pmset disablesleep` 命令：

```
你的用户名 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

此后即为**静默运行**——不再需要密码，也不会阻塞无人值守的自动停止。若日后要移除该
授权，删除该文件即可：

```bash
sudo rm /etc/sudoers.d/nonap
```

> **注意。** `disablesleep` 是系统级且具有粘性的。如果 NoNap 在会话进行且此项开启
> 时被*强制退出*，你的 Mac 将不会睡眠，直到清除该设置——重新启动 NoNap 并 Stop，
> 或运行 `sudo pmset -a disablesleep 0`。

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

欢迎提交 Issues 和 PR：整个应用只有几个小型 Swift 文件，位于 `Sources/NoNap/`。
发布流程见 [RELEASING.md](RELEASING.md)。

## 许可证

[MIT](LICENSE) © barvhaim
