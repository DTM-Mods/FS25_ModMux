<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

# Patch notes

## 1.0.0.2

- New first tab **OVERVIEW**: one line per area (mod fights, key clashes, errors, hints, performance, what waits for
  the next load, what ModMux can see), each with a verdict and an **Open** button. The changes waiting for the next
  load are listed in words, with **Undo all**.
- ERRORS shows **one line per mod** (its errors and warnings in the panel); **All messages** lists them one by one.
- KEYS suggests a **free key** for each clash ("Free: Left Alt + G").
- The page is called just **ModMux**.
- Easier to read: WHO BEATS WHOM shows only pairs that need a look (**Show all** lists the rest); every pair gets a
  verdict (**Broken**, **Check**, **Probably fine**, **Fine**) and a suggested fix, which is also the first button;
  functions are named in words ("HUD: draw speed"); every tab shows how many things wait on it ("CONFLICTS (3)");
  an undecided conflict says **Not set** instead of "Load order"; **All levers off** moved to the ADVANCED view.
- CONFLICTS opens on the new **WHO BEATS WHOM** view: one line per pair of mods, saying what the one does to the
  other: **overwrites** (the other's change is gone), **may overwrite** (it put in its own version; whether the other's
  change still runs inside is checked while you play), **takes over** (it wraps the other and decides whether it runs)
  or **runs after / before** (both run). The buttons let either one win (it is ranked above the other, nobody else is
  muted) or let both run. ADVANCED uses the same words.
- New **KEYS** tab: keys and buttons that two mods use, or a mod and the game, in a situation where both can fire
  (on foot, in a vehicle, always), so one press does two things. It reads your own key settings (`inputBinding.xml`),
  each mod's actions and default keys, and the game's action list. Change keys under Settings > Controls.
- New **ERRORS** tab: errors and warnings sorted by mod. ModMux sees what mods write to the log from its own load on,
  and per-frame scripts that stop with a Lua error. Messages only the engine writes (missing textures) stay in
  log.txt. Both lists are also in `ModMux.log`, which is written again when you leave the game.

## 1.0.0.1

- Works in the normal game. The game hides the debug functions from mods, so 1.0.0.0 couldn't tell which mod a function
  came from and always found 0 conflicts. ModMux now reads the environment each mod's functions were written in
  (`getfenv`) and watches every hook as it is made.
- The zip is now **`FS25_0_ModMux.zip`**: the game loads mods in the order of their names, and ModMux has to load before
  the mods it watches. Delete the old `FS25_ModMux.zip`. Settings stay in `modSettings/FS25_ModMux/`. Mods that still
  load before it are named in the log, the report and the CONFLICTS tab.
- A mod that puts in its own version of a function is a closed box. Hooks of other mods under it are now checked while
  you play: once the function has run a few times, ModMux knows whether they still run or are lost. What it saw is kept
  in `modSettings/FS25_ModMux/evidence.xml` for the next loads.

## 1.0.0.0

First version.
- Finds mods that change the same game function and what became of each change, including changes a later mod threw
  away without a trace.
- The ModMux page in the ESC menu: CONFLICTS (SIMPLE / BY CATEGORY / ADVANCED, pick a winner, shared chain,
  rankings), LIVE, VEHICLE, PERFORMANCE (per-mod cost, parking), REVIEW (duplicates, switched-off changes, HUD overlaps,
  listed incompatible pairs) and PROFILES.
- Safe by design: changes apply on the next load, loading / saving / multiplayer sync functions are locked, safe mode
  after a start that didn't finish, a kill switch file, and blocked saves when a savegame loads without its farms.
- Report in `modSettings/FS25_ModMux/ModMux.log`, console commands for dedicated servers, English and German.
