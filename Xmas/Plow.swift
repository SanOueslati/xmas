import SpriteKit

/// A little snow plow that waits beside the snowflake in the menu bar.
/// Drag it onto a window's top edge and it drives the length of it, scraping the snow off, then goes back to its spot.
final class Plow: SKNode {
    private enum State {
        case parked
        case held
        /// On a window: how far along its top edge, which way (1 right, -1 left), and how many more times it turns round.
        case working(id: CGWindowID, x: CGFloat, direction: CGFloat, turns: Int)
        case returning
    }

    private var state: State = .parked
    /// Its parking spot in the menu bar (bottom-centre of the truck).
    var home = CGPoint.zero
    private let truck = SKSpriteNode(texture: Art.plow)

    override init() {
        super.init()
        zPosition = 26
        truck.size = Art.plowSize
        truck.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(truck)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func isUnder(_ p: CGPoint) -> Bool {
        abs(p.x - position.x) < 22 && p.y > position.y - 4 && p.y < position.y + 26
    }

    func pickUp() { state = .held }

    /// Dropped: start work if it is on a window's top edge, otherwise drive home.
    func letGo(platforms: [Platform]) {
        for p in platforms {
            let x = position.x - p.left
            guard abs(position.y - p.top) < 40, let stretch = p.pile.segments.first(where: { $0.contains(x) }) else { continue }
            // Head for the far end first, then come back, so the whole stretch gets cleared.
            let direction: CGFloat = stretch.upperBound - x > x - stretch.lowerBound ? 1 : -1
            state = .working(id: p.id, x: x, direction: direction, turns: 1)
            return
        }
        state = .returning
    }

    func update(dt: CGFloat, time: TimeInterval, platforms: [Platform], snowfall: Snowfall, mouse: CGPoint) {
        switch state {
        case .parked:
            position = home
            truck.xScale = 1

        case .held:
            position = CGPoint(x: mouse.x, y: mouse.y - 10)

        case .returning:
            let ease = min(1, dt * 6)
            truck.xScale = home.x >= position.x ? 1 : -1
            position.x += (home.x - position.x) * ease
            position.y += (home.y - position.y) * ease
            if hypot(home.x - position.x, home.y - position.y) < 1.5 { state = .parked }

        case .working(let id, var x, var direction, var turns):
            // Stop if the window went away or another one now covers this spot.
            guard let p = platforms.first(where: { $0.id == id }), let stretch = p.pile.segments.first(where: { $0.contains(x) })
            else {
                state = .returning
                return
            }
            x += direction * 55 * dt
            let atEnd = direction > 0 ? x > stretch.upperBound - 22 : x < stretch.lowerBound + 22
            if atEnd, turns == 0 {
                state = .returning
                return
            }
            if atEnd {
                direction = -direction
                turns -= 1
            }
            state = .working(id: id, x: x, direction: direction, turns: turns)
            position = CGPoint(x: p.left + x, y: p.top + 0.6 * sin(CGFloat(time) * 30))
            truck.xScale = direction
            // The blade scrapes down to the window and throws the snow ahead.
            for spot in p.pile.brush(x: x + direction * 18, y: 0, radius: 13, direction: Int(direction)) {
                snowfall.addClump(
                    at: CGPoint(x: p.left + spot.x, y: p.top + spot.y),
                    velocity: CGVector(dx: direction * .random(in: 30...110), dy: .random(in: 40...130)))
            }
        }
    }
}
