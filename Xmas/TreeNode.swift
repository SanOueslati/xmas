import SpriteKit

/// The decorations you can put out. The raw value is the key its count is saved under.
enum PropKind: String, CaseIterable {
    case tree = "trees"
    case snowman = "snowmen"
    case stocking = "stockings"
    case cookie = "cookies"
    case gift = "gifts"

    var title: String {
        switch self {
        case .tree: "a Christmas Tree"
        case .snowman: "a Snowman"
        case .stocking: "a Stocking"
        case .cookie: "a Cookie"
        case .gift: "a Gift"
        }
    }

    /// A freshly drawn picture (each one comes out a little different), its size, and the point on it that stands on a window.
    var art: (texture: SKTexture, size: CGSize, base: CGPoint) {
        switch self {
        case .tree: (Art.tree, Art.treeSize, Art.treeBase)
        case .snowman: (Art.snowman, Art.snowmanSize, CGPoint(x: Art.snowmanSize.width / 2, y: 3))
        case .stocking: (Art.stocking, Art.stockingSize, CGPoint(x: 26, y: 3))
        case .cookie: (Art.cookie, Art.cookieSize, CGPoint(x: Art.cookieSize.width / 2, y: 2))
        case .gift: (Art.gift, Art.giftSize, CGPoint(x: Art.giftSize.width / 2, y: 2))
        }
    }
}

/// A decoration (tree, snowman, stocking or cookie) you can pick up and stand on any window (or on the Dock).
/// Its position is the middle of the pot's foot.
final class TreeNode: SKNode {
    enum State {
        case falling
        /// Standing on a window, `offset` points in from that window's left edge.
        case onWindow(CGWindowID, offset: CGFloat)
        case onFloor
        /// In the user's hand. `grab` is where on the tree the cursor took hold.
        case held(grab: CGPoint)
    }

    private(set) var state: State = .falling
    /// Its place in the front-to-back order when nobody is holding it.
    var restingZ: CGFloat = 14
    private var stateBeforeHold: State = .falling
    private var velocity = CGVector.zero
    private var tilt: CGFloat = 0
    private var tiltSpeed: CGFloat = 0
    /// How fast the window underneath was moving last frame; a sudden change makes the tree wobble.
    private var carriedSpeed: CGFloat = 0
    private var missingFor: CGFloat = 0

    /// Holds the picture and the bulbs so a landing can squash them together.
    private let body = SKNode()
    private var lights: [SKSpriteNode] = []
    private var lightMode = 0

    let kind: PropKind
    /// No two are quite the same size.
    private let sizeScale = CGFloat.random(in: 0.85...1.2)
    private let artSize: CGSize

