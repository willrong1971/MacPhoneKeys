#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if (( $# < 1 || $# > 2 )); then
  print -u2 '用法：MACPHONEKEYS_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: …" zsh scripts/package-appstore.sh APP [OUTPUT.pkg]'
  exit 2
fi
app_dir="${1:A}"
installer_identity="${MACPHONEKEYS_INSTALLER_SIGN_IDENTITY:-}"
if [[ -z "$installer_identity" ]]; then
  print -u2 '缺少 MACPHONEKEYS_INSTALLER_SIGN_IDENTITY；不会生成未签名或伪装为商店包的 PKG。'
  exit 1
fi
if [[ "$installer_identity" != '3rd Party Mac Developer Installer:'* && "$installer_identity" != 'Mac Installer Distribution:'* ]]; then
  print -u2 '需要 Mac App Store Installer 发行证书；不接受 Developer ID Installer、开发证书或 ad-hoc。'
  exit 1
fi
zsh "$project_dir/scripts/validate-appstore.sh" "$app_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
pkg_path="${2:-$project_dir/dist/MacPhoneKeys-$version-MacAppStore.pkg}"
pkg_path="${pkg_path:a}"
[[ "$pkg_path" == *.pkg ]] || { print -u2 '输出路径必须以 .pkg 结尾。'; exit 1; }
[[ ! -e "$pkg_path" ]] || { print -u2 '输出路径已存在；请使用新路径，保留原安装包。'; exit 1; }

# Installer identities must be queried without the codesigning policy filter.
# Keep identity inventory in memory and print no keychain or profile contents.
python3 - "$app_dir" "$installer_identity" <<'PY'
import re
import subprocess
import sys

app, identity = sys.argv[1:]
inventory = subprocess.run(['/usr/bin/security', 'find-identity', '-v'], capture_output=True, text=True)
if inventory.returncode or identity not in re.findall(r'"([^"\n]+)"', inventory.stdout):
    raise SystemExit('找不到完全匹配且有效的 Installer 签名身份；未生成安装包。')
signature = subprocess.run(['/usr/bin/codesign', '--display', '--verbose=4', app], capture_output=True, text=True)
app_team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', signature.stderr + signature.stdout, re.MULTILINE)
installer_team = re.search(r'\(([A-Z0-9]{10})\)$', identity)
if signature.returncode or not app_team or not installer_team or app_team.group(1) != installer_team.group(1):
    raise SystemExit('Installer 证书团队与应用团队不匹配；未生成安装包。')
PY

mkdir -p "${pkg_path:h}"
staging_dir="$(mktemp -d "${pkg_path:h}/.macphonekeys-store.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT INT TERM
staged_app="$staging_dir/${app_dir:t}"
ditto "$app_dir" "$staged_app"
# Validate the copied payload so a concurrent source rebuild cannot produce a
# package containing a different, unvalidated App.
zsh "$project_dir/scripts/validate-appstore.sh" "$staged_app"
staged_pkg="$staging_dir/MacPhoneKeys.pkg"
productbuild --component "$staged_app" /Applications --sign "$installer_identity" "$staged_pkg" >&2
python3 - "$staged_pkg" "$installer_identity" "$pkg_path" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

package, identity, destination = sys.argv[1:]
environment = dict(os.environ, LC_ALL='C')
result = subprocess.run(['/usr/sbin/pkgutil', '--check-signature', package], capture_output=True, text=True, env=environment)
text = result.stdout + result.stderr
leaf = re.search(r'^\s*1\.\s+(.+?)\s*$', text, re.MULTILINE)
apple_status = re.search(r'^\s*Status:\s+signed by a developer certificate issued by Apple(?:\s|$)', text, re.MULTILINE)
if result.returncode or not leaf or leaf.group(1) != identity or not apple_status:
    raise SystemExit('安装包签名验证失败；未交付该 PKG。')
# Both paths share the destination filesystem. An exclusive link prevents a
# late-arriving output file from being silently overwritten.
try:
    os.link(package, destination)
except FileExistsError:
    raise SystemExit('输出路径在打包期间已被创建；保留该文件，未覆盖。')
print(Path(destination))
print('已生成签名 PKG；尚未上传或通过 Apple 审核。', file=sys.stderr)
PY
