#!/usr/bin/env python3
"""Brainrot Cow Farm balance simulator (B4). Python 3.8+, no dependencies.

Reads the REAL tuning numbers from src/shared/Config/{Economy,Cows,Upgrades,Events}.luau
(via tools/luau_config.py) and re-implements the server formulas from:

  ProductionService  tank fill, tank capacity, rare milk rolls
  CanService         can capacity, tank tap, Auto Collect upgrade
  DairyService       price locked at deposit, sell rate, cash pad, milk price, milk truck
  BuyService         geometric cow price
  MergeService       3 -> 1 cascade merge
  CrateService       drops, buy price, odds relative to best tier
  UpgradeService     upgrade costs
  RebirthService     cost, reset, cash multiplier
  Multipliers        cash and production multipliers (events included)

KEEP IN SYNC: formulas live in the functions marked `# == <Service>` below. Config numbers are
parsed, so tuning Config/*.luau needs no change here. World distances (WALK_*) come from
MapBuilder / PlotBuilder and are duplicated below.

The simulated player is "reasonable": walks the tank -> dairy loop, merges every plot visit,
buys whatever pays back fastest (cows, crates, upgrades) unless saving for a rebirth is faster,
and rebirths as soon as it can afford it. No Robux, no friends, no offline time.

Usage:
  python3 tools/balance_sim.py                      # 8 seeds, 72 h of play
  python3 tools/balance_sim.py --hours 24 --seeds 4
  python3 tools/balance_sim.py --set Economy.Crate.BuyPriceSecondsOfProduction=60
  python3 tools/balance_sim.py --proposed           # with B4's proposed tuning (tools/BALANCE.md)
  python3 tools/balance_sim.py --double-cash         # 2x Cash gamepass player
  python3 tools/balance_sim.py --trace 600           # print a state line every 600 s (seed 1)
"""

from __future__ import annotations

import argparse
import math
import random
import statistics
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luau_config import load_all  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "src" / "shared" / "Config"

# --- world geometry (KEEP IN SYNC with src/server/World/MapBuilder.luau + PlotBuilder.luau) ------
# Plot center is PLOT_RADIUS=106 from the dairy center, TankTap at plot-local (-22, -25),
# DepositPad at dairy-local (-6.5, 0), CashPad at (6.5, 0).
WALK_TAP_TO_DEPOSIT = 84.0
WALK_DEPOSIT_TO_CASH = 13.0
WALK_CASH_TO_TAP = 90.0
PAD_OVERHEAD = 1.0  # seconds lost per pad (touch + 1 s debounce)
BASE_WALK_SPEED = 16.0  # WalkSpeedService

# --- player behaviour knobs (not game config) ----------------------------------------------------
DECIDE_EVERY = 5  # seconds between shopping decisions (UI purchases work anywhere)
AUTO_PLOT_VISIT_EVERY = 120  # with Auto Collect the player camps at the dairy, visits plot this often
MAX_CASH_WAIT = 15  # seconds the player waits at the cash pad for the queue to finish selling
AUTO_COLLECT_CONVENIENCE = 0.5  # players value Auto Collect at ~50% of income even if it adds no rate


# Keys that do NOT exist in Config yet. The sim understands them so proposed tuning can be tested
# with --set before the owning session implements them (defaults = current game behaviour).
PROPOSED_KEYS = {
    "BuyPriceGrowth": "Economy.Crate.BuyPriceGrowth: crate price *= this ^ crates bought this rebirth (default 1)",
    "MaxTier": "Economy.Crate.MaxTier: crates never roll above this tier (default = top tier); higher tiers only by merging",
    "PriceUsesCashMultiplier": "Economy.Crate.PriceUsesCashMultiplier: 1 = crate price also scales with the cash multiplier",
}


