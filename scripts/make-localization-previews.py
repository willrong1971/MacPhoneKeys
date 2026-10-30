#!/usr/bin/env python3
"""Prepare isolated, Bluetooth-disabled copies for visual localization checks.

Usage: python3 scripts/make-localization-previews.py build/手机键盘.app
The copies are ad-hoc signed under build/localization-previews. Launch one copy
at a time to inspect menu-bar focus, hotkeys and local input counters using a
fake transport. No Bluetooth manager starts; no reports reach a phone.
This script never launches or installs an app.
"""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import sys

project = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app")
parser.add_argument("--output-dir", type=Path, default=project / "build/localization-previews")
parser.add_argument("--show-assistant", action="store_true")
arguments = parser.parse_args()
source = Path(arguments.app).resolve()
output = arguments.output_dir.resolve()
if project / "build" not in output.parents and output != project / "build":
    raise SystemExit("Preview output must stay inside this project's build directory.")
if source.suffix != ".app" or not (source / "Contents/Info.plist").is_file():
    raise SystemExit("Pass a built MacPhoneKeys .app bundle.")

for language in ("en", "zh-Hans", "zh-Hant"):
    target = output / language / "手机键盘.app"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True)
    info_path = target / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    preview_kind = "sandboxpreview" if info.get("MacPhoneKeysBuildVariant") == "appstore" else "localizationpreview"
    info["CFBundleIdentifier"] += "." + preview_kind + "." + language.lower()
    info["CFBundleLocalizations"] = [language]
    info["CFBundleDevelopmentRegion"] = language
    info["MacPhoneKeysLocalizationPreview"] = True
    info["MacPhoneKeysPreviewShowAssistant"] = arguments.show_assistant
    info_path.write_bytes(plistlib.dumps(info))
    resources = target / "Contents/Resources"
    for folder in resources.glob("*.lproj"):
        if folder.stem != language:
            shutil.rmtree(folder)
    # A production profile cannot authorize the isolated preview identifier.
    profile = target / "Contents/embedded.provisionprofile"
    if profile.exists():
        profile.unlink()
    signing = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
    if info.get("MacPhoneKeysBuildVariant") == "appstore":
        signing += ["--entitlements", str(project / "Resources/MacAppStore.entitlements")]
    subprocess.run(signing + [str(target)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(target)], check=True)
    print(target)
