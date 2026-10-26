# MacPhoneKeys · 手机键盘

[中文](README.md) | **English**

<img src="Resources/AppIcon.png" width="112" alt="MacPhoneKeys icon">

Use a keyboard connected to your Mac to type on an iPhone over Bluetooth. The devices may use **different Apple IDs**, and no iPhone app is required.

MacPhoneKeys stays in the **menu bar**, without a Dock icon. Left-click its icon or press **Control + Option + K** to toggle iPhone input. A small input hint window is shown by default and can be turned off in full settings. **Esc**, the shortcut again, another click on the icon, or switching to another window stops capture and requests key release.

Author: **九福爸爸 9fbaba**.

Version **0.5.0 (8)** supports English, Simplified Chinese and Traditional Chinese. The app selects its interface language from the Mac's preferred supported languages, with English as the fallback. Its English name is **MacPhoneKeys**; its Chinese name is **手机键盘**.

## Interface language

The app uses standard macOS Bundle localizations: `en`, `zh-Hans` and `zh-Hant`. macOS selects a supported language from your preferred language list. If none matches, the app uses English.

You can change the Mac's preferred language order. Where macOS provides per-app language settings, you can also select a language for this app in **System Settings → General → Language & Region → Applications**. Settings and labels vary by macOS version. **Quit the app completely and reopen it after changing the language**; the running interface does not switch immediately.

The app's interface language is separate from the iPhone's input method and hardware-keyboard layout. Changing the interface language does not change the phone's typing language. The [controls reference](#controls-reference) compares the English and Simplified Chinese interfaces.

Input from the Mac's built-in keyboard and an external Bluetooth keyboard connected to the Mac was confirmed with the earlier app. USB keyboards have not been tested. Connect an external keyboard to the Mac first; MacPhoneKeys forwards keyboard events only during active capture with its own keyboard focus.

## Requirements and verification

- A Mac capable of operating as a Bluetooth Low Energy peripheral.
- macOS **12.0 or later** is the build's deployment target.
- An iPhone that can connect to the Mac as a Bluetooth keyboard.
- For source builds: a recent Xcode or Xcode Command Line Tools installation providing Swift and the macOS SDK. There are no third-party package dependencies.

The build script produces a **Universal app containing `arm64` and `x86_64`**. A successful build for an architecture or deployment target does not prove that its Bluetooth keyboard behavior works on every device.

The recorded reference setup was one Apple silicon Mac running **macOS 26.6.2** and one iPhone. Verification confirmed an encrypted keyboard connection, the complete test string `mac keyboard test 123`, and physical typing of `abc123`. The installed app was also confirmed to type successfully. The user has additionally confirmed input from an external Bluetooth keyboard connected to the Mac.

Those phone-side typing results came from **0.2.0**. **0.4.1 (7)** fixed asynchronous activation and focus handling when starting input with full settings closed. The user then confirmed that workflow: the global shortcut started input, the complete `abc123` string appeared on the iPhone, and both stopping with the shortcut and switching to another Mac window returned the icon to its gray outline.

**0.5.0 (8)** adds a revised vector menu bar icon and a saved **Show input hint window** setting. The user confirmed that with both full settings and the hint turned off, the global shortcut started phone input, the complete `abc123` string appeared on iPhone, the icon and stop controls behaved normally, and no hint window appeared.

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

The output path remains `build/手机键盘.app` in every interface language. This filename is intentional; use it exactly as shown in commands. The app is named **MacPhoneKeys** in its English interface.

1. In Finder, drag `手机键盘.app` into **Applications**.
2. Open the app from Applications.
3. Allow Bluetooth access when macOS asks.
4. Keep only one copy of the app running while using or testing it.