# B4's proposed tuning (see tools/BALANCE.md). `--proposed` applies it on top of the parsed config.
PROPOSED_TUNING = [
    "Economy.BuyBasePrice=10",
    "Economy.Rebirth.BaseCost=100e6",
    "Economy.Rebirth.CostGrowth=5",
    "Economy.Crate.BuyPriceSecondsOfProduction=60",
    "Economy.Crate.PriceUsesCashMultiplier=1",
    "Economy.Crate.BuyPriceGrowth=1.06",
    "Economy.Crate.MaxTier=14",
    "Economy.Crate.Odds.1.weight=65",
    "Economy.Crate.Odds.3.weight=5",
    "Economy.Crate.Odds.4.weight=0",
]


def fmt_num(n: float) -> str:
    suffixes = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
    if n < 1000:
        return f"{n:.0f}"
    i = 0
    while n >= 1000 and i < len(suffixes) - 1:
        n /= 1000
        i += 1
    return f"{n:.3g}{suffixes[i]}"


def fmt_time(s: Optional[float]) -> str:
    if s is None:
        return "-"
    s = int(s)
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    if s < 86400:
        return f"{s // 3600}h{(s % 3600) // 60:02d}m"
    return f"{s // 86400}d{(s % 86400) // 3600:02d}h"


def apply_override(cfg: Dict[str, Any], spec: str) -> None:
    """--set Economy.Crate.BuyPriceSecondsOfProduction=60 / Upgrades.pipeSpeed.costGrowth=2 / Cows.growth=4"""
    path, _, raw = spec.partition("=")
    keys = path.split(".")
    node: Any = cfg
    for k in keys[:-1]:
        node = node[int(k) - 1] if isinstance(node, list) else node[k]
    last = keys[-1]
    value: Any = float(raw) if raw.replace(".", "", 1).replace("e", "", 1).replace("-", "", 1).isdigit() else raw
    if isinstance(node, list):
        node[int(last) - 1] = value
    else:
        if last not in node and last not in PROPOSED_KEYS:
            raise SystemExit(f"--set: unknown key {path} (proposed keys: {', '.join(PROPOSED_KEYS)})")
        node[last] = value


