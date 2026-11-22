# iScreenBar Menu

[English](README.md) · 简体中文

**Screen and Light Controller：灯光、双屏联动与 Mac 辅助控制，集中在菜单栏。**

最初是为 Studio Display 补上 iScreenBar 熄屏同步，现在加入亮度联动、环境光规则、自动色温与内屏管理。非官方独立项目，与 BenQ、Apple 无隶属关系。最新版源码继续在这个原仓库以 MIT 许可证公开。

## 界面与功能

详见 [截图使用指南](docs/UI-GUIDE.zh-CN.md) · [完整功能清单](docs/FEATURES.zh-CN.md)。

| 模块 | 功能 |
| --- | --- |
| 快捷控制 | 灯光、自动感光、入座检测、视频模式、亮度跟随、熄屏同步、自动色温、双屏亮度、防止休眠 |
| 灯光调节 | 亮度与 2700–6500K 色温，支持物理操作后的状态回读 |
| 亮度联动 | 保留当前亮度差，实现 MacBook ↔ Studio Display → iScreenBar 联动 |
| 环境光标定 | 使用 Studio Display 传感器，分别保存明亮关灯、昏暗开灯阈值 |
| 自动色温 | 按时间变化，白天偏冷、夜间偏暖；不是测量环境色温 |
| 内屏管理 | 内屏开关、0°/90°/270° 旋转、5 秒确认回退、外屏断开恢复 |
| Studio Display 按钮 | 黑色遮罩，保持窗口布局；**不关闭背光，不等同于硬件节电** |
| 预设 | 保存灯光模式、按前台应用切换模式；独立保存旋转预设 |

图标黄色表示灯亮，灰色表示灯灭，红色提示异常；悬停显示亮度和色温。App 不占 Dock 位置。

- **左键点击**图标打开标准菜单：灯光、亮度、色温、台灯模式、环境光规则、显示器（内屏开关、0°/90°/180°/270° 旋转、Studio Display、旋转预设）、我的最爱、防止休眠、控制面板…、登录时启动、帮助…（帮助窗口，跟随系统浅色/深色外观）、退出。
- **右键点击**（或按住 Control 点击）图标打开完整控制面板，右下角有**退出**按钮。

界面支持英文和简体中文，跟随 macOS 语言设置。若只想让本 App 使用中文，可在“系统设置 › 通用 › 语言与地区 › 应用程序”中选择，然后重启 App。

## 安装

已测试：Apple Silicon MacBook Pro、macOS 26、Studio Display、BenQ iScreenBar（USB VID 0x04A5 / PID 0x2501）。其他系统和设备尚未全面验证。

需要完整的 Xcode 26 或更高版本（仅安装 Command Line Tools 不够）。从 App Store 安装 Xcode 后运行：

```bash
sudo xcode-select -s /Applications/Xcode.app
git clone https://github.com/rogerbush007-a11y/iScreenBar-StudioDisplay-Sync.git
cd iScreenBar-StudioDisplay-Sync
./scripts/install.sh
```

脚本使用 Xcode 工程本机编译、临时签名，安装到 `~/Applications/iScreenBar Menu.app`，创建用户级 LaunchAgent，登录后自动运行。菜单中的**登录时启动**可开关该 LaunchAgent。退出 App 后在下次登录前保持退出，launchd 只在崩溃后重启。若安装过旧版本，请重新运行 `./scripts/install.sh`（或注销后重新登录），以免退出后被自动重新启动。安装无需管理员密码；防止休眠的强制层另需管理员授权。

### 不使用脚本安装

1. 在 Xcode 中构建，或运行 `./scripts/build.sh`，得到 `build/iScreenBar Menu.app`。
2. 将 `iScreenBar Menu.app` 拖到 `/Applications` 或 `~/Applications`。
3. 在访达中打开一次。这样快捷指令和控制中心也能找到它。
4. 左键点击菜单栏图标，选择**登录时启动**。这会写入与脚本相同的 LaunchAgent，指向 App 当前所在位置。

与脚本不同，这样不会立即启动 LaunchAgent，而是在下次登录时生效；在此之前不会写入 `~/Library/Logs/iScreenBarMenu.log`。之后若移动了 App，请关闭再重新打开“登录时启动”。运行 `build/` 中的副本时不要开启“登录时启动”，否则每次登录都会启动该副本。若仍有使用 `local.qiu.iScreenBarStudioSync` 的旧版本在运行，请注销并重新登录一次。

### 从 iScreen Menu（0.4 及更早版本）升级

0.5 版将 App 从 **iScreen Menu** 更名为 **iScreenBar Menu**（Bundle ID `org.windholm.iScreenBarMenu`）。运行 `./scripts/install.sh` 会停止旧 App，将 `~/Applications/iScreen Menu.app` 移到废纸篓，并移除其 `org.windholm.iScreenMenu` LaunchAgent。首次启动时，App 会从旧名称复制设置（我的最爱、旋转预设、阈值等），并替换旧的“登录时启动”项。以下内容需要手动更新：

