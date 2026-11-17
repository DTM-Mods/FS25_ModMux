-- ModMux: who a function belongs to.
-- The game runs every script mod in its own environment table (its globals), and every Lua function keeps the
-- environment it was written in for good: getfenv(f) names the mod that wrote f. The game's own functions have the
-- game's global table. (The game hides the debug library, so file names and upvalues can't be read; this is all
-- ModMux needs.) Everything else in ModMux is built on this.

ModMuxOrigin = {}

ModMuxOrigin.GAME = "game"         -- the game's own scripts and the engine
ModMuxOrigin.UNKNOWN = "?"

ModMuxOrigin.mods = {}             -- active mods, sorted by name: {name, title, dir, author, version, isDLC, ...}
ModMuxOrigin.byName = {}
ModMuxOrigin.byLowerName = {}
ModMuxOrigin.modEnvs = {}          -- mod name -> its environment table
ModMuxOrigin.learned = 0           -- environments matched to a mod while it loaded (not found under its name)

ModMuxOrigin.OWN_NAME = g_currentModName or "FS25_0_ModMux"
ModMuxOrigin.ownEnv = getfenv ~= nil and getfenv(1) or nil

--- The game's global table: where the game's classes live. A mod's own environment only holds the mod's globals and
-- looks the rest up there (metatable __index), so it can't be listed, and a global written into it stays the mod's.
local function findGlobals()
    local candidates = {}
    if getfenv ~= nil then
        -- the environment of a game function is the game's global table
        for _, entry in ipairs({{Utils, "getNoNil"}, {Logging, "info"}, {Utils, "appendedFunction"}}) do
            local f = type(entry[1]) == "table" and rawget(entry[1], entry[2]) or nil
            if type(f) == "function" then
                table.insert(candidates, {getfenv(f), "game function"})
            end
        end
    end
    if getmetatable ~= nil then
        local t = ModMuxOrigin.ownEnv or _G
        for _ = 1, 3 do
            local mt = type(t) == "table" and getmetatable(t) or nil
            t = type(mt) == "table" and mt.__index or nil
            if type(t) ~= "table" then
                break
            end
            table.insert(candidates, {t, "environment metatable"})
        end
    end
    if getfenv ~= nil then
        table.insert(candidates, {getfenv(0), "thread"})
    end
    table.insert(candidates, {_G, "_G"})
    for _, candidate in ipairs(candidates) do
        local t = candidate[1]
        if type(t) == "table" and rawget(t, "Utils") ~= nil and rawget(t, "Utils") == Utils then
            return t, candidate[2]
        end
    end
    return ModMuxOrigin.ownEnv or _G, "none"
end

ModMuxOrigin.G, ModMuxOrigin.globalsVia = findGlobals()
local G = ModMuxOrigin.G

-- owners can only be told apart when mods really run in their own environments
ModMuxOrigin.hasFenv = getfenv ~= nil and type(ModMuxOrigin.ownEnv) == "table" and ModMuxOrigin.ownEnv ~= G

local envToMod = {}                -- environment -> mod name
local envLearned = {}              -- environment -> mod name, learned while the mod loaded
local envCache = setmetatable({}, {__mode = "k"})
local missedEnvs = {}              -- environments looked up without a match since the last refreshMods()

local function addMod(list, byName, entry)
    if entry.name == nil or byName[entry.name] ~= nil then
        return
    end
    entry.title = entry.title or entry.name
    byName[entry.name] = entry
    table.insert(list, entry)
end

--- Reads the active mods from the mod manager (and g_modIsLoaded for anything it misses), and finds their environments.
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
        for name, loaded in pairs(g_modIsLoaded) do
            if loaded and type(name) == "string" then
                addMod(list, byName, {name = name})
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
    missedEnvs = {}
    ModMuxOrigin.refreshEnvs()
end