class Sim:
    def __init__(self, cfg: Dict[str, Any], seed: int, double_cash: bool = False, events: bool = True):
        self.cfg = cfg
        self.E = cfg["Economy"]
        self.U = cfg["Upgrades"]
        self.EV = cfg["Events"]
        self.growth = cfg["Cows"]["growth"]
        self.tier_count = len(cfg["Cows"]["tiers"])
        self.rng = random.Random(seed)
        self.double_cash = double_cash
        self.events_on = events

        self.t = 0
        # world
        self.price = 1.0
        self.price_next = 0
        self.truck_active = False
        self.truck_next = self.E["Truck"]["EverySeconds"]
        self.truck_leaves = 0
        self.event: Optional[Dict[str, Any]] = None
        self.event_ends = 0
        self.event_next = self.EV["EverySeconds"]
        # player
        self.cash = float(self.E["StartingCash"])
        self.cows: Dict[int, int] = {}
        self.reset_run()
        self.rebirths = 0
        self.crates = 0
        self.world_crates = 0
        self.discovered: Dict[int, int] = {}
        self.rebirth_times: List[int] = []
        self.run_best_times: List[Dict[int, int]] = [{}]
        self._mark_discovered()
        # movement state machine
        self.state = "plot"
        self.timer = 0.0
        self.last_auto_fill = -1e9
        self.last_plot_visit = 0
        self.cash_wait = 0
        self.cows_bought_total = 0
        self.crates_bought = 0
        self.crates_dropped = 0

    # ------------------------------------------------------------------ state helpers
    def reset_run(self) -> None:
        # == RebirthService (reset) / DataService template
        self.cows = {int(k): int(v) for k, v in self.E["StartingCows"].items()}
        self.cows_bought = 0
        self.tank = 0.0
        self.can = 0.0
        self.queue = 0.0
        self.dairy_cash = 0.0
        self.up = {k: 0 for k in self.U}
        self.crates_bought_run = 0

    def _mark_discovered(self) -> None:
        run = self.run_best_times[-1]
        for tier, n in self.cows.items():
            if n > 0:
                if tier not in self.discovered:
                    self.discovered[tier] = self.t
                if tier not in run:
                    run[tier] = self.t

    def best_tier(self) -> int:
        tiers = [t for t, n in self.cows.items() if n > 0]
        return max(tiers) if tiers else 1

    # ------------------------------------------------------------------ formulas
    def tier_mps(self, tier: int) -> float:
        return self.growth ** (tier - 1)  # == Cows.luau milkPerSecond

    def herd_mps(self, cows: Optional[Dict[int, int]] = None) -> float:
        cows = self.cows if cows is None else cows
        return sum(self.tier_mps(t) * n for t, n in cows.items())  # == Multipliers.HerdMilkPerSecond

    def production_mult(self, up: Dict[str, int], with_event: bool = True) -> float:
        # == Multipliers.Production
        m = 1 + up["pipeSpeed"] * self.U["pipeSpeed"]["perLevel"]
        if with_event and self.event and self.event.get("productionMultiplier"):
            m *= self.event["productionMultiplier"]
        return m

    def cash_mult(self, rebirths: int, with_event: bool = True) -> float:
        # == Multipliers.Cash (no friends, no boosts)
        m = 1 + self.E["Rebirth"]["CashMultiplierPerRebirth"] * rebirths
        if self.double_cash:
            m *= 2
        if with_event and self.event and self.event.get("cashMultiplier"):
            m *= self.event["cashMultiplier"]
        return m

    def mps(self, cows=None, up=None, with_event: bool = True) -> float:
        up = self.up if up is None else up
        return self.herd_mps(cows) * self.production_mult(up, with_event)

    def tank_cap(self, mps: float, up: Dict[str, int]) -> float:
        # == ProductionService:GetTankCapacity
        T = self.E["Tank"]
        return max(T["MinCapacity"], mps * T["BaseSeconds"]) * (1 + up["tankCapacity"] * self.U["tankCapacity"]["perLevel"])

    def can_cap(self, mps: float, up: Dict[str, int]) -> float:
        # == CanService:GetCanCapacity
        C = self.E["Can"]
        return max(C["MinCapacity"], mps * C["BaseSeconds"]) * (1 + up["canSize"] * self.U["canSize"]["perLevel"])

    def sell_rate(self, mps: float, up: Dict[str, int]) -> float:
        # == DairyService:GetSellPerSecond (value units / s)
        D = self.E["Dairy"]
        rate = mps * D["BaseSellFactor"] * (1 + up["sellSpeed"] * self.U["sellSpeed"]["perLevel"])
        return max(D["MinSellPerSecond"], rate)

    def auto_interval(self, up: Dict[str, int]) -> float:
        # == CanService autoCollect loop
        C = self.E["Can"]
        return max(C["AutoCollectMinSeconds"], C["AutoCollectBaseSeconds"] - up["autoCollect"] * self.U["autoCollect"]["perLevel"])

    def walk_speed(self, up: Dict[str, int]) -> float:
        return BASE_WALK_SPEED + up["walkSpeed"] * self.U["walkSpeed"]["perLevel"]  # == WalkSpeedService

    def cow_price(self, n: int = 1) -> float:
        # == BuyService:Price
        base, g = self.E["BuyBasePrice"], self.E["BuyPriceGrowth"]
        total = base * n if g == 1 else base * g ** self.cows_bought * (g ** n - 1) / (g - 1)
        return math.floor(total + 0.5)

    def crate_price(self) -> float:
        # == CrateService:BuyPrice
        C = self.E["Crate"]
        mps = self.mps(with_event=False)
        if C.get("PriceUsesCashMultiplier"):  # proposed
            mps *= self.cash_mult(self.rebirths, with_event=False)
        price = max(C["BuyBasePrice"], mps * C["BuyPriceSecondsOfProduction"])
        return math.floor(price * C.get("BuyPriceGrowth", 1) ** self.crates_bought_run)  # proposed growth

    def upgrade_cost(self, uid: str) -> float:
        u = self.U[uid]
        return math.floor(u["baseCost"] * u["costGrowth"] ** self.up[uid])  # == Upgrades.Cost

    def rebirth_cost(self) -> float:
        R = self.E["Rebirth"]
        return math.floor(R["BaseCost"] * R["CostGrowth"] ** self.rebirths)  # == RebirthService:Cost

    def trip_seconds(self, up: Dict[str, int]) -> float:
        dist = WALK_TAP_TO_DEPOSIT + WALK_DEPOSIT_TO_CASH + WALK_CASH_TO_TAP
        return dist / self.walk_speed(up) + 3 * PAD_OVERHEAD

    # Steady-state cash/s of the current loop (used only for the player's shopping decisions)
    def income(self, cows=None, up=None, rebirths=None) -> float:
        up = self.up if up is None else up
        rebirths = self.rebirths if rebirths is None else rebirths
        mps = self.mps(cows, up, with_event=False)
        per = self.auto_interval(up) if up["autoCollect"] > 0 else self.trip_seconds(up)
        carry = min(self.can_cap(mps, up), self.tank_cap(mps, up) + mps * per)
        milk = min(mps, carry / per)
        value = min(milk, self.sell_rate(mps, up))
        return value * self.cash_mult(rebirths, with_event=False)

    # ------------------------------------------------------------------ actions
    def merge_all(self) -> None:
        # == MergeService:MergeAll (bottom-up cascade)
        cost = int(self.E["MergeCost"])
        for tier in range(1, self.tier_count):
            have = self.cows.get(tier, 0)
            n = have // cost
            if n > 0:
                left = have - n * cost
                if left > 0:
                    self.cows[tier] = left
                else:
                    self.cows.pop(tier, None)
                self.cows[tier + 1] = self.cows.get(tier + 1, 0) + n
        self._mark_discovered()

    def roll_crate(self, shift: int = 0) -> int:
        # == CrateService:Roll
        odds = self.E["Crate"]["Odds"]
        total = sum(o["weight"] for o in odds)
        pick = self.rng.random() * total
        offset = odds[-1]["offset"]
        for o in odds:
            pick -= o["weight"]
            if pick <= 0:
                offset = o["offset"]
                break
        cap = int(self.E["Crate"].get("MaxTier", self.tier_count))  # proposed
        return int(min(max(self.best_tier() + offset + shift, 1), self.tier_count, max(cap, 1)))

    def open_crates(self) -> None:
        while self.crates > 0:
            self.crates -= 1
            tier = self.roll_crate()
            self.cows[tier] = self.cows.get(tier, 0) + 1
        self._mark_discovered()

    def expected_crate_cows(self) -> Dict[int, int]:
        """Herd after one crate, using expected milk (fractional cow of the best tier)."""
        odds = self.E["Crate"]["Odds"]
        total = sum(o["weight"] for o in odds)
        best = self.best_tier()
        cap = int(self.E["Crate"].get("MaxTier", self.tier_count))
        gain = 0.0
        for o in odds:
            tier = int(min(max(best + o["offset"], 1), self.tier_count, cap))
            gain += o["weight"] / total * self.tier_mps(tier)
        cows = dict(self.cows)
        # express the expected gain as extra tier-1 milk so herd_mps adds it linearly
        cows[1] = cows.get(1, 0) + gain / self.tier_mps(1)
        return cows

    def do_rebirth(self) -> None:
        # == RebirthService onRequest
        self.cash = float(self.E["StartingCash"])
        self.reset_run()
        self.rebirths += 1
        self.rebirth_times.append(self.t)
        self.run_best_times.append({})
        self._mark_discovered()

    def shop(self, at_plot: bool) -> None:
        if self.cash >= self.rebirth_cost():
            self.do_rebirth()
            return
        base = self.income()
        for _ in range(500):  # safety
            options = []
            if at_plot:
                cows = dict(self.cows)
                cows[1] = cows.get(1, 0) + 1
                options.append(("cow", self.cow_price(1), self.income(cows=cows) - base))
            options.append(("crate", self.crate_price(), self.income(cows=self.expected_crate_cows()) - base))
            for uid, u in self.U.items():
                if self.up[uid] >= u["maxLevel"]:
                    continue
                up = dict(self.up)
                up[uid] += 1
                gain = self.income(up=up) - base
                if uid == "autoCollect" and self.up[uid] == 0:
                    gain = max(gain, base * AUTO_COLLECT_CONVENIENCE)
                options.append((uid, self.upgrade_cost(uid), gain))
            options = [o for o in options if o[2] > 1e-12]
            if not options:
                return
            name, cost, gain = min(options, key=lambda o: o[1] / o[2])
            payback = cost / gain
            # an investment that pays back after the next rebirth is wasted (rebirth resets it)
            to_rebirth = (self.rebirth_cost() - self.cash) / base if base > 0 else math.inf
            if payback > to_rebirth and to_rebirth < 3600:
                return
            if self.cash < cost:
                return
            self.cash -= cost
            if name == "cow":
                self.cows_bought += 1
                self.cows_bought_total += 1
                self.cows[1] = self.cows.get(1, 0) + 1
                self._mark_discovered()
            elif name == "crate":
                self.crates_bought += 1
                self.crates_bought_run += 1
                self.crates += 1
                self.open_crates()
            else:
                self.up[name] += 1
            base = self.income()

    def at_plot(self) -> None:
        self.crates += self.world_crates  # touch the dropped crates
        self.world_crates = 0
        self.open_crates()
        self.merge_all()
        self.shop(at_plot=True)
        self.merge_all()
        self.last_plot_visit = self.t

    def fill_can(self) -> None:
        # == CanService:FillCan
        cap = self.can_cap(self.mps(), self.up)
        move = min(self.tank, max(0.0, cap - self.can))
        self.tank -= move
        self.can += move

    def deposit(self) -> None:
        # == DairyService:Deposit (price locked at deposit)
        if self.can <= 0:
            return
        price = self.price * (self.E["Truck"]["PriceBonus"] if self.truck_active else 1)
        self.queue += self.can * price
        self.can = 0.0

    def collect(self) -> None:
        self.cash += self.dairy_cash
        self.dairy_cash = 0.0

    # ------------------------------------------------------------------ world ticks
    def world_tick(self) -> None:
        t = self.t
        MP = self.E["MilkPrice"]
        if t >= self.price_next:  # == DairyService rollPrice
            p = MP["Min"] + self.rng.random() * (MP["Max"] - MP["Min"])
            self.price = math.floor(p * 100 + 0.5) / 100
            self.price_next = t + MP["IntervalSeconds"]
        TR = self.E["Truck"]
        if self.truck_active and t >= self.truck_leaves:
            self.truck_active = False
            self.truck_next = t + TR["EverySeconds"]
        elif not self.truck_active and t >= self.truck_next:
            self.truck_active = True
            self.truck_leaves = t + TR["StaysSeconds"]
        if self.events_on:  # == EventService (B2): one random event every EverySeconds
            if self.event and t >= self.event_ends:
                self.event = None
            if not self.event and t >= self.event_next:
                self.event = self.rng.choice(self.EV["List"])
                self.event_ends = t + self.event["seconds"]
                self.event_next = t + self.EV["EverySeconds"]

    def production_tick(self) -> None:
        # == ProductionService tickPlayer (dt = 1)
        mps = self.mps()
        cap = self.tank_cap(mps, self.up)
        if self.tank >= cap or mps <= 0:
            return
        add = mps
        mult = self.event.get("rareChanceMultiplier", 1) if self.event else 1
        for rare in sorted(self.E["RareMilk"], key=lambda r: r["chance"]):
            if self.rng.random() < rare["chance"] * mult:
                add += mps * (rare["multiplier"] - 1)
                break
        self.tank = min(cap, self.tank + add)

    def sell_tick(self) -> None:
        # == DairyService sellTick (dt = 1)
        if self.queue <= 0:
            return
        sold = min(self.queue, self.sell_rate(self.mps(), self.up))
        self.queue -= sold
        if self.queue < 1e-6:
            self.queue = 0.0
        self.dairy_cash += sold * self.cash_mult(self.rebirths)

    def crate_drop_tick(self) -> None:
        # == CrateService rollDrops
        C = self.E["Crate"]
        if self.t % int(C["DropCheckSeconds"]) != 0:
            return
        mult = self.event.get("crateDropMultiplier", 1) if self.event else 1
        per_cow = min(1.0, C["DropChancePerCowPerMinute"] * C["DropCheckSeconds"] / 60 * mult)
        count = sum(self.cows.values())
        chance = 1 - (1 - per_cow) ** count
        if count > 0 and self.world_crates < C["MaxWorldCrates"] and self.rng.random() < chance:
            self.world_crates += 1
            self.crates_dropped += 1

    def auto_collect_tick(self) -> None:
        if self.up["autoCollect"] > 0 and self.t - self.last_auto_fill >= self.auto_interval(self.up):
            self.last_auto_fill = self.t
            self.fill_can()

    # ------------------------------------------------------------------ player movement
    def player_tick(self) -> None:
        auto = self.up["autoCollect"] > 0
        speed = self.walk_speed(self.up)
        if self.state in ("to_dairy", "to_cash", "to_plot"):
            self.timer -= 1
            if self.timer > 0:
                return
            if self.state == "to_dairy":
                self.deposit()
                self.state, self.timer = "to_cash", WALK_DEPOSIT_TO_CASH / speed + PAD_OVERHEAD
                self.cash_wait = 0
            elif self.state == "to_cash":
                self.state = "cash"
            elif self.state == "to_plot":
                self.state = "plot"
            return
        if self.state == "cash":
            self.cash_wait += 1
            if self.queue <= 0 or self.cash_wait >= MAX_CASH_WAIT:
                self.collect()
                if auto:
                    self.state = "camp"
                else:
                    self.state, self.timer = "to_plot", WALK_CASH_TO_TAP / speed + PAD_OVERHEAD
            return
        if self.state == "camp":  # Auto Collect: stand between deposit and cash pad
            self.deposit()
            if self.t % 2 == 0:
                self.collect()
            if self.t - self.last_plot_visit >= AUTO_PLOT_VISIT_EVERY:
                self.collect()
                self.state, self.timer = "to_plot", WALK_CASH_TO_TAP / speed + PAD_OVERHEAD
            return
        if self.state == "plot":
            self.at_plot()
            self.fill_can()
            mps = self.mps()
            trip = self.trip_seconds(self.up)
            want = min(self.can_cap(mps, self.up), mps * trip)
            if auto or self.can >= want * 0.999:
                self.state, self.timer = "to_dairy", WALK_TAP_TO_DEPOSIT / speed + PAD_OVERHEAD
            # else: wait at the tap for more milk

    # ------------------------------------------------------------------ main loop
    def step(self) -> None:
        self.world_tick()
        self.production_tick()
        self.auto_collect_tick()
        self.sell_tick()
        self.crate_drop_tick()
        self.player_tick()
        if self.t % DECIDE_EVERY == 0 and self.state != "plot":
            self.shop(at_plot=False)  # UI purchases: upgrades, crates, rebirth
        self.t += 1

    def trace_line(self) -> str:
        return (
            f"{fmt_time(self.t):>8}  reb {self.rebirths:2d}  best T{self.best_tier():2d}  "
            f"cash {fmt_num(self.cash):>7}  income {fmt_num(self.income()):>7}/s  "
            f"cows {sum(self.cows.values()):4d}  bought {self.cows_bought:3d}  "
            f"ups {','.join(str(self.up[k]) for k in self.U)}  crates bought {self.crates_bought}"
        )


