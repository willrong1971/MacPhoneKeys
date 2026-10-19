#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="${1:-$project_dir/build/手机键盘.app}"
app_dir="${app_dir:a}"
minimum_macos="12.0"
sign_identity="${MACPHONEKEYS_SIGN_IDENTITY:--}"
[[ "$app_dir" == *.app ]] || { print -u2 "输出路径必须以 .app 结尾。"; exit 1; }
[[ ! -e "$app_dir" || -d "$app_dir" ]] || { print -u2 "输出路径已存在且不是目录。"; exit 1; }
mkdir -p "$project_dir/build" "${app_dir:h}"
staging_dir="$(mktemp -d "$project_dir/build/.universal-build.XXXXXX")"
staged_app="$staging_dir/手机键盘.app"
previous_app="$staging_dir/previous.app"
cleanup() {
  if [[ -d "$previous_app" && ! -e "$app_dir" ]]; then
    mv "$previous_app" "$app_dir"
  fi
  rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staging_dir/Sources"

# Both architectures must use the same saved source snapshot, even if editing
# continues while the first compiler is running.
for source_file in KeyMapping.swift BluetoothKeyboard.swift BLEKeyboard.swift main.swift; do
  cp "$project_dir/Sources/$source_file" "$staging_dir/Sources/$source_file"
done
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $minimum_macos" "$staged_app/Contents/Info.plist"
for resource_file in HIDService.plist AppIcon.icns; do
  if [[ -f "$project_dir/Resources/$resource_file" ]]; then
    cp "$project_dir/Resources/$resource_file" "$staged_app/Contents/Resources/$resource_file"
  fi
done
if [[ ! -f "$staged_app/Contents/Resources/AppIcon.icns" ]]; then
  print -u2 "提示：未找到 Resources/AppIcon.icns；开发构建可继续，制作安装盘前必须补齐图标。"
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
for target_arch in arm64 x86_64; do
  print -u2 -- "编译 $target_arch，最低 macOS $minimum_macos…"
  xcrun swiftc -swift-version 5 -O -sdk "$sdk_path" \
    -target "$target_arch-apple-macos$minimum_macos" \
    -module-cache-path "$staging_dir/ModuleCache/$target_arch" \
    -framework AppKit -framework CoreBluetooth -framework IOBluetooth -framework IOBluetoothUI \
    "$staging_dir/Sources/KeyMapping.swift" "$staging_dir/Sources/BluetoothKeyboard.swift" \
    "$staging_dir/Sources/BLEKeyboard.swift" "$staging_dir/Sources/main.swift" \
    -o "$staging_dir/MacPhoneKeys-$target_arch"
done
xcrun lipo -create "$staging_dir/MacPhoneKeys-arm64" "$staging_dir/MacPhoneKeys-x86_64" \
  -output "$staged_app/Contents/MacOS/MacPhoneKeys"
for target_arch in arm64 x86_64; do
  xcrun lipo "$staged_app/Contents/MacOS/MacPhoneKeys" -verify_arch "$target_arch"
done

if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$staged_app"
else
  # A development identity provides stable local signing but is not Developer ID
  # distribution. Do not contact a timestamp service for development signatures.
  signing_timestamp="--timestamp=none"
  if [[ "$sign_identity" == "Developer ID Application:"* ]]; then signing_timestamp="--timestamp"; fi
  codesign --force --sign "$sign_identity" --options runtime "$signing_timestamp" "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
if [[ -d "$app_dir" ]]; then mv "$app_dir" "$previous_app"; fi
mv "$staged_app" "$app_dir"
print -r -- "$app_dir"
