# Composer preferences

The supplied Lite's `getDisableMarkdown` has three statically identified consumers: `MediaDataController.getEntities`, `EditTextBoldCursor.addMarkdownToggle`, and `EditTextBoldCursor.onTextContextMenuItem`. The editor menu exposes Enable/Disable Markdown. This is not a request to remove explicit formatting entities.

The iOS patch gates the common `TextFormat.convertMarkdownToAttributes` transformer. When disabled, it returns the original attributed string, retaining visible delimiters, manual formatting and mention entities. When enabled, the native parser runs unchanged. This shared transformer is used by normal send/edit and related rich-input paths. A real switch is exposed in exteraGram settings; the Android-style quick editor-menu toggle remains to be added. `addCommaAfterMention` remains unconnected pending exact scope verification.

This source integration is not a device behavior claim. See VALIDATION.md for actual compilation results.