def run(cfg, seeds: int, hours: float, double_cash: bool, events: bool, trace: int) -> Dict[str, Any]:
    total = int(hours * 3600)
    tier_count = len(cfg["Cows"]["tiers"])
    tiers: Dict[int, List[Optional[int]]] = {t: [] for t in range(1, tier_count + 1)}
    rebirths: Dict[int, List[Optional[int]]] = {}
    first_run_tiers: Dict[int, List[Optional[int]]] = {t: [] for t in range(1, tier_count + 1)}
    sims = []
    for seed in range(1, seeds + 1):
        sim = Sim(cfg, seed, double_cash, events)
        for _ in range(total):
            sim.step()
            if trace and seed == 1 and sim.t % trace == 0:
                print(sim.trace_line())
        for t in range(1, tier_count + 1):
            tiers[t].append(sim.discovered.get(t))
            first_run_tiers[t].append(sim.run_best_times[0].get(t))
        for i, rt in enumerate(sim.rebirth_times):
            rebirths.setdefault(i + 1, []).append(rt)
        sims.append(sim)
    for k in rebirths:
        rebirths[k] += [None] * (seeds - len(rebirths[k]))
    return {"tiers": tiers, "first_run": first_run_tiers, "rebirths": rebirths, "sims": sims, "hours": hours}


