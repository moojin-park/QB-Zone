import Foundation

struct UniformClashScore: Equatable, Comparable, Sendable {
    let luminanceContrast: Double
    let colorDistance: Double
    let hueDistance: Double

    var total: Double {
        luminanceContrast * 4 + colorDistance * 3 + hueDistance * 2
    }

    static func < (lhs: UniformClashScore, rhs: UniformClashScore) -> Bool {
        lhs.total < rhs.total
    }
}

enum UniformClashResolver {
    static func score(
        offense: JerseyDescriptor,
        defense: JerseyDescriptor
    ) -> UniformClashScore {
        UniformClashScore(
            luminanceContrast: offense.dominantColor.contrastRatio(
                with: defense.dominantColor
            ),
            colorDistance: offense.dominantColor.normalizedRGBDistance(
                to: defense.dominantColor
            ),
            hueDistance: offense.dominantColor.normalizedHueDistance(
                to: defense.dominantColor
            )
        )
    }

    static func resolve(
        offense: JerseyDescriptor,
        defenseTeam: TeamDescriptor
    ) -> JerseyDescriptor {
        // Preserve catalog order on an exact score tie, which favors the primary jersey.
        defenseTeam.jerseys.dropFirst().reduce(defenseTeam.primaryJersey) { best, candidate in
            score(offense: offense, defense: candidate) > score(offense: offense, defense: best)
                ? candidate
                : best
        }
    }
}
