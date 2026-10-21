import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public enum ExteraFeedNativeError: Error {
    case unsupportedFolder
    case invalidCursor
    case unavailablePeer
    case unsupportedChannel
    case invalidResponse
    case nonAdvancingPage
    case requestFailed(String)
    case timedOut
}

/// An opaque, account-bound cursor. Retains the access hash from the response,
/// so paging never depends on writing a peer into Postbox first.
public struct ExteraFeedDialogPageCursor {
    public let folderID: Int32
    public let index: MessageIndex
    fileprivate let accountPeerID: PeerId
    fileprivate let inputPeer: Api.InputPeer
}

public struct ExteraFeedNativeChannel {
    public let peer: TelegramChannel
    public let folderID: Int32
    public let unreadCount: Int32
    public let maxReadMessageID: Int32
    public let topMessageID: Int32
}

public struct ExteraFeedNativeDialogPage {
    public let channels: [ExteraFeedNativeChannel]
    public let scannedDialogCount: Int
    public let next: ExteraFeedDialogPageCursor?
    public let reachedEnd: Bool
}

public struct ExteraFeedNativeHistoryPage {
    /// Full real messages and media references; no IDs or timestamps are rewritten.
    public let messages: [Message]
    public let rawMessageIDs: [Int32]
    /// Empty server records have no timestamp. The adapter must not invent one
    /// to certify a chronological coverage boundary in the portable feed core.
    public let unavailableMessageIDs: [MessageId]
    public let nextOffsetID: Int32?
    public let snapshotMaxMessageID: Int32?
    public let reachedEnd: Bool
}

private func exteraFeedNativeSignal<T>(_ result: Result<T, ExteraFeedNativeError>) -> Signal<T, ExteraFeedNativeError> {
    switch result {
    case let .success(value): return .single(value)
    case let .failure(error): return .fail(error)
    }
}

private func exteraFeedNativePeers(transaction: Transaction, chats: [Api.Chat], users: [Api.User]) -> [PeerId: Peer] {
    var peers: [PeerId: Peer] = [:]
    for user in users {
        if let peer = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
            peers[peer.id] = peer
        }
    }
    for chat in chats {
        if let peer = mergeGroupOrChannel(lhs: transaction.getPeer(chat.peerId), rhs: chat) {
            peers[peer.id] = peer
        }
    }
    return peers
}

