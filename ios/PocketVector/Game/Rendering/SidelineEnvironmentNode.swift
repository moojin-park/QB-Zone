import SpriteKit
import UIKit

@MainActor
final class SidelineEnvironmentNode: SKNode {
    private enum Palette {
        static let objectShadow = UIColor(
            red: 4 / 255,
            green: 27 / 255,
            blue: 37 / 255,
            alpha: 1
        )
        static let coral = UIColor(
            red: 238 / 255,
            green: 78 / 255,
            blue: 55 / 255,
            alpha: 1
        )
        static let gold = UIColor(
            red: 1,
            green: 188 / 255,
            blue: 62 / 255,
            alpha: 1
        )
    }

    func rebuild(
        for projection: GameProjection,
        textures: TextureLibrary
    ) {
        removeAllChildren()
        addPylons(projection: projection)
        addOfficials(projection: projection, textures: textures)
    }

    private func addPylons(projection: GameProjection) {
        for side in FieldBoundarySide.allCases {
            addPylon(
                at: FieldBoundaryLayout.boundaryPoint(
                    side: side,
                    browserY: FieldBoundaryLayout.endZoneBackBrowserY,
                    projection: projection
                ),
                side: side,
                scale: 0.82,
                positionName: "rear"
            )
            addPylon(
                at: FieldBoundaryLayout.boundaryPoint(
                    side: side,
                    browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
                    projection: projection
                ),
                side: side,
                scale: 1,
                positionName: "front"
            )
        }
    }

    private func addPylon(
        at point: CGPoint,
        side: FieldBoundarySide,
        scale: CGFloat,
        positionName: String
    ) {
        let sideName = side == .left ? "left" : "right"
        let pylon = SKNode()
        pylon.name = "sideline.pylon.\(sideName).\(positionName)"
        pylon.position = point
        pylon.zPosition = 7

        let shadow = SKSpriteNode(
            color: Palette.objectShadow,
            size: CGSize(width: 14 * scale, height: 5 * scale)
        )
        shadow.position = CGPoint(x: 3 * side.rawValue * scale, y: scale)
        pylon.addChild(shadow)

        let body = SKSpriteNode(
            color: Palette.coral,
            size: CGSize(width: 9 * scale, height: 25 * scale)
        )
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        body.position = .zero
        pylon.addChild(body)

        let cap = SKSpriteNode(
            color: Palette.gold,
            size: CGSize(width: 9 * scale, height: 4 * scale)
        )
        cap.position = CGPoint(x: 0, y: 22 * scale)
        pylon.addChild(cap)
        addChild(pylon)
    }

    private func addOfficials(projection: GameProjection, textures: TextureLibrary) {
        let browserY: CGFloat = 355
        let perspective = (browserY - GameProjection.horizonY)
            / (GameProjection.nearGroundY - GameProjection.horizonY)
        let scale = GameProjection.farActorScale
            + (GameProjection.nearActorScale - GameProjection.farActorScale) * perspective
        let officialSize = CGSize(
            width: GameProjection.actorSpriteSize.width * scale,
            height: GameProjection.actorSpriteSize.height * scale
        )
        for (index, side) in FieldBoundarySide.allCases.enumerated() {
            guard let position = FieldBoundaryLayout.staffPosition(
                side: side,
                browserY: browserY,
                preferredInset: 82,
                projection: projection,
                footprintHalfWidth: officialSize.width / 2
            ) else { continue }

            let official = makeOfficial(
                facing: side,
                size: officialSize,
                textures: textures
            )
            let sideName = side == .left ? "left" : "right"
            official.name = "sideline.official.\(sideName)"
            official.position = position
            official.zPosition = 8
            addChild(official)

            let bobUp = SKAction.moveBy(x: 0, y: 2, duration: 0.42)
            bobUp.timingMode = .easeInEaseOut
            let bobDown = bobUp.reversed()
            let bob = SKAction.repeatForever(SKAction.sequence([bobUp, bobDown]))
            official.run(
                SKAction.sequence([
                    SKAction.wait(forDuration: Double(index) * 0.18),
                    bob,
                ]),
                withKey: "sideline-bob"
            )
        }
    }

    private func makeOfficial(
        facing side: FieldBoundarySide,
        size: CGSize,
        textures: TextureLibrary
    ) -> SKNode {
        let official = SKNode()

        let shadow = SKSpriteNode(
            color: Palette.objectShadow,
            size: CGSize(width: size.width * 0.55, height: 8)
        )
        shadow.position = CGPoint(x: 0, y: 1)
        official.addChild(shadow)

        let direction = side == .left ? "left" : "right"
        let frames = (1 ... 2).compactMap { frame in
            textures.texture("characters/official-wave-\(frame)-\(direction).webp")
        }
        let sprite = SKSpriteNode(texture: frames.first)
        sprite.name = "sidelineOfficialSprite"
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = CGPoint(x: 0, y: 3)
        sprite.size = size
        official.addChild(sprite)

        if frames.count == 2 {
            let signal = SKAction.animate(
                with: frames,
                timePerFrame: 0.36,
                resize: false,
                restore: false
            )
            sprite.run(SKAction.repeatForever(signal), withKey: "sideline-signal")
        }

        return official
    }
}
