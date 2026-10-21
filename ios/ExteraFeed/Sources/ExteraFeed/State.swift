import Foundation

/// Value-semantic state, not a scheduler. Own it on one actor/serial queue, or
/// pass snapshots between executors. There is no shared global account state.
public struct ExteraFeedState: Sendable {
    private struct RequestKey: Hashable, Sendable { let peer: ExteraFeedPeerID; let direction: ExteraFeedDirection }
    private struct AlbumKey: Hashable, Sendable { let peer: ExteraFeedPeerID; let id: Int64 }
    public private(set) var configuration: ExteraFeedConfiguration
    public private(set) var generation = UUID()
    private var channels: [ExteraFeedPeerID: ExteraFeedChannel] = [:]
    private var records: [ExteraFeedMessageID: ExteraFeedRecord] = [:]
    private var deleted: Set<ExteraFeedMessageID> = []
    private var sources: [ExteraFeedPeerID: ExteraFeedSourceCoverage] = [:]
    private var newestEpochs: [ExteraFeedPeerID: UUID] = [:]
    private var requests: [RequestKey: ExteraFeedRequest] = [:]
    private var completeAlbums: Set<AlbumKey> = []
    private var pendingReads: [ExteraFeedPeerID: Int32] = [:]
    private var effectiveReads: [ExteraFeedPeerID: Int32] = [:]

    public init(configuration: ExteraFeedConfiguration) throws {
        guard !configuration.account.isEmpty, configuration.excludedChannels.allSatisfy({ $0 > 0 }) else { throw ExteraFeedError.invalidIdentity }
        self.configuration = configuration
    }
    public var includedPeers: Set<ExteraFeedPeerID> { Set(channels.values.filter(configuration.includes).map(\.id)) }
    public var totalUnreadCount: Int64 { channels.values.filter(configuration.includes).reduce(0) { $0 + Int64(max(0, $1.unreadCount)) } }

    public mutating func updateConfiguration(_ value: ExteraFeedConfiguration) throws {
        guard value.account == configuration.account else { throw ExteraFeedError.wrongAccount }
        guard value.historyNamespace == configuration.historyNamespace else { throw ExteraFeedError.invalidIdentity }
        guard value.excludedChannels.allSatisfy({ $0 > 0 }) else { throw ExteraFeedError.invalidIdentity }
        guard value != configuration else { return }
        configuration = value
        invalidateRequests()
        discardExcludedReads()
    }

    /// Metadata/read-counter changes preserve in-flight pages. Changes to the
    /// included source set invalidate every outstanding request generation.
    public mutating func replaceChannels(_ values: [ExteraFeedChannel]) throws {
        guard values.allSatisfy({ $0.id.account == configuration.account }) else { throw ExteraFeedError.wrongAccount }
        guard values.allSatisfy({ $0.id.channel > 0 }) else { throw ExteraFeedError.invalidIdentity }
        guard Set(values.map(\.id)).count == values.count else { throw ExteraFeedError.duplicateChannel }
        let previous = includedPeers
        let previousChannels = channels
        let updated = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let removed = Set(channels.keys).subtracting(updated.keys)
        channels = updated
        for peer in removed { sources.removeValue(forKey: peer); effectiveReads.removeValue(forKey: peer); newestEpochs.removeValue(forKey: peer) }
        records = records.filter { !removed.contains($0.key.peer) }
        completeAlbums = completeAlbums.filter { !removed.contains($0.peer) }
        for channel in values {
            effectiveReads[channel.id] = max(effectiveReads[channel.id] ?? 0, channel.maxReadMessageID)
            if let old = previousChannels[channel.id], channel.topMessageID > old.topMessageID { invalidateNewest(channel.id) }
        }
        if previous != includedPeers { invalidateRequests() }
        discardExcludedReads()
    }

    private mutating func invalidateRequests() { generation = UUID(); requests.removeAll() }
    private mutating func discardExcludedReads() { let included = includedPeers; pendingReads = pendingReads.filter { included.contains($0.key) } }

    public func coverage(for peer: ExteraFeedPeerID) -> ExteraFeedSourceCoverage { sources[peer] ?? ExteraFeedSourceCoverage() }

    /// A complete global older page requires coverage from every included
    /// source. The least-deep source sets the safe merged lower watermark.
    public var olderCoverage: ExteraFeedCoverage {
        var waiting: Set<ExteraFeedPeerID> = []
        var boundaries: [ExteraFeedCursor] = []
        for peer in includedPeers {
            let source = coverage(for: peer)
            guard source.newestCovered else { waiting.insert(peer); continue }
            if !source.olderExhausted {
                if let bound = source.oldestRaw { boundaries.append(bound) } else { waiting.insert(peer) }
            }
        }
        if !waiting.isEmpty { return .waiting(waiting) }
        return boundaries.max().map(ExteraFeedCoverage.through) ?? .complete
    }