/// Reads a page of joined broadcast channels from exactly root (0) or archive
/// (1). The caller follows `next` through both folders to enumerate the catalog.
/// A filtered channel array being empty does not imply end of the raw dialogs.
/// Pinned dialogs are fetched separately on the first page. No local data or
/// read state is written; disposal cancels requests, with a bounded timeout.
public func exteraFeedLoadDialogPage(account: Account, folderID: Int32,
                                     cursor: ExteraFeedDialogPageCursor? = nil) -> Signal<ExteraFeedNativeDialogPage, ExteraFeedNativeError> {
    guard folderID == 0 || folderID == 1 else { return .fail(.unsupportedFolder) }
    if let cursor, cursor.folderID != folderID || cursor.accountPeerID != account.peerId { return .fail(.invalidCursor) }
    let pinned: Signal<Api.messages.PeerDialogs?, ExteraFeedNativeError>
    if cursor == nil {
        pinned = account.network.request(Api.functions.messages.getPinnedDialogs(folderId: folderID), automaticFloodWait: false)
        |> mapError { ExteraFeedNativeError.requestFailed($0.errorDescription) }
        |> map { Optional($0) }
    } else {
        pinned = .single(nil)
    }
    // Both folder_id and exclude_pinned are set. Pinned peers cannot distort
    // the non-pinned offset, and are included by the separate first-page call.
    let dialogs = account.network.request(Api.functions.messages.getDialogs(flags: (1 << 0) | (1 << 1), folderId: folderID,
        offsetDate: cursor?.index.timestamp ?? 0, offsetId: cursor?.index.id.id ?? 0,
        offsetPeer: cursor?.inputPeer ?? .inputPeerEmpty, limit: 100, hash: 0), automaticFloodWait: false)
    |> mapError { ExteraFeedNativeError.requestFailed($0.errorDescription) }

    let signal = combineLatest(dialogs, pinned)
    |> mapToSignal { response, pinned -> Signal<ExteraFeedNativeDialogPage, ExteraFeedNativeError> in
        let rawDialogs: [Api.Dialog]
        var chats: [Api.Chat]
        var users: [Api.User]
        let messages: [Api.Message]
        let reachedEnd: Bool
        switch response {
        case let .dialogs(value):
            rawDialogs = value.dialogs; chats = value.chats; users = value.users; messages = value.messages; reachedEnd = true
        case let .dialogsSlice(value):
            rawDialogs = value.dialogs; chats = value.chats; users = value.users; messages = value.messages; reachedEnd = value.dialogs.isEmpty
        case .dialogsNotModified:
            return .fail(.invalidResponse)
        }
        var allDialogs = rawDialogs
        if let pinned {
            switch pinned {
            case let .peerDialogs(value):
                allDialogs.append(contentsOf: value.dialogs)
                chats.append(contentsOf: value.chats)
                users.append(contentsOf: value.users)
            }
        }
        return account.postbox.transaction { transaction -> Result<ExteraFeedNativeDialogPage, ExteraFeedNativeError> in
            let peers = exteraFeedNativePeers(transaction: transaction, chats: chats, users: users)
            var channels: [PeerId: ExteraFeedNativeChannel] = [:]
            for dialog in allDialogs {
                guard case let .dialog(value) = dialog,
                      let channel = peers[value.peer.peerId] as? TelegramChannel,
                      channel.participationStatus == .member, case .broadcast = channel.info else { continue }
                channels[channel.id] = ExteraFeedNativeChannel(peer: channel, folderID: folderID,
                    unreadCount: max(0, value.unreadCount), maxReadMessageID: max(0, value.readInboxMaxId), topMessageID: max(0, value.topMessage))
            }
            var next: ExteraFeedDialogPageCursor?
            if !reachedEnd {
                var topIDs: Set<MessageId> = []
                for dialog in rawDialogs {
                    if case let .dialog(value) = dialog, (value.flags & (1 << 2)) == 0, value.topMessage > 0 {
                        topIDs.insert(MessageId(peerId: value.peer.peerId, namespace: Namespaces.Message.Cloud, id: value.topMessage))
                    }
                }
                var lower: MessageIndex?
                var matched: Set<MessageId> = []
                for apiMessage in messages {
                    guard let stored = StoreMessage(apiMessage: apiMessage, accountPeerId: account.peerId, peerIsForum: false),
                          case let .Id(id) = stored.id, topIDs.contains(id) else { continue }
                    matched.insert(id)
                    let index = MessageIndex(id: id, timestamp: stored.timestamp)
                    lower = lower.map { min($0, index) } ?? index
                }
                // Missing dates/metadata must remain an explicit gap, rather
                // than skip dialogs or restart at inputPeerEmpty.
                guard matched == topIDs, let lower else { return .failure(.invalidResponse) }
                if let cursor, !(lower < cursor.index) { return .failure(.nonAdvancingPage) }
                let inputPeer: Api.InputPeer
                if lower.id.peerId == account.peerId {
                    inputPeer = .inputPeerSelf
                } else if let peer = peers[lower.id.peerId] ?? transaction.getPeer(lower.id.peerId), let input = apiInputPeer(peer) {
                    inputPeer = input
                } else {
                    return .failure(.unavailablePeer)
                }
                next = ExteraFeedDialogPageCursor(folderID: folderID, index: lower, accountPeerID: account.peerId, inputPeer: inputPeer)
            }
            let values = channels.values.sorted { $0.peer.id < $1.peer.id }
            return .success(ExteraFeedNativeDialogPage(channels: values, scannedDialogCount: rawDialogs.count, next: next, reachedEnd: reachedEnd))
        }
        |> castError(ExteraFeedNativeError.self)
        |> mapToSignal { result -> Signal<ExteraFeedNativeDialogPage, ExteraFeedNativeError> in exteraFeedNativeSignal(result) }
    }
    return signal |> timeout(30.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timedOut))
}