    init(kind: PropKind) {
        self.kind = kind
        let art = kind.art
        artSize = art.size
        super.init()
        addChild(body)
        let content = SKNode()
        content.setScale(sizeScale)
        body.addChild(content)
        let picture = SKSpriteNode(texture: art.texture)
        picture.size = art.size
        picture.anchorPoint = CGPoint(x: art.base.x / art.size.width, y: art.base.y / art.size.height)
        content.addChild(picture)
        // Only the tree carries bulbs.
        for point in kind == .tree ? Art.lightPoints : [] {
            let light = SKSpriteNode(texture: Art.glow)
            light.size = CGSize(width: 13, height: 13)
            light.position = CGPoint(x: point.x - Art.treeBase.x, y: point.y - Art.treeBase.y)
            light.zPosition = 1
            light.blendMode = .add
            light.colorBlendFactor = 1
            content.addChild(light)
            lights.append(light)
        }
        applyLights()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Roughly the tree's outline: wide at the pot, narrow at the star.
    func isUnder(_ p: CGPoint) -> Bool {
        let dx = (p.x - position.x) / sizeScale, dy = (p.y - position.y) / sizeScale
        if kind != .tree {
            let size = artSize
            return dy > -4 && dy < size.height && abs(dx) < size.width / 2
        }
        return dy > -4 && dy < 150 && abs(dx) < 16 + 32 * (1 - dy / 150)
    }

    func pickUp(at point: CGPoint) {
        stateBeforeHold = state
        state = .held(grab: CGPoint(x: point.x - position.x, y: point.y - position.y))
        zPosition = 30
    }

    /// A quick click puts the tree back and changes its lights; a real drag drops it where it is.
    func letGo(clicked: Bool) {
        zPosition = restingZ
        if clicked, case .held = state {
            state = stateBeforeHold
            lightMode = (lightMode + 1) % 3
            applyLights()
            tiltSpeed += 2.5
        } else {
            velocity.dx = max(-1500, min(1500, velocity.dx))
            velocity.dy = max(-1500, min(1500, velocity.dy))
            state = .falling
        }
    }

    /// Moves the tree one frame. Returns the window and spot it landed on, if it touched down on one just now.
    func update(dt: CGFloat, platforms: [Platform], floor: CGFloat, sceneWidth: CGFloat, mouse: CGPoint) -> (Platform, CGFloat)? {
        var landed: (Platform, CGFloat)?
        var lean: CGFloat = 0
        var visible = true

        switch state {
        case .held(let grab):
            let ease = min(1, dt * 28)
            let next = CGPoint(
                x: position.x + (mouse.x - grab.x - position.x) * ease, y: position.y + (mouse.y - grab.y - position.y) * ease)
            velocity = CGVector(dx: (next.x - position.x) / dt, dy: (next.y - position.y) / dt)
            position = next
            lean = max(-0.4, min(0.4, -velocity.dx * 0.0007))

        case .falling:
            let before = position.y
            velocity.dy -= 2400 * dt
            velocity.dx -= velocity.dx * 1.5 * dt
            position.x = min(max(position.x + velocity.dx * dt, 30), sceneWidth - 30)
            position.y += velocity.dy * dt
            lean = max(-0.3, min(0.3, -velocity.dx * 0.0004))
            if velocity.dy < 0 {
                for p in platforms {
                    let x = position.x - p.left
                    guard x >= 8, x <= p.width - 8, before >= p.top, position.y < p.top, p.pile.isVisible(x) else { continue }
                    state = .onWindow(p.id, offset: x)
                    position.y = p.top - 1
                    landed = (p, x)
                    touchDown()
                    break
                }
            }
            if case .falling = state, position.y <= floor {
                position.y = floor
                state = .onFloor
                touchDown()
            }

        case .onWindow(let id, let offset):
            if let p = platforms.first(where: { $0.id == id }) {
                missingFor = 0
                if offset < 8 || offset > p.width - 8 {
                    // The window shrank out from under it.
                    state = .falling
                } else {
                    let x = p.left + offset
                    let speed = (x - position.x) / dt
                    tiltSpeed -= (speed - carriedSpeed) * 0.0009
                    carriedSpeed = speed
                    position = CGPoint(x: x, y: p.top - 1)
                    // Another window is covering this spot: hide rather than float on top of it.
                    visible = p.pile.isVisible(offset)
                }
            } else {
                // Minimised or on another Space: wait out of sight. Closed for good: fall.
                visible = false
                missingFor += dt
                if missingFor > 1 {
                    missingFor = 0
                    if !WindowTracker.exists(id) {
                        state = .falling
                        visible = true
                    }
                }
            }

        case .onFloor:
            position.y = floor
        }

        // A spring pulls the tree upright, so it wobbles after a knock instead of snapping straight.
        tiltSpeed += (-90 * (tilt - lean) - 7 * tiltSpeed) * dt
        tilt = max(-0.6, min(0.6, tilt + tiltSpeed * dt))
        zRotation = tilt
        alpha += ((visible ? 1 : 0) - alpha) * min(1, dt * 10)
        return landed
    }

    private func touchDown() {
        velocity = .zero
        carriedSpeed = 0
        tiltSpeed += .random(in: -1.5...1.5)
        body.run(
            .sequence([
                .scaleX(to: 1.12, y: 0.86, duration: 0.06),
                .scaleX(to: 0.96, y: 1.05, duration: 0.09),
                .scaleX(to: 1, y: 1, duration: 0.10),
            ]))
    }

    private func applyLights() {
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SKColor { SKColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        let palette = [color(1, 0.25, 0.25), color(1, 0.84, 0.30), color(0.35, 1, 0.50), color(0.35, 0.62, 1), color(1, 0.45, 0.82)]
        for (i, light) in lights.enumerated() {
            light.removeAllActions()
            light.alpha = 1
            switch lightMode {
            case 0:
                // Every colour, each bulb twinkling to its own rhythm.
                light.color = palette[i % palette.count]
                let beat = Double.random(in: 0.35...1.0)
                light.run(
                    .sequence([
                        .wait(forDuration: .random(in: 0...1.2)),
                        .repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: beat), .fadeAlpha(to: 1, duration: beat)])),
                    ]))
            case 1:
                // Warm white with a slow shimmer.
                light.color = color(1, 0.84, 0.50)
                let beat = Double.random(in: 0.8...1.6)
                light.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: beat), .fadeAlpha(to: 1, duration: beat)])))
            default:
                // Red and green chasing along the strings.
                light.color = i % 2 == 0 ? color(1, 0.22, 0.22) : color(0.30, 1, 0.45)
                light.alpha = 0.2
                light.run(
                    .sequence([
                        .wait(forDuration: Double(i % 3) * 0.22),
                        .repeatForever(
                            .sequence([
                                .fadeAlpha(to: 1, duration: 0.08), .wait(forDuration: 0.2),
                                .fadeAlpha(to: 0.2, duration: 0.12), .wait(forDuration: 0.26),
                            ])),
                    ]))
            }
        }
    }
}
