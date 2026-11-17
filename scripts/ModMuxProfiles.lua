-- ModMux: the PROFILES tab. A profile is a whole setup under a name: conflict picks, rankings, parked mods and the
-- live settings. Kept in modSettings/FS25_ModMux/profiles.xml. Loading one replaces the setup; picks, rankings and
-- parking apply on the next load like any other change, live settings at once.

ModMuxProfiles = {}

ModMuxProfiles.list = {}         -- {name, saved, setup}
ModMuxProfiles.MAX_NAME = 40

function ModMuxProfiles.path()
    return ModMux.settingsDir .. "profiles.xml"
end

function ModMuxProfiles.load()
    ModMuxProfiles.list = {}
    local path = ModMuxProfiles.path()
    if not fileExists(path) then
        return
    end
    local xml = loadXMLFile("ModMuxProfiles", path)
    if xml == nil or xml == 0 then
        return
    end
    local i = 0
    while true do
        local key = string.format("modMuxProfiles.profile(%d)", i)
        if not hasXMLProperty(xml, key) then
            break
        end
        local name = getXMLString(xml, key .. "#name")
        if name ~= nil and name ~= "" then
            table.insert(ModMuxProfiles.list, {name = name, saved = getXMLString(xml, key .. "#saved") or "",
                setup = ModMux.readSetup(xml, key)})
        end
        i = i + 1
    end
    delete(xml)
end

function ModMuxProfiles.save()
    local xml = createXMLFile("ModMuxProfiles", ModMuxProfiles.path(), "modMuxProfiles")
    if xml == nil or xml == 0 then
        return false
    end
    for i, profile in ipairs(ModMuxProfiles.list) do
        local key = string.format("modMuxProfiles.profile(%d)", i - 1)
        setXMLString(xml, key .. "#name", profile.name)
        setXMLString(xml, key .. "#saved", profile.saved or "")
        ModMux.writeSetup(xml, key, profile.setup)
    end
    saveXMLFile(xml)
    delete(xml)
    return true
end

function ModMuxProfiles.indexOf(name)
    for i, profile in ipairs(ModMuxProfiles.list) do
        if profile.name == name then
            return i
        end
    end
    return nil
end

function ModMuxProfiles.cleanName(name)
    name = tostring(name or ""):gsub("[%c<>\"&]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #name > ModMuxProfiles.MAX_NAME then
        name = name:sub(1, ModMuxProfiles.MAX_NAME)
    end
    return name
end

function ModMuxProfiles.uniqueName()
    local i = #ModMuxProfiles.list + 1
    while true do
        local name = ModMux.getText("mm_profile_defaultName", i)
        if ModMuxProfiles.indexOf(name) == nil then
            return name
        end
        i = i + 1
    end
end

--- the current setup (with the live settings' values as they are now)
function ModMuxProfiles.currentSetup()
    local setup = ModMux.copySetup(ModMux.settings)
    setup.live = ModMuxLive.snapshot()
    return setup
end

--- saves the current setup under a name (replacing a profile of that name); returns the index
function ModMuxProfiles.saveCurrent(name)
    name = ModMuxProfiles.cleanName(name)
    if name == "" then
        name = ModMuxProfiles.uniqueName()
    end
    local profile = {name = name, saved = ModMux.getDate(), setup = ModMuxProfiles.currentSetup()}
    local index = ModMuxProfiles.indexOf(name)
    if index ~= nil then
        ModMuxProfiles.list[index] = profile
    else
        table.insert(ModMuxProfiles.list, profile)
        index = #ModMuxProfiles.list
    end
    ModMuxProfiles.save()
    return index
end

function ModMuxProfiles.apply(index)
    local profile = ModMuxProfiles.list[index]
    if profile == nil then
        return false
    end
    local setup = ModMux.copySetup(profile.setup)
    local settings = ModMux.settings
    settings.rank, settings.categoryRank, settings.picks, settings.hibernate = setup.rank, setup.categoryRank, setup.picks,
        setup.hibernate
    ModMux.saveSettings()
    ModMuxLive.applySnapshot(profile.setup.live)
    return true
end

function ModMuxProfiles.remove(index)
    if ModMuxProfiles.list[index] == nil then
        return false
    end
    table.remove(ModMuxProfiles.list, index)
    ModMuxProfiles.save()
    return true
end

--- {picks, ranked, parked, live} counts of a setup
function ModMuxProfiles.summary(setup)
    local counts = {picks = 0, ranked = #(setup.rank or {}), parked = 0, live = 0}
    for _ in pairs(setup.picks or {}) do
        counts.picks = counts.picks + 1
    end
    for _, list in pairs(setup.categoryRank or {}) do
        counts.ranked = counts.ranked + #list
    end
    for _ in pairs(setup.hibernate or {}) do
        counts.parked = counts.parked + 1
    end
    for _ in pairs(setup.live or {}) do
        counts.live = counts.live + 1
    end
    return counts
end

--- true when a profile's structural parts equal the current setup
function ModMuxProfiles.isCurrent(profile)
    return ModMux.setupKey(profile.setup) == ModMux.setupKey(ModMux.settings)
end
