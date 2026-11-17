-- ModMux: settling conflicts. Applied once per load, right after the mission has loaded (never while playing).
--
-- A conflict's chain is rebuilt from its parts with the game's own Utils helpers, exactly as if the mods had loaded in
-- another order (or one of them not at all):
--   winner  only the winning mod's changes stay (the others are muted)
--   shared  every change runs, including ones a later mod had thrown away (they go back on top)
--   order   the changes are stacked by rank: the higher a mod ranks, the later (outer) its change, so it has the last word
-- A plain replacement (`X.f = function ...`) can't be taken apart: what it calls is fixed inside it. It stays a block
-- ("barrier") that only changes stacked on top of it can be moved around; removing it needs the original below it.

ModMuxLevers = {}

ModMuxLevers.applied = {}           -- conflict id -> {plan, status}
ModMuxLevers.appliedCount = 0

-- whole classes nobody may touch: loading, saving, menus, network, the mod system itself
ModMuxLevers.LOCKED_CLASSES = {
    Utils = true, Class = true, SpecializationUtil = true, SpecializationManager = true, TypeManager = true,
    VehicleTypeManager = true, PlaceableTypeManager = true, XMLFile = true, XMLSchema = true, XMLValueType = true,
    ModManager = true, I18N = true, Logging = true, Mission00 = true, BaseMission = true, FSBaseMission = true,
    MissionInfo = true, FSMissionInfo = true, FSCareerMissionInfo = true, SavegameController = true, Gui = true,
    GuiElement = true, FocusManager = true, InputBinding = true, ConnectionManager = true, Connection = true,
    NetworkNode = true, Server = true, Client = true, MessageCenter = true, StartupScreen = true, MainScreen = true,
    CareerScreen = true, ModSelectionScreen = true, InGameMenu = true, TabbedMenu = true, TabbedMenuFrameElement = true,
    ItemSystem = true, VehicleSystem = true, PlaceableSystem = true, Event = true, EventIds = true,
}

--- nil when levers may touch this function, else why not: "core", "load", "save" or "network"
function ModMuxLevers.lockReason(container, key)
    local class = tostring(container):match("([^/]+)$") or tostring(container)
    if ModMuxLevers.LOCKED_CLASSES[class] then
        return "core"
    end
    local k = tostring(key):lower()
    if k:find("stream") ~= nil or class:find("Event$") ~= nil then
        return "network"
    end
    if k:find("^save") ~= nil or k:find("^onsave") ~= nil or k:find("xmlfile$") ~= nil or k:find("savegame") ~= nil then
        return "save"
    end
    if k == "new" or k:find("^load") ~= nil or k:find("^onload") ~= nil or k:find("^postload") ~= nil
        or k:find("^onpostload") ~= nil or k:find("^onpreload") ~= nil or k:find("^finalize") ~= nil
        or k:find("^onfinalize") ~= nil or k:find("^init") ~= nil or k:find("^register") ~= nil
        or k:find("^delete") ~= nil or k:find("^ondelete") ~= nil or k:find("^prerequisites") ~= nil then
        return "load"
    end
    return nil
end

----------------------------------------------------------------------------------------------------------------
-- Plans
----------------------------------------------------------------------------------------------------------------

local function indexOf(list, value)
    for i, entry in ipairs(list or {}) do
        if entry == value then
            return i
        end
    end
    return nil
end

--- priority of a mod in a rank list (highest first): bigger wins, 0 = not ranked
function ModMuxLevers.priority(rank, mod)
    local i = indexOf(rank, mod)
    if i == nil then
        return 0
    end
    return #rank - i + 1
end

local function rankCovers(rank, mods)
    if rank == nil or #rank == 0 then
        return false
    end
    for _, mod in ipairs(mods) do
        if indexOf(rank, mod) ~= nil then
            return true
        end
    end
    return false
end

--- What a setup wants for one conflict: {mode = default|winner|shared|order, mod, rank, source}
function ModMuxLevers.planFor(conflict, setup)
    if conflict.type ~= "slot" then
        return {mode = "default", source = "types"}
    end
    if conflict.locked then
        return {mode = "default", source = "locked"}
    end
    local pick = setup.picks[conflict.id]
    if pick ~= nil and pick.mode == "winner" and pick.mod ~= nil and indexOf(conflict.mods, pick.mod) ~= nil then
        return {mode = "winner", mod = pick.mod, source = "pick"}
    elseif pick ~= nil and pick.mode == "shared" then
        return {mode = "shared", source = "pick"}
    end
    local categoryRank = setup.categoryRank[conflict.category]
    if rankCovers(categoryRank, conflict.mods) then
        return {mode = "order", rank = categoryRank, source = "category"}
    end
    if rankCovers(setup.rank, conflict.mods) then
        return {mode = "order", rank = setup.rank, source = "rank"}
    end
    return {mode = "default", source = "none"}
end

function ModMuxLevers.samePlan(a, b)
    if a.mode ~= b.mode or a.mod ~= b.mod then
        return false
    end
    if a.mode == "order" then
        return table.concat(a.rank or {}, "\n") == table.concat(b.rank or {}, "\n")
    end
    return true
end

----------------------------------------------------------------------------------------------------------------
-- Rebuilding a chain
----------------------------------------------------------------------------------------------------------------

