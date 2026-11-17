import SpriteKit

/// Everything drawn on one screen: falling snow, the snow lying on windows, and (on the main screen) trees and the cable car.
/// Scene coordinates are points with the origin at the screen's bottom-left corner.
final class SnowScene: SKScene {
    private let screen: NSScreen
    /// Trees and the cable car live only on the main screen, the one with the notch.
    private let isMain: Bool
    /// The screen's top-left corner in global Quartz coordinates (y grows downward), which window frames are given in.
    private let quartzOrigin: CGPoint

    private let snowfall: Snowfall
    private var piles: [CGWindowID: SnowPile] = [:]
    private var platforms: [Platform] = []
    private var trees: [TreeNode] = []
    private var ropeways: [Ropeway] = []
    private var plow: Plow?
    private var treesMade = 0

    private var lastTime: TimeInterval = 0
    private var lastLook: TimeInterval = 0
    /// While windows are moving, their positions are read every frame; otherwise ten times a second is plenty.
    private var lookOftenUntil: TimeInterval = 0
    private var lastPrune: TimeInterval = 0
    private var firstLook = true

    private var mouse: CGPoint
    private var mouseVelocity = CGVector.zero

    private enum Held {
        case tree(TreeNode)
        case hook(Ropeway)
        case plow
    }

    /// Where the snowflake's menu bar item is on screen (global, y up). Set by the app; the plow parks in its right half.
    static var parkingFrame: () -> CGRect? = { nil }
    private var held: Held?
    private var heldSince: TimeInterval = 0
    private var heldFrom = CGPoint.zero

