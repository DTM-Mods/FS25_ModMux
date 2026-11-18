-- ModMux: the KEYS tab. Keys and buttons that more than one action uses, where at least one action is a mod's.
--
-- Sources (all read once per load, nothing is changed):
--   the player's own bindings      <profile>/inputBinding.xml (what the controls menu saved; the real keys)
--   every active mod's modDesc.xml  <actions> (which mod an action belongs to, and its category) and <inputBinding>
--                                   (default keys of actions the player's file doesn't have yet)
--   config/gameActions.xml          the game's actions and their categories (from the SDK, tools/make_game_actions.py)
-- Two actions only clash when they can fire in the same situation: their categories (ONFOOT, VEHICLE, SYSTEM, MENU...)
-- overlap, SYSTEM overlaps everything, and an action without a known category is assumed to overlap everything.

ModMuxKeys = {}

ModMuxKeys.conflicts = {}
ModMuxKeys.gameCategories = {}     -- game action name -> category string
ModMuxKeys.modActions = {}         -- action name -> {mod, category}
ModMuxKeys.stats = {actions = 0, modActions = 0, fromFile = false}

ModMuxKeys.KEYBOARD = "KB_MOUSE_DEFAULT"

local KEY_NAMES = {
    KEY_lctrl = "Left Ctrl", KEY_rctrl = "Right Ctrl", KEY_lshift = "Left Shift", KEY_rshift = "Right Shift",
    KEY_lalt = "Left Alt", KEY_ralt = "Right Alt", KEY_space = "Space", KEY_return = "Enter", KEY_esc = "Esc",
    KEY_tab = "Tab", KEY_backspace = "Backspace", KEY_delete = "Delete", KEY_insert = "Insert", KEY_home = "Home",
    KEY_end = "End", KEY_pageup = "Page Up", KEY_pagedown = "Page Down", KEY_up = "Up", KEY_down = "Down",
    KEY_left = "Left", KEY_right = "Right", MOUSE_BUTTON_LEFT = "Left mouse", MOUSE_BUTTON_RIGHT = "Right mouse",
    MOUSE_BUTTON_MIDDLE = "Middle mouse", MOUSE_BUTTON_WHEEL_UP = "Wheel up", MOUSE_BUTTON_WHEEL_DOWN = "Wheel down",
}
local MODIFIERS = {KEY_lctrl = 1, KEY_rctrl = 1, KEY_lshift = 2, KEY_rshift = 2, KEY_lalt = 3, KEY_ralt = 3}

--- "KEY_lctrl KEY_g" -> "Left Ctrl + G" (modifiers first)
function ModMuxKeys.keyText(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local name = KEY_NAMES[key]
        if name == nil then
            name = key:gsub("^KEY_KP_", "Num "):gsub("^KEY_", ""):gsub("^BUTTON_", "Button "):gsub("^MOUSE_BUTTON_", "Mouse ")
            if #name == 1 then
                name = name:upper()
            end
        end
        table.insert(parts, name)
    end
    return table.concat(parts, " + ")
end

--- the keys of an input string, modifiers first, then by name (one combination = one key list)
function ModMuxKeys.splitKeys(input)
    local keys = {}
    for key in tostring(input):gmatch("%S+") do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        local ma, mb = MODIFIERS[a] or 9, MODIFIERS[b] or 9
        if ma ~= mb then
            return ma < mb
        end
        return a < b
    end)
    return keys
end

local function categorySet(text)
    local set, any = {}, false
    for word in tostring(text or ""):gmatch("%S+") do
        set[word:upper()] = true
        any = true
    end
    return any and set or nil
end

--- can two actions fire in the same situation?
function ModMuxKeys.overlap(a, b)
    local ca, cb = categorySet(a), categorySet(b)
    if ca == nil or cb == nil or ca.SYSTEM or cb.SYSTEM then
        return true
    end
    for word in pairs(ca) do
        if cb[word] then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------------------------------------------------

local function eachIndexed(xml, pattern, callback)
    local i = 0
    while true do
        local key = string.format(pattern, i)
        if not hasXMLProperty(xml, key) then
            break
        end
        callback(key)
        i = i + 1
    end
end

