-- ModMux: finds the functions several mods change, and what became of each change.
--
-- How a mod changes a game function: `Vehicle.update = Utils.appendedFunction(Vehicle.update, myUpdate)` (or prepended /
-- overwritten), which builds a small wrapper that keeps the old function, or a plain `Vehicle.update = function ...` that
-- may or may not call the old one. The wrappers keep the old function as an upvalue, so the whole chain can be walked
-- from the outside: wrapper -> mod function + older wrapper -> ... -> the game's original.
--
-- 1. calibrate(): wraps two dummy functions with each Utils helper to learn where the old / new function sit in the
--    wrapper's upvalues and how such a wrapper looks (file:line), so nothing depends on the game's private code.
-- 2. install(): from ModMux's load on, every Utils.*Function call is recorded with the mod that made it. That also
--    catches a change that was made and then thrown away by a later mod: the silent breakage this mod is about.
-- 3. scan(): walks every class table (and every mod's own classes) and parses each changed function into layers.
--    Runs at ModMux's load, at its loadMap, after every mod's loadMap and when the mission has loaded.
-- 4. analyze(): lost changes, conflicts (two or more mods on one function), vehicle / placeable type chains.

ModMuxScan = {}

local G = (getfenv ~= nil and getfenv(0)) or _G
ModMuxScan.G = G

ModMuxScan.UTILS_NAMES = {append = "appendedFunction", prepend = "prependedFunction", overwrite = "overwrittenFunction"}
ModMuxScan.KINDS = {"append", "prepend", "overwrite"}

ModMuxScan.kinds = {}               -- wrapper signature -> {kind, oldIndex, newIndex}
ModMuxScan.original = {}            -- kind -> the Utils helper as it was before the recorder
ModMuxScan.records = {}             -- every recorded hook made by a mod
ModMuxScan.recordByWrapper = {}
ModMuxScan.transparent = setmetatable({}, {__mode = "k"})  -- ModMux's own wrappers -> the function inside
ModMuxScan.history = {}             -- function -> slot id it was seen in (first one)
ModMuxScan.historyAlias = {}        -- function -> {slot id = true} when it was seen in several slots
ModMuxScan.seenIn = {}              -- recorded wrapper -> slot id a scan found it in
ModMuxScan.elsewhere = {}           -- recorded wrappers found on an object (g_currentMission.hud, ...): not class changes
ModMuxScan.bestFloor = {}           -- slot id -> the game's own function at the bottom of the chain (first seen)
ModMuxScan.containers = {}          -- container name -> table (last scan)
ModMuxScan.slots = {}               -- slot id -> slot with at least one mod in its chain (last scan)
ModMuxScan.generation = 0           -- number of scans done; records remember the generation they were made in
ModMuxScan.scanLog = {}             -- {label, functions, hooked, ms}
ModMuxScan.conflicts = {}
ModMuxScan.conflictById = {}
ModMuxScan.listenerRecords = {}     -- addModEventListener calls seen: {listener, source}
ModMuxScan.installed = false

ModMuxScan.SEVERITY = {lost = 3, replaced = 2, overwrite = 2, shared = 1, types = 1}

local GAME, ENGINE = ModMuxOrigin.GAME, ModMuxOrigin.ENGINE

local function clock()
    if getTimeSec ~= nil then
        return getTimeSec()
    end
    return os.clock()
end

local function signatureOf(f)
    local info = ModMuxOrigin.info(f)
    return info ~= nil and info.signature or "?"
end

----------------------------------------------------------------------------------------------------------------
-- Calibration and the recorder
----------------------------------------------------------------------------------------------------------------

function ModMuxScan.calibrate()
    if Utils == nil or not ModMuxOrigin.hasUpvalues then
        return false
    end
    local function probeOld() end
    local function probeNew() end
    local found = 0
    for _, kind in ipairs(ModMuxScan.KINDS) do
        local helper = Utils[ModMuxScan.UTILS_NAMES[kind]]
        if type(helper) == "function" then
            ModMuxScan.original[kind] = helper
            local wrapper = helper(probeOld, probeNew)
            if type(wrapper) == "function" and wrapper ~= probeOld and wrapper ~= probeNew then
                local oldIndex, newIndex = nil, nil
                for i = 1, 30 do
                    local name, value = debug.getupvalue(wrapper, i)
                    if name == nil then
                        break
                    end
                    if value == probeOld then
                        oldIndex = i
                    elseif value == probeNew then
                        newIndex = i
                    end
                end
                if oldIndex ~= nil and newIndex ~= nil then
                    ModMuxScan.kinds[signatureOf(wrapper)] = {kind = kind, oldIndex = oldIndex, newIndex = newIndex}
                    found = found + 1
                end
            end
        end
    end
    return found == #ModMuxScan.KINDS
end

--- the file a function was called from (level 1 = the function asking)
local function callerSource(level)
    if not ModMuxOrigin.hasDebug then
        return nil
    end
    local info = debug.getinfo(level + 1, "S")
    return info ~= nil and info.source or nil
end

function ModMuxScan.onHook(kind, oldFunc, newFunc, wrapper, source)
    if type(newFunc) ~= "function" or type(oldFunc) ~= "function" or type(wrapper) ~= "function" or wrapper == newFunc then
        return
    end
    local record = {seq = #ModMuxScan.records + 1, kind = kind, old = oldFunc, new = newFunc, wrapper = wrapper,
        callerSource = source, generation = ModMuxScan.generation}
    table.insert(ModMuxScan.records, record)
    ModMuxScan.recordByWrapper[wrapper] = record
end

--- Puts the recorder around the Utils helpers and addModEventListener. Idempotent.
function ModMuxScan.install()
    if ModMuxScan.installed or Utils == nil then
        return
    end
    ModMuxScan.installed = true
    for _, kind in ipairs(ModMuxScan.KINDS) do
        local name = ModMuxScan.UTILS_NAMES[kind]
        local helper = ModMuxScan.original[kind] or Utils[name]
        if type(helper) == "function" then
            ModMuxScan.original[kind] = helper
            local recorder = function(oldFunc, newFunc)
                local wrapper = helper(oldFunc, newFunc)
                ModMuxScan.onHook(kind, oldFunc, newFunc, wrapper, callerSource(2))
                return wrapper
            end
            ModMuxScan.transparent[recorder] = helper
            Utils[name] = recorder
        end
    end

    local addListener = rawget(G, "addModEventListener")
    if type(addListener) == "function" then
        local recorder = function(listener, ...)
            if type(listener) == "table" then
                table.insert(ModMuxScan.listenerRecords, {listener = listener, source = callerSource(2)})
            end
            return addListener(listener, ...)
        end
        ModMuxScan.transparent[recorder] = addListener
        rawset(G, "addModEventListener", recorder)
    end
end

--- Resolves which mod made each record (after the mod list is complete). Records of the game itself are dropped.
function ModMuxScan.resolveRecords()
    local kept = {}
    ModMuxScan.recordByWrapper = {}
    for _, record in ipairs(ModMuxScan.records) do
        local owner = ModMuxOrigin.ofFunction(record.new)
        local caller = ModMuxOrigin.ofSource(record.callerSource)
        if not ModMuxOrigin.isMod(owner) and ModMuxOrigin.isMod(caller) then
            owner = caller
        end
        -- vehicle type chains (SpecializationUtil) are built by the game with the mods' functions: not a class change
        record.viaGame = caller == GAME
        record.mod = owner
        if ModMuxOrigin.isMod(owner) and owner ~= ModMux.MOD_NAME then
            table.insert(kept, record)
        end
        -- every wrapper stays known for parsing, the game's too
        ModMuxScan.recordByWrapper[record.wrapper] = record
    end
    ModMuxScan.modRecords = kept
end

----------------------------------------------------------------------------------------------------------------
-- History: which slot every function was seen in
----------------------------------------------------------------------------------------------------------------

function ModMuxScan.remember(f, id)
    if f == nil then
        return
    end
    local current = ModMuxScan.history[f]
    if current == nil then
        ModMuxScan.history[f] = id
    elseif current ~= id then
        local alias = ModMuxScan.historyAlias[f]
        if alias == nil then
            alias = {[current] = true}
            ModMuxScan.historyAlias[f] = alias
        end
        alias[id] = true
    end
end

function ModMuxScan.historyHas(f, id)
    if ModMuxScan.history[f] == id then
        return true
    end
    local alias = ModMuxScan.historyAlias[f]
    return alias ~= nil and alias[id] == true
end

--- true when `f` was this slot's value (or part of its chain) at some point, directly or as the base of a recorded hook
function ModMuxScan.belongsTo(f, id, depth)
    depth = depth or 0
    if f == nil or id == nil or depth > 30 then
        return false
    end
    if ModMuxScan.historyHas(f, id) then
        return true
    end
    local record = ModMuxScan.recordByWrapper[f]
    return record ~= nil and ModMuxScan.belongsTo(record.old, id, depth + 1)
end

--- the one slot a function belongs to, or nil when unknown / ambiguous
function ModMuxScan.targetOf(f, depth)
    depth = depth or 0
    if f == nil or depth > 30 then
        return nil
    end
    local id = ModMuxScan.history[f]
    if id ~= nil then
        if ModMuxScan.historyAlias[f] ~= nil then
            return nil
        end
        return id
    end
    local record = ModMuxScan.recordByWrapper[f]
    if record ~= nil then
        return ModMuxScan.targetOf(record.old, depth + 1)
    end
    return nil
end

----------------------------------------------------------------------------------------------------------------
-- Parsing one function into layers
----------------------------------------------------------------------------------------------------------------

local function isSuperName(name)
    if type(name) ~= "string" then
        return false
    end
    local n = name:lower()
    return n:find("super") ~= nil or n:find("orig") ~= nil or n:find("^old") ~= nil or n:find("^prev") ~= nil
        or n:find("^base") ~= nil or n:find("vanilla") ~= nil or n:find("default") ~= nil
end

--- The function a plain replacement keeps and (probably) calls: an upvalue that was this slot's value before.
-- Returns super, trusted. A name like "superFunc" / "origUpdate" alone is only a guess (trusted = false).
function ModMuxScan.findSuper(f, id)
    if not ModMuxOrigin.hasUpvalues then
        return nil, false
    end
    local guess = nil
    for i = 1, 60 do
        local name, value = debug.getupvalue(f, i)
        if name == nil then
            break
        end
        if type(value) == "function" and value ~= f then
            if id ~= nil and ModMuxScan.belongsTo(value, id) then
                return value, true
            end
            if guess == nil and isSuperName(name) then
                guess = value
            end
        end
    end
    return guess, false
end

--- Layers of a function, outermost first, and the game function at the bottom (floor; nil when a mod replaced it).
-- layer = {kind = append|prepend|overwrite|replace, fn, wrapper, owner, record, super, trusted}
function ModMuxScan.parse(f, id, containerMod)
    local layers, floor, guessed = {}, nil, false
    local guard = 0
    while type(f) == "function" and guard < 80 do
        guard = guard + 1
        local inner = ModMuxScan.transparent[f]
        if inner ~= nil then
            f = inner
        else
            local record = ModMuxScan.recordByWrapper[f]
            local kind, old, new = nil, nil, nil
            if record ~= nil then
                kind, old, new = record.kind, record.old, record.new
            elseif ModMuxOrigin.hasUpvalues then
                local k = ModMuxScan.kinds[signatureOf(f)]
                if k ~= nil then
                    local _, o = debug.getupvalue(f, k.oldIndex)
                    local _, n = debug.getupvalue(f, k.newIndex)
                    kind, old, new = k.kind, o, n
                end
            end
            if kind ~= nil then
                local owner = (record ~= nil and record.mod) or ModMuxOrigin.ofFunction(new)
                if owner ~= ModMux.MOD_NAME then
                    table.insert(layers, {kind = kind, fn = new, wrapper = f, owner = owner, record = record})
                end
                f = old
            else
                local owner = ModMuxOrigin.ofFunction(f)
                if owner == GAME or owner == ENGINE or (containerMod ~= nil and owner == containerMod) then
                    floor = f
                    break
                end
                local super, trusted = ModMuxScan.findSuper(f, id)
                table.insert(layers, {kind = "replace", fn = f, wrapper = f, owner = owner, super = super, trusted = trusted})
                if super == nil then
                    break
                end
                if not trusted then
                    guessed = true
                end
                f = super
            end
        end
    end
    return layers, floor, guessed
end

--- true when a chain (parsed from `value`) still holds one of the given functions
function ModMuxScan.chainHolds(value, id, containerMod, a, b, c)
    if value == nil then
        return false
    end
    if value == a or value == b or value == c then
        return true
    end
    local layers, floor = ModMuxScan.parse(value, id, containerMod)
    for _, layer in ipairs(layers) do
        if layer.wrapper == a or layer.wrapper == b or layer.wrapper == c or layer.fn == a or layer.fn == b or layer.fn == c
            or (layer.super ~= nil and (layer.super == a or layer.super == b or layer.super == c)) then
            return true
        end
    end
    return floor ~= nil and (floor == a or floor == b or floor == c)
end

--- distinct mod owners of a layer list, innermost (loaded first) first; ModMux and the game left out
function ModMuxScan.modsOf(layers)
    local mods, seen = {}, {}
    for i = #layers, 1, -1 do
        local owner = layers[i].owner
        if ModMuxOrigin.isMod(owner) and owner ~= ModMux.MOD_NAME and not seen[owner] then
            seen[owner] = true
            table.insert(mods, owner)
        end
    end
    return mods
end

----------------------------------------------------------------------------------------------------------------
-- Scanning every class
----------------------------------------------------------------------------------------------------------------

local function isSkippedContainer(name)
    return name == "Utils" or name == "_G" or name:find("^ModMux") ~= nil
end

--- callback(containerName, table, containerMod) for every class table of the game and of every mod
function ModMuxScan.eachContainer(callback)
    local envs = {}
    if type(g_modIsLoaded) == "table" then
        for modName in pairs(g_modIsLoaded) do
            local env = rawget(G, modName)
            if type(env) == "table" and env ~= G then
                envs[modName] = env
            end
        end
    end
    for name, value in pairs(G) do
        if type(name) == "string" and type(value) == "table" and envs[name] == nil and name:find("^%u") ~= nil
            and not isSkippedContainer(name) then
            callback(name, value, nil)
        end
    end
    for modName, env in pairs(envs) do
        if modName ~= ModMux.MOD_NAME then
            for name, value in pairs(env) do
                if type(name) == "string" and type(value) == "table" and name:find("^%u") ~= nil and rawget(G, name) ~= value
                    and not isSkippedContainer(name) then
                    callback(modName .. "/" .. name, value, modName)
                end
            end
        end
    end
end

function ModMuxScan.splitId(id)
    local container, key = id:match("^([^%.]+)%.(.+)$")
    return container, key
end

function ModMuxScan.lookup(id)
    local container, key = ModMuxScan.splitId(id)
    local entry = container ~= nil and ModMuxScan.containers[container] or nil
    if entry == nil then
        return nil, nil, nil
    end
    return entry.table, key, entry.mod
end

ModMuxScan.gameContainers = setmetatable({}, {__mode = "k"})  -- tables that held a game function in any scan

--- The mod a global table belongs to when it is a mod's own class put into the global table: it never held a game
-- function (in any scan) and most of its own functions were written by one mod. Its own functions are then its base,
-- not changes. A game class whose functions a mod replaced is never one of these.
local function dominantOwner(tbl)
    if ModMuxScan.gameContainers[tbl] then
        return nil
    end
    local counts, total = {}, 0
    for _, value in pairs(tbl) do
        if type(value) == "function" then
            local info = ModMuxOrigin.info(value)
            if info.owner == GAME or info.owner == ENGINE then
                ModMuxScan.gameContainers[tbl] = true
                return nil
            end
            if ModMuxScan.kinds[info.signature] == nil and ModMuxScan.recordByWrapper[value] == nil
                and ModMuxScan.transparent[value] == nil then
                counts[info.owner] = (counts[info.owner] or 0) + 1
                total = total + 1
            end
        end
    end
    for owner, count in pairs(counts) do
        if ModMuxOrigin.isMod(owner) and count * 2 > total then
            return owner
        end
    end
    return nil
end

local function makeSlot(id, container, key, tbl, containerMod, value, layers, floor, guessed)
    return {id = id, container = container, key = key, table = tbl, containerMod = containerMod, value = value,
        layers = layers, floor = floor, guessed = guessed, mods = ModMuxScan.modsOf(layers)}
end

function ModMuxScan.scan(label)
    local t0 = clock()
    ModMuxScan.generation = ModMuxScan.generation + 1
    local slots, containers, visited = {}, {}, {}
    local functions, hooked = 0, 0
    local kinds, recordByWrapper, transparent = ModMuxScan.kinds, ModMuxScan.recordByWrapper, ModMuxScan.transparent

    ModMuxScan.eachContainer(function(name, tbl, containerMod)
        if visited[tbl] then
            return
        end
        visited[tbl] = true
        if containerMod == nil then
            containerMod = dominantOwner(tbl)
        end
        containers[name] = {table = tbl, mod = containerMod}
        for key, value in pairs(tbl) do
            if type(key) == "string" and type(value) == "function" then
                functions = functions + 1
                local id = name .. "." .. key
                ModMuxScan.remember(value, id)
                local info = ModMuxOrigin.info(value)
                local owner = info.owner
                local touched = kinds[info.signature] ~= nil or recordByWrapper[value] ~= nil or transparent[value] ~= nil
                    or (owner ~= GAME and owner ~= ENGINE and owner ~= containerMod)
                if touched then
                    local layers, floor, guessed = ModMuxScan.parse(value, id, containerMod)
                    for _, layer in ipairs(layers) do
                        ModMuxScan.remember(layer.wrapper, id)
                        ModMuxScan.remember(layer.fn, id)
                        if recordByWrapper[layer.wrapper] ~= nil and ModMuxScan.seenIn[layer.wrapper] == nil then
                            ModMuxScan.seenIn[layer.wrapper] = id
                        end
                    end
                    if floor ~= nil then
                        ModMuxScan.remember(floor, id)
                        if ModMuxScan.bestFloor[id] == nil then
                            ModMuxScan.bestFloor[id] = floor
                        end
                    end
                    local slot = makeSlot(id, name, key, tbl, containerMod, value, layers, floor, guessed)
                    if #slot.mods > 0 then
                        slots[id] = slot
                        hooked = hooked + 1
                    end
                elseif ModMuxScan.bestFloor[id] == nil then
                    ModMuxScan.bestFloor[id] = value
                end
            end
        end
    end)

    ModMuxScan.slots = slots
    ModMuxScan.containers = containers
    ModMuxScan.scanObjects()
    local ms = (clock() - t0) * 1000
    table.insert(ModMuxScan.scanLog, {label = label, functions = functions, hooked = hooked, ms = ms})
    return functions, hooked, ms
end

--- A change can be put on one object instead of the class (`g_currentMission.hud.drawX = Utils.appendedFunction(...)`).
-- Such a wrapper isn't lost when the class function changes later. The game's g_* objects and their direct fields are
-- searched for recorded wrappers, which are then left out of the lost changes.
function ModMuxScan.scanObjects()
    local recordByWrapper = ModMuxScan.recordByWrapper
    if next(recordByWrapper) == nil then
        return
    end
    local visited = {[G] = true}
    local function look(tbl, depth)
        if visited[tbl] then
            return
        end
        visited[tbl] = true
        for _, value in pairs(tbl) do
            local kind = type(value)
            if kind == "function" then
                if recordByWrapper[value] ~= nil then
                    ModMuxScan.elsewhere[value] = true
                end
            elseif kind == "table" and depth < 1 then
                look(value, depth + 1)
            end
        end
    end
    for name, value in pairs(G) do
        if type(name) == "string" and type(value) == "table" and name:find("^g_") ~= nil then
            look(value, 0)
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Lost changes and conflicts
----------------------------------------------------------------------------------------------------------------

--- Changes a mod made with Utils.*Function that are no longer in the function they were made for.
-- Seen in a scan and gone since: sure. Never seen (made and replaced between two scans): only when the slot no longer
-- holds the function the change was built on either, so a change put on an object instead of the class doesn't count.
function ModMuxScan.findLost()
    local lost = {}
    for _, record in ipairs(ModMuxScan.modRecords or {}) do
        if not record.viaGame and not ModMuxScan.elsewhere[record.wrapper] then
            local id = ModMuxScan.seenIn[record.wrapper]
            local confirmed = id ~= nil
            if id == nil and record.generation < ModMuxScan.lateGeneration then
                id = ModMuxScan.targetOf(record.old)
            end
            local tbl, key, containerMod = nil, nil, nil
            if id ~= nil then
                tbl, key, containerMod = ModMuxScan.lookup(id)
            end
            if tbl ~= nil then
                local value = rawget(tbl, key)
                local holds
                if confirmed then
                    holds = ModMuxScan.chainHolds(value, id, containerMod, record.wrapper, record.new)
                else
                    holds = ModMuxScan.chainHolds(value, id, containerMod, record.wrapper, record.new, record.old)
                end
                if not holds then
                    lost[id] = lost[id] or {}
                    table.insert(lost[id], {record = record, mod = record.mod, kind = record.kind, fn = record.new,
                        confirmed = confirmed})
                end
            end
        end
    end
    return lost
end

--- What kind of fight a slot is (see ModMuxScan.SEVERITY), from its layers outermost first.
function ModMuxScan.classify(layers, lostList)
    if lostList ~= nil and #lostList > 0 then
        return "lost"
    end
    local seenBelow = {}
    -- walk from the inside out; remember which mods sit below each layer
    local below = {}
    for i = #layers, 1, -1 do
        local layer = layers[i]
        local othersBelow = false
        for owner in pairs(below) do
            if owner ~= layer.owner then
                othersBelow = true
                break
            end
        end
        if othersBelow and ModMuxOrigin.isMod(layer.owner) then
            if layer.kind == "replace" and not layer.trusted then
                seenBelow.replaced = true
            elseif layer.kind == "overwrite" or layer.kind == "replace" then
                seenBelow.overwrite = true
            end
        end
        if ModMuxOrigin.isMod(layer.owner) then
            below[layer.owner] = true
        end
    end
    if seenBelow.replaced then
        return "replaced"
    elseif seenBelow.overwrite then
        return "overwrite"
    end
    return "shared"
end

local function addConflict(conflicts, conflict)
    conflict.severity = ModMuxScan.SEVERITY[conflict.kind] or 1
    table.insert(conflicts, conflict)
end

--- All conflicts: class functions (with lost changes) and vehicle / placeable type function chains.
function ModMuxScan.analyze()
    local lost = ModMuxScan.findLost()
    ModMuxScan.lost = lost
    local conflicts = {}

    local ids = {}
    for id in pairs(ModMuxScan.slots) do
        ids[id] = true
    end
    for id in pairs(lost) do
        ids[id] = true
    end
    for id in pairs(ids) do
        local slot = ModMuxScan.slots[id]
        if slot == nil then
            local tbl, key, containerMod = ModMuxScan.lookup(id)
            local value = tbl ~= nil and rawget(tbl, key) or nil
            if value ~= nil then
                local layers, floor, guessed = ModMuxScan.parse(value, id, containerMod)
                slot = makeSlot(id, ModMuxScan.splitId(id), key, tbl, containerMod, value, layers, floor, guessed)
            end
        end
        if slot ~= nil then
            local lostList = lost[id] or {}
            local mods, seen = {}, {}
            for _, owner in ipairs(slot.mods) do
                seen[owner] = true
                table.insert(mods, owner)
            end
            for _, entry in ipairs(lostList) do
                if not seen[entry.mod] then
                    seen[entry.mod] = true
                    table.insert(mods, 1, entry.mod)
                end
            end
            local lostFromOthers = false
            for _, entry in ipairs(lostList) do
                for _, owner in ipairs(slot.mods) do
                    if owner ~= entry.mod then
                        lostFromOthers = true
                    end
                end
            end
            if #mods >= 2 or lostFromOthers then
                local lockReason = ModMuxLevers.lockReason(slot.container, slot.key)
                addConflict(conflicts, {id = id, type = "slot", slot = slot, layers = slot.layers, floor = slot.floor,
                    lost = lostList, mods = mods, kind = ModMuxScan.classify(slot.layers, lostList),
                    category = ModMuxScan.categoryOf(slot.container, slot.key), locked = lockReason ~= nil,
                    lockReason = lockReason})
            end
        end
    end

    for _, conflict in ipairs(ModMuxScan.scanTypes()) do
        addConflict(conflicts, conflict)
    end

    table.sort(conflicts, function(a, b)
        if a.severity ~= b.severity then
            return a.severity > b.severity
        end
        return a.id < b.id
    end)
    ModMuxScan.conflicts = conflicts
    ModMuxScan.conflictById = {}
    for _, conflict in ipairs(conflicts) do
        ModMuxScan.conflictById[conflict.id] = conflict
    end
    return conflicts
end

--- Vehicle and placeable types: the game chains every specialization's overwritten function itself (each gets the
-- previous one as superFunc). Two mods in one chain both run, the outer one decides whether the inner one does.
function ModMuxScan.scanTypes()
    local groups, list = {}, {}
    local managers = {{manager = g_vehicleTypeManager, label = "vehicle"}, {manager = g_placeableTypeManager, label = "placeable"}}
    for _, entry in ipairs(managers) do
        local manager = entry.manager
        local types = nil
        if type(manager) == "table" and manager.getTypes ~= nil then
            types = manager:getTypes()
        end
        if type(types) == "table" then
            for typeKey, typeEntry in pairs(types) do
                local functions = type(typeEntry) == "table" and typeEntry.functions or nil
                if type(functions) == "table" then
                    local typeName = type(typeEntry.name) == "string" and typeEntry.name or tostring(typeKey)
                    for funcName, f in pairs(functions) do
                        if type(f) == "function" and type(funcName) == "string" then
                            local info = ModMuxOrigin.info(f)
                            if ModMuxScan.kinds[info.signature] ~= nil or ModMuxScan.recordByWrapper[f] ~= nil
                                or ModMuxOrigin.isMod(info.owner) then
                                local layers = ModMuxScan.parse(f, nil, nil)
                                -- a specialization's own new function is its base; only overwrites take part
                                local overwrites = {}
                                for _, layer in ipairs(layers) do
                                    if layer.kind ~= "replace" then
                                        table.insert(overwrites, layer)
                                    end
                                end
                                local mods = ModMuxScan.modsOf(overwrites)
                                if #mods >= 2 then
                                    local id = entry.label .. ":" .. funcName .. "|" .. table.concat(mods, "+")
                                    local group = groups[id]
                                    if group == nil then
                                        group = {id = id, type = "types", typeKind = entry.label, key = funcName, mods = mods,
                                            layers = overwrites, types = {}, kind = "types", lost = {}, locked = true,
                                            lockReason = "types", category = ModMuxScan.categoryOf(typeName, funcName)}
                                        groups[id] = group
                                        table.insert(list, group)
                                    end
                                    table.insert(group.types, typeName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, group in ipairs(list) do
        table.sort(group.types)
    end
    return list
end

----------------------------------------------------------------------------------------------------------------
-- Categories ("realms") for the BY CATEGORY view
----------------------------------------------------------------------------------------------------------------

ModMuxScan.CATEGORIES = {
    {id = "wheels", words = {"wheel", "tire", "tyre", "crawler", "friction", "suspension"}},
    {id = "hud", words = {"hud", "display", "gui", "menu", "dialog", "screen", "overlay", "hotspot", "frame", "ingamemap",
        "notification", "help"}},
    {id = "economy", words = {"econom", "price", "money", "finance", "loan", "shop", "store", "sell", "contract", "mission",
        "farm", "bank", "lease"}},
    {id = "weather", words = {"weather", "environment", "season", "rain", "snow", "temperature", "sky", "daytime", "growth"}},
    {id = "ai", words = {"^ai", "helper", "course", "autodrive", "pathfind", "navigation", "traffic", "worker"}},
    {id = "animals", words = {"animal", "husbandry", "livestock", "cow", "pig", "sheep", "chicken", "horse"}},
    {id = "fields", words = {"field", "fruit", "crop", "density", "spray", "sow", "seed", "plough", "plow", "cultivat",
        "mulch", "weed", "harvest", "lime", "fertil", "stone"}},
    {id = "production", words = {"production", "factory", "silo", "storage", "unload", "selling"}},
    {id = "placeables", words = {"placeable", "building", "construct", "placement", "terrain", "landscap"}},
    {id = "player", words = {"player", "character", "handtool", "chainsaw", "camera"}},
    {id = "vehicles", words = {"vehicle", "motor", "drivable", "enterable", "attach", "trailer", "combine", "fill",
        "discharge", "cover", "light", "implement", "tool", "baler", "wrapper", "trailer"}},
    {id = "input", words = {"input", "action", "binding", "keyboard", "mouse", "gamepad"}},
    {id = "network", words = {"event$", "stream", "connection", "server", "client", "network", "sync"}},
}
ModMuxScan.CATEGORY_OTHER = "other"

function ModMuxScan.categoryOf(container, key)
    local class = tostring(container):match("([^/]+)$") or tostring(container)
    for _, text in ipairs({class:lower(), tostring(key):lower()}) do
        for _, category in ipairs(ModMuxScan.CATEGORIES) do
            for _, word in ipairs(category.words) do
                if text:find(word) ~= nil then
                    return category.id
                end
            end
        end
    end
    return ModMuxScan.CATEGORY_OTHER
end

function ModMuxScan.categoryIds()
    local ids = {}
    for _, category in ipairs(ModMuxScan.CATEGORIES) do
        table.insert(ids, category.id)
    end
    table.insert(ids, ModMuxScan.CATEGORY_OTHER)
    return ids
end

ModMuxScan.lateGeneration = math.huge
