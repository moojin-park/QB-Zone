import XCTest

@testable import PocketVector

final class GameCenterServiceTests: XCTestCase {
    func testHighScoreAcknowledgementDoesNotLoseNewerValue() throws {
        let playerID = GameCenterPlayerID("player-a")
        var queue = AccountScopedGameCenterQueue()

        queue.enqueueHighScore(1_000, for: playerID)
        let firstBatch = try XCTUnwrap(queue.batch(for: playerID))
        XCTAssertEqual(firstBatch.highScore, 1_000)

        queue.enqueueHighScore(2_500, for: playerID)
        XCTAssertTrue(queue.acknowledge(firstBatch))

        let remainingBatch = try XCTUnwrap(queue.batch(for: playerID))
        XCTAssertEqual(remainingBatch.highScore, 2_500)
        XCTAssertTrue(queue.acknowledge(remainingBatch))
        XCTAssertNil(queue.batch(for: playerID))
    }

    func testAchievementProgressIsMonotonicAndAccountScoped() throws {
        let playerA = GameCenterPlayerID("player-a")
        let playerB = GameCenterPlayerID("player-b")
        let achievementID = AchievementID("pv.achievement.century_connections")
        var queue = AccountScopedGameCenterQueue()

        queue.enqueueAchievement(id: achievementID, percentComplete: 35, for: playerA)
        queue.enqueueAchievement(id: achievementID, percentComplete: 20, for: playerA)
        queue.enqueueAchievement(id: achievementID, percentComplete: 80, for: playerB)

        let playerABatch = try XCTUnwrap(queue.batch(for: playerA))
        XCTAssertEqual(playerABatch.achievements.map(\.percentComplete), [35])

        queue.enqueueAchievement(id: achievementID, percentComplete: 60, for: playerA)
        XCTAssertTrue(queue.acknowledge(playerABatch))
        XCTAssertEqual(
            try XCTUnwrap(queue.batch(for: playerA)).achievements.map(\.percentComplete),
            [60]
        )
        XCTAssertEqual(
            try XCTUnwrap(queue.batch(for: playerB)).achievements.map(\.percentComplete),
            [80]
        )
        XCTAssertEqual(queue.pendingPlayerIDs(), [playerA, playerB])
    }

    func testAcknowledgementTouchesOnlyExactPlayerAndNeverUnbound() throws {
        let playerA = GameCenterPlayerID("player-a")
        let playerB = GameCenterPlayerID("player-b")
        var queue = AccountScopedGameCenterQueue(
            pendingByPlayerID: [
                playerA: GameCenterPendingMaximaV1(pendingHighScore: 1_000),
                playerB: GameCenterPendingMaximaV1(pendingHighScore: 2_000),
            ],
            unboundPending: GameCenterPendingMaximaV1(
                pendingHighScore: 9_000,
                pendingAchievementPercents: [
                    LaunchAchievementID.firstRead: 100,
                ]
            )
        )
        let playerABefore = queue.pending(for: playerA)
        let unboundBefore = queue.unboundPending
        let playerBBatch = try XCTUnwrap(queue.batch(for: playerB))

        XCTAssertTrue(queue.acknowledge(playerBBatch))

        XCTAssertEqual(queue.pending(for: playerA), playerABefore)
        XCTAssertEqual(queue.unboundPending, unboundBefore)
        XCTAssertNil(queue.pending(for: playerB))
        XCTAssertNil(queue.batch(for: GameCenterPlayerID("unrelated-player")))
    }

    func testUnboundWorkHasNoSubmissionPath() {
        let playerID = GameCenterPlayerID("player-a")
        let queue = AccountScopedGameCenterQueue(
            unboundPending: GameCenterPendingMaximaV1(
                pendingHighScore: 5_000,
                pendingAchievementPercents: [
                    LaunchAchievementID.firstRead: 50,
                ]
            )
        )

        XCTAssertNil(queue.batch(for: playerID))
        XCTAssertTrue(queue.pendingPlayerIDs().isEmpty)
    }

    func testPlayerBucketOverflowAndInvalidPlayerIDFallBackToUnbound() {
        var queue = AccountScopedGameCenterQueue()
        for index in 0..<PlayerScopedGameCenterQueueV1.maximumPlayerBucketCount {
            XCTAssertTrue(
                queue.enqueueHighScore(
                    1_000 + index,
                    for: GameCenterPlayerID("player-\(index)")
                )
            )
        }
        let existing = queue.pendingByPlayerID

        XCTAssertFalse(
            queue.enqueueHighScore(
                9_000,
                for: GameCenterPlayerID("overflow-player")
            )
        )
        XCTAssertFalse(
            queue.enqueueAchievement(
                id: LaunchAchievementID.firstRead,
                percentComplete: 80,
                for: GameCenterPlayerID("invalid\nplayer")
            )
        )

        XCTAssertEqual(queue.pendingByPlayerID, existing)
        XCTAssertEqual(queue.unboundPending.pendingHighScore, 9_000)
        XCTAssertEqual(
            queue.unboundPending.pendingAchievementPercents[
                LaunchAchievementID.firstRead
            ],
            80
        )
    }
}
