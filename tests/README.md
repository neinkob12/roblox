# Headless boot test (C2)

Runs the real game code (server **and** client) outside Roblox, under [Lune](https://github.com/lune-org/lune), with a mocked Roblox runtime. CI runs it as the `boot-test` job.

```sh
cargo install lune --version 0.11.1 --locked   # once
lune run tests/run.luau                        # all scenarios
lune run tests/run.luau core_loop              # only files whose name contains "core_loop"
lune run tests/scenarios/core_loop.luau        # one scenario, full game output
```

Each scenario runs in its own Lune process, so mock state never leaks between them. A scenario exits non-zero when any check fails.

## Layout

| Path | What it is |
|---|---|
| `mock/Scheduler.luau` | Fake clock + `task.*` (`spawn/defer/delay/wait/cancel`), `os.time`/`os.clock`/`tick`/`time` driven by the clock. Every thread is tagged with a context (server or one client). |
| `mock/Signal.luau` | `RBXScriptSignal` (`Connect/Once/Wait`). Handlers run in the context that connected them. |
| `mock/Datatypes.luau` | `Vector3`, `Vector2`, `CFrame` (full rotation math), `Color3`, `UDim/UDim2`, `TweenInfo`, sequences, `NumberRange`, `Random` (deterministic), `Rect`, `Font`, `BrickColor`, `Enum` (lazy), `typeof`. |
| `mock/Instance.luau` | Instance tree: classes with inheritance and defaults, `Parent`/`ChildAdded`/`DescendantAdded`/`Destroy`/`Clone`, attributes + `GetAttributeChangedSignal`, `Changed`/`GetPropertyChangedSignal`, `WaitForChild` (with the "Infinite yield possible" warning), parts, models (pivot/bounding box), GUI objects (absolute size from a 844x390 iPhone-landscape screen), humanoids, values, bindables. |
| `mock/Services.luau` | `Players` (+ `Player`, characters), `RunService`, `TweenService`, `DataStoreService` (in memory, with Roblox's serialization rules), `MarketplaceService`, `MessagingService`, `TextChatService`, `UserInputService` (phone), `HttpService` (HTTP disabled), remotes, and ~30 smaller services. |
| `mock/Loader.luau` | Builds the place from `default.project.json` with Rojo's file rules, and runs scripts with a Roblox-like global environment. Each context has its own `require` cache, like separate peers. |
| `mock/Harness.luau` | The API scenarios use: `boot`, `addPlayer`, `removePlayer`, `advance`, `touch`, `fireServer`, `invokeServer`, `click`, `pressKey`, `chat`, `received`, `serverModule`, `clientModule`, `errors`, `warnings`. |
| `lib/T.luau` | `T.check`, `T.eq`, `T.expectFail(issue, ...)`, `T.finish`. |
| `scenarios/core_loop.luau` | Issue #22 scenario: 2 players, tank -> can -> dairy -> cash, BuyPad5 + MergePad + `CowDiscovered`, crate buy/open, upgrade, rebirth, remote fuzz, leave frees the plot, 5 min soak. |
| `scenarios/systems.luau` | Codes, settings, tutorial, every admin command, monetization debug grants, quests, tapping every UI button, hotkeys, 1 h soak (events, truck, crate drops), rejoin + offline earnings, full server (7th player), death/respawn, join+leave in one frame, shutdown. |
| `scenarios/harness_selftest.luau` | Proves the harness really catches loader failures, `:Start` errors, typo'd child names, errors in delayed threads and bad remote calls. |

## What a run asserts

- No script errors anywhere (server or any client thread).
- No `warn` containing "failed" (the entry scripts warn `[Server] failed to load ...` / `:Start failed`).
- No "Infinite yield possible" warnings.
- The gameplay values listed in each scenario (cash, cows, plot ids, ...).

Known game bugs are marked with `T.expectFail("#<issue>", ...)`. They print `XFAIL` and do not fail the run. When the bug gets fixed, the check prints `XPASS` and fails, so the marker gets removed.

## How faithful is it

- **One shared instance tree.** Server and clients see the same instances (perfect, instant replication). Things the client creates locally (UI, effects) are visible to the server too. Server-only containers (`ServerScriptService`, `ServerStorage`) are not hidden from clients.
- **Remotes are asynchronous** like Roblox: delivered on the next scheduler flush, with arguments deep-copied (tables lose metatables, functions become `nil`). `FireClient` requires a real `Player`. `OnClientEvent` is per player.
- **Reading an unknown property errors** (`X is not a valid member of Class "Path"`), like Roblox. Writes are permissive.
- **Physics is not simulated.** `Touched` only fires when a scenario calls `H:touch(part, player)` (which also moves the character onto the part). `Raycast` returns `nil`. Characters never fall or walk.
- **Rendering is not simulated.** `RenderStepped`/`BindToRenderStep` run every frame, but camera, viewport and text bounds are rough numbers.
- **Tweens are instant**: goals are applied on `Play()`, `Completed` fires after the tween's duration in fake time. Tween goals are type-checked against the current property, like Roblox.
- **DataStores** live in memory. Values are checked against Roblox's rules (no mixed/sparse tables, no NaN/inf, no Instances). DataService's ProfileStore uses its own Mock path in Studio (`IsStudio()` is true here), so the scenarios also check that player data is serializable.
- `RunService:IsStudio()` is `true` (so Studio-only debug paths like admin commands and `DebugGrantProduct` are reachable).
- Not mocked: `MemoryStoreService`, `EditableImage`, localization tables, real HTTP (always errors, per the "no external HTTP" rule).

## Adding a scenario

```lua
local Harness = require("../mock/Harness")
local T = require("../lib/T")
local H = Harness.new({ root = "." })
H:boot()
local p = H:addPlayer("Alice")
H:advance(5)
T.check("has a plot", p:GetAttribute("PlotId") ~= nil)
T.finish()
```

If game code needs a Roblox API the mock lacks, the run fails with `X is not a valid member of ...` or `attempt to call a nil value`. Add it to `mock/Instance.luau` (instance classes) or `mock/Services.luau` (services).
