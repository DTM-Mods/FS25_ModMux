# ModHub upload: ModMux

What to enter in the GIANTS ModHub upload form for this mod. Each text box below has a copy button on GitHub.

<img src="icon_512.png" alt="Mod icon" width="160">

**Mod Icon (512x512):** [`icon_512.png`](icon_512.png)

| Field | Value |
|-------|-------|
| Title English | ModMux |
| Title German | ModMux |
| Title French | ModMux |
| Version | `1` `0` `0` `0` |
| Author | DTM Mods, Fennell |
| Manufacturer | Lizard |
| Category 1 | Gameplay |
| Category 2 | Not Set |
| Category 3 | Not Set |

## Title English
```text
ModMux
```

## Title German
```text
ModMux
```

## Title French
```text
ModMux
```

## Description English
```text
Description: Many mods hook into the same parts of the game. When two of them change the same function, Farming Simulator lets the one loaded later decide, and depending on how it was written the other one may stop working without any message. ModMux shows you every place where your mods meet, explains in plain words what happens there, and lets you decide.
Hotkeys: none. ESC menu > ModMux page. The buttons along the bottom of the page follow the selected line.
GitHub: https://github.com/DTM-Mods/FS25_ModMux

Decide per function or for whole mods:
- Let one mod have its way on a function: only its hook stays there.
- Bring back a hook that another mod threw away, so both run (shared chain).
- Rank mods against each other, overall or only for one area (wheels, HUD, economy, weather, AI...). A higher mod runs last and has the final say.
- Three views: SIMPLE (the ranking), BY CATEGORY (area rankings), ADVANCED (each function with its complete chain of hooks).

More tabs:
- LIVE: switches and values that mods hand to ModMux, applied at once.
- VEHICLE: readings from the vehicle you drive: speed, mass, damage, wear, engine temperature, grip and slip per wheel, the mods inside it.
- PERFORMANCE: milliseconds per frame for each mod against your target frame rate. Park a heavy mod's per-frame work without uninstalling it.
- REVIEW: hints with their reasons: two copies of one mod, mods cutting each other off, HUDs drawn on top of each other, pairs you listed as incompatible.
- PROFILES: store your decisions under a name and switch back later.

Safety:
- Decisions take effect when a savegame loads, never during play.
- Loading, saving and multiplayer sync are never touched.
- If a start doesn't finish, the next one runs with all ModMux interventions off. An empty file MODMUX_SAFE_MODE.txt in modSettings/FS25_ModMux does the same by hand.
- If a savegame comes up with its farms missing, saving is refused for that session.
- Writes only into modSettings/FS25_ModMux (settings, profiles, a start marker, the summary ModMux.log). No internet connection.

Console for dedicated servers: modMux, modMuxPick, modMuxPark, modMuxLevers, modMuxReport.
Single player and multiplayer. Every computer uses its own setup; on a server, the server's setup decides what the server runs.
```

## Description German
```text
Beschreibung: Viele Mods greifen in dieselben Teile des Spiels ein. Ändern zwei davon dieselbe Funktion, entscheidet in Farming Simulator der später geladene, und je nach Bauweise arbeitet der andere ohne jede Meldung nicht mehr. ModMux zeigt dir jede Stelle, an der sich deine Mods treffen, erklärt in einfachen Worten, was dort passiert, und lässt dich entscheiden.
Tastenkombinationen: keine. ESC-Menü > Seite ModMux. Die Tasten unten auf der Seite richten sich nach der gewählten Zeile.
GitHub: https://github.com/DTM-Mods/FS25_ModMux

Entscheide pro Funktion oder für ganze Mods:
- Ein Mod setzt sich bei einer Funktion durch: nur sein Eingriff bleibt dort.
- Hole einen Eingriff zurück, den ein anderer Mod verworfen hat, damit beide laufen (gemeinsame Kette).
- Reihe Mods gegeneinander, allgemein oder nur für einen Bereich (Räder, HUD, Wirtschaft, Wetter, KI...). Ein höherer Mod läuft zuletzt und hat das letzte Wort.
- Drei Ansichten: EINFACH (der Rang), NACH BEREICH (Rang je Bereich), ERWEITERT (jede Funktion mit ihrer ganzen Kette).

Weitere Reiter:
- LIVE: Schalter und Werte, die Mods an ModMux geben, gelten sofort.
- FAHRZEUG: Messwerte des Fahrzeugs, das du fährst: Geschwindigkeit, Masse, Schaden, Abnutzung, Motortemperatur, Haftung und Schlupf je Rad, die Mods darin.
- LEISTUNG: Millisekunden pro Bild für jeden Mod, gemessen an deiner Ziel-Bildrate. Parke die Arbeit eines schweren Mods pro Bild, ohne ihn zu deinstallieren.
- PRÜFEN: Hinweise mit Begründung: zwei Kopien eines Mods, Mods, die sich gegenseitig abschneiden, übereinander gezeichnete HUDs, als unvereinbar eingetragene Paare.
- PROFILE: speichere deine Entscheidungen unter einem Namen und wechsle später zurück.

Sicherheit:
- Entscheidungen greifen beim Laden eines Spielstands, nie während des Spiels.
- Laden, Speichern und Mehrspieler-Abgleich werden nie angefasst.
- Wird ein Start nicht fertig, sind beim nächsten alle ModMux-Eingriffe ausgeschaltet. Eine leere Datei MODMUX_SAFE_MODE.txt in modSettings/FS25_ModMux macht das von Hand.
- Kommt ein Spielstand ohne seine Höfe hoch, wird in dieser Sitzung nicht gespeichert.
- Schreibt nur nach modSettings/FS25_ModMux (Einstellungen, Profile, eine Startmarke, die Übersicht ModMux.log). Keine Internetverbindung.

Konsole für dedizierte Server: modMux, modMuxPick, modMuxPark, modMuxLevers, modMuxReport.
Einzel- und Mehrspieler. Jeder Rechner nutzt seine eigenen Einstellungen; auf einem Server entscheiden die des Servers, was der Server ausführt.
```

