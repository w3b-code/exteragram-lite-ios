"""Build pinned Telegram + local port as an arm64 IPA, without Apple identity.

No P12, provisioning profile, Apple account or developer team is loaded.
Telegram API credentials are application credentials supplied via environment.
"""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM_REVISION = "f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838"
BAZEL_VERSION = "9.2.0"
BAZEL_HASHES = {
    "arm64": "dd466352a3e4d3581b8898740ee1ff208866ccbe25f8d367c5dcb950219587e6",
    "x86_64": "14c9bcb01303b38192e0e2895051c1bcf19bf89d7e416f5aeeeb48b6b624cfbf",
}


def credentials():
    api_id = os.environ.get("TELEGRAM_API_ID", "").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
    if not re.fullmatch(r"[1-9][0-9]*", api_id) or int(api_id) > 2**31 - 1:
        raise ValueError("Set TELEGRAM_API_ID to your own numeric Telegram api_id in repository Secrets")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", api_hash):
        raise ValueError("Set TELEGRAM_API_HASH to your own 32-character Telegram api_hash in repository Secrets")
    return api_id, api_hash


def acquire_bazel(destination):
    arch = platform.machine()
    if arch not in BAZEL_HASHES:
        raise ValueError("Unsupported macOS runner architecture: " + arch)
    target = destination / f"bazel-{BAZEL_VERSION}-darwin-{arch}"
    if not target.exists():
        request = urllib.request.Request(f"https://github.com/bazelbuild/bazel/releases/download/{BAZEL_VERSION}/{target.name}", headers={"User-Agent": "exteragram-lite-ios"})
        with urllib.request.urlopen(request, timeout=60) as response, target.open("wb") as output:
            shutil.copyfileobj(response, output)
    with target.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != BAZEL_HASHES[arch]:
        raise ValueError("Bazel binary SHA-256 mismatch")
    target.chmod(0o755)
    return target


def bazel_work_root(upstream):
    """Bazel 9's repository-content cache must be outside the source checkout."""
    temporary = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())).resolve()
    candidate = temporary / "exteragram-bazel-user-root"
    if candidate.is_relative_to(upstream.resolve()):
        raise ValueError("Bazel temporary root must be outside the Telegram source checkout")
    candidate.mkdir(parents=True, exist_ok=True)
    return candidate


def build(upstream, output):
    api_id, api_hash = credentials()
    if sys.platform != "darwin":
        raise ValueError("Device IPA compilation requires the configured GitHub macOS runner")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, text=True).strip()
    if revision != UPSTREAM_REVISION:
        raise ValueError("Unexpected Telegram source revision: " + revision)
    versions = json.loads((upstream / "versions.json").read_text())
    if versions["bazel"].split(":")[0] != BAZEL_VERSION:
        raise ValueError("Pinned source and Bazel version disagree")
    rule_file = upstream / "build-system/bazel-rules/rules_apple/apple/internal/codesigning_support.bzl"
    if 'if "disable_legacy_signing" in features:' not in rule_file.read_text():
        raise ValueError("Vendored rules_apple no longer supports the verified unsigned feature")
    subprocess.run([sys.executable, str(ROOT / "scripts/apply_port.py"), str(upstream)], check=True)
    build_input = upstream / "build-input"
    build_input.mkdir(exist_ok=True)
    bazel = acquire_bazel(build_input)
    config_repo = build_input / "configuration-repository"
    (config_repo / "provisioning").mkdir(parents=True, exist_ok=True)
    (config_repo / "WORKSPACE").write_text("")
    (config_repo / "MODULE.bazel").write_text('module(name = "build_configuration")\n')
    (config_repo / "BUILD").write_text("")
    (config_repo / "provisioning/BUILD").write_text("exports_files([])\n")
    config = {
        "bundle_id": "org.exteragram.lite.ios", "api_id": api_id, "api_hash": api_hash,
        # Only a syntactic placeholder for generated unsigned entitlements.
        # Feather replaces signing identity/team at final on-device signing.
        "team_id": "0000000000", "app_center_id": "0", "is_internal_build": "false",
        "is_appstore_build": "false", "appstore_id": "0", "app_specific_url_scheme": "exteragram",
        "premium_iap_product_id": "", "enable_siri": False, "enable_icloud": False,
    }
    config_file = build_input / "unsigned-configuration.json"
    config_file.write_text(json.dumps(config))
    config_file.chmod(0o600)
    sys.path.insert(0, str(upstream / "build-system/Make"))
    original_cwd = Path.cwd()
    os.chdir(upstream)
    try:
        configuration_module = importlib.import_module("BuildConfiguration")
        make = importlib.import_module("Make")
        configuration = configuration_module.build_configuration_from_json(str(config_file))
        variables = config_repo / "variables.bzl"
        configuration.write_to_variables_file(str(bazel), False, "production", str(variables))
        variables.chmod(0o600)
        command = make.BazelCommandLine(str(bazel), False, False, str(bazel_work_root(upstream)))
        command.set_configuration("release_arm64")
        command.set_build_number(os.environ.get("EXTERA_BUILD_NUMBER", "1"))
        command.set_disable_provisioning_profiles()
        command.common_build_args += [
            "--features=disable_legacy_signing", "--jobs=3",
            "--local_resources=cpu=3", "--local_resources=memory=9500",
        ]
        command.invoke_build()
    finally:
        os.chdir(original_cwd)
        config_file.unlink(missing_ok=True)
    built = upstream / "bazel-bin/Telegram/Telegram.ipa"
    if not built.is_file():
        raise ValueError("Bazel succeeded but the expected device IPA was not produced")
    output.mkdir(parents=True, exist_ok=True)
    ipa = output / "exteraGram-Lite-unsigned.ipa"
    shutil.copyfile(built, ipa)
    from validate_ipa import validate
    facts = validate(ipa)
    facts.update(upstream_revision=revision, port_revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                 distribution="unsigned_for_on_device_signing", feature_parity="not_yet_complete")
    (output / "build-manifest.json").write_text(json.dumps(facts, indent=2))
    print("Validated unsigned device IPA:", ipa.name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-credentials", action="store_true")
    parser.add_argument("--upstream", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    try:
        if args.check_credentials:
            credentials()
            print("Telegram API configuration is present (values withheld).")
            return
        if args.upstream is None:
            parser.error("--upstream is required for building")
        build(args.upstream.resolve(), args.output.resolve())
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))


if __name__ == "__main__":
    main()
