#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
checks_dir="$project_dir/build/checks"
mkdir -p "$checks_dir"

zsh -n "$project_dir/build.sh" "$project_dir/package.sh"
plutil -lint "$project_dir/Resources/Info.plist"
plutil -lint "$project_dir/Resources/PrivacyInfo.xcprivacy" "$project_dir/Resources/MacAppStore.entitlements"
[[ -s "$project_dir/Resources/AppIcon.icns" ]]
for strings_file in "$project_dir"/Resources/*.lproj/*.strings(N); do
  plutil -lint "$strings_file"
done

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/Localization.swift" "$project_dir/Tests/LocalizationTests.swift" \
  -framework Foundation -o "$checks_dir/LocalizationTests"
"$checks_dir/LocalizationTests" "$project_dir"
if [[ "${1:-}" == "--localization-only" ]]; then exit 0; fi

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/AppPreferences.swift" "$project_dir/Tests/AppPreferencesTests.swift" \
  -framework Foundation -o "$checks_dir/AppPreferencesTests"
"$checks_dir/AppPreferencesTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/CaptureActivation.swift" "$project_dir/Tests/CaptureActivationTests.swift" \
  -framework Foundation -o "$checks_dir/CaptureActivationTests"
"$checks_dir/CaptureActivationTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/DiagnosticReport.swift" "$project_dir/Tests/DiagnosticReportTests.swift" \
  -framework Foundation -o "$checks_dir/DiagnosticReportTests"
"$checks_dir/DiagnosticReportTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/BLELifecycle.swift" "$project_dir/Tests/BLELifecycleTests.swift" \
  -framework Foundation -o "$checks_dir/BLELifecycleTests"
"$checks_dir/BLELifecycleTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/PairingFlow.swift" "$project_dir/Tests/PairingFlowTests.swift" \
  -framework Foundation -o "$checks_dir/PairingFlowTests"
"$checks_dir/PairingFlowTests"

xcrun swiftc -swift-version 5 \
  "$project_dir/Sources/KeyMapping.swift" "$project_dir/Tests/KeyMappingTests.swift" \
  -o "$checks_dir/KeyMappingTests"
"$checks_dir/KeyMappingTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/Localization.swift" "$project_dir/Sources/BLELifecycle.swift" "$project_dir/Sources/BLEKeyboard.swift" \
  "$project_dir/Tests/BLEInputReportQueueTests.swift" \
  -framework CoreBluetooth -o "$checks_dir/BLEInputReportQueueTests"
"$checks_dir/BLEInputReportQueueTests"

xcrun swiftc -swift-version 5 -D HID_SDP_TESTS -parse-as-library \
  "$project_dir/Sources/Localization.swift" "$project_dir/Sources/BluetoothKeyboard.swift" \
  "$project_dir/Tests/SDPTests.swift" \
  -framework Foundation -framework IOBluetooth -o "$checks_dir/SDPTests"
"$checks_dir/SDPTests"
