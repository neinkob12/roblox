# QA checklist: 15 minutes before every publish

Do this in order. Tick each box. If anything fails, screenshot the **Output** window (View > Output) and send it to Claude.

Admin commands work in Studio for everyone (see `src/server/Services/AdminService.luau`). Type `/admin` in chat for the list.

## A. Fresh join (2 min)

- [ ] Press **Play** (F5). Output shows `[Server] started N modules` and **no red errors**.
- [ ] You spawn on the lobby spawn, then get moved to your own plot. The sign at your gate shows your name.
- [ ] The HUD shows cash **$10** and 1 cow in Stall1 (Mucca Pappuccia), bobbing.
- [ ] Milk flows in the pipes and the tank fill rises. After about 25 s, the tank is not empty.

## B. Core loop, every pad (4 min)

- [ ] **TankTap:** step on it. Expect "+X milk in your can" and the can icon fills. Step again with a full can: "Your can is full!".
- [ ] Walk to the **Dairy**. **DepositPad:** expect "Sold X milk at Y.YYx!" and the can is empty. The price board shows the same price.
- [ ] **CashPad:** wait 2 s, step on it. Expect "+$X" and the cash goes up by the same amount.
- [ ] Type `/cash 1e6`. Cash shows **$1M**.
- [ ] **BuyPad1:** cash goes down by the label price, +1 cow. **BuyPad5:** +5. **BuyPad25:** +25. Each label updates its price afterwards.
- [ ] **MergePad:** with 27+ tier 1 cows, step on it. Expect "MERGED! xN (up to ...)" and the discovery reveal for each new tier. Stall counters ("x3") match.
- [ ] A pad on **someone else's plot** does nothing for you (test in section F).

## C. Systems (3 min)

- [ ] **Upgrades:** buy each of the 6 once from the upgrades UI. Cash drops by the shown cost. Running Boots makes you visibly faster.
- [ ] **Crates:** `/crate 3`, open them from the UI. The spin plays and a cow near your best tier appears.
- [ ] **Buy crate** from the UI: the cash drops by the crate price.
- [ ] **Rebirth:** `/cash 1e12`, press Rebirth. Cash goes back to $10, cows back to 1, upgrades back to 0, rebirths = 1, and the "Cash x1.5" notification shows. The cow index (discovered) is kept.
- [ ] **Truck:** `/truck`. Within 1 s the truck drives in and the board says "MILK TRUCK!". It leaves after 45 s.
- [ ] **Price:** `/price 1.5`. The board shows 1.50x in green. `/price off` re-rolls it.
- [ ] **Events:** `/event MilkFlood`. The HUD timer and milk/s double. `/event off` ends it.
- [ ] **Offline:** `/offline 3600`. The welcome-back popup shows the milk amount, and the tank jumps up (never above capacity).

## D. Saving across rejoin (2 min)

Studio uses a mock store by default, so data resets every test. To test real saving:

- [ ] The game must be published, with **Game Settings > Security > Enable Studio Access to API Services** on.
- [ ] Set `USE_MOCK_IN_STUDIO = false` in `DataService.luau` **locally only** (don't commit it).
- [ ] Play, `/cash 12345`, buy 1 upgrade, stop. Play again: cash is about 12345 (plus offline earnings), and the upgrade is still level 1.
- [ ] Put `USE_MOCK_IN_STUDIO` back to `true`.
- [ ] On the live game: join, earn something, leave, rejoin on a phone. The progress is there.

## E. Purchases in Studio (1 min)

- [ ] Click each gamepass and dev product button in the shop. The Studio test purchase prompt appears (it costs no real Robux).
- [ ] Confirm "2x Cash": the cash per sell doubles. Confirm "Cash Pack S": cash goes up once. Rejoin: the gamepass is still active.
- [ ] If a product shows ID 0, its ID is not set yet in `Config/Products.luau` (see `docs/MONETIZATION_SETUP.md`).

## F. Two players (2 min)

- [ ] **Test tab > Clients and Servers**: choose 2 players, press **Start**. Two client windows open.
- [ ] Each player gets a **different plot**, with their own name on the sign.
- [ ] Player 2 steps on player 1's BuyPad and TankTap: nothing happens.
- [ ] Both sell at the dairy at the same time: both get paid, the price board is the same for both.
- [ ] Player 2 leaves: their plot becomes "Free Plot" and their cows disappear.
- [ ] Stop with **Cleanup** in the Test tab.

## G. Mobile (1 min)

- [ ] **Test tab > Device**: pick **iPhone 14 Pro**, rotate to **landscape**, press Play.
- [ ] Every button is easy to tap (at least about a fingertip). Nothing is cut off by the notch or the joystick.
- [ ] The HUD numbers are readable. Long numbers use K/M/B (e.g. "$1.23M").
- [ ] Switch to a small phone (iPhone SE) and a tablet (iPad): the layout still fits.

## H. Trailer camera (optional, 30 s)

- [ ] `/trailer` (or F7): the HUD and chat hide, the camera orbits your plot.
- [ ] Keys `1`-`5` switch shots smoothly. `F` shows the 9:16 frame. `C` hides your avatar. `H` hides the panel. Buttons do the same on mobile.
- [ ] `/trailer` again (or the Exit button): the HUD, chat and normal camera come back.

## Before you press Publish

- [ ] No red errors in Output during the whole test.
- [ ] `USE_MOCK_IN_STUDIO = true` is still committed.
- [ ] Re-checked the brainrot names (see `docs/MARKETING.md` section 8).
- [ ] Thumbnails, icon and description are uploaded.