--- the parts of a conflict, innermost (oldest) first; changes thrown away by a later mod are marked lost
function ModMuxLevers.units(conflict)
    local current, lost = {}, {}
    for i = #conflict.layers, 1, -1 do
        local layer = conflict.layers[i]
        table.insert(current, {kind = layer.kind, fn = layer.fn, owner = layer.owner, super = layer.super,
            trusted = layer.trusted, natural = #current + 1})
    end
    for _, entry in ipairs(conflict.lost or {}) do
        table.insert(lost, {kind = entry.kind, fn = entry.fn, owner = entry.mod, lost = true, natural = 1000 + #lost})
    end
    return current, lost
end

--- Builds the function a plan asks for. Returns func or nil, status:
--   ok, partial (some muted parts sit inside a plain replacement and stay), same (nothing to change),
--   noBase (the game's original is unknown, a plain replacement can't be removed), unsafe (guessed chain)
function ModMuxLevers.build(conflict, plan)
    local current, lost = ModMuxLevers.units(conflict)
    local isMod = ModMuxOrigin.isMod

    local function keep(unit)
        if plan.mode == "winner" then
            return not isMod(unit.owner) or unit.owner == plan.mod
        end
        return true
    end
    local function priority(owner)
        return ModMuxLevers.priority(plan.rank, owner)
    end

    -- the outermost plain replacement that stays is the barrier; everything inside it stays as it is
    local barrier = nil
    for i = #current, 1, -1 do
        if current[i].kind == "replace" and keep(current[i]) then
            barrier = i
            break
        end
    end

    local base, start, partial = nil, 1, false
    if barrier ~= nil then
        base = current[barrier].fn
        start = barrier + 1
        for i = 1, barrier - 1 do
            if not keep(current[i]) then
                partial = true
            end
        end
    else
        for _, unit in ipairs(current) do
            if unit.kind == "replace" and unit.super ~= nil and not unit.trusted then
                return nil, "unsafe"
            end
        end
        base = conflict.floor or ModMuxScan.bestFloor[conflict.id]
        if base == nil then
            return nil, "noBase"
        end
    end

    -- the mod that probably threw the lost changes away: the strongest plain replacement now in the chain
    local replacerPriority = 0
    for _, unit in ipairs(current) do
        if isMod(unit.owner) and (unit.kind == "replace" or replacerPriority == 0) then
            replacerPriority = math.max(replacerPriority, priority(unit.owner))
        end
    end

    local rest, natural = {}, {}
    for i = start, #current do
        local unit = current[i]
        if unit.kind ~= "replace" then
            table.insert(natural, unit)
            if keep(unit) then
                table.insert(rest, unit)
            end
        end
    end
    local broughtBack = 0
    for _, unit in ipairs(lost) do
        local wanted = plan.mode == "shared" or (plan.mode == "winner" and unit.owner == plan.mod)
            or (plan.mode == "order" and priority(unit.owner) > replacerPriority)
        if wanted then
            table.insert(rest, unit)
            broughtBack = broughtBack + 1
        end
    end

    if plan.mode == "order" then
        table.sort(rest, function(a, b)
            local pa, pb = priority(a.owner), priority(b.owner)
            if pa ~= pb then
                return pa < pb
            end
            return a.natural < b.natural
        end)
    end

    -- nothing to do when the result is the chain as it is
    if broughtBack == 0 and #rest == #natural and (barrier ~= nil or conflict.floor ~= nil) then
        local same = true
        for i, unit in ipairs(rest) do
            if natural[i] ~= unit then
                same = false
                break
            end
        end
        local droppedReplace = false
        for i = start, #current do
            if current[i].kind == "replace" then
                droppedReplace = true
            end
        end
        if same and not droppedReplace then
            return nil, "same"
        end
    end

    local f = base
    for _, unit in ipairs(rest) do
        local helper = ModMuxScan.original[unit.kind]
        if helper == nil then
            return nil, "unsafe"
        end
        f = helper(f, unit.fn)
    end
    return f, partial and "partial" or "ok"
end

--- Applies a setup to every conflict it has a plan for. Returns how many functions were rebuilt.
function ModMuxLevers.applyAll(conflicts, setup)
    ModMuxLevers.applied = {}
    local count = 0
    for _, conflict in ipairs(conflicts) do
        local plan = ModMuxLevers.planFor(conflict, setup)
        if plan.mode ~= "default" then
            local f, status = ModMuxLevers.build(conflict, plan)
            if f ~= nil then
                conflict.slot.table[conflict.slot.key] = f
                count = count + 1
                Logging.info("%s %s: %s (%s)", ModMux.TAG, conflict.id, ModMuxLevers.planText(plan), status)
            elseif status ~= "same" then
                Logging.warning("%s %s: %s not possible (%s), left as it was", ModMux.TAG, conflict.id,
                    ModMuxLevers.planText(plan), status)
            end
            ModMuxLevers.applied[conflict.id] = {plan = plan, status = f ~= nil and status or (status or "failed"),
                done = f ~= nil}
        end
    end
    ModMuxLevers.appliedCount = count
    return count
end

--- English one-liner for the log
function ModMuxLevers.planText(plan)
    if plan.mode == "winner" then
        return "winner " .. tostring(plan.mod)
    elseif plan.mode == "shared" then
        return "shared chain"
    elseif plan.mode == "order" then
        return "order by " .. tostring(plan.source)
    end
    return "load order"
end
