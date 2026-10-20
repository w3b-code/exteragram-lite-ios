# GitHub build and Feather signing

The workflow is manual (`Actions` → `iOS packages and unsigned IPA` → `Run workflow`). It has no push/PR trigger and does not change repository visibility. Keep the repository public for the complete workflow if using the free standard GitHub-hosted macOS runners. Private-repository minutes and artifact storage are separate allowances.

The package job tests `ExteraResources`, `ExteraPreferences`, `ExteraSpeech`, and `ExteraTranslation`, typechecks the Apple speech adapter against the iPhoneOS SDK, parses the Swift overlays, and tests the Python IPA validator. To run only these checks, clear the **Build a device IPA** option. No API credentials or Apple signing files are needed for package checks.

For an application build, add repository Secrets `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` with the application's own Telegram API credentials. They can be obtained at https://my.telegram.org/apps. No `.p12`, password, `.mobileprovision`, Apple account or signing certificate is used by this workflow. These API credentials identify the Telegram application; they are unrelated to Feather's certificate.

The app job checks out Telegram iOS at `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838` and applies this repository's source overlay. The pinned upstream requires Xcode 26.6 and Bazel 9.2.0. The workflow uses the standard `macos-26-intel` runner, selects that exact Xcode, and verifies the SHA-256 of the official Bazel binary. It does not bypass toolchain version checks. A future runner-image change that removes that Xcode fails explicitly.

The build writes the upstream build-configuration module directly with an unsigned placeholder team identifier. It disables provisioning-profile dependencies with `--//Telegram:disableProvisioningProfiles` and disables device signing with the vendored rules_apple feature `disable_legacy_signing`. The normal Make.py signing resolver is deliberately not invoked: at this pinned revision its build command requires signing material and does not expose the same disable-profile switch as project generation.

Bazel's output root is placed under `RUNNER_TEMP`, outside the source checkout. Bazel 9 rejects its repository-content cache when that cache is inside the main repository.

After successful compilation, the workflow verifies that the IPA has a single `Payload/*.app`, an iPhoneOS main bundle, an arm64 device Mach-O platform, and no embedded provisioning profile or bundle-signature resources. It records a checksum and source revisions in `build-manifest.json`. These checks establish build/package structure; they do not establish installation, login or feature parity on a physical iPhone.

Download the `exteragram-lite-unsigned-<run number>` artifact, extract its outer ZIP, and import `exteraGram-Lite-unsigned.ipa` into Feather. Sign it there with the certificate and profile already on the phone. The artifact retention is one day to limit storage usage. The generated IPA cannot be installed before final on-device signing. Entitlements allowed by the final profile, including app groups and push notifications, must be checked on the phone; no success is implied before that test.

This repository is a work in progress. A successful build is not evidence that all exteraGram Lite functions have been ported. The generated manifest explicitly records that parity is incomplete until the source feature ledger and device validation establish otherwise.

Reference material:

- Telegram source build guide: https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/README.md
- Telegram toolchain versions: https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/versions.json
- rules_apple signing implementation: https://github.com/ali-fareed/rules_apple/blob/485016eb5b0948cc17307064e7977a6d68e94046/apple/internal/codesigning_support.bzl
- Standard macOS 26 Intel runner image: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
- Telegram API credentials: https://core.telegram.org/api/obtaining_api_id
