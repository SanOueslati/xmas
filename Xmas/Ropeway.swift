import SpriteKit

/// A rope that hangs from the notch with a hook on its end.
/// Drag the hook onto a window and a cable car starts riding the rope between the two.
final class Ropeway: SKNode {
    private enum State {
        /// Hanging loose under the notch.
        case dangling
        /// In the user's hand.
        case held
        /// On a window. `settled` turns true once the hook has reached it; from then on it sticks rigidly.
        case hooked(settled: Bool)
        /// Winding back up to the notch.
        case reelingIn
    }

    /// The length of rope that hangs loose when the hook isn't on a window.
    private static let slack: CGFloat = 26

    private var state: State = .dangling
    /// Which pulley position under the notch this one uses (0 is the middle, then alternating left and right).
    var slot = 0
    /// The window the user hooked onto, and how far along its top edge.
    /// Kept while that window is covered or off-screen, so the hook can go back when it reappears.
    private var home: (id: CGWindowID, offset: CGFloat)?
    private var homeHiddenFor: CGFloat = 0
    private var homeShownFor: CGFloat = 0

    /// The pulley wheel under the notch.
    private let anchor: CGPoint
    /// The hook's eye, where the rope is tied.
    private var hookPoint: CGPoint
    private var swing: CGFloat = 0.6
    private var swingSpeed: CGFloat = 0

    private let rope = SKShapeNode()
    private let hook = SKSpriteNode(texture: Art.hook)
    private let car = SKNode()
    /// Flips so the car faces the way it is travelling.
    private let carBody = SKNode()
    /// 0 at the notch end of the rope, 1 at the hook end.
    private var progress: CGFloat = 0
    private var heading: CGFloat = 1
    private var waiting: CGFloat = 0

