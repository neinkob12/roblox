# Brainrot Cow Farm: Game Design Document

**One-liner:** Buy brainrot cows, pipe their milk into your tank, sell it at the dairy when the milk price peaks, merge 3 cows into a stronger one, rebirth, repeat.

**Reference:** Roblox "Chicken Farm" (2026). We copy the mechanics, NEVER the assets or name.

## Pillars
1. **Numbers go up, fast.** Big juicy popups, an abbreviated number for everything.
2. **Walk-around loop.** The player physically carries milk from their tank to the dairy (unlike pure idle games).
3. **Brainrot collection.** 18 funny cows; the new-tier reveal is the dopamine moment.
4. **Mobile-first.** Big buttons, landscape phone layout, works on PC.

## Core loop
1. **Buy** basic cows on the buy pads (x1 / x5 / x25). Prices scale with `cowsBought`.
2. Cows sit in **stalls** (one stall per tier shows one cow plus an "x47" counter), bobbing and mooing.
3. Milk flows through animated **pipes** into the player's **tank**. The tank has a capacity and stops when full.
4. The player walks to the **tank tap** to fill their **milk can** (the HUD shows a can icon at bottom center).
5. The player walks to the central **dairy** and steps on the **deposit pad**. The milk gets sold over time at the current **milk price** (0.5x to 1.5x, re-rolled every 30s, same for the whole server). A **milk truck** visits every ~5 minutes with a 1.5x bonus.
6. Sold cash piles up and the player steps on the **cash pad** to collect it.
7. **Merge pad:** every 3 cows of a tier become 1 of the next tier (all possible merges at once).
8. **Rare milk:** 1% golden (x5) and 0.2% diamond (x10) production ticks, with popups.
9. **Mystery Milk Crates** drop from cows or can be bought for cash. Opening one does a spin and gives a cow near your best tier.
10. **Upgrades** (all reset on rebirth): tank capacity, pipe speed, can size, walk speed, dairy sell speed, auto collect.
11. **Rebirth:** resets cash, cows and upgrades and gives a permanent +50% cash per rebirth. No tier gating.
12. **Offline earnings:** the tank keeps filling at 50% efficiency for up to 8 hours, within capacity. A welcome-back popup shows on return.

## Cows (18 tiers): see `src/shared/Config/Cows.luau`
Each tier makes 3.5x the milk of the previous one. Famous brainrot characters are cow-ified (Brr Brr Patamoo, Lirili Larilatte, Chimpanzini Muuanini, Trippi Troppi Muuppi, Frigo Cammellatte, Glorbo Muuttodrillo, La Vacca Saturno Saturnita). **Banned:** Tung Tung Tung Sahur, Tralalero Tralala, Bombardiro Crocodilo, Ballerina Cappuccina (pending US + UK Class 9 trademark; tier 9 renamed to "Tiptoe Moochiato").
Models are built from Parts (blocky style, matching the reference look). There are no meshes.

## Meta systems
- **Quests:** short rotating tasks (merge X, sell X milk, open X crates) with cash/crate/boost rewards.
- **Global leaderboards:** total cash earned and rebirths (OrderedDataStore), shown on boards at the dairy.
- **Timed events** every 10 minutes: Milk Price Frenzy (2x cash), Milk Flood (2x production), Golden Milk Rush (5x rare chance), Crate Rain. A HUD timer reads "Next event in 08:54".
- **Codes:** redeem box in settings.
- **Friend boost:** +10% cash per friend in the server, capped at +50%.
- **No obby.**

## Monetization (see `Config/Products.luau`)
- **Gamepasses:**
  - 2x Cash forever
  - Auto Merge
  - Auto Sell (the can auto-deposits remotely)
- **Dev products:**
  - Cash packs S / M / L (scaled to the player's production)
  - Premium Milk Crate
  - 3x Cash boost (15 min)

## Platform and tech
- 6 players per server, one barn plot each.
- English, with Roblox auto-translate (the user is German, so test with a German client).
- Rojo plus plain Luau (`--!strict`), ProfileStore for data, plain RemoteEvents via `Net.luau`, and UI built in code.

## Marketing (B4)
- A **16:9 gameplay thumbnail** (1920x1080), the most important search asset. Captured from real gameplay plus text overlay.
- A **gameplay video** on the store page (real gameplay, 15 to 30s).
- **Roblox Shorts** made from real gameplay clips, recorded with the in-game trailer camera mode.
- An icon (512x512).

## Sound (LAST)
- The reference game has continuous background music and no voice lines.
- We add music, sound effects (moo, pipe, cash, merge, crate), and a brainrot voice shout on each new-tier unlock (ElevenLabs).
- A mute toggle goes in settings.

## Out of scope tonight
Milk processing (cheese, butter, ice cream) is planned for update 2. Also out: trading, obby, custom meshes and rigged animations.