--- mod environments: the table under each mod's name in the global table, plus the ones learned while mods loaded
function ModMuxOrigin.refreshEnvs()
    local map, byMod = {}, {}
    for env, name in pairs(envLearned) do
        map[env] = name
        byMod[name] = env
    end
    for _, mod in ipairs(ModMuxOrigin.mods) do
        local env = rawget(G, mod.name)
        if type(env) == "table" and env ~= G then
            map[env] = mod.name
            byMod[mod.name] = env
        end
    end
    if type(ModMuxOrigin.ownEnv) == "table" and ModMuxOrigin.ownEnv ~= G then
        map[ModMuxOrigin.ownEnv] = ModMuxOrigin.OWN_NAME
        byMod[ModMuxOrigin.OWN_NAME] = ModMuxOrigin.ownEnv
    end
    envToMod = map
    ModMuxOrigin.modEnvs = byMod
end

--- The mod whose scripts the game is loading right now (nil once loading is over, and for ModMux itself).
function ModMuxOrigin.loadingMod()
    local name = rawget(G, "g_currentModName")
    if name == nil then
        name = g_currentModName
    end
    if type(name) ~= "string" or name == "" or name == ModMuxOrigin.OWN_NAME then
        return nil
    end
    return name
end

--- While a mod loads, a function of an environment ModMux doesn't know yet is that mod's.
function ModMuxOrigin.learnEnv(env, modName)
    if type(env) ~= "table" or env == G or modName == nil or envToMod[env] ~= nil or envLearned[env] ~= nil then
        return
    end
    if not ModMuxOrigin.hasFenv then
        return
    end
    -- the mod's own environment under its name is the better source, if it is there
    local named = rawget(G, modName)
    if type(named) == "table" and named ~= env then
        return
    end
    envLearned[env] = modName
    envToMod[env] = modName
    ModMuxOrigin.modEnvs[modName] = ModMuxOrigin.modEnvs[modName] or env
    ModMuxOrigin.learned = ModMuxOrigin.learned + 1
end

--- the environment a function was written in (cached)
function ModMuxOrigin.envOf(f)
    if type(f) ~= "function" or getfenv == nil then
        return nil
    end
    local env = envCache[f]
    if env == nil then
        env = getfenv(f)
        if env ~= nil then
            envCache[f] = env
        end
    end
    return env
end

function ModMuxOrigin.ofEnv(env)
    if env == nil or not ModMuxOrigin.hasFenv then
        return ModMuxOrigin.UNKNOWN
    elseif env == G then
        return ModMuxOrigin.GAME
    end
    local owner = envToMod[env]
    if owner == nil and not missedEnvs[env] then
        -- a mod that finished loading after the last look
        missedEnvs[env] = true
        ModMuxOrigin.refreshEnvs()
        owner = envToMod[env]
    end
    return owner or ModMuxOrigin.UNKNOWN
end

--- The owner of a function: a mod name, GAME, or UNKNOWN (an environment that isn't a mod's: treated like the game's).
function ModMuxOrigin.ofFunction(f)
    if type(f) ~= "function" then
        return ModMuxOrigin.UNKNOWN
    end
    return ModMuxOrigin.ofEnv(ModMuxOrigin.envOf(f))
end

--- {owner} of a function (kept as a table for the callers that read .owner)
function ModMuxOrigin.info(f)
    if type(f) ~= "function" then
        return nil
    end
    return {owner = ModMuxOrigin.ofFunction(f)}
end

function ModMuxOrigin.isMod(owner)
    return owner ~= nil and ModMuxOrigin.byName[owner] ~= nil
end

--- A mod's title for players ("Mod Name"), or the owner id itself.
function ModMuxOrigin.title(owner)
    local mod = ModMuxOrigin.byName[owner]
    if mod ~= nil then
        return tostring(mod.title)
    elseif owner == ModMuxOrigin.GAME then
        return ModMux.getText("mm_owner_game")
    elseif owner == ModMuxOrigin.UNKNOWN then
        return ModMux.getText("mm_owner_unknown")
    end
    return tostring(owner)
end

--- one line for the log and the report: how ModMux reads owners in this game
function ModMuxOrigin.describe()
    local envs = 0
    for _ in pairs(ModMuxOrigin.modEnvs) do
        envs = envs + 1
    end
    return string.format("function owners %s (game globals via %s, %d mod environments, %d learned while loading)",
        ModMuxOrigin.hasFenv and "on" or "OFF", ModMuxOrigin.globalsVia, envs, ModMuxOrigin.learned)
end
