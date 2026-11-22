# iScreenBar Menu

[English](README.md) · 简体中文

**菜单栏 App：让 BenQ iScreenBar 与 Apple Studio Display 保持同步，并管理 MacBook 内建显示器。**

Studio Display 休眠时，iScreenBar Menu 关闭台灯，唤醒时重新打开。它还可以让台灯跟随显示器亮度，借助 Studio Display 的传感器按室内光线开关台灯，并按时间调整色温；同时管理内建显示器（开关、旋转、拔出外屏后恢复）和防止休眠。台灯直接通过 USB 控制，无需 BenQ 官方 App。

本项目为非官方独立项目，与 BenQ、Apple 无隶属关系。最初派生自 rogerbush007-a11y 的 [iScreenBar-StudioDisplay-Sync](https://github.com/rogerbush007-a11y/iScreenBar-StudioDisplay-Sync)，以 MIT 许可证发布。

## 功能

详见 [使用指南](docs/UI-GUIDE.zh-CN.md) 和 [完整功能清单](docs/FEATURES.zh-CN.md)。

| 模块 | 功能 |
| --- | --- |
| 快捷控制 | 灯光、自动感光、入座检测、视频模式、亮度跟随、熄屏同步、自动色温、双屏亮度、防止休眠 |
| 灯光 | 亮度与色温（2700–6500K）；可回读在灯体上直接做的调整 |
| 熄屏同步 | Studio Display 休眠时关灯，唤醒后恢复 |
| 唤醒屏幕 | 可选：回到座位、灯体入座检测把灯打开时，同时唤醒休眠的 Studio Display |
| 亮度跟随 / 双屏亮度 | 台灯跟随 Studio Display 亮度；MacBook 与 Studio Display 亮度联动，保持你设定的差值 |
| 环境光规则 | 使用 Studio Display 光线传感器和你记录的两个阈值：室内明亮时**关灯**，昏暗时**开灯**。只开关台灯，不调暗 |
| 自动色温 | 按本地时间白天偏冷、夜间偏暖；不测量室内色温 |
| 内建显示器 | 开关；旋转（面板按钮按 0°/90°/270° 循环，菜单提供 0°/90°/180°/270°），5 秒内确认；拔出外接显示器时强制恢复。没有内建显示器且只连接 Studio Display 时隐藏 |
| Studio Display 按钮 | 黑色遮罩，窗口位置不变；**背光保持开启** |
| 我的最爱与模式中心 | 保存灯光设置，可按前台 App 自动切换；另有旋转预设，在连接 Studio Display 时应用 |
| 防止休眠 | 在关闭或退出前阻止系统休眠（需要管理员密码） |
| 自动化 | AppleScript、快捷指令、控制中心和桌面小组件（macOS 26 及更高版本） |

菜单栏图标黄色表示灯亮，灰色表示灯灭，红色表示需要处理的问题；悬停可查看亮度和色温。App 不显示 Dock 图标。

- **左键点击**图标打开完整控制面板，右下角有**关于…**、**帮助…**和**退出**按钮。
- **右键点击**（或按住 Control 点击）打开标准菜单：灯光、亮度、色温、台灯、环境光规则、显示器、我的最爱、防止休眠、控制面板…、登录时启动、帮助…、退出。

界面支持英文和简体中文，跟随 macOS 语言设置。若只想让本 App 使用中文，可在“系统设置 › 通用 › 语言与地区 › 应用程序”中选择，然后重启 App。

## 系统要求

- macOS 14 或更高版本的 Mac；控制中心控制项和小组件需要 macOS 26 或更高版本
- Apple Studio Display
- BenQ iScreenBar（USB VID 0x04A5 / PID 0x2501）。不支持其他 ScreenBar 型号

已在 Apple Silicon MacBook Pro（macOS 26 和 27）、Studio Display（包括固件 17.0）和 iScreenBar 上测试。其他配置尚未全面验证。

## 安装

### 下载（推荐）

1. 从 [Releases](https://github.com/hstriepe/iScreenBar-StudioDisplay-Sync/releases) 下载最新的 DMG。发布版本使用 Developer ID 签名，并经过 Apple 公证。
2. 打开 DMG，将 **iScreenBar Menu** 拖到 `/Applications`。
3. 在访达中打开一次 App。这样快捷指令和控制中心也能找到它。
4. 右键点击菜单栏图标，选择**登录时启动**。

“登录时启动”会添加一个指向 App 当前位置的用户级 LaunchAgent，在下次登录时生效；在此之前不会写入 `~/Library/Logs/iScreenBarMenu.log`。之后若移动了 App，请关闭再重新打开“登录时启动”。退出 App 后在下次登录前保持退出，launchd 只在崩溃后重启。

没有自动更新。更新时退出 App，用新版本替换即可。

### 从源码构建

需要完整的 Xcode 26 或更高版本（仅安装 Command Line Tools 不够）。

```bash
sudo xcode-select -s /Applications/Xcode.app
git clone https://github.com/hstriepe/iScreenBar-StudioDisplay-Sync.git
cd iScreenBar-StudioDisplay-Sync
./scripts/install.sh
```

脚本以临时（本机）签名构建 App，安装到 `~/Applications/iScreenBar Menu.app`，并立即创建和启动 LaunchAgent。无需管理员密码。

只构建不安装：运行 `./scripts/build.sh`（产物为 `build/iScreenBar Menu.app`）或在 Xcode 中构建，然后按上面第 2–4 步操作。运行 `build/` 中的副本时不要开启“登录时启动”，否则每次登录都会启动该副本。

### 从 iScreen Menu（0.4 及更早版本）升级

0.5 版将 App 从 **iScreen Menu** 更名为 **iScreenBar Menu**（Bundle ID `org.windholm.iScreenBarMenu`）。首次启动时，新 App 会从旧名称复制设置（我的最爱、旋转预设、阈值），并替换旧的“登录时启动”项。`./scripts/install.sh` 还会退出旧 App 并将 `~/Applications/iScreen Menu.app` 移到废纸篓；若通过 DMG 安装，请自行退出并删除旧 App。然后：

- 控制中心：移除旧的 iScreen Menu 控制项，再从 iScreenBar Menu 重新添加。
- AppleScript：将 `tell application "iScreen Menu"` 改为 `tell application "iScreenBar Menu"`。
- 快捷指令：将 iScreen Menu 的操作替换为 iScreenBar Menu 的操作。
- 日志改为 `~/Library/Logs/iScreenBarMenu.log`；旧的 `iScreenMenu.log` 可以删除。

若仍有使用 `local.qiu.iScreenBarStudioSync` 的更早版本在运行，请注销并重新登录一次。

## 使用

### 环境光规则

1. 打开控制面板（点击图标）。
2. 在不需要台灯时室内最亮的光线下，点击**明亮关灯**。
3. 在需要台灯时室内最暗的光线下，点击**昏暗开灯**。
4. 打开标题旁的**启用**。至少保存一个阈值后它才可用。

“环境光”数值是 Studio Display 传感器近 10 秒的中位数，是相对分数而非勒克斯。高于明亮关灯点约 30 秒后关灯，低于昏暗开灯点约 30 秒后开灯。因明亮而关灯后，室内稍暗于明亮关灯点约 45 秒也会重新开灯。两点之间不做切换。

环境光规则只开关台灯。若想让台灯随室内光线**调暗**，请将**亮度跟随**与 Studio Display 的自动亮度（系统设置 › 显示器）配合使用，或使用灯体自身的**自动感光**。亮度跟随与自动感光不能同时开启。

### 其他说明

- 熄屏同步优先：显示器休眠时，室内变暗也不会开灯。
- **唤醒屏幕**（入座检测设置标题旁的开关，或“台灯 › 入座时唤醒屏幕”）是唯一的例外。开启入座检测和熄屏同步后，显示器休眠期间入座检测保持运行；离席超过离席时间后回到座位、灯体自行开灯时，软件会唤醒显示器。Mac 已锁定时显示锁定屏幕，不会解锁。仅在显示器休眠时有效，整机睡眠时无效；它只根据灯被打开来判断，因此有人从侦测范围内经过也可能唤醒屏幕。若 10 秒内显示器未被唤醒，熄屏同步会重新关灯。环境关灯锁定期间入座检测保持暂停，不会唤醒。
- 关闭亮度跟随后，台灯保持当前亮度。
- 旋转预设开启时，每次连接 Studio Display 都会应用保存的角度；关闭时，内建显示器回到 0°，重新连接后也保持 0°。
- 拔出外接显示器时强制恢复内建显示器。除此之外，App 不会在锁屏、休眠或唤醒期间重新配置显示器。
- 防止休眠使用 `caffeinate` 和管理员授权的 `pmset disablesleep`，关闭或退出时释放。请在本机实际验证合盖和锁屏行为。
- 日常灯控不需要 BenQ 官方 App。请避免两者同时运行，因为两者都会写入灯光设置。相机联动的视频模式和灯体硬件记忆尚未完全对齐，本 App 不能替代所有官方功能。

## 自动化

iScreenBar Menu 可通过 AppleScript、快捷指令以及（macOS 26 及更高版本上的）控制中心操作。每项设置的效果与控制面板按钮完全相同，限制也相同：灯光设置需要连接 iScreenBar，Mac 锁定时无法调整显示器，开启防止休眠需要输入管理员密码。若 App 未运行，快捷指令和 AppleScript 会自动启动它。

**AppleScript。** 在“脚本编辑器”中打开词典（文件 › 打开词典… › iScreenBar Menu）。属性：`light`、`brightness`（1–100）、`color temperature`（2700–6500 K，需先关闭自动色温）、`auto temperature`、`auto light`、`presence`、`video mode`、`match screen`、`link screens`、`sleep sync`、`wake screen`、`keep awake`、`builtin display`，以及只读的 `lamp connected`、`lamp status`、`favorites`、`rotation preset`。命令：`toggle light`、`apply favorite "名称"`、`apply rotation preset`、`show control panel`。AppleScript 术语为英文。其他 App 首次发送命令时，macOS 会请求“自动化”权限。

```applescript
tell application "iScreenBar Menu"
    set brightness to 60
    set color temperature to 4000
    apply favorite "Night Work"
    get lamp status -- "Light on · 60% · 4000K"
end tell
```

**快捷指令。** 操作：设置灯光、开启或关闭设置、获取设置、设置灯光亮度、设置色温、应用我的最爱、应用旋转预设、显示控制面板、获取灯光状态。切换灯光、应用我的最爱、灯光状态、旋转预设和控制面板也作为现成快捷指令提供给聚焦和 Siri。

**控制中心（macOS 26 及更高版本）。** 在“控制中心 › 编辑控制 › iScreenBar Menu”中添加：台灯灯光、防止休眠、旋转预设、控制面板、台灯调暗 / 台灯调亮（每次 10%）、台灯调暖 / 台灯调冷（每次 500 K）。它们是按钮而不是开关，不显示当前状态。iScreenBar Menu 退出时不起作用。

**小组件（macOS 26 及更高版本）。** 通过“编辑小组件”（桌面或通知中心）添加**台灯亮度与色温**。它以两条各 10 格的条显示台灯的亮度和色温；点按某一格即设为该档（亮度 10–100%，色温 2700–6500 K），点按电源按钮可开关灯光。小组件不支持真正的滑块，因此是点按而不是拖动。开启自动色温时色温条不可用。iScreenBar Menu 退出时小组件会提示且不起作用。

## 故障排除与限制

```bash
tail -f ~/Library/Logs/iScreenBarMenu.log
launchctl print gui/$(id -u)/org.windholm.iScreenBarMenu
```

只有通过 LaunchAgent 运行时才会写入日志；从访达或 Xcode 打开的副本输出到各自的控制台。

- 显示控制使用 macOS 私有框架（SkyLight、MonitorPanel、DisplayServices），可能随系统更新而变化；缺少相关函数时 App 会安全回退并记录日志。
- Studio Display 固件 17.0 更改了显示器光线传感器的 USB ID。0.5 (39) 及更高版本兼容两种 ID；更早版本会显示环境光标定不可用。
- 台灯 USB 指令专用于 iScreenBar，不支持其他 ScreenBar 型号。
- 指令成功或状态回读成功，不代表台灯确实发生了变化。

## 卸载

```bash
./scripts/uninstall.sh
```

这会将 App 和 LaunchAgent 移到废纸篓，并保留日志。若通过 DMG 安装且没有仓库，请关闭“登录时启动”，退出 App，再将其移到废纸篓。

## 开发

用 Xcode 打开 `iScreenBarMenu.xcodeproj`。工程由 `project.yml` 通过 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成；修改 `project.yml` 后运行 `xcodegen generate`，并同时提交两者。提交前运行 `./scripts/check.sh`，CI 运行的也是这个脚本。界面文字通过 `iScreenBarMenu/Localizable.xcstrings` 本地化（英文为源语言，含简体中文翻译）。

源码构建默认使用临时签名。如需用自己的证书签名，请在不纳入 Git 的 `Config/Signing.local.xcconfig` 中设置（参见 `Config/Signing.xcconfig`）。

App 不发出网络请求，没有分析或云端依赖。参见 [安全说明](SECURITY.md)、[商标声明](NOTICE.md)、[贡献指南](CONTRIBUTING.md)、[MIT 许可证](LICENSE)。
