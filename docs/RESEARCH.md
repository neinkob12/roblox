# Research and decisions so far

## Reference game
The user's video shows **Chicken Farm** (Roblox, 2026), not SirMing's 2018 "Egg Farm Simulator".
The lucky block odds match exactly: Bee / Mushroom / Dummy = Biene / Pilz / Puppe.

Core loop seen in the video:
1. Buy pads ("Kaufen 5/25/100") with prices that scale up
2. Chickens in nests lay eggs onto a carpet, and the player walks over them to collect (plus an "auto collect" upgrade)
3. Deposit at a station. The Egg Multiplier swings between 0.5x and 1.5x every 30s.
4. Eggs are sold over time ("2,885 pro Sekunde"), then the player steps on a pad to collect the cash
5. Merge: 3 of a tier become 1 of the next tier
6. Lucky blocks (paid, random chicken)
7. Meta systems: Rebirth, Quests, Index, Obby, Event timer, friend boost, offline earnings
8. Monetization: a permanent 2x Cash gamepass and Robux cash packs
9. Audio: continuous background music, no voice lines

## Our game: Cows and Milk (decisions)
- **Loop:** very close to the reference
- **Production:** cows produce milk that flows through animated **pipes** into a **tank** on the player's plot. The player fills a **milk can** at the tank (HUD icon at bottom center) and carries it to sell.
- **Tanks:** upgradable capacity. When a tank is full, it stops filling.
- **Selling:** a **dairy** with a Milk Price board (0.5x to 1.5x every 30s), **plus** a milk truck that occasionally offers a bonus price
- **Cash:** the dairy sells over time, and the player steps on a collect pad to pick up the money
- **Offline earnings:** yes, capped
- **Processing** (cheese, butter, ice cream): later update
- **Tiers:** 18 cow tiers in brainrot style
- **Merging:** 3 into 1, on a merge pad
- **Rare milk drops:** golden milk (x5) and diamond milk (x10), shown with popups
- **Buying:** buy pads for x1, x5 and x25 with scaling prices
- **Plots:** one barn plot per player
- **Display:** each tier has one stall showing one cow plus an "x47" counter
- **Animation:** simple bob and wiggle, plus a moo
- **Names:** famous brainrot characters are OK, but only ones with **no lawsuit and no offensive audio**. NO Tung Tung Tung Sahur (federal trademark suit) and NO Tralalero Tralala (blasphemous audio). The rest of the list is original brainrot-style names.

## Repos
**Use:**
- rojo-rbx/rojo
- MadStudioRoblox/ProfileStore
- Sleitnick/RbxUtil
- evaera/Cmdr (debug)
- UpliftGames/wally (optional)
- dphfox/Fusion (optional)
- balaboom123/awesome-italian-brainrot (reference only)

**Avoid:** "Best ... 2026" SEO repos and anything with "script executor" or "Steal a Brainrot script". Examples: pogogt12/slime-tycoon-forge, felixscd/Roblox-Project-Foundation, koalesanajlepsze/Steal-a-Brainrot-Script.

## Boundaries
- **Claude** writes all the Luau code, builds the `.rbxlx` with Rojo, makes the Part-built models, and generates audio (ElevenLabs) and images (Canva).
- **The user** opens Studio, playtests, uploads audio and images, creates the gamepasses and dev products, and publishes.
- **Not possible:** using the reference game's assets or name, rigged meshes, trading, and guaranteed players.
