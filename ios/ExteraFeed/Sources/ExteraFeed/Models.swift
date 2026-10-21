import Foundation

public enum ExteraFeedError: Error, Equatable, Sendable {
    case invalidIdentity, wrongAccount, duplicateChannel, unavailableSource, noAnchor
    case staleResult, invalidPage, nonAdvancingPage
}

/// A real broadcast-channel identity, scoped to a stable account record.
public struct ExteraFeedPeerID: Hashable, Codable, Sendable {
    public let account: String
    public let channel: Int64
    public init(account: String, channel: Int64) throws {
        guard !account.isEmpty, channel > 0 else { throw ExteraFeedError.invalidIdentity }
        self.account = account; self.channel = channel
    }
    private enum CodingKeys: String, CodingKey { case account, channel }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(account: values.decode(String.self, forKey: .account), channel: values.decode(Int64.self, forKey: .channel))
    }
}

public struct ExteraFeedMessageID: Hashable, Codable, Sendable {
    public let peer: ExteraFeedPeerID
    public let namespace: Int32
    public let message: Int32
    public init(peer: ExteraFeedPeerID, namespace: Int32 = 0, message: Int32) throws {
        guard message > 0 else { throw ExteraFeedError.invalidIdentity }
        self.peer = peer; self.namespace = namespace; self.message = message
    }
    private enum CodingKeys: String, CodingKey { case peer, namespace, message }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(peer: values.decode(ExteraFeedPeerID.self, forKey: .peer), namespace: values.decode(Int32.self, forKey: .namespace), message: values.decode(Int32.self, forKey: .message))
    }
}

/// Ascending chronological order, exactly `(date, -channelID, realMessageID)`
/// within an account/namespace. Compare channels in reverse without negation
/// so Int64 overflow is impossible. Namespace/account provide a total order.
public struct ExteraFeedCursor: Hashable, Codable, Comparable, Sendable {
    public let timestamp: Int32
    public let id: ExteraFeedMessageID
    public init(timestamp: Int32, id: ExteraFeedMessageID) { self.timestamp = timestamp; self.id = id }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.id.peer.account != rhs.id.peer.account { return lhs.id.peer.account < rhs.id.peer.account }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.id.peer.channel != rhs.id.peer.channel { return lhs.id.peer.channel > rhs.id.peer.channel }
        if lhs.id.message != rhs.id.message { return lhs.id.message < rhs.id.message }
        return lhs.id.namespace < rhs.id.namespace
    }
}

public struct ExteraFeedChannel: Equatable, Sendable {
    public let id: ExteraFeedPeerID
    public var isBroadcast: Bool
    public var isCommunity: Bool
    public var isMember: Bool
    public var isArchived: Bool
    public var isMuted: Bool
    public var unreadCount: Int32
    public var maxReadMessageID: Int32
    public var topMessageID: Int32
    public init(id: ExteraFeedPeerID, isBroadcast: Bool = true, isCommunity: Bool = false, isMember: Bool = true,
                isArchived: Bool = false, isMuted: Bool = false, unreadCount: Int32 = 0,
                maxReadMessageID: Int32 = 0, topMessageID: Int32 = 0) {
        self.id = id; self.isBroadcast = isBroadcast; self.isCommunity = isCommunity; self.isMember = isMember
        self.isArchived = isArchived; self.isMuted = isMuted; self.unreadCount = max(0, unreadCount)
        self.maxReadMessageID = max(0, maxReadMessageID); self.topMessageID = max(0, topMessageID)
    }
    public var isEligible: Bool { isBroadcast && !isCommunity && isMember }
}

public struct ExteraFeedConfiguration: Equatable, Codable, Sendable {
    public let account: String
    public let historyNamespace: Int32
    public var includeArchived: Bool
    /// Positive real channel IDs within this configuration's account.
    public var excludedChannels: Set<Int64>
    public init(account: String, historyNamespace: Int32 = 0, includeArchived: Bool = false, excludedChannels: Set<Int64> = []) throws {
        guard !account.isEmpty, excludedChannels.allSatisfy({ $0 > 0 }) else { throw ExteraFeedError.invalidIdentity }
        self.account = account; self.historyNamespace = historyNamespace; self.includeArchived = includeArchived; self.excludedChannels = excludedChannels
    }
    private enum CodingKeys: String, CodingKey { case account, historyNamespace, includeArchived, excludedChannels }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(account: values.decode(String.self, forKey: .account), historyNamespace: values.decode(Int32.self, forKey: .historyNamespace),
                      includeArchived: values.decode(Bool.self, forKey: .includeArchived), excludedChannels: values.decode(Set<Int64>.self, forKey: .excludedChannels))
    }
    public func includes(_ channel: ExteraFeedChannel) -> Bool {
        channel.id.account == account && channel.isEligible && (includeArchived || !channel.isArchived)
            && !excludedChannels.contains(channel.id.channel)
    }
}

