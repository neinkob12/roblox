# START HERE: from build file to published game

The game is built. These are the steps only you can do, in order. Each one links to its click-by-click guide.

**Time needed:** about 1.5 hours, plus marketing.

---

## Step 1: Install Studio and open the game (10 min)
- Guide: [STUDIO_SETUP.md](STUDIO_SETUP.md), Path A.
- Download Roblox Studio at https://create.roblox.com ("Start Creating").
- Open `BrainrotCowFarm.rbxlx` (the newest one Claude sent you).
- Turn on **View > Output**. Errors show up there in red.

## Step 2: First playtest (15 min)
- Guide: [QA_CHECKLIST.md](QA_CHECKLIST.md). It takes 15 minutes and covers every pad, saving, purchases, 2 players and mobile.
- **Fast testing (admin chat commands, Studio only):** `/cash 1e9`, `/cows 10 3`, `/crate 5`, `/rebirths 2`, `/event MilkFlood`, `/price 1.5`, `/truck`, `/offline 3600`, `/reset`, `/admin` (lists all of them).
- **Codes to try in Settings:** `MOOO`, `BRAINROT`, `RELEASE`.
- **Pets and eggs:**
  1. Open the Egg Shop at the EggStand on the dairy plaza. Claim the free egg, then press **Odds** to see the chances.
  2. Wait 60s and tap the nest on your plot to hatch the egg.
  3. Open the Pets menu to equip your pet. It should follow you, and your milk/s should go up.
  - `/rebirths 3` unlocks more nests and pet slots. `/cash 1e9` lets you buy eggs.
- **Daily reward:** the Daily button in the menu.
- **Phone view:** Test tab > Device > iPhone, landscape.
- **Send Claude:** screenshots of anything red in Output, plus anything that looks off. This is the most valuable thing you can do. The game has passed type checks and a headless boot test, but nobody has played it in real Roblox yet.

## Step 3: Publish privately (5 min)
- **File > Publish to Roblox As > New experience**, named "Brainrot Cow Farm". Keep it **private** for now.
- **Game Settings > Security:** turn on **Enable Studio Access to API Services**. This is needed for saving.
- **Places:** set **Max Players to 6**. The map has exactly 6 plots.

## Step 4: Upload sounds (15 min)
- Guide: [SOUND_UPLOAD.md](SOUND_UPLOAD.md).
- There are 40 files: 20 sound effects, 18 cow voice shouts and 2 music loops, all in `sound/`.
- Bulk import them in Studio, then paste the IDs into `src/shared/Config/Sounds.luau`. A helper script fills them in.
- Until you do this, the game runs **silent**, without errors.

## Step 5: Create the Robux products (15 min)
- Guide: [MONETIZATION_SETUP.md](MONETIZATION_SETUP.md).
- **3 gamepasses:** 2x Cash, Auto Merge, Auto Sell.
- **5 dev products:** 3 cash packs, Premium Crate, 3x Boost.
- Send Claude the IDs. Until then, the shop hides those buttons.
- Studio test purchases are free.

## Step 6: Final checks (10 min)
1. **Trademark re-check.** Search each famous cow name on USPTO, EUIPO and WIPO the day you publish (the list is in [MARKETING.md](MARKETING.md), section 8).
   - Banned: Tung Tung Tung Sahur, Tralalero Tralala, Bombardiro Crocodilo, Ballerina Cappuccina.
   - Tier 18, "La Vacca Saturno Saturnita", is the least changed from its meme original. Decide whether to keep it.
2. **Fill in the Maturity questionnaire** in Creator Hub.
3. **Check verification.** Video thumbnails and some publishing steps may need ID or age verification ([MARKETING.md](MARKETING.md), section 7).

## Step 7: Marketing, then go public
- Guide: [MARKETING.md](MARKETING.md).
- In game, type `/trailer` for the cinematic camera. Keys `1`-`5` switch shots, `F` toggles the 9:16 frame for Shorts, and `H` hides the panel.
- **What to capture, all from real gameplay:**
  - A **16:9 thumbnail** at 1920x1080. This is the most important search asset.
  - A **30s store video**.
  - **Roblox Shorts**. MARKETING.md has 6 ideas with a first-second hook for each.
- Then set **Privacy: Public**.

---

## Open questions for you
- **Top cow name:** keep "La Vacca Saturno Saturnita", or switch to the safer "Saturnomoo Saturnita"?
- **After the first playtest:** anything that feels too slow or too fast? Every number is in `src/shared/Config/`, and Claude can re-tune it with the balance simulator (`python3 tools/balance_sim.py`).
