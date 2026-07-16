import SpriteKit
import UIKit

@MainActor
final class SidelineEnvironmentNode: SKNode {
    private enum Palette {
        static let outOfBounds = UIColor(
            red: 10 / 255,
            green: 58 / 255,
            blue: 66 / 255,
            alpha: 1
        )
        static let outOfBoundsShadow = UIColor(
            red: 4 / 255,
            green: 27 / 255,
            blue: 37 / 255,
            alpha: 1
        )
        static let endZone = UIColor(
            red: 5 / 255,
            green: 47 / 255,
            blue: 75 / 255,
            alpha: 1
        )
        static let stripe = UIColor(red: 67 / 255, green: 181 / 255, blue: 177 / 255, alpha: 1)
        static let chalk = UIColor(red: 236 / 255, green: 241 / 255, blue: 220 / 255, alpha: 1)
        static let chalkShadow = UIColor(red: 2 / 255, green: 24 / 255, blue: 31 / 255, alpha: 0.72)
        static let coral = UIColor(red: 238 / 255, green: 78 / 255, blue: 55 / 255, alpha: 1)
        static let gold = UIColor(red: 1, green: 188 / 255, blue: 62 / 255, alpha: 1)
    }

    func rebuild(
        for projection: GameProjection,
        offenseIdentity: TeamVisualIdentity,
        textures: TextureLibrary
    ) {
        removeAllChildren()
        addEndZoneSurface(
            projection: projection,
            identity: offenseIdentity,
            textures: textures
        )
        addFieldBranding(
            projection: projection,
            identity: offenseIdentity,
            textures: textures
        )
        addOutOfBoundsSurfaces(projection: projection)
        addSurfaceDetails(projection: projection)
        addYardLineExtensions(projection: projection)
        addBoundaryChalk(projection: projection)
        addPylons(projection: projection)
        addOfficials(projection: projection, textures: textures)
    }

