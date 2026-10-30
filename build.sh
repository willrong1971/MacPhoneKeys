#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="${1:-$project_dir/build/手机键盘.app}"
app_dir="${app_dir:a}"
minimum_macos="12.0"
sign_identity="${MACPHONEKEYS_SIGN_IDENTITY:--}"
build_variant="${MACPHONEKEYS_BUILD_VARIANT:-direct}"
provisioning_profile="${MACPHONEKEYS_PROVISIONING_PROFILE:-}"
[[ "$build_variant" == direct || "$build_variant" == appstore ]] || { print -u2 "构建方式必须是 direct 或 appstore。"; exit 1; }
[[ -z "$provisioning_profile" || "$build_variant" == appstore ]] || { print -u2 "配置描述文件只用于 appstore 构建。"; exit 1; }
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
source_files=(Localization.swift AppPreferences.swift GlobalHotKey.swift CaptureActivation.swift MenuBarIcon.swift MenuBarController.swift KeyMapping.swift BluetoothKeyboard.swift BLELifecycle.swift BLEKeyboard.swift PairingFlow.swift ConnectionAssistant.swift DiagnosticReport.swift DiagnosticReportExporter.swift SingleInstanceCoordinator.swift main.swift)
for source_file in "${source_files[@]}"; do
  cp "$project_dir/Sources/$source_file" "$staging_dir/Sources/$source_file"
done
for localization_dir in "$project_dir"/Resources/*.lproj(N/); do
  ditto "$localization_dir" "$staged_app/Contents/Resources/${localization_dir:t}"
done
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $minimum_macos" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MacPhoneKeysBuildVariant string $build_variant" "$staged_app/Contents/Info.plist"
cp "$project_dir/Resources/PrivacyInfo.xcprivacy" "$staged_app/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -n "$provisioning_profile" ]]; then
  [[ -f "$provisioning_profile" ]] || { print -u2 "找不到指定的配置描述文件。"; exit 1; }
  cp "$provisioning_profile" "$staged_app/Contents/embedded.provisionprofile"
fi
for resource_file in HIDService.plist AppIcon.icns; do
  if [[ -f "$project_dir/Resources/$resource_file" ]]; then
    cp "$project_dir/Resources/$resource_file" "$staged_app/Contents/Resources/$resource_file"
  fi
done
if [[ ! -f "$staged_app/Contents/Resources/AppIcon.icns" ]]; then
  print -u2 "提示：未找到 Resources/AppIcon.icns；开发构建可继续，制作安装盘前必须补齐图标。"
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
snapshot_sources=()
for source_file in "${source_files[@]}"; do snapshot_sources+=("$staging_dir/Sources/$source_file"); done
for target_arch in arm64 x86_64; do
  print -u2 -- "编译 $target_arch，最低 macOS $minimum_macos…"
  xcrun swiftc -swift-version 5 -O -sdk "$sdk_path" \
    -target "$target_arch-apple-macos$minimum_macos" \
    -module-cache-path "$staging_dir/ModuleCache/$target_arch" \
    -framework AppKit -framework Carbon -framework CoreBluetooth -framework IOBluetooth -framework IOBluetoothUI \
    "${snapshot_sources[@]}" \
    -o "$staging_dir/MacPhoneKeys-$target_arch"
done
xcrun lipo -create "$staging_dir/MacPhoneKeys-arm64" "$staging_dir/MacPhoneKeys-x86_64" \
  -output "$staged_app/Contents/MacOS/MacPhoneKeys"
for target_arch in arm64 x86_64; do
  xcrun lipo "$staged_app/Contents/MacOS/MacPhoneKeys" -verify_arch "$target_arch"
done

entitlement_options=()
if [[ "$build_variant" == appstore ]]; then
  signing_entitlements="$project_dir/Resources/MacAppStore.entitlements"
  if [[ -n "$provisioning_profile" ]]; then
    security cms -D -i "$provisioning_profile" -o "$staging_dir/profile.plist"
    python3 - "$signing_entitlements" "$staging_dir/profile.plist" "$staged_app/Contents/Info.plist" "$staging_dir/signing.entitlements" <<'PY'
import plistlib,sys
from pathlib import Path
base,profile,info=(plistlib.loads(Path(p).read_bytes()) for p in sys.argv[1:4])
ent=profile.get('Entitlements',{})
identifier=info['CFBundleIdentifier']
team=ent.get('com.apple.developer.team-identifier') or next(iter(profile.get('TeamIdentifier',[])),None)
key='com.apple.application-identifier' if 'com.apple.application-identifier' in ent else 'application-identifier'
application=ent.get(key)
if not team or application != team+'.'+identifier:
    raise SystemExit('配置描述文件必须准确匹配本项目的 Team 与 Bundle ID。')
base[key]=application
base['com.apple.developer.team-identifier']=team
Path(sys.argv[4]).write_bytes(plistlib.dumps(base))
PY
    signing_entitlements="$staging_dir/signing.entitlements"
  fi
  entitlement_options=(--entitlements "$signing_entitlements")
fi
if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - --timestamp=none "${entitlement_options[@]}" "$staged_app"
else
  # A development identity provides stable local signing but is not Developer ID
  # distribution. Do not contact a timestamp service for development signatures.
  signing_timestamp="--timestamp=none"
  if [[ "$sign_identity" == "Developer ID Application:"* || "$sign_identity" == "Apple Distribution:"* || "$sign_identity" == "Mac App Distribution:"* || "$sign_identity" == "3rd Party Mac Developer Application:"* ]]; then signing_timestamp="--timestamp"; fi
  codesign --force --sign "$sign_identity" --options runtime "$signing_timestamp" "${entitlement_options[@]}" "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
if [[ "$build_variant" == appstore && ( "$sign_identity" == "-" || "$sign_identity" == "Apple Development:"* ) ]]; then
  print -u2 "已创建本地沙盒候选；此签名不能用于提交 Mac App Store。"
fi
if [[ -d "$app_dir" ]]; then mv "$app_dir" "$previous_app"; fi
mv "$staged_app" "$app_dir"
print -r -- "$app_dir"
