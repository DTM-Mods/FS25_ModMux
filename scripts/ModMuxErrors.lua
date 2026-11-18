-- ModMux: the ERRORS tab. Errors and warnings, per mod.
--
-- What ModMux can see (the engine gives mods no way to read log.txt):
--   log lines   every Logging.error / warning / xmlError / xmlWarning / devError / devWarning (and print lines that
--               start with "Error" or "Warning") from ModMux's load on. ModMux loads second, so that is nearly all.
--   stops       a mod's per-frame function (event listener update / draw, specialization onUpdate...) that started and
--               never finished stopped with a Lua error. Seen through PERFORMANCE's timers (ModMuxPerf.open).
-- Not seen: messages the engine writes itself (missing textures, Lua errors outside per-frame code); log.txt has them.
-- Which mod: a mod folder or mod name in the message, the file of an XML message, else the mod that was loading.
-- The caller's environment is deliberately not used: getfenv(2) fails on tail calls, and that would break the caller.

ModMuxErrors = {}

ModMuxErrors.entries = {}          -- {mod, level, text, how, count, firstAt, lastAt, order}
ModMuxErrors.byKey = {}
ModMuxErrors.perMod = {}
ModMuxErrors.MAX_PER_MOD = 100
ModMuxErrors.MAX_TOTAL = 2000
ModMuxErrors.MAX_TEXT = 400
ModMuxErrors.installed = false
ModMuxErrors.busy = false          -- inside our own recording: a log line ModMux itself writes then isn't recorded
ModMuxErrors.order = 0
ModMuxErrors.version = 0           -- grows with every new entry (the tab redraws when it changed)

-- Logging function -> level
ModMuxErrors.LOGGING = {error = "error", warning = "warning", devError = "error", devWarning = "warning",
    xmlError = "error", xmlWarning = "warning", xmlDevError = "error", xmlDevWarning = "warning", fatal = "error"}

local G = ModMuxOrigin.G
local textOwnerCache, textOwnerCount = {}, 0

local function clock()
    if getTimeSec ~= nil then
        return getTimeSec()
    end
    return os.clock()
end

local function plain(value)
    local kind = type(value)
    if kind == "string" then
        return value
    elseif kind == "number" or kind == "boolean" or kind == "nil" then
        return tostring(value)
    end
    -- no tostring on tables / userdata: a broken __tostring would throw inside someone else's log call
    return "<" .. kind .. ">"
end

--- string.format that can't throw: every %x takes the next value as text
function ModMuxErrors.looseFormat(text, ...)
    local args, n, i = {...}, select("#", ...), 0
    local out = plain(text)
    if n == 0 then
        return out
    end
    out = out:gsub("%%([%-%+ #0]*%d*%.?%d*)([%a%%])", function(_, conversion)
        if conversion == "%" then
            return "%"
        end
        i = i + 1
        local value = args[i]
        if type(value) == "number" and (conversion == "f" or conversion == "g" or conversion == "e") then
            return string.format("%.3f", value):gsub("%.?0+$", "")
        elseif type(value) == "number" and (conversion == "d" or conversion == "i") then
            return tostring(math.floor(value))
        end
        return plain(value)
    end)
    return out
end

