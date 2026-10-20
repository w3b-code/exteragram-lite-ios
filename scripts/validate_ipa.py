"""Validate device IPA structure and main Mach-O platform without installing it."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile

CPU_TYPE_ARM64 = 0x0100000C
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2


def macho_platforms(data):
    """Read a bounded thin/fat Mach-O header and load-command platform facts."""
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
        endian = ">" if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf") else "<"
        fat64 = data[:4] in (b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca")
        count = struct.unpack_from(endian + "I", data, 4)[0]
        if count > 32:
            raise ValueError("Unreasonable fat Mach-O architecture count")
        facts = []
        width = 32 if fat64 else 20
        for index in range(count):
            entry = 8 + index * width
            if fat64:
                cpu, subtype, offset, size, align, reserved = struct.unpack_from(endian + "IIQQII", data, entry)
            else:
                cpu, subtype, offset, size, align = struct.unpack_from(endian + "IIIII", data, entry)
            if offset + size > len(data):
                raise ValueError("Truncated fat Mach-O architecture")
            facts.extend(macho_platforms(data[offset:offset + size]))
        return facts
    endian = "<" if data[:4] == b"\xcf\xfa\xed\xfe" else ">" if data[:4] == b"\xfe\xed\xfa\xcf" else None
    if endian is None or len(data) < 32:
        raise ValueError("Expected a 64-bit Mach-O executable")
    magic, cpu, subtype, filetype, commands, commands_size, flags, reserved = struct.unpack_from(endian + "8I", data, 0)
    if commands > 4096 or commands_size > len(data) - 32:
        raise ValueError("Invalid Mach-O load-command bounds")
    offset = 32
    platforms = []
    for _ in range(commands):
        if offset + 8 > 32 + commands_size:
            raise ValueError("Truncated Mach-O command")
        command, size = struct.unpack_from(endian + "II", data, offset)
        if size < 8 or offset + size > 32 + commands_size:
            raise ValueError("Invalid Mach-O command size")
        if command == LC_BUILD_VERSION:
            if size < 24:
                raise ValueError("Truncated LC_BUILD_VERSION")
            platforms.append(struct.unpack_from(endian + "I", data, offset + 8)[0])
        elif command == LC_VERSION_MIN_IPHONEOS:
            platforms.append(PLATFORM_IOS)
        offset += size
    if len(platforms) != 1:
        raise ValueError("Expected one unambiguous iOS platform load command")
    return [{"cpu_type": cpu, "platform": platforms[0], "filetype": filetype}]


def validate(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate archive names")
        for name in names:
            parts = PurePosixPath(name).parts
            if name.startswith("/") or ".." in parts or "\\" in name:
                raise ValueError("Unsafe archive path")
        roots = {PurePosixPath(name).parts[1] for name in names if name.startswith("Payload/") and len(PurePosixPath(name).parts) > 1 and PurePosixPath(name).parts[1].endswith(".app")}
        if len(roots) != 1:
            raise ValueError("IPA must contain exactly one Payload/*.app")
        root = "Payload/" + roots.pop()
        info = plistlib.loads(archive.read(root + "/Info.plist"))
        if info.get("CFBundlePackageType") != "APPL":
            raise ValueError("Payload is not an application bundle")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Main bundle is not an iPhoneOS device build")
        executable = info["CFBundleExecutable"]
        if PurePosixPath(executable).name != executable:
            raise ValueError("Invalid CFBundleExecutable")
        facts = macho_platforms(archive.read(root + "/" + executable))
        if not any(fact["cpu_type"] == CPU_TYPE_ARM64 for fact in facts):
            raise ValueError("Main executable has no arm64 device slice")
        if any(fact["platform"] != PLATFORM_IOS for fact in facts):
            raise ValueError("Simulator or non-iOS Mach-O platform found")
        if any(fact["filetype"] != 2 for fact in facts):
            raise ValueError("Main Mach-O is not an executable")
        macho_entries = []
        magics = (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
                  b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf")
        for name in names:
            if name.endswith("/"):
                continue
            with archive.open(name) as stream:
                prefix = stream.read(4)
                if prefix not in magics:
                    continue
                entry_facts = macho_platforms(prefix + stream.read())
            if any(fact["platform"] != PLATFORM_IOS or fact["cpu_type"] != CPU_TYPE_ARM64 for fact in entry_facts):
                raise ValueError("Simulator or non-arm64 Mach-O embedded in IPA: " + name)
            macho_entries.append({"path": name, "architectures": entry_facts})
        if any(name.endswith("embedded.mobileprovision") for name in names):
            raise ValueError("Unsigned distribution must not contain a provisioning profile")
        if any("/_CodeSignature/" in name for name in names):
            raise ValueError("IPA unexpectedly contains bundle signing resources")
        with Path(path).open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        return {"bundle_id": info["CFBundleIdentifier"], "version": info.get("CFBundleShortVersionString"),
                "build": info.get("CFBundleVersion"), "main_bundle": root,
                "architectures": facts, "macho_entries": macho_entries, "entries": len(names), "bytes": Path(path).stat().st_size,
                "sha256": digest,
                "provisioning_profile": "absent", "installation_test": "not_performed"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.ipa), indent=2))


if __name__ == "__main__":
    main()
