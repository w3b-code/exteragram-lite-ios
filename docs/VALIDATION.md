# Recorded validation

The checks below refer to the exact source revisions shown. They are not claims about a later revision or a physical iPhone.

| Port revision | Evidence | Result |
|---|---|---|
| `8c28d4fb598cbbf15b7af3dd012d5e5c5ca8c58c` | [GitHub run 39465848539](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39465848539) | Preferences: 11 Swift tests passed. Resources: 5 Swift tests passed. Python: 12 tests passed. Overlay Swift syntax passed. |
| Same revision | Same run, unsigned IPA job | API configuration preflight, recursive checkout, and Xcode 26.6 selection passed. Bazel stopped before source compilation because its repository-content cache was inside the checkout. No IPA was produced. |
| `de9c8405f0e94af5f51bd50704810083e511f7ac` | Local Python unittest run on Windows | 14 tests passed, including two regression checks for the external Bazel output root. |
| Same revision | [GitHub run 39467713077](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39467713077) | Module checks passed. Bazel advanced past the cache error but stopped during target analysis: rules_apple attempted to embed a missing provisioning profile for IntentsExtension despite disabled signing. No IPA was produced. |
| `2ad319cb4c6c7266a0bfc4b6178b14483a72f9a7` | [GitHub run 39469568458](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39469568458) | 39 Swift tests passed (5 resources, 11 preferences, 8 speech, 15 translation). Apple speech adapter typechecked for arm64 iPhoneOS/iOS 15. Overlay Swift syntax and all 14 Python tests passed. This was a module-only run. |
| `25b698f8d371d27b1e138a0766e70fa7db32c8a8` | [GitHub run 39470628322](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39470628322) | Module checks, including four additional Zalgo tests, passed. Unsigned profile analysis was fixed and compilation reached over 2,000 Bazel actions. The WASI compiler then failed with `Bad CPU type in executable`: upstream supplied its arm64 host archive to an Intel runner. No IPA was produced. |
| `18dc71479b8323fd52d022f4aa563ac0dfc48cb1` | [GitHub run 39472936890](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39472936890), Swift modules job | All five packages passed (50 Swift tests including the seven export tests), the iPhone speech typecheck passed, overlay syntax and 14 Python tests passed. The full application job is a separate result. |

| Same revision | Same run, unsigned IPA job | Compilation stopped at the first Metal shader because the selected Xcode had no usable Metal Toolchain. No IPA was produced. The next workflow explicitly downloads the component and compiles a small iPhoneOS shader under the same minimal environment before starting Bazel. |

Device compilation, installation in Feather, Telegram login, profile-dependent capabilities, and feature behavior on an iPhone remain separate checks. Full Lite feature parity is incomplete.
