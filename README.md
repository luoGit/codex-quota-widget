# Codex Quota Widget

> A tiny macOS helper that keeps your Codex quota visible before quota anxiety kicks in.  
> 主功能是桌面悬浮胶囊；Touch Bar 是给老款 MacBook Pro 用户的增强显示。

![Codex Quota Widget floating capsule mockup](assets/capsule-ui.svg)

Optional Touch Bar preview:

![Codex Quota Widget Touch Bar mockup](assets/touch-bar-ui.svg)

Chinese UI preview:

![Codex Quota Widget Chinese Touch Bar mockup](assets/touch-bar-ui-zh.svg)

## What It Does

Codex Quota Widget shows your current Codex quota in a floating desktop capsule. If your Mac has a Touch Bar, it can also mirror the same quota as a segmented bar.

- Main display: a floating desktop capsule that stays visible while Codex is running.
- Optional display: a Touch Bar view with segmented quota bars, remaining percentages, reset times, and countdowns.
- Click the capsule to open a compact detail panel with reset times, data freshness, and plan information.
- Supports Codex quota schema changes: if Codex only returns a 7-day quota, the widget hides the old 5-hour row automatically.

It is built for people who use Codex heavily and want the same kind of ambient awareness as a download speed widget or battery meter: glance once, keep working.

## 它解决什么问题

Codex 的剩余额度通常藏得比较深，需要点进本地模式里的额度状态才能看到。这个小工具会展示 Codex 当前实际返回的额度窗口；如果新版本只剩 7 天额度，就自动隐藏旧的 5 小时额度。主功能是桌面悬浮胶囊，所以没有 Touch Bar 的 Mac 也能正常使用：

- 桌面悬浮胶囊：一直在屏幕边缘显示，不占菜单栏。
- Touch Bar 展示条：如果你的 Mac 有 Touch Bar，可以像电量条一样显示当前额度。
- 只在 Codex 运行时出现，Codex 退出后自动隐藏。
- 点击桌面胶囊可以展开详情，查看额度重置时间、数据更新时间和套餐信息。

## Highlights

