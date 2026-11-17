# Xmas

A tiny macOS menu bar app that turns your desktop into a snowy Christmas scene, on top of the apps you're using.

- **Snowfall** across every screen, with Light / Medium / Heavy strength.
- **Wind** in three strengths that gusts and changes direction.
- **Snow settles on window tops**, packs down, rounds off over the corners and spills off the ends.
- **Move a window** and the snow shakes off it.
- **Brush snow off** by moving the cursor through it.
- **Decorations** you can drop on any window and drag around: Christmas trees, snowmen, stockings, cookies and gifts. Each one comes out a little different. Right-click one to remove it.
- **Cable cars**: drag the hook under the notch onto a window and a cable car rides the rope. Add up to five.
- **Snow plow** parked next to the menu bar icon: drag it onto a window and it clears the snow.
- **Fairy lights** along every window's top edge.

Everything is controlled from the snowflake in the menu bar. Clicks pass straight through the snow to your apps.

## Requirements

- macOS 14 or later
- Xcode 16 or later to build

No special permissions are needed: the app only reads where windows are, never what's in them.

## Build and run

Open `Xmas.xcodeproj` in Xcode and press Run, or from the terminal:

```bash
xcodebuild -project Xmas.xcodeproj -scheme Xmas -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Xmas.app
```

The project is set to sign with automatic signing; pick your own team under *Signing & Capabilities* if Xcode asks.

## How it works

One transparent, click-through window per screen hosts a SpriteKit scene. The app reads window positions with `CGWindowListCopyWindowInfo` and keeps a height map of snow for each window's top edge. All artwork is drawn in code with Core Graphics, so there are no image assets.

| File | What it does |
| --- | --- |
| `XmasApp.swift` | App entry point and the menu bar menu |
| `Overlay.swift` | The see-through window over each screen |
| `SnowScene.swift` | The scene: windows, mouse, and everything that moves |
| `Snowfall.swift` | Falling flakes, loose clumps and wind |
| `SnowPile.swift` | The snow lying on one window |
| `TreeNode.swift` | Draggable decorations |
| `Ropeway.swift` | The notch rope and cable car |
| `Plow.swift` | The snow plow |
| `Art.swift` | All the drawings |
| `Settings.swift` | Saved menu choices |
| `WindowTracker.swift` | Reads where other apps' windows are |