function ModMuxKeys.loadGameActions(path)
    ModMuxKeys.gameCategories = {}
    if not fileExists(path) then
        return 0
    end
    local xml = loadXMLFile("ModMuxGameActions", path)
    if xml == nil or xml == 0 then
        return 0
    end
    local count = 0
    eachIndexed(xml, "gameActions.action(%d)", function(key)
        local name = getXMLString(xml, key .. "#name")
        if name ~= nil then
            ModMuxKeys.gameCategories[name] = getXMLString(xml, key .. "#category") or ""
            count = count + 1
        end
    end)
    delete(xml)
    return count
end

--- every active mod's actions and default keys: actions[name] = {mod, category}, defaults[name] = {{device, input}}
function ModMuxKeys.readModActions(mods)
    local actions, defaults = {}, {}
    for _, mod in ipairs(mods) do
        if mod.dir ~= nil and mod.dir ~= "" and mod.name ~= ModMux.MOD_NAME then
            local dir = mod.dir:sub(-1) == "/" and mod.dir or (mod.dir .. "/")
            local xml = loadXMLFile("ModMuxModDesc", dir .. "modDesc.xml")
            if xml ~= nil and xml ~= 0 then
                eachIndexed(xml, "modDesc.actions.action(%d)", function(key)
                    local name = getXMLString(xml, key .. "#name")
                    if name ~= nil and actions[name] == nil then
                        -- "categoy" is a typo some mods ship; the game ignores it, but it tells what was meant
                        actions[name] = {mod = mod.name, category = getXMLString(xml, key .. "#category")
                            or getXMLString(xml, key .. "#categoy")}
                    end
                end)
                eachIndexed(xml, "modDesc.inputBinding.actionBinding(%d)", function(key)
                    local action = getXMLString(xml, key .. "#action")
                    if action ~= nil then
                        eachIndexed(xml, key .. ".binding(%d)", function(bindingKey)
                            local device, input = getXMLString(xml, bindingKey .. "#device"), getXMLString(xml, bindingKey .. "#input")
                            if device ~= nil and input ~= nil and input ~= "" then
                                defaults[action] = defaults[action] or {}
                                table.insert(defaults[action], {device = device, input = input})
                            end
                        end)
                    end
                end)
                delete(xml)
            end
        end
    end
    return actions, defaults
end

--- the player's saved bindings: bindings[action] = {{device, input}}; nil when there is no file
function ModMuxKeys.readUserBindings(path)
    if not fileExists(path) then
        return nil
    end
    local xml = loadXMLFile("ModMuxInputBinding", path)
    if xml == nil or xml == 0 then
        return nil
    end
    local bindings = {}
    eachIndexed(xml, "inputBinding.actionBinding(%d)", function(key)
        local action = getXMLString(xml, key .. "#action")
        if action ~= nil then
            bindings[action] = bindings[action] or {}
            eachIndexed(xml, key .. ".binding(%d)", function(bindingKey)
                local device, input = getXMLString(xml, bindingKey .. "#device"), getXMLString(xml, bindingKey .. "#input")
                if device ~= nil and input ~= nil and input ~= "" then
                    table.insert(bindings[action], {device = device, input = input})
                end
            end)
        end
    end)
    delete(xml)
    return bindings
end

----------------------------------------------------------------------------------------------------------------
-- Conflicts
----------------------------------------------------------------------------------------------------------------

