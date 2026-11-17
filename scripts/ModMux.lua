-- ModMux: core. Settings, safe mode, the boot marker, the mod event listener, the report and the console.
-- Sourced last of ModMux's scripts; ModMux.boot() at the bottom starts everything at ModMux's place in the load order.
--
-- When things happen in one load:
--   boot (our scripts load)  recorder on, first scan
--   ModMux:loadMap           second scan (every mod's scripts are loaded by now)
--   ModMuxLate:loadMap       third scan, after every mod's loadMap (registered during the loadMap round, so it comes last)
--   Mission00 finished       last scan, conflicts, then the levers of this load are applied, parking, timers, the page
--   ~10 s of play            the boot marker says "ok" (a load that never gets here starts the next one in safe mode)
--
-- Files, all in modSettings/FS25_ModMux/: settings.xml, profiles.xml, boot.xml, ModMux.log and the player's optional
-- knownIncompatible.xml and MODMUX_SAFE_MODE.txt. Nothing else is written anywhere, nothing goes over the network.

ModMux = {}

ModMux.MOD_NAME = g_currentModName or "FS25_ModMux"
ModMux.MOD_DIR = g_currentModDirectory or ""
ModMux.TAG = "[ModMux]"
ModMux.KILL_FILE = "MODMUX_SAFE_MODE.txt"
ModMux.RECOVERY_MS = 10000
ModMux.WARNING_DELAY_MS = 8000
ModMux.AUTO_HUD_SCAN_MS = 60000
ModMux.HUD_SCAN_FRAMES = 300

ModMux.safeMode = false
ModMux.safeReason = nil            -- killSwitch | lastLaunch | abnormal | suspended
ModMux.killSwitch = false
ModMux.blockSaves = false
ModMux.missionLoaded = false
ModMux.runMs = 0
ModMux.bootState = nil
ModMux.pendingWarning = false
ModMux.autoHudDone = false
ModMux.settingsDir = ""
ModMux.missionReady = false        -- the mission has loaded; ModMux's own work follows on its first update
ModMux.errors = {}                 -- steps of ModMux's own work that stopped with an error (see ModMux.guard)
ModMux.frameBroken = false

local G = ModMuxScan.G

function ModMux.getText(key, ...)
    local text = key
    if g_i18n ~= nil then
        text = g_i18n:getText(key, ModMux.MOD_NAME)
    end
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

--- Runs f(...) so an error in ModMux's own work can never stop the game or the other mods from loading: inside a
-- coroutine when the game has them (the error goes to the log and ModMux carries on without that step), directly
-- otherwise. (GIANTS' TestRunner forbids the usual protected call.)
function ModMux.guard(label, f, ...)
    if coroutine == nil or coroutine.create == nil or coroutine.resume == nil then
        f(...)
        return true
    end
    local co = coroutine.create(f)
    local ok, err = coroutine.resume(co, ...)
    if not ok then
        Logging.error("%s %s stopped with an error, ModMux carries on without it: %s", ModMux.TAG, label, tostring(err))
        if debug ~= nil and debug.traceback ~= nil then
            print(debug.traceback(co))
        end
        table.insert(ModMux.errors, label)
        return false
    end
    return true
end

function ModMux.getDate()
    if getDate ~= nil then
        local value = getDate("%Y-%m-%d %H:%M")
        if type(value) == "string" then
            return value
        end
    end
    return ""
end

function ModMux.getVersion()
    if g_modManager ~= nil and g_modManager.getModByName ~= nil then
        local mod = g_modManager:getModByName(ModMux.MOD_NAME)
        if mod ~= nil and mod.version ~= nil then
            return tostring(mod.version)
        end
    end
    return "?"
end

----------------------------------------------------------------------------------------------------------------
-- Settings and setups
-- A setup = what the levers do: rank (mods, highest first), categoryRank (category -> mods), picks (conflict id ->
-- {mode, mod}), hibernate (parked mods) and live (live setting values). Settings = the current setup + options.
----------------------------------------------------------------------------------------------------------------

function ModMux.defaultSettings()
    return {rank = {}, categoryRank = {}, picks = {}, hibernate = {}, live = {}, dismissed = {},
        options = {warnOnScreen = true, budgetFps = 60, perfProbes = true, hudAutoScan = true, leversSuspended = false}}
end

local function copyList(list)
    local copy = {}
    for i, value in ipairs(list or {}) do
        copy[i] = value
    end
    return copy
end

function ModMux.copySetup(setup)
    local copy = {rank = copyList(setup.rank), categoryRank = {}, picks = {}, hibernate = {}, live = {}}
    for category, list in pairs(setup.categoryRank or {}) do
        copy.categoryRank[category] = copyList(list)
    end
    for id, pick in pairs(setup.picks or {}) do
        copy.picks[id] = {mode = pick.mode, mod = pick.mod}
    end
    for mod, parked in pairs(setup.hibernate or {}) do
        copy.hibernate[mod] = parked
    end
    for id, value in pairs(setup.live or {}) do
        copy.live[id] = value
    end
    return copy
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

--- one string for the structural parts of a setup, to compare two setups
function ModMux.setupKey(setup)
    local parts = {"rank:" .. table.concat(setup.rank or {}, ",")}
    for _, category in ipairs(sortedKeys(setup.categoryRank)) do
        if #setup.categoryRank[category] > 0 then
            table.insert(parts, "cat:" .. category .. "=" .. table.concat(setup.categoryRank[category], ","))
        end
    end
    for _, id in ipairs(sortedKeys(setup.picks)) do
        local pick = setup.picks[id]
        table.insert(parts, "pick:" .. id .. "=" .. tostring(pick.mode) .. ":" .. tostring(pick.mod))
    end
    for _, mod in ipairs(sortedKeys(setup.hibernate)) do
        if setup.hibernate[mod] then
            table.insert(parts, "park:" .. mod)
        end
    end
    return table.concat(parts, ";")
end

function ModMux.readSetup(xml, key)
    local setup = {rank = {}, categoryRank = {}, picks = {}, hibernate = {}, live = {}}
    local i = 0
    while true do
        local name = getXMLString(xml, string.format("%s.rank.mod(%d)#name", key, i))
        if name == nil then
            break
        end
        table.insert(setup.rank, name)
        i = i + 1
    end
    i = 0
    while true do
        local categoryKey = string.format("%s.categories.category(%d)", key, i)
        local category = getXMLString(xml, categoryKey .. "#name")
        if category == nil then
            break
        end
        local list, j = {}, 0
        while true do
            local name = getXMLString(xml, string.format("%s.mod(%d)#name", categoryKey, j))
            if name == nil then
                break
            end
            table.insert(list, name)
            j = j + 1
        end
        setup.categoryRank[category] = list
        i = i + 1
    end
    i = 0
    while true do
        local pickKey = string.format("%s.picks.pick(%d)", key, i)
        local id = getXMLString(xml, pickKey .. "#slot")
        if id == nil then
            break
        end
        local mode = getXMLString(xml, pickKey .. "#mode")
        if mode == "winner" or mode == "shared" then
            setup.picks[id] = {mode = mode, mod = getXMLString(xml, pickKey .. "#mod")}
        end
        i = i + 1
    end
    i = 0
    while true do
        local name = getXMLString(xml, string.format("%s.hibernate.mod(%d)#name", key, i))
        if name == nil then
            break
        end
        setup.hibernate[name] = true
        i = i + 1
    end
    i = 0
    while true do
        local settingKey = string.format("%s.live.setting(%d)", key, i)
        local id = getXMLString(xml, settingKey .. "#id")
        if id == nil then
            break
        end
        setup.live[id] = getXMLString(xml, settingKey .. "#value")
        i = i + 1
    end
    return setup
end

function ModMux.writeSetup(xml, key, setup)
    for i, name in ipairs(setup.rank or {}) do
        setXMLString(xml, string.format("%s.rank.mod(%d)#name", key, i - 1), name)
    end
    local c = 0
    for _, category in ipairs(sortedKeys(setup.categoryRank)) do
        local list = setup.categoryRank[category]
        if #list > 0 then
            local categoryKey = string.format("%s.categories.category(%d)", key, c)
            setXMLString(xml, categoryKey .. "#name", category)
            for j, name in ipairs(list) do
                setXMLString(xml, string.format("%s.mod(%d)#name", categoryKey, j - 1), name)
            end
            c = c + 1
        end
    end
    for i, id in ipairs(sortedKeys(setup.picks)) do
        local pickKey = string.format("%s.picks.pick(%d)", key, i - 1)
        local pick = setup.picks[id]
        setXMLString(xml, pickKey .. "#slot", id)
        setXMLString(xml, pickKey .. "#mode", pick.mode)
        if pick.mod ~= nil then
            setXMLString(xml, pickKey .. "#mod", pick.mod)
        end
    end
    local h = 0
    for _, name in ipairs(sortedKeys(setup.hibernate)) do
        if setup.hibernate[name] then
            setXMLString(xml, string.format("%s.hibernate.mod(%d)#name", key, h), name)
            h = h + 1
        end
    end
    for i, id in ipairs(sortedKeys(setup.live)) do
        local settingKey = string.format("%s.live.setting(%d)", key, i - 1)
        setXMLString(xml, settingKey .. "#id", id)
        setXMLString(xml, settingKey .. "#value", tostring(setup.live[id]))
    end
end

function ModMux.settingsPath()
    return ModMux.settingsDir .. "settings.xml"
end

function ModMux.loadSettings()
    local settings = ModMux.defaultSettings()
    local path = ModMux.settingsPath()
    if not fileExists(path) then
        return settings
    end
    local xml = loadXMLFile("ModMuxSettings", path)
    if xml == nil or xml == 0 then
        return settings
    end
    local setup = ModMux.readSetup(xml, "modMux")
    settings.rank, settings.categoryRank, settings.picks, settings.hibernate, settings.live = setup.rank, setup.categoryRank,
        setup.picks, setup.hibernate, setup.live
    local o = settings.options
    local function bool(name, default)
        local value = getXMLBool(xml, "modMux.options#" .. name)
        if value == nil then
            return default
        end
        return value
    end
    o.warnOnScreen = bool("warnOnScreen", o.warnOnScreen)
    o.perfProbes = bool("perfProbes", o.perfProbes)
    o.hudAutoScan = bool("hudAutoScan", o.hudAutoScan)
    o.leversSuspended = bool("leversSuspended", o.leversSuspended)
    o.budgetFps = getXMLInt(xml, "modMux.options#budgetFps") or o.budgetFps
    local i = 0
    while true do
        local id = getXMLString(xml, string.format("modMux.dismissed.item(%d)#id", i))
        if id == nil then
            break
        end
        settings.dismissed[id] = true
        i = i + 1
    end
    delete(xml)
    return settings
end

function ModMux.saveSettings()
    local settings = ModMux.settings
    if settings == nil or ModMux.settingsDir == "" then
        return false
    end
    local xml = createXMLFile("ModMuxSettings", ModMux.settingsPath(), "modMux")
    if xml == nil or xml == 0 then
        return false
    end
    setXMLInt(xml, "modMux#version", 1)
    local o = settings.options
    setXMLBool(xml, "modMux.options#warnOnScreen", o.warnOnScreen)
    setXMLBool(xml, "modMux.options#perfProbes", o.perfProbes)
    setXMLBool(xml, "modMux.options#hudAutoScan", o.hudAutoScan)
    setXMLBool(xml, "modMux.options#leversSuspended", o.leversSuspended)
    setXMLInt(xml, "modMux.options#budgetFps", o.budgetFps)
    ModMux.writeSetup(xml, "modMux", settings)
    for i, id in ipairs(sortedKeys(settings.dismissed)) do
        setXMLString(xml, string.format("modMux.dismissed.item(%d)#id", i - 1), id)
    end
    saveXMLFile(xml)
    delete(xml)
    return true
end

----------------------------------------------------------------------------------------------------------------
-- Boot marker and safe mode
----------------------------------------------------------------------------------------------------------------

function ModMux.bootPath()
    return ModMux.settingsDir .. "boot.xml"
end

function ModMux.readBoot()
    local path = ModMux.bootPath()
    if not fileExists(path) then
        return nil
    end
    local xml = loadXMLFile("ModMuxBoot", path)
    if xml == nil or xml == 0 then
        return nil
    end
    local state = getXMLString(xml, "modMuxBoot#state")
    delete(xml)
    return state
end

function ModMux.writeBoot(state, levers)
    local xml = createXMLFile("ModMuxBoot", ModMux.bootPath(), "modMuxBoot")
    if xml == nil or xml == 0 then
        return
    end
    setXMLString(xml, "modMuxBoot#state", state)
    setXMLString(xml, "modMuxBoot#date", ModMux.getDate())
    setXMLInt(xml, "modMuxBoot#levers", levers or 0)
    saveXMLFile(xml)
    delete(xml)
    ModMux.bootState = state
end

--- true when this load has anything structural to do (picks, rankings, parking, timers)
function ModMux.hasStructural(setup)
    return ModMux.setupKey(setup) ~= ModMux.setupKey(ModMux.defaultSettings()) or setup.perfProbes == true
end

--- the levers come back on with the next load
function ModMux.resumeLevers()
    ModMux.settings.options.leversSuspended = false
    ModMux.saveSettings()
end

function ModMux.suspendLevers()
    ModMux.settings.options.leversSuspended = true
    ModMux.saveSettings()
end

----------------------------------------------------------------------------------------------------------------
-- Abnormal load: a savegame that had farms comes up with none (a conflict can do that). Saving now would overwrite
-- the good savegame with the broken state, so this session doesn't save, and the next one starts in safe mode.
----------------------------------------------------------------------------------------------------------------

function ModMux.countSavedFarms(directory)
    local path = directory .. "/farms.xml"
    if not fileExists(path) then
        return 0
    end
    local xml = loadXMLFile("ModMuxFarms", path)
    if xml == nil or xml == 0 then
        return 0
    end
    local count, i = 0, 0
    while true do
        local key = string.format("farms.farm(%d)", i)
        if not hasXMLProperty(xml, key) then
            break
        end
        local farmId = getXMLInt(xml, key .. "#farmId")
        if farmId == nil or farmId > 0 then
            count = count + 1
        end
        i = i + 1
    end
    delete(xml)
    return count
end

function ModMux.countCurrentFarms()
    local manager = g_farmManager
    if manager == nil then
        return nil
    end
    local farms = manager.getFarms ~= nil and manager:getFarms() or manager.farms
    if type(farms) ~= "table" then
        return nil
    end
    local spectator = (FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID) or 0
    local count = 0
    for _, farm in pairs(farms) do
        if type(farm) == "table" and farm.farmId ~= nil and farm.farmId ~= spectator then
            count = count + 1
        end
    end
    return count
end

function ModMux.checkAbnormal()
    local mission = g_currentMission
    if mission == nil or mission.getIsServer == nil or not mission:getIsServer() then
        return false
    end
    local info = mission.missionInfo
    local directory = info ~= nil and info.savegameDirectory or nil
    if directory == nil then
        return false
    end
    local saved = ModMux.countSavedFarms(directory)
    local current = ModMux.countCurrentFarms()
    if saved > 0 and current == 0 then
        ModMux.blockSaves = true
        ModMux.writeBoot("abnormal")
        Logging.error("%s this savegame had %d farm(s) and loaded with none: saving is blocked for this session so the " ..
            "savegame on disk stays as it was. The next start is in safe mode (every ModMux lever off).", ModMux.TAG, saved)
        return true
    end
    return false
end

function ModMux.installSaveGuard()
    if FSBaseMission == nil or type(FSBaseMission.saveSavegame) ~= "function" then
        return
    end
    local original = FSBaseMission.saveSavegame
    local guard = function(mission, ...)
        if ModMux.blockSaves then
            Logging.warning("%s save blocked: this load came up without its farms (see the ModMux REVIEW tab)", ModMux.TAG)
            ModMux.notify(ModMux.getText("mm_notify_saveBlocked"), true)
            return
        end
        return original(mission, ...)
    end
    ModMuxScan.transparent[guard] = original
    FSBaseMission.saveSavegame = guard
end

----------------------------------------------------------------------------------------------------------------
-- Boot and the mission
----------------------------------------------------------------------------------------------------------------

function ModMux.boot()
    local profile = getUserProfileAppPath()
    createFolder(profile .. "modSettings/")
    ModMux.settingsDir = profile .. "modSettings/" .. ModMux.MOD_NAME .. "/"
    createFolder(ModMux.settingsDir)

    ModMux.settings = ModMux.loadSettings()
    ModMux.killSwitch = fileExists(ModMux.settingsDir .. ModMux.KILL_FILE)
    local lastBoot = ModMux.readBoot()
    if ModMux.killSwitch then
        ModMux.safeMode, ModMux.safeReason = true, "killSwitch"
    elseif lastBoot == "loading" or lastBoot == "abnormal" then
        ModMux.safeMode, ModMux.safeReason = true, lastBoot == "loading" and "lastLaunch" or "abnormal"
        ModMux.suspendLevers()
    elseif ModMux.settings.options.leversSuspended then
        ModMux.safeMode, ModMux.safeReason = true, "suspended"
    end
    if lastBoot ~= nil and lastBoot ~= "ok" then
        ModMux.writeBoot("ok")
    end

    -- what this load runs with; changes made while playing wait for the next load
    ModMux.applied = ModMux.copySetup(ModMux.settings)
    ModMux.applied.perfProbes = ModMux.settings.options.perfProbes

    ModMuxOrigin.refreshMods()
    ModMuxScan.calibrated = ModMuxScan.calibrate()
    if not ModMux.killSwitch then
        ModMuxScan.install()
        ModMux.installSaveGuard()
    end

    -- only a flag: the work follows on ModMux's first update, outside the game's loading
    if Mission00 ~= nil and Mission00.loadMission00Finished ~= nil then
        Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
            ModMux.missionReady = true
        end)
    end
    addModEventListener(ModMux)

    rawset(G, "g_modMux", {
        version = ModMux.getVersion(),
        registerLiveSetting = function(def)
            return ModMuxLive.register(def)
        end,
        isSafeMode = function()
            return ModMux.safeMode
        end,
        getConflictCount = function()
            return #ModMuxScan.conflicts
        end
    })

    ModMux.guard("first scan", ModMuxScan.scan, "boot")

    local mode = ModMux.safeMode and ("SAFE MODE (" .. tostring(ModMux.safeReason) .. ")") or "levers on"
    print(string.format("%s %s loaded at position %d of %d mods, %s, hook recorder %s, chain reading %s", ModMux.TAG,
        ModMux.getVersion(), ModMux.loadPosition(), #ModMuxOrigin.mods, mode, ModMuxScan.installed and "on" or "off",
        ModMuxScan.calibrated and "on" or "OFF (the game hides function details)"))
end

--- how many mods loaded before ModMux (+1): they can't be watched live, only read from what they left behind
function ModMux.loadPosition()
    local position = 1
    local own = ModMux.MOD_NAME:lower()
    for _, mod in ipairs(ModMuxOrigin.mods) do
        if not mod.isDLC and mod.name:lower() < own then
            position = position + 1
        end
    end
    return position
end

ModMuxLate = {}

function ModMuxLate:loadMap()
    ModMux.guard("scan after every loadMap", ModMux.onAllLoadMaps)
end

function ModMux.onAllLoadMaps()
    if ModMux.missionLoaded then
        return
    end
    ModMuxScan.resolveRecords()
    ModMuxScan.scan("afterLoadMaps")
    ModMuxScan.lateGeneration = ModMuxScan.generation
end

function ModMux:loadMap(filename)
    if not ModMux.lateRegistered then
        ModMux.lateRegistered = true
        addModEventListener(ModMuxLate)
    end
    ModMux.guard("loadMap scan", function()
        ModMuxOrigin.refreshMods()
        ModMuxScan.resolveRecords()
        ModMuxScan.scan("loadMap")
        ModMux.loadMapGeneration = ModMuxScan.generation
    end)
    ModMux.guard("settings", function()
        ModMuxLive.registerOwn()
        ModMuxProfiles.load()
    end)

    addConsoleCommand("modMux", "ModMux: conflicts and what is done about them", "consoleSummary", ModMux)
    addConsoleCommand("modMuxReport", "ModMux: writes modSettings/FS25_ModMux/ModMux.log", "consoleReport", ModMux)
    addConsoleCommand("modMuxPick", "ModMux: modMuxPick <conflict id> <mod name|shared|default> (next load)", "consolePick", ModMux)
    addConsoleCommand("modMuxPark", "ModMux: modMuxPark <mod name> [off] (next load)", "consolePark", ModMux)
    addConsoleCommand("modMuxLevers", "ModMux: modMuxLevers on|off (next load)", "consoleLevers", ModMux)
end

function ModMux.onMissionLoaded()
    if ModMuxScan.lateGeneration == math.huge then
        ModMuxScan.lateGeneration = ModMux.loadMapGeneration or ModMuxScan.generation
    end
    ModMuxOrigin.refreshMods()
    ModMuxScan.resolveRecords()
    ModMuxScan.scan("mission")
    local conflicts = ModMuxScan.analyze()
    ModMuxPerf.findListeners()
    ModMux.checkAbnormal()

    if not ModMux.safeMode then
        local setup = ModMux.applied
        -- an abnormal load keeps its marker: the next start must be in safe mode
        if ModMux.hasStructural(setup) and not ModMux.blockSaves then
            ModMux.writeBoot("loading", ModMux.countPlans(setup))
        end
        ModMuxLevers.applyAll(conflicts, setup)
        for mod, parked in pairs(setup.hibernate) do
            if parked then
                ModMuxPerf.park(mod)
            end
        end
        if setup.perfProbes then
            ModMuxPerf.install()
        end
        ModMux.refreshAppliedChains()
    end

    ModMuxReview.loadKnownPairs({ModMux.MOD_DIR .. "config/knownIncompatible.xml", ModMux.settingsDir .. "knownIncompatible.xml"})
    ModMuxReview.build(conflicts)
    ModMux.writeReport()
    ModMux.logSummary()

    if g_dedicatedServer == nil and g_gui ~= nil then
        ModMuxFrame.register()
    end
    ModMux.pendingWarning = true
end

--- after the levers: the chains as they are now, for the ADVANCED view
function ModMux.refreshAppliedChains()
    for id, entry in pairs(ModMuxLevers.applied) do
        local conflict = ModMuxScan.conflictById[id]
        if entry.done and conflict ~= nil and conflict.slot ~= nil then
            local value = rawget(conflict.slot.table, conflict.slot.key)
            conflict.after = ModMuxScan.parse(value, id, conflict.slot.containerMod)
        end
    end
end

function ModMux.countPlans(setup)
    local count = 0
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if ModMuxLevers.planFor(conflict, setup).mode ~= "default" then
            count = count + 1
        end
    end
    for _, parked in pairs(setup.hibernate) do
        if parked then
            count = count + 1
        end
    end
    return count
end

--- how many changes wait for the next load (settings differ from what this load runs with)
function ModMux.pendingCount()
    local settings, applied = ModMux.settings, ModMux.applied
    if settings == nil or applied == nil then
        return 0
    end
    local count = 0
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if not ModMuxLevers.samePlan(ModMuxLevers.planFor(conflict, settings), ModMuxLevers.planFor(conflict, applied)) then
            count = count + 1
        end
    end
    local mods = {}
    for mod in pairs(settings.hibernate) do
        mods[mod] = true
    end
    for mod in pairs(applied.hibernate) do
        mods[mod] = true
    end
    for mod in pairs(mods) do
        if (settings.hibernate[mod] == true) ~= (applied.hibernate[mod] == true) then
            count = count + 1
        end
    end
    if settings.options.perfProbes ~= applied.perfProbes then
        count = count + 1
    end
    if ModMux.safeReason ~= "killSwitch" and settings.options.leversSuspended ~= (ModMux.safeMode == true) then
        count = count + 1
    end
    return count
end

function ModMux:update(dt)
    if ModMux.missionReady and not ModMux.missionLoaded then
        ModMux.missionLoaded = true
        ModMux.guard("mission", ModMux.onMissionLoaded)
    end
    -- a frame that stopped with an error leaves frameBroken set: the numbers stop instead of the log filling up
    if ModMuxPerf.installed and not ModMux.frameBroken then
        ModMux.frameBroken = true
        ModMuxPerf.endFrame()
        ModMux.frameBroken = false
    end
    if not ModMux.missionLoaded then
        return
    end
    ModMux.runMs = ModMux.runMs + (dt or 0)
    if ModMux.bootState == "loading" and ModMux.runMs >= ModMux.RECOVERY_MS then
        ModMux.writeBoot("ok")
    end
    if ModMux.pendingWarning and ModMux.runMs >= ModMux.WARNING_DELAY_MS then
        ModMux.pendingWarning = false
        ModMux.showStartWarning()
    end
    if not ModMux.autoHudDone and ModMux.runMs >= ModMux.AUTO_HUD_SCAN_MS then
        ModMux.autoHudDone = true
        if ModMux.settings.options.hudAutoScan and g_dedicatedServer == nil then
            ModMux.startHudScan()
        end
    end
end

function ModMux:deleteMap()
    if ModMux.bootState == "loading" and ModMux.runMs > 2000 then
        ModMux.writeBoot("ok")
    end
    ModMuxPerf.stopHudScan()
    removeConsoleCommand("modMux")
    removeConsoleCommand("modMuxReport")
    removeConsoleCommand("modMuxPick")
    removeConsoleCommand("modMuxPark")
    removeConsoleCommand("modMuxLevers")
    ModMuxFrame.unregister()
end

function ModMux.startHudScan()
    if ModMuxPerf.startHudScan(ModMux.HUD_SCAN_FRAMES) then
        ModMuxReview.hudScanState = "running"
        return true
    end
    return false
end

function ModMux.notify(text, critical)
    if g_dedicatedServer ~= nil or g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        return
    end
    local kind = critical and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_INFO
    g_currentMission:addIngameNotification(kind, text)
end

function ModMux.lostCount()
    local count = 0
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if conflict.kind == "lost" then
            count = count + 1
        end
    end
    return count
end

function ModMux.showStartWarning()
    if ModMux.blockSaves then
        ModMux.notify(ModMux.getText("mm_notify_abnormal"), true)
    end
    if ModMux.safeMode and ModMux.safeReason ~= "suspended" then
        ModMux.notify(ModMux.getText("mm_notify_safe_" .. ModMux.safeReason), true)
    end
    if not ModMux.settings.options.warnOnScreen then
        return
    end
    local flat = ModMuxReview.flatCount(ModMux.settings.dismissed)
    if flat > 0 then
        ModMux.notify(ModMux.getText("mm_notify_flat", flat), true)
    elseif ModMux.lostCount() > 0 then
        ModMux.notify(ModMux.getText("mm_notify_lost", ModMux.lostCount()), false)
    end
end

function ModMux.onReviewChanged()
    if ModMuxFrame.instance ~= nil and ModMuxFrame.instance.onDataChanged ~= nil then
        ModMuxFrame.instance:onDataChanged()
    end
end

----------------------------------------------------------------------------------------------------------------
-- Report (modSettings/FS25_ModMux/ModMux.log) and log summary
----------------------------------------------------------------------------------------------------------------

local function writeTextFile(path, content)
    local file = createFile(path, FileAccess.WRITE)
    if file == nil or file == 0 then
        return false
    end
    fileWrite(file, content)
    delete(file)
    return true
end

function ModMux.buildReport()
    local lines = {}
    local function add(fmt, ...)
        if select("#", ...) > 0 then
            table.insert(lines, string.format(fmt, ...))
        else
            table.insert(lines, fmt)
        end
    end
    add("ModMux %s report, %s", ModMux.getVersion(), ModMux.getDate())
    add("Mods: %d active, ModMux loaded as number %d (mods before it are read from what they left behind)",
        #ModMuxOrigin.mods, ModMux.loadPosition())
    if ModMux.safeMode then
        add("SAFE MODE: %s. No conflict was rewired, nothing parked, no timers.", tostring(ModMux.safeReason))
    end
    if ModMux.blockSaves then
        add("SAVES BLOCKED: this savegame had farms and loaded with none.")
    end
    add("Hook recorder: %s, chain reading: %s, hooks recorded: %d (by mods: %d)", ModMuxScan.installed and "on" or "off",
        ModMuxScan.calibrated and "on" or "off", #ModMuxScan.records, #(ModMuxScan.modRecords or {}))
    for _, scan in ipairs(ModMuxScan.scanLog) do
        add("Scan %-14s %6d functions, %4d changed by mods, %.0f ms", scan.label, scan.functions, scan.hooked, scan.ms)
    end
    add("")
    add("CONFLICTS: %d", #ModMuxScan.conflicts)
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        add("")
        add("[%s] %s  (%s)", ModMuxTabs.kindText(conflict), ModMuxTabs.conflictTitle(conflict), ModMuxTabs.modList(conflict.mods, 10))
        for _, line in ipairs(ModMuxTabs.explain(conflict)) do
            add("    %s", line)
        end
        local applied = ModMuxLevers.applied[conflict.id]
        if applied ~= nil then
            add("    This load: %s (%s)", ModMuxLevers.planText(applied.plan), applied.status)
        end
    end
    local parked = sortedKeys(ModMuxPerf.parked)
    if #parked > 0 then
        add("")
        add("PARKED: %s", table.concat(parked, ", "))
    end
    local findings = ModMuxReview.list(ModMux.settings.dismissed, true)
    if #findings > 0 then
        add("")
        add("REVIEW: %d", #findings)
        for _, finding in ipairs(findings) do
            add("- %s%s", ModMuxTabs.findingTitle(finding), finding.dismissed and " (dismissed)" or "")
            for _, line in ipairs(ModMuxTabs.evidenceLines(finding)) do
                add("    %s", line)
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function ModMux.writeReport()
    return writeTextFile(ModMux.settingsDir .. "ModMux.log", ModMux.buildReport())
end

function ModMux.logSummary()
    local bySeverity = {0, 0, 0}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        bySeverity[conflict.severity] = bySeverity[conflict.severity] + 1
    end
    print(string.format("%s %d conflicts (%d serious, %d may block, %d shared), %d rewired this load, %d mods parked, " ..
        "report in modSettings/%s/ModMux.log", ModMux.TAG, #ModMuxScan.conflicts, bySeverity[3], bySeverity[2], bySeverity[1],
        ModMuxLevers.appliedCount, #sortedKeys(ModMuxPerf.parked), ModMux.MOD_NAME))
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if conflict.kind == "lost" then
            print(string.format("%s   lost changes in %s: %s", ModMux.TAG, conflict.id, ModMuxTabs.modList(conflict.mods, 6)))
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Console
----------------------------------------------------------------------------------------------------------------

function ModMux:consoleSummary()
    local lines = {string.format("ModMux: %d conflicts, %d changes wait for the next load%s", #ModMuxScan.conflicts,
        ModMux.pendingCount(), ModMux.safeMode and (", SAFE MODE (" .. tostring(ModMux.safeReason) .. ")") or "")}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        local plan = ModMuxLevers.planFor(conflict, ModMux.settings)
        table.insert(lines, string.format("  [%s] %s: %s -> %s", ModMuxTabs.kindText(conflict), conflict.id,
            table.concat(conflict.mods, ", "), ModMuxLevers.planText(plan)))
    end
    return table.concat(lines, "\n")
end

function ModMux:consoleReport()
    if ModMux.writeReport() then
        return "Written: " .. ModMux.settingsDir .. "ModMux.log"
    end
    return "Could not write " .. ModMux.settingsDir .. "ModMux.log"
end

function ModMux:consolePick(id, choice)
    local conflict = id ~= nil and ModMuxScan.conflictById[id] or nil
    if conflict == nil or conflict.type ~= "slot" then
        return "Unknown conflict id (see 'modMux'): " .. tostring(id)
    end
    if conflict.locked then
        return "Locked: " .. id
    end
    if choice == nil or choice == "default" then
        ModMux.settings.picks[id] = nil
    elseif choice == "shared" then
        ModMux.settings.picks[id] = {mode = "shared"}
    else
        local found = nil
        for _, mod in ipairs(conflict.mods) do
            if mod:lower() == choice:lower() then
                found = mod
            end
        end
        if found == nil then
            return "Not in this conflict: " .. choice
        end
        ModMux.settings.picks[id] = {mode = "winner", mod = found}
    end
    ModMux.saveSettings()
    return "Saved, applies on the next load: " .. ModMuxLevers.planText(ModMuxLevers.planFor(conflict, ModMux.settings))
end

function ModMux:consolePark(name, off)
    if name == nil or not ModMuxOrigin.isMod(name) then
        return "Unknown mod: " .. tostring(name)
    end
    ModMux.settings.hibernate[name] = (off ~= "off") or nil
    ModMux.saveSettings()
    return string.format("%s %s on the next load", name, off == "off" and "runs normally" or "is parked")
end

function ModMux:consoleLevers(state)
    if state == "off" then
        ModMux.suspendLevers()
        return "Levers off from the next load"
    elseif state == "on" then
        ModMux.resumeLevers()
        return "Levers on from the next load"
    end
    return "modMuxLevers on|off"
end

ModMux.guard("start", ModMux.boot)
