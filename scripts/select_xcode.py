"""Select the exact Xcode requested by pinned Telegram source; no bypass."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def main():
    required = json.loads(Path(sys.argv[1]).read_text())["xcode"]
    candidates = []
    for app in Path("/Applications").glob("Xcode*.app"):
        try:
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        except (OSError, plistlib.InvalidFileException):
            continue
        version = str(info.get("CFBundleShortVersionString", ""))
        if version == required or version == required + ".0":
            candidates.append(app)
    if not candidates:
        raise SystemExit(f"Pinned source requires Xcode {required}; it is not installed on this runner. No version check was bypassed.")
    selected = sorted(candidates)[0] / "Contents/Developer"
    subprocess.run(["sudo", "xcode-select", "--switch", str(selected)], check=True)
    subprocess.run(["xcodebuild", "-version"], check=True)


if __name__ == "__main__":
    main()