    public var posts: [ExteraFeedRecord] {
        let included = includedPeers
        return records.values.filter { included.contains($0.id.peer) }.sorted { $0.cursor > $1.cursor }
    }
    public var coveredPosts: [ExteraFeedRecord] {
        switch olderCoverage {
        case .waiting: return []
        case .complete: return posts
        case let .through(bound): return posts.filter { $0.cursor >= bound }
        }
    }

    public mutating func makeRequest(peer: ExteraFeedPeerID, direction: ExteraFeedDirection) throws -> ExteraFeedRequest {
        guard includedPeers.contains(peer) else { throw ExteraFeedError.unavailableSource }
        let source = coverage(for: peer)
        let bound = direction == .older ? source.oldestRaw : source.newestRaw
        if direction == .newer && bound == nil { throw ExteraFeedError.noAnchor }
        let freshness = newestEpochs[peer] ?? UUID()
        newestEpochs[peer] = freshness
        let token = ExteraFeedRequest(peer: peer, direction: direction, bound: bound, generation: generation, freshness: freshness, identifier: UUID())
        requests[RequestKey(peer: peer, direction: direction)] = token
        return token
    }

    private func isCurrent(_ token: ExteraFeedRequest) -> Bool {
        token.generation == generation && includedPeers.contains(token.peer)
            && requests[RequestKey(peer: token.peer, direction: token.direction)] == token
    }

    public mutating func apply(_ page: ExteraFeedPage, for token: ExteraFeedRequest) throws {
        guard isCurrent(token) else { throw ExteraFeedError.staleResult }
        guard !page.records.isEmpty || page.reachedEnd else { throw ExteraFeedError.nonAdvancingPage }
        guard page.records.allSatisfy({ $0.id.peer == token.peer && $0.id.message > 0 && $0.id.namespace == configuration.historyNamespace }),
              Set(page.records.map(\.id)).count == page.records.count else { throw ExteraFeedError.invalidPage }
        let cursors = page.records.map(\.cursor)
        if let bound = token.bound {
            guard cursors.allSatisfy({ token.direction == .older ? $0 < bound : $0 > bound }) else { throw ExteraFeedError.nonAdvancingPage }
        }
        let expected = cursors.sorted { token.direction == .older ? $0 > $1 : $0 < $1 }
        guard cursors == expected else { throw ExteraFeedError.invalidPage }

        var source = coverage(for: token.peer)
        if let low = cursors.min() { source.oldestRaw = source.oldestRaw.map { min($0, low) } ?? low }
        if let high = cursors.max() { source.newestRaw = source.newestRaw.map { max($0, high) } ?? high }
        if token.direction == .older {
            source.olderExhausted = page.reachedEnd
            if token.bound == nil && page.startsAtNewest { source.newestCovered = token.freshness == newestEpochs[token.peer] }
        } else { source.newestCovered = page.reachedEnd && token.freshness == newestEpochs[token.peer] }
        source.failures.removeValue(forKey: token.direction)
        sources[token.peer] = source
        requests.removeValue(forKey: RequestKey(peer: token.peer, direction: token.direction))
        mergeValidated(page.records)
    }

    /// Transient failures are visible state, never evidence of exhaustion.
    public mutating func fail(_ token: ExteraFeedRequest, reason: ExteraFeedFailure) throws {
        guard isCurrent(token) else { throw ExteraFeedError.staleResult }
        var source = coverage(for: token.peer)
        source.failures[token.direction] = reason
        sources[token.peer] = source
        requests.removeValue(forKey: RequestKey(peer: token.peer, direction: token.direction))
    }

    /// Live edits/new posts need not alter paging cursors: only page coverage
    /// advances those. An older revision never overwrites a newer cached edit.
    public mutating func mergeUpdates(_ values: [ExteraFeedRecord]) throws {
        guard values.allSatisfy({ $0.id.peer.account == configuration.account }) else { throw ExteraFeedError.wrongAccount }
        guard values.allSatisfy({ channels[$0.id.peer] != nil && $0.id.message > 0 && $0.id.namespace == configuration.historyNamespace }) else { throw ExteraFeedError.unavailableSource }
        for value in values where value.kind == .post && !deleted.contains(value.id) && records[value.id] == nil {
            let newest = coverage(for: value.id.peer).newestRaw
            if newest == nil || value.cursor > newest! { invalidateNewest(value.id.peer) }
        }
        mergeValidated(values)
    }
    private mutating func mergeValidated(_ values: [ExteraFeedRecord]) {
        for value in values where value.kind == .post && !deleted.contains(value.id) {
            if let existing = records[value.id], existing.revision > value.revision { continue }
            if let existing = records[value.id], existing.albumID != value.albumID {
                if let group = existing.albumID { completeAlbums.remove(AlbumKey(peer: value.id.peer, id: group)) }
            }
            if let group = value.albumID, records[value.id] == nil { completeAlbums.remove(AlbumKey(peer: value.id.peer, id: group)) }
            records[value.id] = value
        }
    }

