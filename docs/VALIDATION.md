# Recorded validation

The checks below refer to the exact source revisions shown. They are not claims about a later revision or a physical iPhone.

| Port revision | Evidence | Result |
|---|---|---|
| `8c28d4fb598cbbf15b7af3dd012d5e5c5ca8c58c` | [GitHub run 39465848539](https://github.com/w3b-code/exteragram-lite-ios/actions/runs/39465848539) | Preferences: 11 Swift tests passed. Resources: 5 Swift tests passed. Python: 12 tests passed. Overlay Swift syntax passed. |
| Same revision | Same run, unsigned IPA job | API configuration preflight, recursive checkout, and Xcode 26.6 selection passed. Bazel stopped before source compilation because its repository-content cache was inside the checkout. No IPA was produced. |
| `de9c8405f0e94af5f51bd50704810083e511f7ac` | Local Python unittest run on Windows | 14 tests passed, including two regression checks for the external Bazel output root. |

Device compilation, installation in Feather, Telegram login, profile-dependent capabilities, and feature behavior on an iPhone remain separate checks. Full Lite feature parity is incomplete.
