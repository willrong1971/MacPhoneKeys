# Mac App Store 发行准备

检查日期：2026-10-30。作者：九福爸爸 9fbaba。

本文件记录发行要求与待验证事项，不表示 App 已通过审核、已上传、已经公证或已完成沙盒真机验证。当前正常使用的安装版应继续保留，候选版另行验证。

## 两种交付物

| 交付方式 | 本地可以准备 | 正式交付还需完成 |
| --- | --- | --- |
| 直接下载 | Universal App、DMG、中文与英文说明、校验值 | Developer ID Application 签名、公证、干净安装验证 |
| Mac App Store | 沙盒候选 App、权限与隐私清单、商店资料草案 | 本项目 App ID、App Store 配置描述文件、发行签名、App Store Connect 记录、上传处理和审核 |

DMG 是直接分发安装盘。商店版本通过 Xcode 提供的发行技术打包上传，用户随后从 Mac App Store 安装。两者的构建和验收状态分别记录。[Apple 发行准备](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)、[上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

本机只读检查发现可用签名身份是 Apple Development，未发现本项目对应的 Mac App Store 配置描述文件。其他项目的证书或配置描述文件不能替代本项目的匹配配置。此次没有创建证书、读取私钥、操作开发者账户或上传软件。

Apple 说明：只使用不受限制权限的纯 Mac App，提交商店时可能不需要配置描述文件；TestFlight 始终需要。本项目的正式检查选择统一要求显式应用标识和匹配的商店配置描述文件，便于保持 App Store／TestFlight 发行配置一致。这是本项目的构建策略，不是对所有 Mac App 的通用要求。[TN3125：Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

## 构建与本地检查

沙盒候选构建可以使用本地开发签名或 ad-hoc 签名，供本机验证。候选检查只检验包结构、Universal 架构、严格签名、最小权限和隐私清单，不会把它标成可提交包：

```sh
MACPHONEKEYS_BUILD_VARIANT=appstore zsh build.sh build/store-candidate/手机键盘.app
zsh scripts/validate-appstore.sh build/store-candidate/手机键盘.app --candidate
```

正式构建需要先配置本项目的 App Store 发行身份和匹配的配置描述文件。下列变量应从本机钥匙串和受保护文件路径提供，敏感材料不进入仓库：

```sh
export MACPHONEKEYS_BUILD_VARIANT=appstore
export MACPHONEKEYS_SIGN_IDENTITY='Apple Distribution: YOUR_NAME (TEAM_ID)'
export MACPHONEKEYS_PROVISIONING_PROFILE='/absolute/path/to/MacPhoneKeys-Store.provisionprofile'
zsh build.sh build/store-release/手机键盘.app
zsh scripts/validate-appstore.sh build/store-release/手机键盘.app
export MACPHONEKEYS_INSTALLER_SIGN_IDENTITY='3rd Party Mac Developer Installer: YOUR_NAME (TEAM_ID)'
zsh scripts/package-appstore.sh build/store-release/手机键盘.app
```

正式检查还验证 Apple 证书链、发行证书类型、应用标识、团队、配置描述文件有效期、证书匹配，以及没有设备列表或调试权限。打包脚本通过 `productbuild` 制作单 App 的签名 PKG，并执行 `pkgutil --check-signature`。缺少发行凭据时脚本明确失败，不生成未签名的商店包；已有输出不会被覆盖。

这些命令不上传构建、不修改开发者账户，也不会安装生成的包。本地检查通过后，仍需 Apple 的上传验证、沙盒真机测试与审核。[证书类型](https://developer.apple.com/help/account/certificates/certificates-overview/)、[发行签名与打包](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)

## 已准备的权限与隐私文件

`Resources/MacAppStore.entitlements` 只申请以下权限：

- App Sandbox：商店版本必需。
- Bluetooth：通过系统蓝牙框架提供键盘服务。
- 用户选择文件的读写：通过系统保存面板导出诊断文件。

没有申请网络、USB、摄像头、麦克风、辅助功能、输入监控或文件系统例外。用户键盘事件只由本 App 的前台输入窗口接收；全局快捷键只切换输入状态。[沙盒配置](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)、[Bluetooth 权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth)、[用户选择文件权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)

`Resources/PrivacyInfo.xcprivacy` 声明无跟踪、无开发者数据收集，并为本 App 自有偏好使用 UserDefaults 声明 `CA92.1`。该声明依据当前没有统计 SDK、广告 SDK 或自动上传的实现。诊断保存在本机，导出由用户发起；发送到配对手机的按键用于实时输入，不保存输入内容。后续若增加自动上传、账号或第三方 SDK，必须重新核对清单和 App Store 隐私回答。[必需原因 API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)、[App 隐私说明](https://developer.apple.com/app-store/app-privacy-details/)

构建脚本需要将隐私清单复制到 `.app/Contents/Resources/PrivacyInfo.xcprivacy`，并用权限文件签名。单独存在这两份源文件不代表构建产物已启用沙盒。

## 必须用候选版验证的技术边界

| 项目 | 已知情况 | 商店候选版验收 |
| --- | --- | --- |
| BLE peripheral | CoreBluetooth 与 Bluetooth 沙盒权限均为公开接口 | 在沙盒内完成服务注册、实际广播、加密输入订阅和手机可见文字验证 |
| 系统配对窗口 | `IOBluetoothPairingController` 是公开 API，能显示搜索与配对窗口 | 确认沙盒内能找到目标手机、正常取消和完成配对；窗口成功不等于键盘订阅成功 |
| BLE HID 服务 | 实现使用标准 HID UUID `1812` 的完整 128 位表达 | 必须实测当前系统；没有找到 Apple 对依赖 UUID 表达长度差异注册行为的支持承诺 |
| 菜单栏 App | `LSUIElement` 是公开的 agent App 配置 | 菜单、完整设置、帮助、退出、首次连接向导均可发现和使用 |
| 快捷键 | 当前使用公开的 `RegisterEventHotKey`，默认包含 Control 修饰键 | 在沙盒内验证注册、冲突提示、开始/停止与失焦释放；不扩展为全局按键监听 |
| 文件和偏好 | 沙盒 App 的应用支持目录位于自身容器内 | 验证本地日志、设置持久化和系统保存面板导出；验证升级时的偏好行为 |

Apple 将短 UUID 和完整 UUID 定义为同一标识；完整 `00001812-0000-1000-8000-00805F9B34FB` 不是自定义服务。当前实现能在本机工作，尚不足以承诺所有系统均支持这一发布方式。[CBUUID](https://developer.apple.com/documentation/corebluetooth/cbuuid)

Apple 的公开配对窗口说明没有保证其会修复本次出现的 BLE 入站“没有处理程序”错误。因此应通过公开接口进行对照验证，不能依赖系统助理的内部进程名、私有启动参数、自动确认配对码或关闭加密。[系统配对窗口](https://developer.apple.com/documentation/iobluetoothui/iobluetoothpairingcontroller)、[系统配对结果](https://developer.apple.com/documentation/iobluetoothui/iobluetoothpairingcontroller/getresults%28%29)

`LSUIElement` 本身不表示不能提供前台界面。快捷键也存在系统版本行为差异，仍需逐版本实测。[Launch Services Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)、[Apple 关于快捷键修饰键的说明](https://developer.apple.com/forums/thread/763878)

## 一人验收

不再以招募五位试用者作为当前交付条件。由作者在现有 Mac 与 iPhone 上完成下列记录，并明确兼容范围只有实际测试的设备和系统组合。

1. 在保留正常安装版的前提下，先完成候选版离线检查及独立界面预览。
2. 单独运行候选版，验证首次向导、系统配对窗口取消、已配对重连和英文短串。每项区分本地日志与手机实际结果。
3. 验证完整设置关闭、提示浮窗关闭、快捷键切换、Esc、切到其他 Mac App 后停止，无卡键或恢复后补发旧输入。
4. 记录 App 退出重开、Mac 睡眠唤醒、手机离开再回来、手机蓝牙关闭开启等场景；日常重连无需删除配对记录。
5. 连续使用至少七天，记录失败次数、恢复步骤与耗时。尚未执行的项保留“待测”，不填写成功率。
6. 沙盒候选版独立完成同一组蓝牙与输入验证，不能沿用非沙盒版的结果。

这是一人测试计划，尚不是已完成的验收记录。当前设备以外的兼容性应通过发布说明明确标注，后续随真实反馈扩大。

## App Store Connect 待完成事项

- 在当前开发团队确认 `local.will.MacPhoneKeys` 可注册并创建对应的显式 App ID；正式商店 App 创建后保持标识稳定。
- 配置匹配本项目的 Mac App Store 发行签名和配置描述文件；不要复用其他项目的文件。敏感凭据不进入 Git。
- 创建 App Store Connect 的 macOS App 记录，设置版本、构建号、类别、年龄分级、地区和价格。
- 提供中英文名称、准确的功能与兼容范围、真实截图、支持 URL、隐私政策 URL、版权和审核联系方式。
- 审核备注说明菜单栏入口、全局快捷键、停止方式、需要另一台 iPhone 完成的步骤，以及无需更换 Apple ID、无需安装 iPhone App。
- 按实际使用的加密回答出口合规问题；不要为省略表单而直接写入未经核实的豁免声明。
- 通过 Xcode 或 Transporter 验证和上传；处理 Apple 返回的错误及警告，再提交审核。

App Store Connect 的开发者显示名称依账户注册资料确定，版权文字不能替代法定提供者信息。Apple 最终审核决定是否接收本实现。

商店最终提交需要完整、可用的产品；不以 beta/demo 名称绕过稳定性验收。开发阶段可继续提供明确标注的直接下载候选版，具备发行配置后也可使用 TestFlight。[App Review Guidelines 2.1、2.2、2.4.5、2.5.1](https://developer.apple.com/app-store/review/guidelines/)、[App Store 工作流程](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow)、[配置描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)

正式发行前还应完成 Developer ID 路线的签名和公证，供商店以外下载使用。[Developer ID](https://developer.apple.com/developer-id/)、[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
