# AgentMonitor

AgentMonitor 是一个 macOS 菜单栏工具，用来集中查看 Claude Code 和 Codex CLI 的会话状态。

它通过 Claude Code hooks 和 Codex notify hook 接收本地事件，在菜单栏显示当前会话数量、待确认数量和已完成数量，并在下拉面板里列出每个会话。点击会话记录时，AgentMonitor 会尝试跳回对应的 Terminal 或 iTerm2 窗口。

## 功能

- 在 macOS 菜单栏显示会话概览：`总数 待确认 已完成`
- 按 Claude Code 和 Codex 分组展示会话
- 显示项目目录名、Git 分支、状态、更新时间和最近消息摘要
- 点击会话记录跳转到对应终端窗口
- 对待确认、完成、失败状态发送系统通知
- 支持清理已完成或失败的会话记录

## 状态栏格式

状态栏显示格式类似：

```text
3  待1  完2
```

- `3`：当前记录的总会话数
- `待1`：等待确认的会话数量
- `完2`：已完成的会话数量

当存在待确认会话时，状态栏图标会切换为强调状态。

## 下拉面板信息

每条会话记录包含：

- 会话标题：优先使用 hook 上报的首条用户消息或会话标题
- 项目名：来自 hook 上报的 `cwd` 最后一段目录名
- Git 分支：从会话工作目录读取，格式为 `branch main`
- 状态：运行中、等待确认、已完成、出错
- 更新时间：例如 `刚刚`、`5分钟前`
- 最近消息：来自 Claude Code 或 Codex hook 上报的最后消息摘要

如果当前 hook payload 没有可识别的用户消息，AgentMonitor 会继续使用项目名作为标题。

如果工作目录不是 Git 仓库，分支信息会自动隐藏。

## 安装和运行

### 构建 App

```bash
make app
```

构建完成后会生成：

```text
AgentMonitor.app
```

### 运行

```bash
make run
```

### 安装到 Applications

```bash
make install
```

## 配置 Hooks

先启动 AgentMonitor，然后运行：

```bash
./Scripts/install.sh
```

这个脚本会配置：

- Claude Code hooks：写入 `~/.claude/settings.json`
- Codex notify hook：写入 `~/.codex/config.toml`
- AgentMonitor wrapper scripts：写入 `~/.agentmonitor/`

如果只想配置其中一个：

```bash
./Scripts/install.sh --claude-only
./Scripts/install.sh --codex-only
```

配置完成后，需要重启已经打开的 Claude Code 或 Codex 会话，让新的 hook 生效。

## 设置

点击下拉面板底部的“设置”可以打开设置窗口。

当前支持：

- 开机启动：勾选后 AgentMonitor 会随 macOS 登录自动启动。
- 系统通知：可分别控制“任务已完成”和“等待确认”两类通知。
- 端口配置：默认端口为 `17321`，也可以自定义本地 hook server 端口。

端口设置会写入 macOS defaults。新安装的 hook wrapper 会在每次执行时读取当前端口，因此修改端口后不需要手动改脚本；如果你的 hook 是旧版本安装的，请重新运行：

```bash
./Scripts/install.sh
```

## 跳转到会话窗口

AgentMonitor 会在 hook payload 中附加当前终端 TTY，并在点击会话记录时通过 AppleScript 查找对应的 Terminal 或 iTerm2 tab/session。

首次使用跳转功能时，macOS 可能会请求权限，允许 AgentMonitor 控制 Terminal 或 iTerm2 即可。

如果找不到对应终端窗口，AgentMonitor 会退回到打开该会话的工作目录。

## 本地服务

AgentMonitor 会监听本地端口：

```text
localhost:17321
```

hook 会把事件 POST 到：

```text
http://localhost:17321/hooks/claude
http://localhost:17321/hooks/codex
```

该服务只用于本机 hook 通信。

## 开发

Debug 构建：

```bash
swift build
```

Release 构建：

```bash
swift build -c release
```

清理：

```bash
make clean
```

## 注意事项

- 会话数据只保存在内存中，退出 AgentMonitor 后会清空。
- 旧 hook 产生的会话可能没有 TTY 信息，点击时无法精确跳回终端窗口。
- Git 分支信息在收到 hook 事件时读取；切换分支后，需要新的 hook 事件到来才会更新显示。
- 当前支持 Terminal 和 iTerm2 的窗口跳转。
