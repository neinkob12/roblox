# Studio setup (Windows, first time ever)

## Path A: tonight's easy way (no Rojo needed)
Claude sends you a file called `BrainrotCowFarm.rbxlx` (the whole game in one file).

1. **Install Studio:** go to https://create.roblox.com, log in, and click **"Start Creating"**. It downloads Roblox Studio. Install it and log in.
2. **Open the game:** double-click `BrainrotCowFarm.rbxlx`, or in Studio use **File > Open from File...** and pick it.
3. **Play-test:** click the big **Play** button (top bar, "Home" tab), or press F5. You spawn in, and your farm gets built by code. Press **Stop** (Shift+F5) to end.
4. **The Output window:** **View > Output**. Errors show up here in red. Screenshot them and send them to Claude. This is how we debug.
5. **Phone test:** **Test tab > Device** (the phone icon). Pick e.g. "iPhone 14 Pro" landscape, then press Play.
6. **New version from Claude:** close the old place, open the new `.rbxlx`. Don't build things by hand in Studio. Everything lives in code, so manual changes get overwritten.

## Publishing (when the core loop works)
1. **File > Publish to Roblox As...** > **Create new experience**. Name it "Brainrot Cow Farm", genre Simulation, and click **Create**.
2. **Turn on saving:** **Home > Game Settings > Security**, and switch on **"Enable Studio Access to API Services"**. Save.
3. **Server size:** Game Settings > **Places** > ... > Configure Place > **Max players: 6**.
4. In the browser at https://create.roblox.com/dashboard/creations, click your game.
   - **Experience Questionnaire** (maturity rating): fill it in honestly. Expect "Minimal" or "Mild".
   - **Places > Thumbnails:** upload the 16:9 gameplay thumbnails (1920x1080) and the trailer video. Video thumbnails may need ID verification.
   - **Icon:** 512x512.
   - **Monetization > Passes / Developer Products:** create them (see `docs/MONETIZATION_SETUP.md`) and send the IDs to Claude.
5. **Make it public:** Dashboard > your game > **Settings > Privacy: Public**. If Roblox asks for age or ID verification, you have to do that yourself.

## Path B: live sync with Rojo (later, nicer)
With live sync, code changes appear in Studio instantly, without reopening files.
1. Install Rokit: in PowerShell, run `Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression`
2. Clone this repo (GitHub Desktop is easiest), open PowerShell in the folder, and run `rokit add rojo-rbx/rojo` and then `rojo plugin install`.
3. Run `rojo serve`. In Studio, go to the **Plugins** tab > **Rojo** > **Connect**.