- 控制中心：移除旧的 iScreen Menu 控制项，再从 iScreenBar Menu 重新添加。
- AppleScript：将 `tell application "iScreen Menu"` 改为 `tell application "iScreenBar Menu"`。
- 快捷指令：将 iScreen Menu 的操作替换为 iScreenBar Menu 的操作。
- 日志改为 `~/Library/Logs/iScreenBarMenu.log`；旧的 `iScreenMenu.log` 可以删除。

日常灯控直接通过 USB HID 执行，不依赖官方 App。建议避免两个软件同时自动写入灯光设置。相机自动视频模式和灯体硬件记忆尚未完全对齐，不宣称完整替代官方所有功能。

## 使用规则

- 亮度跟随与灯体自动感光互斥，关闭跟随后保留当前亮度。
- 环境光采用近 10 秒中位数。明亮关灯约 30 秒，达到昏暗开灯点约 30 秒；环境关灯后的渐进回开约 45 秒。带回差与持续时间判断，不是越过数值就立即切换。
- 旋转预设开启：连接 Studio Display 时应用保存角度。关闭：回到 0°，重新连接也请求保持 0°。
- 外屏断开请求强制恢复内屏。一般显示配置操作避开锁屏/唤醒切换，断开恢复是例外。
- 防止休眠使用 caffeinate 和管理员授权的 pmset disablesleep，关闭或退出后尝试释放。请实际验证本机合盖、锁屏与恢复行为。

## 自动化

iScreenBar Menu 可通过 AppleScript、快捷指令以及（macOS 26 上的）控制中心操作。每项设置的效果与控制面板按钮完全相同，限制也相同：灯光设置需要连接 iScreenBar，Mac 锁定时无法调整显示器，开启防止休眠需要输入管理员密码。App 必须在运行；若未运行，快捷指令和 AppleScript 会自动启动它。

**AppleScript。** 在“脚本编辑器”中打开词典（文件 › 打开词典… › iScreenBar Menu）。属性：`light`、`brightness`（1–100）、`color temperature`（2700–6500 K，需先关闭自动色温）、`auto temperature`、`auto light`、`presence`、`video mode`、`match screen`、`link screens`、`sleep sync`、`keep awake`、`builtin display`，以及只读的 `lamp connected`、`lamp status`、`favorites`、`rotation preset`。命令：`toggle light`、`apply favorite "名称"`、`apply rotation preset`、`show control panel`。AppleScript 术语为英文。其他 App 首次发送命令时，macOS 会请求“自动化”权限。

```applescript
tell application "iScreenBar Menu"
    set brightness to 60
    set color temperature to 4000
    apply favorite "Night Work"
    get lamp status -- "Light on · 60% · 4000K"
end tell
```

**快捷指令。** 操作：设置灯光、开启或关闭设置、获取设置、设置灯光亮度、设置色温、应用我的最爱、应用旋转预设、显示控制面板、获取灯光状态。切换灯光、应用我的最爱、灯光状态、旋转预设和控制面板也作为现成快捷指令提供给聚焦和 Siri。

**控制中心（macOS 26）。** 在“控制中心 › 编辑控制 › iScreenBar Menu”中添加：台灯灯光、防止休眠、旋转预设、控制面板。它们是按钮而不是开关，不显示当前状态。控制项会通知正在运行的 App，因此 iScreenBar Menu 退出时不起作用。

## 验证与限制

```bash
./scripts/check.sh
tail -f ~/Library/Logs/iScreenBarMenu.log
launchctl print gui/$(id -u)/org.windholm.iScreenBarMenu
```

2026-10-05 的“关闭内屏后拔掉外屏恢复”已由使用者实际确认；2026-10-06 的旋转预设关闭回 0°已构建部署，仍待新一轮插拔验收。构建通过、系统状态回读不代表面板确实发光。

显示控制依赖 macOS 私有 SkyLight / MonitorPanel / DisplayServices 接口，系统升级后需要复测。USB 报文针对特定灯型，其他 ScreenBar 型号不保证兼容。虚拟分屏实验不属于当前正式功能。

## 卸载与开发

```bash
./scripts/uninstall.sh
# 仅构建，不安装：
./scripts/build.sh
```

卸载将 App 和 LaunchAgent 移至废纸篓，保留日志。构建产物位于 `build/iScreenBar Menu.app`。

开发时用 Xcode 打开 `iScreenBarMenu.xcodeproj`。工程由 `project.yml` 通过 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成；修改 `project.yml` 后运行 `xcodegen generate`，并同时提交两者。界面文字通过 `iScreenBarMenu/Localizable.xcstrings` 本地化（英文为源语言，含简体中文翻译）。默认使用临时签名；如需用自己的证书签名，请在不纳入 Git 的 `Config/Signing.local.xcconfig` 中设置（参见 `Config/Signing.xcconfig`）。

目前为本机临时签名，无 Developer ID 公证或自动更新。

源码无网络请求、分析或云端依赖。参见 [安全说明](SECURITY.md)、[商标声明](NOTICE.md)、[MIT 许可证](LICENSE)。