    public mutating func delete(_ ids: Set<ExteraFeedMessageID>) throws {
        guard ids.allSatisfy({ $0.peer.account == configuration.account }) else { throw ExteraFeedError.wrongAccount }
        for id in ids {
            if let record = records.removeValue(forKey: id), let group = record.albumID { completeAlbums.remove(AlbumKey(peer: id.peer, id: group)) }
            deleted.insert(id)
        }
    }
    public mutating func noteNewerAvailable(peer: ExteraFeedPeerID) throws {
        guard includedPeers.contains(peer) else { throw ExteraFeedError.unavailableSource }
        invalidateNewest(peer)
    }
    private mutating func invalidateNewest(_ peer: ExteraFeedPeerID) {
        newestEpochs[peer] = UUID()
        var source = coverage(for: peer); source.newestCovered = false; sources[peer] = source
    }

    public mutating func certifyAlbumComplete(peer: ExteraFeedPeerID, albumID: Int64) throws {
        guard includedPeers.contains(peer), albumID != 0 else { throw ExteraFeedError.unavailableSource }
        completeAlbums.insert(AlbumKey(peer: peer, id: albumID))
    }
    public var timeline: [ExteraFeedTimelineItem] {
        let values = posts
        var groups: [AlbumKey: [ExteraFeedRecord]] = [:]
        for value in values { if let album = value.albumID { groups[AlbumKey(peer: value.id.peer, id: album), default: []].append(value) } }
        var emitted: Set<AlbumKey> = []
        var items: [ExteraFeedTimelineItem] = []
        for value in values {
            if let album = value.albumID {
                let key = AlbumKey(peer: value.id.peer, id: album)
                if emitted.insert(key).inserted { items.append(ExteraFeedTimelineItem(peer: key.peer, albumID: album, records: groups[key] ?? [], isComplete: completeAlbums.contains(key))) }
            } else { items.append(ExteraFeedTimelineItem(peer: value.id.peer, albumID: nil, records: [value], isComplete: true)) }
        }
        return items
    }

    public func isUnread(_ id: ExteraFeedMessageID) -> Bool {
        guard includedPeers.contains(id.peer), records[id] != nil else { return false }
        return id.message > max(effectiveReads[id.peer] ?? 0, pendingReads[id.peer] ?? 0)
    }
    public mutating func onVisible(_ id: ExteraFeedMessageID, actuallyVisible: Bool, visibility: ExteraFeedVisibility) {
        guard actuallyVisible, visibility.canMarkRead, isUnread(id) else { return }
        pendingReads[id.peer] = max(pendingReads[id.peer] ?? 0, id.message)
    }
    /// Caller schedules the approximately one-second batch and sends these
    /// maxima through the real Telegram read API. Acknowledged server unread
    /// counters must be supplied via replaceChannels, not guessed from rows.
    public mutating func drainReadMaxima() -> [ExteraFeedPeerID: Int32] {
        discardExcludedReads()
        let result = pendingReads
        for (peer, value) in result { effectiveReads[peer] = max(effectiveReads[peer] ?? 0, value) }
        pendingReads.removeAll()
        return result
    }
    /// Requeue an unacknowledged batch after a failed read RPC. The adapter
    /// must retain drained batches until acknowledged; no network runs here.
    public mutating func requeueReadMaxima(_ values: [ExteraFeedPeerID: Int32]) throws {
        guard values.keys.allSatisfy({ $0.account == configuration.account }), values.values.allSatisfy({ $0 > 0 }) else { throw ExteraFeedError.invalidIdentity }
        let included = includedPeers
        for (peer, value) in values where included.contains(peer) { pendingReads[peer] = max(pendingReads[peer] ?? 0, value) }
    }
    public var markAllReadCandidates: [ExteraFeedPeerID: Int32] {
        Dictionary(uniqueKeysWithValues: channels.values.filter { configuration.includes($0) && $0.topMessageID > 0 }.map { ($0.id, $0.topMessageID) })
    }
}