    init(screen: NSScreen, isMain: Bool) {
        self.screen = screen
        self.isMain = isMain
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        quartzOrigin = CGPoint(x: screen.frame.minX, y: mainHeight - screen.frame.maxY)
        snowfall = Snowfall(size: screen.frame.size)
        let location = NSEvent.mouseLocation
        mouse = CGPoint(x: location.x - screen.frame.minX, y: location.y - screen.frame.minY)
        super.init(size: screen.frame.size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(snowfall.layer)
        applySettings()
        NotificationCenter.default.addObserver(self, selector: #selector(applySettings), name: Settings.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    /// Height of the menu bar or notch, whichever is taller.
    private var topInset: CGFloat { max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY) }

    /// The top of the Dock, or the bottom of the screen when the Dock is hidden or on a side.
    private var floorY: CGFloat { screen.visibleFrame.minY - screen.frame.minY }

    /// Where the rope's pulley hangs: from the underside of the notch, a little left of centre.
    private var notchAnchor: CGPoint {
        var x = size.width / 2
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            x = (left.maxX + right.minX) / 2 - screen.frame.minX - (right.minX - left.maxX) * 0.18
        }
        return CGPoint(x: x, y: size.height - topInset - (Art.bracketSize.height - Art.bracketWheel.y))
    }

    @objc private func applySettings() {
        let settings = Settings.shared
        let area = Double(size.width * size.height) / 1_000_000
        snowfall.setFlakeCount(Int(settings.intensity.density * area))
        snowfall.windSpeed = settings.wind.speed
        if !settings.piles { shakeOff() }
        guard isMain else { return }

        for kind in PropKind.allCases {
            let wanted = settings.count(of: kind)
            while trees.filter({ $0.kind == kind }).count > wanted, let index = trees.lastIndex(where: { $0.kind == kind }) {
                trees.remove(at: index).removeFromParent()
            }
            while trees.filter({ $0.kind == kind }).count < wanted {
                // New decorations drop in from above and land on whatever is underneath.
                let tree = TreeNode(kind: kind)
                // In front of the snow, and newer ones in front of older ones.
                treesMade += 1
                tree.restingZ = 14 + CGFloat(treesMade) * 0.01
                tree.zPosition = tree.restingZ
                tree.position = CGPoint(x: size.width * .random(in: 0.25...0.75), y: size.height + 20)
                addChild(tree)
                trees.append(tree)
            }
        }
        if settings.plow, plow == nil {
            let plow = Plow()
            addChild(plow)
            self.plow = plow
        } else if !settings.plow, let plow {
            if case .plow = held { held = nil }
            plow.removeFromParent()
            self.plow = nil
        }
        while ropeways.count > settings.cableCars {
            if case .hook = held { held = nil }
            ropeways.removeLast().removeFromParent()
        }
        while ropeways.count < settings.cableCars {
            // Each rope gets its own pulley: the first in the usual spot, the rest spread out either side of it.
            let slot = [0, -1, 1, -2, 2].first { slot in !ropeways.contains { $0.slot == slot } } ?? 0
            let ropeway = Ropeway(anchor: CGPoint(x: notchAnchor.x + CGFloat(slot) * 34, y: notchAnchor.y))
            ropeway.slot = slot
            addChild(ropeway)
            ropeways.append(ropeway)
        }
    }

    /// Knocks all the settled snow loose.
    func shakeOff() {
        for p in platforms {
            for spot in p.pile.shed(1, maxPoints: 40) {
                snowfall.addClump(
                    at: CGPoint(x: p.left + spot.x, y: p.top + spot.y),
                    velocity: CGVector(dx: .random(in: -30...30), dy: .random(in: -20...60)))
            }
        }
        // Piles on windows that aren't showing right now.
        for pile in piles.values { _ = pile.shed(1, maxPoints: 0) }
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(max(currentTime - lastTime, 1.0 / 240), 1.0 / 20))
        lastTime = currentTime
        let pressed = NSEvent.pressedMouseButtons & 1 == 1

        // A held mouse button usually means a window is being dragged, so follow closely.
        if pressed || currentTime < lookOftenUntil || currentTime - lastLook >= 0.1 { look(at: currentTime) }

        let location = NSEvent.mouseLocation
        let previous = mouse
        mouse = CGPoint(x: location.x - screen.frame.minX, y: location.y - screen.frame.minY)
        mouseVelocity = CGVector(dx: (mouse.x - previous.x) / dt, dy: (mouse.y - previous.y) / dt)

        if held != nil, !pressed { release() }
        let settle = Settings.shared.piles
        // Only a moving cursor ploughs; a parked one would keep re-kicking the snow that falls back on it.
        if settle, held == nil, mouse != previous { brush(from: previous, to: mouse) }

        snowfall.update(dt: dt, time: currentTime, platforms: platforms, settle: settle)

        for tree in trees {
            guard let (platform, x) = tree.update(dt: dt, platforms: platforms, floor: floorY, sceneWidth: size.width, mouse: mouse),
                platform.pile.surface(at: x) > 2
            else { continue }
            // Landing in snow flattens it and throws some up.
            platform.pile.press(at: x, halfWidth: 20, to: 0.45)
            for _ in 0..<10 {
                snowfall.addClump(
                    at: CGPoint(x: platform.left + x + .random(in: -20...20), y: platform.top + 4),
                    velocity: CGVector(dx: .random(in: -140...140), dy: .random(in: 60...190)))
            }
        }
        for ropeway in ropeways { ropeway.update(dt: dt, time: currentTime, platforms: platforms, mouse: mouse) }
        if let plow {
            if let spot = Self.parkingFrame() {
                plow.home = CGPoint(x: spot.minX + 44 - screen.frame.minX, y: spot.minY + (spot.height - Art.plowSize.height) / 2 - screen.frame.minY)
            }
            plow.update(dt: dt, time: currentTime, platforms: platforms, snowfall: snowfall, mouse: mouse)
        }
        let lights = Settings.shared.lights
        for pile in piles.values { pile.updateLights(enabled: lights) }

        let scale = screen.backingScaleFactor
        for pile in piles.values { pile.update(now: currentTime, scale: scale) }

        // The overlay lets clicks through to the apps below, except while the cursor is on something you can grab.
        let wantsMouse = held != nil || (!pressed && target(at: mouse) != nil)
        if let window = view?.window, window.ignoresMouseEvents == wantsMouse { window.ignoresMouseEvents = !wantsMouse }
    }

    // MARK: Windows

