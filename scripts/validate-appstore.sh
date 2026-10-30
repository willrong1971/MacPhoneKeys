#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if (( $# < 1 || $# > 2 )) || [[ "${2:-}" != "" && "${2:-}" != "--candidate" ]]; then
  print -u2 '用法：zsh scripts/validate-appstore.sh APP [--candidate]'
  exit 2
fi
app_dir="${1:A}"
validation_mode="${2:-release}"

# Decode signatures and profiles only in memory. The temporary directory used
# below holds public signing certificates, never a profile payload or private key.
python3 - "$app_dir" "$validation_mode" "$project_dir" <<'PY'
from pathlib import Path
import datetime
import plistlib
import re
import subprocess
import sys
import tempfile

app = Path(sys.argv[1])
candidate = sys.argv[2] == '--candidate'
project = Path(sys.argv[3])

def fail(message):
    raise SystemExit('App Store 检查失败：' + message)

def command(arguments, purpose):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        fail(purpose + '。未输出签名权限或配置描述文件内容。')
    return result

def plist_file(path, purpose):
    try:
        data = plistlib.loads(path.read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException):
        fail(purpose + '缺失或格式无效。')
    if not isinstance(data, dict):
        fail(purpose + '必须是字典。')
    return data

if app.suffix != '.app' or not app.is_dir():
    fail('请提供已构建的 .app 目录。')
info = plist_file(app / 'Contents/Info.plist', 'Info.plist')
source_info = plist_file(project / 'Resources/Info.plist', '工程 Info.plist')
bundle_id = info.get('CFBundleIdentifier')
if bundle_id != source_info.get('CFBundleIdentifier'):
    fail('应用标识与本工程不匹配；不接受界面预览副本。')
if info.get('MacPhoneKeysBuildVariant') != 'appstore':
    fail('此 App 未标记为 appstore 构建。请设置 MACPHONEKEYS_BUILD_VARIANT=appstore 后重新构建。')
if info.get('MacPhoneKeysLocalizationPreview'):
    fail('界面预览副本不能用作商店候选版。')
if info.get('CFBundlePackageType') != 'APPL':
    fail('应用包类型不是 APPL。')
for key, title in [('CFBundleShortVersionString', '版本号'), ('CFBundleVersion', '构建号')]:
    value = info.get(key)
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value):
        fail(title + '必须是最多三段的数字字符串。')
executable_name = info.get('CFBundleExecutable')
if not isinstance(executable_name, str) or not executable_name or Path(executable_name).name != executable_name:
    fail('主程序名称无效。')
executable = app / 'Contents/MacOS' / executable_name
if not executable.is_file():
    fail('缺少主程序。')
for architecture in ['arm64', 'x86_64']:
    command(['/usr/bin/xcrun', 'lipo', str(executable), '-verify_arch', architecture], 'Universal 架构检查失败')
command(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], '严格签名验证失败')
signatures = []
for architecture in ['arm64', 'x86_64']:
    signature = command(['/usr/bin/codesign', '--display', '--architecture', architecture, '--verbose=4', str(app)], '无法读取签名摘要')
    signature_text = (signature.stdout + signature.stderr).decode('utf-8', 'replace')
    architecture_fields = {}
    architecture_authorities = []
    for line in signature_text.splitlines():
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        if key == 'Authority':
            architecture_authorities.append(value)
        else:
            architecture_fields[key] = value
    if architecture_fields.get('Identifier') != bundle_id:
        fail('签名标识与 Info.plist 不一致。')
    entitlement_result = command(['/usr/bin/codesign', '--display', '--architecture', architecture, '--entitlements', ':-', str(app)], '无法读取签名权限')
    try:
        architecture_entitlements = plistlib.loads(entitlement_result.stdout)
    except (ValueError, plistlib.InvalidFileException):
        fail('签名未包含有效的权限字典。')
    if not isinstance(architecture_entitlements, dict):
        fail('签名权限必须是字典。')
    signatures.append((architecture_fields, architecture_authorities, architecture_entitlements))
fields, authorities, entitlements = signatures[0]
other_fields, other_authorities, other_entitlements = signatures[1]
if (entitlements != other_entitlements or authorities != other_authorities
        or fields.get('TeamIdentifier') != other_fields.get('TeamIdentifier')):
    fail('两种架构的签名团队、证书链名称或权限不一致。')
required = {
    'com.apple.security.app-sandbox',
    'com.apple.security.device.bluetooth',
    'com.apple.security.files.user-selected.read-write',
}
for key in required:
    if entitlements.get(key) is not True:
        fail('缺少必需的沙盒、蓝牙或用户选择文件权限。')
identity_keys = {'com.apple.application-identifier', 'com.apple.developer.team-identifier'}
debug_keys = {'get-task-allow', 'com.apple.security.get-task-allow'}
allowed = required | identity_keys | debug_keys | {'beta-reports-active'}
if set(entitlements) - allowed:
    fail('签名含非预期权限；请逐项审阅，不自动接受额外访问权限。')
if any(entitlements.get(key, False) is not False for key in debug_keys):
    fail('不接受调试进程访问权限。')

