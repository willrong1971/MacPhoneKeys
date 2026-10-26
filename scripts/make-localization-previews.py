#!/usr/bin/env python3
"""Prepare isolated, Bluetooth-disabled copies for visual localization checks.

Usage: python3 scripts/make-localization-previews.py build/手机键盘.app
The copies are ad-hoc signed under build/localization-previews. Launch a copy
through Finder to inspect it; this script never launches or installs an app.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

project = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve()
if source.suffix != ".app" or not (source / "Contents/Info.plist").is_file():
    raise SystemExit("Pass a built MacPhoneKeys .app bundle.")

for language in ("en", "zh-Hans", "zh-Hant"):
    target = project / "build/localization-previews" / language / "手机键盘.app"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True)
    info_path = target / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] += ".localizationpreview." + language.lower()
    info["CFBundleLocalizations"] = [language]
    info["CFBundleDevelopmentRegion"] = language
    info["MacPhoneKeysLocalizationPreview"] = True
    info_path.write_bytes(plistlib.dumps(info))
    resources = target / "Contents/Resources"
    for folder in resources.glob("*.lproj"):
        if folder.stem != language:
            shutil.rmtree(folder)
    subprocess.run(
        ["codesign", "--force", "--sign", "-", "--timestamp=none", str(target)],
        check=True,
    )
    print(target)
