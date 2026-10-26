# MacPhoneKeys · 手机键盘

**中文** | [English](README.en.md)

<img src="Resources/AppIcon.png" width="112" alt="MacPhoneKeys 图标">

用 Mac 上的键盘，通过蓝牙给 iPhone 打字。两台设备可以登录不同的 Apple ID；iPhone 无需安装 App。

旧版实测已确认 Mac 自带键盘，以及连接到 Mac 的外接蓝牙键盘，都可以作为输入来源。USB 键盘尚未实测。

作者：**九福爸爸 9fbaba**。

这是一个原生 macOS App，使用 Swift、AppKit 和 CoreBluetooth。默认常驻菜单栏，不占 Dock。左键点击菜单栏图标，或按全局快捷键 **Control + Option + K**，即可切换手机输入，并在开始捕获时显示简短的输入提示面板。按 **Esc**、再次点击图标或切换到其他窗口，都会停止输入并尝试释放按键。

当前版本为 **0.4.0 (6)**。App 支持简体中文、繁体中文和英文，会根据 Mac 的首选语言自动选择界面；[完整英文指南](README.en.md)提供英文安装与连接说明。

## 界面语言

App 使用标准 macOS Bundle 语言资源：`en`、`zh-Hans` 和 `zh-Hant`。macOS 会从 Mac 的首选语言中选择 App 支持的语言；没有匹配语言时使用英文。中文名称为“手机键盘”，英文名称为 **MacPhoneKeys**。

可以调整 Mac 的首选语言；如果系统提供 App 专用语言设置，也可以在“系统设置 → 通用 → 语言与地区 → 应用程序”中为本 App 单独选择语言。更改后请完全退出 App，再重新打开；界面不会在运行中即时切换。不同 macOS 版本的设置位置可能不同。

界面语言与 iPhone 的输入法、硬件键盘布局分别设置。切换 App 界面语言不会改变手机的输入语言。

## 当前状态

已在一台运行 **macOS 26.6.2** 的 Apple 芯片 Mac 与一台 iPhone 上实测：

- iPhone 建立了加密键盘连接。
- 固定测试串 `mac keyboard test 123` 完整显示。
- 用户使用 Mac 实体键盘手动输入 `abc123`，手机完整显示。
- 安装到“应用程序”后的版本也已确认可以打字。

上述手机输入记录来自 **0.2.0**。本次 **0.4.0 (6)** 的菜单栏界面只在本地预览和离线回归范围内验证，尚未进行新版手机端输入实测；现有 **0.2.0** 安装版保持不动。旧版手机实测结果不能代替新版菜单栏流程的端到端验证。

构建目标为 **macOS 12.0 及以上**，生成包含 **arm64 和 x86_64** 的 Universal App。这个目标表示二进制的架构与最低系统版本，**不代表所有 Mac 和 iPhone 均已验证兼容**。Intel Mac、其他 macOS 版本、其他 iPhone、中文选字及睡眠后重连仍需实测。

## 获取源码

```sh
git clone https://github.com/willrong1971/MacPhoneKeys.git
cd MacPhoneKeys
```

也可以选择 **Code → Download ZIP**，解压后在终端进入工程目录。

## 编译与安装

需要 macOS，以及提供 Swift 编译器和 macOS SDK 的近期 Xcode 或 Xcode Command Line Tools。项目没有第三方包依赖。

构建：

```sh
zsh build.sh
```

输出文件路径固定为 `build/手机键盘.app`，不随界面语言变化。在 Finder 中把它拖入“应用程序”，再从“应用程序”中打开。英文界面中的 App 名称为 MacPhoneKeys。为避免混淆连接状态，使用时只运行一份 App。

首次运行时允许蓝牙访问。如果此前拒绝，可以在系统的隐私设置中为本 App 开启蓝牙权限。

### 签名与公证

脚本默认使用 **ad-hoc 签名**，适合本地构建；仓库不包含开发者证书、私钥或公证凭据。可以通过环境变量 `MACPHONEKEYS_SIGN_IDENTITY` 指定自己钥匙串中的签名证书完整名称。

