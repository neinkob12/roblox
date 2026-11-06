# Account B: start 4 sessions

**Setup (once):**
1. The GitHub user of account B must be a **collaborator** on `neinkob12/roblox`. On GitHub, go to the repo > Settings > Collaborators > Add people, then accept the invite on the other account.
2. Log in to claude.ai/code with account B, connect GitHub (that user), and make sure the repo is selectable.

**Then:** start 4 new sessions, each on repo `neinkob12/roblox`, and paste one block per session:

---
### Session B1
```
You are a worker session on the Roblox game "Brainrot Cow Farm". Your work package is GitHub issue neinkob12/roblox#6 ([B1] UI / HUD). Read CLAUDE.md, docs/GDD.md, docs/CONTRACTS.md and the issue. Create branch pkg/b1-ui from latest main, work ONLY in the files your package owns, install rojo + stylua via cargo if missing, run `stylua src` and `rojo build -o build/test.rbxlx` before every push. Open a DRAFT PR into main early titled "[B1] UI / HUD" with "Closes #6", keep pushing, mark ready when done with exact Studio test steps. Do not merge; the lead session merges.
```
### Session B2
```
You are a worker session on the Roblox game "Brainrot Cow Farm". Your work package is GitHub issue neinkob12/roblox#7 ([B2] Meta systems). Read CLAUDE.md, docs/GDD.md, docs/CONTRACTS.md and the issue. Create branch pkg/b2-meta from latest main, work ONLY in the files your package owns, install rojo + stylua via cargo if missing, run `stylua src` and `rojo build -o build/test.rbxlx` before every push. Open a DRAFT PR into main early titled "[B2] Meta systems" with "Closes #7", keep pushing, mark ready when done with exact Studio test steps. Do not merge; the lead session merges.
```
### Session B3
```
You are a worker session on the Roblox game "Brainrot Cow Farm". Your work package is GitHub issue neinkob12/roblox#8 ([B3] Monetization). Read CLAUDE.md, docs/GDD.md, docs/CONTRACTS.md and the issue. Create branch pkg/b3-monetization from latest main, work ONLY in the files your package owns, install rojo + stylua via cargo if missing, run `stylua src` and `rojo build -o build/test.rbxlx` before every push. Open a DRAFT PR into main early titled "[B3] Monetization" with "Closes #8", keep pushing, mark ready when done with exact Studio test steps. Do not merge; the lead session merges.
```
### Session B4
```
You are a worker session on the Roblox game "Brainrot Cow Farm". Your work package is GitHub issue neinkob12/roblox#9 ([B4] QA, tooling & marketing). Read CLAUDE.md, docs/GDD.md, docs/CONTRACTS.md and the issue. Create branch pkg/b4-qa-marketing from latest main, work ONLY in the files your package owns, install rojo + stylua via cargo if missing, run `stylua src` and `rojo build -o build/test.rbxlx` before every push. Open a DRAFT PR into main early titled "[B4] QA, tooling & marketing" with "Closes #9", keep pushing, mark ready when done with exact Studio test steps. Do not merge; the lead session merges.
```
