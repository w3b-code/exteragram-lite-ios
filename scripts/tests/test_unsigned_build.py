import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from build_unsigned import credentials
from validate_ipa import validate, macho_platforms


def binary(platform=2, cpu=0x0100000C):
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0) + struct.pack("<6I", 0x32, 24, platform, 0x0F0000, 0x1A0000, 0)


class IpaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.ipa = Path(self.temporary.name) / "example.ipa"

    def write_ipa(self, executable=None, extras=None):
        info = {"CFBundlePackageType": "APPL", "CFBundleIdentifier": "org.example.test",
                "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "Example",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Example.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Example.app/Example", binary() if executable is None else executable)
            for name, data in (extras or {}).items():
                archive.writestr(name, data)

    def test_valid_unsigned_arm64_ipa(self):
        self.write_ipa()
        facts = validate(self.ipa)
        self.assertEqual(facts["bundle_id"], "org.example.test")
        self.assertEqual(facts["architectures"], [{"cpu_type": 0x0100000C, "platform": 2, "filetype": 2}])
        self.assertEqual(facts["installation_test"], "not_performed")

    def test_arm64_simulator_is_not_a_device_build(self):
        self.write_ipa(executable=binary(platform=7))
        with self.assertRaisesRegex(ValueError, "Simulator"):
            validate(self.ipa)

    def test_x86_executable_is_rejected(self):
        self.write_ipa(executable=binary(cpu=0x01000007))
        with self.assertRaisesRegex(ValueError, "arm64"):
            validate(self.ipa)

    def test_embedded_simulator_framework_is_rejected(self):
        self.write_ipa(extras={"Payload/Example.app/Frameworks/Bad.framework/Bad": binary(platform=7)})
        with self.assertRaisesRegex(ValueError, "embedded"):
            validate(self.ipa)

    def test_profiles_and_signatures_are_not_shipped(self):
        for name in ("Payload/Example.app/embedded.mobileprovision", "Payload/Example.app/_CodeSignature/CodeResources"):
            with self.subTest(name=name):
                self.write_ipa(extras={name: b"example"})
                with self.assertRaises(ValueError):
                    validate(self.ipa)

    def test_zip_path_traversal_is_rejected(self):
        self.write_ipa(extras={"Payload/../outside": b"example"})
        with self.assertRaisesRegex(ValueError, "Unsafe archive"):
            validate(self.ipa)

    def test_truncated_load_command_is_rejected(self):
        self.write_ipa(executable=binary()[:-1])
        with self.assertRaises(ValueError):
            validate(self.ipa)


class CredentialsTests(unittest.TestCase):
    def test_absent_credentials_have_clear_error(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "TELEGRAM_API_ID"):
                credentials()

    def test_credential_types_are_validated(self):
        with patch.dict(os.environ, {"TELEGRAM_API_ID": "12345", "TELEGRAM_API_HASH": "f" * 32}, clear=True):
            self.assertEqual(credentials(), ("12345", "f" * 32))
        with patch.dict(os.environ, {"TELEGRAM_API_ID": "12345", "TELEGRAM_API_HASH": "bad"}, clear=True):
            with self.assertRaisesRegex(ValueError, "TELEGRAM_API_HASH"):
                credentials()


if __name__ == "__main__":
    unittest.main()
