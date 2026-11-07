# Mobile audit (C6)

Every module in `src/client/UI/` was checked against the CLAUDE.md mobile rules. This was a code review only (no Studio in the cloud session), so the numbers below are computed from the layout code. Please confirm them in Studio's device emulator.

## How the scaling works

`Components.Screen` puts a `UIScale` on a root frame that is laid out in reference pixels (`Theme.ReferenceSize` = 900x420):

`scale = clamp(min(screenW / 900, guiH / 420), 0.7, 1.6)`

`guiH` is the screen height minus the Roblox top bar, because `IgnoreGuiInset = false`. The new top bar is 58 px tall; the classic one was 36 px.

| Device (landscape) | Screen | Scale | Root in ref px | 64 ref px button |
|---|---|---|---|---|
| iPhone SE 2/3 | 667x375 | 0.741 | 900 x 428 | 47 px |
| iPhone 14 | 844x390 | 0.79 | 1068 x 420 | 51 px |
| Small Android | 640x360 | 0.711 | 900 x 425 | 45 px |
| Worst case (scale clamped) | 568x320 | 0.70 | 811 x 374 | 45 px |
| iPad | 1024x768 | 1.14 | 900 x 642 | 73 px |
| PC 1080p | 1920x1080 | 1.6 | 1200 x 639 | 102 px |

## Findings and fixes

| # | Area | Finding | Fix |
|---|---|---|---|
| 1 | `Theme.MinTouch` | 56 ref px. The comment assumed scale 0.79, but iPhone SE is 0.741, so buttons were 41.5 px, below 44. | Raised to **64** (at least 44.8 px even at the 0.7 floor). |
| 2 | Settings rows | The toggle rows were 62 px apart, which would overlap 64 px buttons. | Rows are now `MinTouch + 2` apart (4 rows with Reduce motion) and the panel is 410 tall. |
| 3 | Shop cards | 70 px card for a 64 px button. | Card is 74 px. |
| 4 | Upgrades and Quests cards | 72 and 76 px cards for 64 px buttons. | Fits, no change. |
| 5 | Side menu | 2x3 grid centered at 42% height. Adding Index makes 4 rows (280 ref px). Centered, that would reach about y=320 ref on the SE, and the jump button starts around y=306. | The grid is now **anchored top-right** (y 10 to 290). It clears the jump button on the SE (jump top at about y 306) and on small Android (about y 298). The one exception is the 568x320 worst case, where the bottom row's corner touches the jump button by about 20x40 ref px. |
| 6 | Panels on tiny screens | At the 0.7 floor the root is only 374 ref px tall. The Shop panel (370 tall) and its close button were clipped. | `OpenPanel` shrinks a panel to fit the root, with a 12 px margin. Panels are now centered at 50% (was 52%). |
| 7 | Top-center banners | The event chip (y 8), truck banner (fixed y 48) and toasts (fixed y 90) had fixed positions. A tutorial banner (C4) would collide with them. | New `TopStack` module: banners stack by order, hidden ones take no space, and toasts follow the stack's bottom edge. Orders: event 10, truck 20, **tutorial 30 (C4: use `TopStack.Add(frame, 30)`)**. |
| 8 | Milk price timer | 16 ref px text is about 11.9 px on the SE, which is hard to read. | Raised to 19 ref px (about 14 px). The chip is 54 px and the boost list moved down to 68. |
| 9 | Cash block (touch) | Lifted 120 ref px from the bottom. On the SE that puts its bottom edge at y 308 ref. The classic small thumbstick starts at about y 279 ref with the 58 px top bar, so they overlap by about 30 ref px. Input is not blocked, because the cash frame and labels are `Active = false`, and the default Dynamic Thumbstick only draws where you touch. | No change, to keep the Hud diff small. If it looks crowded in the emulator, raise `lift` to 150 in `Hud.buildCash`. |
| 10 | Milk can (bottom center) | 190 ref px wide, centered. On the SE it covers about x 263 to 404 real px. The jump button starts at x 572 and the thumbstick ends at about x 110. | No overlap, no change. |
| 11 | Roblox top bar | Every HUD ScreenGui uses `IgnoreGuiInset = false`, so nothing sits under the top bar. Only the Discovery reveal is full screen (intentional, tap anywhere to close). | No change. |
| 12 | Close buttons | Every panel gets a 64 px red X from `Components.Panel`, and tapping the dim background also closes it. The crate spin and the welcome back popup have big tap targets. | Covered by fix 1. |
| 13 | Text scaling | All labels use `TextScaled` inside fixed ref px boxes, so text scales with the `UIScale`. The smallest are the side-button names (19 ref px, about 14 px on the SE) and boost rows (22 ref px). | OK. |
| 14 | Crate spin window | 640 ref px wide, and the root is at least 811 wide. | Fits. |

## Reduce motion

The lead's SettingsService (#28) accepts `reduceMotion`, so C6 added a **Reduce motion** toggle (default off) to Settings. The panel is now 410 tall. On the SE, fix 6 shrinks it by about 1.5%, and its buttons are still about 46.7 px. When it is on:

- Panels open instantly, with no bounce.
- Rainbow strokes stop spinning.
- Cash snaps to the new value, with no count-up, no floating "+$X" popup and no pulse.

Other packages can read it with `Components.ReduceMotion()` (UI) or `data.settings.reduceMotion` (C5 FxController, A2 DiscoveryController).

## Notes

- Hud fonts and strokes are already consistent (FredokaOne for body text, LuckiestGuy for titles, stroke 2, stroke 3 or 4 on big numbers). The cash count-up tween and `Format` everywhere were already in place from B1.