--- conflict = {id, device, keys, keyText, kind = mods|game, severity, actions = {{name, mod, category}}}
function ModMuxKeys.analyze(userBindings, modActions, defaults, gameCategories)
    local bindings = {}
    for action, list in pairs(userBindings or {}) do
        bindings[action] = list
    end
    -- mod actions the player's file doesn't have yet keep their default keys
    for action, list in pairs(defaults or {}) do
        if bindings[action] == nil then
            bindings[action] = list
        end
    end

    local groups, order = {}, {}
    for action, list in pairs(bindings) do
        local seen = {}
        for _, binding in ipairs(list) do
            local keys = ModMuxKeys.splitKeys(binding.input)
            local id = binding.device .. "|" .. table.concat(keys, " ")
            if #keys > 0 and not seen[id] then
                seen[id] = true
                if groups[id] == nil then
                    groups[id] = {id = id, device = binding.device, keys = keys, actions = {}}
                    table.insert(order, id)
                end
                table.insert(groups[id].actions, action)
            end
        end
    end

    local conflicts = {}
    table.sort(order)
    for _, id in ipairs(order) do
        local group = groups[id]
        if #group.actions >= 2 then
            table.sort(group.actions)
            local function info(action)
                local mod = modActions[action]
                if mod ~= nil then
                    return {name = action, mod = mod.mod, category = mod.category}
                end
                return {name = action, mod = nil, category = gameCategories[action]}
            end
            -- keep the actions that can fire together with a mod action
            local involved, isIn, mods = {}, {}, {}
            for i, a in ipairs(group.actions) do
                local ia = info(a)
                for j, b in ipairs(group.actions) do
                    if i ~= j then
                        local ib = info(b)
                        local differentOwner = ia.mod ~= ib.mod
                        if (ia.mod ~= nil or ib.mod ~= nil) and differentOwner and ModMuxKeys.overlap(ia.category, ib.category) then
                            for _, entry in ipairs({ia, ib}) do
                                if not isIn[entry.name] then
                                    isIn[entry.name] = true
                                    table.insert(involved, entry)
                                    if entry.mod ~= nil then
                                        mods[entry.mod] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if #involved >= 2 then
                table.sort(involved, function(x, y)
                    return x.name < y.name
                end)
                local modList = {}
                for mod in pairs(mods) do
                    table.insert(modList, mod)
                end
                table.sort(modList)
                local kind = #modList >= 2 and "mods" or "game"
                table.insert(conflicts, {id = "keys:" .. id, device = group.device, keys = group.keys,
                    keyText = ModMuxKeys.keyText(group.keys), kind = kind, severity = kind == "mods" and 2 or 1,
                    actions = involved, mods = modList})
            end
        end
    end
    -- a combination nothing uses yet, with the clash's key: "Free: Left Alt + G"
    local options = {{}, {"KEY_lalt"}, {"KEY_lshift"}, {"KEY_lctrl"}, {"KEY_lalt", "KEY_lshift"}, {"KEY_lctrl", "KEY_lshift"},
        {"KEY_lctrl", "KEY_lalt"}}
    for _, conflict in ipairs(conflicts) do
        local base = {}
        for _, key in ipairs(conflict.keys) do
            if MODIFIERS[key] == nil then
                table.insert(base, key)
            end
        end
        if conflict.device == ModMuxKeys.KEYBOARD and #base == 1 and base[1]:find("^KEY_") ~= nil then
            for _, modifiers in ipairs(options) do
                local keys = ModMuxKeys.splitKeys(table.concat(modifiers, " ") .. " " .. base[1])
                if groups[conflict.device .. "|" .. table.concat(keys, " ")] == nil then
                    conflict.free = ModMuxKeys.keyText(keys)
                    break
                end
            end
        end
    end
    table.sort(conflicts, function(a, b)
        if a.severity ~= b.severity then
            return a.severity > b.severity
        end
        if (a.device == ModMuxKeys.KEYBOARD) ~= (b.device == ModMuxKeys.KEYBOARD) then
            return a.device == ModMuxKeys.KEYBOARD
        end
        return a.keyText < b.keyText
    end)
    return conflicts
end

--- reads everything and finds the conflicts (once per load)
function ModMuxKeys.refresh()
    ModMuxKeys.loadGameActions(ModMux.MOD_DIR .. "config/gameActions.xml")
    local modActions, defaults = ModMuxKeys.readModActions(ModMuxOrigin.mods)
    local userBindings = ModMuxKeys.readUserBindings(getUserProfileAppPath() .. "inputBinding.xml")
    ModMuxKeys.modActions = modActions
    local count = 0
    for _ in pairs(modActions) do
        count = count + 1
    end
    ModMuxKeys.stats = {modActions = count, fromFile = userBindings ~= nil}
    ModMuxKeys.conflicts = ModMuxKeys.analyze(userBindings, modActions, defaults, ModMuxKeys.gameCategories)
    return ModMuxKeys.conflicts
end

--- what an action is called in the controls menu (its input_ text), or its name
function ModMuxKeys.actionText(action)
    if g_i18n == nil then
        return action.name
    end
    local key = "input_" .. action.name
    -- only texts that exist: getText of a missing one logs a warning
    if g_i18n.hasText ~= nil and not g_i18n:hasText(key, action.mod) then
        return action.name
    end
    local text = action.mod ~= nil and g_i18n:getText(key, action.mod) or g_i18n:getText(key)
    if type(text) ~= "string" or text == "" or text:find("^Missing") ~= nil or text == key then
        return action.name
    end
    return text
end

function ModMuxKeys.counts()
    local mods, game = 0, 0
    for _, conflict in ipairs(ModMuxKeys.conflicts) do
        if conflict.kind == "mods" then
            mods = mods + 1
        else
            game = game + 1
        end
    end
    return mods, game
end