    init(anchor: CGPoint) {
        self.anchor = anchor
        hookPoint = CGPoint(x: anchor.x, y: anchor.y - Self.slack)
        super.init()
        zPosition = 25

        rope.strokeColor = SKColor(srgbRed: 0.87, green: 0.79, blue: 0.56, alpha: 1)
        rope.lineWidth = 1.4
        rope.lineCap = .round
        rope.fillColor = .clear
        addChild(rope)

        let bracket = SKSpriteNode(texture: Art.bracket)
        bracket.size = Art.bracketSize
        bracket.anchorPoint = CGPoint(x: Art.bracketWheel.x / Art.bracketSize.width, y: Art.bracketWheel.y / Art.bracketSize.height)
        bracket.position = anchor
        bracket.zPosition = 2
        addChild(bracket)

        hook.size = Art.hookSize
        hook.anchorPoint = CGPoint(x: Art.hookEye.x / Art.hookSize.width, y: Art.hookEye.y / Art.hookSize.height)
        hook.zPosition = 3
        addChild(hook)

        let cabin = SKSpriteNode(texture: Art.car)
        cabin.size = Art.carSize
        cabin.anchorPoint = CGPoint(x: Art.carGrip.x / Art.carSize.width, y: Art.carGrip.y / Art.carSize.height)
        let beam = SKSpriteNode(texture: Art.beam)
        beam.size = Art.beamSize
        beam.anchorPoint = CGPoint(x: 0, y: 0.5)
        beam.position = CGPoint(x: Art.carLamp.x - Art.carGrip.x, y: Art.carLamp.y - Art.carGrip.y)
        beam.zPosition = -1
        carBody.addChild(beam)
        carBody.addChild(cabin)
        car.addChild(carBody)
        car.zPosition = 4
        car.alpha = 0
        addChild(car)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func hookIsUnder(_ p: CGPoint) -> Bool {
        hypot(p.x - hookPoint.x, p.y - (hookPoint.y - 7)) < 17
    }

    func pickUp() {
        state = .held
        home = nil
    }

    /// Dropped: catch on a window's top edge if one is close, otherwise wind back up.
    func letGo(platforms: [Platform]) {
        var best: (Platform, CGFloat, CGFloat)?
        for p in platforms {
            let x = hookPoint.x - p.left
            let miss = abs(hookPoint.y - 8 - p.top)
            guard x >= 10, x <= p.width - 10, miss < 36, p.pile.isVisible(x) else { continue }
            if miss < best?.2 ?? .infinity { best = (p, x, miss) }
        }
        if let (p, x, _) = best {
            attach(to: p, at: x)
        } else {
            state = .reelingIn
        }
    }

    func attach(to p: Platform, at offset: CGFloat) {
        home = (p.id, offset)
        homeHiddenFor = 0
        state = .hooked(settled: false)
    }

    func update(dt: CGFloat, time: TimeInterval, platforms: [Platform], mouse: CGPoint) {
        // Where the hook belongs on its window, if that spot can be seen right now.
        var homePoint: CGPoint?
        if let home {
            if let p = platforms.first(where: { $0.id == home.id }) {
                if home.offset < 6 || home.offset > p.width - 6 {
                    self.home = nil
                } else if p.pile.isVisible(home.offset) {
                    homePoint = CGPoint(x: p.left + home.offset, y: p.top + 8)
                }
            } else if homeHiddenFor > 1, !WindowTracker.exists(home.id) {
                self.home = nil
            }
        }
        if homePoint == nil {
            homeHiddenFor += dt
            homeShownFor = 0
        } else {
            homeHiddenFor = 0
            homeShownFor += dt
        }

        var riding = false
        switch state {
        case .dangling:
            swingSpeed += (-28 * swing - 0.9 * swingSpeed + 1.2 * sin(CGFloat(time) * 0.9)) * dt
            swing += swingSpeed * dt
            hookPoint = CGPoint(x: anchor.x + Self.slack * sin(swing), y: anchor.y - Self.slack * cos(swing))
            // Its window came back: throw the hook over again.
            if homeShownFor > 0.3 { state = .hooked(settled: false) }

        case .held:
            let ease = min(1, dt * 30)
            hookPoint.x += (mouse.x - hookPoint.x) * ease
            hookPoint.y += (mouse.y + 7 - hookPoint.y) * ease

        case .hooked(let settled):
            if let homePoint {
                if settled {
                    hookPoint = homePoint
                    riding = true
                } else {
                    let ease = min(1, dt * 10)
                    hookPoint.x += (homePoint.x - hookPoint.x) * ease
                    hookPoint.y += (homePoint.y - hookPoint.y) * ease
                    if hypot(homePoint.x - hookPoint.x, homePoint.y - hookPoint.y) < 3 { state = .hooked(settled: true) }
                }
            } else if home == nil || homeHiddenFor > 0.6 {
                // The window closed, or something is covering it.
                state = .reelingIn
            }

        case .reelingIn:
            let rest = CGPoint(x: anchor.x, y: anchor.y - Self.slack)
            let ease = min(1, dt * 9)
            hookPoint.x += (rest.x - hookPoint.x) * ease
            hookPoint.y += (rest.y - hookPoint.y) * ease
            if hypot(rest.x - hookPoint.x, rest.y - hookPoint.y) < 2 {
                state = .dangling
                swing = 0
                swingSpeed = Bool.random() ? 2 : -2
            }
        }

        // The rope sags a little once it is long enough to.
        let span = hypot(hookPoint.x - anchor.x, hookPoint.y - anchor.y)
        let sag = max(0, span - 40) * 0.07
        let control = CGPoint(x: (anchor.x + hookPoint.x) / 2, y: (anchor.y + hookPoint.y) / 2 - sag)
        let path = CGMutablePath()
        path.move(to: anchor)
        path.addQuadCurve(to: hookPoint, control: control)
        rope.path = path
        hook.position = hookPoint
        if case .dangling = state { hook.zRotation = swing } else { hook.zRotation *= 0.8 }

        // The cable car: down to the window, a pause, back up to the notch, a pause.
        let canRide = riding && span > 170
        car.alpha += ((canRide ? 1 : 0) - car.alpha) * min(1, dt * 6)
        if canRide {
            if waiting > 0 {
                waiting -= dt
            } else {
                // Slows down as it comes into either end.
                let nearEnd = min(progress, 1 - progress)
                progress += heading * (64 / span) * (0.25 + 0.75 * min(1, nearEnd * 6)) * dt
                if progress >= 1 {
                    progress = 1
                    heading = -1
                    waiting = 1.4
                } else if progress <= 0 {
                    progress = 0
                    heading = 1
                    waiting = 1.4
                }
            }
        } else if car.alpha < 0.02 {
            progress = 0
            heading = 1
            waiting = 0.6
        }
        let t = (30 + progress * (span - 66)) / max(span, 1)
        let u = 1 - t
        car.position = CGPoint(
            x: u * u * anchor.x + 2 * u * t * control.x + t * t * hookPoint.x,
            y: u * u * anchor.y + 2 * u * t * control.y + t * t * hookPoint.y)
        car.zRotation = 0.05 * sin(CGFloat(time) * 2.3)
        carBody.xScale = heading * (hookPoint.x >= anchor.x ? 1 : -1) >= 0 ? 1 : -1
    }
}
