import Foundation

enum MatchupGenerationError: Error, Equatable {
    case invalidSelection(InventoryRuleError)
    case unknownOffenseJersey(JerseyID)
    case noAvailableDefense
}

struct MatchupGenerator: Sendable {
    let catalog: LaunchCatalog

    init(catalog: LaunchCatalog = .approved) {
        self.catalog = catalog
    }

    func makeRunConfiguration(
        selection: PlayerSelection,
        inventory: PlayerInventory,
        runID: RunID = RunID(),
        seed: UInt32,
        startedAt: Date,
        economyVersion: Int = EconomyConfiguration.currentVersion
    ) throws -> RunConfiguration {
        do {
            try InventoryRules.validate(
                selection: selection,
                inventory: inventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw MatchupGenerationError.invalidSelection(error)
        }

        guard let offenseJerseyID = selection.selectedJerseyID,
              let offenseJersey = catalog.jersey(id: offenseJerseyID) else {
            throw MatchupGenerationError.unknownOffenseJersey(
                selection.selectedJerseyID
                    ?? JerseyID("missing-selection.\(selection.selectedTeamID.rawValue)")
            )
        }

        let candidates = catalog.teams.filter { $0.id != selection.selectedTeamID }
        guard !candidates.isEmpty else {
            throw MatchupGenerationError.noAvailableDefense
        }

        var random = MatchupSeededGenerator(seed: seed)
        let defenseTeam = candidates[random.nextIndex(upperBound: candidates.count)]
        let defenseJersey = UniformClashResolver.resolve(
            offense: offenseJersey,
            defenseTeam: defenseTeam
        )

        return RunConfiguration(
            runID: runID,
            randomSeed: seed,
            offenseTeamID: selection.selectedTeamID,
            offenseJerseyID: offenseJersey.id,
            defenseTeamID: defenseTeam.id,
            defenseJerseyID: defenseJersey.id,
            footballID: selection.selectedFootballID,
            economyVersion: economyVersion,
            startedAt: startedAt
        )
    }
}

private struct MatchupSeededGenerator {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed == 0 ? 0xA341_316C : seed
    }

    mutating func nextIndex(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Int(state % UInt32(upperBound))
    }
}
