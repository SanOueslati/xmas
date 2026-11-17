import AppKit

struct WindowInfo {
    let id: CGWindowID
    /// Global Quartz coordinates: origin at the top-left of the main display, y grows downward.
    let frame: CGRect
}

/// Reads where other apps' windows are. Positions and sizes need no permission (only window titles and pixels do).
enum WindowTracker {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static var cache: [WindowInfo] = []
    private static var cacheTime: TimeInterval = -1

    /// Ordinary on-screen windows, front to back. Cached per frame so every screen's scene shares one query.
    static func windows(at time: TimeInterval) -> [WindowInfo] {
        if time != cacheTime {
            cacheTime = time
            cache = query()
        }
        return cache
    }

    /// True while the window still exists, even if it is minimised or on another Space.
    static func exists(_ id: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as NSArray? else { return false }
        return list.count > 0
    }

    private static func query() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else {
            return []
        }
        let display = CGDisplayBounds(CGMainDisplayID())
        var out: [WindowInfo] = []
        out.reserveCapacity(list.count)
        for case let w as NSDictionary in list {
            // Layers 0–8 are normal windows and floating panels. Above that it's the Dock, menu bar and overlays.
            guard let layer = w[kCGWindowLayer] as? Int, (0...8).contains(layer),
                let pid = w[kCGWindowOwnerPID] as? pid_t, pid != ownPID,
                let id = w[kCGWindowNumber] as? CGWindowID,
                let bounds = w[kCGWindowBounds] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width >= 80, frame.height >= 40,
                (w[kCGWindowAlpha] as? Double ?? 1) > 0.05
            else { continue }
            // A floating panel that covers the whole display is some other app's see-through overlay, not a real window.
            if layer != 0, frame.width >= display.width * 0.95, frame.height >= display.height * 0.9 { continue }
            out.append(WindowInfo(id: id, frame: frame))
        }
        return out
    }
}
