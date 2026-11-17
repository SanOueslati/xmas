import Foundation

enum Intensity: Int, CaseIterable {
    case off, light, medium, heavy

    var title: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        }
    }

    /// Flakes per million square points of screen (a 15" MacBook Air is about 1.3 million).
    var density: Double {
        switch self {
        case .off: 0
        case .light: 110
        case .medium: 240
        case .heavy: 480
        }
    }
}

enum Wind: Int, CaseIterable {
    case off, light, medium, strong

    var title: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    /// Sideways push on the snow, in points per second. Flakes fall at roughly 50 to 110.
    var speed: CGFloat {
        switch self {
        case .off: 0
        case .light: 45
        case .medium: 110
        case .strong: 230
        }
    }
}

/// What the menu bar menu controls. Saved in UserDefaults; scenes re-read it when `changed` is posted.
final class Settings {
    static let shared = Settings()
    static let changed = Notification.Name("XmasSettingsChanged")

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: ["intensity": Intensity.medium.rawValue, "piles": true, "cableCars": 1, "plow": true, "lights": true, "trees": 1])
    }

    var intensity: Intensity {
        get { Intensity(rawValue: defaults.integer(forKey: "intensity")) ?? .medium }
        set { set(newValue.rawValue, "intensity") }
    }

    var wind: Wind {
        get { Wind(rawValue: defaults.integer(forKey: "wind")) ?? .off }
        set { set(newValue.rawValue, "wind") }
    }

    /// Snow settles on the top edge of windows.
    var piles: Bool {
        get { defaults.bool(forKey: "piles") }
        set { set(newValue, "piles") }
    }

    /// How many ropes with a cable car hang from the notch.
    var cableCars: Int {
        get { defaults.integer(forKey: "cableCars") }
        set { set(max(0, min(newValue, 5)), "cableCars") }
    }

    /// A little truck that drives along window tops clearing the snow.
    var plow: Bool {
        get { defaults.bool(forKey: "plow") }
        set { set(newValue, "plow") }
    }

    /// Fairy lights along the top of every window.
    var lights: Bool {
        get { defaults.bool(forKey: "lights") }
        set { set(newValue, "lights") }
    }

    /// How many of each decoration are out.
    func count(of kind: PropKind) -> Int { defaults.integer(forKey: kind.rawValue) }

    func setCount(_ count: Int, of kind: PropKind) { set(max(0, min(count, 12)), kind.rawValue) }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