    private func addEndZoneSurface(
        projection: GameProjection,
        identity: TeamVisualIdentity,
        textures: TextureLibrary
    ) {
        let leftBack = FieldBoundaryLayout.boundaryPoint(
            side: .left,
            browserY: FieldBoundaryLayout.endZoneBackBrowserY,
            projection: projection
        )
        let rightBack = FieldBoundaryLayout.boundaryPoint(
            side: .right,
            browserY: FieldBoundaryLayout.endZoneBackBrowserY,
            projection: projection
        )
        let leftFront = FieldBoundaryLayout.boundaryPoint(
            side: .left,
            browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
            projection: projection
        )
        let rightFront = FieldBoundaryLayout.boundaryPoint(
            side: .right,
            browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
            projection: projection
        )

        // Cover only the two small rear-corner overhangs from the old 964px
        // rectangular band. Keeping these masks tight preserves the locked
        // stadium and out-of-bounds treatment around the corrected trapezoid.
        let paintedHalfWidth: CGFloat = 482
        let intersectionBrowserY = GameProjection.horizonY
            + (paintedHalfWidth - FieldBoundaryLayout.farHalfWidthPixels)
            / (FieldBoundaryLayout.nearHalfWidthPixels - FieldBoundaryLayout.farHalfWidthPixels)
            * (GameProjection.nearGroundY - GameProjection.horizonY)
        for side in FieldBoundarySide.allCases {
            let back = side == .left ? leftBack : rightBack
            let paintedX = projection.centerX + side.rawValue * paintedHalfWidth
            let intersection = CGPoint(
                x: paintedX,
                y: GameProjection.logicalHeight - intersectionBrowserY
            )

            let path = CGMutablePath()
            path.move(to: CGPoint(x: paintedX, y: back.y))
            path.addLine(to: back)
            path.addLine(to: intersection)
            path.closeSubpath()

            let outsideMask = SKShapeNode(path: path)
            outsideMask.fillColor = Palette.outOfBounds
            outsideMask.strokeColor = .clear
            outsideMask.isAntialiased = false
            outsideMask.zPosition = 0
            addChild(outsideMask)
        }

        let endZonePath = CGMutablePath()
        endZonePath.move(to: leftBack)
        endZonePath.addLine(to: rightBack)
        endZonePath.addLine(to: rightFront)
        endZonePath.addLine(to: leftFront)
        endZonePath.closeSubpath()

        let endZoneBase = SKShapeNode(path: endZonePath)
        endZoneBase.fillColor = identity.palette
            .color(for: identity.endZone.background)
            .uiColor
        endZoneBase.strokeColor = identity.palette
            .color(for: identity.endZone.boundary)
            .uiColor
        endZoneBase.lineWidth = 3
        endZoneBase.isAntialiased = false
        endZoneBase.zPosition = 1
        addChild(endZoneBase)

        let artwork = SKCropNode()
        artwork.name = "endZoneArtwork.\(identity.teamID.rawValue)"
        let mask = SKShapeNode(path: endZonePath)
        mask.fillColor = .white
        mask.strokeColor = .clear
        mask.isAntialiased = false
        artwork.maskNode = mask
        artwork.zPosition = 2

        let height = leftBack.y - leftFront.y
        let centerY = (leftBack.y + leftFront.y) / 2
        let emblemSide = max(30, height * 0.82)
        let emblemTexture = textures.emblemTexture(
            for: identity,
            size: CGSize(width: emblemSide, height: emblemSide)
        )
        let motifCount = max(1, identity.endZone.motifRepeatCount)
        let availableWidth = max(1, rightFront.x - leftFront.x)
        for index in 0 ..< motifCount {
            let progress = (CGFloat(index) + 0.5) / CGFloat(motifCount)
            let motif = SKSpriteNode(texture: emblemTexture)
            motif.name = "endZoneMotif.\(identity.emblem.motif.rawValue).\(index)"
            motif.size = CGSize(width: emblemSide, height: emblemSide)
            motif.position = CGPoint(
                x: leftFront.x + availableWidth * progress,
                y: motifY(
                    layout: identity.endZone.motifLayout,
                    index: index,
                    count: motifCount,
                    centerY: centerY,
                    height: height
                )
            )
            motif.zRotation = motifRotation(
                layout: identity.endZone.motifLayout,
                index: index
            )
            motif.alpha = identity.endZone.motifOpacity
            motif.zPosition = 0
            artwork.addChild(motif)
        }

        let market = makeWordmarkLabel(
            identity.wordmark.marketLine,
            fontSize: max(8, height * 0.18),
            color: identity.palette.color(for: identity.wordmark.marketColor).uiColor
        )
        market.position = CGPoint(x: projection.centerX, y: centerY + height * 0.18)
        market.zPosition = 2
        fit(label: market, maximumWidth: availableWidth * 0.70)
        artwork.addChild(market)

        let nickname = makeWordmarkLabel(
            identity.wordmark.nicknameLine,
            fontSize: max(18, height * 0.42),
            color: identity.palette.color(for: identity.endZone.wordmark).uiColor
        )
        nickname.position = CGPoint(x: projection.centerX, y: centerY - height * 0.12)
        nickname.zPosition = 3
        fit(label: nickname, maximumWidth: availableWidth * 0.76)
        artwork.addChild(nickname)

        addChild(artwork)
    }

    private func addFieldBranding(
        projection: GameProjection,
        identity: TeamVisualIdentity,
        textures: TextureLibrary
    ) {
        // The immutable stadium plate contains legacy Nova lettering. This code-native plate fully
        // covers that authored rectangle and supplies the selected offense's original mark instead.
        let width = min(680, projection.viewportWidth * 0.70)
        let height: CGFloat = 126
        let frame = CGRect(
            x: projection.centerX - width / 2,
            y: GameProjection.logicalHeight - 448,
            width: width,
            height: height
        )
        let panel = SKShapeNode(
            path: CGPath(
                roundedRect: frame,
                cornerWidth: height * 0.42,
                cornerHeight: height * 0.42,
                transform: nil
            )
        )
        panel.name = "fieldBranding.\(identity.teamID.rawValue)"
        panel.fillColor = identity.palette
            .color(for: identity.endZone.background)
            .uiColor
        panel.strokeColor = identity.palette.accent.uiColor
        panel.lineWidth = 5
        panel.isAntialiased = true
        panel.zPosition = 4
        addChild(panel)

        let emblemSide = height * 0.78
        let emblem = SKSpriteNode(texture: textures.emblemTexture(
            for: identity,
            size: CGSize(width: emblemSide, height: emblemSide)
        ))
        emblem.size = CGSize(width: emblemSide, height: emblemSide)
        emblem.position = CGPoint(x: frame.minX + height * 0.62, y: frame.midY)
        emblem.zPosition = 5
        addChild(emblem)

        let market = makeWordmarkLabel(
            identity.wordmark.marketLine,
            fontSize: 17,
            color: identity.palette.color(for: identity.wordmark.marketColor).uiColor
        )
        market.horizontalAlignmentMode = .left
        market.position = CGPoint(x: frame.minX + height * 1.15, y: frame.midY + 19)
        market.zPosition = 5
        fit(label: market, maximumWidth: frame.width - height * 1.38)
        addChild(market)

        let nickname = makeWordmarkLabel(
            identity.wordmark.nicknameLine,
            fontSize: 39,
            color: identity.palette.color(for: identity.wordmark.nicknameColor).uiColor
        )
        nickname.horizontalAlignmentMode = .left
        nickname.position = CGPoint(x: frame.minX + height * 1.15, y: frame.midY - 20)
        nickname.zPosition = 5
        fit(label: nickname, maximumWidth: frame.width - height * 1.38)
        addChild(nickname)
    }