public enum ExteraFeedRecordKind: Equatable, Sendable { case post, service, empty, sponsored }

/// Payload is an opaque, caller-owned value for the portable core. The native
/// adapter should retain full real messages separately, keyed by `id`.
public struct ExteraFeedRecord: Equatable, Sendable {
    public let id: ExteraFeedMessageID
    public let timestamp: Int32
    public let revision: Int64
    public let kind: ExteraFeedRecordKind
    public let albumID: Int64?
    public let payload: String
    public init(id: ExteraFeedMessageID, timestamp: Int32, revision: Int64 = 0, kind: ExteraFeedRecordKind = .post,
                albumID: Int64? = nil, payload: String = "") {
        self.id = id; self.timestamp = timestamp; self.revision = revision; self.kind = kind
        self.albumID = albumID == 0 ? nil : albumID; self.payload = payload
    }
    public var cursor: ExteraFeedCursor { ExteraFeedCursor(timestamp: timestamp, id: id) }
}

public enum ExteraFeedDirection: Hashable, Sendable { case older, newer }
public struct ExteraFeedRequest: Equatable, Sendable {
    public let peer: ExteraFeedPeerID
    public let direction: ExteraFeedDirection
    public let bound: ExteraFeedCursor?
    public let generation: UUID
    public let freshness: UUID
    public let identifier: UUID
}

public struct ExteraFeedPage: Sendable {
    public let records: [ExteraFeedRecord]
    /// The adapter must establish this from real source coverage, not merely
    /// the number of cached or filtered records returned.
    public let reachedEnd: Bool
    /// An initial older page can explicitly certify coverage at the newest edge.
    public let startsAtNewest: Bool
    public init(records: [ExteraFeedRecord], reachedEnd: Bool, startsAtNewest: Bool = false) {
        self.records = records; self.reachedEnd = reachedEnd; self.startsAtNewest = startsAtNewest
    }
}

public enum ExteraFeedFailure: Equatable, Sendable { case network, timedOut, floodWait, permission }
public struct ExteraFeedSourceCoverage: Equatable, Sendable {
    public internal(set) var oldestRaw: ExteraFeedCursor?
    public internal(set) var newestRaw: ExteraFeedCursor?
    public internal(set) var olderExhausted = false
    public internal(set) var newestCovered = false
    public internal(set) var failures: [ExteraFeedDirection: ExteraFeedFailure] = [:]
    public init() {}
}

public enum ExteraFeedCoverage: Equatable, Sendable {
    case waiting(Set<ExteraFeedPeerID>)
    /// Every included source covers this timestamp/identity through its newest edge.
    case through(ExteraFeedCursor)
    case complete
}

public struct ExteraFeedTimelineItem: Equatable, Sendable {
    public let peer: ExteraFeedPeerID
    public let albumID: Int64?
    public let records: [ExteraFeedRecord]
    /// False for an album until the adapter explicitly certifies its edge members.
    public let isComplete: Bool
}

public struct ExteraFeedVisibility: Sendable {
    public var viewportActive: Bool
    public var sceneActive: Bool
    public var hostResumed: Bool
    public var initialPositionApplied: Bool
    public var readyToMarkRead: Bool
    public var restoreOrDividerPending: Bool
    public var sheetPresented: Bool
    public init(viewportActive: Bool = false, sceneActive: Bool = false, hostResumed: Bool = false,
                initialPositionApplied: Bool = false, readyToMarkRead: Bool = false,
                restoreOrDividerPending: Bool = false, sheetPresented: Bool = false) {
        self.viewportActive = viewportActive; self.sceneActive = sceneActive; self.hostResumed = hostResumed
        self.initialPositionApplied = initialPositionApplied; self.readyToMarkRead = readyToMarkRead
        self.restoreOrDividerPending = restoreOrDividerPending; self.sheetPresented = sheetPresented
    }
    public var canMarkRead: Bool {
        viewportActive && sceneActive && hostResumed && initialPositionApplied && readyToMarkRead
            && !restoreOrDividerPending && !sheetPresented
    }
}
