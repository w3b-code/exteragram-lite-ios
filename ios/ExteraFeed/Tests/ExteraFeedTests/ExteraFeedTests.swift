import Foundation
import XCTest
@testable import ExteraFeed

final class ExteraFeedTests: XCTestCase {
    private func peer(_ channel: Int64, account: String = "account-a") throws -> ExteraFeedPeerID {
        try ExteraFeedPeerID(account: account, channel: channel)
    }
    private func row(_ channel: Int64, _ message: Int32, _ date: Int32, kind: ExteraFeedRecordKind = .post,
                     revision: Int64 = 0, album: Int64? = nil, text: String = "", namespace: Int32 = 0) throws -> ExteraFeedRecord {
        ExteraFeedRecord(id: try ExteraFeedMessageID(peer: peer(channel), namespace: namespace, message: message), timestamp: date,
                         revision: revision, kind: kind, albumID: album, payload: text)
    }
    private func state(_ channels: [ExteraFeedChannel]) throws -> ExteraFeedState {
        var state = try ExteraFeedState(configuration: ExteraFeedConfiguration(account: "account-a"))
        try state.replaceChannels(channels)
        return state
    }
    private func assertError(_ expected: ExteraFeedError, file: StaticString = #filePath, line: UInt = #line,
                             _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ExteraFeedError, expected, file: file, line: line)
        }
    }

    func testCompositeIdentityAndDecodedValidation() throws {
        let a = try ExteraFeedMessageID(peer: peer(1), message: 7)
        let b = try ExteraFeedMessageID(peer: peer(2), message: 7)
        let c = try ExteraFeedMessageID(peer: peer(1, account: "account-b"), message: 7)
        let d = try ExteraFeedMessageID(peer: peer(1), namespace: 3, message: 7)
        XCTAssertEqual(Set([a, b, c, d]).count, 4)
        XCTAssertEqual(try JSONDecoder().decode(ExteraFeedMessageID.self, from: JSONEncoder().encode(a)), a)
        assertError(.invalidIdentity) { _ = try self.peer(0) }
        assertError(.invalidIdentity) { _ = try ExteraFeedMessageID(peer: self.peer(1), message: 0) }
        XCTAssertThrowsError(try JSONDecoder().decode(ExteraFeedPeerID.self, from: Data("{\"account\":\"a\",\"channel\":-1}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ExteraFeedConfiguration.self, from: Data("{\"account\":\"a\",\"historyNamespace\":0,\"includeArchived\":false,\"excludedChannels\":[-1]}".utf8)))
    }

    func testAndroidNegativeChannelTupleOrderingWithoutOverflow() throws {
        let values = try [row(2, 9, 100), row(1, 9, 100), row(1, 10, 100), row(Int64.max, 30, 100), row(7, 1, 101)]
        let sorted = values.sorted { $0.cursor > $1.cursor }
        XCTAssertEqual(sorted.map(\.id.peer.channel), [7, 1, 1, 2, Int64.max])
        XCTAssertEqual(sorted.map(\.id.message), [1, 10, 9, 9, 30])
        XCTAssertEqual(Set(values.map(\.cursor)).count, 5)
    }

    func testEligibilityArchiveExclusionsAndAccountScopedPersistence() throws {
        let one = try peer(1), two = try peer(2)
        var channels = [ExteraFeedChannel(id: one, unreadCount: 4), ExteraFeedChannel(id: two, isArchived: true, unreadCount: 7),
                        ExteraFeedChannel(id: try peer(3), isBroadcast: false, unreadCount: 20),
                        ExteraFeedChannel(id: try peer(4), isCommunity: true, unreadCount: 20),
                        ExteraFeedChannel(id: try peer(5), isMember: false, unreadCount: 20)]
        var feed = try state(channels)
        XCTAssertEqual(feed.includedPeers, [one])
        var config = try ExteraFeedConfiguration(account: "account-a", includeArchived: true, excludedChannels: [1])
        try feed.updateConfiguration(config)
        XCTAssertEqual(feed.includedPeers, [two])
        XCTAssertEqual(feed.totalUnreadCount, 7)
        XCTAssertEqual(try JSONDecoder().decode(ExteraFeedConfiguration.self, from: JSONEncoder().encode(config)), config)
        config.excludedChannels = [1, 2]
        try feed.updateConfiguration(config)
        XCTAssertTrue(feed.posts.isEmpty)
        XCTAssertEqual(feed.olderCoverage, .complete)
        channels.append(ExteraFeedChannel(id: try peer(1, account: "account-b")))
        assertError(.wrongAccount) { try feed.replaceChannels(channels) }
        XCTAssertTrue(feed.includedPeers.isEmpty)
        assertError(.wrongAccount) { try feed.updateConfiguration(ExteraFeedConfiguration(account: "account-b")) }
    }

    func testGenerationRejectsOldResultsButCounterChangesDoNotInvalidate() throws {
        let one = try peer(1)
        var channel = ExteraFeedChannel(id: one, unreadCount: 1)
        var feed = try state([channel])
        let generation = feed.generation
        let request = try feed.makeRequest(peer: one, direction: .older)
        channel.unreadCount = 9
        try feed.replaceChannels([channel])
        XCTAssertEqual(feed.generation, generation)
        try feed.updateConfiguration(ExteraFeedConfiguration(account: "account-a"))
        XCTAssertEqual(feed.generation, generation)
        try feed.apply(ExteraFeedPage(records: [row(1, 1, 1)], reachedEnd: false, startsAtNewest: true), for: request)
        let old = try feed.makeRequest(peer: one, direction: .older)
        try feed.updateConfiguration(ExteraFeedConfiguration(account: "account-a", excludedChannels: [1]))
        XCTAssertNotEqual(feed.generation, generation)
        assertError(.staleResult) { try feed.apply(ExteraFeedPage(records: [], reachedEnd: true), for: old) }
        XCTAssertEqual(feed.coverage(for: one).olderExhausted, false)
    }

    func testSupersededDuplicateAndOtherSessionResultsAreRejected() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        let obsolete = try feed.makeRequest(peer: one, direction: .older)
        let current = try feed.makeRequest(peer: one, direction: .older)
        let page = try ExteraFeedPage(records: [row(1, 9, 9)], reachedEnd: false, startsAtNewest: true)
        assertError(.staleResult) { try feed.apply(page, for: obsolete) }
        var otherSession = try state([ExteraFeedChannel(id: one)])
        assertError(.staleResult) { try otherSession.apply(page, for: current) }
        try feed.apply(page, for: current)
        assertError(.staleResult) { try feed.apply(page, for: current) }
        XCTAssertEqual(feed.posts.count, 1)
    }

    func testFilteredRowsAdvanceRawCursorAndDoNotBecomePostsOrReads() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        let request = try feed.makeRequest(peer: one, direction: .older)
        let records = try [row(1, 30, 30, kind: .service), row(1, 20, 20), row(1, 10, 10, kind: .empty)]
        try feed.apply(ExteraFeedPage(records: records, reachedEnd: false, startsAtNewest: true), for: request)
        XCTAssertEqual(feed.posts.map(\.id.message), [20])
        XCTAssertEqual(feed.coverage(for: one).oldestRaw?.id.message, 10)
        XCTAssertEqual(try feed.makeRequest(peer: one, direction: .older).bound?.id.message, 10)
        XCTAssertFalse(feed.isUnread(records[0].id))
        XCTAssertFalse(feed.isUnread(records[2].id))
        XCTAssertEqual(feed.olderCoverage, .through(records[2].cursor))
    }

    func testGlobalWatermarkWaitsForEverySourceAndUsesLeastDeepCoverage() throws {
        let one = try peer(1), two = try peer(2)
        var feed = try state([ExteraFeedChannel(id: one), ExteraFeedChannel(id: two)])
        let a = try feed.makeRequest(peer: one, direction: .older)
        try feed.apply(ExteraFeedPage(records: [row(1, 10, 100), row(1, 8, 80)], reachedEnd: false, startsAtNewest: true), for: a)
        XCTAssertEqual(feed.olderCoverage, .waiting([two]))
        XCTAssertTrue(feed.coveredPosts.isEmpty)
        let b = try feed.makeRequest(peer: two, direction: .older)
        let boundary = try row(2, 9, 90)
        try feed.apply(ExteraFeedPage(records: [row(2, 11, 110), boundary], reachedEnd: false, startsAtNewest: true), for: b)
        XCTAssertEqual(feed.olderCoverage, .through(boundary.cursor))
        XCTAssertEqual(feed.coveredPosts.map(\.timestamp), [110, 100, 90])
        let endA = try feed.makeRequest(peer: one, direction: .older)
        try feed.apply(ExteraFeedPage(records: [], reachedEnd: true), for: endA)
        XCTAssertEqual(feed.olderCoverage, .through(boundary.cursor))
        let endB = try feed.makeRequest(peer: two, direction: .older)
        try feed.apply(ExteraFeedPage(records: [], reachedEnd: true), for: endB)
        XCTAssertEqual(feed.olderCoverage, .complete)
        XCTAssertEqual(feed.coveredPosts.count, 4)
    }

    func testNewestCoverageIsExplicitAndNewerPagesUseAscendingRawCursor() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        assertError(.noAnchor) { _ = try feed.makeRequest(peer: one, direction: .newer) }
        let initial = try feed.makeRequest(peer: one, direction: .older)
        try feed.apply(ExteraFeedPage(records: [row(1, 10, 10)], reachedEnd: true), for: initial)
        XCTAssertEqual(feed.olderCoverage, .waiting([one]))
        let newer = try feed.makeRequest(peer: one, direction: .newer)
        try feed.apply(ExteraFeedPage(records: [row(1, 11, 11, kind: .empty), row(1, 12, 12)], reachedEnd: false), for: newer)
        XCTAssertEqual(feed.coverage(for: one).newestRaw?.id.message, 12)
        XCTAssertEqual(feed.olderCoverage, .waiting([one]))
        let end = try feed.makeRequest(peer: one, direction: .newer)
        try feed.apply(ExteraFeedPage(records: [], reachedEnd: true), for: end)
        XCTAssertEqual(feed.olderCoverage, .complete)
        try feed.noteNewerAvailable(peer: one)
        XCTAssertEqual(feed.olderCoverage, .waiting([one]))
    }

    func testTemporaryFailureIsRetryableAndNeverExhaustion() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        let request = try feed.makeRequest(peer: one, direction: .older)
        try feed.fail(request, reason: .floodWait)
        XCTAssertEqual(feed.coverage(for: one).failures[.older], .floodWait)
        XCTAssertFalse(feed.coverage(for: one).olderExhausted)
        assertError(.staleResult) { try feed.fail(request, reason: .network) }
        let retry = try feed.makeRequest(peer: one, direction: .older)
        try feed.apply(ExteraFeedPage(records: [], reachedEnd: true, startsAtNewest: true), for: retry)
        XCTAssertNil(feed.coverage(for: one).failures[.older])
        XCTAssertEqual(feed.olderCoverage, .complete)
    }

    func testLivePostDuringRequestCannotFalselyCertifyNewestEdge() throws {
        let one = try peer(1)
        var channel = ExteraFeedChannel(id: one, topMessageID: 10)
        var feed = try state([channel])
        let initial = try feed.makeRequest(peer: one, direction: .older)
        try feed.mergeUpdates([row(1, 11, 11)])
        try feed.apply(ExteraFeedPage(records: [row(1, 10, 10)], reachedEnd: true, startsAtNewest: true), for: initial)
        XCTAssertEqual(feed.olderCoverage, .waiting([one]))
        let catchUp = try feed.makeRequest(peer: one, direction: .newer)
        try feed.apply(ExteraFeedPage(records: [row(1, 11, 11)], reachedEnd: true), for: catchUp)
        XCTAssertEqual(feed.olderCoverage, .complete)
        let refresh = try feed.makeRequest(peer: one, direction: .newer)
        channel.topMessageID = 12
        try feed.replaceChannels([channel])
        try feed.apply(ExteraFeedPage(records: [], reachedEnd: true), for: refresh)
        XCTAssertEqual(feed.olderCoverage, .waiting([one]))
    }

    func testEditDedupDeletionAndLatePagesCannotResurrectDeletedPost() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        let edited = try row(1, 20, 20, revision: 2, text: "edited")
        try feed.mergeUpdates([edited, edited])
        try feed.mergeUpdates([row(1, 20, 20, revision: 1, text: "old")])
        XCTAssertEqual(feed.posts.map(\.payload), ["edited"])
        try feed.delete([edited.id])
        let request = try feed.makeRequest(peer: one, direction: .older)
        try feed.apply(ExteraFeedPage(records: [edited, row(1, 10, 10)], reachedEnd: false, startsAtNewest: true), for: request)
        try feed.mergeUpdates([edited])
        XCTAssertEqual(feed.posts.map(\.id.message), [10])
        XCTAssertEqual(feed.coverage(for: one).newestRaw?.id.message, 20)
    }

    func testAlbumsNeverJoinDifferentChannelsAndCompletenessIsCertified() throws {
        let one = try peer(1), two = try peer(2)
        var feed = try state([ExteraFeedChannel(id: one), ExteraFeedChannel(id: two)])
        try feed.mergeUpdates([row(1, 5, 5, album: 77), row(2, 5, 5, album: 77), row(1, 4, 4, album: 77)])
        XCTAssertEqual(feed.timeline.count, 2)
        XCTAssertEqual(feed.timeline.first?.records.map(\.id.peer), [one, one])
        XCTAssertEqual(feed.timeline.last?.records.map(\.id.peer), [two])
        XCTAssertTrue(feed.timeline.allSatisfy { !$0.isComplete })
        try feed.certifyAlbumComplete(peer: one, albumID: 77)
        XCTAssertTrue(feed.timeline[0].isComplete)
        XCTAssertFalse(feed.timeline[1].isComplete)
        try feed.mergeUpdates([row(1, 3, 3, album: 77)])
        XCTAssertFalse(feed.timeline[0].isComplete)
        XCTAssertEqual(feed.timeline[0].records.count, 3)
    }

    private var activeVisibility: ExteraFeedVisibility {
        ExteraFeedVisibility(viewportActive: true, sceneActive: true, hostResumed: true, initialPositionApplied: true, readyToMarkRead: true)
    }
    func testEveryVisibilityGateAndActualVisibilityPreventsPrematureRead() throws {
        let one = try peer(1), value = try row(1, 4, 4)
        var gates: [ExteraFeedVisibility] = []
        var gate = activeVisibility; gate.viewportActive = false; gates.append(gate)
        gate = activeVisibility; gate.sceneActive = false; gates.append(gate)
        gate = activeVisibility; gate.hostResumed = false; gates.append(gate)
        gate = activeVisibility; gate.initialPositionApplied = false; gates.append(gate)
        gate = activeVisibility; gate.readyToMarkRead = false; gates.append(gate)
        gate = activeVisibility; gate.restoreOrDividerPending = true; gates.append(gate)
        gate = activeVisibility; gate.sheetPresented = true; gates.append(gate)
        var feed = try state([ExteraFeedChannel(id: one)])
        try feed.mergeUpdates([value])
        for gate in gates { feed.onVisible(value.id, actuallyVisible: true, visibility: gate) }
        feed.onVisible(value.id, actuallyVisible: false, visibility: activeVisibility)
        XCTAssertTrue(feed.drainReadMaxima().isEmpty)
        feed.onVisible(value.id, actuallyVisible: true, visibility: activeVisibility)
        XCTAssertEqual(feed.drainReadMaxima(), [one: 4])
    }

    func testUnreadCountsAllIncludedChannelsAndReadBatchesKeepRealPerPeerMaxima() throws {
        let one = try peer(1), two = try peer(2), archived = try peer(3)
        var feed = try state([ExteraFeedChannel(id: one, unreadCount: 100, maxReadMessageID: 2, topMessageID: 50),
                              ExteraFeedChannel(id: two, isMuted: true, unreadCount: 200, topMessageID: 40),
                              ExteraFeedChannel(id: archived, isArchived: true, unreadCount: 300)])
        XCTAssertEqual(feed.totalUnreadCount, 300) // No rows loaded; muted channels still count.
        try feed.mergeUpdates([row(1, 3, 9), row(1, 8, 8), row(2, 5, 7), row(2, 6, 6, kind: .sponsored)])
        for value in feed.posts { feed.onVisible(value.id, actuallyVisible: true, visibility: activeVisibility) }
        XCTAssertEqual(feed.drainReadMaxima(), [one: 8, two: 5])
        XCTAssertEqual(feed.totalUnreadCount, 300) // Do not guess server counters from cached rows.
        XCTAssertEqual(feed.markAllReadCandidates, [one: 50, two: 40])
        try feed.requeueReadMaxima([one: 8, two: 5])
        try feed.updateConfiguration(ExteraFeedConfiguration(account: "account-a", excludedChannels: [2]))
        XCTAssertEqual(feed.drainReadMaxima(), [one: 8])
        XCTAssertEqual(feed.totalUnreadCount, 100)
        XCTAssertEqual(feed.markAllReadCandidates, [one: 50])
    }

    func testInvalidPagesAreAtomicAndNamespaceIsPreserved() throws {
        let one = try peer(1)
        var feed = try state([ExteraFeedChannel(id: one)])
        let token = try feed.makeRequest(peer: one, direction: .older)
        assertError(.invalidPage) { try feed.apply(ExteraFeedPage(records: [row(1, 1, 1), row(1, 2, 2)], reachedEnd: false), for: token) }
        assertError(.invalidPage) { try feed.apply(ExteraFeedPage(records: [row(1, 1, 1, namespace: 3)], reachedEnd: false), for: token) }
        assertError(.nonAdvancingPage) { try feed.apply(ExteraFeedPage(records: [], reachedEnd: false), for: token) }
        XCTAssertNil(feed.coverage(for: one).oldestRaw)
        XCTAssertTrue(feed.posts.isEmpty)
        try feed.apply(ExteraFeedPage(records: [row(1, 2, 2)], reachedEnd: false, startsAtNewest: true), for: token)
        XCTAssertEqual(feed.posts.first?.id.namespace, 0)
        let older = try feed.makeRequest(peer: one, direction: .older)
        assertError(.nonAdvancingPage) { try feed.apply(ExteraFeedPage(records: [row(1, 2, 2)], reachedEnd: false), for: older) }
        XCTAssertEqual(feed.posts.count, 1)
    }
}
