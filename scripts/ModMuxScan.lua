-- ModMux: finds the functions several mods change, and what became of each change.
--
-- How a mod changes a game function: `Vehicle.update = Utils.appendedFunction(Vehicle.update, myUpdate)` (or prepended /
-- overwritten), which builds a small wrapper around the old function, or a plain `Vehicle.update = function ...` that may
-- or may not call the old one. The game hides what is inside a function, so ModMux watches the changes being made:
--
-- 1. install(): ModMux loads first (its zip name sorts first) and puts a recorder around the Utils helpers. Every
--    change made after that is recorded: the old function, the mod's function, the wrapper, and the mod (the
--    environment the mod's function was written in). The mod's function is handed on inside a tiny probe that notes
--    when it runs. Changes made by mods that loaded before ModMux can't be seen.
-- 2. scan(): walks every class table (and every mod's own classes) and takes each changed function apart into its
--    layers, as far as the recorded wrappers go. A plain replacement is a closed box: what is under it is unknown.
--    Runs at ModMux's load, at its loadMap, after every mod's loadMap and when the mission has loaded.
-- 3. analyze(): lost changes, changes hidden under a plain replacement, conflicts (two or more mods on one function),
--    vehicle / placeable type chains.
-- 4. While playing: for a change hidden under a plain replacement, ModMux counts how often the function runs. Once it
--    has run a few times, the probe tells whether the change still runs ("runs") or never does ("blocked", lost). The
--    verdict is kept for the next loads (evidence.xml), so the levers can act on it.

ModMuxScan = {}

local G = ModMuxOrigin.G
ModMuxScan.G = G

ModMuxScan.UTILS_NAMES = {append = "appendedFunction", prepend = "prependedFunction", overwrite = "overwrittenFunction"}
ModMuxScan.KINDS = {"append", "prepend", "overwrite"}

ModMuxScan.original = {}            -- kind -> the Utils helper as it was before the recorder
ModMuxScan.records = {}             -- every recorded change
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
ModMuxScan.listenerRecords = {}     -- addModEventListener calls seen: {listener, mod}
ModMuxScan.installed = false
ModMuxScan.loading = true           -- mods are still loading their scripts (until ModMux's loadMap)

ModMuxScan.verdicts = {}            -- verdict key -> "runs" | "blocked" (this load and earlier ones, evidence.xml)
ModMuxScan.verdictsChanged = false
ModMuxScan.EVIDENCE_CALLS = 20      -- runs of a function before a hidden change that never ran counts as blocked

ModMuxScan.SEVERITY = {lost = 3, replaced = 2, overwrite = 2, shared = 1, types = 1}

local GAME = ModMuxOrigin.GAME

local function clock()
    if getTimeSec ~= nil then
        return getTimeSec()
    end
    return os.clock()
end

local function isMod(owner)
    return ModMuxOrigin.isMod(owner)
end

----------------------------------------------------------------------------------------------------------------
-- The recorder
----------------------------------------------------------------------------------------------------------------

local function makeRecorder(kind, helper)
    local own = ModMuxOrigin.ownEnv
    return function(oldFunc, newFunc)
        if type(oldFunc) ~= "function" or type(newFunc) ~= "function" then
            return helper(oldFunc, newFunc)
        end
        local env = ModMuxOrigin.envOf(newFunc)
        local loadingMod = ModMuxScan.loading and ModMuxOrigin.loadingMod() or nil
        local record = {kind = kind, old = oldFunc, new = newFunc, env = env, loadingMod = loadingMod,
            generation = ModMuxScan.generation, ran = false}
        local passed = newFunc
        if ModMuxOrigin.hasFenv and env ~= G and env ~= own then
            -- a mod's change: noted once it runs (one extra call, nothing else)
            passed = function(...)
                if not record.ran then
                    record.ran = true
                end
                return newFunc(...)
            end
        end
        local wrapper = helper(oldFunc, passed)
        if type(wrapper) == "function" and wrapper ~= passed then
            record.wrapper = wrapper
            record.seq = #ModMuxScan.records + 1
            table.insert(ModMuxScan.records, record)
            ModMuxScan.recordByWrapper[wrapper] = record
            if loadingMod ~= nil then
                ModMuxOrigin.learnEnv(env, loadingMod)
            end
        end
        return wrapper
    end
end

local LISTENER_FUNCTIONS = {"loadMap", "update", "draw", "updateTick", "deleteMap", "mouseEvent", "keyEvent"}

--- Puts the recorder around the Utils helpers and addModEventListener (in the game's global table, where every mod
-- finds them). Idempotent.
function ModMuxScan.install()
    if ModMuxScan.installed or Utils == nil then
        return
    end
    ModMuxScan.installed = true
    for _, kind in ipairs(ModMuxScan.KINDS) do
        local name = ModMuxScan.UTILS_NAMES[kind]
        local helper = Utils[name]
        if type(helper) == "function" then
            ModMuxScan.original[kind] = helper
            local recorder = makeRecorder(kind, helper)
            ModMuxScan.transparent[recorder] = helper
            Utils[name] = recorder
        end
    end

    local addListener = rawget(G, "addModEventListener")
    if type(addListener) == "function" then
        local recorder = function(listener, ...)
            if type(listener) == "table" then
                local mod = ModMuxScan.loading and ModMuxOrigin.loadingMod() or nil
                table.insert(ModMuxScan.listenerRecords, {listener = listener, mod = mod})
                if mod ~= nil then
                    for _, name in ipairs(LISTENER_FUNCTIONS) do
                        ModMuxOrigin.learnEnv(ModMuxOrigin.envOf(rawget(listener, name)), mod)
                    end
                end
            end
            return addListener(listener, ...)
        end
        ModMuxScan.transparent[recorder] = addListener
        rawset(G, "addModEventListener", recorder)
    end
end

--- Which mod made each record (after the mod list is complete). Records of the game itself stay known for parsing.
function ModMuxScan.resolveRecords()
    local kept = {}
    ModMuxScan.recordByWrapper = {}
    for _, record in ipairs(ModMuxScan.records) do
        local owner = ModMuxOrigin.ofEnv(record.env)
        if owner == ModMuxOrigin.UNKNOWN and isMod(record.loadingMod) then
            owner = record.loadingMod
        end
        record.mod = owner
        if isMod(owner) and owner ~= ModMuxOrigin.OWN_NAME then
            table.insert(kept, record)
        end
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
-- Taking one function apart into layers
----------------------------------------------------------------------------------------------------------------

--- Layers of a function, outermost first, and the game's function at the bottom (floor). The walk follows the recorded
-- wrappers; it stops at a plain replacement by a mod (a closed box: kind "replace", the last layer, floor nil).
-- layer = {kind = append|prepend|overwrite|replace, fn, wrapper, owner, record}
function ModMuxScan.parse(f, id, containerMod)
    local layers, floor = {}, nil
    local guard = 0
    while type(f) == "function" and guard < 200 do
        guard = guard + 1
        local inner = ModMuxScan.transparent[f]
        if inner ~= nil then
            f = inner
        else
            local record = ModMuxScan.recordByWrapper[f]
            if record ~= nil then
                local owner = record.mod or ModMuxOrigin.ofFunction(record.new)
                if owner ~= ModMuxOrigin.OWN_NAME then
                    table.insert(layers, {kind = record.kind, fn = record.new, wrapper = f, owner = owner, record = record})
                end
                f = record.old
            else
                local owner = ModMuxOrigin.ofFunction(f)
                if not isMod(owner) or owner == containerMod or owner == ModMuxOrigin.OWN_NAME then
                    floor = f
                else
                    table.insert(layers, {kind = "replace", fn = f, wrapper = f, owner = owner})
                end
                break
            end
        end
    end
    return layers, floor
end

--- Whether a chain (parsed from `value`) still holds one of the given functions, whether it ends in a closed plain
-- replacement, and whose. Returns holds, opaque, replacer.
function ModMuxScan.chainState(value, id, containerMod, a, b, c)
    if value == nil then
        return false, false, nil
    end
    if value == a or value == b or value == c then
        return true, false, nil
    end
    local layers, floor = ModMuxScan.parse(value, id, containerMod)
    for _, layer in ipairs(layers) do
        if layer.wrapper == a or layer.wrapper == b or layer.wrapper == c or layer.fn == a or layer.fn == b or layer.fn == c then
            return true, false, nil
        end
    end
    if floor ~= nil then
        return floor == a or floor == b or floor == c, false, nil
    end
    local last = layers[#layers]
    if last ~= nil and last.kind == "replace" then
        return false, true, last.owner
    end
    return false, false, nil
end

--- distinct mod owners of a layer list, innermost (loaded first) first; ModMux and the game left out
function ModMuxScan.modsOf(layers)
    local mods, seen = {}, {}
    for i = #layers, 1, -1 do
        local owner = layers[i].owner
        if isMod(owner) and owner ~= ModMuxOrigin.OWN_NAME and not seen[owner] then
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
    for modName, env in pairs(ModMuxOrigin.modEnvs) do
        envs[env] = modName
    end
    for name, value in pairs(G) do
        if type(name) == "string" and type(value) == "table" and envs[value] == nil and name:find("^%u") ~= nil
            and not isSkippedContainer(name) then
            callback(name, value, nil)
        end
    end
    for env, modName in pairs(envs) do
        if modName ~= ModMuxOrigin.OWN_NAME then
            for name, value in pairs(env) do
                if type(name) == "string" and type(value) == "table" and name:find("^%u") ~= nil and rawget(G, name) ~= value
                    and envs[value] == nil and not isSkippedContainer(name) then
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

--- The mod a global table belongs to when it is a mod's own class put into the game's global table: it never held a
-- game function (in any scan) and most of its own functions were written by one mod. Its own functions are then its
-- base, not changes. A game class whose functions a mod replaced is never one of these.
local function dominantOwner(tbl)
    if ModMuxScan.gameContainers[tbl] then
        return nil
    end
    local counts, total = {}, 0
    for _, value in pairs(tbl) do
        if type(value) == "function" then
            local owner = ModMuxOrigin.ofFunction(value)
            if owner == GAME then
                ModMuxScan.gameContainers[tbl] = true
                return nil
            end
            if ModMuxScan.recordByWrapper[value] == nil and ModMuxScan.transparent[value] == nil then
                counts[owner] = (counts[owner] or 0) + 1
                total = total + 1
            end
        end
    end
    for owner, count in pairs(counts) do
        if isMod(owner) and count * 2 > total then
            return owner
        end
    end
    return nil
end

local function makeSlot(id, container, key, tbl, containerMod, value, layers, floor)
    return {id = id, container = container, key = key, table = tbl, containerMod = containerMod, value = value,
        layers = layers, floor = floor, mods = ModMuxScan.modsOf(layers)}
end

function ModMuxScan.scan(label)
    local t0 = clock()
    ModMuxScan.generation = ModMuxScan.generation + 1
    local slots, containers, visited = {}, {}, {}
    local functions, hooked = 0, 0
    local recordByWrapper, transparent = ModMuxScan.recordByWrapper, ModMuxScan.transparent
    local own = ModMuxOrigin.OWN_NAME

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
                local touched = recordByWrapper[value] ~= nil or transparent[value] ~= nil
                if not touched then
                    local owner = ModMuxOrigin.ofFunction(value)
                    touched = isMod(owner) and owner ~= containerMod and owner ~= own
                end
                if touched then
                    local layers, floor = ModMuxScan.parse(value, id, containerMod)
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
                    local slot = makeSlot(id, name, key, tbl, containerMod, value, layers, floor)
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
-- Lost and hidden changes, conflicts
----------------------------------------------------------------------------------------------------------------

function ModMuxScan.verdictKey(id, entry)
    return string.format("%s|%s|%s|%s", id, tostring(entry.mod), tostring(entry.kind), tostring(entry.replacer))
end

--- Changes a mod made with Utils.*Function that are no longer visible in the function they were made for:
--   lost[id]    the chain is open all the way down and the change isn't in it (state "lost")
--   hidden[id]  a mod's plain replacement sits on top: the change may still run inside it. State "hidden" until the
--               function has run a few times ("runs" or, as "lost", blocked); a verdict from an earlier load counts.
-- Seen in a scan and gone since: sure. Never seen (made and replaced between two scans): only when the slot no longer
-- holds the function the change was built on either, so a change put on an object instead of the class doesn't count.
function ModMuxScan.findLost()
    local lost, hidden = {}, {}
    for _, record in ipairs(ModMuxScan.modRecords or {}) do
        if not record.inTypes and not ModMuxScan.elsewhere[record.wrapper] then
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
                local holds, opaque, replacer
                if confirmed then
                    holds, opaque, replacer = ModMuxScan.chainState(value, id, containerMod, record.wrapper, record.new)
                else
                    holds, opaque, replacer = ModMuxScan.chainState(value, id, containerMod, record.wrapper, record.new, record.old)
                end
                if not holds then
                    local entry = {record = record, mod = record.mod, kind = record.kind, fn = record.new, confirmed = confirmed}
                    if opaque then
                        entry.replacer = replacer
                        entry.key = ModMuxScan.verdictKey(id, entry)
                        entry.verdict = ModMuxScan.verdicts[entry.key]
                        entry.state = (entry.verdict == "blocked" and "lost") or (entry.verdict == "runs" and "runs") or "hidden"
                        hidden[id] = hidden[id] or {}
                        table.insert(hidden[id], entry)
                    else
                        entry.state = "lost"
                        lost[id] = lost[id] or {}
                        table.insert(lost[id], entry)
                    end
                end
            end
        end
    end
    return lost, hidden
end

--- What kind of fight a slot is (see ModMuxScan.SEVERITY), from its layers outermost first and its lost / hidden
-- changes (hidden ones sit under the innermost layer, a plain replacement).
function ModMuxScan.classify(layers, lostList, hiddenList)
    if lostList ~= nil and #lostList > 0 then
        return "lost"
    end
    local below, unknown = {}, false
    for _, entry in ipairs(hiddenList or {}) do
        below[entry.mod] = true
        if entry.state == "hidden" then
            unknown = true
        end
    end
    local result = "shared"
    for i = #layers, 1, -1 do
        local layer = layers[i]
        local othersBelow = false
        for owner in pairs(below) do
            if owner ~= layer.owner then
                othersBelow = true
                break
            end
        end
        if othersBelow and isMod(layer.owner) then
            if layer.kind == "replace" then
                if unknown then
                    return "replaced"
                end
                result = "overwrite"
            elseif layer.kind == "overwrite" then
                result = "overwrite"
            end
        end
        if isMod(layer.owner) then
            below[layer.owner] = true
        end
    end
    return result
end

--- Sorts a conflict's changes into lost / hidden by their state, then its kind and severity.
function ModMuxScan.reshape(conflict)
    local lost, hidden = {}, {}
    for _, entry in ipairs(conflict.entries) do
        if entry.state == "lost" then
            table.insert(lost, entry)
        else
            table.insert(hidden, entry)
        end
    end
    conflict.lost, conflict.hidden = lost, hidden
    conflict.kind = ModMuxScan.classify(conflict.layers, lost, hidden)
    conflict.severity = ModMuxScan.SEVERITY[conflict.kind] or 1
end

local function sortConflicts(conflicts)
    table.sort(conflicts, function(a, b)
        if a.severity ~= b.severity then
            return a.severity > b.severity
        end
        return a.id < b.id
    end)
end

--- All conflicts: class functions (with lost and hidden changes) and vehicle / placeable type function chains.
function ModMuxScan.analyze()
    local typeConflicts = ModMuxScan.scanTypes()
    local lost, hidden = ModMuxScan.findLost()
    ModMuxScan.lost = lost
    local conflicts = {}

    local ids = {}
    for id in pairs(ModMuxScan.slots) do
        ids[id] = true
    end
    for id in pairs(lost) do
        ids[id] = true
    end
    for id in pairs(hidden) do
        ids[id] = true
    end
    for id in pairs(ids) do
        local slot = ModMuxScan.slots[id]
        if slot == nil then
            local tbl, key, containerMod = ModMuxScan.lookup(id)
            local value = tbl ~= nil and rawget(tbl, key) or nil
            if value ~= nil then
                local layers, floor = ModMuxScan.parse(value, id, containerMod)
                slot = makeSlot(id, ModMuxScan.splitId(id), key, tbl, containerMod, value, layers, floor)
            end
        end
        if slot ~= nil then
            local entries = {}
            for _, entry in ipairs(lost[id] or {}) do
                table.insert(entries, entry)
            end
            for _, entry in ipairs(hidden[id] or {}) do
                table.insert(entries, entry)
            end
            local mods, seen = {}, {}
            for _, owner in ipairs(slot.mods) do
                seen[owner] = true
                table.insert(mods, owner)
            end
            local fromOthers = false
            for _, entry in ipairs(entries) do
                if not seen[entry.mod] then
                    seen[entry.mod] = true
                    table.insert(mods, 1, entry.mod)
                end
                for _, owner in ipairs(slot.mods) do
                    if owner ~= entry.mod then
                        fromOthers = true
                    end
                end
            end
            if #mods >= 2 or fromOthers then
                local lockReason = ModMuxLevers.lockReason(slot.container, slot.key)
                local conflict = {id = id, type = "slot", slot = slot, layers = slot.layers, floor = slot.floor,
                    entries = entries, mods = mods, category = ModMuxScan.categoryOf(slot.container, slot.key),
                    locked = lockReason ~= nil, lockReason = lockReason}
                ModMuxScan.reshape(conflict)
                table.insert(conflicts, conflict)
            end
        end
    end

    for _, conflict in ipairs(typeConflicts) do
        conflict.severity = ModMuxScan.SEVERITY[conflict.kind] or 1
        table.insert(conflicts, conflict)
    end

    sortConflicts(conflicts)
    ModMuxScan.conflicts = conflicts
    ModMuxScan.conflictById = {}
    for _, conflict in ipairs(conflicts) do
        ModMuxScan.conflictById[conflict.id] = conflict
    end
    return conflicts
end

--- Vehicle and placeable types: the game chains every specialization's overwritten function itself (each gets the
-- previous one as superFunc). Two mods in one chain both run, the outer one decides whether the inner one does.
-- The records of these chains are marked: they are the game's doing, never lost changes.
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
                        if type(f) == "function" and type(funcName) == "string"
                            and (ModMuxScan.recordByWrapper[f] ~= nil or isMod(ModMuxOrigin.ofFunction(f))) then
                            local layers = ModMuxScan.parse(f, nil, nil)
                            -- a specialization's own new function is its base; only overwrites take part
                            local overwrites = {}
                            for _, layer in ipairs(layers) do
                                if layer.record ~= nil then
                                    layer.record.inTypes = true
                                end
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
                                        layers = overwrites, types = {}, kind = "types", lost = {}, hidden = {}, entries = {},
                                        locked = true, lockReason = "types", category = ModMuxScan.categoryOf(typeName, funcName)}
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
    for _, group in ipairs(list) do
        table.sort(group.types)
    end
    return list
end

----------------------------------------------------------------------------------------------------------------
-- Evidence while playing: does a change hidden under a plain replacement still run?
----------------------------------------------------------------------------------------------------------------

--- After the levers: every conflict with hidden changes (and blocked ones from earlier loads) gets a counter around
-- its function, and the probes start from zero. Conflicts whose chain a lever rebuilt are left out.
function ModMuxScan.startEvidence()
    local watched = 0
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        local applied = ModMuxLevers.applied[conflict.id]
        if conflict.type == "slot" and not (applied ~= nil and applied.done) then
            local entries = {}
            for _, entry in ipairs(conflict.entries) do
                if entry.replacer ~= nil then
                    entry.record.ran = false
                    table.insert(entries, entry)
                end
            end
            local slot = conflict.slot
            local inner = rawget(slot.table, slot.key)
            if #entries > 0 and type(inner) == "function" then
                local counts = {n = 0}
                local counter = function(...)
                    counts.n = counts.n + 1
                    return inner(...)
                end
                ModMuxScan.transparent[counter] = inner
                slot.table[slot.key] = counter
                conflict.watch = {counts = counts, entries = entries}
                watched = watched + 1
            end
        end
    end
    return watched
end

--- Reads the probes. Returns true when a verdict changed (the conflicts are sorted again).
function ModMuxScan.updateEvidence()
    local changed = false
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        local watch = conflict.watch
        if watch ~= nil then
            local reshape = false
            for _, entry in ipairs(watch.entries) do
                local verdict = nil
                if entry.record.ran then
                    verdict = "runs"
                elseif watch.counts.n >= ModMuxScan.EVIDENCE_CALLS then
                    verdict = "blocked"
                end
                entry.calls = watch.counts.n
                if verdict ~= nil then
                    entry.seenNow = true
                    if verdict ~= entry.verdict then
                        entry.verdict = verdict
                        ModMuxScan.verdicts[entry.key] = verdict
                        ModMuxScan.verdictsChanged = true
                        changed = true
                    end
                    local state = verdict == "blocked" and "lost" or "runs"
                    if state ~= entry.state then
                        entry.state = state
                        entry.confirmed = true
                        reshape = true
                        changed = true
                    end
                end
            end
            if reshape then
                ModMuxScan.reshape(conflict)
            end
        end
    end
    if changed then
        sortConflicts(ModMuxScan.conflicts)
    end
    return changed
end

function ModMuxScan.loadVerdicts(path)
    ModMuxScan.verdicts = {}
    if not fileExists(path) then
        return
    end
    local xml = loadXMLFile("ModMuxEvidence", path)
    if xml == nil or xml == 0 then
        return
    end
    local i = 0
    while true do
        local key = string.format("modMuxEvidence.item(%d)", i)
        local id = getXMLString(xml, key .. "#key")
        if id == nil then
            break
        end
        local verdict = getXMLString(xml, key .. "#verdict")
        if verdict == "runs" or verdict == "blocked" then
            ModMuxScan.verdicts[id] = verdict
        end
        i = i + 1
    end
    delete(xml)
end

function ModMuxScan.saveVerdicts(path)
    local xml = createXMLFile("ModMuxEvidence", path, "modMuxEvidence")
    if xml == nil or xml == 0 then
        return false
    end
    local keys = {}
    for key in pairs(ModMuxScan.verdicts) do
        table.insert(keys, key)
    end
    table.sort(keys)
    for i, key in ipairs(keys) do
        local node = string.format("modMuxEvidence.item(%d)", i - 1)
        setXMLString(xml, node .. "#key", key)
        setXMLString(xml, node .. "#verdict", ModMuxScan.verdicts[key])
    end
    saveXMLFile(xml)
    delete(xml)
    ModMuxScan.verdictsChanged = false
    return true
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
