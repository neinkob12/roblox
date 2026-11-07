# Mobile audit (C6)

Every module in `src/client/UI/` was checked against the CLAUDE.md mobile rules. This was a code review only (no Studio in the cloud session), so the numbers below are computed from the layout code. Please confirm them in Studio's device emulator.

## How the scaling works

`UiKit.Screen` (src/client/Lib/UiKit.luau; was `Components.Screen` before the D1 cleanup) puts a `UIScale` on a root frame that is laid out in reference pixels (`Theme.ReferenceSize` = 900x420):

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
| 7 | Top-center banners | The event chip (y 8), truck banner (fixed y 48) and toasts (fixed y 90) had fixed positions. A tutorial banner (C4) would collide with them. | New `TopStack` module: banners stack by order, hidden ones take no space, and toasts follow the stack's bottom edge. Orders: price 5, event 10, truck 20, **tutorial 30 (C4: use `TopStack.Add(frame, 30)`)**, boosts 40. |
| 8 | Milk price timer | 16 ref px text is about 11.9 px on the SE, which is hard to read. | Raised to 19 ref px (about 14 px). The chip is 54 px and the boost list moved down to 68. |
| 9 | Cash block (touch) | Lifted 120 ref px from the bottom. On the SE that puts its bottom edge at y 308 ref. The classic small thumbstick starts at about y 279 ref with the 58 px top bar, so they overlap by about 30 ref px. Input is not blocked, because the cash frame and labels are `Active = false`, and the default Dynamic Thumbstick only draws where you touch. | No change, to keep the Hud diff small. If it looks crowded in the emulator, raise `lift` to 150 in `Hud.buildCash`. |
| 10 | Milk can (bottom center) | 190 ref px wide, centered. On the SE it covers about x 263 to 404 real px. The jump button starts at x 572 and the thumbstick ends at about x 110. | No overlap, no change. |
| 11 | Roblox top bar | Every HUD ScreenGui uses `IgnoreGuiInset = false`, so nothing sits under the top bar. Only the Discovery reveal is full screen (intentional, tap anywhere to close). | No change. |
| 12 | Close buttons | Every panel gets a 64 px red X from `Components.Panel`, and tapping the dim background also closes it. The crate spin and the welcome back popup have big tap targets. | Covered by fix 1. |
| 13 | Text scaling | All labels use `TextScaled` inside fixed ref px boxes, so text scales with the `UIScale`. The smallest are the side-button names (19 ref px, about 14 px on the SE) and boost rows (22 ref px). | OK. |
| 14 | Crate spin window | 640 ref px wide, and the root is at least 811 wide. | Fits. |
| 15 | Side menu, 9 buttons (wave 5: F2 Pets + E1 Daily) | 2 columns would be 5 rows (y 10 to 362 ref), well into the jump button (top about y 306 on the SE). Smaller buttons would drop below 44 px. | The grid is now **3 columns x 3 rows** (`Theme.MenuColumns = 3`, y 10 to 218, x 682 to 890 ref), so it also clears the 568x320 worst case from #5. `Theme.MenuReserve` went from 160 to 230, so panels center in the 670 ref px left of it. The 700 px Pets/Egg Shop panels scale to about 0.93, still 44 px+ targets. TopStack (x 240 to 660) stays clear. A 10th button would add a 4th row (y 290), which still fits. |

## Review round 2 (lead's client review)

| # | Finding | Fix |
|---|---|---|
| R1 | The crate spin (DisplayOrder 110) and the "NEW COW!" reveal (100) could play at the same time. The reveal spoiled the spin result, and the spin overlay swallowed its taps. | New `src/client/Lib/RevealQueue.luau`: `Push(fn, priority)`. Both overlays go through it, so only one plays at a time. Spins have priority 0 and discoveries 10, and there is a 0.15 s start delay, so a crate that gives a new cow shows the spin first and then the reveal. |
| R2 | Touch targets were below 44 px. | Already fixed by finding 1 above (MinTouch 64). |
| R3 | Some text was smaller than 14 px on 667x375. | Price chip is 200 wide with a 19 ref px timer (about 14 px). The sell chip is 250x32 with shorter text ("Collect $X at dairy!"). The Upgrades effect is 44 tall (22 per line, card 84). The Quests reward is 20 and the Shop info is 22. |
| R4 | The panel dimmer (20) covered the side menu (6), so switching panels took 2 taps. | The menu is now on `Layers.Menu = 25`, above the dimmer. Panels are centered in the area left of the menu (`Theme.MenuReserve = 160`), so they never sit under it. Their close X stays clear too. |
| R5 | The top-left HUD sat under the default chat window. | The price chip (order 5) and boosts (order 40) moved into the top-center `TopStack`. Nothing is top-left anymore. Stack orders: price 5, event 10, truck 20, tutorial 30, boosts 40. |
| R6 | DisplayOrders were magic numbers. | `Theme.Layers` = Hud 5, TopStack 7, Panels 20, Menu 25, Popups 40, Tutorial 45, Toasts 50, Reveal 100, Trailer 1000. All C6, UI and Discovery screens use it. `TrailerCamController` (B4) still uses a literal 1000, which is the same value. |

## Reduce motion

The lead's SettingsService (#28) accepts `reduceMotion`, so C6 added a **Reduce motion** toggle (default off) to Settings. The panel is now 410 tall. On the SE, fix 6 shrinks it by about 1.5%, and its buttons are still about 46.7 px. When it is on:

- Panels open instantly, with no bounce.
- Rainbow strokes stop spinning.
- Cash snaps to the new value, with no count-up, no floating "+$X" popup and no pulse.

Other packages can read it with `Components.ReduceMotion()` (UI) or `data.settings.reduceMotion` (C5 FxController, A2 DiscoveryController).

## Notes

- Hud fonts and strokes are already consistent (FredokaOne for body text, LuckiestGuy for titles, stroke 2, stroke 3 or 4 on big numbers). The cash count-up tween and `Format` everywhere were already in place from B1.
