# App Store 资料草案

作者版权：Copyright © 2026 九福爸爸 9fbaba. MIT License.

以下为候选构建的提交资料草案。尚未创建商店记录、上传或提交审核。仅在沙盒版完成真机输入验收后，按实际结果定稿。

## 简体中文

- 名称：手机键盘
- 副标题：用 Mac 键盘给 iPhone 打字
- 类别：工具
- 关键词：键盘,蓝牙,iPhone,输入,Mac,外接键盘,菜单栏
- 支持网址：https://github.com/willrong1971/MacPhoneKeys/issues
- 隐私政策：https://github.com/willrong1971/MacPhoneKeys/blob/main/docs/Privacy.zh-Hans.md

说明：

用 Mac 的键盘，通过蓝牙在 iPhone 上输入。两台设备可以登录不同的 Apple ID，iPhone 无需安装 App。

日常使用时，手机键盘常驻 Mac 菜单栏。点击图标或按 Control + Option + K，开启或停止手机输入。按 Esc 或切换到其他 Mac 窗口，也可停止输入。完整设置和输入提示浮窗可以关闭。

连接向导帮助你检查 Mac 蓝牙准备情况、打开系统配对窗口，并确认手机是否收到测试文字。连接异常时，可重建本 App 的键盘服务或主动导出诊断摘要。

输入由 iPhone 的硬件键盘布局和输入法处理。App 不记录输入内容，不申请辅助功能或输入监控权限，不通过互联网或 iCloud 传送按键。

需要支持蓝牙外围服务的 Mac 与 iPhone。首次使用需在手机蓝牙设置中选择 Mac 并按系统提示配对。已验证的具体设备与系统版本应随最终实测结果填写；最低编译版本不代表所有型号均已验证。

## English

- Name: MacPhoneKeys
- Subtitle: Type on iPhone from your Mac
- Category: Utilities
- Keywords: keyboard,Bluetooth,iPhone,typing,Mac,menu bar,external keyboard
- Support URL: https://github.com/willrong1971/MacPhoneKeys/issues
- Privacy policy: https://github.com/willrong1971/MacPhoneKeys/blob/main/docs/Privacy.en.md

Description:

Use your Mac's keyboard to type on an iPhone over Bluetooth. The devices can use different Apple IDs, and no iPhone app is required.

MacPhoneKeys stays in the Mac menu bar. Click its icon or press Control + Option + K to start or stop phone input. Esc or switching to another Mac window also stops input. Full settings and the input hint window can stay closed.

The connection assistant checks Mac Bluetooth preparation, opens a system pairing panel and helps you confirm that test text appeared on the phone. If a connection fails, you can rebuild the app's keyboard service or choose to export a diagnostic summary.

The iPhone's hardware-keyboard layout and input method determine the resulting text. MacPhoneKeys does not record typed text, request Accessibility or Input Monitoring access, or relay keys over the internet or iCloud.

Requires a Mac supporting Bluetooth peripheral services and an iPhone. On first use, select the Mac in the iPhone's Bluetooth settings and follow system pairing prompts. The final listing must name only device and OS combinations actually validated; the deployment target is not a universal compatibility claim.

## 审核备注草案

1. This is a native macOS menu bar app that provides a Bluetooth HID keyboard service to a user's iPhone. Review requires a nearby physical iPhone with Bluetooth enabled; no account or paid backend is used.
2. Launch the app and open Connect iPhone… from the menu bar menu. Keep Settings > Bluetooth open on the iPhone. Use the system pairing panel or select the Mac's system name on the phone. Confirm matching system pairing codes manually.
3. After encrypted keyboard input becomes ready, open an empty note on the iPhone and tap the body. Use an English/US hardware-keyboard layout for the initial literal test. Send the assistant's test, then confirm its visible result on the phone.
4. Close the settings window. Press Control + Option + K and type a short string. Press the shortcut again or Esc to stop. Switching to another Mac app also stops capture. Keyboard events are received only by this app's own focused window.
5. The sandbox build requests Bluetooth and user-selected-file access. Export Diagnostics uses NSSavePanel and produces fixed state/event summaries. There is no automatic upload, tracking SDK or global keyboard monitor.
6. Final reviewer notes must include the tested macOS/iOS versions, exact candidate build, any known limitations, and real screenshots. Do not claim that a successful pairing panel proves phone typing.

## 提交前由账户持有人确定

- App Store Connect 的 App 记录及开发团队、本项目 Bundle ID 与发行配置。
- 提供者显示名称按开发者账户资料决定；作者版权文字仍为九福爸爸 9fbaba。
- 价格、发布地区、年龄分级、审核联系人、出口合规回答及实际隐私问卷。
- 真实的商店截图；隐私和支持 URL 发布后可访问。
- 最终通过沙盒真机验证的构建，以及提交和发布时机。

本草案不自动提交任何声明，不签署协议，也不表示 Apple 已批准本实现。
