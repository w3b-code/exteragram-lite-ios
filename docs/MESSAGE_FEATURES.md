# Message feature integration

The patch registry `port/patches/message_features.json` targets Telegram iOS commit `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`. It contains 21 exact text replacements in 14 source/BUILD files. The supplied Android APK SHA-256 is `adbead84d31057fbe2d58433fe4f51f09463eb0c007d82ae28df2344462777ed`.

These are actual preference consumers in native Telegram iOS. They depend on the local Bazel target `//submodules/ExteraPreferences:ExteraPreferences` and its typed `ExteraSettings` declarations. A setting takes effect when its affected content next lays out or is reopened; this patch set does not force every existing chat cell to rebuild when leaving the settings screen.

| APK parameter | Native hook | Behavior when enabled |
|---|---|---|
| `disableNumberRounding` | `TelegramPresentationData/Sources/NumericFormat.swift`, `compactNumericCountString` | Returns the complete decimal integer in places that use the shared compact counter formatter, e.g. `12345` instead of `12.3K`. The original compact formatter remains unchanged when disabled. |
| `formatTimeWithSeconds` | `TextFormat/Sources/DateFormat.swift`, `stringForMessageTimestamp` | Enables the existing upstream seconds formatter. It preserves local/UTC selection, 12/24-hour presentation, and AM/PM spacing. Explicit callers already requesting seconds keep seconds when the preference is disabled. |
| `replaceEditedWithIcon` | `ChatMessageDateAndStatusNode.swift` | Replaces only the visible localized edited label with the pencil glyph `✎`. The original logic deciding whether an edited label exists, including primary-edited-date server configuration, stays intact. This is the native glyph adaptation of the Android icon option. |
| `hideShareButton` | Bubble, static sticker, animated sticker and instant-video item renderers | Suppresses the regular side forwarding button before measuring its layout. Context-menu forwarding is unchanged. Sponsored-message action controls keep their separate original behavior. |

The parameter names/default declarations and UI labels are present in the selected Lite APK's recovered `ExteraConfig` and localization assets. The iOS hooks above are new platform adaptations; static APK inventory alone does not establish runtime equivalence. No network requests, read-state changes, message-deletion changes or server-state changes are introduced by these patches.

## Validation performed

- Loaded each original source/BUILD file directly from the pinned Git commit, without editing the upstream checkout.
- Verified every `old` fragment has exactly its declared occurrence count after earlier replacements in the same file.
- Verified the 14 modified source/BUILD files have the expected imports and direct Bazel dependencies, including the low-level formatting modules. `ExteraPreferences` must remain Foundation-only to avoid dependency cycles.
- The original branches remain present when each switch is disabled. Forwarding-button suppression runs after upstream eligibility and before width/layout computation in all four item renderers.
- Confirmed upstream `stringForMessageTimestamp` already accepts `withSeconds`, and upstream `stringForShortTimestamp` handles seconds in both time formats. The patch reuses that code rather than formatting timestamps a second way.

Compilation and UI execution must be validated by the macOS CI/app build. There is no Swift compiler in the local Windows environment, and these checks do not establish that an IPA was built or installed.

## Not implemented by this patch set

The remaining Lite features, including channel/group/private reaction visibility, are outside this change. Reaction presentation has multiple independent inline, standalone and footer paths; filtering only `mergedMessageReactionsAndPeers` would leave some footer rows and would be an incomplete implementation. These settings must not be advertised as functional until all relevant presentation paths have been integrated and checked.
