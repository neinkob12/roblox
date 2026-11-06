# Contracts: how the parallel sessions fit together

Read this before you write a single line. If you need to change a contract, say so loudly in your PR description and the lead session will coordinate.

## 1. File ownership (one owner per file = no merge conflicts)

| Work package | Owns (create/edit freely) | Account |
|---|---|---|
| **Lead** (this repo's integrator) | `default.project.json`, `src/server/init.server.luau`, `src/client/init.client.luau`, `src/shared/Net.luau`, `src/shared/Signal.luau`, `src/shared/Format.luau`, `src/shared/Multipliers.luau`, `src/shared/Config/Cows.luau`, `src/server/Services/DataService.luau`, `src/client/Controllers/DataController.luau`, `docs/*`, `CLAUDE.md`, `.github/*` | A |
| **A1 World & Map** | `src/server/World/*` (MapBuilder, PlotBuilder, Decor, Lighting) | A |
| **A2 Cow Models & Stalls** | `src/shared/CowModels.luau`, `src/server/Services/StallService.luau`, `src/client/Controllers/CowAnimController.luau`, `src/client/Controllers/DiscoveryController.luau` | A |
| **A3 Milk Flow & Dairy** | `src/server/Services/PlotService.luau`, `ProductionService.luau`, `CanService.luau`, `DairyService.luau`, `src/client/Controllers/PipeFlowController.luau`, tuning in `Config/Economy.luau` (Tank, Can, Dairy, MilkPrice, Truck, RareMilk, Offline) | A |
| **A4 Herd Economy** | `src/server/Services/BuyService.luau`, `MergeService.luau`, `CrateService.luau`, `UpgradeService.luau`, `RebirthService.luau`, `src/server/Services/WalkSpeedService.luau`, `Config/Upgrades.luau`, tuning in `Config/Economy.luau` (BuyPads, Merge, Crate, Rebirth) | A |
| **B1 UI / HUD** | `src/client/UI/*` (all ScreenGuis built in code) | B |
| **B2 Meta Systems** | `QuestService`, `LeaderboardService`, `EventService`, `CodesService`, `FriendBoostService`, `Config/Quests.luau`, `Config/Codes.luau`, `Config/Events.luau` | B |
| **B3 Monetization** | `MonetizationService.luau`, `Config/Products.luau`, `docs/MONETIZATION_SETUP.md` | B |
| **B4 QA, Tooling & Marketing** | `src/server/Services/AdminService.luau` (Cmdr), `tools/*` (balance sim), `src/client/Controllers/TrailerCamController.luau`, `docs/MARKETING.md`, `docs/STUDIO_SETUP.md` | B |

Sound comes LAST (after gameplay works): `Config/Sounds.luau` + `SoundController`, owned by the lead.

## 2. Lifecycle

Every module in `src/server/Services`, `src/server/World`, `src/client/Controllers` and `src/client/UI` is auto-loaded.

- `:Init()` runs first, synchronously. Create things and don't yield.
- `:Start()` runs after all Inits. You can yield, connect events and run loops.
- Require other services directly, e.g. `require(script.Parent.DataService)`.

## 3. Player data (DataService)

See the API in the header of `src/server/Services/DataService.luau`.

- **Never** keep your own copy of player state. Read `DataService:Get(player)`.
- After mutating a nested table (e.g. `data.cows["3"] += 1`), call `DataService:Replicate(player, "cows")`.
- Cows are keyed by **string** tier: `data.cows["1"]`.
- Client side: `DataController:OnChanged("cash", fn)`.

## 4. Networking (Net)

- All remotes are declared in `src/shared/Net.luau`. To add one, edit that list in your PR (the only shared-file exception, kept to one line per remote).
- The server validates everything: cash, distance to pads, cooldowns. Never trust the client.

## 5. Attributes (shared state without remotes)

| Where | Attribute | Type | Set by |
|---|---|---|---|
| `workspace` | `MilkPrice` | number (0.5 to 1.5) | A3 DairyService |
| `workspace` | `MilkPriceNextAt` | number (os.time) | A3 |
| `workspace` | `TruckActive` | bool | A3 |
| `workspace` | `TruckLeavesAt` / `TruckNextAt` | number | A3 |
| `workspace` | `EventId` | string ("" = none) | B2 EventService |
| `workspace` | `EventEndsAt` / `EventNextAt` | number | B2 |
| `Player` | `PlotId` | number 1..6 | A3 PlotService |
| `Player` | `Pass_DoubleCash` / `Pass_AutoMerge` / `Pass_AutoSell` | bool | B3 Monetization |
| `Player` | `FriendCount` | number | B2 FriendBoostService |
| `Player` | `MilkPerSecond` | number (for UI) | A3 ProductionService |
| `Player` | `TankCapacity` / `CanCapacity` / `SellPerSecond` | number (for UI) | A3 |

All cash and production math goes through `src/shared/Multipliers.luau`.

## 6. World layout (A1 builds it, everyone else finds parts BY NAME)

```
Workspace
├── Map                     (decor, ground, fences; nobody else touches)
├── Dairy                   (center of the map)
│   ├── DepositPad          (Part, touch -> deposit can into dairy queue)       A3
│   ├── CashPad             (Part, touch -> collect dairyCash)                  A3
│   ├── PriceBoard          (Part with SurfaceGui "Gui" > TextLabel "Price")    A3 writes text
│   ├── TruckStop           (Part where the truck model appears)                A3
│   └── LeaderboardCash / LeaderboardRebirths (Parts with SurfaceGui "Gui")     B2
└── Plots
    └── Plot1 .. Plot6      (Model, attribute PlotId = n, attribute OwnerUserId = 0)
        ├── Spawn           (SpawnLocation, Neutral=false; owner respawns here)
        ├── BuyPad1 / BuyPad5 / BuyPad25   (Parts + BillboardGui "Label")      A4
        ├── MergePad        (Part + BillboardGui "Label")                       A4
        ├── CrateSpawn      (Part where dropped crates appear)                  A4
        ├── Tank            (Model: "Shell" Part, "Fill" Part scaled by level)  A3
        ├── TankTap         (Part, touch -> fill can)                           A3
        ├── Pipes           (Folder of Parts, PipeFlowController animates)      A3
        ├── Stalls          (Folder: Stall1 .. Stall18, each has "CowAnchor" Attachment + BillboardGui "Count") A2
        └── OwnerSign       (Part + SurfaceGui "Gui" > TextLabel "Name")        A3
```

Pads use server-side `Touched` with a 1 second per-player debounce, and only the plot owner can use their own plot's pads. A1 must give every pad a `BillboardGui` named `Label` with a `TextLabel` named `Text`.

## 7. Definition of done for every PR

- `rojo build` succeeds, and StyLua and Selene pass (CI does this).
- No `wait()` (use `task.wait`), no deprecated APIs, `--!strict` at the top of every file.
- Your PR description lists: what you built, how to test it in Studio (steps), and any contract changes.

## 8. Integration notes (added by lead after A1-A4 merged)

These are binding for the B packages:

- **`data.dairyQueue` holds milk VALUE** (`milk * price` locked at deposit), not raw milk. The UI should label it "Selling: $X" (multiply by `Multipliers.Cash` for an estimate). `stats.milkSold` counts raw milk.
- **Missing cow keys mean 0.** Merging deletes tiers that hit 0 (`data.cows["1"] = nil`). Always use `data.cows[tostring(t)] or 0`.
- **`CrateService:GiveCrate(player, premium)`:**
  - `premium=false` adds 1 to `data.crates`
  - `premium=true` opens the crate immediately with odds +1, fires `CrateOpened(tier, "premium")` and returns the tier

  B3 calls it for the PremiumCrate product.
- **`CrateOpened(tier, source)`:** `source` is `"crate"` or `"premium"`.
- **World extras:**
  - `workspace.Map.LobbySpawn` (neutral spawn before a plot is assigned)
  - `workspace.MapReady = true` after the build
  - `workspace.MilkTruck` (truck model while active)
  - `workspace.DroppedCrates` (Parts named `MysteryCrate` with `OwnerUserId`)
- **Stalls:** `StallN` is a Part with attribute `Tier`. `Count` BillboardGui > TextLabel `Text`. The cow model is parented as `StallN.Cow`. Cow models carry attributes `CowTier` and `CowId`.
- **Reusable APIs:**
  - `CowModels.Build(tier)` (PrimaryPart `Root` at the feet, front = -Z)
  - `DiscoveryController:Show(tier)` (client reveal)
  - `PlotService:GetPlot(player)`
  - `DairyService:Deposit(player)`
  - `CanService:FillCan(player)`
  - `HerdUtil.GiveCow(player, tier, n)`
- **Player attributes for UI:** `MilkPerSecond`, `TankCapacity`, `CanCapacity`, `SellPerSecond`, `PlotId`.
- **Economy tuning keys added:** `AutoMergeSeconds`, `Tank.TickSeconds/ReplicateSeconds`, `Can.AutoCollect*`, `Dairy.TickSeconds/AutoSellSeconds`, `Truck.DriveSeconds/DriveDistance`, `Crate.DropCheckSeconds/MaxWorldCrates/PremiumOddsShift`.
