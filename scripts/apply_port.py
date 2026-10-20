"""Apply the port to one exact, pinned Telegram-iOS checkout.

All replacement anchors are checked before any file is written. Source drift
fails explicitly instead of silently producing a partially enabled client.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PORT = Path(__file__).resolve().parent.parent


def safe_path(root, relative):
    result = (root / relative).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError(f"Path outside target: {relative}")
    return result


def plan_patches(upstream):
    updates = {}
    for registry in sorted((PORT / "port/patches").glob("*.json")):
        patches = json.loads(registry.read_text(encoding="utf-8"))
        for patch in patches:
            target = safe_path(upstream, patch["path"])
            text = updates.get(target)
            if text is None:
                text = target.read_text(encoding="utf-8")
            old, new = patch["old"], patch["new"]
            count = patch.get("occurrences", 1)
            if new != old and text.count(new) == count:
                updates[target] = text
                continue
            if text.count(old) != count:
                raise ValueError(f"{registry.name}: {patch['path']}: expected {count} anchors, found {text.count(old)}")
            updates[target] = text.replace(old, new)
    for group in sorted((PORT / "port/overlays").glob("*")):
        if not group.is_dir():
            continue
        for source in sorted(group.rglob("*")):
            if source.is_file():
                updates[safe_path(upstream, source.relative_to(group))] = source.read_text(encoding="utf-8")
    return updates


def add_modules(upstream, updates):
    # SwiftPM tests and the device build consume the same module sources.
    for module in ["ExteraSpeech", "ExteraTranslation"]:
        sources = PORT / "ios" / module / "Sources" / module
        for source in sorted(sources.rglob("*.swift")):
            updates[safe_path(upstream, Path("submodules") / module / "Sources" / source.relative_to(sources))] = source.read_text(encoding="utf-8")
        updates[safe_path(upstream, f"submodules/{module}/BUILD")] = f'''load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "{module}",
    module_name = "{module}",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)
'''
    preferences = PORT / "ios/ExteraPreferences/Sources/ExteraPreferences"
    for source in sorted(preferences.glob("*.swift")):
        updates[safe_path(upstream, "submodules/ExteraPreferences/Sources/" + source.name)] = source.read_text(encoding="utf-8")
    updates[safe_path(upstream, "submodules/ExteraPreferences/BUILD")] = '''load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "ExteraPreferences",
    module_name = "ExteraPreferences",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)
'''
    resources = PORT / "ios/ExteraResources/Sources/ExteraResources"
    for source in sorted(resources.rglob("*")):
        if source.is_file():
            text = source.read_text(encoding="utf-8")
            if source.suffix == ".swift":
                text = text.replace("Bundle.module", "exteraResourceBundle")
                if source.name == "ExteraLocalization.swift":
                    text += '''
private final class ExteraResourceBundleToken {}
private let exteraResourceBundle: Bundle = {
    for owner in [Bundle(for: ExteraResourceBundleToken.self), Bundle.main] {
        if let url = owner.url(forResource: "ExteraResources", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
    }
    return Bundle(for: ExteraResourceBundleToken.self)
}()
'''
            updates[safe_path(upstream, Path("submodules/ExteraResources") / source.relative_to(resources))] = text
    updates[safe_path(upstream, "submodules/ExteraResources/BUILD")] = '''load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle")
apple_resource_bundle(
    name = "ExteraResourcesBundle",
    bundle_name = "ExteraResources",
    resources = glob(["Resources/**/*.strings"]),
)
swift_library(
    name = "ExteraResources",
    module_name = "ExteraResources",
    srcs = glob(["*.swift"]),
    data = [":ExteraResourcesBundle"],
    visibility = ["//visibility:public"],
)
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.upstream.resolve(strict=True)
    manifest = json.loads((PORT / "port/manifest.json").read_text(encoding="utf-8"))
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if commit != manifest["upstream_commit"]:
        raise ValueError(f"Unsupported upstream commit: {commit}")
    updates = plan_patches(root)
    add_modules(root, updates)
    record = {str(path.relative_to(root)).replace("\\", "/"): hashlib.sha256(text.encode()).hexdigest()
              for path, text in updates.items()}
    if not args.check:
        for path, text in updates.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
        (root / "extera-port-manifest.json").write_text(json.dumps({"source": manifest, "files": record}, indent=2), encoding="utf-8")
    print(json.dumps({"upstream": commit, "files": len(record), "mode": "check" if args.check else "applied",
                      "full_feature_parity_verified": False}))


if __name__ == "__main__":
    main()
