# Further Lite display preferences

Three additional preferences are connected to actual native consumers. Their recovered defaults are retained: `hideKeyboardOnScroll` and `filterZalgo` are true, `disableGreetingSticker` is false.

- `hideKeyboardOnScroll`: the chat-history drag callback dismisses the current input. The existing search/filter dismissal logic remains. Turning this off removes this forced dismissal; iOS's normal interactive keyboard gestures still operate.
- `disableGreetingSticker`: the empty-chat greeting keeps its title and explanatory or business text. Only the sticker is hidden, its layout height and spacing removed, its pending request canceled, and its tap disabled. Re-enabling permits normal sticker loading on a subsequent layout.
- `filterZalgo`: the common `stringWithAppliedEntities` formatter filters rendered text before applying entities. Stored messages and outgoing text are unchanged. This covers text using that formatter; peer names and other independent renderers still need separate integration.

APK evidence is the selected Lite SHA-256 recorded in `port/manifest.json`. Static incoming references identify `ChatActivity.27.onScrollStateChanged`, `ChatGreetingsView.<init>`, and `com.exteragram.messenger.utils.text.ZalgoFilter`. Focused decompilation supplied the filter's complete algorithm.

The Zalgo filter permits two consecutive nonspacing/enclosing marks in the five common combining ranges (U+0300–036F, U+1AB0–1AFF, U+1DC0–1DFF, U+20D0–20FF and U+FE20–FE2F), or four elsewhere. A mixed sequence uses the lower limit. If a run exceeds its limit, the whole run is replaced with U+2060 word joiners, one per original UTF-16 code unit. U+061C, U+200E/F, U+202A–202E and U+2066–2069 direction controls are similarly replaced. Emoji joiners and ordinary accents within the thresholds stay intact. This preserves the entity offsets used by Telegram's renderer.

Four Foundation tests cover preserved scripts/emoji, mark thresholds, supplementary-scalar UTF-16 offsets and direction controls. Device behavior and complete coverage of names/renderers remain pending; this is not a claim of complete Lite parity.
