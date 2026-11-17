import AppKit

/// A menu bar app: no Dock icon, no windows of its own, just the snowflake menu and a see-through overlay per screen.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlays: [Overlay] = []
    private var screenFrames: [CGRect] = []
    private var activity: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Xmas is never the frontmost app, and macOS slows background apps down. This keeps the snow smooth.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Animating snow")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
        SnowScene.parkingFrame = { [weak item] in item?.button?.window?.frame }
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusIcon), name: Settings.changed, object: nil)

        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildOverlays), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #if DEBUG
            // `-snapshot <file.png> [-snapshotAfter <seconds>] [-demo YES]` saves a picture of the overlay for checking the artwork.
            let args = UserDefaults.standard
            if args.string(forKey: "snapshot") != nil {
                if args.bool(forKey: "demo") { perform(#selector(runDemo), with: nil, afterDelay: 1.5) }
                perform(#selector(saveSnapshot), with: nil, afterDelay: max(2, args.double(forKey: "snapshotAfter")))
            }
        #endif
    }

    /// One overlay per screen. Rebuilt only when a screen is added, removed or resized.
    @objc private func rebuildOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != screenFrames else { return }
        screenFrames = frames
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.enumerated().map { Overlay(screen: $1, isMain: $0 == 0) }
    }

    /// With the plow on, the menu bar item is wider: snowflake on the left, an empty parking space for the plow on the right.
    @objc private func updateStatusIcon() {
        guard let item = statusItem, let flake = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Xmas") else { return }
        guard Settings.shared.plow else {
            item.length = NSStatusItem.squareLength
            item.button?.image = flake
            return
        }
        let wide = NSImage(size: NSSize(width: 62, height: 18), flipped: false) { _ in
            flake.draw(in: NSRect(x: 2, y: 1, width: 16, height: 16))
            return true
        }
        wide.isTemplate = true
        item.length = 66
        item.button?.image = wide
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = Settings.shared
        menu.removeAllItems()

        let snowfall = NSMenuItem(title: "Snowfall", action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for level in Intensity.allCases {
            let item = NSMenuItem(title: level.title, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = settings.intensity == level ? .on : .off
            levels.addItem(item)
        }
        snowfall.submenu = levels
        menu.addItem(snowfall)

        let wind = NSMenuItem(title: "Wind", action: nil, keyEquivalent: "")
        let strengths = NSMenu()
        for strength in Wind.allCases {
            let item = NSMenuItem(title: strength.title, action: #selector(setWind(_:)), keyEquivalent: "")
            item.target = self
            item.tag = strength.rawValue
            item.state = settings.wind == strength ? .on : .off
            strengths.addItem(item)
        }
        wind.submenu = strengths
        menu.addItem(wind)
        add("Snow Settles on Windows", #selector(togglePiles), to: menu).state = settings.piles ? .on : .off
        add("Shake Off the Snow", #selector(shakeOff), to: menu)
        menu.addItem(.separator())
        for kind in PropKind.allCases {
            add("Add \(kind.title)", #selector(addProp(_:)), to: menu).representedObject = kind.rawValue
        }
        add("Add a Cable Car", #selector(addCableCar), to: menu)
        if settings.cableCars > 0 || PropKind.allCases.contains(where: { settings.count(of: $0) > 0 }) {
            add("Remove All Decorations", #selector(removeProps), to: menu)
        }
        add("Snow Plow in Menu Bar", #selector(togglePlow), to: menu).state = settings.plow ? .on : .off
        add("Lights on Windows", #selector(toggleLights), to: menu).state = settings.lights ? .on : .off
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Xmas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func setWind(_ sender: NSMenuItem) {
        Settings.shared.wind = Wind(rawValue: sender.tag) ?? .off
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        Settings.shared.intensity = Intensity(rawValue: sender.tag) ?? .medium
    }

    @objc private func togglePiles() { Settings.shared.piles.toggle() }
    @objc private func shakeOff() { overlays.forEach { $0.scene.shakeOff() } }
    @objc private func addProp(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let kind = PropKind(rawValue: key) else { return }
        Settings.shared.setCount(Settings.shared.count(of: kind) + 1, of: kind)
    }

    @objc private func removeProps() {
        PropKind.allCases.forEach { Settings.shared.setCount(0, of: $0) }
        Settings.shared.cableCars = 0
    }
    @objc private func toggleLights() { Settings.shared.lights.toggle() }
    @objc private func togglePlow() { Settings.shared.plow.toggle() }
    @objc private func addCableCar() { Settings.shared.cableCars += 1 }

    #if DEBUG
        @objc private func runDemo() { overlays.first?.scene.demo() }

        @objc private func saveSnapshot() {
            guard let path = UserDefaults.standard.string(forKey: "snapshot") else { return }
            overlays.first?.scene.saveSnapshot(to: path)
        }
    #endif
}
