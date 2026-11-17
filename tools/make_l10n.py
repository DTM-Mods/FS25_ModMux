"""Writes translations/l10n_en.xml and l10n_de.xml from the table below (one row per text, both languages side by side,
so they never drift apart). Texts formatted with values use %s / %d / %.1f; a literal percent sign in those is %%.
Usage: python -I tools/make_l10n.py"""
import pathlib
from xml.sax.saxutils import quoteattr

project = pathlib.Path(__file__).resolve().parent.parent

T = [
    # page
    ("mm_menuTitle", "ModMux Switchboard", "ModMux Schaltzentrale"),
    ("mm_tab_conflicts", "CONFLICTS", "KONFLIKTE"),
    ("mm_tab_live", "LIVE", "LIVE"),
    ("mm_tab_vehicle", "VEHICLE", "FAHRZEUG"),
    ("mm_tab_performance", "PERFORMANCE", "LEISTUNG"),
    ("mm_tab_review", "REVIEW", "PRÜFEN"),
    ("mm_tab_profiles", "PROFILES", "PROFILE"),
    ("mm_view_simple", "SIMPLE", "EINFACH"),
    ("mm_view_category", "BY CATEGORY", "NACH BEREICH"),
    ("mm_view_advanced", "ADVANCED", "ERWEITERT"),
    ("mm_button_save", "Save", "Speichern"),
    ("mm_on", "On", "An"),
    ("mm_off", "Off", "Aus"),
    ("mm_owner_game", "Game", "Spiel"),
    ("mm_owner_unknown", "an unknown script", "ein unbekanntes Skript"),

    # columns
    ("mm_col_mod", "Mod", "Mod"),
    ("mm_col_mods", "Mods", "Mods"),
    ("mm_col_fights", "Fights with", "Konflikt mit"),
    ("mm_col_conflicts", "Conflicts", "Konflikte"),
    ("mm_col_status", "Status", "Status"),
    ("mm_col_category", "Category", "Bereich"),
    ("mm_col_function", "Function", "Funktion"),
    ("mm_col_kind", "Kind", "Art"),
    ("mm_col_decision", "Decision", "Entscheidung"),
    ("mm_col_setting", "Setting", "Einstellung"),
    ("mm_col_value", "Value", "Wert"),
    ("mm_col_reading", "Reading", "Messwert"),
    ("mm_col_perFrame", "Per frame", "Pro Bild"),
    ("mm_col_budget", "Of budget", "Vom Budget"),
    ("mm_col_finding", "Finding", "Befund"),
    ("mm_col_profile", "Profile", "Profil"),
    ("mm_col_saved", "Saved", "Gespeichert"),
    ("mm_col_contents", "Contents", "Inhalt"),

    # cells and statuses
    ("mm_cell_opponents", "%d mod(s)", "%d Mod(s)"),
    ("mm_cell_conflicts", "%d (%d serious)", "%d (%d schwer)"),
    ("mm_cell_profile", "%d picks, %d ranked, %d parked", "%d Wahl, %d gereiht, %d geparkt"),
    ("mm_status_ranked", "Ranked", "Gereiht"),
    ("mm_status_loadOrder", "Load order", "Ladereihenfolge"),
    ("mm_status_pending", "Next load", "Nächster Start"),
    ("mm_status_next", "Next: %s", "Danach: %s"),
    ("mm_status_instant", "Instant", "Sofort"),
    ("mm_status_parked", "Parked", "Geparkt"),
    ("mm_status_parksNext", "Parks next load", "Parkt beim nächsten Start"),
    ("mm_status_unparksNext", "Runs next load", "Läuft beim nächsten Start"),
    ("mm_status_dismissed", "Dismissed", "Ausgeblendet"),
    ("mm_status_current", "Current", "Aktuell"),
    ("mm_level_good", "OK", "OK"),
    ("mm_level_warn", "Watch", "Beobachten"),
    ("mm_level_bad", "High", "Hoch"),

    # conflict kinds and categories
    ("mm_kind_lost", "Lost", "Verloren"),
    ("mm_kind_replaced", "May skip", "Evtl. übergangen"),
    ("mm_kind_overwrite", "May block", "Evtl. blockiert"),
    ("mm_kind_shared", "Shared", "Geteilt"),
    ("mm_kind_types", "Types", "Typen"),
    ("mm_cat_wheels", "Wheels", "Räder"),
    ("mm_cat_hud", "HUD and menus", "HUD und Menüs"),
    ("mm_cat_economy", "Economy", "Wirtschaft"),
    ("mm_cat_weather", "Weather and time", "Wetter und Zeit"),
    ("mm_cat_ai", "AI and helpers", "KI und Helfer"),
    ("mm_cat_animals", "Animals", "Tiere"),
    ("mm_cat_fields", "Fields and crops", "Felder und Früchte"),
    ("mm_cat_production", "Productions and storage", "Produktionen und Lager"),
    ("mm_cat_placeables", "Buildings", "Gebäude"),
    ("mm_cat_player", "Player", "Spieler"),
    ("mm_cat_vehicles", "Vehicles", "Fahrzeuge"),
    ("mm_cat_input", "Controls", "Steuerung"),
    ("mm_cat_network", "Multiplayer", "Mehrspieler"),
    ("mm_cat_other", "Other", "Sonstiges"),
    ("mm_types_title_vehicle", "Vehicle types: %s", "Fahrzeugtypen: %s"),
    ("mm_types_title_placeable", "Building types: %s", "Gebäudetypen: %s"),

    # decisions
    ("mm_plan_default", "Load order", "Ladereihenfolge"),
    ("mm_plan_winner", "%s wins", "%s gewinnt"),
    ("mm_plan_shared", "Shared chain", "Gemeinsame Kette"),
    ("mm_plan_rank", "Ranked", "Nach Rang"),
    ("mm_plan_category", "Ranked in %s", "Nach Rang in %s"),
    ("mm_plan_locked", "Locked", "Gesperrt"),
    ("mm_plan_types", "Read only", "Nur Anzeige"),
    ("mm_build_ok", "done", "erledigt"),
    ("mm_build_partial", "partly: some changes sit inside another mod's version and stay",
     "teilweise: einige Änderungen stecken in der Version eines anderen Mods und bleiben"),
    ("mm_build_same", "nothing to change", "nichts zu ändern"),
    ("mm_build_noBase", "not possible: the game's original of this function is unknown",
     "nicht möglich: das Original des Spiels ist für diese Funktion unbekannt"),
    ("mm_build_unsafe", "not possible: this chain is only partly readable, left alone to be safe",
     "nicht möglich: diese Kette ist nur teilweise lesbar, zur Sicherheit unverändert"),
    ("mm_build_failed", "not possible", "nicht möglich"),
    ("mm_build_none", "as loaded", "wie geladen"),

    # chain
    ("mm_chain_head", "How it runs now (outermost first, it has the last word):",
     "So läuft es jetzt (äußerste zuerst, sie hat das letzte Wort):"),
    ("mm_layer_append", "adds its code after the rest", "hängt seinen Code hinter den Rest"),
    ("mm_layer_prepend", "adds its code before the rest", "setzt seinen Code vor den Rest"),
    ("mm_layer_overwrite", "wraps the rest and decides whether it runs", "umschließt den Rest und entscheidet, ob er läuft"),
    ("mm_layer_replace", "put in its own version of the function", "hat eine eigene Version der Funktion eingesetzt"),
    ("mm_layer_floor", "the game's original", "das Original des Spiels"),
    ("mm_layer_hidden", "INSIDE IT, NOT KNOWN YET: %s (%s)", "DARIN, NOCH UNBEKANNT: %s (%s)"),
    ("mm_layer_hiddenRuns", "inside it, still runs: %s (%s)", "darin, läuft noch: %s (%s)"),
    ("mm_layer_lost", "NOT RUNNING: %s (%s)", "LÄUFT NICHT: %s (%s)"),

    # explanations
    ("mm_ex_lost", "%s changed this function, but %s replaced it afterwards without passing that change on, so the change from %s never runs.",
     "%s hat diese Funktion geändert, aber %s hat sie danach ersetzt, ohne diese Änderung weiterzugeben. Die Änderung von %s läuft nie."),
    ("mm_ex_lostLikely", "%s changed this function, then %s put in its own version and the change is gone (ModMux saw the change made, "
     "not removed). The change from %s most likely never runs.",
     "%s hat diese Funktion geändert, dann hat %s eine eigene Version eingesetzt und die Änderung ist weg (ModMux hat die Änderung "
     "gesehen, nicht das Entfernen). Die Änderung von %s läuft sehr wahrscheinlich nie."),
    ("mm_ex_lostFix", "Pick a winner, or turn on the shared chain so both changes run (the lost one goes back on top).",
     "Wähle einen Gewinner oder schalte die gemeinsame Kette ein, damit beide Änderungen laufen (die verlorene kommt oben wieder drauf)."),
    ("mm_ex_replaced", "%s put in its own version of this function. The changes below it from %s only run if that version "
     "passes them on.",
     "%s hat eine eigene Version dieser Funktion eingesetzt. Die Änderungen darunter von %s laufen nur, wenn diese Version sie "
     "weitergibt."),
    ("mm_ex_replacedWatch", "ModMux finds out while you play: once the function has run a few times, this shows whether they still run.",
     "ModMux findet es beim Spielen heraus: sobald die Funktion ein paar Mal gelaufen ist, steht hier, ob sie noch laufen."),
    ("mm_ex_hiddenRuns", "Seen while playing: the change from %s still runs.",
     "Beim Spielen gesehen: die Änderung von %s läuft noch."),
    ("mm_ex_lostSeen", "%s changed this function, then %s put in its own version that doesn't pass the change on: the function ran "
     "%d times since loading, the change from %s not once.",
     "%s hat diese Funktion geändert, dann hat %s eine eigene Version eingesetzt, die die Änderung nicht weitergibt: die Funktion "
     "lief seit dem Laden %d Mal, die Änderung von %s kein einziges Mal."),
    ("mm_ex_lostEarlier", "%s changed this function, then %s put in its own version that doesn't pass the change on (seen on an "
     "earlier load). The change from %s doesn't run.",
     "%s hat diese Funktion geändert, dann hat %s eine eigene Version eingesetzt, die die Änderung nicht weitergibt (bei einem "
     "früheren Start gesehen). Die Änderung von %s läuft nicht."),
    ("mm_ex_overwrite", "%s wraps this function and decides whether the rest runs. If it skips the original, the changes below it (%s) don't run.",
     "%s umschließt diese Funktion und entscheidet, ob der Rest läuft. Lässt es das Original aus, laufen die Änderungen darunter (%s) nicht."),
    ("mm_ex_blockFix", "If something of the inner mod doesn't work, pick it as winner or raise it in the ranking.",
     "Wenn etwas vom inneren Mod nicht funktioniert, wähle ihn als Gewinner oder setze ihn im Rang nach oben."),
    ("mm_ex_shared", "Every change runs, in this order: %s. The last one has the last word.",
     "Jede Änderung läuft, in dieser Reihenfolge: %s. Die letzte hat das letzte Wort."),
    ("mm_ex_sharedFix", "Usually fine. If two mods set the same value, the later one wins: change the order with the ranking.",
     "Meist in Ordnung. Setzen zwei Mods denselben Wert, gewinnt der spätere: ändere die Reihenfolge über den Rang."),
    ("mm_ex_types", "In %d type(s), %s each change %s. The game chains them itself: each one gets the previous one and decides whether it runs.",
     "In %d Typ(en) ändern %s jeweils %s. Das Spiel verkettet sie selbst: jede bekommt die vorige und entscheidet, ob sie läuft."),
    ("mm_ex_typesOrder", "Order (first decides): %s", "Reihenfolge (erste entscheidet): %s"),
    ("mm_ex_typesList", "Types: %s", "Typen: %s"),
    ("mm_ex_typesReadOnly", "Shown for information. The game builds these chains per vehicle, ModMux doesn't change them.",
     "Nur zur Information. Das Spiel baut diese Ketten pro Fahrzeug, ModMux ändert sie nicht."),
    ("mm_ex_locked_core", "Locked: this belongs to the game's core (loading, menus, the mod system). ModMux never changes it.",
     "Gesperrt: das gehört zum Kern des Spiels (Laden, Menüs, Modsystem). ModMux ändert es nie."),
    ("mm_ex_locked_load", "Locked: this runs while loading. Changing it could stop the game from loading, so ModMux never does.",
     "Gesperrt: das läuft beim Laden. Eine Änderung könnte das Laden verhindern, deshalb macht ModMux das nie."),
    ("mm_ex_locked_save", "Locked: this saves your game. Changing it could lose data, so ModMux never does.",
     "Gesperrt: das speichert dein Spiel. Eine Änderung könnte Daten kosten, deshalb macht ModMux das nie."),
    ("mm_ex_locked_network", "Locked: this keeps multiplayer in sync. Changing it on one side only would break that, so ModMux never does.",
     "Gesperrt: das hält den Mehrspieler synchron. Eine Änderung nur auf einer Seite würde das brechen, deshalb macht ModMux das nie."),
    ("mm_ex_thisLoad", "This load: %s (%s)", "Dieser Start: %s (%s)"),
    ("mm_ex_nextLoad", "Next load: %s", "Nächster Start: %s"),
    ("mm_ex_category", "Category: %s", "Bereich: %s"),

    # SIMPLE / BY CATEGORY
    ("mm_simple_rankLine", "Rank #%d", "Rang #%d"),
    ("mm_simple_unranked", "Not ranked: follows the load order.", "Ohne Rang: folgt der Ladereihenfolge."),
    ("mm_simple_help", "Raise a mod to make it win its fights: its changes run last and get the last word. Ranked mods beat "
     "unranked ones. Applies on the next load.",
     "Setze einen Mod nach oben, damit er seine Konflikte gewinnt: seine Änderungen laufen zuletzt und haben das letzte Wort. "
     "Gereihte Mods schlagen ungereihte. Gilt ab dem nächsten Start."),
    ("mm_category_help", "This ranking only counts in %s and comes before the overall one.",
     "Dieser Rang gilt nur in %s und geht dem allgemeinen vor."),
    ("mm_simple_fightsHead", "Its conflicts:", "Seine Konflikte:"),
    ("mm_simple_fight", "%s with %s (%s)", "%s mit %s (%s)"),

    # actions
    ("mm_act_view", "View: %s", "Ansicht: %s"),
    ("mm_act_raise", "Raise", "Hoch"),
    ("mm_act_lower", "Lower", "Runter"),
    ("mm_act_resetRank", "Reset ranking", "Rang zurücksetzen"),
    ("mm_act_resetCategory", "Reset category", "Bereich zurücksetzen"),
    ("mm_act_winnerNext", "Winner: %s", "Gewinner: %s"),
    ("mm_act_winnerNone", "Winner: none", "Gewinner: keiner"),
    ("mm_act_sharedOn", "Shared chain", "Gemeinsame Kette"),
    ("mm_act_sharedOff", "Shared chain off", "Gemeinsame Kette aus"),
    ("mm_act_resetPick", "Load order", "Ladereihenfolge"),
    ("mm_act_resume", "Levers back on", "Hebel wieder an"),
    ("mm_act_suspend", "All levers off", "Alle Hebel aus"),
    ("mm_act_toggle", "Switch", "Umschalten"),
    ("mm_act_increase", "More", "Mehr"),
    ("mm_act_decrease", "Less", "Weniger"),
    ("mm_act_park", "Park", "Parken"),
    ("mm_act_unpark", "Unpark", "Entparken"),
    ("mm_act_resetStats", "Reset numbers", "Werte zurücksetzen"),
    ("mm_act_probesOn", "Timers on", "Zeitmessung an"),
    ("mm_act_probesOff", "Timers off", "Zeitmessung aus"),
    ("mm_act_dismiss", "Dismiss", "Ausblenden"),
    ("mm_act_restore", "Restore", "Wieder zeigen"),
    ("mm_act_showDismissed", "Show dismissed", "Ausgeblendete zeigen"),
    ("mm_act_hideDismissed", "Hide dismissed", "Ausgeblendete verbergen"),
    ("mm_act_hudScan", "Scan HUD", "HUD prüfen"),
    ("mm_act_loadProfile", "Load", "Laden"),
    ("mm_act_saveProfile", "Save as new", "Neu speichern"),
    ("mm_act_overwriteProfile", "Overwrite", "Überschreiben"),
    ("mm_act_deleteProfile", "Delete", "Löschen"),

    # dialogs
    ("mm_confirm_resetRank", "Remove every mod from the ranking? The load order decides again from the next load.",
     "Alle Mods aus dem Rang nehmen? Ab dem nächsten Start entscheidet wieder die Ladereihenfolge."),
    ("mm_confirm_resume", "Turn ModMux's levers back on? Your picks, rankings and parked mods apply again from the next load.",
     "ModMux-Hebel wieder einschalten? Deine Wahl, Ränge und geparkten Mods gelten ab dem nächsten Start wieder."),
    ("mm_confirm_suspend", "Turn every lever off? From the next load ModMux only watches and changes nothing. Your setup is kept.",
     "Alle Hebel ausschalten? Ab dem nächsten Start beobachtet ModMux nur und ändert nichts. Deine Einstellungen bleiben."),
    ("mm_confirm_loadProfile", "Load the profile '%s'? It replaces your current picks, rankings and parked mods (from the next load); "
     "live settings change at once.",
     "Profil '%s' laden? Es ersetzt deine Wahl, Ränge und geparkten Mods (ab dem nächsten Start); Live-Einstellungen ändern sich sofort."),
    ("mm_confirm_overwriteProfile", "Save the current setup into '%s'?", "Aktuelle Einstellungen in '%s' speichern?"),
    ("mm_confirm_deleteProfile", "Delete the profile '%s'?", "Profil '%s' löschen?"),
    ("mm_ask_profileName", "Profile name", "Profilname"),
    ("mm_profile_defaultName", "Profile %d", "Profil %d"),
    ("mm_info_hudScan", "Close the menu and play on: for about 5 seconds ModMux notes where each mod draws. "
     "The result shows up here in REVIEW.",
     "Schließe das Menü und spiele weiter: etwa 5 Sekunden lang notiert ModMux, wo jeder Mod zeichnet. "
     "Das Ergebnis erscheint hier unter PRÜFEN."),

    # sub headers, footers, empty lists
    ("mm_sub_conflicts", "View: %s  |  %d conflicts: %d lost, %d may block, %d shared",
     "Ansicht: %s  |  %d Konflikte: %d verloren, %d evtl. blockiert, %d geteilt"),
    ("mm_sub_early", "  |  %d mod(s) loaded before ModMux, not watched", "  |  %d Mod(s) vor ModMux geladen, nicht beobachtet"),
    ("mm_sub_live", "%d settings, applied at once", "%d Einstellungen, gelten sofort"),
    ("mm_sub_vehicle", "The vehicle you sit in, updated twice a second", "Das Fahrzeug, in dem du sitzt, zweimal pro Sekunde aktualisiert"),
    ("mm_sub_perf", "Frame %.1f ms (%d fps)  |  mods %.2f ms  |  budget %d fps = %.1f ms",
     "Bild %.1f ms (%d fps)  |  Mods %.2f ms  |  Budget %d fps = %.1f ms"),
    ("mm_sub_review_never", "HUD overlap scan: not run yet (runs a minute into play, or press Scan HUD)",
     "HUD-Überlappung: noch nicht geprüft (läuft nach einer Minute Spiel, oder HUD prüfen drücken)"),
    ("mm_sub_review_running", "HUD overlap scan: running, close the menu for a few seconds",
     "HUD-Überlappung: läuft, schließe das Menü für ein paar Sekunden"),
    ("mm_sub_review_done", "HUD overlap scan: done", "HUD-Überlappung: geprüft"),
    ("mm_sub_profiles", "%d profiles", "%d Profile"),
    ("mm_footer_ok", "Picks, rankings and parking apply on the next load. Nothing is waiting.",
     "Wahl, Ränge und Parken gelten ab dem nächsten Start. Nichts wartet."),
    ("mm_footer_pending", "%d change(s) wait for the next load. Save and restart the game to apply them.",
     "%d Änderung(en) warten auf den nächsten Start. Speichern und das Spiel neu starten, um sie anzuwenden."),
    ("mm_footer_safe_killSwitch", "SAFE MODE: MODMUX_SAFE_MODE.txt is in modSettings/FS25_ModMux. Every lever is off; delete the file "
     "to turn them back on.",
     "SICHERER MODUS: MODMUX_SAFE_MODE.txt liegt in modSettings/FS25_ModMux. Alle Hebel sind aus; lösche die Datei, um sie wieder "
     "einzuschalten."),
    ("mm_footer_safe_lastLaunch", "SAFE MODE: the last start didn't finish, so every lever is off. Turn them back on when you're ready.",
     "SICHERER MODUS: der letzte Start wurde nicht fertig, deshalb sind alle Hebel aus. Schalte sie wieder ein, wenn du bereit bist."),
    ("mm_footer_safe_abnormal", "SAFE MODE: the last load came up without its farms, so every lever is off.",
     "SICHERER MODUS: der letzte Start kam ohne seine Höfe hoch, deshalb sind alle Hebel aus."),
    ("mm_footer_safe_suspended", "Levers are off: ModMux only watches. Turn them back on with the button.",
     "Hebel sind aus: ModMux beobachtet nur. Schalte sie mit der Taste wieder ein."),
    ("mm_footer_safeResumed", "Levers are off for this load and come back on with the next one.",
     "Die Hebel sind für diesen Start aus und ab dem nächsten wieder an."),
    ("mm_empty_conflicts", "No conflicts: no two mods change the same function.",
     "Keine Konflikte: keine zwei Mods ändern dieselbe Funktion."),
    ("mm_empty_noOwners", "ModMux can't tell which mod a function comes from in this game version, so it can't find conflicts. "
     "The details are in modSettings/FS25_ModMux/ModMux.log.",
     "ModMux kann in dieser Spielversion nicht erkennen, von welchem Mod eine Funktion stammt, und findet deshalb keine Konflikte. "
     "Einzelheiten stehen in modSettings/FS25_ModMux/ModMux.log."),
    ("mm_empty_conflictsEarly", "No conflicts among the mods ModMux watched. %d mod(s) loaded before it and can't be watched: "
     "keep the zip named %s so it loads first.",
     "Keine Konflikte bei den Mods, die ModMux beobachtet hat. %d Mod(s) wurden davor geladen und können nicht beobachtet werden: "
     "lass die Zip-Datei %s heißen, damit sie zuerst lädt."),
    ("mm_empty_live", "No live settings.", "Keine Live-Einstellungen."),
    ("mm_empty_vehicle", "Get into a vehicle to see its numbers.", "Steig in ein Fahrzeug, um seine Werte zu sehen."),
    ("mm_empty_perf", "Measuring... numbers show after a few frames.", "Messe... die Werte erscheinen nach ein paar Bildern."),
    ("mm_empty_perfOff", "Timers are off (safe mode or switched off). Turn them on: applies on the next load.",
     "Zeitmessung ist aus (sicherer Modus oder abgeschaltet). Schalte sie ein: gilt ab dem nächsten Start."),
    ("mm_empty_review", "Nothing to review.", "Nichts zu prüfen."),
    ("mm_empty_profiles", "No profiles yet. Save the current setup as a new profile.",
     "Noch keine Profile. Speichere die aktuellen Einstellungen als neues Profil."),

    # LIVE
    ("mm_live_from", "From: %s", "Von: %s"),
    ("mm_live_range", "From %s to %s in steps of %s", "Von %s bis %s in Schritten von %s"),
    ("mm_live_help", "Changes apply at once. ModMux remembers the value and gives it back next time.",
     "Änderungen gelten sofort. ModMux merkt sich den Wert und setzt ihn beim nächsten Mal wieder."),
    ("mm_live_warn", "Warning on screen at start", "Warnung beim Start anzeigen"),
    ("mm_live_warn_desc", "A message a few seconds into play when mods are flatly incompatible or switch each other's changes off.",
     "Eine Meldung kurz nach Spielbeginn, wenn Mods unvereinbar sind oder sich gegenseitig Änderungen abschalten."),
    ("mm_live_budget", "Frame budget", "Bild-Budget"),
    ("mm_live_budget_desc", "The frame rate you aim for. PERFORMANCE shows each mod's cost as a share of one frame at this rate.",
     "Die Bildrate, die du anstrebst. LEISTUNG zeigt die Kosten jedes Mods als Anteil eines Bildes bei dieser Rate."),
    ("mm_live_hudScan", "HUD overlap scan a minute into play", "HUD-Prüfung nach einer Minute Spiel"),
    ("mm_live_hudScan_desc", "Notes for a few seconds where each mod draws on screen and reports mods drawing over each other.",
     "Notiert ein paar Sekunden lang, wo jeder Mod zeichnet, und meldet Mods, die übereinander zeichnen."),

    # VEHICLE
    ("mm_veh_name", "Vehicle", "Fahrzeug"),
    ("mm_veh_type", "Type: %s", "Typ: %s"),
    ("mm_veh_speed", "Speed", "Geschwindigkeit"),
    ("mm_veh_mass", "Total mass", "Gesamtmasse"),
    ("mm_veh_damage", "Damage", "Schaden"),
    ("mm_veh_wear", "Wear", "Abnutzung"),
    ("mm_veh_temp", "Engine temperature", "Motortemperatur"),
    ("mm_veh_motor", "Engine", "Motor"),
    ("mm_veh_running", "Running, %s rpm", "Läuft, %s Drehzahl"),
    ("mm_veh_hours", "Operating hours", "Betriebsstunden"),
    ("mm_veh_wheel", "Wheel %d", "Rad %d"),
    ("mm_veh_wheelValue", "%s, grip %s, slip %s", "%s, Haftung %s, Schlupf %s"),
    ("mm_veh_wheelHelp", "Grip is the tyre's friction on what it stands on (1.00 = the game's normal). Slip is how much the wheel "
     "spins faster than the vehicle moves.",
     "Haftung ist die Reibung des Reifens auf dem Untergrund (1,00 = normal im Spiel). Schlupf ist, wie viel sich das Rad schneller "
     "dreht als das Fahrzeug fährt."),
    ("mm_veh_contact_none", "in the air", "in der Luft"),
    ("mm_veh_contact_ground", "on the ground", "am Boden"),
    ("mm_veh_contact_object", "on an object", "auf einem Objekt"),
    ("mm_veh_mods", "Mods in this vehicle", "Mods in diesem Fahrzeug"),
    ("mm_veh_noMods", "Only the game's own parts.", "Nur Teile des Spiels."),
    ("mm_veh_fights", "Conflicts in this vehicle type", "Konflikte in diesem Fahrzeugtyp"),
    ("mm_veh_noFights", "No two mods change the same function of this vehicle type.",
     "Keine zwei Mods ändern dieselbe Funktion dieses Fahrzeugtyps."),
    ("mm_veh_live", "Live value, read from the vehicle.", "Live-Wert, aus dem Fahrzeug gelesen."),

    # PERFORMANCE
    ("mm_perf_avg", "Average %.2f ms per frame, peak %.2f ms", "Durchschnitt %.2f ms pro Bild, Spitze %.2f ms"),
    ("mm_perf_share", "%.1f %% of one frame at %d fps", "%.1f %% eines Bildes bei %d fps"),
    ("mm_perf_functions", "%d functions timed (%d event listeners)", "%d Funktionen gemessen (%d Ereignis-Listener)"),
    ("mm_perf_parkHelp", "Parking stops this mod's own per-frame work (its update and draw) from the next load, without "
     "uninstalling it. Its vehicles and buildings keep working; its HUD, timers and automation stop.",
     "Parken stoppt ab dem nächsten Start die Arbeit dieses Mods pro Bild (update und draw), ohne ihn zu deinstallieren. Seine "
     "Fahrzeuge und Gebäude funktionieren weiter; sein HUD, seine Timer und Automatik stoppen."),
    ("mm_perf_cantPark", "This mod has no event listener ModMux could park.",
     "Dieser Mod hat keinen Ereignis-Listener, den ModMux parken könnte."),

    # REVIEW
    ("mm_revkind_duplicate", "Duplicate?", "Doppelt?"),
    ("mm_revkind_incompatible", "Incompatible", "Unvereinbar"),
    ("mm_revkind_hard", "Switched off", "Abgeschaltet"),
    ("mm_revkind_hud", "HUD overlap", "HUD-Überlappung"),
    ("mm_rev_duplicate", "Possible duplicate: %s", "Möglicherweise doppelt: %s"),
    ("mm_rev_incompatible", "Known incompatible: %s and %s", "Bekannt unvereinbar: %s und %s"),
    ("mm_rev_hard", "%s switches off changes of %s", "%s schaltet Änderungen von %s ab"),
    ("mm_rev_hud", "HUD overlap: %s and %s", "HUD-Überlappung: %s und %s"),
    ("mm_rev_help_duplicate", "Two copies of one mod can fight each other. Keep the newer one and remove the other from your mods folder.",
     "Zwei Kopien eines Mods können sich in die Quere kommen. Behalte die neuere und entferne die andere aus dem Mod-Ordner."),
    ("mm_rev_help_incompatible", "These two are known not to work together. Use one of them.",
     "Diese beiden funktionieren bekannt nicht zusammen. Nutze nur einen davon."),
    ("mm_rev_help_hard", "See CONFLICTS (ADVANCED) for each function: pick a winner or turn on the shared chain.",
     "Siehe KONFLIKTE (ERWEITERT) für jede Funktion: wähle einen Gewinner oder schalte die gemeinsame Kette ein."),
    ("mm_rev_help_hud", "Both draw on the same part of the screen. Move one of them in its own settings, or park one.",
     "Beide zeichnen auf denselben Teil des Bildschirms. Verschiebe einen in seinen Einstellungen oder parke einen."),
    ("mm_ev_modLine", "%s: %s, version %s, by %s", "%s: %s, Version %s, von %s"),
    ("mm_ev_dupReason_name", "Same file name apart from a copy or version suffix.", "Gleicher Dateiname bis auf einen Kopie- oder Versionszusatz."),
    ("mm_ev_dupReason_title", "Same title.", "Gleicher Titel."),
    ("mm_ev_dupReason_hash", "Identical files (same hash).", "Identische Dateien (gleicher Hash)."),
    ("mm_ev_knownPair", "Listed in ModMux's list of known incompatible mods.", "Steht in ModMux' Liste bekannt unvereinbarer Mods."),
    ("mm_ev_hardCount", "In %d function(s) the change is gone:", "In %d Funktion(en) ist die Änderung weg:"),
    ("mm_ev_more", "... and %d more", "... und %d weitere"),
    ("mm_ev_hudWhere", "Both draw at the %s %s of the screen.", "Beide zeichnen %s %s auf dem Bildschirm."),
    ("mm_ev_hudArea", "Overlap: %s %% of the screen.", "Überlappung: %s %% des Bildschirms."),
    ("mm_pos_top", "top", "oben"),
    ("mm_pos_middle", "middle", "mittig"),
    ("mm_pos_bottom", "bottom", "unten"),
    ("mm_pos_left", "left", "links"),
    ("mm_pos_center", "center", "in der Mitte"),
    ("mm_pos_right", "right", "rechts"),

    # PROFILES
    ("mm_profile_saved", "Saved: %s", "Gespeichert: %s"),
    ("mm_profile_counts", "%d conflict picks, %d ranked mods, %d parked mods, %d live settings",
     "%d Konflikt-Wahlen, %d gereihte Mods, %d geparkte Mods, %d Live-Einstellungen"),
    ("mm_profile_help", "Loading a profile replaces your picks, rankings and parked mods (they apply on the next load); its live "
     "settings change at once.",
     "Ein Profil zu laden ersetzt deine Wahl, Ränge und geparkten Mods (gilt ab dem nächsten Start); seine Live-Einstellungen "
     "ändern sich sofort."),

    # notifications
    ("mm_notify_flat", "ModMux: %d pair(s) of mods don't work together. ESC menu > ModMux > REVIEW.",
     "ModMux: %d Mod-Paar(e) funktionieren nicht zusammen. ESC-Menü > ModMux > PRÜFEN."),
    ("mm_notify_lost", "ModMux: %d mod change(s) are switched off by other mods. ESC menu > ModMux > CONFLICTS.",
     "ModMux: %d Mod-Änderung(en) werden von anderen Mods abgeschaltet. ESC-Menü > ModMux > KONFLIKTE."),
    ("mm_notify_safe_killSwitch", "ModMux safe mode (MODMUX_SAFE_MODE.txt): every lever is off.",
     "ModMux sicherer Modus (MODMUX_SAFE_MODE.txt): alle Hebel sind aus."),
    ("mm_notify_safe_lastLaunch", "ModMux safe mode: the last start didn't finish, so every lever is off. ESC menu > ModMux.",
     "ModMux sicherer Modus: der letzte Start wurde nicht fertig, alle Hebel sind aus. ESC-Menü > ModMux."),
    ("mm_notify_safe_abnormal", "ModMux safe mode: the last load came up without its farms, so every lever is off.",
     "ModMux sicherer Modus: der letzte Start kam ohne Höfe hoch, alle Hebel sind aus."),
    ("mm_notify_abnormal", "ModMux: this savegame loaded without its farms. Saving is blocked so your savegame on disk stays safe. "
     "Quit without saving.",
     "ModMux: dieser Spielstand wurde ohne seine Höfe geladen. Speichern ist gesperrt, damit dein Spielstand sicher bleibt. "
     "Beende ohne zu speichern."),
    ("mm_notify_saveBlocked", "ModMux: not saved. This load came up without its farms; your savegame on disk is untouched.",
     "ModMux: nicht gespeichert. Dieser Start kam ohne Höfe hoch; dein Spielstand ist unverändert."),
]


def write(lang, index):
    keys = [row[0] for row in T]
    assert len(keys) == len(set(keys)), "duplicate key"
    lines = ['<?xml version="1.0" encoding="utf-8" standalone="no"?>',
             '<!-- generated by tools/make_l10n.py: edit the table there, not this file -->', "<l10n>", "    <texts>"]
    for row in T:
        lines.append(f'        <text name="{row[0]}" text={quoteattr(row[index])}/>')
    lines += ["    </texts>", "</l10n>", ""]
    out = project / "translations" / f"l10n_{lang}.xml"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return out


for lang, index in (("en", 1), ("de", 2)):
    print(write(lang, index), len(T), "texts")
