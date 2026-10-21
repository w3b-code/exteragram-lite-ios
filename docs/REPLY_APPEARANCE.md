# Reply appearance preferences

This patch connects `replyColors`, `replyEmoji`, and `replyBackground` to the native `ChatMessageReplyInfoNode`. All three recovered Lite defaults are `true`; their enabled paths retain the original pinned Telegram rendering.

## Shipped-artifact evidence

Target: supplied exteraGram Lite 12.10.6 APK, SHA-256 `adbead84d31057fbe2d58433fe4f51f09463eb0c007d82ae28df2344462777ed`. Static REA/JADX analysis used the existing verified headless JADX jar and Java 21; the APK was not executed. Incoming-reference totals are JADX using-node counts, not exhaustive dynamic reachability.

| Preference | Positive static consumers | Retained REA evidence |
|---|---|---|
| `replyColors` | `ReplyMessageLine.check`, `resolveCollectionColor`, preference getter | `ev_95143c46cc5d7e60fe4ccd95170c081dbc7c08efe7ec0187065a71950d0fab28` |
| `replyEmoji` | The same two render methods, `ChatMessageCellDelegate.didPressReplyMessage`, preference getter | `ev_07f792e656359e7ade61635ee5de811c422aa344416bbf2c039f8389f10df3f6` |
| `replyBackground` | The same two render methods and preference getter | `ev_137cd74b5b6f5aeda040d0eb891a45ceb39e0ce90fb796e297bc5e3eee7b179c` |

Focused Java bodies: `check` evidence `ev_83bc7f203c9fc5117ac52b616e4bb71336da93973b6d6d1840c7de01755edb53`; `resolveCollectionColor` evidence `ev_83c51774e0ac5fbaa13b9e59bd25b63a52d84ab20d49c935cf15a1745a6f08a0`. The check body contains two duplicated-code JADX warnings; observations below rely on its explicit preference guards, corroborated by the separate collectible resolver.

Observed Android semantics: disabling colors clears secondary/tertiary stripe colors and uses the theme's ordinary reply line/name colors. Disabling background sets its fill to transparent in reply branches; certain other numeric line modes have exceptions. Disabling emoji clears the background emoji document; the collectible resolver additionally clears its gift emoji sticker document. The class is reused beyond ordinary replies, so its numeric mode branches must not be blindly treated as identical surfaces.

## Native implementation

Native comparison uses Telegram-iOS `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`.

- `ChatMessageReplyInfoNode` captures the three display values once per asynchronous measure/apply transaction. With colors disabled, custom author colors and multi-color dashes are cleared before selecting the original incoming/outgoing theme accents. Standalone replies keep their native service-message contrast.
- Emoji disabled removes both the peer's repeated background pattern and the collectible gift icon. The gift ID is cleared before width measurement, so the icon's extra title inset is also removed. Native reuse cleanup removes the previous gift layer and pattern when their inputs become absent. Text custom emoji, mention/quote entities, spoilers, media thumbnails, the quote marker, and reply navigation are unchanged.
- Background disabled requests the existing transparent template, preserving the vertical line and content. A standalone reply was already transparent and stays so. Pattern visibility is independent of fill visibility, matching the separate settings. Special summary decorations retain their native behavior.
- `MessageInlineBlockBackgroundView` now rebuilds its template when `isTransparent` or explicit `backgroundColor` changes, as well as when the existing colors change. Previously a fill-only change on a reused node updated stored parameters without updating the image. This shared invalidation fix makes the declared rendering inputs effective; it does not apply global preferences to other users of the view.

There is no change to stored messages, read state, permissions, media requests, or server account colors. The setting is read when affected reply content next lays out; this patch does not force all existing message cells to rebuild immediately.

## Scope and remaining paths

The common reply-info renderer is reused by ordinary bubbles and standalone sticker/instant-video reply headers. The input `ReplyAccessoryPanelNode` already uses a plain native accent separator, without the peer background/palette/gift decoration handled here.

Android's reused line also appears in link/ad and contact/collectible contexts. Native `ChatMessageAttachedContentNode`, `ChatMessageContactBubbleContentNode`, story `ForwardInfoPanelComponent`, and regular forwarded-header styling have not been changed by this patch: exact Android numeric-mode mappings and exceptions need a separate comparison. The Android emoji-related click effect has not been separately reproduced on iOS; ordinary native reply navigation is preserved. This is real reply-renderer integration, not a claim of complete parity across every reused Android line mode.

## Validation

Each old fragment was checked against the pinned original source. The patch adds a direct `ExteraPreferences` dependency and import to the reply renderer. `apply_port.py` successfully applied the complete combined port and its automatic second-pass idempotence check; a subsequent `--check` and `git diff --check` passed. The shared invalidation condition uses fields already present in the view's `Params`. No macOS typecheck, full app compile, or iPhone visual check was performed locally. Those remain CI/device checks.
