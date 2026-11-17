-- ModMux: the VEHICLE tab. Live numbers of the machine you sit in, read only.
-- Every value is read through the vehicle's own functions when it has them; anything missing shows as "-".

ModMuxVehicle = {}

ModMuxVehicle.MAX_WHEELS = 12

function ModMuxVehicle.getCurrent()
    local vehicle = nil
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        vehicle = g_localPlayer:getCurrentVehicle()
    end
    if vehicle == nil and g_currentMission ~= nil then
        vehicle = g_currentMission.controlledVehicle
    end
    return vehicle
end

local function call(vehicle, name, ...)
    local f = vehicle[name]
    if type(f) == "function" then
        return f(vehicle, ...)
    end
    return nil
end

local function percent(value)
    return string.format("%d %%", math.floor((tonumber(value) or 0) * 100 + 0.5))
end

local function level(value, warn, bad)
    if value == nil then
        return nil
    elseif value >= bad then
        return "bad"
    elseif value >= warn then
        return "warn"
    end
    return "good"
end

local contactNames = nil
local function contactName(contact)
    if contactNames == nil then
        contactNames = {}
        if type(WheelContactType) == "table" then
            for name, value in pairs(WheelContactType) do
                if type(value) == "number" then
                    contactNames[value] = name
                end
            end
        end
    end
    local name = contactNames[contact]
    if name == "NONE" or contact == nil then
        return ModMux.getText("mm_veh_contact_none")
    elseif name == "OBJECT" then
        return ModMux.getText("mm_veh_contact_object")
    end
    return ModMux.getText("mm_veh_contact_ground")
end

--- mods whose specializations this vehicle uses: {mod = count}
function ModMuxVehicle.modsOf(vehicle)
    local counts = {}
    for _, spec in ipairs(type(vehicle.specializations) == "table" and vehicle.specializations or {}) do
        if type(spec) == "table" then
            local owner = nil
            for _, name in ipairs({"prerequisitesPresent", "registerFunctions", "registerEventListeners", "onLoad"}) do
                local f = rawget(spec, name)
                if type(f) == "function" then
                    owner = ModMuxOrigin.ofFunction(ModMuxScan.transparent[f] or f)
                    break
                end
            end
            if owner == nil then
                for _, f in pairs(spec) do
                    if type(f) == "function" then
                        owner = ModMuxOrigin.ofFunction(ModMuxScan.transparent[f] or f)
                        break
                    end
                end
            end
            if ModMuxOrigin.isMod(owner) then
                counts[owner] = (counts[owner] or 0) + 1
            end
        end
    end
    return counts
end

--- rows {label, value, level, detail} for the VEHICLE tab; nil when you sit in nothing
function ModMuxVehicle.rows(vehicle)
    if vehicle == nil then
        return nil
    end
    local rows = {}
    local function add(labelKey, value, lvl, detail)
        table.insert(rows, {label = ModMux.getText(labelKey), value = value or "-", level = lvl, detail = detail})
    end

    local name = call(vehicle, "getFullName") or call(vehicle, "getName") or vehicle.typeName or "?"
    add("mm_veh_name", tostring(name), nil, {ModMux.getText("mm_veh_type", tostring(vehicle.typeName or "?"))})

    local speed = call(vehicle, "getLastSpeed")
    add("mm_veh_speed", speed ~= nil and string.format("%.1f km/h", speed) or nil)

    local mass = call(vehicle, "getTotalMass")
    add("mm_veh_mass", mass ~= nil and string.format("%.2f t", mass) or nil)

    local damage = call(vehicle, "getDamageAmount")
    add("mm_veh_damage", damage ~= nil and percent(damage) or nil, level(damage, 0.2, 0.5))

    local wear = call(vehicle, "getWearTotalAmount")
    add("mm_veh_wear", wear ~= nil and percent(wear) or nil, level(wear, 0.3, 0.6))

    local motorized = vehicle.spec_motorized
    local temperature = motorized ~= nil and motorized.motorTemperature ~= nil and motorized.motorTemperature.value or nil
    add("mm_veh_temp", temperature ~= nil and string.format("%d °C", math.floor(temperature + 0.5)) or nil,
        level(temperature, 95, 110))

    local started = call(vehicle, "getIsMotorStarted")
    local rpm = call(vehicle, "getMotorRpmPercentage")
    if started ~= nil then
        add("mm_veh_motor", started and (rpm ~= nil and ModMux.getText("mm_veh_running", percent(rpm)) or ModMux.getText("mm_on"))
            or ModMux.getText("mm_off"))
    end

    if type(vehicle.operatingTime) == "number" then
        add("mm_veh_hours", string.format("%.1f h", vehicle.operatingTime / 3600000))
    end

    local wheels = call(vehicle, "getWheels")
    if type(wheels) == "table" then
        for i, wheel in ipairs(wheels) do
            if i > ModMuxVehicle.MAX_WHEELS then
                break
            end
            local physics = type(wheel) == "table" and wheel.physics or nil
            if type(physics) == "table" then
                local grip = (tonumber(physics.tireGroundFrictionCoeff) or 1) * (tonumber(physics.frictionScale) or 1)
                local slip = type(physics.netInfo) == "table" and tonumber(physics.netInfo.slip) or nil
                local value = ModMux.getText("mm_veh_wheelValue", contactName(physics.contact), string.format("%.2f", grip),
                    slip ~= nil and percent(slip) or "-")
                table.insert(rows, {label = ModMux.getText("mm_veh_wheel", i), value = value, level = level(slip, 0.15, 0.35),
                    detail = {ModMux.getText("mm_veh_wheelHelp")}})
            end
        end
    end

    local mods = ModMuxVehicle.modsOf(vehicle)
    local names = {}
    for mod, count in pairs(mods) do
        table.insert(names, string.format("%s (%d)", ModMuxOrigin.title(mod), count))
    end
    table.sort(names)
    add("mm_veh_mods", #names > 0 and tostring(#names) or "0", nil, #names > 0 and names or {ModMux.getText("mm_veh_noMods")})

    local typeName = vehicle.typeName
    local fights = {}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if conflict.type == "types" and conflict.typeKind == "vehicle" then
            for _, t in ipairs(conflict.types) do
                if t == typeName then
                    table.insert(fights, conflict.key .. ": " .. ModMuxTabs.modList(conflict.mods, 3))
                    break
                end
            end
        end
    end
    add("mm_veh_fights", tostring(#fights), #fights > 0 and "warn" or "good",
        #fights > 0 and fights or {ModMux.getText("mm_veh_noFights")})
    return rows
end