def summarize(values: List[Optional[int]]) -> str:
    got = sorted(v for v in values if v is not None)
    if not got:
        return f"{'never':>9} {'':>9} {'':>9}   0/{len(values)}"
    med = statistics.median(got) if len(got) * 2 > len(values) else None
    return f"{fmt_time(med):>9} {fmt_time(got[0]):>9} {fmt_time(got[-1]):>9}   {len(got)}/{len(values)}"


TARGETS = {5: "~5m", 10: "45-60m", 18: "multi-day"}


def report(cfg, res) -> None:
    names = {t["tier"]: t["name"] for t in cfg["Cows"]["tiers"]}
    seeds = len(res["sims"])
    print(f"\nPlay time to FIRST discover each tier ({seeds} seeds, {res['hours']:g} h of active play)")
    print(f"{'tier':>4}  {'name':<28} {'median':>9} {'fastest':>9} {'slowest':>9}  reached  target")
    for t, vals in res["tiers"].items():
        print(f"{t:>4}  {names[t]:<28} {summarize(vals)}  {TARGETS.get(t, '')}")
    print("\nPlay time to each rebirth (target: first rebirth 30-45 min)")
    print(f"{'#':>4}  {'cost':<28} {'median':>9} {'fastest':>9} {'slowest':>9}  reached")
    R = cfg["Economy"]["Rebirth"]
    for n, vals in sorted(res["rebirths"].items()):
        cost = math.floor(R["BaseCost"] * R["CostGrowth"] ** (n - 1))
        print(f"{n:>4}  {fmt_num(cost):<28} {summarize(vals)}")
    if not res["rebirths"]:
        print("   (no rebirth reached)")
    s = res["sims"][0]
    print(f"\nSeed 1 at the end: {s.trace_line()}")
    print(f"  cows bought (all runs) {s.cows_bought_total}, crates bought {s.crates_bought}, crates dropped {s.crates_dropped}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hours", type=float, default=72)
    ap.add_argument("--seeds", type=int, default=8)
    ap.add_argument("--set", action="append", default=[], metavar="Path.To.Key=value")
    ap.add_argument("--proposed", action="store_true", help="apply B4's PROPOSED_TUNING first")
    ap.add_argument("--double-cash", action="store_true", help="simulate the 2x Cash gamepass")
    ap.add_argument("--no-events", action="store_true", help="disable timed events (B2)")
    ap.add_argument("--trace", type=int, default=0, metavar="SECONDS", help="print seed 1 state every N s")
    ap.add_argument("--config", type=Path, default=CONFIG_DIR)
    args = ap.parse_args()

    cfg = load_all(args.config)
    if args.proposed:
        args.set = PROPOSED_TUNING + args.set
    for spec in args.set:
        apply_override(cfg, spec)
    if args.set:
        print("Overrides:", ", ".join(args.set))
    res = run(cfg, args.seeds, args.hours, args.double_cash, not args.no_events, args.trace)
    report(cfg, res)


if __name__ == "__main__":
    main()
