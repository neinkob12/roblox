# Brainrot Cow Farm: rules for every Claude session

This is a Roblox game (Luau, Rojo). Several Claude sessions on two accounts build it in parallel. The lead session integrates.

## Before you start
1. Read `docs/GDD.md` (what we build) and `docs/CONTRACTS.md` (who owns which files, plus the APIs, attributes and world part names).
2. Read your GitHub issue. It names your work package (A1..A4, B1..B4) and your exact files.
3. Work ONLY in the files your package owns. If you need something from another package, code against the contract (part names, attributes, DataService API) and note it in your PR.

## Git
- Branch: `pkg/<id>-<short-name>` (e.g. `pkg/a3-milk-flow`), from latest `main`.
- Commit small and often. Open a **draft PR into `main`** early, title `[A3] Milk flow & dairy`, and link the issue (`Closes #N`).
- Before pushing: `stylua src` and `rojo build -o build/test.rbxlx`. CI runs StyLua, Selene and Rojo build.
- Never push to `main`. Never force-push someone else's branch. Merging is done by the lead session.

## Code rules
- `--!strict` at the top of every file. `task.wait/task.spawn/task.delay` only.
- Services: `ModuleScript` returning a table with optional `:Init()` and `:Start()` (auto-loaded, see CONTRACTS section 2).
- Server-authoritative: the client only sends requests through remotes declared in `src/shared/Net.luau`. Validate everything on the server.
- Player state lives ONLY in `DataService`. Cash changes only via `DataService:AddCash` / `DataService:SpendCash`.
- All multipliers go through `src/shared/Multipliers.luau`. All tunable numbers go in `src/shared/Config/*`.
- Big numbers are shown via `Format.Number` / `Format.Cash`.
- Mobile-first UI: minimum touch target 44px, use `UIScale` / `Scale` sizing, and test in Studio's device emulator (iPhone landscape).
- No Toolbox/free models (backdoor risk). Build models from Parts in code. No external HTTP.
- Wave 2 ownership is in docs/CONTRACTS.md section 9.
- Brainrot names: never use Tung Tung Tung Sahur, Tralalero Tralala, Bombardiro Crocodilo or Ballerina Cappuccina.

## Testing (you cannot run Studio)
You can't run Roblox here, so be extra careful. Before pushing, reread each file for nil-access and typos. In your PR, write exact **Studio test steps** for the human ("Press Play, walk to BuyPad5, expect cash -X and 5 cows in Stall1").

## Tools available in cloud sessions
Install if missing: `cargo install rojo --locked`, `cargo install stylua --locked --features luau`, `cargo install selene --locked`.
