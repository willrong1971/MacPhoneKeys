# MacPhoneKeys · 手机键盘

[中文](README.md) | **English**

<img src="Resources/AppIcon.png" width="112" alt="MacPhoneKeys icon">

Use a keyboard connected to your Mac to type on an iPhone over Bluetooth. The devices may use **different Apple IDs**, and no iPhone app is required.

Author: **九福爸爸 9fbaba**.

**The app interface is currently in Chinese.** This guide provides English instructions and a [table of the actual Chinese controls](#chinese-ui-reference). It does not change the app's language.

Input from the Mac's built-in keyboard and an external Bluetooth keyboard connected to the Mac has been confirmed by the user. USB keyboards have not been tested. Connect an external keyboard to the Mac first; MacPhoneKeys forwards the keyboard events received by its own input area.

## Requirements and verification

- A Mac capable of operating as a Bluetooth Low Energy peripheral.
- macOS **12.0 or later** is the build's deployment target.
- An iPhone that can connect to the Mac as a Bluetooth keyboard.
- For source builds: a recent Xcode or Xcode Command Line Tools installation providing Swift and the macOS SDK. There are no third-party package dependencies.

The build script produces a **Universal app containing `arm64` and `x86_64`**. A successful build for an architecture or deployment target does not prove that its Bluetooth keyboard behavior works on every device.

The recorded reference setup was one Apple silicon Mac running **macOS 26.6.2** and one iPhone. Verification confirmed an encrypted keyboard connection, the complete test string `mac keyboard test 123`, and physical typing of `abc123`. The installed app was also confirmed to type successfully. The user has additionally confirmed input from an external Bluetooth keyboard connected to the Mac.

Other Mac models, Intel hardware, other macOS versions, other iPhones, Chinese candidate selection, other languages and keyboard layouts, and reconnection after sleep still need testing. These results are not a general compatibility guarantee.

## Get the source

```sh
git clone https://github.com/willrong1971/MacPhoneKeys.git
cd MacPhoneKeys
```

Alternatively, select **Code → Download ZIP** on the repository page, extract it, and open a terminal in the extracted directory.

## Build and install

From the project directory, run:

```sh
zsh build.sh
```

The output is `build/手机键盘.app`. The Chinese filename is intentional; use it exactly as shown in commands.

1. In Finder, drag `手机键盘.app` into **Applications**.
2. Open the app from Applications.
3. Allow Bluetooth access when macOS asks.
4. Keep only one copy of the app running while using or testing it.

The app starts its Bluetooth keyboard service automatically. Continue with [Pair and type](#pair-and-type).

### Bluetooth permission, signing and notarization

If Bluetooth access was denied, enable access for this app in **System Settings → Privacy & Security → Bluetooth**, or the corresponding privacy pane in System Preferences on older macOS versions.

The source build defaults to **ad-hoc signing**. The repository does not include a developer certificate, private key or notarization credentials. To use your own signing identity, set `MACPHONEKEYS_SIGN_IDENTITY` to the full name of a certificate already available in your keychain before running the build or packaging script.

**The scripts do not automatically notarize the app or DMG.** A downloaded, unnotarized build may be blocked by Gatekeeper on another Mac. Check its source and the release's signing information before using macOS's app-specific **Open Anyway** option when available. Do not disable system-wide security protection. An Apple Development signature is not the same as a Developer ID distribution that has completed notarization.

Distributors must arrange their own appropriate signing and notarization. See [Apple's Developer ID documentation](https://developer.apple.com/developer-id/).

## Pair and type

1. Open **手机键盘** on the Mac and wait for the service to start.
2. On the iPhone, open **Settings → Bluetooth** and select the **Mac's system name**. It may not appear as “MacPhoneKeys” or “MacKeys.” Follow the system pairing prompts and verify any displayed pairing code.
3. Open Notes or another app on the iPhone and tap the text field where you want to type. Make sure its cursor is active.
4. On the Mac, wait until **开始输入** (*Start typing*) becomes available, then click it. Keep the app's input area focused and type with the built-in Mac keyboard or an external Bluetooth keyboard connected to the Mac.
5. Press **Esc**, click **停止输入（Esc）** (*Stop typing*), or switch to another Mac window to stop forwarding input.

For an initial check, click **发送英文测试串** (*Send English test string*). In the confirmation dialog, choose **发送测试串** (*Send test string*) to send `mac keyboard test 123` without pressing Return, or **取消** (*Cancel*) to leave the phone unchanged. For this literal test string, use an English/US hardware keyboard layout on the iPhone.

Confirm that the text actually appears on the iPhone. **已接收按键** (*Accepted key presses*) includes reports waiting in a local send queue; a rising count is not proof of phone-side delivery or visible text.

## Chinese UI reference

The translations below explain the current Chinese interface; the English labels are not shown inside the app.

| Chinese text in the app | English meaning | Purpose |
| --- | --- | --- |
| 手机键盘 | Phone Keyboard | App and window name. |
| 启动蓝牙键盘 | Start Bluetooth keyboard | Start the service if it is stopped. |
| 停止蓝牙键盘 | Stop Bluetooth keyboard | Stop the service. |
| 打开 Mac 蓝牙设置 | Open Mac Bluetooth settings | Open the Mac's Bluetooth settings. |
| 开始输入 | Start typing | Focus the input area and forward keyboard events. |
| 停止输入（Esc） | Stop typing (Esc) | Stop forwarding input and release keys. |
| 发送英文测试串 | Send English test string | Open the test confirmation dialog. |
| 发送测试串 | Send test string | Confirm sending the English test string. |
| 取消 | Cancel | Cancel the test dialog. |
| 切换手机输入法 | Switch iPhone input method | Send Control + Space to the phone. Click Start typing again afterward. |
| 已接收按键 | Accepted key presses | Local input count, including reports waiting to send. |
| 连接记录 | Connection log | Service, connection and error messages. |
| 打开记录文件 | Open log file | Locate the log in Finder. |
| 帮助 → 连接与使用说明 | Help → Connection and usage instructions | Open the app's Chinese help dialog. |
| 知道了 | Got it | Close the help dialog. |
| 退出手机键盘 | Quit Phone Keyboard | Quit the app. |

Additional pairing and transport controls may appear when the app is launched with `--diagnostics`. They belong to experimental diagnostics and are not required for the default BLE workflow.

## Input methods and keyboard layouts

MacPhoneKeys forwards **hardware key events**, not completed text from the Mac's input method. The iPhone's active hardware keyboard layout and input method determine the resulting characters and candidate selection.

- Physical key codes follow an **ANSI-based mapping**. The English test string uses US-ANSI keystrokes.
- Common letters, digits, punctuation, navigation keys and modifiers are mapped in the source. This is not a promise that all keyboard shortcuts or extra hardware keys work on every layout.
- ISO/JIS-specific keys, other layouts and other languages have not been comprehensively mapped or verified. Punctuation can differ when the iPhone uses a different hardware keyboard layout.
- For Chinese, select an appropriate hardware keyboard input method on the iPhone. The **切换手机输入法** button sends **Control + Space**; click **开始输入** again afterward. Chinese candidate selection has not completed physical-device validation.
- Text already composed on the Mac, including Chinese characters, is not inserted as a Unicode string. The app does not read or transfer the Mac's clipboard and does not implement Unicode text injection.
- **Esc is reserved for stopping input** in the Mac app; it is not forwarded as an Escape keystroke to the phone.

## Create a DMG

To rebuild the app and make a disk image:

```sh
zsh package.sh
```

The default output is `build/手机键盘-0.2.0-通用版.dmg`. The script checks the Universal architectures and app signature and verifies the disk image. It does not automatically upload or notarize anything.

The disk image includes Chinese and English installation/usage instructions and the MIT license file, `LICENSE`.

To package an existing app without rebuilding it:

```sh
zsh package.sh build/手机键盘-0.2.0-通用版.dmg build/手机键盘.app
```

Open the DMG in Finder, drag the app onto its **Applications** shortcut, and eject the disk image after installation. If a release provides a prebuilt DMG, check that release's signing and notarization information before opening the app.

The packaging script currently expects version **0.2.0 (4)**. Update the version check in the script and `Resources/Info.plist` together when changing that version.

## Troubleshooting

### The iPhone does not show “MacPhoneKeys”

Look for the **Mac's system name** in iPhone Bluetooth settings. This setup has been observed under that name rather than the app's advertised name. Confirm that the Mac app has Bluetooth permission, its service is running, and only one copy is open. Read the connection log before changing pairing records.

### Start typing remains disabled

The app enables input after the phone subscribes to an encrypted keyboard input report. Service registration or advertising success alone does not establish that state. Check the phone's Bluetooth connection and the app's connection messages.

### The counter increases, but no text appears

Tap the intended text field on the iPhone again, confirm that its cursor is active, and check its hardware keyboard input method. Try the supplied English test string with an English/US layout, then confirm the result on the phone before testing normal typing. The local counter and “submitted” messages do not prove that an iPhone app displayed the characters.

### Characters or punctuation differ from the Mac keyboard

The iPhone interprets ANSI-based physical key codes using its own active layout. Match the iPhone's hardware keyboard layout to the intended input where possible. Other layouts and language-specific keys remain unverified; changing the Mac input source does not turn the app into a Unicode text sender.

### Pairing or reconnection fails after a rebuild or installation

Run one installed copy from Applications and inspect the connection log. To reopen it, press **Esc** to stop input, then quit with **Command-Q** before opening it again. System-managed pairing and GATT service caching can affect reconnection, and the current implementation has limited cross-device testing. Do not repeatedly delete pairing records or reset global Bluetooth settings as a first step. Report the exact failure and relevant errors so that discovery, authentication and subscription problems can be distinguished.

### The phone reports a full keyboard battery

The Battery service returns a fixed **100% test value**. It is not the Mac's actual battery level. The device vendor identifier is also an experimental placeholder rather than a registered manufacturer's identity.

### Is a shared Apple ID required?

No. Input uses the Bluetooth keyboard connection. The Mac and iPhone may keep different Apple IDs.

## BLE implementation limits

The default transport is **HID over GATT**. The successful reference implementation registers HID, Battery and Device Information services using their expanded Bluetooth Base UUID forms, while advertising the short HID service UUID.

macOS reserves some standard GATT services. Short-form HID service registration was rejected on the reference Mac, while the expanded representation worked there. This behavior may differ across OS versions or devices and is not a general platform guarantee.

The source retains a Classic Bluetooth transport for diagnostics, but reliable phone-side input through that transport has not been verified. Use the default BLE path for the documented workflow.

Input reports use a bounded local queue. Stopping input clears reports that have not been accepted by the system and attempts to release keys. Reports already submitted to the system Bluetooth stack cannot be recalled.

## Source checks and project layout

Run the offline checks from the project directory:

```sh
zsh scripts/check.sh
```

The checks validate shell syntax and app metadata and run tests for key mapping, BLE FIFO/backpressure and cancellation, and Classic Bluetooth SDP data. They do not connect to an iPhone, start the app or operate Bluetooth. Passing them does not replace physical pairing, input and reconnection tests.

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | Chinese UI and foreground keyboard events. |
| `Sources/KeyMapping.swift` | Mac key codes to HID usages. |
| `Sources/BLEKeyboard.swift` | BLE HID services and bounded input queue. |
| `Sources/BluetoothKeyboard.swift` | Experimental Classic Bluetooth transport. |
| `Tests/` | Checks that do not connect to a device. |
| `Resources/` | App metadata, icons and installation instructions. |
| `build.sh` / `package.sh` | Universal app and DMG build scripts. |
| `scripts/check.sh` | Offline checks. |
| `scripts/generate-icon.swift` | Original geometric icon generator. |

To regenerate the icon:

```sh
xcrun swift scripts/generate-icon.swift
```

## Privacy and issue reports

The app receives keyboard events only while its own foreground input area is active. It does not request Accessibility or Input Monitoring permission, read Apple accounts, the clipboard or contacts, or send input through iCloud or the network. Connection logs record connection events, errors and counts, not typed content.

For a useful issue report, include the macOS and iOS versions, Mac architecture, keyboard connection type and layout, reproduction steps, and relevant connection errors. Say whether text was actually visible on the iPhone. Remove device names, Bluetooth addresses, account details and other personal information before sharing logs.

## License

Copyright (c) 2026 **九福爸爸 9fbaba**.

Released under the [MIT License](LICENSE), which permits use, modification, building and redistribution subject to its terms.
