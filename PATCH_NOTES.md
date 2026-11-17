<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

# Patch notes

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
- The Switchboard page in the ESC menu: CONFLICTS (SIMPLE / BY CATEGORY / ADVANCED, pick a winner, shared chain,
  rankings), LIVE, VEHICLE, PERFORMANCE (per-mod cost, parking), REVIEW (duplicates, switched-off changes, HUD overlaps,
  listed incompatible pairs) and PROFILES.
- Safe by design: changes apply on the next load, loading / saving / multiplayer sync functions are locked, safe mode
  after a start that didn't finish, a kill switch file, and blocked saves when a savegame loads without its farms.
- Report in `modSettings/FS25_ModMux/ModMux.log`, console commands for dedicated servers, English and German.