    /// Reads where every window is and works out which parts of each top edge can be seen.
    private func look(at now: TimeInterval) {
        let elapsed = CGFloat(max(now - lastLook, 1.0 / 120))
        lastLook = now
        let windows = WindowTracker.windows(at: now)
        let ceiling = size.height - topInset - 2
        var found: [Platform] = []
        var seen = Set<CGWindowID>()

        for (i, w) in windows.enumerated() {
            let left = w.frame.minX - quartzOrigin.x
            let top = size.height - (w.frame.minY - quartzOrigin.y)
            // Must be on this screen, and not tucked under the menu bar where snow has nowhere to sit.
            guard left < size.width, left + w.frame.width > 0, top > 20, top < ceiling else { continue }

            var segments = [max(0, -left)...min(w.frame.width, size.width - left)]
            // Windows in front hide the part of this edge they overlap. Checked just above the edge, where the snow lies.
            let probe = w.frame.minY - 3
            for front in windows[..<i] {
                let f = front.frame
                guard f.minY < probe, f.maxY > probe, f.maxX > w.frame.minX, f.minX < w.frame.maxX else { continue }
                segments = cut((f.minX - w.frame.minX)...(f.maxX - w.frame.minX), from: segments)
                if segments.isEmpty { break }
            }

            let pile: SnowPile
            if let existing = piles[w.id] {
                pile = existing
                pile.resize(to: w.frame.width)
            } else {
                pile = SnowPile()
                pile.resize(to: w.frame.width)
                // Windows already open at launch start with some snow; later ones collect their own.
                if firstLook, Settings.shared.piles { pile.prefill(.random(in: 0.5...0.85)) }
                piles[w.id] = pile
                addChild(pile.node)
                addChild(pile.lights)
            }

            let origin = CGPoint(x: left, y: top)
            if let old = pile.origin, old != origin {
                lookOftenUntil = now + 0.5
                // Moving a window shakes snow off it. The further and faster it goes, the more comes off;
                // a hard drag clears most of it. The snow keeps a little of the window's motion as it falls.
                let distance = hypot(origin.x - old.x, origin.y - old.y)
                let speed = distance / elapsed
                let fraction = min(0.7, distance * 0.012 + speed / 2500)
                let carry = CGVector(dx: (origin.x - old.x) / elapsed * 0.15, dy: max(0, (origin.y - old.y) / elapsed * 0.15))
                for spot in pile.shed(fraction, maxPoints: 30) {
                    snowfall.addClump(
                        at: CGPoint(x: old.x + spot.x, y: old.y + spot.y),
                        velocity: CGVector(dx: carry.dx + .random(in: -30...30), dy: carry.dy + .random(in: -10...50)))
                }
            }
            for spot in pile.spills {
                snowfall.addClump(
                    at: CGPoint(x: origin.x + spot.x, y: origin.y + spot.y),
                    velocity: CGVector(dx: (spot.x == 0 ? -1 : 1) * .random(in: 10...35), dy: .random(in: 0...20)), radius: .random(in: 1.2...2.2))
            }
            pile.spills.removeAll()
            pile.origin = origin
            pile.node.position = origin
            pile.lights.position = origin
            pile.segments = segments
            pile.onScreen = true
            seen.insert(w.id)
            found.append(Platform(id: w.id, left: left, top: top, width: w.frame.width, pile: pile))
        }

        // Minimised, hidden or on another Space: keep the snow, just don't draw it.
        for (id, pile) in piles where !seen.contains(id) {
            pile.onScreen = false
            pile.origin = nil
        }
        // Closed for good: forget it.
        if now - lastPrune > 20 {
            lastPrune = now
            for (id, pile) in piles where !seen.contains(id) && !WindowTracker.exists(id) {
                pile.node.removeFromParent()
                pile.lights.removeFromParent()
                piles[id] = nil
            }
        }
        platforms = found
        firstLook = false
    }

    /// Removes `hole` from a list of stretches, dropping leftovers too short to bother with.
    private func cut(_ hole: ClosedRange<CGFloat>, from segments: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        for s in segments {
            if hole.upperBound <= s.lowerBound || hole.lowerBound >= s.upperBound {
                out.append(s)
                continue
            }
            if hole.lowerBound - s.lowerBound >= 10 { out.append(s.lowerBound...hole.lowerBound) }
            if s.upperBound - hole.upperBound >= 10 { out.append(hole.upperBound...s.upperBound) }
        }
        return out
    }

    // MARK: Mouse