The app starts its Bluetooth keyboard service automatically and appears in the menu bar. It does not open the full settings window or add a Dock icon by default. Continue with [Pair and type](#pair-and-type).

### Bluetooth permission, signing and notarization

If Bluetooth access was denied, enable access for this app in **System Settings → Privacy & Security → Bluetooth**, or the corresponding privacy pane in System Preferences on older macOS versions.

The source build defaults to **ad-hoc signing**. The repository does not include a developer certificate, private key or notarization credentials. To use your own signing identity, set `MACPHONEKEYS_SIGN_IDENTITY` to the full name of a certificate already available in your keychain before running the build or packaging script.

**The scripts do not automatically notarize the app or DMG.** A downloaded, unnotarized build may be blocked by Gatekeeper on another Mac. Check its source and the release's signing information before using macOS's app-specific **Open Anyway** option when available. Do not disable system-wide security protection. An Apple Development signature is not the same as a Developer ID distribution that has completed notarization.

Distributors must arrange their own appropriate signing and notarization. See [Apple's Developer ID documentation](https://developer.apple.com/developer-id/).

## Pair and type

1. Open **MacPhoneKeys** on the Mac, find its app icon in the menu bar, and wait for the service to start.
2. On the iPhone, open **Settings → Bluetooth** and select the **Mac's system name**. It may not appear as “MacPhoneKeys” or “MacKeys.” Follow the system pairing prompts and verify any displayed pairing code.
3. Open Notes or another app on the iPhone and tap the text field where you want to type. Make sure its cursor is active.
4. Once the connection is ready, left-click the Mac's menu bar icon or press **Control + Option + K**. Wait for the icon to become filled, then type using the built-in Mac keyboard or an external Bluetooth keyboard connected to the Mac. The input hint window is shown by default; you can turn it off in full settings.
5. Press **Esc**, press the shortcut again, click the menu bar icon again, or switch to another Mac window to stop forwarding input and request key release.

For an initial check, right-click the menu bar icon, choose **Full Settings…**, and click **Send English Test**. In the confirmation dialog, choose **Send Test Text** to send `mac keyboard test 123` without pressing Return, or **Cancel** to leave the phone unchanged. For this literal test string, use an English/US hardware keyboard layout on the iPhone.

Confirm that the text actually appears on the iPhone. **Accepted keys** includes reports waiting in a local send queue; a rising count is not proof of phone-side delivery or visible text.

## Menu bar and shortcut

- The menu bar uses a wider vector **keyboard → phone** icon with thicker lines. A **filled icon** means capture has actually gained input focus and input is being forwarded to iPhone. A **gray outline** means local Mac input. Requesting activation alone does not fill the icon, and its fill does not prove that the iPhone displayed any text.
- Left-click the icon to toggle iPhone input. Right-click it for **Start phone input** / **Stop phone input**, **Full Settings…**, help and quit.
- The default global shortcut is **Control + Option + K**. If another app has already registered it, MacPhoneKeys reports the conflict; the icon and menu remain available.
- **Show input hint window** in full settings is enabled by default, and your choice is saved. When it is turned off, input still works and the menu bar icon provides the status indication. **Esc**, the shortcut again, or losing focus still stops capture.

Full settings retains pairing, connection diagnostics, logs, English test text and input-method controls. Diagnostic transports remain experimental; the documented connection uses the default BLE transport.

**Start Typing** in full settings follows the same hint-window setting. You can alternatively click the original input area in full settings to capture keystrokes there.

Full settings can stay closed during normal use. A shortcut or icon action from another Mac app first waits for MacPhoneKeys to activate and gain keyboard focus before enabling capture. Cancellation or focus loss invalidates a pending activation, so a late event cannot restart input. The global shortcut does not depend on keeping full settings open.

## Controls reference

These labels are a reference for the English and Simplified Chinese interfaces. The app also includes a Traditional Chinese localization.

| Simplified Chinese interface | English interface | Purpose |
| --- | --- | --- |
| 手机键盘 | MacPhoneKeys | App and window name. |
| 开始手机输入 | Start phone input | Start capture from the menu bar menu. |
| 停止手机输入 | Stop phone input | Stop capture from the menu bar menu. |
| 完整设置… | Full Settings… | Open pairing, diagnostics, test and other settings controls. |
| 启动蓝牙键盘 | Start Keyboard Service | Start the service if it is stopped. |
| 停止蓝牙键盘 | Stop Keyboard Service | Stop the service. |
| 打开 Mac 蓝牙设置 | Mac Bluetooth Settings | Open the Mac's Bluetooth settings. |
| 开始输入 | Start Typing | Begin capture, showing the hint window if enabled. |
| 显示输入提示浮窗 | Show input hint window | Show or hide the input hint; enabled by default and saved. |
| 停止输入（Esc） | Stop Typing (Esc) | Stop forwarding input and release keys. |
| 发送英文测试串 | Send English Test | Open the test confirmation dialog. |
| 发送测试串 | Send Test Text | Confirm sending the English test string. |
| 取消 | Cancel | Cancel the test dialog. |
| 切换手机输入法 | Switch iPhone Input Method | Send Control + Space to the phone. Use the icon or global shortcut to start typing again afterward. |
| 已接收按键 | Accepted keys | Local input count, including reports waiting to send. |
| 连接记录 | Connection Log | Service, connection and error messages. |
| 打开记录文件 | Show Log File | Locate the log in Finder. |
| 帮助 → 连接与使用说明 | Help → Connection and Usage | Open the help dialog in the selected interface language. |
| 知道了 | Got It | Close the help dialog. |
| 退出手机键盘 | Quit MacPhoneKeys | Quit the app. |

The right-click menu opens full settings, where pairing, test and transport-diagnostic controls are available. These diagnostics are not required for the default BLE workflow.

## Input methods and keyboard layouts

MacPhoneKeys forwards **hardware key events**, not completed text from the Mac's input method. The iPhone's active hardware keyboard layout and input method determine the resulting characters and candidate selection.

- Physical key codes follow an **ANSI-based mapping**. The English test string uses US-ANSI keystrokes.
- Common letters, digits, punctuation, navigation keys and modifiers are mapped in the source. This is not a promise that all keyboard shortcuts or extra hardware keys work on every layout.
- ISO/JIS-specific keys, other layouts and other languages have not been comprehensively mapped or verified. Punctuation can differ when the iPhone uses a different hardware keyboard layout.
- For Chinese, select an appropriate hardware keyboard input method on the iPhone. In full settings, **Switch iPhone Input Method** sends **Control + Space**; use the menu bar icon or global shortcut to start typing again afterward. Chinese candidate selection has not completed physical-device validation.
- Text already composed on the Mac, including Chinese characters, is not inserted as a Unicode string. The app does not read or transfer the Mac's clipboard and does not implement Unicode text injection.
- **Esc is reserved for stopping input** in the Mac app; it is not forwarded as an Escape keystroke to the phone.

## Create a DMG

To rebuild the app and make a disk image:

```sh
zsh package.sh
```

The default output is `build/手机键盘-0.5.0-通用版.dmg`. The script checks the Universal architectures and app signature and verifies the disk image. It does not automatically upload or notarize anything.

The disk image includes Chinese and English installation/usage instructions and the MIT license file, `LICENSE`.

To package an existing app without rebuilding it:

```sh
zsh package.sh build/手机键盘-0.5.0-通用版.dmg build/手机键盘.app
```

Open the DMG in Finder, drag the app onto its **Applications** shortcut, and eject the disk image after installation. If a release provides a prebuilt DMG, check that release's signing and notarization information before opening the app.

The packaging script currently expects version **0.5.0 (8)**. Update the version check in the script and `Resources/Info.plist` together when changing that version.

## Troubleshooting

### The iPhone does not show “MacPhoneKeys”

Look for the **Mac's system name** in iPhone Bluetooth settings. This setup has been observed under that name rather than the app's advertised name. Confirm that the Mac app has Bluetooth permission, its service is running, and only one copy is open. Read the connection log before changing pairing records.

### Start typing remains disabled

The app enables input after the phone subscribes to an encrypted keyboard input report. Service registration or advertising success alone does not establish that state. Check the phone's Bluetooth connection and the app's connection messages.

### The counter increases, but no text appears

Tap the intended text field on the iPhone again, confirm that its cursor is active, and check its hardware keyboard input method. If input still fails, open **Full Settings…**, click **Stop Keyboard Service**, then **Start Keyboard Service**. Wait for reconnection and try the supplied English test string with an English/US layout. Restarting only the app's service restored output in one 0.4.1 test; the root cause was not determined. Do not start by deleting pairing records or resetting global Bluetooth. The local counter and “submitted” messages do not prove that an iPhone app displayed the characters.

### Characters or punctuation differ from the Mac keyboard

The iPhone interprets ANSI-based physical key codes using its own active layout. Match the iPhone's hardware keyboard layout to the intended input where possible. Other layouts and language-specific keys remain unverified; changing the Mac input source does not turn the app into a Unicode text sender.

### Pairing or reconnection fails after a rebuild or installation

Run one copy and inspect the connection log in full settings. To reopen it, press **Esc** to stop input, then right-click the menu bar icon and choose **Quit MacPhoneKeys** before opening it again. System-managed pairing and GATT service caching can affect reconnection, and the current implementation has limited cross-device testing. Do not repeatedly delete pairing records or reset global Bluetooth settings as a first step. Report the exact failure and relevant errors so that discovery, authentication and subscription problems can be distinguished.

### No Dock icon or full window appears

This is the default menu bar mode. Look for the app icon near the Mac's menu bar clock. Right-click it to open full settings or quit. The input hint window appears during capture only if **Show input hint window** is enabled.

### The global shortcut is unavailable

MacPhoneKeys reports a shortcut-registration conflict if another program has claimed **Control + Option + K**. Use the menu bar icon or its menu to start and stop input; the app does not silently take over the conflicting shortcut.

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

The checks validate shell syntax, app metadata, language selection and resource coverage, hint-setting defaults and persistence in an isolated preferences suite, capture activation timing, key mapping, BLE FIFO/backpressure and cancellation, and Classic Bluetooth SDP data. They do not connect to an iPhone, start the app or operate Bluetooth. Passing them does not replace physical pairing, input and reconnection tests.

After building, developers can prepare isolated UI previews:

```sh
python3 scripts/make-localization-previews.py build/手机键盘.app
```

The copies under `build/localization-previews/` use separate app identities, temporary log directories and an isolated `PreviewKeyboardTransport`. They do not start Bluetooth managers or send input to a phone. You can test translations, layout, focus, global shortcuts, icon states and local accepted-key counts. These previews validate the interface and local key routing; they cannot verify that text appears on an iPhone and must not be distributed as installable releases.

After changing Simplified Chinese translations, run `xcrun swift scripts/generate-traditional-localization.swift` to update Traditional Chinese values, then review the result. Lookup keys remain unchanged.

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | Localized menu bar, full settings, input panel and foreground keyboard events. |
| `Sources/MenuBarController.swift` | Menu bar icon, left/right clicks and menu. |
| `Sources/MenuBarIcon.swift` | The keyboard → phone vector menu bar icon. |
| `Sources/AppPreferences.swift` | Input hint defaults and saved preference. |
| `Sources/GlobalHotKey.swift` | Global input-toggle shortcut and conflict handling. |
| `Sources/KeyMapping.swift` | Mac key codes to HID usages. |
| `Sources/BLEKeyboard.swift` | BLE HID services and bounded input queue. |
| `Sources/BluetoothKeyboard.swift` | Experimental Classic Bluetooth transport. |
| `Tests/` | Checks that do not connect to a device. |
| `Tests/AppPreferencesTests.swift` | Default and cross-instance persistence checks in an isolated preferences suite. |
| `Resources/` | App metadata, icons, installation instructions and `en` / `zh-Hans` / `zh-Hant` language resources. |
| `build.sh` / `package.sh` | Universal app and DMG build scripts. |
| `scripts/check.sh` | Offline checks. |
| `scripts/generate-icon.swift` | Original geometric icon generator. |

To regenerate the icon:

```sh
xcrun swift scripts/generate-icon.swift
```

## Privacy and issue reports

The app receives keystrokes for forwarding only after capture is enabled and while the app has keyboard focus; the hint window is optional. The global shortcut toggles capture. The app does not request Accessibility or Input Monitoring permission, read Apple accounts, the clipboard or contacts, or send input through iCloud or the network. Connection logs record connection events, errors and counts, not typed content.

For a useful issue report, include the macOS and iOS versions, Mac architecture, keyboard connection type and layout, reproduction steps, and relevant connection errors. Say whether text was actually visible on the iPhone. Remove device names, Bluetooth addresses, account details and other personal information before sharing logs.

## License

Copyright (c) 2026 **九福爸爸 9fbaba**.

Released under the [MIT License](LICENSE), which permits use, modification, building and redistribution subject to its terms.
