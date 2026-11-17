-- ModMux: what every mod costs per frame, parking a mod's per-frame work, and the HUD overlap scan.
--
-- Measured: each mod's event listener (update, updateTick, draw) and its vehicle / placeable specializations' per-frame
-- events (onUpdate, onUpdateTick, onDraw, ...). Each is wrapped once at load with a timer (two clock reads per call).
-- Parking (restart-gated) swaps a parked mod's listener update / updateTick / draw for an empty function. Its
-- specializations keep running: a parked mod's own tractor must still drive.

ModMuxPerf = {}

ModMuxPerf.LISTENER_FUNCTIONS = {"update", "updateTick", "draw"}
ModMuxPerf.SPEC_EVENTS = {"onUpdate", "onUpdateTick", "onPostUpdate", "onPostUpdateTick", "onUpdateEnd", "onDraw"}
ModMuxPerf.SMOOTHING = 0.05

ModMuxPerf.stats = {}              -- mod -> {ms, peak, last, acc, functions, listeners}
ModMuxPerf.listenersByMod = {}     -- mod -> {{listener, parkable}}
ModMuxPerf.parked = {}             -- mod -> number of functions parked this session
ModMuxPerf.installed = false
ModMuxPerf.current = nil           -- the mod whose code runs right now (inside a timed call)
ModMuxPerf.frameMs = 0             -- smoothed real frame time
ModMuxPerf.lastFrameAt = nil
ModMuxPerf.frames = 0
ModMuxPerf.hud = nil               -- running HUD scan

local G = ModMuxScan.G

local function clock()
    if getTimeSec ~= nil then
        return getTimeSec()
    end
    return os.clock()
end

local function noop()
end
ModMuxPerf.noop = noop

function ModMuxPerf.getStats(mod)
    local stats = ModMuxPerf.stats[mod]
    if stats == nil then
        stats = {ms = 0, peak = 0, last = 0, acc = 0, functions = 0, listeners = 0}
        ModMuxPerf.stats[mod] = stats
    end
    return stats
end

----------------------------------------------------------------------------------------------------------------
-- Finding every mod's event listeners
----------------------------------------------------------------------------------------------------------------

local OWNER_FUNCTIONS = {"update", "draw", "updateTick", "loadMap", "deleteMap", "mouseEvent", "keyEvent"}

local function ownerOf(listener, mod)
    if ModMuxOrigin.isMod(mod) then
        return mod
    end
    for _, name in ipairs(OWNER_FUNCTIONS) do
        local f = rawget(listener, name)
        if type(f) == "function" then
            local o = ModMuxOrigin.ofFunction(ModMuxScan.transparent[f] or f)
            if ModMuxOrigin.isMod(o) then
                return o
            end
        end
    end
    return nil
end

local function hasPerFrame(tbl)
    for _, name in ipairs(ModMuxPerf.LISTENER_FUNCTIONS) do
        if type(rawget(tbl, name)) == "function" then
            return true
        end
    end
    return false
end

