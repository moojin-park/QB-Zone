import Foundation

struct RGBColor: Codable, Equatable, Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        precondition(normalized.count == 6, "RGBColor requires a six-digit hexadecimal value")
        guard let value = UInt32(normalized, radix: 16) else {
            preconditionFailure("Invalid RGB hexadecimal value: \(hex)")
        }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var relativeLuminance: Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrastRatio(with other: RGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func normalizedRGBDistance(to other: RGBColor) -> Double {
        let redDelta = Double(Int(red) - Int(other.red))
        let greenDelta = Double(Int(green) - Int(other.green))
        let blueDelta = Double(Int(blue) - Int(other.blue))
        return sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
            / sqrt(3 * 255 * 255)
    }

    func normalizedHueDistance(to other: RGBColor) -> Double {
        let distance = abs(hueDegrees - other.hueDegrees)
        return min(distance, 360 - distance) / 180
    }

    private var hueDegrees: Double {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard delta > 0 else { return 0 }

        let hue: Double
        if maximum == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }
        return hue < 0 ? hue + 360 : hue
    }
}

enum JerseyKind: String, Codable, Equatable, Sendable {
    case primary
    case alternate
}

struct JerseyAssetKeys: Codable, Equatable, Hashable, Sendable {
    let paletteToken: String
}

struct JerseyDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: JerseyID
    let teamID: TeamID
    let kind: JerseyKind
    let displayName: String
    let primaryColor: RGBColor
    let secondaryColor: RGBColor
    let accentColor: RGBColor
    let assets: JerseyAssetKeys

    var dominantColor: RGBColor { primaryColor }
}

struct TeamAssetKeys: Codable, Equatable, Hashable, Sendable {
    let logo: String
    let endZone: String
    let fieldBranding: String
}

struct TeamDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: TeamID
    let displayName: String
    let initiallyOwned: Bool
    let primaryColor: RGBColor
    let secondaryColor: RGBColor
    let accentColor: RGBColor
    let primaryJersey: JerseyDescriptor
    let alternateJersey: JerseyDescriptor
    let assets: TeamAssetKeys

    var jerseys: [JerseyDescriptor] {
        [primaryJersey, alternateJersey]
    }
}

struct FootballDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: FootballID
    let displayName: String
    let initiallyOwned: Bool
    let assetKey: String
}

enum CatalogItemKind: Codable, Equatable, Hashable, Sendable {
    case team(TeamID)
    case alternateJersey(JerseyID)
    case football(FootballID)
}

struct CatalogItemDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: CatalogItemID
    let displayName: String
    let kind: CatalogItemKind
    let price: Int64
}