    private func motifY(
        layout: EndZoneMotifLayout,
        index: Int,
        count: Int,
        centerY: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        switch layout {
        case .offsetDisks, .waveBands:
            return centerY + (index.isMultiple(of: 2) ? height * 0.10 : -height * 0.10)
        case .frequencySteps:
            let progress = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
            return centerY - height * 0.18 + progress * height * 0.36
        case .splitRays, .radialCore:
            return centerY + (index == count / 2 ? height * 0.08 : 0)
        case .mirroredCorners, .horizonBand, .rivetRail:
            return centerY
        }
    }

    private func motifRotation(layout: EndZoneMotifLayout, index: Int) -> CGFloat {
        switch layout {
        case .mirroredCorners:
            return index.isMultiple(of: 2) ? -0.16 : 0.16
        case .splitRays:
            return index.isMultiple(of: 2) ? -0.28 : 0.28
        case .waveBands:
            return index.isMultiple(of: 2) ? -0.08 : 0.08
        case .horizonBand, .rivetRail, .offsetDisks, .radialCore, .frequencySteps:
            return 0
        }
    }

    private func makeWordmarkLabel(
        _ text: String,
        fontSize: CGFloat,
        color: UIColor
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    private func fit(label: SKLabelNode, maximumWidth: CGFloat) {
        guard label.frame.width > maximumWidth, label.frame.width > 0 else { return }
        label.xScale = maximumWidth / label.frame.width
    }

    private func addOutOfBoundsSurfaces(projection: GameProjection) {
        let frontBrowserY = FieldBoundaryLayout.endZoneFrontBrowserY
        let nearBrowserY = GameProjection.nearGroundY

        for side in FieldBoundarySide.allCases {
            let front = FieldBoundaryLayout.boundaryPoint(
                side: side,
                browserY: frontBrowserY,
                projection: projection
            )
            let near = FieldBoundaryLayout.boundaryPoint(
                side: side,
                browserY: nearBrowserY,
                projection: projection
            )
            let edgeX: CGFloat = side == .left ? 0 : projection.viewportWidth

            let path = CGMutablePath()
            path.move(to: CGPoint(x: edgeX, y: front.y))
            path.addLine(to: front)
            path.addLine(to: near)
            path.addLine(to: CGPoint(x: edgeX, y: near.y))
            path.closeSubpath()

            let shadow = SKShapeNode(path: path)
            shadow.fillColor = Palette.outOfBoundsShadow
            shadow.strokeColor = .clear
            shadow.isAntialiased = false
            shadow.zPosition = 1
            addChild(shadow)

            let insetPath = CGMutablePath()
            insetPath.move(to: CGPoint(x: edgeX, y: front.y - 3))
            insetPath.addLine(to: CGPoint(x: front.x, y: front.y - 3))
            insetPath.addLine(to: near)
            insetPath.addLine(to: CGPoint(x: edgeX, y: near.y))
            insetPath.closeSubpath()

            let surface = SKShapeNode(path: insetPath)
            surface.fillColor = Palette.outOfBounds
            surface.strokeColor = .clear
            surface.isAntialiased = false
            surface.zPosition = 2
            addChild(surface)
        }
    }

    private func addSurfaceDetails(projection: GameProjection) {
        for side in FieldBoundarySide.allCases {
            for (index, browserY) in [328, 374, 420, 466].enumerated() {
                let y = CGFloat(browserY)
                let boundary = FieldBoundaryLayout.boundaryPoint(
                    side: side,
                    browserY: y,
                    projection: projection
                )
                let availableWidth = side == .left
                    ? boundary.x
                    : projection.viewportWidth - boundary.x
                guard availableWidth > 34 else { continue }

                let width = min(42, availableWidth * 0.28)
                let centerX = side == .left
                    ? availableWidth * 0.34
                    : projection.viewportWidth - availableWidth * 0.34
                let stripe = SKSpriteNode(
                    color: index.isMultiple(of: 2) ? Palette.stripe : Palette.gold,
                    size: CGSize(width: width, height: index.isMultiple(of: 2) ? 3 : 2)
                )
                stripe.position = CGPoint(x: centerX, y: GameProjection.logicalHeight - y)
                stripe.alpha = index.isMultiple(of: 2) ? 0.42 : 0.5
                stripe.zRotation = side.rawValue * 0.08
                stripe.zPosition = 3
                addChild(stripe)
            }
        }
    }

    private func addBoundaryChalk(projection: GameProjection) {
        let leftBack = FieldBoundaryLayout.boundaryPoint(
            side: .left,
            browserY: FieldBoundaryLayout.endZoneBackBrowserY,
            projection: projection
        )
        let leftNear = FieldBoundaryLayout.boundaryPoint(
            side: .left,
            browserY: GameProjection.nearGroundY,
            projection: projection
        )
        let rightBack = FieldBoundaryLayout.boundaryPoint(
            side: .right,
            browserY: FieldBoundaryLayout.endZoneBackBrowserY,
            projection: projection
        )
        let rightNear = FieldBoundaryLayout.boundaryPoint(
            side: .right,
            browserY: GameProjection.nearGroundY,
            projection: projection
        )

        addChalkLine(from: leftBack, to: leftNear)
        addChalkLine(from: rightBack, to: rightNear)

        let leftFront = FieldBoundaryLayout.boundaryPoint(
            side: .left,
            browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
            projection: projection
        )
        let rightFront = FieldBoundaryLayout.boundaryPoint(
            side: .right,
            browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
            projection: projection
        )
        addChalkLine(from: leftFront, to: rightFront, lineWidth: 4)
    }

    /// The raster plate's yard lines ended at the legacy, narrow boundary.
    /// Extend only those outer segments to the widened sideline so the logo and
    /// authored center-field pixels remain untouched and no stripe enters OOB.
    private func addYardLineExtensions(projection: GameProjection) {
        let yardLines: [(browserY: CGFloat, width: CGFloat)] = [
            (324, 2),
            (359, 2),
            (401, 3),
            (458, 3),
            (522, 4),
            (599, 5),
            (694, 7),
        ]

        for yardLine in yardLines {
            for side in FieldBoundarySide.allCases {
                let widened = FieldBoundaryLayout.boundaryPoint(
                    side: side,
                    browserY: yardLine.browserY,
                    projection: projection
                )
                let legacy = FieldBoundaryLayout.legacyBoundaryPoint(
                    side: side,
                    browserY: yardLine.browserY,
                    projection: projection
                )

                let path = CGMutablePath()
                path.move(to: widened)
                path.addLine(to: legacy)

                let extensionNode = SKShapeNode(path: path)
                extensionNode.strokeColor = Palette.chalk.withAlphaComponent(0.82)
                extensionNode.lineWidth = yardLine.width
                extensionNode.lineCap = .butt
                extensionNode.isAntialiased = false
                extensionNode.zPosition = 3.5
                addChild(extensionNode)
            }
        }
    }

    private func addChalkLine(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat = 5) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let shadow = SKShapeNode(path: path)
        shadow.strokeColor = Palette.chalkShadow
        shadow.lineWidth = lineWidth + 4
        shadow.lineCap = .butt
        shadow.isAntialiased = false
        shadow.zPosition = 4
        addChild(shadow)

        let chalk = SKShapeNode(path: path)
        chalk.strokeColor = Palette.chalk
        chalk.lineWidth = lineWidth
        chalk.lineCap = .butt
        chalk.isAntialiased = false
        chalk.zPosition = 5
        addChild(chalk)
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
                scale: 0.82
            )
            addPylon(
                at: FieldBoundaryLayout.boundaryPoint(
                    side: side,
                    browserY: FieldBoundaryLayout.endZoneFrontBrowserY,
                    projection: projection
                ),
                side: side,
                scale: 1
            )
        }
    }

    private func addPylon(at point: CGPoint, side: FieldBoundarySide, scale: CGFloat) {
        let pylon = SKNode()
        pylon.position = point
        pylon.zPosition = 7

        let shadow = SKSpriteNode(
            color: Palette.outOfBoundsShadow,
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
            color: Palette.outOfBoundsShadow,
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
