# Hidden send-as button

`hideSendAsPeer` hides the composer sender avatar and removes its text-field inset in all three native layout paths. It leaves the selected sending identity and Telegram account state intact. This is a visual preference, not a request to change the sender.

As described by the supplied Lite localization `HideSendAsPeerInfo`, long-pressing the emoji/sticker input button still opens sender selection. A separate transparent `ContextReferenceContentNode` anchors the existing Telegram menu at that button. Its normal send-as eligibility, Premium checks and `updatePeerSendAsPeer` request are reused. The recognizer is enabled only when the preference is on, peers are available, and the composer is not editing a message.

Recognizer reconciliation uses each current accessory item, including when native buttons are reused between input modes. It attaches once for `.input`, disables a prior recognizer if an item changes type, and rechecks the item on activation. Both button-array replacement paths are covered. The main layout updates `presentationInterfaceState` before reconciliation; an unchanged state remains current. The transparent anchor does not intercept touches.

Static APK incoming-reference evidence points to `ChatActivityEnterView` construction, sender-selection updates and dismissal. The source patch is checked against pinned Telegram iOS. Patch application and reapplication pass; compilation of this composer change and long-press behavior on an iPhone are still pending.
