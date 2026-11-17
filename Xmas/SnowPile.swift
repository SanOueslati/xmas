import SpriteKit

/// The snow lying on one window's top edge.
///
/// The window's width is cut into thin columns and each column remembers how high its snow is.
/// Coordinates here are "local": x runs from the window's left edge, y is the height above its top edge.
final class SnowPile {
    static let columnWidth: CGFloat = 3
    /// The tallest a settled pile gets.
    static let maxHeight: CGFloat = 13
    /// Pushing snow along with the cursor can heap it this high for a moment.
    static let heapHeight: CGFloat = maxHeight * 1.8
    /// How rounded a window's corners are assumed to be. The snow curves down around them.
    static let cornerRadius: CGFloat = 11
    private static let taperLength: CGFloat = 13

    let node = SKSpriteNode()
    /// A string of fairy lights along the window's top edge. Sits at the same position as `node`.
    let lights = SKNode()
    private var bulbs: [SKSpriteNode] = []
    private var lightsNeedLayout = true
    private(set) var width: CGFloat = 0
    private var heights: [CGFloat] = []
    /// How high each column may fill. Varies gently along the window so the pile isn't a flat bar.
    private var limits: [CGFloat] = []
    private let seed = CGFloat.random(in: 0...1000)

    /// Scene position of the window's top-left corner, as of the last look at the window list.
    var origin: CGPoint?
    /// False while the window is minimised, hidden or on another Space.
    var onScreen = true {
        didSet {
            node.isHidden = !(onScreen && hasPicture)
            lights.isHidden = !onScreen
        }
    }
    /// The stretches of the top edge that no other window covers.
    var segments: [ClosedRange<CGFloat>] = [] {
        didSet {
            if segments != oldValue {
                redraw(soon: true)
                lightsNeedLayout = true
            }
        }
    }

    private var hasPicture = false { didSet { node.isHidden = !(onScreen && hasPicture) } }
    private var needsRedraw = false
    private var redrawSoon = false
    private var lastRedraw: TimeInterval = 0
    /// Frames left in which carved snow keeps slumping into a natural slope.
    private var settling = 0

    init() {
        node.zPosition = 10
        lights.zPosition = 11
        node.isHidden = true
    }

    private func redraw(soon: Bool) {
        needsRedraw = true
        if soon { redrawSoon = true }
    }

    // MARK: Shape

    func resize(to newWidth: CGFloat) {
        guard abs(newWidth - width) > 0.5 || heights.isEmpty else { return }
        width = newWidth
        lightsNeedLayout = true
        let count = max(1, Int((newWidth / Self.columnWidth).rounded(.up)))
        if count < heights.count { heights.removeLast(heights.count - count) }
        while heights.count < count { heights.append(0) }
        // How much snow each column can hold. Near the ends it can only pile as steep as snow will stand,
        // so the pile rounds off over each end instead of stopping in a wall. A gentle wobble keeps the top from being flat.
        limits = (0..<count).map { i in
            let x = (CGFloat(i) + 0.5) * Self.columnWidth
            let wobble = sin((x + seed) * 0.03) * 0.6 + sin((x + seed) * 0.11 + 2) * 0.4
            return min(Self.maxHeight * (0.88 + 0.12 * wobble), 1 + edgeDistance(x) * 0.55)
        }
        for i in heights.indices { heights[i] = min(heights[i], max(limits[i], Self.heapHeight * 0.5)) }
        redraw(soon: true)
    }

    /// Starts the pile part-full so a freshly launched app doesn't look bare.
    func prefill(_ fraction: CGFloat) {
        for i in heights.indices { heights[i] = limits[i] * fraction }
        redraw(soon: true)
    }

    private func edgeDistance(_ x: CGFloat) -> CGFloat { min(x, width - x) }

    /// Snow thins out to nothing at the window's two ends.
    private func taper(_ d: CGFloat) -> CGFloat {
        if d >= Self.taperLength { return 1 }
        if d <= 0 { return 0 }
        let t = 1 - d / Self.taperLength
        return sqrt(1 - t * t)
    }

