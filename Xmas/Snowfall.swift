import SpriteKit

/// A window's top edge, in scene coordinates. Snow, trees and the rope's hook can all rest on it.
struct Platform {
    let id: CGWindowID
    let left: CGFloat
    let top: CGFloat
    let width: CGFloat
    let pile: SnowPile
}

/// The snow in the air: the steady fall of flakes, and loose clumps knocked off a pile.
final class Snowfall {
    let layer = SKNode()
    var size: CGSize
    /// How hard the wind setting pushes flakes sideways, in points per second.
    var windSpeed: CGFloat = 0

    private final class Flake {
        let node: SKSpriteNode
        /// Big, soft, fast flakes "near the camera". They never settle.
        let blurred: Bool
        var x: CGFloat = 0, y: CGFloat = 0
        var radius: CGFloat = 1
        var fallSpeed: CGFloat = 60
        var windShare: CGFloat = 1
        var sway: CGFloat = 10, swayRate: CGFloat = 1, phase: CGFloat = 0
        var settles = true

        init(blurred: Bool) {
            self.blurred = blurred
            node = SKSpriteNode(texture: blurred ? Art.blurFlake : Art.flake)
        }
    }

    private struct Clump {
        let node: SKSpriteNode
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        let radius: CGFloat
        let settles: Bool
    }

    private var flakes: [Flake] = []
    private var clumps: [Clump] = []
    private var spareClumpNodes: [SKSpriteNode] = []

    init(size: CGSize) {
        self.size = size
        layer.zPosition = 40
    }

    func setFlakeCount(_ count: Int) {
        while flakes.count > count { flakes.removeLast().node.removeFromParent() }
        while flakes.count < count {
            let flake = Flake(blurred: flakes.count % 20 == 19)
            restart(flake, anywhere: true)
            layer.addChild(flake.node)
            flakes.append(flake)
        }
    }

    private func restart(_ f: Flake, anywhere: Bool) {
        let u = CGFloat.random(in: 0...1)
        f.radius = f.blurred ? .random(in: 4...7) : 0.8 + 2.3 * u * u
        f.fallSpeed = f.blurred ? .random(in: 120...170) : 30 + f.radius * 24 + .random(in: 0...16)
        f.windShare = 0.5 + f.radius * 0.25
        f.sway = .random(in: 6...22)
        f.swayRate = .random(in: 0.6...1.9)
        f.phase = .random(in: 0...(2 * .pi))
        f.settles = !f.blurred && u < 0.85
        let diameter = f.radius * (f.blurred ? 2 : 2.7)
        f.node.size = CGSize(width: diameter, height: diameter)
        f.node.alpha = f.blurred ? 0.5 : 0.55 + 0.45 * (f.radius - 0.8) / 2.3
        f.x = .random(in: 0...size.width)
        f.y = anywhere ? .random(in: 0...size.height) : size.height + .random(in: 4...30)
        f.node.position = CGPoint(x: f.x, y: f.y)
    }

    /// Loose snow that falls under gravity (knocked off by the cursor, a moving window or a landing tree).
    func addClump(at point: CGPoint, velocity: CGVector, radius: CGFloat = .random(in: 1.5...3.4)) {
        if clumps.count >= 260 { spareClumpNodes.append(clumps.removeFirst().node) }
        let node = spareClumpNodes.popLast() ?? SKSpriteNode(texture: Art.flake)
        if node.parent == nil { layer.addChild(node) }
        node.isHidden = false
        node.size = CGSize(width: radius * 2.7, height: radius * 2.7)
        node.position = point
        clumps.append(
            Clump(node: node, x: point.x, y: point.y, vx: velocity.dx, vy: velocity.dy, radius: radius, settles: Bool.random()))
    }

    func update(dt: CGFloat, time: TimeInterval, platforms: [Platform], settle: Bool) {
        let t = CGFloat(time)
        // There is always a faint breeze that swings left and right. The wind setting adds a steady push on top:
        // it gusts, and every minute or two it dies down and comes back from the other side.
        let breeze = 14 * sin(t * 0.13) + 9 * sin(t * 0.31 + 1.3) + 5 * sin(t * 0.71 + 0.5)
        let side = max(-1, min(1, 2.5 * sin(t * 0.035)))
        let gust = 0.75 + 0.25 * sin(t * 0.47) * sin(t * 1.3 + 0.8)
        let wind = breeze + windSpeed * side * gust
        for f in flakes {
            let before = f.y
            f.phase += f.swayRate * dt
            f.x += (wind * f.windShare + cos(f.phase) * f.sway) * dt
            f.y -= f.fallSpeed * dt
            if f.x < -8 { f.x += size.width + 16 } else if f.x > size.width + 8 { f.x -= size.width + 16 }
            if f.y < -8
                || (settle && f.settles && lands(x: f.x, from: before, to: f.y, amount: 0.5 + f.radius * 0.45, on: platforms))
            {
                restart(f, anywhere: false)
            } else {
                f.node.position = CGPoint(x: f.x, y: f.y)
            }
        }

        var i = 0
        while i < clumps.count {
            var c = clumps[i]
            let before = c.y
            c.vy -= 1300 * dt
            c.vx += (wind * 0.6 - c.vx) * 1.2 * dt
            c.x += c.vx * dt
            c.y += c.vy * dt
            let gone =
                c.y < -10 || c.x < -20 || c.x > size.width + 20
                || (settle && c.settles && c.vy < 0 && lands(x: c.x, from: before, to: c.y, amount: c.radius * 0.8, on: platforms))
            if gone {
                c.node.isHidden = true
                spareClumpNodes.append(c.node)
                clumps.swapAt(i, clumps.count - 1)
                clumps.removeLast()
            } else {
                c.node.position = CGPoint(x: c.x, y: c.y)
                clumps[i] = c
                i += 1
            }
        }
    }

    /// True when something falling from `before` to `after` crossed the surface of a pile and stuck to it.
    private func lands(x: CGFloat, from before: CGFloat, to after: CGFloat, amount: CGFloat, on platforms: [Platform]) -> Bool {
        for p in platforms {
            let localX = x - p.left
            guard localX >= 0, localX <= p.width, before >= p.top - SnowPile.cornerRadius, after <= p.top + SnowPile.heapHeight
            else { continue }
            let surface = p.top + p.pile.surface(at: localX)
            if before >= surface, after < surface, p.pile.isVisible(localX), p.pile.deposit(at: localX, amount: amount) {
                return true
            }
        }
        return false
    }
}