--- mod -> list of {listener, parkable}. Registered listeners (seen by ModMux or in the game's list) can be parked;
-- tables that only look like listeners (mods loaded before ModMux) are measured but not parked unless clearly one.
function ModMuxPerf.findListeners()
    local byMod, seen = {}, {}
    local function add(listener, owner, parkable)
        if seen[listener] or not ModMuxOrigin.isMod(owner) or owner == ModMux.MOD_NAME then
            return
        end
        seen[listener] = true
        byMod[owner] = byMod[owner] or {}
        table.insert(byMod[owner], {listener = listener, parkable = parkable})
    end
    for _, record in ipairs(ModMuxScan.listenerRecords) do
        add(record.listener, ownerOf(record.listener, record.mod), true)
    end
    local list = rawget(G, "g_modEventListeners")
    if type(list) == "table" then
        for _, listener in ipairs(list) do
            if type(listener) == "table" then
                add(listener, ownerOf(listener), true)
            end
        end
    end
    for modName, env in pairs(ModMuxOrigin.modEnvs) do
        if type(env) == "table" and env ~= G then
            for _, value in pairs(env) do
                if type(value) == "table" and not seen[value] and hasPerFrame(value)
                    and (type(rawget(value, "loadMap")) == "function" or type(rawget(value, "deleteMap")) == "function") then
                    local owner = ownerOf(value)
                    if owner == modName then
                        add(value, owner, type(rawget(value, "loadMap")) == "function" and rawget(value, "new") == nil)
                    end
                end
            end
        end
    end
    ModMuxPerf.listenersByMod = byMod
    return byMod
end

----------------------------------------------------------------------------------------------------------------
-- Parking
----------------------------------------------------------------------------------------------------------------

function ModMuxPerf.park(mod)
    local count = 0
    for _, entry in ipairs(ModMuxPerf.listenersByMod[mod] or {}) do
        if entry.parkable then
            for _, name in ipairs(ModMuxPerf.LISTENER_FUNCTIONS) do
                if type(rawget(entry.listener, name)) == "function" then
                    entry.listener[name] = noop
                    count = count + 1
                end
            end
        end
    end
    ModMuxPerf.parked[mod] = count
    return count
end

function ModMuxPerf.canPark(mod)
    for _, entry in ipairs(ModMuxPerf.listenersByMod[mod] or {}) do
        if entry.parkable then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------------------------------------------------
-- Timing
----------------------------------------------------------------------------------------------------------------

local function finish(stats, t0, previous, ...)
    stats.acc = stats.acc + (clock() - t0) * 1000
    ModMuxPerf.current = previous
    return ...
end

local wrappedKeys = {}

function ModMuxPerf.wrap(tbl, name, mod)
    local inner = rawget(tbl, name)
    if type(inner) ~= "function" or inner == noop then
        return false
    end
    wrappedKeys[tbl] = wrappedKeys[tbl] or {}
    if wrappedKeys[tbl][name] then
        return false
    end
    wrappedKeys[tbl][name] = true
    local stats = ModMuxPerf.getStats(mod)
    local wrapper = function(...)
        local previous = ModMuxPerf.current
        ModMuxPerf.current = mod
        local t0 = clock()
        return finish(stats, t0, previous, inner(...))
    end
    ModMuxScan.transparent[wrapper] = inner
    tbl[name] = wrapper
    stats.functions = stats.functions + 1
    return true
end

--- Wraps every mod listener and every mod specialization per-frame event. Once per game session.
function ModMuxPerf.install()
    if ModMuxPerf.installed then
        return
    end
    ModMuxPerf.installed = true
    for mod, entries in pairs(ModMuxPerf.listenersByMod) do
        for _, entry in ipairs(entries) do
            local any = false
            for _, name in ipairs(ModMuxPerf.LISTENER_FUNCTIONS) do
                any = ModMuxPerf.wrap(entry.listener, name, mod) or any
            end
            if any then
                local stats = ModMuxPerf.getStats(mod)
                stats.listeners = stats.listeners + 1
            end
        end
    end

    local done = {}
    for _, manager in ipairs({g_vehicleTypeManager, g_placeableTypeManager}) do
        local types = (type(manager) == "table" and manager.getTypes ~= nil) and manager:getTypes() or nil
        for _, typeEntry in pairs(types or {}) do
            local listeners = type(typeEntry) == "table" and typeEntry.eventListeners or nil
            if type(listeners) == "table" then
                for _, eventName in ipairs(ModMuxPerf.SPEC_EVENTS) do
                    for _, spec in ipairs(listeners[eventName] or {}) do
                        if type(spec) == "table" then
                            done[spec] = done[spec] or {}
                            if not done[spec][eventName] then
                                done[spec][eventName] = true
                                local owner = ModMuxOrigin.ofFunction(rawget(spec, eventName))
                                if ModMuxOrigin.isMod(owner) and owner ~= ModMux.MOD_NAME then
                                    ModMuxPerf.wrap(spec, eventName, owner)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Once per frame (ModMux's update): closes the frame's numbers.
function ModMuxPerf.endFrame()
    ModMuxPerf.current = nil
    local now = clock()
    if ModMuxPerf.lastFrameAt ~= nil then
        local frameMs = (now - ModMuxPerf.lastFrameAt) * 1000
        if frameMs > 0 and frameMs < 1000 then
            ModMuxPerf.frameMs = ModMuxPerf.frameMs + (frameMs - ModMuxPerf.frameMs) * ModMuxPerf.SMOOTHING
        end
    end
    ModMuxPerf.lastFrameAt = now
    ModMuxPerf.frames = ModMuxPerf.frames + 1
    local k = ModMuxPerf.SMOOTHING
    for _, stats in pairs(ModMuxPerf.stats) do
        stats.last = stats.acc
        stats.acc = 0
        stats.ms = stats.ms + (stats.last - stats.ms) * k
        stats.peak = math.max(stats.peak * 0.995, stats.last)
    end
    if ModMuxPerf.hud ~= nil then
        ModMuxPerf.updateHudScan()
    end
end

function ModMuxPerf.resetStats()
    for _, stats in pairs(ModMuxPerf.stats) do
        stats.ms, stats.peak, stats.last, stats.acc = 0, 0, 0, 0
    end
end

--- {mod, ms, peak, functions, listeners} sorted by cost, the parked mods included
function ModMuxPerf.list()
    local list = {}
    for mod, stats in pairs(ModMuxPerf.stats) do
        if stats.functions > 0 then
            table.insert(list, {mod = mod, ms = stats.ms, peak = stats.peak, functions = stats.functions,
                listeners = stats.listeners})
        end
    end
    for mod in pairs(ModMuxPerf.parked) do
        if ModMuxPerf.stats[mod] == nil then
            table.insert(list, {mod = mod, ms = 0, peak = 0, functions = 0, listeners = 0})
        end
    end
    table.sort(list, function(a, b)
        if a.ms ~= b.ms then
            return a.ms > b.ms
        end
        return a.mod:lower() < b.mod:lower()
    end)
    return list
end

function ModMuxPerf.totalMs()
    local total = 0
    for _, stats in pairs(ModMuxPerf.stats) do
        total = total + stats.ms
    end
    return total
end

----------------------------------------------------------------------------------------------------------------
-- HUD overlap scan: for a few seconds, every rectangle a mod draws (renderOverlay / drawFilledRect / renderText) is
-- noted with the mod drawing it. Only drawing done inside a measured listener or specialization is seen.
----------------------------------------------------------------------------------------------------------------

ModMuxPerf.HUD_DRAW_FUNCTIONS = {"renderOverlay", "drawFilledRect", "renderText", "setTextAlignment"}

function ModMuxPerf.startHudScan(frames)
    if ModMuxPerf.hud ~= nil or not ModMuxPerf.installed then
        return false
    end
    local originals = {}
    for _, name in ipairs(ModMuxPerf.HUD_DRAW_FUNCTIONS) do
        originals[name] = rawget(G, name)
    end
    if type(originals.renderOverlay) ~= "function" and type(originals.renderText) ~= "function" then
        return false
    end
    local hud = {framesLeft = frames, rects = {}, originals = originals, wrappers = {}, align = 0}
    local alignCenter = RenderText ~= nil and RenderText.ALIGN_CENTER or 1
    local alignRight = RenderText ~= nil and RenderText.ALIGN_RIGHT or 2

    local function add(x, y, w, h)
        local mod = ModMuxPerf.current
        if mod == nil or type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
            return
        end
        if w <= 0 or h <= 0 or w > 0.9 or h > 0.9 then
            return
        end
        local list = hud.rects[mod]
        if list == nil then
            list = {keys = {}}
            hud.rects[mod] = list
        end
        if #list >= 64 then
            return
        end
        local key = string.format("%.3f %.3f %.3f %.3f", x, y, w, h)
        if not list.keys[key] then
            list.keys[key] = true
            table.insert(list, {x = x, y = y, w = w, h = h})
        end
    end

    if type(originals.renderOverlay) == "function" then
        hud.wrappers.renderOverlay = function(id, x, y, w, h, ...)
            add(x, y, w, h)
            return originals.renderOverlay(id, x, y, w, h, ...)
        end
    end
    if type(originals.drawFilledRect) == "function" then
        hud.wrappers.drawFilledRect = function(x, y, w, h, ...)
            add(x, y, w, h)
            return originals.drawFilledRect(x, y, w, h, ...)
        end
    end
    if type(originals.setTextAlignment) == "function" then
        hud.wrappers.setTextAlignment = function(alignment, ...)
            hud.align = alignment
            return originals.setTextAlignment(alignment, ...)
        end
    end
    if type(originals.renderText) == "function" then
        hud.wrappers.renderText = function(x, y, size, text, ...)
            if ModMuxPerf.current ~= nil and type(size) == "number" and type(x) == "number" then
                local w = size * 0.5 * #tostring(text)
                if getTextWidth ~= nil then
                    w = getTextWidth(size, tostring(text))
                end
                local left = x
                if hud.align == alignCenter then
                    left = x - w / 2
                elseif hud.align == alignRight then
                    left = x - w
                end
                add(left, y, w, size)
            end
            return originals.renderText(x, y, size, text, ...)
        end
    end
    for name, wrapper in pairs(hud.wrappers) do
        rawset(G, name, wrapper)
    end
    ModMuxPerf.hud = hud
    return true
end

function ModMuxPerf.stopHudScan()
    local hud = ModMuxPerf.hud
    if hud == nil then
        return
    end
    ModMuxPerf.hud = nil
    for name, wrapper in pairs(hud.wrappers) do
        -- only put the original back if nobody replaced our wrapper meanwhile
        if rawget(G, name) == wrapper then
            rawset(G, name, hud.originals[name])
        end
    end
    ModMuxReview.onHudScan(hud.rects)
end

function ModMuxPerf.updateHudScan()
    local hud = ModMuxPerf.hud
    -- the HUD is hidden while a menu is open: those frames don't count
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then
        return
    end
    hud.framesLeft = hud.framesLeft - 1
    if hud.framesLeft <= 0 then
        ModMuxPerf.stopHudScan()
    end
end
