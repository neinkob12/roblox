# Monetization setup (gamepasses and dev products)

This guide is for a first-time creator on Windows. You will create 3 gamepasses and 5 developer products in Creator Hub, then paste their IDs into `src/shared/Config/Products.luau`.

Until you do this, every ID is `0`. The game still runs fine: buy buttons stay hidden and the server prints one warning, `[Monetization] Products not configured`.

## Before you start

1. Open the game in Roblox Studio (via Rojo, see `docs/STUDIO_SETUP.md`).
2. Publish it once: **File > Publish to Roblox**. Pick a name (e.g. "Brainrot Cow Farm") and click **Create**. Passes and products can only be attached to a published experience.
3. In Studio, open **Home > Game Settings > Security** and turn on **Enable Studio Access to API Services**, then **Save**. (Needed so Studio can ask Roblox whether you own a pass.)

## Part 1: Gamepasses (one-time, permanent)

Do these steps once per pass:

1. Go to **https://create.roblox.com** in your browser and log in.
2. Click **Creations** in the left menu, then click your experience (Brainrot Cow Farm).
3. In the left menu, open **Monetization > Passes**.
4. Click **Create a Pass**.
5. Click **Upload Image** and choose a square PNG (512 x 512 works well). See the icon ideas below.
6. Type the **Name** and **Description** from the table below.
7. Click **Create Pass**.
8. Click the new pass in the list, then open **Sales** in the left menu.
9. Turn on **Item for Sale**, type the **Price** in Robux from the table, and click **Save Changes**.
10. Go back to the pass list, click the **three dots** (...) on the pass and choose **Copy Asset ID**. Paste it somewhere (Notepad) next to the pass name.

| Config key | Name | Price | Description | Icon idea |
|---|---|---|---|---|
| `DoubleCash` | 2x Cash Forever | 199 | Every sale at the dairy pays double. Forever! | A cow with a gold "2x" stamp, dollar bills flying |
| `AutoMerge` | Auto Merge | 149 | Your cows merge into stronger cows automatically every few seconds. | Three small cows with arrows into one big glowing cow |
| `AutoSell` | Auto Sell | 249 | Your milk can deposits itself at the dairy, no walking needed. | A milk can with little wings flying to a dairy |

## Part 2: Developer products (can be bought again and again)

Do these steps once per product:

1. In Creator Hub, in your experience, open **Monetization > Developer Products**.
2. Click **Create a Developer Product**.
3. Upload an icon (square PNG, 512 x 512), then type the **Name**, **Description** and **Price** from the table below.
4. Click **Create Developer Product** (or **Save**).
5. In the list, click the **three dots** (...) on the product and choose **Copy Product ID**. Paste it into Notepad next to the name.

| Config key | Name | Price | Description | Icon idea |
|---|---|---|---|---|
| `CashSmall` | Cash Pack S | 25 | Instantly get 10 minutes of your farm's cash (at least $1,000). | A small stack of cash with a milk drop |
| `CashMedium` | Cash Pack M | 99 | Instantly get 1 hour of your farm's cash (at least $1,000). | A big cash pile in a milk bucket |
| `CashLarge` | Cash Pack L | 299 | Instantly get 4 hours of your farm's cash (at least $1,000). | A vault overflowing with cash and milk |
| `PremiumCrate` | Premium Milk Crate | 49 | Opens right away with better odds for a strong cow. | A golden crate with a shining cow silhouette |
| `Boost3x` | 3x Cash (15 min) | 39 | Triple cash for 15 minutes. Buying again adds more time. | A stopwatch with a big "3x" and coins |

Cash packs scale with your production: the amount is "N seconds of your current milk per second, times all your cash multipliers", with a minimum of $1,000. So they stay useful late in the game.

## Part 3: Paste the IDs

1. Open `src/shared/Config/Products.luau` in your editor (VS Code).
2. Replace each `id = 0` with the ID you copied. Example:
   ```lua
   DoubleCash = { id = 1234567890, name = "2x Cash Forever", robux = 199, attribute = "Pass_DoubleCash" },
   ```
3. Keep the `robux` numbers the same as the prices you set on the website (the UI shows these numbers).
4. Save. Rojo syncs it into Studio automatically.
5. Commit and push (or ask Claude to do it).

## Part 4: Test in Studio (free)

**Test purchases in Studio are free.** Studio shows a "This is a test purchase; your account will not be charged" popup. No Robux are spent.

1. Press **Play** in Studio.
2. Check the Output window: the "Products not configured" warning should be gone (or list only the ones you skipped).
3. Open the shop in the game's UI and buy each item. Confirm the popup.
4. Expected results:
   - **2x Cash Forever:** sales at the dairy pay double right away (no rejoin).
   - **Auto Merge:** cows merge by themselves every few seconds.
   - **Auto Sell:** your can empties into the dairy by itself every few seconds.
   - **Cash Pack:** cash goes up by the shown amount, with a "+$X from Cash Pack" popup.
   - **Premium Milk Crate:** the crate spin plays and you get a cow.
   - **3x Cash:** a "3x Cash active for 15 min!" popup. Buy again and it says 30 min.

Notes:
- In Studio, saved data resets every test (mock data store). In a live server it saves.
- Gamepass test purchases in Studio only last for that test session. After you stop and press Play again you will not own the pass (unless you really bought it). That is normal.

### Testing without any IDs (Studio command bar)

You can test the grant logic before you create anything. Press **Play**, then at the top of the **Command Bar** (View > Command Bar) make sure it says **Server**, and run:

```lua
local M = require(game.ServerScriptService.Server.Services.MonetizationService)
local p = game.Players:GetPlayers()[1]
print(M:DebugGrantProduct(p, "CashSmall"))   -- prints PurchaseGranted, cash goes up
print(M:DebugGrantProduct(p, "Boost3x"))
print(M:DebugGrantProduct(p, "PremiumCrate"))
M:DebugSetPass(p, "AutoSell", true)          -- pretend you own Auto Sell
```

These helpers do nothing outside Studio.
