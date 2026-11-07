# Balance report (B4)

Generated with `python3 tools/balance_sim.py --hours 168 --seeds 6` on 2026-11-07, against `main` at the A1-A4 merge.
Times are **active play time** of a "reasonable" free player (no Robux, no friends, no offline time, timed events on).
Re-run after any change to `src/shared/Config/*.luau`: the sim parses those files directly.

## Pets and eggs (P1, 2026-11-07)

The sim now models F1/F2 pets: free egg every `Eggs.FreeEggSeconds`, the Egg Shop (`Pricing.Egg`), nests, hatch odds with luck (`Odds.Egg`), equip slots, the 5 -> 1 variant merge, `Multipliers.PetBonus` with its caps, `PetIndexMilk`, and pets surviving rebirth. It also applies the E1 Index cash bonus (`IndexRewards.CashMultiplier`) in both modes, so the "no pets" column is a little faster than the B4 report further down.

Simulated egg player: claims every free egg, hatches on every plot visit, buys the best unlocked egg when it costs at most 25% of cash **and** fits a budget of 15% of all cash earned (`--egg-cash-fraction`, `--egg-budget`). Without the budget, nests free up every 60 s and the cash rule alone parks cash at 4x the egg price, so rebirths stall. Equips the milk/cash split that maximizes `(1 + milk) x (1 + cash)`.

`python3 tools/balance_sim.py --compare --hours 168 --seeds 6` (medians, current config, no config changes needed):

| Milestone | Target | No pets | Pets | Heavy egg buyer (50%/50%) | Pets + release what-if | Heavy + release |
|---|---|---|---|---|---|---|
| Tier 5 | ~5m | 4m01s | 3m08s | 3m08s | 3m08s | 3m08s |
| Tier 10 | 45-60m | 55m07s | 59m02s | 56m48s | 59m02s | 56m48s |
| Rebirth 1 | 30-45m | 33m17s | 35m00s | 40m22s | 35m00s | 40m22s |
| Rebirth 2 | | 1h17m | 1h12m | 1h17m | 1h12m | 1h17m |
| Rebirth 3 | | 1h57m | 1h50m | 2h07m | 1h50m | 2h07m |
| Rebirth 4 | | 2h57m | 2h45m | 3h22m | 2h45m | 3h22m |
| Rebirth 5 | | 4h02m | 3h53m | 4h49m | 3h53m | 4h49m |
| Tier 18 | multi-day | 1d21h | 1d22h | 1d21h | 1d18h | 2d03h |
| Pet milk / cash cap reached | | | never | never | 1d23h / 2d05h | 23h / 22h |
| Inventory full, nothing to merge | | | **15h24m** | **7h02m** | never | never |

Findings:

1. **Pets don't break pacing.** Even when both caps are reached (x16 income), tier 18 stays at 1d18h or slower and the first rebirth at 35 min or slower. Two things absorb the pet bonus. Crate prices scale with `milk/s x Multipliers.Cash`, so pet milk and cash bonuses raise them too. And tier 1 cow prices grow geometrically (`1.032 ^ bought`), so x16 income only buys about 88 more cows per run. Heavy egg buying is even slower early on, because the egg spending costs more than the early pets give back.
2. **Inventory deadlock (bug, needs code, owner F1).** There is no way to release a pet. Rainbow pets can't merge, and up to 4 normal + 4 golden copies of each of the 15 pets can sit unmerged, so every seed fills `Pets.MaxInventory = 50` with nothing left to merge (median 15 h, 7 h for a heavy buyer). After that, `placeBlocker` refuses **every** egg, the free egg too, and the pet index stops growing (23 of 45 for seed 1). Raising `MaxInventory` only delays this. Fix: a `RequestReleasePet(uid)` remote (or "release all unequipped Normals of a rarity"). `--pet-release` simulates it: pacing still holds (1d18h).
3. **Dairy and Cosmic eggs are almost never bought.** `Dairy` (600 s of income) and `Cosmic` (1800 s) cost 5x and 15x a `Pasture` egg, but give the same legendary chance per cash and per nest second (Pasture 0.2% / 120 s vs Dairy 1% / 600 s), and Pasture hatches 5x faster. Optional, not applied (pacing is fine either way): `Eggs.List.2.priceSeconds = 400` and `Eggs.List.3.priceSeconds = 900`, so the better eggs are worth saving for. With those prices the simulated player still buys only Pasture eggs (its cash rule rarely allows 4x a Dairy price), so the table doesn't change at all (tier 18 1d22h, rebirth 1 35m00s). This is a design call, not a pacing fix. Test with `--set Eggs.List.2.priceSeconds=400 --set Eggs.List.3.priceSeconds=900`.

## Targets vs. results

| Milestone | Target | Current config | Proposed tuning |
|---|---|---|---|
| Tier 5 | ~5 min | 2m26s (too fast) | 6m10s |
| Tier 10 | 45-60 min | 1h06m (ok) | 1h06m |
| First rebirth | 30-45 min | 16m45s (too fast) | 45m32s |
| Tier 18 | multi-day | **3h26m (far too fast)** | ~2 days of active play (1d23h to 2d09h) |

