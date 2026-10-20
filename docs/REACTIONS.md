# Reaction visibility integration

The three independent Lite preferences `hideReactionsInChannels`, `hideReactionsInGroups` and `hideReactionsInPrivateChats` now have a native display-policy implementation in the reaction overlay. They are presentation choices; this change does not remove or edit reaction attributes, update account state, send reactions, or alter networking.

Target source: Telegram iOS `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`, after the earlier message-feature patch registry. The selected APK and its recovered keys remain the project baseline; this iOS implementation is an adaptation rather than an observed Android runtime result.

## Coverage

`port/overlays/reactions/.../ChatMessageItemCommon/Sources/ExteraReactionVisibility.swift` introduces read-only wrappers around the original reaction projections. All 18 chat renderer source files that directly obtain reaction display models are patched to use these wrappers:

- 16 inline/date-status reaction-and-peer projection calls are filtered together, so reaction peer avatars cannot remain after the buttons are hidden.
- Seven direct attribute projection calls are filtered, covering bubble footer creation, bubble outside reactions, static and animated stickers, instant video, rich-data layout and the reaction footer itself.
- Bubble footer creation receives `nil` when hidden, preventing an empty footer from being inserted. Rich-data layout also sees no visible reactions, so it does not reserve outside reaction layout for hidden rows.
- Generic media rendering receives its date reactions from these filtered parent projections; it does not independently read raw reaction attributes.

Broadcast channels use the channel switch; channel-based groups/supergroups and legacy groups use the group switch; users, bots, Saved Messages and secret chats use the private-chat switch. Missing user/secret/legacy-group peers can be classified from their namespace. A missing channel peer is ambiguous between a broadcast and supergroup, so its reactions remain visible rather than use the wrong setting.

The original `mergedMessageReactions` and `mergedMessageReactionsAndPeers` engine functions are untouched. The message, attributes, reaction counts, pending local state and stored account data are untouched. With switches disabled, the wrappers return exactly the original projections. Context-menu reaction actions, the dedicated reaction list screen, paid-reaction sending, and transient reaction animations remain available; the settings hide persistent reaction rows in chat cells.

Settings are read for the message currently being rendered. Like the preceding message feature hooks, changes apply when content next lays out or is reopened; this overlay does not force an immediate refresh of every existing node.

## Validation and limits

- The registry contains 24 exact replacement operations across 18 renderer files and the common component's BUILD file. All anchors were checked against the current pinned/previously patched source without changing upstream.
- Every patched renderer already directly imports and depends on `ChatMessageItemCommon`. Only that common module gains dependencies on `ExteraPreferences` and `Postbox`; no engine module or cycle is introduced.
- Static coverage verification checks that no direct unfiltered `mergedMessageReactions*` call remains in these 18 renderer source files after applying the registry in memory.
- XCTest coverage is included in the overlay for all independent toggle combinations, real broadcast-vs-supergroup peer objects using upstream test factories, private/secret/legacy-group namespace fallback, and ambiguous missing channel peers.
- Swift compilation, XCTest execution and visual behavior must still be checked in macOS CI/on iPhone. Local Windows checks do not establish runtime or installation success.
