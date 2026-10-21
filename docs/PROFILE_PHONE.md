# Hiding the own account phone number

Source: supplied Lite 12.10.6 APK, SHA-256 `adbead84d31057fbe2d58433fe4f51f09463eb0c007d82ae28df2344462777ed`. Static REA/JADX method references identify eight consumers of `ExteraConfig.getHidePhoneNumber`. This is a display preference, not a Telegram account privacy setting.

`SettingsActivity.setInfo(User)` omits the own phone from the header and joins the username only when present. `ProfileActivity.updateRowsIds` omits the phone row only for the current account; other users are unaffected. `SettingsActivity.fillItems` applies a spoiler to the own number in the phone validation suggestion. These are decompiled observations, not runtime checks. The separate account-search/drawer consumers remain to be matched on iOS.

`profile_phone.json` connects the native settings header (including its phone-based title fallback), own profile phone row, phone setting label, and validation suggestion. On iOS the phone setting action remains available without the number label; validation text uses the localized phone-number label. Other users' contact details and Telegram server privacy rules are unchanged. Returning from settings recomputes the native profile layout.

The parameter appears in the exteraGram settings screen. Compilation and device behavior are recorded separately in VALIDATION.md. This does not yet claim complete parity for account switcher/search surfaces or explicit phone-change screens.
