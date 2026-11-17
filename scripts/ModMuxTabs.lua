-- ModMux: what each tab of the Switchboard shows and what its buttons do. No GUI in here (tested headless):
-- ModMuxFrame only draws a model = {columns, rows, subHeader, footer, emptyText, actions} and calls run().
-- row = {id, cells = {4 texts}, colors = {per cell: good|warn|bad|dim|nil}, detailTitle, detail = {lines}, actions}
-- action = {id, text, slot (1-5: which button), run = function() -> nil | dialog request}
-- A dialog request is {confirm = text, onYes = function} or {askText = prompt, default = text, onText = function(text)}.

ModMuxTabs = {}

ModMuxTabs.CONFLICTS = 1
ModMuxTabs.LIVE = 2
ModMuxTabs.VEHICLE = 3
ModMuxTabs.PERFORMANCE = 4
ModMuxTabs.REVIEW = 5
ModMuxTabs.PROFILES = 6
ModMuxTabs.TAB_KEYS = {"mm_tab_conflicts", "mm_tab_live", "mm_tab_vehicle", "mm_tab_performance", "mm_tab_review",
    "mm_tab_profiles"}

ModMuxTabs.VIEW_SIMPLE = 1
ModMuxTabs.VIEW_CATEGORY = 2
ModMuxTabs.VIEW_ADVANCED = 3
ModMuxTabs.VIEW_KEYS = {"mm_view_simple", "mm_view_category", "mm_view_advanced"}

local t = function(key, ...)
    return ModMux.getText(key, ...)
end

local function indexOf(list, value)
    for i, entry in ipairs(list or {}) do
        if entry == value then
            return i
        end
    end
    return nil
end

----------------------------------------------------------------------------------------------------------------
-- Texts shared with the report
----------------------------------------------------------------------------------------------------------------

