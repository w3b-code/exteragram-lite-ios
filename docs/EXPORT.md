# Cloud chat text export

The message context menu offers **Export chat text (HTML/JSON)** in supported, unprotected cloud chats. It exports the whole available history of the selected message's peer, rather than the currently selected messages or the history loaded on screen. A confirmation explains the scope before any history requests start. The result consists of `result.json` and a self-contained `messages.html`, shared through iOS's native share sheet; **Save to Files** can save both documents.

## What is included

Every successfully returned history page is read, following descending Telegram message IDs until a successful empty server response. The first page establishes an upper message-ID bound; later requests exclude newly arriving messages. Output messages are ordered by increasing server ID, preserving conversation order even when dates are equal or unexpected. Export metadata states the peer, title, UTC export time, upper bound and scope. Messages contain ID, Unix timestamp, displayed author and author ID, plain text/caption, visible edit time, a reply ID for replies in the same peer, and attachment metadata. Document metadata includes ID, file name, MIME type and byte size when available. Photo metadata includes its ID. Files are not downloaded or embedded.

The JSON schema is version 1, specific to this iOS port. `completed` means that the cloud-history traversal reached a successful empty page and document generation completed; it does not certify that a destination app saved the shared files. All attachment records have `binaryIncluded: false`. Unavailable/deleted server placeholders remain explicitly marked `kind: unavailable`; missing service details are identified by `kind: service`. Other media types have a generic `other_media` attachment marker.

HTML escapes every dynamic text field, includes no scripts or external assets, creates no active links from message text or attachment names, and carries a restrictive content security policy. Attachment names are metadata, never output paths. All documents use fixed filenames inside a newly created temporary directory. JSON uses Foundation's encoder with stable keys; UTC dates use ISO 8601 independently of device locale/time zone. Conversion to both output documents happens off the main thread. iOS files use complete file protection and are removed after the share sheet completes, on generation failure, or after a canceled job's background encoding finishes. App termination can leave protected temporary files for subsequent OS temporary-directory cleanup.

## Boundaries and failures

This is a live, paginated cloud-history read using the signed-in account's existing access. It does not recover deleted or inaccessible messages, take a server-side transactional snapshot, include another account, or follow a group's migration into its older peer. Edits/deletions while the export runs can affect results. Forums, monoforums and secret chats are explicitly unsupported. Copy-protected chats/messages are blocked. Ephemeral or secret media are omitted and their count is recorded.

The adapter does not export media binaries, rich-text entities, reactions, poll choices, detailed service-action payloads, contact lists, sessions, profile photos, stories, or an entire Telegram account. HTML and JSON are usable documents but do not reproduce the APK's exact directory structure or JSON schema. The confirmation and each document state these limitations.

The current in-memory implementation limits a job to 100,000 server records and a 20 MiB conservative content budget. The budget charges UTF-8 text/metadata bytes with allowance for escaping in both formats and fixed record/attachment overhead. Either limit fails explicitly without producing a completed export; it is not a silent truncation. Each server request has a 60-second UI timeout. Telegram RPC errors, flood limits, malformed responses, unrenderable non-placeholder records, repeated/non-advancing pages and local write failures also stop the job. No cached or selected-message subset is presented as a full successful export. The user can cancel the loading indicator; it disposes the pending request and prevents a subsequent share sheet. Bounded background encoding already in progress finishes and removes its temporary files.

The UI requests no new iOS data permission: it uses the authenticated Telegram connection and then presents the system share sheet. The destination and any resulting external disclosure are chosen there by the user. Export does not mark messages read or insert history pages into Postbox.

## Implementation API

`ExteraExport` is a Foundation-only Swift package (iOS 15+/macOS 12+). `ExteraExportMessage`, `ExteraExportAttachment`, `ExteraExportDocument` and `ExteraExportPage` are Sendable value types. `ExteraExportAccumulator.append` validates cursor progress, page consistency, content budgets and the explicit empty terminal page. A rejected page permanently marks that accumulator failed, so appending an empty page afterwards cannot produce a completed partial export. `document` throws until the terminal page arrives without a prior failure. `ExteraExportEncoder.json`, `.html`, `.escapeHTML` and `.utcDate` encode results. No networking occurs in this package.

`exteraExportCloudHistoryPage(account:peerId:offsetId:snapshotMaxMessageId:)` is the production TelegramCore adapter. It returns `Signal<ExteraExportPage, ExteraExportHistoryError>`, requests `messages.getHistory` in pages of 100 with automatic flood waiting disabled, and retains errors instead of converting them into an empty successful response. Its temporary rendering map uses upstream `StoreMessage` and `locallyRenderedMessage`. The UI owns sequential requests, timeout, cancellation, document writing and native sharing.

## APK evidence

Source artifact: `exteraGram-lite-universal-20261004.apk`, SHA-256 `adbead84d31057fbe2d58433fe4f51f09463eb0c007d82ae28df2344462777ed`. Focused static inspection with the existing JADX 0.7.1 headless bundle found:

- `export.ExportSettings`: default `Format.Json`, one optional input peer, from/till date fields, media type mask 1 and size limit 8,388,608 bytes.
- `export.output.AbstractWriter.Format`: `Html`, `Json`, `HtmlAndJson`.
- `export.output.json.JsonWriter`: `result.json`, per-chat `info.json`, numbered `messagesN.json`, and file switching based on groups of 100 messages. It applies date filtering before serializing messages.
- `export.controllers.ExportRequestsController`: offset/limit history requests and Takeout request wrapping, including Takeout session completion.

These are static observations, not an observed Android export. JADX reported one transitive `ConstructorVisitor` error in `HtmlWriter.getTextFromAction`; exact HTML service-action behavior is therefore unresolved. The selected settings, writer-format enum, JSON writer and request-controller evidence was sufficient for the scoped implementation above. The iOS implementation uses ordinary authorized history requests and does not implement Telegram's Takeout account-export workflow. No developer credentials were extracted or reused.

## Validation

Seven deterministic package tests cover terminal-page requirements and ordering, repeated/newer-page rejection, cursor progress across omitted records, record caps/malformed pages, content-budget failures before state mutation, Unicode/document metadata JSON round trips with stable UTC dates, and HTML injection/path escaping. These tests do not exercise a Telegram account or iOS sharing.

All three export patch anchors matched the immutable pinned upstream commit `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`. The aggregate `apply_port.py --check` passed with 116 planned files. A second virtual pass of every patch registry produced exactly the same 67 patch/overlay file contents, without writing to upstream; export and speech have separate insertion anchors. Swift package tests require the macOS CI runner because this Windows host has no Swift compiler. Full Telegram device compilation and authenticated multi-page, flood-error, large-chat, cancellation, protected-chat and Save-to-Files behavior still need CI/device verification.
