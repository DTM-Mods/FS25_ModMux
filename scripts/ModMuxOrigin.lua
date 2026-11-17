-- ModMux: who a function belongs to.
-- Every Lua function knows the file it was written in (debug.getinfo(f, "S").source). A file inside a mod's folder
-- belongs to that mod, a file under dataS/ to the game. Everything else in ModMux is built on this.

ModMuxOrigin = {}

ModMuxOrigin.GAME = "game"         -- the game's own scripts (dataS/...)
ModMuxOrigin.ENGINE = "engine"     -- C functions of the engine
ModMuxOrigin.UNKNOWN = "?"

ModMuxOrigin.mods = {}             -- active mods, sorted by name: {name, title, dir, dirLower, author, version, ...}
ModMuxOrigin.byName = {}
ModMuxOrigin.byLowerName = {}
ModMuxOrigin.hasDebug = debug ~= nil and debug.getinfo ~= nil
ModMuxOrigin.hasUpvalues = debug ~= nil and debug.getupvalue ~= nil

local sourceCache = {}
local functionCache = setmetatable({}, {__mode = "k"})

local function normalizePath(path)
    path = tostring(path):gsub("\\", "/"):lower()
    local first = path:sub(1, 1)
    if first == "@" or first == "=" then
        path = path:sub(2)
    end
    return path
end
ModMuxOrigin.normalizePath = normalizePath

local function addMod(list, byName, entry)
    if entry.name == nil or byName[entry.name] ~= nil then
        return
    end
    if entry.dir ~= nil and entry.dir ~= "" then
        entry.dirLower = normalizePath(entry.dir)
        if entry.dirLower:sub(-1) ~= "/" then
            entry.dirLower = entry.dirLower .. "/"
        end
    end
    entry.title = entry.title or entry.name
    byName[entry.name] = entry
    table.insert(list, entry)
end

--- Reads the active mods from the mod manager (and g_modIsLoaded for anything it misses).
function ModMuxOrigin.refreshMods()
    local list, byName = {}, {}
    local manager = g_modManager
    local mods = nil
    if manager ~= nil and manager.getActiveMods ~= nil then
        mods = manager:getActiveMods()
    end
    if mods == nil and manager ~= nil and manager.getMods ~= nil then
        mods = manager:getMods()
    end
    for _, mod in ipairs(mods or {}) do
        if type(mod) == "table" and mod.modName ~= nil then
            addMod(list, byName, {name = mod.modName, title = mod.title, dir = mod.modDir, author = mod.author,
                version = mod.version, isDLC = mod.isDLC == true, fileHash = mod.fileHash, modFile = mod.modFile})
        end
    end
    if type(g_modIsLoaded) == "table" then
        local directories = type(g_modNameToDirectory) == "table" and g_modNameToDirectory or {}
        for name, loaded in pairs(g_modIsLoaded) do
            if loaded and type(name) == "string" then
                addMod(list, byName, {name = name, dir = directories[name]})
            end
        end
    end
    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    ModMuxOrigin.mods = list
    ModMuxOrigin.byName = byName
    ModMuxOrigin.byLowerName = {}
    for _, entry in ipairs(list) do
        ModMuxOrigin.byLowerName[entry.name:lower()] = entry
    end
    sourceCache = {}
    functionCache = setmetatable({}, {__mode = "k"})
end

--- The owner of a source file name: a mod name, GAME, ENGINE or UNKNOWN.
function ModMuxOrigin.ofSource(source)
    if source == nil then
        return ModMuxOrigin.UNKNOWN
    end
    local cached = sourceCache[source]
    if cached ~= nil then
        return cached
    end

    local owner = ModMuxOrigin.UNKNOWN
    if source == "=[C]" then
        owner = ModMuxOrigin.ENGINE
    else
        local path = normalizePath(source)
        for _, mod in ipairs(ModMuxOrigin.mods) do
            if mod.dirLower ~= nil and path:find(mod.dirLower, 1, true) ~= nil then
                owner = mod.name
                break
            end
        end
        if owner == ModMuxOrigin.UNKNOWN then
            local folder = path:match("/mods/([^/]+)/")
            if folder ~= nil then
                local mod = ModMuxOrigin.byLowerName[(folder:gsub("%.zip$", ""))]
                if mod ~= nil then
                    owner = mod.name
                end
            end
        end
        if owner == ModMuxOrigin.UNKNOWN then
            if path:find("^datas/") ~= nil or path:find("/datas/") ~= nil or path:find("^data/") ~= nil then
                owner = ModMuxOrigin.GAME
            else
                local dlc = path:match("pdlc/([^/]+)/")
                if dlc ~= nil then
                    local mod = ModMuxOrigin.byLowerName["pdlc_" .. dlc] or ModMuxOrigin.byLowerName[dlc]
                    owner = mod ~= nil and mod.name or ModMuxOrigin.GAME
                end
            end
        end
    end
    sourceCache[source] = owner
    return owner
end

--- {owner, source, line, signature} of a function (cached).
function ModMuxOrigin.info(f)
    if type(f) ~= "function" then
        return nil
    end
    local cached = functionCache[f]
    if cached ~= nil then
        return cached
    end
    local entry
    if ModMuxOrigin.hasDebug then
        local info = debug.getinfo(f, "S")
        if info ~= nil then
            local source = info.source or "?"
            local line = info.linedefined or -1
            local owner = info.what == "C" and ModMuxOrigin.ENGINE or ModMuxOrigin.ofSource(source)
            entry = {owner = owner, source = source, line = line, signature = source .. ":" .. tostring(line)}
        end
    end
    entry = entry or {owner = ModMuxOrigin.UNKNOWN, source = "?", line = -1, signature = "?"}
    functionCache[f] = entry
    return entry
end

function ModMuxOrigin.ofFunction(f)
    local info = ModMuxOrigin.info(f)
    return info ~= nil and info.owner or ModMuxOrigin.UNKNOWN
end

function ModMuxOrigin.isMod(owner)
    return owner ~= nil and ModMuxOrigin.byName[owner] ~= nil
end

--- A mod's title for players ("Mod Name"), or the owner id itself.
function ModMuxOrigin.title(owner)
    local mod = ModMuxOrigin.byName[owner]
    if mod ~= nil then
        return tostring(mod.title)
    elseif owner == ModMuxOrigin.GAME or owner == ModMuxOrigin.ENGINE then
        return ModMux.getText("mm_owner_game")
    end
    return tostring(owner)
end

--- Short "file:line" of where a function was written, for the ADVANCED view and the report.
function ModMuxOrigin.where(f)
    local info = ModMuxOrigin.info(f)
    if info == nil then
        return "?"
    end
    local path = tostring(info.source):gsub("\\", "/")
    local first = path:sub(1, 1)
    if first == "@" or first == "=" then
        path = path:sub(2)
    end
    local lower = path:lower()
    local mod = ModMuxOrigin.byName[info.owner]
    local start = nil
    if mod ~= nil and mod.dirLower ~= nil then
        local at = lower:find(mod.dirLower, 1, true)
        if at ~= nil then
            start = at + #mod.dirLower
        end
    else
        start = lower:find("datas/", 1, true)
    end
    if start ~= nil then
        path = path:sub(start)
    else
        path = path:match("([^/]+/[^/]+)$") or path
    end
    return string.format("%s:%d", path, info.line)
end