function ModMuxTabs.modList(mods, max)
    local names = {}
    for i, mod in ipairs(mods) do
        if i > max then
            return table.concat(names, ", ") .. string.format(" +%d", #mods - max)
        end
        table.insert(names, ModMuxOrigin.title(mod))
    end
    return table.concat(names, ", ")
end

function ModMuxTabs.kindText(conflict)
    return t("mm_kind_" .. conflict.kind)
end

function ModMuxTabs.kindColor(conflict)
    if conflict.kind == "lost" then
        return "bad"
    elseif conflict.kind == "replaced" or conflict.kind == "overwrite" then
        return "warn"
    end
    return "dim"
end

function ModMuxTabs.categoryText(category)
    return t("mm_cat_" .. category)
end

function ModMuxTabs.conflictTitle(conflict)
    if conflict.type == "types" then
        return t("mm_types_title_" .. conflict.typeKind, conflict.key)
    end
    local slot = conflict.slot
    local class = tostring(slot.container):match("([^/]+)$") or slot.container
    if slot.containerMod ~= nil and slot.container:find("/") ~= nil then
        return string.format("%s.%s [%s]", class, slot.key, ModMuxOrigin.title(slot.containerMod))
    end
    return string.format("%s.%s", class, slot.key)
end

function ModMuxTabs.planShort(conflict, plan)
    if conflict.type == "types" then
        return t("mm_plan_types")
    elseif conflict.locked then
        return t("mm_plan_locked")
    elseif plan.mode == "winner" then
        return t("mm_plan_winner", ModMuxOrigin.title(plan.mod))
    elseif plan.mode == "shared" then
        return t("mm_plan_shared")
    elseif plan.mode == "order" then
        if plan.source == "category" then
            return t("mm_plan_category", ModMuxTabs.categoryText(conflict.category))
        end
        return t("mm_plan_rank")
    end
    return t("mm_plan_default")
end

local function layerText(layer)
    return t("mm_layer_" .. layer.kind)
end

--- the chain, outermost (runs first / last word) first; then what sits hidden inside a plain replacement, then what
-- doesn't run at all
function ModMuxTabs.chainLines(layers, floor, lost, hidden)
    local lines = {t("mm_chain_head")}
    for i, layer in ipairs(layers) do
        table.insert(lines, string.format("%d. %s: %s", i, ModMuxOrigin.title(layer.owner), layerText(layer)))
    end
    if floor ~= nil then
        table.insert(lines, string.format("%d. %s", #layers + 1, t("mm_layer_floor")))
    end
    for _, entry in ipairs(hidden or {}) do
        table.insert(lines, t(entry.state == "runs" and "mm_layer_hiddenRuns" or "mm_layer_hidden", ModMuxOrigin.title(entry.mod),
            t("mm_layer_" .. entry.kind)))
    end
    for _, entry in ipairs(lost or {}) do
        table.insert(lines, t("mm_layer_lost", ModMuxOrigin.title(entry.mod), t("mm_layer_" .. entry.kind)))
    end
    return lines
end

--- plain English: what happens in this conflict and what can be done
function ModMuxTabs.explain(conflict)
    local lines = {}
    if conflict.type == "types" then
        local order = {}
        for _, layer in ipairs(conflict.layers) do
            table.insert(order, ModMuxOrigin.title(layer.owner))
        end
        table.insert(lines, t("mm_ex_types", #conflict.types, ModMuxTabs.modList(conflict.mods, 4), conflict.key))
        table.insert(lines, t("mm_ex_typesOrder", table.concat(order, " > ")))
        local shown = {}
        for i, name in ipairs(conflict.types) do
            if i > 6 then
                table.insert(shown, string.format("+%d", #conflict.types - 6))
                break
            end
            table.insert(shown, name)
        end
        table.insert(lines, t("mm_ex_typesList", table.concat(shown, ", ")))
        table.insert(lines, t("mm_ex_typesReadOnly"))
        return lines
    end

    local slotMods = conflict.slot.mods
    if conflict.kind == "lost" then
        for _, entry in ipairs(conflict.lost) do
            local mod = ModMuxOrigin.title(entry.mod)
            if entry.replacer ~= nil then
                local who = ModMuxOrigin.title(entry.replacer)
                if entry.calls ~= nil and entry.calls > 0 then
                    table.insert(lines, t("mm_ex_lostSeen", mod, who, entry.calls, mod))
                else
                    table.insert(lines, t("mm_ex_lostEarlier", mod, who, mod))
                end
            else
                local others = {}
                for _, owner in ipairs(slotMods) do
                    if owner ~= entry.mod then
                        table.insert(others, owner)
                    end
                end
                local who = #others > 0 and ModMuxTabs.modList(others, 3) or t("mm_owner_unknown")
                table.insert(lines, t(entry.confirmed and "mm_ex_lost" or "mm_ex_lostLikely", mod, who, mod))
            end
        end
        table.insert(lines, t("mm_ex_lostFix"))
    elseif conflict.kind == "replaced" or conflict.kind == "overwrite" then
        -- the outermost mod that sits on top of another mod's change; the hidden changes sit under the innermost layer
        local outer, below = nil, {}
        for i, layer in ipairs(conflict.layers) do
            if ModMuxOrigin.isMod(layer.owner) and (layer.kind == "overwrite" or layer.kind == "replace") then
                for j = i + 1, #conflict.layers do
                    local other = conflict.layers[j].owner
                    if ModMuxOrigin.isMod(other) and other ~= layer.owner and indexOf(below, other) == nil then
                        table.insert(below, other)
                    end
                end
                for _, entry in ipairs(conflict.hidden or {}) do
                    if entry.mod ~= layer.owner and indexOf(below, entry.mod) == nil then
                        table.insert(below, entry.mod)
                    end
                end
                if #below > 0 then
                    outer = layer.owner
                    break
                end
            end
        end
        if outer ~= nil then
            table.insert(lines, t("mm_ex_" .. conflict.kind, ModMuxOrigin.title(outer), ModMuxTabs.modList(below, 3)))
        end
        if conflict.kind == "replaced" then
            table.insert(lines, t("mm_ex_replacedWatch"))
        end
        for _, entry in ipairs(conflict.hidden or {}) do
            if entry.state == "runs" then
                table.insert(lines, t("mm_ex_hiddenRuns", ModMuxOrigin.title(entry.mod)))
            end
        end
        table.insert(lines, t("mm_ex_blockFix"))
    else
        local order = {}
        for i = #conflict.layers, 1, -1 do
            local owner = conflict.layers[i].owner
            if ModMuxOrigin.isMod(owner) and indexOf(order, owner) == nil then
                table.insert(order, owner)
            end
        end
        local titles = {}
        for _, owner in ipairs(order) do
            table.insert(titles, ModMuxOrigin.title(owner))
        end
        table.insert(lines, t("mm_ex_shared", table.concat(titles, " > ")))
        table.insert(lines, t("mm_ex_sharedFix"))
    end
    if conflict.locked then
        table.insert(lines, t("mm_ex_locked_" .. tostring(conflict.lockReason)))
    end
    return lines
end

----------------------------------------------------------------------------------------------------------------
-- Review texts
----------------------------------------------------------------------------------------------------------------

function ModMuxTabs.findingTitle(finding)
    local mods = finding.mods
    if finding.kind == "hard" then
        return t("mm_rev_hard", ModMuxOrigin.title(mods[2]), ModMuxOrigin.title(mods[1]))
    elseif finding.kind == "duplicate" then
        -- the titles are often the same: name the files
        return t("mm_rev_duplicate", table.concat(mods, ", "))
    end
    return t("mm_rev_" .. finding.kind, ModMuxOrigin.title(mods[1]), ModMuxOrigin.title(mods[2]))
end

function ModMuxTabs.evidenceLines(finding)
    local lines = {}
    for _, entry in ipairs(finding.evidence or {}) do
        if entry.text ~= nil then
            table.insert(lines, entry.text)
        else
            local args = {}
            for i, arg in ipairs(entry.args or {}) do
                args[i] = entry.argKeys and t(arg) or arg
            end
            if #args > 0 then
                table.insert(lines, t(entry.key, unpack(args)))
            else
                table.insert(lines, t(entry.key))
            end
        end
    end
    return lines
end

----------------------------------------------------------------------------------------------------------------
-- Models
----------------------------------------------------------------------------------------------------------------

local function action(id, textKey, slot, run, ...)
    return {id = id, text = t(textKey, ...), slot = slot, run = run}
end

local function saveAnd(f)
    return function(...)
        local result = f(...)
        ModMux.saveSettings()
        return result
    end
end

function ModMuxTabs.footer()
    if ModMux.safeMode then
        local key = "mm_footer_safe_" .. tostring(ModMux.safeReason)
        if ModMux.safeReason ~= "killSwitch" and not ModMux.settings.options.leversSuspended then
            key = "mm_footer_safeResumed"
        end
        return t(key), "bad"
    end
    local pending = ModMux.pendingCount()
    if pending > 0 then
        return t("mm_footer_pending", pending), "warn"
    end
    return t("mm_footer_ok"), nil
end

local function slotConflicts(category)
    local list = {}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        if conflict.type == "slot" and (category == nil or conflict.category == category) then
            table.insert(list, conflict)
        end
    end
    return list
end

--- mods taking part in conflicts: {mod -> {conflicts, opponents, serious}}, display order (ranked first)
function ModMuxTabs.involved(conflicts, rank)
    local byMod, mods = {}, {}
    for _, conflict in ipairs(conflicts) do
        for _, mod in ipairs(conflict.mods) do
            local entry = byMod[mod]
            if entry == nil then
                entry = {mod = mod, conflicts = {}, opponents = {}, serious = 0}
                byMod[mod] = entry
                table.insert(mods, mod)
            end
            table.insert(entry.conflicts, conflict)
            if conflict.severity >= 3 then
                entry.serious = entry.serious + 1
            end
            for _, other in ipairs(conflict.mods) do
                if other ~= mod then
                    entry.opponents[other] = true
                end
            end
        end
    end
    table.sort(mods, function(a, b)
        local ia, ib = indexOf(rank, a), indexOf(rank, b)
        if ia ~= nil and ib ~= nil then
            return ia < ib
        elseif ia ~= nil or ib ~= nil then
            return ia ~= nil
        end
        return ModMuxOrigin.title(a):lower() < ModMuxOrigin.title(b):lower()
    end)
    return mods, byMod
end

function ModMuxTabs.moveInRank(rank, mod, direction)
    local i = indexOf(rank, mod)
    if direction > 0 then
        if i == nil then
            table.insert(rank, mod)
        elseif i > 1 then
            rank[i], rank[i - 1] = rank[i - 1], rank[i]
        else
            return false
        end
    else
        if i == nil then
            return false
        elseif i < #rank then
            rank[i], rank[i + 1] = rank[i + 1], rank[i]
        else
            table.remove(rank, i)
        end
    end
    return true
end

local function countKeys(map)
    local n = 0
    for _ in pairs(map) do
        n = n + 1
    end
    return n
end

local function rankRow(id, mod, entry, rank, appliedRank, firstCell)
    local position = indexOf(rank, mod)
    local pending = position ~= indexOf(appliedRank, mod)
    local status = position ~= nil and t("mm_status_ranked") or t("mm_status_loadOrder")
    if pending then
        status = t("mm_status_pending")
    end
    local fights = {}
    for _, conflict in ipairs(entry.conflicts) do
        local opponents = {}
        for _, other in ipairs(conflict.mods) do
            if other ~= mod then
                table.insert(opponents, other)
            end
        end
        table.insert(fights, t("mm_simple_fight", ModMuxTabs.conflictTitle(conflict), ModMuxTabs.modList(opponents, 2),
            ModMuxTabs.kindText(conflict)))
    end
    local detail = {position ~= nil and t("mm_simple_rankLine", position) or t("mm_simple_unranked"), t("mm_simple_help"), "",
        t("mm_simple_fightsHead")}
    for i, line in ipairs(fights) do
        if i > 12 then
            table.insert(detail, t("mm_ev_more", #fights - 12))
            break
        end
        table.insert(detail, line)
    end
    return {id = id, mod = mod,
        cells = {firstCell, t("mm_cell_opponents", countKeys(entry.opponents)), t("mm_cell_conflicts", #entry.conflicts, entry.serious),
            status},
        colors = {nil, nil, entry.serious > 0 and "bad" or nil, pending and "warn" or nil}, detailTitle = ModMuxOrigin.title(mod),
        detail = detail}
end

function ModMuxTabs.simpleModel(ui)
    local settings = ModMux.settings
    local conflicts = slotConflicts(nil)
    local mods, byMod = ModMuxTabs.involved(conflicts, settings.rank)
    local rows = {}
    for _, mod in ipairs(mods) do
        local position = indexOf(settings.rank, mod)
        local first = position ~= nil and string.format("#%d  %s", position, ModMuxOrigin.title(mod))
            or string.format("-   %s", ModMuxOrigin.title(mod))
        local row = rankRow("mod:" .. mod, mod, byMod[mod], settings.rank, ModMux.applied.rank, first)
        row.actions = {
            action("raise", "mm_act_raise", 1, saveAnd(function()
                ModMuxTabs.moveInRank(settings.rank, mod, 1)
            end)),
            action("lower", "mm_act_lower", 2, saveAnd(function()
                ModMuxTabs.moveInRank(settings.rank, mod, -1)
            end)),
        }
        if #settings.rank > 0 then
            table.insert(row.actions, action("resetRank", "mm_act_resetRank", 3, function()
                return {confirm = t("mm_confirm_resetRank"), onYes = saveAnd(function()
                    settings.rank = {}
                end)}
            end))
        end
        table.insert(rows, row)
    end
    return {columns = {t("mm_col_mod"), t("mm_col_fights"), t("mm_col_conflicts"), t("mm_col_status")}, rows = rows,
        emptyText = t("mm_empty_conflicts")}
end

function ModMuxTabs.categoryModel(ui)
    local settings = ModMux.settings
    local rows = {}
    for _, category in ipairs(ModMuxScan.categoryIds()) do
        local conflicts = slotConflicts(category)
        if #conflicts > 0 then
            settings.categoryRank[category] = settings.categoryRank[category] or {}
            local rank = settings.categoryRank[category]
            local mods, byMod = ModMuxTabs.involved(conflicts, rank)
            for _, mod in ipairs(mods) do
                local position = indexOf(rank, mod)
                local row = rankRow("cat:" .. category .. ":" .. mod, mod, byMod[mod], rank, ModMux.applied.categoryRank[category],
                    ModMuxTabs.categoryText(category))
                row.cells[2] = position ~= nil and string.format("#%d  %s", position, ModMuxOrigin.title(mod))
                    or string.format("-   %s", ModMuxOrigin.title(mod))
                row.cells[3] = t("mm_cell_conflicts", #byMod[mod].conflicts, byMod[mod].serious)
                table.insert(row.detail, 2, t("mm_category_help", ModMuxTabs.categoryText(category)))
                row.actions = {
                    action("raise", "mm_act_raise", 1, saveAnd(function()
                        ModMuxTabs.moveInRank(rank, mod, 1)
                    end)),
                    action("lower", "mm_act_lower", 2, saveAnd(function()
                        ModMuxTabs.moveInRank(rank, mod, -1)
                    end)),
                }
                if #rank > 0 then
                    table.insert(row.actions, action("resetCategory", "mm_act_resetCategory", 3, saveAnd(function()
                        settings.categoryRank[category] = {}
                    end)))
                end
                table.insert(rows, row)
            end
        end
    end
    return {columns = {t("mm_col_category"), t("mm_col_mod"), t("mm_col_conflicts"), t("mm_col_status")}, rows = rows,
        emptyText = t("mm_empty_conflicts")}
end

--- the next choice of "Pick winner": load order -> each mod -> load order
local function nextWinner(conflict, pick)
    local current = pick ~= nil and pick.mode == "winner" and indexOf(conflict.mods, pick.mod) or 0
    if current >= #conflict.mods then
        return nil
    end
    return {mode = "winner", mod = conflict.mods[current + 1]}
end

function ModMuxTabs.advancedModel(ui)
    local settings = ModMux.settings
    local rows = {}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        local plan = ModMuxLevers.planFor(conflict, settings)
        local appliedPlan = ModMuxLevers.planFor(conflict, ModMux.applied)
        local pending = not ModMuxLevers.samePlan(plan, appliedPlan)
        local status = ModMuxTabs.planShort(conflict, plan)
        if pending then
            status = t("mm_status_next", status)
        end
        local detail = ModMuxTabs.explain(conflict)
        table.insert(detail, "")
        local chain = conflict.after or conflict.layers
        for _, line in ipairs(ModMuxTabs.chainLines(chain, conflict.after == nil and conflict.floor or nil,
            conflict.after == nil and conflict.lost or nil, conflict.after == nil and conflict.hidden or nil)) do
            table.insert(detail, line)
        end
        table.insert(detail, "")
        local applied = ModMuxLevers.applied[conflict.id]
        if applied ~= nil then
            table.insert(detail, t("mm_ex_thisLoad", ModMuxTabs.planShort(conflict, applied.plan), t("mm_build_" .. applied.status)))
        else
            table.insert(detail, t("mm_ex_thisLoad", ModMuxTabs.planShort(conflict, appliedPlan), t("mm_build_none")))
        end
        if pending then
            table.insert(detail, t("mm_ex_nextLoad", ModMuxTabs.planShort(conflict, plan)))
        end
        if conflict.type == "slot" then
            table.insert(detail, t("mm_ex_category", ModMuxTabs.categoryText(conflict.category)))
        end

        local row = {id = conflict.id, conflict = conflict,
            cells = {ModMuxTabs.conflictTitle(conflict), ModMuxTabs.modList(conflict.mods, 2), ModMuxTabs.kindText(conflict), status},
            colors = {nil, nil, ModMuxTabs.kindColor(conflict), pending and "warn" or nil},
            detailTitle = ModMuxTabs.conflictTitle(conflict),
            detail = detail, actions = {}}
        if conflict.type == "slot" and not conflict.locked then
            local pick = settings.picks[conflict.id]
            local nextPick = nextWinner(conflict, pick)
            local nextText = nextPick ~= nil and t("mm_act_winnerNext", ModMuxOrigin.title(nextPick.mod)) or t("mm_act_winnerNone")
            table.insert(row.actions, {id = "winner", text = nextText, slot = 1, run = saveAnd(function()
                settings.picks[conflict.id] = nextPick
            end)})
            if #conflict.lost > 0 or (pick ~= nil and pick.mode == "shared") then
                local isShared = pick ~= nil and pick.mode == "shared"
                table.insert(row.actions, action("shared", isShared and "mm_act_sharedOff" or "mm_act_sharedOn", 2, saveAnd(function()
                    settings.picks[conflict.id] = (not isShared) and {mode = "shared"} or nil
                end)))
            end
            if pick ~= nil then
                table.insert(row.actions, action("reset", "mm_act_resetPick", 3, saveAnd(function()
                    settings.picks[conflict.id] = nil
                end)))
            end
        end
        table.insert(rows, row)
    end
    return {columns = {t("mm_col_function"), t("mm_col_mods"), t("mm_col_kind"), t("mm_col_decision")}, rows = rows,
        emptyText = t("mm_empty_conflicts")}
end

function ModMuxTabs.conflictsModel(ui)
    local model
    if ui.view == ModMuxTabs.VIEW_CATEGORY then
        model = ModMuxTabs.categoryModel(ui)
    elseif ui.view == ModMuxTabs.VIEW_ADVANCED then
        model = ModMuxTabs.advancedModel(ui)
    else
        model = ModMuxTabs.simpleModel(ui)
    end
    local counts = {0, 0, 0}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        counts[conflict.severity] = counts[conflict.severity] + 1
    end
    model.subHeader = t("mm_sub_conflicts", t(ModMuxTabs.VIEW_KEYS[ui.view]), #ModMuxScan.conflicts, counts[3], counts[2], counts[1])
    local early = #ModMux.earlyMods()
    if early > 0 then
        model.subHeader = model.subHeader .. t("mm_sub_early", early)
    end
    model.globalActions = {action("view", "mm_act_view", 6, function()
        ui.view = ui.view % 3 + 1
    end, t(ModMuxTabs.VIEW_KEYS[ui.view % 3 + 1]))}
    if ModMux.safeMode and ModMux.safeReason ~= "killSwitch" then
        if ModMux.settings.options.leversSuspended then
            table.insert(model.globalActions, action("resume", "mm_act_resume", 5, function()
                return {confirm = t("mm_confirm_resume"), onYes = function()
                    ModMux.resumeLevers()
                end}
            end))
        end
    elseif not ModMux.safeMode then
        table.insert(model.globalActions, action("suspend", "mm_act_suspend", 5, function()
            return {confirm = t("mm_confirm_suspend"), onYes = function()
                ModMux.suspendLevers()
            end}
        end))
    end
    if not ModMuxOrigin.hasFenv then
        model.emptyText = t("mm_empty_noOwners")
    elseif early > 0 and #ModMuxScan.conflicts == 0 then
        model.emptyText = t("mm_empty_conflictsEarly", early, ModMux.ZIP_NAME .. ".zip")
    end
    return model
end

function ModMuxTabs.liveModel(ui)
    local rows = {}
    for _, entry in ipairs(ModMuxLive.list) do
        local mod = entry.modName ~= nil and ModMuxOrigin.title(entry.modName) or "?"
        local detail = {}
        if entry.description ~= nil then
            table.insert(detail, tostring(entry.description))
            table.insert(detail, "")
        end
        table.insert(detail, t("mm_live_from", mod))
        if entry.kind == "number" then
            table.insert(detail, t("mm_live_range", tostring(entry.min), tostring(entry.max), tostring(entry.step)))
        end
        table.insert(detail, t("mm_live_help"))
        local row = {id = "live:" .. entry.id, cells = {entry.title, mod, ModMuxLive.valueText(entry), t("mm_status_instant")},
            detailTitle = entry.title, detail = detail, actions = {}}
        if entry.kind == "bool" then
            table.insert(row.actions, action("toggle", "mm_act_toggle", 1, function()
                ModMuxLive.step(entry, 1)
            end))
        else
            table.insert(row.actions, action("next", "mm_act_increase", 1, function()
                ModMuxLive.step(entry, 1)
            end))
            table.insert(row.actions, action("previous", "mm_act_decrease", 2, function()
                ModMuxLive.step(entry, -1)
            end))
        end
        table.insert(rows, row)
    end
    return {columns = {t("mm_col_setting"), t("mm_col_mod"), t("mm_col_value"), ""}, rows = rows,
        subHeader = t("mm_sub_live", #rows), emptyText = t("mm_empty_live")}
end

local LEVEL_KEYS = {good = "mm_level_good", warn = "mm_level_warn", bad = "mm_level_bad"}

function ModMuxTabs.vehicleModel(ui)
    local vehicle = ModMuxVehicle.getCurrent()
    local rows = {}
    for i, entry in ipairs(ModMuxVehicle.rows(vehicle) or {}) do
        table.insert(rows, {id = "veh:" .. i, cells = {entry.label, entry.value, "", entry.level ~= nil and t(LEVEL_KEYS[entry.level]) or ""},
            colors = {nil, nil, nil, entry.level}, detailTitle = entry.label, detail = entry.detail or {t("mm_veh_live")},
            actions = {}})
    end
    return {columns = {t("mm_col_reading"), t("mm_col_value"), "", t("mm_col_status")}, rows = rows,
        subHeader = vehicle ~= nil and t("mm_sub_vehicle") or "", emptyText = t("mm_empty_vehicle"), live = true}
end

function ModMuxTabs.budgetMs()
    return 1000 / math.max(1, ModMux.settings.options.budgetFps or 60)
end

function ModMuxTabs.performanceModel(ui)
    local settings = ModMux.settings
    local budget = ModMuxTabs.budgetMs()
    local rows = {}
    for _, entry in ipairs(ModMuxPerf.list()) do
        local mod = entry.mod
        local share = entry.ms / budget
        local parkedNow = ModMuxPerf.parked[mod] ~= nil
        local parkedNext = settings.hibernate[mod] == true
        local status = ""
        if parkedNow and parkedNext then
            status = t("mm_status_parked")
        elseif parkedNext then
            status = t("mm_status_parksNext")
        elseif parkedNow then
            status = t("mm_status_unparksNext")
        end
        local detail = {t("mm_perf_avg", entry.ms, entry.peak), t("mm_perf_share", share * 100, settings.options.budgetFps),
            t("mm_perf_functions", entry.functions, entry.listeners), "", t("mm_perf_parkHelp")}
        if not ModMuxPerf.canPark(mod) and not parkedNext then
            table.insert(detail, t("mm_perf_cantPark"))
        end
        local row = {id = "perf:" .. mod, cells = {ModMuxOrigin.title(mod), string.format("%.2f ms", entry.ms),
            string.format("%.1f %%", share * 100), status},
            colors = {nil, nil, (share >= 0.10 and "bad") or (share >= 0.03 and "warn") or nil, status ~= "" and "warn" or nil},
            detailTitle = ModMuxOrigin.title(mod), detail = detail, actions = {}}
        if parkedNext or ModMuxPerf.canPark(mod) then
            table.insert(row.actions, action("park", parkedNext and "mm_act_unpark" or "mm_act_park", 1, saveAnd(function()
                settings.hibernate[mod] = (not parkedNext) or nil
            end)))
        end
        table.insert(rows, row)
    end
    local frameMs = ModMuxPerf.frameMs
    local fps = frameMs > 0 and math.floor(1000 / frameMs + 0.5) or 0
    local model = {columns = {t("mm_col_mod"), t("mm_col_perFrame"), t("mm_col_budget"), t("mm_col_status")}, rows = rows,
        subHeader = t("mm_sub_perf", frameMs, fps, ModMuxPerf.totalMs(), settings.options.budgetFps, budget), live = true,
        emptyText = ModMuxPerf.installed and t("mm_empty_perf") or t("mm_empty_perfOff")}
    model.globalActions = {
        action("resetStats", "mm_act_resetStats", 2, function()
            ModMuxPerf.resetStats()
        end),
        action("probes", settings.options.perfProbes and "mm_act_probesOff" or "mm_act_probesOn", 3, saveAnd(function()
            settings.options.perfProbes = not settings.options.perfProbes
        end)),
    }
    return model
end

function ModMuxTabs.reviewModel(ui)
    local settings = ModMux.settings
    local rows = {}
    local kindKeys = {duplicate = "mm_revkind_duplicate", incompatible = "mm_revkind_incompatible", hard = "mm_revkind_hard",
        hud = "mm_revkind_hud"}
    for _, finding in ipairs(ModMuxReview.list(settings.dismissed, ui.showDismissed)) do
        local detail = ModMuxTabs.evidenceLines(finding)
        table.insert(detail, "")
        table.insert(detail, t("mm_rev_help_" .. finding.kind))
        local row = {id = finding.id, cells = {ModMuxTabs.findingTitle(finding), t(kindKeys[finding.kind]),
            ModMuxTabs.modList(finding.mods, 2), finding.dismissed and t("mm_status_dismissed") or ""},
            colors = {finding.dismissed and "dim" or nil, finding.dismissed and "dim" or (finding.severity >= 3 and "bad" or "warn"),
                nil, "dim"},
            detailTitle = ModMuxTabs.findingTitle(finding), detail = detail, actions = {}}
        table.insert(row.actions, action("dismiss", finding.dismissed and "mm_act_restore" or "mm_act_dismiss", 1, saveAnd(function()
            settings.dismissed[finding.id] = (not finding.dismissed) or nil
        end)))
        table.insert(rows, row)
    end
    local model = {columns = {t("mm_col_finding"), t("mm_col_kind"), t("mm_col_mods"), t("mm_col_status")}, rows = rows,
        subHeader = t("mm_sub_review_" .. ModMuxReview.hudScanState), emptyText = t("mm_empty_review")}
    model.globalActions = {
        action("showDismissed", ui.showDismissed and "mm_act_hideDismissed" or "mm_act_showDismissed", 2, function()
            ui.showDismissed = not ui.showDismissed
        end),
    }
    if ModMuxPerf.installed and ModMuxReview.hudScanState ~= "running" then
        table.insert(model.globalActions, action("hudScan", "mm_act_hudScan", 3, function()
            ModMux.startHudScan()
            return {info = t("mm_info_hudScan")}
        end))
    end
    return model
end

function ModMuxTabs.profilesModel(ui)
    local rows = {}
    for index, profile in ipairs(ModMuxProfiles.list) do
        local counts = ModMuxProfiles.summary(profile.setup)
        local current = ModMuxProfiles.isCurrent(profile)
        local row = {id = "profile:" .. profile.name, cells = {profile.name, profile.saved,
            t("mm_cell_profile", counts.picks, counts.ranked, counts.parked), current and t("mm_status_current") or ""},
            colors = {nil, nil, nil, current and "good" or nil}, detailTitle = profile.name,
            detail = {t("mm_profile_saved", profile.saved), t("mm_profile_counts", counts.picks, counts.ranked, counts.parked, counts.live),
                "", t("mm_profile_help")}, actions = {}}
        table.insert(row.actions, action("load", "mm_act_loadProfile", 1, function()
            return {confirm = t("mm_confirm_loadProfile", profile.name), onYes = function()
                ModMuxProfiles.apply(index)
            end}
        end))
        table.insert(row.actions, action("overwrite", "mm_act_overwriteProfile", 3, function()
            return {confirm = t("mm_confirm_overwriteProfile", profile.name), onYes = function()
                ModMuxProfiles.saveCurrent(profile.name)
            end}
        end))
        table.insert(row.actions, action("delete", "mm_act_deleteProfile", 4, function()
            return {confirm = t("mm_confirm_deleteProfile", profile.name), onYes = function()
                ModMuxProfiles.remove(index)
            end}
        end))
        table.insert(rows, row)
    end
    local model = {columns = {t("mm_col_profile"), t("mm_col_saved"), t("mm_col_contents"), ""}, rows = rows,
        subHeader = t("mm_sub_profiles", #rows), emptyText = t("mm_empty_profiles")}
    model.globalActions = {action("saveNew", "mm_act_saveProfile", 2, function()
        return {askText = t("mm_ask_profileName"), default = ModMuxProfiles.uniqueName(), onText = function(text)
            ModMuxProfiles.saveCurrent(text)
        end}
    end)}
    return model
end

local BUILDERS = {ModMuxTabs.conflictsModel, ModMuxTabs.liveModel, ModMuxTabs.vehicleModel, ModMuxTabs.performanceModel,
    ModMuxTabs.reviewModel, ModMuxTabs.profilesModel}

--- the model of a tab; every model gets a footer and its global actions merged after the row actions
function ModMuxTabs.build(ui)
    local model = BUILDERS[ui.tab](ui)
    model.footer, model.footerColor = ModMuxTabs.footer()
    model.globalActions = model.globalActions or {}
    model.rows = model.rows or {}
    return model
end

--- the buttons for a selected row: its own actions plus the tab's, one per slot (row actions win)
function ModMuxTabs.actionsFor(model, row)
    local bySlot, list = {}, {}
    for _, entry in ipairs(row ~= nil and row.actions or {}) do
        if bySlot[entry.slot] == nil then
            bySlot[entry.slot] = entry
            table.insert(list, entry)
        end
    end
    for _, entry in ipairs(model.globalActions or {}) do
        if bySlot[entry.slot] == nil then
            bySlot[entry.slot] = entry
            table.insert(list, entry)
        end
    end
    table.sort(list, function(a, b)
        return a.slot < b.slot
    end)
    return list
end