## Description French
```text
Description : Beaucoup de mods interviennent dans les mêmes parties du jeu. Quand deux d'entre eux modifient la même fonction, Farming Simulator laisse décider celui chargé en dernier, et selon sa conception l'autre peut cesser de fonctionner sans aucun message. ModMux vous montre chaque endroit où vos mods se croisent, explique simplement ce qui s'y passe et vous laisse décider.
Raccourcis : aucun. Menu Échap > page ModMux. Les boutons en bas de la page suivent la ligne sélectionnée.
GitHub: https://github.com/DTM-Mods/FS25_ModMux

Décidez par fonction ou pour des mods entiers :
- Donner raison à un mod sur une fonction : seul son crochet y reste.
- Rétablir un crochet qu'un autre mod a écarté, pour que les deux tournent (chaîne partagée).
- Classer les mods entre eux, globalement ou pour un seul domaine (roues, HUD, économie, météo, IA...). Un mod placé plus haut passe en dernier et a le dernier mot.
- Trois vues : SIMPLE (le classement), BY CATEGORY (classements par domaine), ADVANCED (chaque fonction avec sa chaîne complète).

Autres onglets :
- LIVE : interrupteurs et valeurs que les mods confient à ModMux, appliqués aussitôt.
- VEHICLE : mesures du véhicule que vous conduisez : vitesse, masse, dégâts, usure, température moteur, adhérence et patinage par roue, les mods qu'il contient.
- PERFORMANCE : millisecondes par image pour chaque mod, comparées à votre fréquence d'images visée. Mettez en pause le travail par image d'un mod lourd sans le désinstaller.
- REVIEW : indices avec leurs raisons : deux copies d'un même mod, mods qui se coupent l'un l'autre, HUD dessinés l'un sur l'autre, paires déclarées incompatibles.
- PROFILES : enregistrez vos décisions sous un nom et revenez-y plus tard.

Sécurité :
- Les décisions s'appliquent au chargement d'une partie, jamais pendant le jeu.
- Le chargement, la sauvegarde et la synchronisation multijoueur ne sont jamais touchés.
- Si un démarrage n'aboutit pas, le suivant tourne avec toutes les interventions de ModMux désactivées. Un fichier vide MODMUX_SAFE_MODE.txt dans modSettings/FS25_ModMux fait de même à la main.
- Si une partie se charge sans ses fermes, la sauvegarde est refusée pour cette session.
- N'écrit que dans modSettings/FS25_ModMux (réglages, profils, un marqueur de démarrage, le résumé ModMux.log). Aucune connexion internet.

Console pour serveurs dédiés : modMux, modMuxPick, modMuxPark, modMuxLevers, modMuxReport.
Solo et multijoueur. Chaque ordinateur utilise ses propres réglages ; sur un serveur, ceux du serveur décident de ce qu'il exécute.
```

## Before uploading

- The mod has no French: the in-game texts exist in English and German only, and modDesc.xml has only English and
  German descriptions. The French text here does not add translations to the mod.
- It ships console commands (`modMux`, `modMuxReport`, `modMuxPick`, `modMuxPark`, `modMuxLevers`). They are how a
  dedicated server is set up; your decision whether they stay in a ModHub build.
- It writes files to `modSettings/FS25_ModMux/` (settings, profiles, a start marker, `ModMux.log`). ModHub allows
  modSettings, but say so in the description if GIANTS asks.
- It reads other mods' hooks with Lua's `debug` library and can rebuild them (on the next load, at the player's
  request). Expect GIANTS to look at that closely; the description says what it does.
- NOT tested in game yet (1.0.0.0 passed the offline tests and TestRunner only). Test it in single player and on the
  server before uploading.
- Screenshots: none yet. ModHub needs at least 3 unedited in-game shots at 1600x900, the first without UI. The
  pictures in `../previews/` are mock-ups and must NOT be uploaded.
