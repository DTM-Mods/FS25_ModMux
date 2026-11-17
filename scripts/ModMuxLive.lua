-- ModMux: the LIVE tab. Settings mods expose (toggles, sliders, choices), changed in game at once.
--
-- Any mod can add its own:
--   if g_modMux ~= nil then
--       g_modMux.registerLiveSetting({id = "myMod.showHud", modName = g_currentModName, title = "Show my HUD",
--           kind = "bool", get = function() return MyMod.showHud end, set = function(value) MyMod.showHud = value end})
--   end
-- kind "number" also needs min, max, step (and may give format = "%.1f m"); kind "choice" needs choices = {values}
-- and may give texts = {display texts}. description = one line shown on the right. ModMux remembers the last value set
-- through it and gives it back when the mod registers again (remember = false turns that off).

ModMuxLive = {}

ModMuxLive.list = {}
ModMuxLive.byId = {}

local KINDS = {bool = true, number = true, choice = true}

function ModMuxLive.encode(value)
    return tostring(value)
end

function ModMuxLive.decode(entry, text)
    if text == nil then
        return nil
    end
    if entry.kind == "bool" then
        return text == "true"
    elseif entry.kind == "number" then
        return tonumber(text)
    end
    for _, choice in ipairs(entry.choices) do
        if tostring(choice) == text then
            return choice
        end
    end
    return nil
end

function ModMuxLive.register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.get) ~= "function" or type(def.set) ~= "function" then
        Logging.warning("%s registerLiveSetting needs id, get and set", ModMux.TAG)
        return false
    end
    local kind = def.kind or "bool"
    if not KINDS[kind] then
        Logging.warning("%s live setting %s: unknown kind %s", ModMux.TAG, def.id, tostring(kind))
        return false
    end
    if kind == "number" and (type(def.min) ~= "number" or type(def.max) ~= "number" or type(def.step) ~= "number"
        or def.step <= 0 or def.max < def.min) then
        Logging.warning("%s live setting %s: a number needs min, max and step", ModMux.TAG, def.id)
        return false
    end
    if kind == "choice" and (type(def.choices) ~= "table" or #def.choices == 0) then
        Logging.warning("%s live setting %s: a choice needs choices", ModMux.TAG, def.id)
        return false
    end

    local entry = {id = def.id, modName = def.modName, title = tostring(def.title or def.id), kind = kind, get = def.get,
        set = def.set, min = def.min, max = def.max, step = def.step, choices = def.choices, texts = def.texts,
        format = def.format, description = def.description, remember = def.remember ~= false, own = def.own == true}
    local existing = ModMuxLive.byId[def.id]
    if existing ~= nil then
        for i, other in ipairs(ModMuxLive.list) do
            if other == existing then
                ModMuxLive.list[i] = entry
            end
        end
    else
        table.insert(ModMuxLive.list, entry)
    end
    ModMuxLive.byId[def.id] = entry

    if entry.remember then
        local stored = ModMuxLive.decode(entry, ModMux.settings.live[entry.id])
        if stored ~= nil then
            entry.set(stored)
        end
    end
    return true
end

function ModMuxLive.setValue(entry, value, remember)
    entry.set(value)
    if remember and entry.remember then
        ModMux.settings.live[entry.id] = ModMuxLive.encode(value)
        ModMux.saveSettings()
    end
end

local function roundToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

--- one step up (+1) or down (-1); a toggle flips either way
function ModMuxLive.step(entry, direction)
    local value = entry.get()
    local new
    if entry.kind == "bool" then
        new = not value
    elseif entry.kind == "number" then
        new = roundToStep((tonumber(value) or entry.min) + direction * entry.step, entry.step)
        new = math.max(entry.min, math.min(entry.max, new))
    else
        local index = 1
        for i, choice in ipairs(entry.choices) do
            if choice == value then
                index = i
            end
        end
        index = ((index - 1 + direction) % #entry.choices) + 1
        new = entry.choices[index]
    end
    ModMuxLive.setValue(entry, new, true)
    return new
end

function ModMuxLive.valueText(entry)
    local value = entry.get()
    if entry.kind == "bool" then
        return ModMux.getText(value and "mm_on" or "mm_off")
    elseif entry.kind == "number" then
        if entry.format ~= nil then
            return string.format(entry.format, tonumber(value) or 0)
        end
        return tostring(value)
    end
    for i, choice in ipairs(entry.choices) do
        if choice == value then
            return tostring(entry.texts ~= nil and entry.texts[i] or choice)
        end
    end
    return tostring(value)
end

--- id -> value text of every remembered setting (for profiles)
function ModMuxLive.snapshot()
    local values = {}
    for _, entry in ipairs(ModMuxLive.list) do
        if entry.remember then
            values[entry.id] = ModMuxLive.encode(entry.get())
        end
    end
    return values
end

function ModMuxLive.applySnapshot(values)
    for id, text in pairs(values or {}) do
        local entry = ModMuxLive.byId[id]
        if entry ~= nil and entry.remember then
            local value = ModMuxLive.decode(entry, text)
            if value ~= nil then
                ModMuxLive.setValue(entry, value, true)
            end
        end
    end
end

--- ModMux's own instant settings
function ModMuxLive.registerOwn()
    local options = ModMux.settings.options
    local function option(name)
        return function()
            return ModMux.settings.options[name]
        end
    end
    local function setOption(name)
        return function(value)
            ModMux.settings.options[name] = value
            ModMux.saveSettings()
        end
    end
    ModMuxLive.register({id = "modMux.warnOnScreen", modName = ModMux.MOD_NAME, title = ModMux.getText("mm_live_warn"),
        description = ModMux.getText("mm_live_warn_desc"), kind = "bool", get = option("warnOnScreen"),
        set = setOption("warnOnScreen"), remember = false, own = true})
    ModMuxLive.register({id = "modMux.budgetFps", modName = ModMux.MOD_NAME, title = ModMux.getText("mm_live_budget"),
        description = ModMux.getText("mm_live_budget_desc"), kind = "choice", choices = {30, 45, 60, 75, 90, 120, 144},
        texts = {"30 fps", "45 fps", "60 fps", "75 fps", "90 fps", "120 fps", "144 fps"}, get = option("budgetFps"),
        set = setOption("budgetFps"), remember = false, own = true})
    ModMuxLive.register({id = "modMux.hudAutoScan", modName = ModMux.MOD_NAME, title = ModMux.getText("mm_live_hudScan"),
        description = ModMux.getText("mm_live_hudScan_desc"), kind = "bool", get = option("hudAutoScan"),
        set = setOption("hudAutoScan"), remember = false, own = true})
    return options
end
