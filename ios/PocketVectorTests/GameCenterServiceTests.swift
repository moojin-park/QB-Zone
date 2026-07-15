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
}
