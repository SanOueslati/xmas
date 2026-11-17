import SpriteKit

/// One see-through window covering a whole screen, floating above every app.
/// Clicks pass straight through it unless the scene says the cursor is on something you can grab.
final class Overlay {
    let scene: SnowScene
    private let panel: NSPanel

    init(screen: NSScreen, isMain: Bool) {
        // Non-activating: grabbing a tree doesn't steal focus from the app you're working in.
        panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        // Just above the menu bar and Dock, but below menus and notifications.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = View(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        scene = SnowScene(screen: screen, isMain: isMain)
        view.presentScene(scene)
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class View: SKView {
        /// Take the very first click even though Xmas is never the active app.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let scene = scene as? SnowScene else { return }
            scene.mouseDown(at: event.location(in: scene))
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let scene = scene as? SnowScene else { return }
            scene.rightMouseDown(at: event.location(in: scene))
        }
    }
}