    /// How far the window's rounded corner dips below its top edge.
    private func drop(_ d: CGFloat) -> CGFloat {
        let r = Self.cornerRadius
        if d >= r { return 0 }
        let t = r - max(0, d)
        return r - sqrt(r * r - t * t)
    }

    private func sample(_ values: [CGFloat], _ x: CGFloat) -> CGFloat {
        let f = x / Self.columnWidth - 0.5
        let i = Int(f.rounded(.down))
        let a = values[min(max(i, 0), values.count - 1)], b = values[min(max(i + 1, 0), values.count - 1)]
        return a + (b - a) * (f - CGFloat(i))
    }

    /// Height of the snow's surface at local x (negative on the rounded corners).
    func surface(at x: CGFloat) -> CGFloat {
        let d = edgeDistance(x)
        return sample(heights, x) * taper(d) - drop(d)
    }

    func isVisible(_ x: CGFloat) -> Bool { segments.contains { $0.contains(x) } }

    // MARK: Fairy lights

    /// One bulb every 26 points, shown only where no other window covers the edge.
    func updateLights(enabled: Bool) {
        guard lightsNeedLayout || enabled != !bulbs.isEmpty else { return }
        lightsNeedLayout = false
        let wanted = enabled ? max(0, Int((width - 28) / 26) + 1) : 0
        while bulbs.count > wanted { bulbs.removeLast().removeFromParent() }
        let palette: [SKColor] = [
            SKColor(srgbRed: 1, green: 0.27, blue: 0.27, alpha: 1), SKColor(srgbRed: 1, green: 0.84, blue: 0.30, alpha: 1),
            SKColor(srgbRed: 0.35, green: 1, blue: 0.50, alpha: 1), SKColor(srgbRed: 0.38, green: 0.65, blue: 1, alpha: 1),
        ]
        while bulbs.count < wanted {
            let i = bulbs.count
            let bulb = SKSpriteNode(texture: Art.glow)
            bulb.size = CGSize(width: 18, height: 18)
            bulb.color = palette[i % palette.count]
            bulb.colorBlendFactor = 1
            // The string dips between pegs: every other bulb hangs a little lower.
            bulb.position = CGPoint(x: 14 + CGFloat(i) * 26, y: i % 2 == 0 ? -3 : -6)
            let beat = Double.random(in: 0.5...1.3)
            bulb.run(
                .sequence([
                    .wait(forDuration: .random(in: 0...1.3)),
                    .repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: beat), .fadeAlpha(to: 1, duration: beat)])),
                ]))
            lights.addChild(bulb)
            bulbs.append(bulb)
        }
        for bulb in bulbs { bulb.isHidden = !isVisible(bulb.position.x) }
    }

    // MARK: Adding and removing snow

    /// Snow that slid off the ends of the window since the last look, as local points. The scene turns them into falling clumps.
    var spills: [CGPoint] = []

    /// A flake lands at local x. Returns false when that spot is already full, so the flake keeps falling past it.
    func deposit(at x: CGFloat, amount: CGFloat) -> Bool {
        let column = Int(x / Self.columnWidth)
        guard heights.indices.contains(column), heights[column] < limits[column] else { return false }
        // Fresh snow packs down as the pile deepens, so it grows quickly at first and then slows.
        let packed = amount * .random(in: 0.6...1.4) * (1 - 0.55 * heights[column] / Self.maxHeight)
        for k in -2...2 where heights.indices.contains(column + k) {
            let i = column + k
            let share = 0.5 + 0.5 * cos(CGFloat(k) / 3 * .pi)
            heights[i] += packed * share
            // Too much for this spot: the extra rolls to the lower neighbour, or off the end of the window.
            if heights[i] > limits[i] {
                let extra = heights[i] - limits[i]
                heights[i] = limits[i]
                spill(extra, from: i)
            }
        }
        settling = max(settling, 6)
        redraw(soon: false)
        return true
    }

    private func spill(_ amount: CGFloat, from i: Int) {
        let left = i > 0 ? heights[i - 1] : -1, right = i < heights.count - 1 ? heights[i + 1] : -1
        let j = left < right ? i - 1 : i + 1
        if heights.indices.contains(j), heights[j] < limits[j] {
            heights[j] = min(limits[j], heights[j] + amount)
        } else if i < 8 || i > heights.count - 9 {
            spilled += amount
            if spilled > 2.5 {
                spilled = 0
                spills.append(CGPoint(x: i < 8 ? 0 : width, y: 1))
            }
        }
    }

    private var spilled: CGFloat = 0

    /// The cursor, treated as a ball, pushes through the snow.
    /// Half of what it scoops is shoved ahead of it (`direction` is -1 or 1), the rest is knocked loose.
    /// Returns local points where loose snow should start falling.
    func brush(x cx: CGFloat, y cy: CGFloat, radius: CGFloat, direction: Int) -> [CGPoint] {
        let first = max(0, Int((cx - radius) / Self.columnWidth))
        let last = min(heights.count - 1, Int((cx + radius) / Self.columnWidth))
        guard first <= last else { return [] }
        var loose: [CGPoint] = []
        var scooped: CGFloat = 0
        for i in first...last {
            let x = (CGFloat(i) + 0.5) * Self.columnWidth
            let dx = x - cx
            // The underside of the ball above this column.
            let floor = max(0, cy - sqrt(max(0, radius * radius - dx * dx)))
            guard heights[i] > floor else { continue }
            let removed = heights[i] - floor
            scooped += removed
            heights[i] = floor
            if removed > 1, loose.count < 6, isVisible(x) { loose.append(CGPoint(x: x, y: floor + removed * 0.6)) }
        }
        guard scooped > 0 else { return [] }
        if direction != 0 {
            let share = scooped * 0.5 / 4
            for k in 0..<4 {
                let i = (direction > 0 ? last + 1 : first - 1) + direction * k
                let x = (CGFloat(i) + 0.5) * Self.columnWidth
                if heights.indices.contains(i), isVisible(x) {
                    heights[i] = min(Self.heapHeight, heights[i] + share)
                } else if share > 0.6 {
                    // Pushed off the end of the window.
                    loose.append(CGPoint(x: min(max(x, 0), width), y: 1))
                }
            }
        }
        settling = 45
        redraw(soon: true)
        return loose
    }

    /// Flattens the snow under something heavy (a tree landing).
    func press(at x: CGFloat, halfWidth: CGFloat, to fraction: CGFloat) {
        let first = max(0, Int((x - halfWidth) / Self.columnWidth))
        let last = min(heights.count - 1, Int((x + halfWidth) / Self.columnWidth))
        guard first <= last else { return }
        for i in first...last { heights[i] *= fraction }
        settling = 45
        redraw(soon: true)
    }

    /// Shakes off a share of the snow (1 = all of it). Returns local points where it should start falling.
    /// The loose top layer goes first and the snow doesn't come off evenly, so what's left looks knocked about, not shrunk.
    func shed(_ fraction: CGFloat, maxPoints: Int) -> [CGPoint] {
        guard let tallest = heights.max(), tallest > 0.3 else { return [] }
        var points: [CGPoint] = []
        let total = heights.reduce(0, +)
        for i in heights.indices {
            let x = (CGFloat(i) + 0.5) * Self.columnWidth
            let lost = heights[i] * min(1, fraction * .random(in: 0.5...1.6))
            heights[i] -= lost
            // One clump for roughly every few points of snow lost, up to the cap.
            if lost > 0.4, points.count < maxPoints, isVisible(x), CGFloat.random(in: 0...1) < lost / 2.2 {
                points.append(CGPoint(x: x, y: heights[i] + lost * .random(in: 0.3...0.9)))
            }
        }
        if total > 0 { settling = 45 }
        redraw(soon: true)
        return points
    }

    /// Steep walls left by the cursor slide down until the slope is gentle.
    private func settle() {
        // Snow holds a slope of about 25 degrees: 1.4 points of height per 3-point column.
        let maxStep: CGFloat = 1.4
        for i in 0..<(heights.count - 1) {
            let d = heights[i] - heights[i + 1]
            if d > maxStep {
                let move = (d - maxStep) / 2
                heights[i] -= move
                heights[i + 1] += move
            } else if d < -maxStep {
                let move = (-d - maxStep) / 2
                heights[i] += move
                heights[i + 1] -= move
            }
        }
    }

    // MARK: Drawing

    /// Redraws the pile's picture when it has changed. Slow growth is batched; anything the user caused shows at once.
    func update(now: TimeInterval, scale: CGFloat) {
        if settling > 0 {
            settling -= 1
            settle()
            redraw(soon: true)
        }
        guard onScreen, needsRedraw, now - lastRedraw > (redrawSoon ? 0.06 : 0.5) else { return }
        needsRedraw = false
        redrawSoon = false
        lastRedraw = now

        guard !segments.isEmpty, width > 0 else {
            hasPicture = false
            return
        }
        // Soften column-to-column steps before drawing.
        var smooth = heights
        if heights.count > 2 {
            for i in 1..<(heights.count - 1) { smooth[i] = (heights[i - 1] + 2 * heights[i] + heights[i + 1]) / 4 }
        }
        var shapes: [(outline: CGPath, crest: CGPath)] = []
        for seg in segments {
            if let shape = paths(for: seg, heights: smooth) { shapes.append(shape) }
        }
        guard !shapes.isEmpty else {
            hasPicture = false
            return
        }

        // Plain fills only: this runs often and for every window, so no blurs or wide strokes.
        let pad: CGFloat = 6
        let below = Self.cornerRadius + 5
        let size = CGSize(width: (width + pad * 2).rounded(.up), height: (below + Self.heapHeight + 6).rounded(.up))
        node.texture = Art.texture(width: size.width, height: size.height, scale: scale) { c in
            c.translateBy(x: pad, y: below)
            for shape in shapes {
                // A faint shadow underneath, so the snow still reads on a white window.
                c.saveGState()
                c.translateBy(x: 0, y: -1.2)
                c.setFillColor(Art.rgb(0.05, 0.12, 0.30, 0.28))
                c.addPath(shape.outline)
                c.fillPath()
                c.restoreGState()
                // Blue-grey body, white along the top as if lit from above.
                c.setFillColor(Art.rgb(0.80, 0.87, 0.97))
                c.addPath(shape.outline)
                c.fillPath()
                c.setFillColor(Art.rgb(1, 1, 1))
                c.addPath(shape.crest)
                c.fillPath()
            }
        }
        node.size = size
        node.anchorPoint = CGPoint(x: pad / size.width, y: below / size.height)
        hasPicture = true
    }

    /// The snow's outline over one visible stretch of the edge, plus the bright band along its top.
    private func paths(for seg: ClosedRange<CGFloat>, heights: [CGFloat]) -> (outline: CGPath, crest: CGPath)? {
        let start = max(0, seg.lowerBound), end = min(width, seg.upperBound)
        guard end - start > 4 else { return nil }
        var top: [CGPoint] = [], bottom: [CGPoint] = [], band: [CGPoint] = []
        var peak: CGFloat = 0
        var x = start
        while true {
            let d = edgeDistance(x), thin = taper(d), base = -drop(d)
            let h = sample(heights, x) * thin
            peak = max(peak, h)
            // Dips a little below the edge so no gap shows between snow and window.
            let low = base - 2.5 * thin
            top.append(CGPoint(x: x, y: base + h))
            bottom.append(CGPoint(x: x, y: low))
            band.append(CGPoint(x: x, y: max(low, base + h - 4.5)))
            if x >= end { break }
            // Finer steps near the window's ends, where the outline curves.
            x = min(end, x + (d < Self.taperLength + 3 ? 1.5 : 3))
        }
        guard peak > 0.6 else { return nil }
        let outline = CGMutablePath()
        outline.addLines(between: top + bottom.reversed())
        outline.closeSubpath()
        let crest = CGMutablePath()
        crest.addLines(between: top + band.reversed())
        crest.closeSubpath()
        return (outline, crest)
    }
}
