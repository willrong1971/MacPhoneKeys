# MacPhoneKeys · 手机键盘

<img src="Resources/AppIcon.png" width="112" alt="MacPhoneKeys 图标">

用 Mac 自带键盘，通过蓝牙给 iPhone 打字。两台设备可以登录不同的 Apple ID；iPhone 无需安装 App。

作者：**九福爸爸 9fbaba**。

这是一个原生 macOS App，使用 Swift、AppKit 和 CoreBluetooth。输入仅在 App 前台的输入区中接收，按 **Esc** 或切换到其他窗口即可停止。

## 当前状态

已在一台运行 **macOS 26.6.2** 的 Apple 芯片 Mac 与一台 iPhone 上实测：

- iPhone 建立了加密键盘连接。
- 固定测试串 `mac keyboard test 123` 完整显示。
- 用户使用 Mac 实体键盘手动输入 `abc123`，手机完整显示。
- 安装到“应用程序”后的版本也已确认可以打字。

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

输出为 `build/手机键盘.app`。在 Finder 中把它拖入“应用程序”，再从“应用程序”中打开。为避免混淆连接状态，使用时只运行一份 App。

首次运行时允许蓝牙访问。如果此前拒绝，可以在系统的隐私设置中为本 App 开启蓝牙权限。

### 签名与公证

脚本默认使用 **ad-hoc 签名**，适合本地构建；仓库不包含开发者证书、私钥或公证凭据。可以通过环境变量 `MACPHONEKEYS_SIGN_IDENTITY` 指定自己钥匙串中的签名证书完整名称。

**本项目的构建脚本不自动提交 Apple 公证。** 下载的未公证 App 在其他 Mac 上可能被 Gatekeeper 阻止。请先确认来源，再按 macOS 为该 App 提供的“仍要打开”等提示操作；不要关闭全局安全保护。Apple Development 开发签名也不等同于 Developer ID 公证发行。

正式对外分发安装包，需要发行者自行完成合适的签名与公证。参见 [Apple Developer ID 说明](https://developer.apple.com/developer-id/)。

## 连接 iPhone

1. 打开 Mac 上的“手机键盘”，等待蓝牙键盘服务启动。
2. 在 iPhone 打开“设置 → 蓝牙”，选择这台 **Mac 的系统名称**，按系统提示完成配对。列表中的名称可能不是 App 名称。
3. 在 iPhone 的备忘录等 App 中点一下文字输入位置，确认光标闪烁。
4. 等待 Mac 的“开始输入”按钮可用，点击后用 Mac 键盘打字。
5. 按 **Esc**，或切到其他 Mac 窗口，停止输入。

可以先使用“发送英文测试串”按钮检查手机是否实际显示文字。“已接收按键”包含本地等待发送的报告；计数增长不能代替手机画面的确认。

### 中文输入

App 发送硬件键盘按键，由 **iPhone 的硬件键盘输入法**组词、选字。Mac 输入法已经组好的中文不会作为整段文字传过去。“切换手机输入法”按钮发送 `Control + Space`；切换后重新点击“开始输入”。中文输入流程尚未完成实机验证。

## 制作 DMG

重新构建并制作带“Applications”快捷方式的安装盘：

```sh
zsh package.sh
```

输出为 `build/手机键盘-0.2.0-通用版.dmg`。脚本检查 Universal 架构和 App 签名，并验证磁盘映像，不会自动上传或公证。

也可以打包已经构建的 App，避免重复编译：

```sh
zsh package.sh build/手机键盘-0.2.0-通用版.dmg build/手机键盘.app
```

目前打包脚本对应 `0.2.0 (4)`。修改版本号时，需要同步调整 `Resources/Info.plist` 与打包脚本的版本检查。

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

也可以分别运行：

```sh
mkdir -p build

xcrun swiftc Sources/KeyMapping.swift Tests/KeyMappingTests.swift \
  -o build/KeyMappingTests
./build/KeyMappingTests

xcrun swiftc -parse-as-library Sources/BLEKeyboard.swift \
  Tests/BLEInputReportQueueTests.swift -framework CoreBluetooth \
  -o build/BLEInputReportQueueTests
./build/BLEInputReportQueueTests

xcrun swiftc -D HID_SDP_TESTS -parse-as-library \
  Sources/BluetoothKeyboard.swift Tests/SDPTests.swift \
  -framework Foundation -framework IOBluetooth -o build/SDPTests
./build/SDPTests
```

检查覆盖键码映射、BLE 发送队列的顺序与取消行为，以及传统蓝牙 SDP 数据。这些检查无法替代蓝牙配对、手机输入和重连的实机验证。

| 路径 | 内容 |
| --- | --- |
| `Sources/main.swift` | App 界面与前台键盘事件 |
| `Sources/KeyMapping.swift` | Mac 键码到 HID 键码的映射 |
| `Sources/BLEKeyboard.swift` | BLE HID 服务与有界发送队列 |
| `Sources/BluetoothKeyboard.swift` | 传统蓝牙诊断后端 |
| `Tests/` | 不连接设备的检查 |
| `Resources/` | App 信息、图标和安装说明 |
| `scripts/generate-icon.swift` | 原创几何图标的重建脚本 |

重建图标：

```sh
xcrun swift scripts/generate-icon.swift
```

App 不申请辅助功能或输入监控权限，不读取 Apple 账户、剪贴板或通讯录，输入不经过 iCloud 或网络。连接记录仅保存连接事件、错误和计数，不保存输入内容。

## English overview

MacPhoneKeys is an experimental native macOS app that lets a Mac keyboard type on an iPhone over Bluetooth Low Energy. The devices may use different Apple IDs, and no iPhone app is required.

Author: **九福爸爸 9fbaba**.

Clone this repository, run `zsh build.sh`, and move `build/手机键盘.app` to Applications. Run `zsh package.sh` to build a DMG. Builds are Universal (`arm64` + `x86_64`) with a macOS 12.0 deployment target. Pair the iPhone with the Mac, focus a text field on the iPhone, then click the app's input button. Press Esc or switch windows to stop.

Physical typing has been confirmed on one Apple silicon Mac running macOS 26.6.2 and one iPhone, including the installed app. Other machines, OS versions and Chinese input remain unverified. The BLE implementation relies on behavior that may differ between macOS versions. Default builds are ad-hoc signed and are not automatically notarized; downloaded builds may trigger Gatekeeper warnings.

## 许可

采用 [MIT License](LICENSE)，允许任何人使用、修改、编译和分发，具体条件见许可证。