--- the mod a message names (by folder or by mod name), or nil
function ModMuxErrors.modFromText(text)
    local cached = textOwnerCache[text]
    if cached ~= nil then
        return cached or nil
    end
    local lower = text:lower():gsub("\\", "/")
    local best, bestLength = nil, 0
    for _, mod in ipairs(ModMuxOrigin.mods) do
        local name = mod.name:lower()
        if #name > bestLength then
            local at = lower:find(name, 1, true)
            while at ~= nil do
                local before, after = lower:sub(at - 1, at - 1), lower:sub(at + #name, at + #name)
                if not before:find("[%w_]") and not after:find("[%w_]") then
                    best, bestLength = mod.name, #name
                    break
                end
                at = lower:find(name, at + 1, true)
            end
        end
    end
    if textOwnerCount < 2000 then
        textOwnerCache[text] = best or false
        textOwnerCount = textOwnerCount + 1
    end
    return best
end

function ModMuxErrors.add(level, text, how, mod)
    text = plain(text):gsub("^%s+", ""):gsub("%s+$", "")
    if #text > ModMuxErrors.MAX_TEXT then
        text = text:sub(1, ModMuxErrors.MAX_TEXT) .. "..."
    end
    if mod == nil or not ModMuxOrigin.isMod(mod) then
        mod = ModMuxErrors.modFromText(text) or ModMuxOrigin.loadingMod() or ModMuxOrigin.GAME
    end
    if mod == ModMux.MOD_NAME then
        return
    end
    local key = mod .. "\n" .. level .. "\n" .. text
    local now = clock()
    local entry = ModMuxErrors.byKey[key]
    if entry ~= nil then
        entry.count = entry.count + 1
        entry.lastAt = now
        return
    end
    local count = ModMuxErrors.perMod[mod] or 0
    if count >= ModMuxErrors.MAX_PER_MOD or #ModMuxErrors.entries >= ModMuxErrors.MAX_TOTAL then
        return
    end
    ModMuxErrors.perMod[mod] = count + 1
    ModMuxErrors.order = ModMuxErrors.order + 1
    entry = {mod = mod, level = level, text = text, how = how, count = 1, firstAt = now, lastAt = now,
        order = ModMuxErrors.order, duringLoad = not ModMux.missionLoaded}
    ModMuxErrors.byKey[key] = entry
    table.insert(ModMuxErrors.entries, entry)
    ModMuxErrors.version = ModMuxErrors.version + 1
end

--- a log call seen by a wrapper: never lets anything of ours reach the caller
local function record(level, how, first, ...)
    if ModMuxErrors.busy then
        return
    end
    ModMuxErrors.busy = true
    local text
    if how:find("^xml") ~= nil and type(first) ~= "string" then
        -- xmlWarning(xmlFile, text, ...): the file tells which mod it belongs to
        local file = nil
        if type(first) == "table" and type(first.filename) == "string" then
            file = first.filename
        elseif type(first) == "number" and getXMLFilename ~= nil then
            file = getXMLFilename(first)
        end
        local message = ...
        text = ModMuxErrors.looseFormat(message, select(2, ...))
        if type(file) == "string" then
            text = text .. " (" .. file .. ")"
        end
    else
        text = ModMuxErrors.looseFormat(first, ...)
    end
    ModMuxErrors.add(level, text, how)
    ModMuxErrors.busy = false
end

local function wrapLogging(name, level)
    local original = rawget(Logging, name)
    if type(original) ~= "function" then
        return
    end
    local wrapper = function(...)
        record(level, name, ...)
        return original(...)
    end
    ModMuxScan.transparent[wrapper] = original
    Logging[name] = wrapper
end

--- Puts the recorder around the game's log functions and print. Once per game session.
function ModMuxErrors.install()
    if ModMuxErrors.installed then
        return
    end
    ModMuxErrors.installed = true
    if type(Logging) == "table" then
        for name, level in pairs(ModMuxErrors.LOGGING) do
            wrapLogging(name, level)
        end
    end
    local originalPrint = rawget(G, "print")
    if type(originalPrint) == "function" then
        local wrapper = function(first, ...)
            if not ModMuxErrors.busy and type(first) == "string" then
                local head = first:sub(1, 12):lower()
                if head:find("^%s*error") ~= nil then
                    record("error", "print", first, ...)
                elseif head:find("^%s*warning") ~= nil then
                    record("warning", "print", first, ...)
                end
            end
            return originalPrint(first, ...)
        end
        ModMuxScan.transparent[wrapper] = originalPrint
        rawset(G, "print", wrapper)
    end
end

--- a per-frame function of a mod started and never returned: it stopped with a Lua error
function ModMuxErrors.onStop(mod, label)
    ModMuxErrors.add("error", ModMux.getText("mm_err_stopped", label), "stop", mod)
end

--- entries for the tab: by mod (title), errors before warnings, most frequent first; or all by count
function ModMuxErrors.list(sortByCount, hideGame)
    local list = {}
    for _, entry in ipairs(ModMuxErrors.entries) do
        if not hideGame or ModMuxOrigin.isMod(entry.mod) then
            table.insert(list, entry)
        end
    end
    local function title(entry)
        if not ModMuxOrigin.isMod(entry.mod) then
            return "\255"  -- the game and unknown sources last
        end
        return ModMuxOrigin.title(entry.mod):lower()
    end
    table.sort(list, function(a, b)
        if not sortByCount then
            local ta, tb = title(a), title(b)
            if ta ~= tb then
                return ta < tb
            end
        end
        if a.level ~= b.level then
            return a.level == "error"
        end
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.order < b.order
    end)
    return list
end

function ModMuxErrors.counts()
    local errors, warnings, mods = 0, 0, {}
    for _, entry in ipairs(ModMuxErrors.entries) do
        if entry.level == "error" then
            errors = errors + 1
        else
            warnings = warnings + 1
        end
        if ModMuxOrigin.isMod(entry.mod) then
            mods[entry.mod] = true
        end
    end
    local modCount = 0
    for _ in pairs(mods) do
        modCount = modCount + 1
    end
    return errors, warnings, modCount
end

function ModMuxErrors.clear()
    ModMuxErrors.entries, ModMuxErrors.byKey, ModMuxErrors.perMod = {}, {}, {}
    ModMuxErrors.version = ModMuxErrors.version + 1
end
