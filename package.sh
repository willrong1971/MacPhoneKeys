#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
dmg_path="${1:-$project_dir/build/手机键盘-0.3.0-通用版.dmg}"
dmg_path="${dmg_path:a}"
[[ "$dmg_path" == *.dmg ]] || { print -u2 "输出路径必须以 .dmg 结尾。"; exit 1; }

# A supplied app is packaged without rebuilding it. With no second argument,
# create a fresh Universal build first. Nothing is uploaded or published.
if (( $# >= 2 )); then
  app_dir="${2:a}"
else
  app_dir="$("$project_dir/build.sh")"
fi
[[ -d "$app_dir" ]] || { print -u2 "找不到要打包的 App：$app_dir"; exit 1; }
[[ -f "$app_dir/Contents/Resources/AppIcon.icns" ]] || { print -u2 "缺少 AppIcon.icns，拒绝制作无图标安装盘。"; exit 1; }
codesign --verify --deep --strict "$app_dir"
for target_arch in arm64 x86_64; do
  xcrun lipo "$app_dir/Contents/MacOS/MacPhoneKeys" -verify_arch "$target_arch"
done
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_dir/Contents/Info.plist")"
[[ "$version" == "0.3.0" && "$build_number" == "5" ]] || { print -u2 "App 版本应为 0.3.0 (5)，请重新构建。"; exit 1; }

mkdir -p "$project_dir/build" "${dmg_path:h}"
staging_dir="$(mktemp -d "$project_dir/build/.dmg-package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT INT TERM
payload="$staging_dir/payload"
mkdir -p "$payload"
ditto "$app_dir" "$payload/手机键盘.app"
ln -s /Applications "$payload/Applications"
for guide_file in 安装与使用.txt Installation-and-Usage.en.txt; do
  if [[ -f "$project_dir/Resources/$guide_file" ]]; then
    cp "$project_dir/Resources/$guide_file" "$payload/$guide_file"
  fi
done
if [[ -f "$project_dir/LICENSE" ]]; then
  cp "$project_dir/LICENSE" "$payload/LICENSE"
fi
hdiutil create -volname "手机键盘 $version" -srcfolder "$payload" \
  -format UDZO -fs HFS+ -ov "$staging_dir/package.dmg" >&2
hdiutil verify "$staging_dir/package.dmg" >&2
sign_identity="${MACPHONEKEYS_SIGN_IDENTITY:--}"
if [[ "$sign_identity" != "-" ]]; then
  signing_timestamp="--timestamp=none"
  if [[ "$sign_identity" == "Developer ID Application:"* ]]; then signing_timestamp="--timestamp"; fi
  codesign --force --sign "$sign_identity" "$signing_timestamp" "$staging_dir/package.dmg"
  codesign --verify --strict "$staging_dir/package.dmg"
fi
mv -f "$staging_dir/package.dmg" "$dmg_path"
print -r -- "$dmg_path"
