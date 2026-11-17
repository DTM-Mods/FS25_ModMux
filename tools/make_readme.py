"""Writes README.md in the DTM README layout (header, icon, badges, banners and footer taken from FS25_ModReveal's
README, so the template stays identical), with ModMux's own content in between.
Usage: python -I tools/make_readme.py"""
import pathlib
import re

project = pathlib.Path(__file__).resolve().parent.parent
template = (project.parent / "FS25_ModReveal" / "README.md").read_text(encoding="utf-8")

head = template[:template.index('<p align="center">\n  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg"')]
head = head.replace("FS25_ModReveal", "FS25_ModMux").replace("Mod Reveal icon", "ModMux icon")
head = head.replace("<h1 align=\"center\">Mod Reveal</h1>", "<h1 align=\"center\">ModMux</h1>")
head = re.sub(r"<b>.*?</b><br>", "<b>Shows where your mods collide inside the game, and lets you decide who wins.</b><br>", head, count=1)
foot = template[template.index('<p align="center">\n  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/license.jpg"'):]

BODY = '''<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg" alt="Features" width="100%">
</p>

Say one mod makes tyres grip better in mud and another adds a wheel wear system. Both hook into the game's wheel code.
Farming Simulator doesn't referee that: whichever mod is loaded later decides, and depending on how it was written the
other mod's code may never run again. Nothing tells you; you only notice that a feature you installed does nothing.

ModMux reads how every mod has hooked into the game, finds the spots where two or more of them meet, and shows you
what happens at each one. Then you decide.

<p align="center">
  <img src="previews/switchboard_conflicts_advanced.png" alt="Mock-up of the ModMux page: the ADVANCED view lists seven conflicts; the selected one shows that one mod's change to Vehicle.draw no longer runs because another mod replaced the function" width="100%">
  <sub>Mock-up drawn from ModMux's real page data with test mods, not an in-game screenshot. More in <a href="previews/">previews/</a>.</sub>
</p>

### Using it

1. Load your savegame as usual.
2. Open the **ESC menu** and go to the **ModMux** page (its tab shows a switch symbol).
3. On **CONFLICTS**, every spot where mods meet is listed. Select one and the right side explains it: which mods are
   involved, in what order they run, and whether one of them cut another off.
4. Decide what should happen (see below).
5. Save and restart. Your decisions take effect at the next load, never in the middle of a session.

### What you can decide

- **One mod gets its way**: pick a winner for a single function. Only that mod's hook stays; the others are switched
  off there (and only there).
- **Both mods get their way**: when a mod threw another mod's hook away, the shared chain puts it back, so both run.
- **A general pecking order**: rank mods against each other. A higher mod runs last and has the final say wherever it
  meets a lower one. Mods you haven't ranked keep the game's load order.
- **A pecking order per area**: the same, but only for wheels, the HUD, the economy, weather, AI and so on. An area
  ranking overrides the general one.

Three views show the same data at different depths: **SIMPLE** (the ranking), **BY CATEGORY** (the area rankings) and
**ADVANCED** (each function on its own, with the complete chain of hooks).

### The other tabs

| Tab | What it's for |
|---|---|
| LIVE | Switches and values that mods hand to ModMux; changing them takes effect right away. |
| VEHICLE | Readings from the vehicle you're driving: speed, total mass, damage, wear, engine temperature, grip and slip of each wheel, which mods it contains and where they collide in its vehicle type. |
| PERFORMANCE | How many milliseconds each mod takes per frame, compared with the frame rate you aim for. A heavy mod can be parked: its per-frame work stops from the next load, it stays installed. |
| REVIEW | Hints with their reasons: two copies of the same mod, mods that cut each other off, mods whose HUDs sit on top of each other, pairs you've listed as incompatible. Hide a hint once you've dealt with it. |
| PROFILES | Store the current set of decisions, rankings, parked mods and LIVE values under a name, and switch back to it later. |

Each load also writes a plain-text summary to `modSettings/FS25_ModMux/ModMux.log`, and if mods cut each other off you
get a notification shortly after the game starts.

### What if something goes wrong?

- **Can ModMux break my game mid-session?** No. It only rewires things while a savegame loads, based on what you set
  last time.
- **Which functions are off limits?** Anything involved in loading, saving or keeping multiplayer in sync. ModMux shows
  conflicts there but won't touch them.
- **What if the game doesn't start after a change?** ModMux notices that the previous start never finished and starts
  the next one with all of its changes switched off. You turn them back on from the CONFLICTS page when you're ready.
  To force that by hand, put an empty file named `MODMUX_SAFE_MODE.txt` into `modSettings/FS25_ModMux/`.
- **What if a savegame comes up with its farms missing?** Then saving is refused for that session, so the damaged state
  never replaces the savegame on disk, and the following start has all ModMux changes switched off.
- **What does it write, and where?** Only into `modSettings/FS25_ModMux/`: its settings, the profiles, a small start
  marker and the summary file. It never connects to the internet.

### Multiplayer and dedicated servers

Each computer applies its own setup. What the server runs (AI, saving, events) follows the server's setup, set with the
console: `modMux` (the conflicts and their ids), `modMuxPick <id> <mod name|shared|default>`, `modMuxPark <mod name> [off]`,
`modMuxLevers on|off` and `modMuxReport`. All of them take effect at the next start.

### For modders: offer live settings

```lua
-- in your loadMap (ModMux may load after your mod)
if g_modMux ~= nil then
    g_modMux.registerLiveSetting({id = "myMod.showHud", modName = g_currentModName, title = "Show my HUD", kind = "bool",
        get = function() return MyMod.showHud end, set = function(value) MyMod.showHud = value end})
end
```

`kind = "number"` also needs `min`, `max`, `step` (optional `format = "%.1f m"`); `kind = "choice"` needs `choices`
(optional `texts`). `description` is shown in the details panel. ModMux remembers the value set through it and gives it
back the next time the mod registers (`remember = false` turns that off).

'''