## Findings

1. **Crates are the runaway engine.** A crate costs 120 s of *milk* production, but it pays out a cow near your best tier. A herd is dominated by its top 2-3 cows, so one crate adds about 30% of the herd's milk for 2 minutes of income. The payback is under 7 minutes and it compounds forever. The current config reaches tier 18 in about 3.5 hours.
2. **The rebirth multiplier makes crates cheaper.** The crate price is in milk/s, while income is milk/s times the cash multiplier. At rebirth 8, crates cost 5x less in real terms.
3. **Pads are too cheap early.** 81 tier 1 cows cost about $2.3K total but merge into a tier 5 cow worth 150 milk/s, so tier 5 arrives at about 2.5 minutes.
4. **Rebirth 1 at $1M is reached in about 17 minutes.**
5. **Four upgrades never pay back in active play:** `tankCapacity`, `canSize`, `walkSpeed` and `sellSpeed`. The can already holds 30 s of production, while the round trip tank -> dairy -> tank takes about 14 s, so the can is never the bottleneck. The sell rate is 2x production, so selling isn't either. The simulated player buys only `pipeSpeed` (to max) and `autoCollect` level 1. Real players will buy them anyway, but they feel useless. See proposal 6.

## Proposed tuning (the lead applies; A3/A4 own the code)

Config-only changes (`Config/Economy.luau`):

| Key | Now | Proposed |
|---|---|---|
| `BuyBasePrice` | 5 | **10** |
| `Rebirth.BaseCost` | 1e6 | **100e6** |
| `Rebirth.CostGrowth` | 6 | **5** |
| `Crate.BuyPriceSecondsOfProduction` | 120 | **60** |
| `Crate.Odds` | -1:60, 0:30, +1:9, +2:1 | **-1:65, 0:30, +1:5, +2:0** |

New keys (need a small code change in `CrateService`, owner A4):

| New key | Value | Meaning |
|---|---|---|
| `Crate.PriceUsesCashMultiplier` | `true` | `BuyPrice = max(BuyBasePrice, milk/s * Multipliers.Cash * Seconds)`, so rebirths stop making crates cheaper |
| `Crate.BuyPriceGrowth` | `1.06` | price `*= 1.06 ^ cratesBoughtThisRebirth`. Needs a new data key `cratesBought` (reset in `RebirthService`, like `cowsBought`) |
| `Crate.MaxTier` | `14` | `Roll` clamps to `math.min(Cows.Count, MaxTier)`. Tiers 15-18 then only come from **merging**, which makes them a real long-term goal. Premium crates should respect it too |

6. **Make the "useless" upgrades matter (optional, not simulated in the table above):** lower `Can.BaseSeconds` from 30 to about 8-10, so a round trip carries less than it produces. Then `canSize` and `walkSpeed` gain value, and `autoCollect` becomes the big convenience unlock. Re-run the sim after trying it: `--set Economy.Can.BaseSeconds=8`.

Test any change before committing it:
```
python3 tools/balance_sim.py --proposed --set Economy.Can.BaseSeconds=8
```

## Raw output: current config
```

Play time to FIRST discover each tier (6 seeds, 168 h of active play)
tier  name                            median   fastest   slowest  reached  target
   1  Mucca Pappuccia                  0m00s     0m00s     0m00s   6/6  
   2  Moolino Panino                   0m00s     0m00s     0m00s   6/6  
   3  Brr Brr Patamoo                  0m37s     0m31s     1m02s   6/6  
   4  Bovino Spaghettino               1m24s     1m10s     2m01s   6/6  
   5  Lirili Larilatte                 2m26s     2m09s     2m44s   6/6  ~5m
   6  Lattuccio Biscottino             9m33s     6m40s    12m10s   6/6  
   7  Chimpanzini Muuanini            13m52s    10m25s    32m30s   6/6  
   8  Mammuccia Fragoletta            31m51s    28m45s    41m58s   6/6  
   9  Ballerina Cappumoocina          47m36s    22m55s    57m50s   6/6  
  10  Gelatino Muccalino               1h06m     1h00m     1h20m   6/6  45-60m
  11  Trippi Troppi Muuppi             1h22m     1h03m     1h41m   6/6  
  12  Pizzavacca Formaggiona           1h29m     1h21m     1h45m   6/6  
  13  Frigo Cammellatte                1h48m     1h44m     2h06m   6/6  
  14  Robomucca Bullonella             2h12m     1h45m     2h26m   6/6  
  15  Vulcanuccia Lavalina             2h25m     2h06m     2h41m   6/6  
  16  Glorbo Muuttodrillo              2h39m     2h30m     3h00m   6/6  
  17  Arcobalena Muuuricca             3h00m     2h54m     3h31m   6/6  
  18  La Vacca Saturno Saturnita       3h26m     3h14m     3h31m   6/6  multi-day

Play time to each rebirth (target: first rebirth 30-45 min)
   #  cost                            median   fastest   slowest  reached
   1  1M                              16m45s    12m40s    18m35s   6/6
   2  6M                              33m32s    24m00s    45m25s   6/6
   3  36M                             51m57s    40m45s     1h02m   6/6
   4  216M                             1h11m     1h03m     1h25m   6/6
   5  1.3B                             1h30m     1h23m     1h46m   6/6
   6  7.78B                            1h51m     1h46m     2h08m   6/6
   7  46.7B                            2h16m     2h07m     2h28m   6/6
   8  280B                             2h38m     2h31m     2h51m   6/6
   9  1.68T                            3h01m     2h56m     3h12m   6/6
  10  10.1T                            3h28m     3h16m     3h32m   6/6
  11  60.5T                            3h53m     3h41m     4h04m   6/6
  12  363T                             4h28m     4h16m     4h41m   6/6
  13  2.18Qa                           5h21m     5h07m     5h28m   6/6
  14  13.1Qa                           6h44m     6h34m     6h53m   6/6
  15  78.4Qa                           9h58m     9h56m    10h02m   6/6
  16  470Qa                           22h00m    21h31m    22h13m   6/6
  17  2.82Qi                           3d07h     3d06h     3d08h   6/6

Seed 1 at the end:    7d00h  reb 17  best T18  cash  20.2Qa  income  1.34Qa/s  cows 22802  bought 437  ups 0,25,0,0,0,1  crates bought 57893
  cows bought (all runs) 3996, crates bought 57893, crates dropped 9182
```

