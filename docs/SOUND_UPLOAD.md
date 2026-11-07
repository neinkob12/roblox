# Sound upload guide (C3)

All 40 game sounds are already generated in the repo under `sound/`. Roblox can't play
files straight from the repo, so you upload them once. Then you paste their IDs into
`src/shared/Config/Sounds.luau`. Until you do, the game runs without sound and nothing breaks:
`SoundController` skips any sound whose id is still `rbxassetid://0`.

Time needed: about 15 minutes.

## What gets uploaded

| Folder | Files | What it is |
|---|---|---|
| `sound/music/` | 2 | Farm loop (bouncy mandolin/accordion) and a calm variant, 90 s each |
| `sound/sfx/` | 20 | Moos, milk pipe loop, can fill, splash, cash, coin, buy, merge, crate spin/reveal, rare sparkle, rebirth, upgrade, error, click, truck horn, event fanfare, new cow fanfare |
| `sound/voice/` | 18 | `voice_tier_01` .. `voice_tier_18`: a dramatic shout of each cow's name |

All files are small mp3s (3.4 MB total), well under the Roblox limit of 20 MB and 7 minutes per file.

## Before you start

- **Who owns the game?** Upload the audio with the **same owner** as the experience.
  If the game belongs to a **group**, choose the group as the creator during the upload,
  otherwise the sounds stay silent in the live game.
- Roblox limits how many audio files you can upload per month. The limit is lower for
  accounts that are not ID-verified. If an upload gets refused, upload the rest later.
  Upload order of importance: `sfx` first, then `voice`, then `music`.
- New audio goes through moderation. It can take a few minutes before it plays.

## Step 1: Bulk import in Studio

1. Open the game in Roblox Studio.
2. Top menu: **View** > **Asset Manager**. A panel opens.
3. In the Asset Manager, click the **Bulk Import** button (the icon with an arrow pointing up,
   top of the panel).
4. In the file picker, go to the repo folder `sound/sfx`, press **Ctrl+A** (Mac: **Cmd+A**)
   to select all the `.mp3` files, and click **Open**.
5. Wait for the progress bar. If Studio asks about the creator, choose the game's owner (you or the group).
6. Repeat steps 3 to 5 for `sound/voice` and `sound/music`.
7. In the Asset Manager, open the **Audio** folder. You should see all files listed by their
   file names (for example `sfx_moo_1`). Don't rename them: the next step uses the names.

## Step 2: Collect all the IDs at once

1. In the **Explorer**, right-click **Workspace** > **Insert Object** > **Folder**.
   Rename the folder to `SoundImport`.
2. In the Asset Manager **Audio** folder, click the first file, then **Shift+click** the last
   file to select them all.
3. Drag the selection onto the `SoundImport` folder in the Explorer. Studio creates one
   `Sound` per file inside the folder.
4. Open **View** > **Command Bar** and **View** > **Output**.
5. Paste this line into the Command Bar and press **Enter**:

   ```lua
   for _, s in workspace.SoundImport:GetDescendants() do if s:IsA("Sound") then print(s.Name, (s.SoundId:match("%d+"))) end end
   ```

6. The Output window now shows one line per sound, like `sfx_moo_1 1234567890`.
   Click into the Output, press **Ctrl+A**, then **Ctrl+C**.
7. Delete the `SoundImport` folder (it was only needed for this step).

## Step 3: Paste the IDs into the config

**Option A (fast, needs Python):**

1. Create a file `sound/ids.txt` and paste the Output text into it. Save.
2. In a terminal at the repo root, run:

   ```
   python3 sound/fill_ids.py sound/ids.txt
   ```

   It prints `filled 40 ids` and how many are still 0. Timestamps and other junk in the
   pasted text are fine, it ignores them.
3. Delete `sound/ids.txt`, then commit the changed `src/shared/Config/Sounds.luau`.

**Option B (by hand):**

Open `src/shared/Config/Sounds.luau`. Each entry has a `file = "sound/.../NAME.mp3"`.
Find the line whose file name matches, and replace the `0` in `id = "rbxassetid://0"` with the number.
Voice lines are the list `VOICE_IDS` near the bottom: line `-- 7` is `voice_tier_07`.

## Step 4: Test

1. With Rojo running (`rojo serve`, then Connect in the Rojo plugin), press **Play**.
2. You should hear the farm music within a few seconds.
3. Click any button: soft click. Walk near your stalls: a moo every 6 to 14 seconds.
4. Open **Settings** and turn **Music** off: music stops. Turn it on: it resumes.
   Same for **Sound effects** and **Cow voices**.
5. If something stays silent: check the Output for `Failed to load sound`. That means the
   ID is wrong or the audio belongs to a different owner than the game (see "Before you start").

## Regenerating sounds (developers)

`python3 sound/generate.py` recreates any missing file with the ElevenLabs API
(`--force` to redo everything, `--only Moo1,Voice3` for single sounds). Voice lines are read from
`src/shared/Config/Cows.luau`, so a renamed cow gets a new matching shout. Re-upload the
changed files and run Step 2 and 3 again for them.
