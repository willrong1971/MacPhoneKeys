#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
checks_dir="$project_dir/build/checks"
mkdir -p "$checks_dir"

zsh -n "$project_dir/build.sh" "$project_dir/package.sh"
plutil -lint "$project_dir/Resources/Info.plist"
[[ -s "$project_dir/Resources/AppIcon.icns" ]]

xcrun swiftc -swift-version 5 \
  "$project_dir/Sources/KeyMapping.swift" "$project_dir/Tests/KeyMappingTests.swift" \
  -o "$checks_dir/KeyMappingTests"
"$checks_dir/KeyMappingTests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/BLEKeyboard.swift" "$project_dir/Tests/BLEInputReportQueueTests.swift" \
  -framework CoreBluetooth -o "$checks_dir/BLEInputReportQueueTests"
"$checks_dir/BLEInputReportQueueTests"

xcrun swiftc -swift-version 5 -D HID_SDP_TESTS -parse-as-library \
  "$project_dir/Sources/BluetoothKeyboard.swift" "$project_dir/Tests/SDPTests.swift" \
  -framework Foundation -framework IOBluetooth -o "$checks_dir/SDPTests"
"$checks_dir/SDPTests"