## Raw output: proposed tuning (`--proposed`)
```
Overrides: Economy.BuyBasePrice=10, Economy.Rebirth.BaseCost=100e6, Economy.Rebirth.CostGrowth=5, Economy.Crate.BuyPriceSecondsOfProduction=60, Economy.Crate.PriceUsesCashMultiplier=1, Economy.Crate.BuyPriceGrowth=1.06, Economy.Crate.MaxTier=14, Economy.Crate.Odds.1.weight=65, Economy.Crate.Odds.3.weight=5, Economy.Crate.Odds.4.weight=0

Play time to FIRST discover each tier (6 seeds, 168 h of active play)
tier  name                            median   fastest   slowest  reached  target
   1  Mucca Pappuccia                  0m00s     0m00s     0m00s   6/6  
   2  Moolino Panino                   0m35s     0m29s     0m40s   6/6  
   3  Brr Brr Patamoo                  1m08s     0m55s     1m33s   6/6  
   4  Bovino Spaghettino               2m18s     2m04s     2m27s   6/6  
   5  Lirili Larilatte                 6m10s     4m40s     6m23s   6/6  ~5m
   6  Lattuccio Biscottino             9m26s     6m00s    12m40s   6/6  
   7  Chimpanzini Muuanini            12m56s    12m24s    18m53s   6/6  
   8  Mammuccia Fragoletta            20m12s    18m48s    27m36s   6/6  
   9  Ballerina Cappumoocina          30m50s    23m27s    31m52s   6/6  
  10  Gelatino Muccalino               1h06m    42m21s     1h21m   6/6  45-60m
  11  Trippi Troppi Muuppi             1h44m     1h11m     2h24m   6/6  
  12  Pizzavacca Formaggiona           3h06m     2h07m     3h32m   6/6  
  13  Frigo Cammellatte                3h43m     3h32m     4h17m   6/6  
  14  Robomucca Bullonella             6h26m     3h57m     7h12m   6/6  
  15  Vulcanuccia Lavalina             8h08m     7h06m    10h04m   6/6  
  16  Glorbo Muuttodrillo             11h17m    10h08m    12h34m   6/6  
  17  Arcobalena Muuuricca            16h14m    14h24m    18h17m   6/6  
  18  La Vacca Saturno Saturnita       2d02h     1d23h     2d09h   6/6  multi-day

Play time to each rebirth (target: first rebirth 30-45 min)
   #  cost                            median   fastest   slowest  reached
   1  100M                            45m32s    39m05s    51m35s   6/6
   2  500M                             1h27m     1h16m     1h41m   6/6
   3  2.5B                             2h23m     2h01m     2h49m   6/6
   4  12.5B                            3h29m     2h58m     3h41m   6/6
   5  62.5B                            4h46m     4h01m     5h04m   6/6
   6  312B                             6h44m     5h49m     7h34m   6/6
   7  1.56T                            8h38m     7h30m    10h16m   6/6
   8  7.81T                           11h50m    10h43m    13h16m   6/6
   9  39.1T                           17h04m    15h13m    19h09m   6/6
  10  195T                             1d10h     1d07h     1d13h   6/6
  11  977T                             3d08h     3d01h     3d12h   6/6
  12  4.88Qa                               -     6d23h     6d23h   1/6

Seed 1 at the end:    7d00h  reb 11  best T18  cash    517T  income    121B/s  cows   12  bought 495  ups 0,25,0,0,0,1  crates bought 549
  cows bought (all runs) 3272, crates bought 549, crates dropped 342
```