privacy = plist_file(app / 'Contents/Resources/PrivacyInfo.xcprivacy', '隐私清单')
if privacy.get('NSPrivacyTracking') is not False or privacy.get('NSPrivacyTrackingDomains') != []:
    fail('隐私清单的跟踪声明与当前实现不符。')
if privacy.get('NSPrivacyCollectedDataTypes') != []:
    fail('隐私清单的数据收集声明与当前实现不符。')
expected_access = [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                    'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}]
if privacy.get('NSPrivacyAccessedAPITypes') != expected_access:
    fail('必需原因 API 声明与当前自有偏好用途不符。')

profile_path = app / 'Contents/embedded.provisionprofile'
if candidate:
    if entitlements.get('beta-reports-active'):
        fail('本地候选模式不验证 TestFlight 权限，请使用正式检查。')
    print('本地沙盒候选检查通过：Universal、严格签名、最小权限和隐私清单。')
    print('此结果不表示具备提交签名、完成沙盒真机测试或获得 Apple 审核通过。')
    raise SystemExit(0)

store_prefixes = ('Apple Distribution:', 'Mac App Distribution:', '3rd Party Mac Developer Application:')
if not authorities or not authorities[0].startswith(store_prefixes):
    fail('正式检查需要 Mac App Store 应用发行签名；不接受 ad-hoc、Apple Development 或 Developer ID。')
command(['/usr/bin/codesign', '--verify', '--strict', '--test-requirement', 'anchor apple generic', str(app)], '签名证书未通过 Apple 证书链要求')
team = fields.get('TeamIdentifier', '')
if not re.fullmatch(r'[A-Z0-9]{10}', team):
    fail('签名缺少有效的团队标识。')
if entitlements.get('com.apple.developer.team-identifier') != team:
    fail('签名团队权限与签名团队不匹配。')
if not profile_path.is_file():
    fail('本项目正式发行策略要求嵌入匹配的商店配置描述文件，以统一准备 App Store 和 TestFlight。')
decoded = command(['/usr/bin/security', 'cms', '-D', '-i', str(profile_path)], '配置描述文件解码失败')
try:
    profile = plistlib.loads(decoded.stdout)
except (ValueError, plistlib.InvalidFileException):
    fail('配置描述文件内容无效。')
if not isinstance(profile, dict):
    fail('配置描述文件内容无效。')
profile_entitlements = profile.get('Entitlements', {})
if not isinstance(profile_entitlements, dict):
    fail('配置描述文件缺少有效权限。')
platforms = profile.get('Platform', [])
if not isinstance(platforms, list) or not set(platforms) & {'OSX', 'macOS'}:
    fail('配置描述文件不是 macOS 配置。')
teams = profile.get('TeamIdentifier', [])
if not isinstance(teams, list) or team not in teams or profile_entitlements.get('com.apple.developer.team-identifier') != team:
    fail('配置描述文件团队与应用签名团队不匹配。')
profile_app_id = profile_entitlements.get('com.apple.application-identifier')
app_id = entitlements.get('com.apple.application-identifier')
if not isinstance(profile_app_id, str) or '*' in profile_app_id or app_id != profile_app_id:
    fail('需要与签名完全匹配的显式应用标识，不接受通配标识。')
suffix = '.' + bundle_id
if not profile_app_id.endswith(suffix):
    fail('配置描述文件属于其他应用。')
prefix = profile_app_id[:-len(suffix)]
if prefix not in profile.get('ApplicationIdentifierPrefix', []):
    fail('配置描述文件的应用前缀无效。')
now = datetime.datetime.now(datetime.timezone.utc)
expiration = profile.get('ExpirationDate')
if not isinstance(expiration, datetime.datetime):
    fail('配置描述文件缺少到期时间。')
if expiration.tzinfo is None:
    expiration = expiration.replace(tzinfo=datetime.timezone.utc)
if expiration <= now:
    fail('配置描述文件已经过期。')
if 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
    fail('不接受指定测试设备或全设备直接分发的配置描述文件。')
if any(profile_entitlements.get(key, False) is not False for key in debug_keys):
    fail('配置描述文件允许调试访问，不能用于本项目正式商店包。')
if 'beta-reports-active' in entitlements and entitlements['beta-reports-active'] != profile_entitlements.get('beta-reports-active', False):
    fail('TestFlight 报告权限与配置描述文件不匹配。')
certificates = profile.get('DeveloperCertificates', [])
if not isinstance(certificates, list) or not certificates:
    fail('配置描述文件未授权任何发行证书。')
with tempfile.TemporaryDirectory(prefix='macphonekeys-store-cert-') as temporary:
    for architecture in ['arm64', 'x86_64']:
        certificate_prefix = Path(temporary) / ('signer-' + architecture)
        command(['/usr/bin/codesign', '--display', '--architecture', architecture, '--extract-certificates', str(certificate_prefix), str(app)], '无法检查签名证书与配置描述文件匹配关系')
        try:
            leaf_certificate = Path(str(certificate_prefix) + '0').read_bytes()
        except OSError:
            fail('无法检查签名证书。')
        if leaf_certificate not in certificates:
            fail('应用的实际签名证书未被配置描述文件授权。')
print('本地商店上传前检查通过：签名类型、显式应用标识、团队、配置描述文件与证书匹配。')
print('仍需 Apple 上传处理、实际设备验证和 App Review；本脚本不会上传。')
PY