- Native macOS helper written in `Swift + AppKit`.
- No menu bar clutter, no Dock icon, no Python GUI dependencies.
- Reads quota from Codex's local `app-server` first, then falls back to session logs.
- Shows the real `codex` quota bucket and avoids the misleading `codex_bengalfox` bucket.
- Keeps newer app-server snapshots from being overwritten by older session-log fallback data.
- Auto-discovers the `codex` binary in `Codex.app`, `ChatGPT.app`, or common CLI locations (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`).
- Automatically hides quota windows that Codex no longer returns.
- Optional Touch Bar display for Touch Bar MacBook Pro models.
- The whole UI (capsule details, context menu, alerts) switches between English and Chinese from the capsule context menu.
- Touch Bar menu items only appear on Macs that actually have a Touch Bar.
- Right-click menu: expand details, refresh (with last refresh time), language, launch at login, open log, about, and quit.
- Launching the app again wakes the running instance instead of starting a second capsule.
- LaunchAgent support for silent login startup.

## 功能亮点

- 原生 `Swift + AppKit` 实现。
- 不占菜单栏，没有 Dock 图标。
- 优先通过 Codex 本机 `app-server` 读取真实额度，日志解析只作为备用。
- 只读取 `rateLimitsByLimitId.codex`，避免误读其他额度桶。
- 避免旧 session log 回退数据覆盖较新的 app-server 额度快照。
- 自动识别 `Codex.app`、`ChatGPT.app` 内置以及 Homebrew / 本地安装的 `codex` 命令。
- 自动隐藏 Codex 当前已经不再返回的额度窗口。
- Touch Bar 是可选增强，适合仍在使用 Touch Bar MacBook Pro 的用户。
- 右键胶囊可以在 English / 中文之间切换整个界面语言：胶囊详情、右键菜单和提示框都会同步切换。
- 没有 Touch Bar 的 Mac 不会显示 Touch Bar 相关菜单项。
- 右键菜单包含：展开详情、立即刷新（显示上次刷新时间）、界面语言、开机自启、打开日志、关于和退出。
- 重复打开应用（Dock、访达、DMG）会唤醒已有实例并显示胶囊，不会出现第二个浮窗。
- 支持登录后后台自启，打开 Codex 后自动出现。

## Release Package

Build a drag-to-Applications bundle:

```bash
./scripts/package_release.sh
# optional: override the marketing version
VERSION=1.1.0 ./scripts/package_release.sh
```

Outputs in `dist/`:

- `Codex Quota Widget.app` — run it directly, or drag it into `/Applications`.
- `CodexQuotaWidget-<version>.dmg` — mount it and drag the app onto the Applications shortcut.
- `CodexQuotaWidget-<version>.zip` — the same bundle for manual distribution.

The bundle is ad-hoc signed and declares `LSUIElement`, so it runs as an accessory app without a Dock icon. It is not notarized: a copy downloaded from the internet needs the quarantine flag removed once with `xattr -dr com.apple.quarantine "/Applications/Codex Quota Widget.app"`.

Only one floating widget runs at a time; the app and the LaunchAgent share `~/.codex-quota-widget/instance.lock`. If you move from the LaunchAgent helper to the app, remove the agent first:

```bash
./scripts/uninstall_launch_agent.sh
```

To regenerate the app icon after changing `scripts/AppIconGenerator.swift`:

```bash
./scripts/generate_app_icon.sh
```

## 发布安装包

打包成可以直接放进「应用程序」的 release 包：

```bash
./scripts/package_release.sh
# 需要改版本号时
VERSION=1.1.0 ./scripts/package_release.sh
```

`dist/` 下会生成：

- `Codex Quota Widget.app`：可直接运行，或拖入 `/Applications`。
- `CodexQuotaWidget-<version>.dmg`：挂载后把应用拖到 Applications 快捷方式即可安装。
- `CodexQuotaWidget-<version>.zip`：同一个应用包，方便手动分发。

应用使用 ad-hoc 签名并声明 `LSUIElement`，运行时不占 Dock 图标。由于没有做公证，从网络下载的包首次打开前需要执行一次 `xattr -dr com.apple.quarantine "/Applications/Codex Quota Widget.app"`。

应用版与 LaunchAgent 版共用 `~/.codex-quota-widget/instance.lock`，同一时间只会运行一个浮窗。如果要从 LaunchAgent 方式切换到应用方式，先卸载自启：

```bash
./scripts/uninstall_launch_agent.sh
```

修改图标绘制脚本后，可重新生成图标：

```bash
./scripts/generate_app_icon.sh
```

## Startup and Quit

When you run the app bundle:

- **Launch at login** — right-click the capsule and toggle `Launch at Login`. The app registers itself with `SMAppService`, so macOS shows it under `System Settings -> General -> Login Items`. Disabling it removes the registration again. When macOS requires approval, the menu item shows `Launch at Login (Allow in System Settings)`.
- **Enabling from a DMG is blocked** — drag the app into `/Applications` first; the menu explains this instead of registering a copy that lives in `/Volumes`.
- **Legacy LaunchAgent** — if `~/Library/LaunchAgents/com.wendy.codex-quota-widget.plist` still exists, the first enable asks to remove it, so the two startup mechanisms do not fight each other.
- **Approval required** — if macOS reports the login item needs approval, the menu opens Login Items settings for you.
- **Refresh** — `Refresh Now` shows the time of the last successful refresh and forces a fresh quota read.
- **Language** — the `Language` submenu switches the whole interface between English and 中文, including capsule details, menus, and alerts.
- **Quit** — `Quit Codex Quota Widget` in the context menu terminates the app. Reopening it from Finder, Dock, or Spotlight wakes the running instance and shows the capsule, so a second process never starts.
- **Silent start** — the login-started app shows nothing until Codex is running, matching the LaunchAgent behavior. Opening the app yourself always brings the capsule back; if Codex isn't running it shows placeholder quotas and stays visible until Codex starts or you quit.
- **Reopening while Codex is closed** — the capsule no longer flashes and disappears: it stays on screen with `--` values instead of looking like the app failed to open.
- **Diagnostics** — launch, quit, wake requests, and quota-source changes are appended to `~/.codex-quota-widget/widget.log`; `Open Log` opens it in the default app.
- **About** — `About Codex Quota Widget` shows version, build, and the current macOS version.
- **Duplicate launch** — only one instance runs. Starting a copy from the DMG or an unzipped folder shows which instance is already running and wakes its capsule; reopening right after quitting briefly waits for the old process to release the lock instead of exiting silently.

## Install

Clone the repo, then run:

```bash
./scripts/install_launch_agent.sh
```

This will:

- Build the native helper.
- Copy the binary to `~/.codex-quota-widget/bin`.
- Install a user-level LaunchAgent.
- Start the helper immediately.

To restart after making changes:

```bash
./scripts/restart_helper.sh
```

To uninstall:

```bash
./scripts/uninstall_launch_agent.sh
```

## 安装使用

进入项目目录后运行：

```bash
./scripts/install_launch_agent.sh
```

安装完成后：

- 登录 macOS 后 helper 会静默启动。
- 没打开 Codex 时不会显示任何东西。
- 打开 Codex 后，桌面胶囊和 Touch Bar 会自动出现。
- 关闭 Codex 后，它们会自动隐藏。

如果 Touch Bar 被系统关闭按钮隐藏，可以右键桌面胶囊，选择 `显示 Touch Bar` 重新显示。没有 Touch Bar 的 Mac 不会出现这两个菜单项。

如果想切换界面语言，可以右键胶囊，打开 `界面语言` 子菜单选择 `English` 或 `中文`。

如果 Touch Bar 一直不显示，请检查 macOS 设置：`系统设置` -> `键盘` -> `触控栏设置` -> `触控栏显示`，需要选择 `App 控制`。也可以右键桌面胶囊，选择 `打开 Touch Bar 设置…` 快速跳到键盘设置页。

没有 Touch Bar 的 Mac 会继续使用桌面悬浮胶囊，不需要二次开发。

## 启动与退出

应用包的启动与退出行为：

- **开机自启**：右键胶囊勾选 `开机自启`，应用会通过 `SMAppService` 注册登录项，可在 `系统设置 -> 通用 -> 登录项` 中看到；取消勾选会同时注销。macOS 要求批准时，菜单项会显示为 `开机自启（需在系统设置允许）`。
- **不要从 DMG 直接开启自启**：菜单会提示先把应用拖进 `/Applications`，避免注册一个位于 `/Volumes` 的临时路径。
- **旧 LaunchAgent 迁移**：如果还存在 `~/Library/LaunchAgents/com.wendy.codex-quota-widget.plist`，首次开启自启会询问是否移除，避免两套自启同时运行。
- **需要系统确认时**：macOS 提示登录项需要批准时，菜单会直接打开登录项设置。
- **立即刷新**：菜单项会带上上次刷新时间，点击后强制重新读取一次额度。
- **界面语言**：`界面语言` 子菜单可在 English / 中文之间切换，胶囊详情、右键菜单和提示框会一起切换。
- **退出**：右键菜单选择 `退出 Codex Quota Widget` 即可结束进程；再次从访达、Dock 或聚焦打开时，会唤醒已有实例并显示胶囊，不会启动第二个进程。
- **静默启动**：登录自启后不会主动显示界面，等到 Codex 运行才出现，与原 LaunchAgent 行为一致。主动从访达或 Dock 打开应用时则一定会显示胶囊；如果 Codex 没运行，胶囊会显示 `--` 占位并保持可见，直到 Codex 启动或手动退出。
- **Codex 未运行时打开**：浮窗不再闪一下又消失，而是稳定显示占位额度，避免看起来像应用打不开。
- **启动诊断**：启动、退出、唤醒和额度来源变化都会记录到 `~/.codex-quota-widget/widget.log`；菜单里的 `打开日志` 可直接用默认应用打开。
- **关于**：`关于 Codex Quota Widget` 会显示版本、构建号和当前 macOS 版本。
- **重复启动**：同一时间只允许一个实例。从磁盘映像或解压目录再开一份时，会提示当前实例所在路径并唤醒已有浮窗；刚退出后立刻重新打开会短暂等待旧进程释放锁，不会静默退出。

## Touch Bar Setup

If the Touch Bar view does not appear, check macOS settings first:

- Open `System Settings` -> `Keyboard` -> `Touch Bar Settings`.
- Set `Touch Bar shows` to `App Controls`.
- You can also right-click the desktop capsule and choose `Open Touch Bar Settings…` to open Keyboard settings quickly.

This is a macOS-level setting. The widget can show Touch Bar content, but it cannot force macOS to switch away from Control Strip-only modes. On Macs without a Touch Bar, the widget hides these menu items entirely.

## Manual Run

For local testing:

```bash
./scripts/run_local.sh
```

To verify the quota data source:

```bash
./scripts/build.sh
./bin/CodexQuotaWidget --once
```

If the output contains `"sourceFileName": "Codex app-server"`, the primary data source is working.

If Codex is installed in a custom location, set `CODEX_QUOTA_WIDGET_CODEX_PATH` to the full path of the bundled `codex` binary.

## 手动验证

本地调试可以运行：

```bash
./scripts/run_local.sh
```

检查数据源：

```bash
./scripts/build.sh
./bin/CodexQuotaWidget --once
```

如果输出里看到 `"sourceFileName": "Codex app-server"`，说明已经通过 Codex 本机服务拿到了真实额度。

如果你的 Codex 安装在自定义位置，可以把 `CODEX_QUOTA_WIDGET_CODEX_PATH` 设为内置 `codex` 二进制的完整路径。

## Notes

- Touch Bar display uses macOS private Touch Bar APIs. If your Mac does not have Touch Bar, or the API is unavailable, the floating capsule still works.
- Touch Bar display also depends on the macOS `Touch Bar shows: App Controls` setting.
- This is an unofficial personal tool and is not affiliated with OpenAI.
- The Codex internal app-server protocol may change in future releases.
- Released under the MIT License.

## 注意事项

- Touch Bar 展示使用了 macOS 私有 Touch Bar API；没有 Touch Bar 的 Mac 或系统不支持时，桌面胶囊仍然可用。
- Touch Bar 展示也依赖 macOS 的 `触控栏显示：App 控制` 设置。
- 这是一个非官方个人工具，不代表 OpenAI。
- Codex 本机 `app-server` 的内部协议未来可能变化。
- 项目使用 MIT License 开源。

## Credits

The Touch Bar quota display idea is inspired by 小红书 creator **@Fly**，小红书 ID：`26872565825`.  
This project adapts that idea into a local floating capsule plus Touch Bar helper.

## 致谢

Touch Bar 额度条的创意来自小红书作者 **@Fly**，小红书 ID：`26872565825`。  
这个项目是在原有桌面胶囊小工具基础上的本地化改造与实现。