/// An older-history transport primitive, with independent raw ID progress.
/// A future coordinator owns newer paging, cache/hole observation and feed core
/// coverage. Fetching these pages does not mark a post read or increment views.
public func exteraFeedLoadHistoryPage(account: Account, channel: TelegramChannel, offsetID: Int32 = 0,
                                      snapshotMaxMessageID: Int32? = nil) -> Signal<ExteraFeedNativeHistoryPage, ExteraFeedNativeError> {
    guard channel.participationStatus == .member, case .broadcast = channel.info,
          let inputPeer = apiInputPeer(channel) else { return .fail(.unsupportedChannel) }
    guard offsetID >= 0, snapshotMaxMessageID.map({ $0 > 0 }) ?? true else { return .fail(.invalidCursor) }
    let maxID = snapshotMaxMessageID.map { $0 < Int32.max ? $0 + 1 : 0 } ?? 0
    let signal = account.network.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: offsetID, offsetDate: 0,
        addOffset: 0, limit: 100, maxId: maxID, minId: 0, hash: 0), automaticFloodWait: false)
    |> mapError { ExteraFeedNativeError.requestFailed($0.errorDescription) }
    |> mapToSignal { response -> Signal<ExteraFeedNativeHistoryPage, ExteraFeedNativeError> in
        let raw: [Api.Message]
        let chats: [Api.Chat]
        let users: [Api.User]
        switch response {
        case let .messages(value): raw = value.messages; chats = value.chats; users = value.users
        case let .messagesSlice(value): raw = value.messages; chats = value.chats; users = value.users
        case let .channelMessages(value): raw = value.messages; chats = value.chats; users = value.users
        case .messagesNotModified: return .fail(.invalidResponse)
        }
        let ids = raw.map(\.rawId)
        guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { return .fail(.invalidResponse) }
        if offsetID != 0, !ids.allSatisfy({ $0 < offsetID }) { return .fail(.nonAdvancingPage) }
        if let snapshotMaxMessageID, !ids.allSatisfy({ $0 <= snapshotMaxMessageID }) { return .fail(.invalidResponse) }
        return account.postbox.transaction { transaction -> Result<ExteraFeedNativeHistoryPage, ExteraFeedNativeError> in
            var peers = exteraFeedNativePeers(transaction: transaction, chats: chats, users: users)
            if peers[channel.id] == nil { peers[channel.id] = channel }
            var messages: [Message] = []
            var unavailable: [MessageId] = []
            for apiMessage in raw {
                if case .messageEmpty = apiMessage {
                    unavailable.append(MessageId(peerId: channel.id, namespace: Namespaces.Message.Cloud, id: apiMessage.rawId))
                    continue
                }
                guard let stored = StoreMessage(apiMessage: apiMessage, accountPeerId: account.peerId, peerIsForum: false),
                      let message = locallyRenderedMessage(message: stored, peers: peers), message.id.peerId == channel.id else {
                    return .failure(.invalidResponse)
                }
                messages.append(message)
            }
            return .success(ExteraFeedNativeHistoryPage(messages: messages, rawMessageIDs: ids, unavailableMessageIDs: unavailable,
                nextOffsetID: ids.min(), snapshotMaxMessageID: snapshotMaxMessageID ?? ids.max(), reachedEnd: raw.isEmpty))
        }
        |> castError(ExteraFeedNativeError.self)
        |> mapToSignal { result -> Signal<ExteraFeedNativeHistoryPage, ExteraFeedNativeError> in exteraFeedNativeSignal(result) }
    }
    return signal |> timeout(30.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timedOut))
}