**本项目的构建脚本不自动提交 Apple 公证。** 下载的未公证 App 在其他 Mac 上可能被 Gatekeeper 阻止。请先确认来源，再按 macOS 为该 App 提供的“仍要打开”等提示操作；不要关闭全局安全保护。Apple Development 开发签名也不等同于 Developer ID 公证发行。

正式对外分发安装包，需要发行者自行完成合适的签名与公证。参见 [Apple Developer ID 说明](https://developer.apple.com/developer-id/)。

## 连接 iPhone

1. 打开 Mac 上的“手机键盘”，找到“手机键盘”的菜单栏图标，等待蓝牙键盘服务启动。默认不会显示 Dock 图标或完整设置窗口。
2. 在 iPhone 打开“设置 → 蓝牙”，选择这台 **Mac 的系统名称**，按系统提示完成配对。列表中的名称可能不是 App 名称。
3. 在 iPhone 的备忘录等 App 中点一下文字输入位置，确认光标闪烁。
4. 连接就绪后，左键点击 Mac 菜单栏图标，或按 **Control + Option + K**。输入提示面板出现后，用 Mac 键盘打字。
5. 按 **Esc**、再次点击菜单栏图标，或切到其他 Mac 窗口，停止输入并尝试释放按键。

### 菜单栏与快捷键

- **实心图标**表示正在向 iPhone 输入；**灰色轮廓图标**表示本机输入。图标的填充状态不是蓝牙配对成功或手机已显示文字的证明。
- 左键点击图标切换手机输入；右键打开菜单，可选“开始手机输入”／“停止手机输入”、“完整设置…”、帮助或退出 App。
- 默认全局快捷键为 **Control + Option + K**。如快捷键被其他程序占用，App 会提示冲突；仍可使用菜单栏图标和菜单。
- 简短的输入提示面板只在捕获输入期间出现。退出捕获后，按键交回 Mac 正常使用。

在右键菜单中打开完整设置，可以继续使用配对、连接诊断、连接记录、英文测试和手机输入法切换等功能。诊断入口供排查使用，默认 BLE 工作流程无需切换到传统蓝牙。

完整设置中的“开始输入”按钮也会打开简短输入面板；仍可直接点击完整设置里原有的输入区，在该输入区内捕获按键。

可以在完整设置中使用“发送英文测试串”检查手机是否实际显示文字。“已接收按键”包含本地等待发送的报告；计数增长不能代替手机画面的确认。

### 中文输入

App 发送硬件键盘按键，由 **iPhone 的硬件键盘输入法**组词、选字。Mac 输入法已经组好的中文不会作为整段文字传过去。完整设置中的“切换手机输入法”按钮发送 `Control + Space`；切换后重新点击菜单栏图标或按全局快捷键开始输入。中文输入流程尚未完成实机验证。

物理键码按 ANSI 布局映射，英文测试串按 US-ANSI 组合发送。其他语言、ISO／JIS 布局和额外硬件按键尚未建立兼容清单；iPhone 当前的硬件键盘布局也会影响最终字符。

## 制作 DMG

重新构建并制作带“Applications”快捷方式的安装盘：

```sh
zsh package.sh
```

输出为 `build/手机键盘-0.4.0-通用版.dmg`。脚本检查 Universal 架构和 App 签名，并验证磁盘映像，不会自动上传或公证。

安装盘同时附带中文、英文安装使用说明和 MIT 许可证，方便不同语言的用户安装与使用。

也可以打包已经构建的 App，避免重复编译：

```sh
zsh package.sh build/手机键盘-0.4.0-通用版.dmg build/手机键盘.app
```

目前打包脚本对应 `0.4.0 (6)`。修改版本号时，需要同步调整 `Resources/Info.plist` 与打包脚本的版本检查。

## BLE 实验范围

默认后端是 HID over GATT（低功耗蓝牙）。当前实机成功的实现使用完整 Bluetooth Base UUID 表达注册 HID、Battery 和 Device Information 服务，并用短 HID UUID 广播。

macOS 会保留部分标准 GATT 服务；普通短 UUID 注册在本机曾被系统拒绝。当前完整 UUID 表达虽然在本机有效，但没有跨设备、跨系统版本的兼容性保证。服务注册或广播成功，也不等于 iPhone 已识别并接受键盘。

另外：

- Battery 服务固定报告 **100%**，仅为实验占位，不代表 Mac 实际电量。
- PnP 厂商字段采用实验占位值，不声明任何已注册厂商身份。
- 源码保留传统蓝牙后端供诊断；其可靠性尚未得到实机验证。默认使用 BLE。
- 停止输入会清空尚未提交给系统的报告并尝试释放按键；已经交给系统蓝牙栈的字符无法撤回。

如果连接失败，先确认只运行一份 App，并查看 App 的连接记录。报告问题时请附上 macOS／iOS 版本、Mac 架构、失败步骤及必要的错误信息；去掉设备名称、地址、账户等个人信息。不要仅凭按钮计数报告输入成功。

## 检查与源码结构

以下检查在本机运行，不连接手机、不操作蓝牙：

```sh
zsh scripts/check.sh
```

检查覆盖语言选择与资源完整性、键码映射、BLE 发送队列的顺序与取消行为，以及传统蓝牙 SDP 数据。各项检查的编译命令由脚本维护。这些检查无法替代蓝牙配对、手机输入和重连的实机验证。

开发时可在构建后生成独立的界面预览：

```sh
python3 scripts/make-localization-previews.py build/手机键盘.app
```

预览副本位于 `build/localization-previews/`，使用独立的 App 身份、临时日志目录和隔离的 `PreviewKeyboardTransport`，不启动任何蓝牙管理器，也不发送到手机。可以在预览中测试界面文字与布局、焦点、全局快捷键、图标状态和本地按键接收计数。这些预览仅供界面和本地按键路由验证，不能验证 iPhone 文字显示，也不应作为安装版分发。

修改简体翻译后，可用 `xcrun swift scripts/generate-traditional-localization.swift` 更新繁体资源值，再审阅生成结果。资源的查找键始终保留不变。

| 路径 | 内容 |
| --- | --- |
| `Sources/main.swift` | 本地化菜单栏、完整设置、输入提示面板与前台键盘事件 |
| `Sources/MenuBarController.swift` | 菜单栏图标、左右键操作与菜单 |
| `Sources/GlobalHotKey.swift` | 全局输入切换快捷键与冲突处理 |
| `Sources/KeyMapping.swift` | Mac 键码到 HID 键码的映射 |
| `Sources/BLEKeyboard.swift` | BLE HID 服务与有界发送队列 |
| `Sources/BluetoothKeyboard.swift` | 传统蓝牙诊断后端 |
| `Tests/` | 不连接设备的检查 |
| `Resources/` | App 信息、图标、安装说明，以及 `en`／`zh-Hans`／`zh-Hant` 语言资源 |
| `scripts/generate-icon.swift` | 原创几何图标的重建脚本 |

重建图标：

```sh
xcrun swift scripts/generate-icon.swift
```

App 仅在主动开启捕获，且输入提示面板或完整设置的输入区获得焦点时接收要转发的按键，不申请辅助功能或输入监控权限，不读取 Apple 账户、剪贴板或通讯录，输入不经过 iCloud 或网络。全局快捷键用于切换捕获状态。连接记录仅保存连接事件、错误和计数，不保存输入内容。

## English overview

MacPhoneKeys is an experimental native macOS menu bar app that lets a Mac keyboard type on an iPhone over Bluetooth Low Energy. Click its menu bar icon or press Control + Option + K to toggle input. The devices may use different Apple IDs, and no iPhone app is required.

The app supports English, Simplified Chinese and Traditional Chinese, selected from the Mac's preferred supported languages, with English as the fallback. Quit and reopen the app after changing its language. Read the [complete English guide](README.en.md) for building, installation, pairing, controls, troubleshooting and compatibility limits.

## 许可

采用 [MIT License](LICENSE)，允许任何人使用、修改、编译和分发，具体条件见许可证。