DEV = '''<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/installation.jpg" alt="Installation" width="100%">
</p>

Download `FS25_ModMux.zip` from the [latest release](https://github.com/DTM-Mods/FS25_ModMux/releases/latest) and put it in
`Documents/My Games/FarmingSimulator2025/mods`, without unzipping or renaming it. In multiplayer the server and every
player need the same zip.

See [PATCH_NOTES.md](PATCH_NOTES.md) for what changed in each version.

<details>
<summary><b>For developers</b></summary>

How it works: a mod changes a game function with `Utils.appendedFunction` / `prependedFunction` / `overwrittenFunction`
(a wrapper that keeps the old function as an upvalue) or by plainly assigning its own function. ModMux reads those
chains from the outside with `debug.getinfo` (which file, so which mod) and `debug.getupvalue` (the old function inside
a wrapper). It calibrates itself at start by wrapping two dummy functions, so it doesn't depend on the game's code.
From its own load on it records every `Utils.*Function` call, which also catches changes a later mod threw away.

- `scripts/ModMuxOrigin.lua`: which mod a function belongs to.
- `scripts/ModMuxScan.lua`: calibration, the hook recorder, scans of every class (the game's and each mod's), chain
  parsing, lost changes, conflicts, vehicle / placeable type chains, categories.
- `scripts/ModMuxLevers.lua`: locks, plans (winner, shared chain, rank / category order) and rebuilding a chain with the
  game's own Utils helpers.
- `scripts/ModMuxPerf.lua`: per-mod timers, parking, the HUD overlap scan.
- `scripts/ModMuxReview.lua`, `ModMuxLive.lua`, `ModMuxVehicle.lua`, `ModMuxProfiles.lua`: the other tabs' data.
- `scripts/ModMuxTabs.lua`: what each tab shows and what its buttons do (no GUI, tested headless).
- `scripts/gui/ModMuxFrame.lua`, `gui/ModMuxFrame.xml`: the ESC menu page.
- `scripts/ModMux.lua`: settings, safe mode and boot marker, the mod event listener, report, console.
- `config/knownIncompatible.xml`: shipped incompatible pairs (empty: only pairs confirmed in game belong there).
- Generated: `tools/make_l10n.py` (translations), `tools/make_gui.py` (page layout), `tools/make_textures.py`
  (textures; the mod icon from `_brand/tools/make_icons.py <brand> <work> --modhub modMux`), `tools/make_readme.py`.
- Test: `python tests/test_offline.py` runs everything in the game's Lua 5.1 (`pip install lupa`) with a fake game and
  fake mods fighting over functions, through several starts (levers, safe mode, kill switch, abnormal load, every
  Switchboard button).
- Build: `python -I tools/build_zip.py dist/FS25_ModMux.zip`.

</details>

'''

out = project / "README.md"
out.write_text(head + BODY + DEV + foot, encoding="utf-8", newline="\n")
print(out, "written")