    /// The cursor ploughs through any snow it crosses. Fast moves are walked in small steps so they don't skip over a pile.
    private func brush(from a: CGPoint, to b: CGPoint) {
        let radius: CGFloat = 13
        let steps = max(1, min(8, Int((hypot(b.x - a.x, b.y - a.y) / 10).rounded(.up))))
        let direction = abs(mouseVelocity.dx) > 30 ? (mouseVelocity.dx > 0 ? 1 : -1) : 0
        let fling = CGVector(dx: max(-900, min(900, mouseVelocity.dx)) * 0.3, dy: max(0, min(900, mouseVelocity.dy)) * 0.25)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            for platform in platforms {
                let x = p.x - platform.left, y = p.y - platform.top
                guard x > -radius, x < platform.width + radius, y > -8, y < SnowPile.heapHeight + radius,
                    platform.pile.isVisible(min(max(x, 0), platform.width))
                else { continue }
                for spot in platform.pile.brush(x: x, y: y, radius: radius, direction: direction) {
                    snowfall.addClump(
                        at: CGPoint(x: platform.left + spot.x, y: platform.top + spot.y),
                        velocity: CGVector(dx: fling.dx + .random(in: -45...45), dy: fling.dy + .random(in: 20...120)))
                }
            }
        }
    }

    /// The thing under the cursor that can be picked up, if any.
    private func target(at point: CGPoint) -> Held? {
        if let plow, plow.isUnder(point) { return .plow }
        if let ropeway = ropeways.last(where: { $0.hookIsUnder(point) }) { return .hook(ropeway) }
        if let tree = trees.last(where: { $0.alpha > 0.5 && $0.isUnder(point) }) { return .tree(tree) }
        return nil
    }

    /// Called by the overlay view. Only the press arrives as an event; the drag and release are read each frame.
    func mouseDown(at point: CGPoint) {
        guard held == nil, let target = target(at: point) else { return }
        held = target
        heldSince = lastTime
        heldFrom = point
        switch target {
        case .tree(let tree): tree.pickUp(at: point)
        case .hook(let ropeway): ropeway.pickUp()
        case .plow: plow?.pickUp()
        }
    }

    /// Right-click a decoration, or a rope's hook, to take it away.
    func rightMouseDown(at point: CGPoint) {
        if held == nil, let index = ropeways.lastIndex(where: { $0.hookIsUnder(point) }) {
            ropeways.remove(at: index).removeFromParent()
            Settings.shared.cableCars = ropeways.count
            return
        }
        guard held == nil, let index = trees.lastIndex(where: { $0.alpha > 0.5 && $0.isUnder(point) }) else { return }
        let tree = trees.remove(at: index)
        tree.run(.sequence([.group([.scale(to: 0.1, duration: 0.18), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
        Settings.shared.setCount(trees.filter { $0.kind == tree.kind }.count, of: tree.kind)
    }

    private func release() {
        guard let held else { return }
        self.held = nil
        switch held {
        case .tree(let tree):
            tree.letGo(clicked: lastTime - heldSince < 0.3 && hypot(mouse.x - heldFrom.x, mouse.y - heldFrom.y) < 5)
        case .hook(let ropeway):
            ropeway.letGo(platforms: platforms)
        case .plow:
            plow?.letGo(platforms: platforms)
        }
    }

    // MARK: Debug

    #if DEBUG
        /// Hooks the rope onto the first suitable window, so the cable car can be checked without a hand on the mouse.
        @objc func demo() {
            guard let ropeway = ropeways.first, let p = platforms.first(where: { $0.top < size.height - 100 && !$0.pile.segments.isEmpty }),
                let widest = p.pile.segments.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound })
            else { return }
            ropeway.attach(to: p, at: (widest.lowerBound + widest.upperBound) / 2 + 60)
        }

        /// Saves the overlay drawn over grey stand-ins for the real windows.
        /// (A real screenshot needs the Screen Recording permission, which this app never asks for.)
        func saveSnapshot(to path: String) {
            guard let view, let overlay = view.texture(from: self, crop: CGRect(origin: .zero, size: size))?.cgImage() else { return }
            let scale = screen.backingScaleFactor
            guard
                let c = CGContext(
                    data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            c.scaleBy(x: scale, y: scale)
            c.setFillColor(Art.rgb(0.09, 0.12, 0.22))
            c.fill(CGRect(origin: .zero, size: size))
            for w in WindowTracker.windows(at: -2).reversed() {
                let rect = CGRect(
                    x: w.frame.minX - quartzOrigin.x, y: size.height - (w.frame.maxY - quartzOrigin.y), width: w.frame.width,
                    height: w.frame.height)
                c.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
                c.setFillColor(Art.rgb(0.23, 0.24, 0.28))
                c.setStrokeColor(Art.rgb(0.42, 0.43, 0.48))
                c.drawPath(using: .fillStroke)
            }
            c.draw(overlay, in: CGRect(origin: .zero, size: size))
            guard let image = c.makeImage(),
                let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
    #endif
}
