-- ModMux: what each tab of the ModMux page shows and what its buttons do. No GUI in here (tested headless):
-- ModMuxFrame only draws a model = {columns, rows, subHeader, footer, emptyText, actions} and calls run().
-- row = {id, cells = {4 texts}, colors = {per cell: good|warn|bad|dim|nil}, detailTitle, detail = {lines}, actions}
-- action = {id, text, slot (1-5: which button), run = function() -> nil | dialog request}
-- A dialog request is {confirm = text, onYes = function} or {askText = prompt, default = text, onText = function(text)}.

ModMuxTabs = {}

ModMuxTabs.OVERVIEW = 1
ModMuxTabs.CONFLICTS = 2
ModMuxTabs.KEYS = 3
ModMuxTabs.ERRORS = 4
ModMuxTabs.LIVE = 5
ModMuxTabs.VEHICLE = 6
ModMuxTabs.PERFORMANCE = 7
ModMuxTabs.REVIEW = 8
ModMuxTabs.PROFILES = 9
ModMuxTabs.TAB_KEYS = {"mm_tab_overview", "mm_tab_conflicts", "mm_tab_keys", "mm_tab_errors", "mm_tab_live", "mm_tab_vehicle",
    "mm_tab_performance", "mm_tab_review", "mm_tab_profiles"}

ModMuxTabs.VIEW_PAIRS = 1
ModMuxTabs.VIEW_SIMPLE = 2
ModMuxTabs.VIEW_CATEGORY = 3
ModMuxTabs.VIEW_ADVANCED = 4
ModMuxTabs.VIEW_KEYS = {"mm_view_pairs", "mm_view_simple", "mm_view_category", "mm_view_advanced"}

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

----------------------------------------------------------------------------------------------------------------
-- WHO BEATS WHOM: one row per pair of mods, what the one does to the other
----------------------------------------------------------------------------------------------------------------

-- strongest first: overwrites (the other's change is gone), mayOverwrite (it replaced the function, whether the other's
-- change still runs inside is found out while playing), takesOver (it wraps the other and decides whether it runs),
-- runsAfter / runsBefore (both run; the later one has the last word)
ModMuxTabs.REL_RANK = {overwrites = 4, mayOverwrite = 3, takesOver = 2, runsAfter = 1, runsBefore = 1}
ModMuxTabs.REL_COLOR = {overwrites = "bad", mayOverwrite = "warn", takesOver = "warn"}

--- {top, under, rel} for every pair of mods in one conflict (top acts on under)
function ModMuxTabs.relations(conflict)
    local out, seen = {}, {}
    local isMod = ModMuxOrigin.isMod
    local function add(top, under, rel)
        if top == nil or under == nil or top == under or not isMod(top) or not isMod(under) then
            return
        end
        local key = top .. ">" .. under
        local old = seen[key]
        if old == nil then
            seen[key] = {top = top, under = under, rel = rel}
            table.insert(out, seen[key])
        elseif ModMuxTabs.REL_RANK[rel] > ModMuxTabs.REL_RANK[old.rel] then
            old.rel = rel
        end
    end
    local layers = conflict.layers or {}
    -- changes that are gone: the mods that put in their own version threw them away
    local replacers = {}
    for _, layer in ipairs(layers) do
        if layer.kind == "replace" and indexOf(replacers, layer.owner) == nil then
            table.insert(replacers, layer.owner)
        end
    end
    if #replacers == 0 then
        for _, mod in ipairs(conflict.slot ~= nil and conflict.slot.mods or {}) do
            table.insert(replacers, mod)
        end
    end
    for _, entry in ipairs(conflict.lost or {}) do
        for _, mod in ipairs(replacers) do
            add(mod, entry.mod, "overwrites")
        end
    end
    -- changes under a plain replacement (the innermost layer): they run only if that version passes them on
    local bottom = layers[#layers]
    for _, entry in ipairs(conflict.hidden or {}) do
        if bottom ~= nil then
            add(bottom.owner, entry.mod, entry.state == "runs" and "takesOver" or "mayOverwrite")
        end
    end
    for i, outer in ipairs(layers) do
        for j = i + 1, #layers do
            local rel = "runsAfter"
            if outer.kind == "overwrite" or outer.kind == "replace" then
                rel = "takesOver"
            elseif outer.kind == "prepend" then
                rel = "runsBefore"
            end
            add(outer.owner, layers[j].owner, rel)
        end
    end
    return out
end

--- pairs of mods over all conflicts: {top, under, rel (strongest), items = {{conflict, rel}}}, strongest first
function ModMuxTabs.pairList()
    local byKey, list = {}, {}
    for _, conflict in ipairs(ModMuxScan.conflicts) do
        for _, relation in ipairs(ModMuxTabs.relations(conflict)) do
            local key = relation.top .. ">" .. relation.under
            local pair = byKey[key]
            if pair == nil then
                pair = {key = key, top = relation.top, under = relation.under, rel = relation.rel, items = {}}
                byKey[key] = pair
                table.insert(list, pair)
            elseif ModMuxTabs.REL_RANK[relation.rel] > ModMuxTabs.REL_RANK[pair.rel] then
                pair.rel = relation.rel
            end
            table.insert(pair.items, {conflict = conflict, rel = relation.rel})
        end
    end
    for _, pair in ipairs(list) do
        table.sort(pair.items, function(a, b)
            local ra, rb = ModMuxTabs.REL_RANK[a.rel], ModMuxTabs.REL_RANK[b.rel]
            if ra ~= rb then
                return ra > rb
            end
            return a.conflict.id < b.conflict.id
        end)
    end
    table.sort(list, function(a, b)
        local ra, rb = ModMuxTabs.REL_RANK[a.rel], ModMuxTabs.REL_RANK[b.rel]
        if ra ~= rb then
            return ra > rb
        end
        if #a.items ~= #b.items then
            return #a.items > #b.items
        end
        return a.key < b.key
    end)
    return list
end

--- puts `winner` directly above `loser` in a ranking (highest first); ranked mods beat unranked ones
function ModMuxTabs.rankAbove(rank, winner, loser)
    for i = #rank, 1, -1 do
        if rank[i] == winner then
            table.remove(rank, i)
        end
    end
    local at = indexOf(rank, loser)
    if at ~= nil then
        table.insert(rank, at, winner)
    else
        table.insert(rank, winner)
    end
end

--- "drawControlledEntityHUD" -> "draw controlled entity HUD"; "ProductionPoint" -> "Production point"
function ModMuxTabs.humanize(name)
    local spaced = tostring(name):gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
    local words = {}
    for word in spaced:gmatch("%S+") do
        if #word > 1 and word:upper() == word then
            table.insert(words, word)
        else
            table.insert(words, word:lower())
        end
    end
    local text = table.concat(words, " ")
    return text:sub(1, 1):upper() .. text:sub(2)
end

--- a function in words: "Production point: load" (vehicle / building type chains keep their title)
function ModMuxTabs.functionText(conflict)
    if conflict.type == "types" then
        return ModMuxTabs.conflictTitle(conflict)
    end
    local slot = conflict.slot
    local class = tostring(slot.container):match("([^/]+)$") or slot.container
    local key = ModMuxTabs.humanize(slot.key)
    return string.format("%s: %s", ModMuxTabs.humanize(class), key:sub(1, 1):lower() .. key:sub(2))
end

ModMuxTabs.VERDICT = {overwrites = "broken", mayOverwrite = "check", takesOver = "probablyFine", runsAfter = "fine",
    runsBefore = "fine"}
ModMuxTabs.VERDICT_COLOR = {broken = "bad", check = "warn", probablyFine = "dim", fine = "good"}

--- pairs that need a look (broken or to check)
function ModMuxTabs.needsLook(pair)
    return pair.rel == "overwrites" or pair.rel == "mayOverwrite"
end

--- Pair buttons work through the overall ranking (SIMPLE): only the order between the two changes, nobody is muted
-- (a winner pick would mute every other mod in a shared function). A ranked mod's change that the other mod threw away
-- comes back on top; one that may still run inside the other's own version stays until playing shows it's blocked.
function ModMuxTabs.pairsModel(ui)
    local settings = ModMux.settings
    local rows = {}
    local hidden = 0
    for _, pair in ipairs(ModMuxTabs.pairList()) do
        if not ui.showHarmless and not ModMuxTabs.needsLook(pair) then
            hidden = hidden + 1
        else
            table.insert(rows, ModMuxTabs.pairRow(pair, settings))
        end
    end
    local model = {columns = {t("mm_col_mod"), t("mm_col_does"), t("mm_col_toMod"), t("mm_col_verdict")}, rows = rows,
        emptyText = hidden > 0 and t("mm_empty_pairsHarmless", hidden) or t("mm_empty_conflicts"),
        subHeaderExtra = t("mm_sub_pairs", #rows, hidden)}
    model.extraActions = {action("harmless", ui.showHarmless and "mm_act_hideHarmless" or "mm_act_showHarmless", 5, function()
        ui.showHarmless = not ui.showHarmless
    end, hidden)}
    return model
end

function ModMuxTabs.pairRow(pair, settings)
    local topTitle, underTitle = ModMuxOrigin.title(pair.top), ModMuxOrigin.title(pair.under)
    local settable, locked, anyPick, anyBoth = {}, 0, false, false
    local pTop, pUnder = ModMuxLevers.priority(settings.rank, pair.top), ModMuxLevers.priority(settings.rank, pair.under)
    local ranked = pTop ~= pUnder
    local verdict = ModMuxTabs.VERDICT[pair.rel]
    local detail = {t("mm_relx_" .. pair.rel, topTitle, underTitle, underTitle), "", t("mm_suggest_" .. verdict, underTitle), "",
        t("mm_pair_where")}
    for i, item in ipairs(pair.items) do
        local conflict = item.conflict
        if i <= 12 then
            table.insert(detail, t("mm_pair_line", ModMuxTabs.functionText(conflict), t("mm_rel_" .. item.rel)))
        end
        if conflict.type == "slot" and not conflict.locked then
            table.insert(settable, conflict)
            anyPick = anyPick or settings.picks[conflict.id] ~= nil
            anyBoth = anyBoth or #(conflict.lost or {}) > 0 or #(conflict.hidden or {}) > 0
        else
            locked = locked + 1
        end
    end
    if #pair.items > 12 then
        table.insert(detail, t("mm_ev_more", #pair.items - 12))
    end
    if locked > 0 then
        table.insert(detail, t("mm_pair_locked", locked))
    end
    if ranked then
        table.insert(detail, t("mm_pair_ranked", pTop > pUnder and topTitle or underTitle, pTop > pUnder and underTitle or topTitle))
    end
    table.insert(detail, "")
    table.insert(detail, t("mm_pair_help"))
    local decided = anyPick or ranked
    local verdictText = t("mm_verdict_" .. verdict)
    if decided then
        verdictText = t("mm_verdict_set", verdictText)
    end
    local row = {id = "pair:" .. pair.key, cells = {topTitle, t("mm_rel_" .. pair.rel), underTitle, verdictText},
        colors = {nil, ModMuxTabs.REL_COLOR[pair.rel], nil, ModMuxTabs.VERDICT_COLOR[verdict]},
        detailTitle = string.format("%s / %s", topTitle, underTitle), detail = detail, actions = {}}
    if #settable > 0 then
        local function setPicks(pick)
            return saveAnd(function()
                for _, conflict in ipairs(settable) do
                    if pick == nil or #(conflict.lost or {}) > 0 or #(conflict.hidden or {}) > 0 then
                        settings.picks[conflict.id] = pick
                    end
                end
            end)
        end
        -- the suggested fix first: keep both mods working where one knocked the other out
        if anyBoth then
            table.insert(row.actions, action("both", "mm_act_pairBoth", 1, setPicks({mode = "shared"})))
        end
        table.insert(row.actions, action("winUnder", "mm_act_pairWin", anyBoth and 2 or 1, saveAnd(function()
            ModMuxTabs.rankAbove(settings.rank, pair.under, pair.top)
        end), underTitle))
        table.insert(row.actions, action("winTop", "mm_act_pairWin", anyBoth and 3 or 2, saveAnd(function()
            ModMuxTabs.rankAbove(settings.rank, pair.top, pair.under)
        end), topTitle))
        if anyPick or ranked then
            table.insert(row.actions, action("reset", "mm_act_pairReset", anyBoth and 4 or 3, saveAnd(function()
                for _, conflict in ipairs(settable) do
                    settings.picks[conflict.id] = nil
                end
                for _, mod in ipairs({pair.top, pair.under}) do
                    for i = #settings.rank, 1, -1 do
                        if settings.rank[i] == mod then
                            table.remove(settings.rank, i)
                        end
                    end
                end
            end)))
        end
    end
    return row
end

--- how many things each tab wants you to look at (shown on the tab)
function ModMuxTabs.badges()
    local badges = {}
    local conflicts = 0
    for _, pair in ipairs(ModMuxTabs.pairList()) do
        if ModMuxTabs.needsLook(pair) then
            conflicts = conflicts + 1
        end
    end
    badges[ModMuxTabs.CONFLICTS] = conflicts
    local keys = 0
    for _, conflict in ipairs(ModMuxKeys.conflicts) do
        if conflict.kind == "mods" and not ModMux.settings.dismissed[conflict.id] then
            keys = keys + 1
        end
    end
    badges[ModMuxTabs.KEYS] = keys
    local errors = 0
    for _, entry in ipairs(ModMuxErrors.entries) do
        if entry.level == "error" and ModMuxOrigin.isMod(entry.mod) then
            errors = errors + 1
        end
    end
    badges[ModMuxTabs.ERRORS] = errors
    badges[ModMuxTabs.REVIEW] = #ModMuxReview.list(ModMux.settings.dismissed, false)
    return badges
end

function ModMuxTabs.tabTexts()
    local badges = ModMuxTabs.badges()
    local texts = {}
    for i, key in ipairs(ModMuxTabs.TAB_KEYS) do
        local count = badges[i] or 0
        texts[i] = count > 0 and t("mm_tab_badge", t(key), count) or t(key)
    end
    return texts
end

function ModMuxTabs.conflictsModel(ui)
    local model
    if ui.view == ModMuxTabs.VIEW_PAIRS then
        model = ModMuxTabs.pairsModel(ui)
    elseif ui.view == ModMuxTabs.VIEW_CATEGORY then
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
    if model.subHeaderExtra ~= nil then
        model.subHeader = t("mm_sub_viewPrefix", t(ModMuxTabs.VIEW_KEYS[ui.view])) .. model.subHeaderExtra
    else
        model.subHeader = t("mm_sub_conflicts", t(ModMuxTabs.VIEW_KEYS[ui.view]), #ModMuxScan.conflicts, counts[3], counts[2],
            counts[1])
    end
    local early = #ModMux.earlyMods()
    if early > 0 then
        model.subHeader = model.subHeader .. t("mm_sub_early", early)
    end
    model.globalActions = {action("view", "mm_act_view", 6, function()
        ui.view = ui.view % #ModMuxTabs.VIEW_KEYS + 1
    end, t(ModMuxTabs.VIEW_KEYS[ui.view % #ModMuxTabs.VIEW_KEYS + 1]))}
    if ModMux.safeMode and ModMux.safeReason ~= "killSwitch" then
        if ModMux.settings.options.leversSuspended then
            table.insert(model.globalActions, action("resume", "mm_act_resume", 5, function()
                return {confirm = t("mm_confirm_resume"), onYes = function()
                    ModMux.resumeLevers()
                end}
            end))
        end
    elseif not ModMux.safeMode and ui.view == ModMuxTabs.VIEW_ADVANCED then
        -- an expert switch: only in ADVANCED
        table.insert(model.globalActions, action("suspend", "mm_act_suspend", 5, function()
            return {confirm = t("mm_confirm_suspend"), onYes = function()
                ModMux.suspendLevers()
            end}
        end))
    end
    for _, entry in ipairs(model.extraActions or {}) do
        table.insert(model.globalActions, entry)
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

----------------------------------------------------------------------------------------------------------------
-- KEYS and ERRORS
----------------------------------------------------------------------------------------------------------------

local function categoryText(category, seen)
    local words = {}
    seen = seen or {}
    local known = {onfoot = true, vehicle = true, system = true}
    for word in tostring(category or ""):gmatch("%S+") do
        local lower = word:lower()
        local text
        if known[lower] then
            text = t("mm_keycat_" .. lower)
        elseif lower:find("^menu") ~= nil then
            text = t("mm_keycat_menu")
        else
            text = lower
        end
        if not seen[text] then
            seen[text] = true
            table.insert(words, text)
        end
    end
    if #words == 0 then
        if seen[t("mm_keycat_any")] then
            return ""
        end
        seen[t("mm_keycat_any")] = true
        return t("mm_keycat_any")
    end
    return table.concat(words, ", ")
end

function ModMuxTabs.keysModel(ui)
    local settings = ModMux.settings
    local rows = {}
    local modCount, gameCount = ModMuxKeys.counts()
    for _, conflict in ipairs(ModMuxKeys.conflicts) do
        local dismissed = settings.dismissed[conflict.id] == true
        if (ui.showGameKeys or conflict.kind == "mods") and (ui.showDismissed or not dismissed) then
            local owners, where, seenWhere = {}, {}, {}
            local whereSeen = {}
            local detail = {t(conflict.kind == "mods" and "mm_keys_explainMods" or "mm_keys_explainGame", conflict.keyText), ""}
            for _, entry in ipairs(conflict.actions) do
                local owner = entry.mod ~= nil and ModMuxOrigin.title(entry.mod) or t("mm_owner_game")
                if entry.mod ~= nil then
                    table.insert(owners, entry.mod)
                end
                local situation = categoryText(entry.category)
                local new = categoryText(entry.category, whereSeen)
                if new ~= "" and not seenWhere[new] then
                    seenWhere[new] = true
                    table.insert(where, new)
                end
                table.insert(detail, t("mm_keys_action", owner, ModMuxKeys.actionText(entry), situation))
            end
            table.insert(detail, "")
            if conflict.free ~= nil then
                table.insert(detail, t("mm_keys_free", conflict.free))
            end
            table.insert(detail, t("mm_keys_fix"))
            local device = conflict.device == ModMuxKeys.KEYBOARD and "" or (t("mm_keys_controller") .. ": ")
            local gameShare = #owners < #conflict.actions
            local modsText = ModMuxTabs.modList(conflict.mods, 2) .. (gameShare and (" + " .. t("mm_owner_game")) or "")
            local row = {id = conflict.id, cells = {device .. conflict.keyText, modsText, table.concat(where, ", "),
                dismissed and t("mm_status_dismissed") or t(conflict.kind == "mods" and "mm_keys_kindMods" or "mm_keys_kindGame")},
                colors = {dismissed and "dim" or nil, nil, nil, dismissed and "dim" or (conflict.kind == "mods" and "warn" or "dim")},
                detailTitle = device .. conflict.keyText, detail = detail, actions = {}}
            table.insert(row.actions, action("dismiss", dismissed and "mm_act_restore" or "mm_act_dismiss", 1, saveAnd(function()
                settings.dismissed[conflict.id] = (not dismissed) or nil
            end)))
            table.insert(rows, row)
        end
    end
    local source = ModMuxKeys.stats.fromFile and "mm_keys_sourceFile" or "mm_keys_sourceDefaults"
    local model = {columns = {t("mm_col_keys"), t("mm_col_mods"), t("mm_col_where"), t("mm_col_kind")}, rows = rows,
        subHeader = t("mm_sub_keys", modCount, gameCount, t(source)), emptyText = t("mm_empty_keys")}
    model.globalActions = {
        action("showGame", ui.showGameKeys and "mm_act_hideGameKeys" or "mm_act_showGameKeys", 2, function()
            ui.showGameKeys = not ui.showGameKeys
        end, gameCount),
        action("showDismissed", ui.showDismissed and "mm_act_hideDismissed" or "mm_act_showDismissed", 3, function()
            ui.showDismissed = not ui.showDismissed
        end),
    }
    return model
end

--- ERRORS per mod: one row per mod, its messages in the panel
function ModMuxTabs.errorModRows(rows, ui)
    local groups, order = {}, {}
    for _, entry in ipairs(ModMuxErrors.list(false, ui.hideGameErrors)) do
        local group = groups[entry.mod]
        if group == nil then
            group = {mod = entry.mod, errors = 0, warnings = 0, total = 0, entries = {}}
            groups[entry.mod] = group
            table.insert(order, group)
        end
        if entry.level == "error" then
            group.errors = group.errors + 1
        else
            group.warnings = group.warnings + 1
        end
        group.total = group.total + entry.count
        table.insert(group.entries, entry)
    end
    if ui.errorsByCount then
        table.sort(order, function(a, b)
            if a.errors ~= b.errors then
                return a.errors > b.errors
            end
            return a.total > b.total
        end)
    end
    for _, group in ipairs(order) do
        local isMod = ModMuxOrigin.isMod(group.mod)
        local owner = isMod and ModMuxOrigin.title(group.mod) or t("mm_err_gameOrUnknown")
        local detail = {}
        for i, entry in ipairs(group.entries) do
            if i > 16 then
                table.insert(detail, t("mm_ev_more", #group.entries - 16))
                break
            end
            local text = entry.text:gsub("%s+", " ")
            table.insert(detail, t("mm_err_line", t("mm_err_level_" .. entry.level), entry.count, text))
        end
        table.insert(detail, "")
        if not isMod then
            table.insert(detail, t("mm_err_unattributed"))
        end
        table.insert(detail, t(group.errors > 0 and "mm_err_helpError" or "mm_err_helpWarning"))
        table.insert(rows, {id = "errmod:" .. group.mod, cells = {owner, t("mm_err_modCounts", group.errors, group.warnings), "",
            t(group.errors > 0 and "mm_err_verdictErrors" or "mm_err_verdictWarnings")},
            colors = {nil, nil, nil, group.errors > 0 and "bad" or "warn"}, detailTitle = owner, detail = detail, actions = {}})
    end
end

function ModMuxTabs.errorsModel(ui)
    local rows = {}
    if not ui.errorsAll then
        ModMuxTabs.errorModRows(rows, ui)
    end
    for _, entry in ipairs(ui.errorsAll and ModMuxErrors.list(ui.errorsByCount, ui.hideGameErrors) or {}) do
        local owner = ModMuxOrigin.isMod(entry.mod) and ModMuxOrigin.title(entry.mod) or t("mm_err_gameOrUnknown")
        local when = entry.duringLoad and t("mm_err_whenLoad") or t("mm_err_whenPlay")
        local detail = {entry.text, "", t("mm_err_how_" .. (entry.how == "stop" and "stop" or (entry.how == "print" and "print" or "log"))),
            t("mm_err_count", entry.count, when)}
        if not ModMuxOrigin.isMod(entry.mod) then
            table.insert(detail, t("mm_err_unattributed"))
        end
        table.insert(detail, "")
        table.insert(detail, t(entry.level == "error" and "mm_err_helpError" or "mm_err_helpWarning"))
        local first = entry.text:gsub("%s+", " ")
        table.insert(rows, {id = "err:" .. entry.order, cells = {owner, first, t("mm_err_level_" .. entry.level),
            entry.count > 1 and string.format("%dx", entry.count) or "1x"},
            colors = {nil, nil, entry.level == "error" and "bad" or "warn", entry.count >= 10 and "warn" or nil},
            detailTitle = owner, detail = detail, actions = {}})
    end
    local errors, warnings, mods = ModMuxErrors.counts()
    local columns = {t("mm_col_mod"), t("mm_col_found"), "", t("mm_col_verdict")}
    if ui.errorsAll then
        columns = {t("mm_col_mod"), t("mm_col_message"), t("mm_col_kind"), t("mm_col_count")}
    end
    local model = {columns = columns, rows = rows,
        subHeader = t("mm_sub_errors", errors, warnings, mods), emptyText = t(ModMuxErrors.installed and "mm_empty_errors"
            or "mm_empty_errorsOff")}
    model.globalActions = {
        action("allMessages", ui.errorsAll and "mm_act_errPerMod" or "mm_act_errAll", 1, function()
            ui.errorsAll = not ui.errorsAll
        end),
        action("sort", ui.errorsByCount and "mm_act_errSortMod" or "mm_act_errSortCount", 2, function()
            ui.errorsByCount = not ui.errorsByCount
        end),
        action("hideGame", ui.hideGameErrors and "mm_act_errShowGame" or "mm_act_errHideGame", 3, function()
            ui.hideGameErrors = not ui.hideGameErrors
        end),
        action("clear", "mm_act_errClear", 4, function()
            return {confirm = t("mm_confirm_errClear"), onYes = function()
                ModMuxErrors.clear()
            end}
        end),
    }
    return model
end

----------------------------------------------------------------------------------------------------------------
-- OVERVIEW: one line per area, a verdict and a button that opens it; what waits for the next load, with undo
----------------------------------------------------------------------------------------------------------------

--- what the settings change at the next load, in words
function ModMuxTabs.pendingLines()
    local settings, applied = ModMux.settings, ModMux.applied
    local lines = {}
    if settings == nil or applied == nil then
        return lines
    end
    local function titles(list)
        local out = {}
        for _, mod in ipairs(list or {}) do
            table.insert(out, ModMuxOrigin.title(mod))
        end
        return table.concat(out, " > ")
    end
    local ids = {}
    for id in pairs(settings.picks) do
        ids[id] = true
    end
    for id in pairs(applied.picks) do
        ids[id] = true
    end
    local sorted = {}
    for id in pairs(ids) do
        table.insert(sorted, id)
    end
    table.sort(sorted)
    for _, id in ipairs(sorted) do
        local before, after = applied.picks[id], settings.picks[id]
        if (before and before.mode) ~= (after and after.mode) or (before and before.mod) ~= (after and after.mod) then
            local conflict = ModMuxScan.conflictById[id]
            local name = conflict ~= nil and ModMuxTabs.functionText(conflict) or id
            local what = t("mm_plan_default")
            if after ~= nil and after.mode == "shared" then
                what = t("mm_plan_shared")
            elseif after ~= nil then
                what = t("mm_plan_winner", ModMuxOrigin.title(after.mod))
            end
            table.insert(lines, t("mm_pending_pick", name, what))
        end
    end
    if table.concat(settings.rank or {}, ",") ~= table.concat(applied.rank or {}, ",") then
        table.insert(lines, #settings.rank > 0 and t("mm_pending_rank", titles(settings.rank)) or t("mm_pending_rankCleared"))
    end
    local categories = {}
    for category in pairs(settings.categoryRank) do
        categories[category] = true
    end
    for category in pairs(applied.categoryRank) do
        categories[category] = true
    end
    for category in pairs(categories) do
        local now, before = settings.categoryRank[category] or {}, applied.categoryRank[category] or {}
        if table.concat(now, ",") ~= table.concat(before, ",") then
            table.insert(lines, t("mm_pending_category", ModMuxTabs.categoryText(category), #now > 0 and titles(now) or "-"))
        end
    end
    local mods = {}
    for mod in pairs(settings.hibernate) do
        mods[mod] = true
    end
    for mod in pairs(applied.hibernate) do
        mods[mod] = true
    end
    for mod in pairs(mods) do
        local now, before = settings.hibernate[mod] == true, applied.hibernate[mod] == true
        if now ~= before then
            table.insert(lines, t(now and "mm_pending_park" or "mm_pending_unpark", ModMuxOrigin.title(mod)))
        end
    end
    if settings.options.perfProbes ~= applied.perfProbes then
        table.insert(lines, t(settings.options.perfProbes and "mm_pending_timersOn" or "mm_pending_timersOff"))
    end
    if ModMux.safeReason ~= "killSwitch" and settings.options.leversSuspended ~= (ModMux.safeMode == true) then
        table.insert(lines, t(settings.options.leversSuspended and "mm_pending_leversOff" or "mm_pending_leversOn"))
    end
    return lines
end

--- every change since this load started is taken back
function ModMuxTabs.undoPending()
    local settings = ModMux.settings
    local copy = ModMux.copySetup(ModMux.applied)
    settings.rank, settings.categoryRank, settings.picks, settings.hibernate = copy.rank, copy.categoryRank, copy.picks,
        copy.hibernate
    settings.options.perfProbes = ModMux.applied.perfProbes
    if ModMux.safeReason ~= "killSwitch" then
        settings.options.leversSuspended = ModMux.safeMode == true
    end
    ModMux.saveSettings()
end

function ModMuxTabs.overviewModel(ui)
    local rows = {}
    local function add(id, title, summary, verdict, detail, gotoTab, gotoView)
        local row = {id = "overview:" .. id, cells = {title, summary, "", t("mm_verdict_" .. verdict)},
            colors = {nil, nil, nil, ModMuxTabs.VERDICT_COLOR[verdict]}, detailTitle = title, detail = detail, actions = {}}
        if gotoTab ~= nil then
            table.insert(row.actions, action("open", "mm_act_open", 1, function()
                return {gotoTab = gotoTab, view = gotoView}
            end, t(ModMuxTabs.TAB_KEYS[gotoTab])))
        end
        table.insert(rows, row)
        return row
    end

    if ModMux.safeMode then
        local row = add("safe", t("mm_ov_safe"), t("mm_ov_safe_" .. tostring(ModMux.safeReason)), "broken",
            {(ModMuxTabs.footer())}, nil)
        if ModMux.safeReason ~= "killSwitch" and ModMux.settings.options.leversSuspended then
            table.insert(row.actions, action("resume", "mm_act_resume", 1, function()
                return {confirm = t("mm_confirm_resume"), onYes = function()
                    ModMux.resumeLevers()
                end}
            end))
        end
    end

    -- mod fights
    local broken, check, harmless = 0, 0, 0
    local fightLines = {t("mm_ov_fights_help"), ""}
    for _, pair in ipairs(ModMuxTabs.pairList()) do
        if pair.rel == "overwrites" then
            broken = broken + 1
        elseif pair.rel == "mayOverwrite" then
            check = check + 1
        else
            harmless = harmless + 1
        end
        if ModMuxTabs.needsLook(pair) and #fightLines < 10 then
            table.insert(fightLines, t("mm_ov_pairLine", ModMuxOrigin.title(pair.top), t("mm_rel_" .. pair.rel),
                ModMuxOrigin.title(pair.under)))
        end
    end
    table.insert(fightLines, t("mm_ov_harmless", harmless))
    local fightSummary = broken > 0 and t("mm_ov_fights_broken", broken, check) or (check > 0 and t("mm_ov_fights_check", check)
        or t("mm_ov_none"))
    add("fights", t("mm_ov_fights"), fightSummary, broken > 0 and "broken" or (check > 0 and "check" or "fine"), fightLines,
        ModMuxTabs.CONFLICTS, ModMuxTabs.VIEW_PAIRS)

    -- key clashes
    local keyMods, keyGame = ModMuxKeys.counts()
    local keyLines = {t("mm_ov_keys_help"), ""}
    for _, conflict in ipairs(ModMuxKeys.conflicts) do
        if conflict.kind == "mods" and #keyLines < 10 then
            table.insert(keyLines, t("mm_ov_keyLine", conflict.keyText, ModMuxTabs.modList(conflict.mods, 3)))
        end
    end
    add("keys", t("mm_ov_keys"), keyMods > 0 and t("mm_ov_keys_some", keyMods) or t("mm_ov_none"), keyMods > 0 and "check" or "fine",
        keyLines, ModMuxTabs.KEYS)

    -- errors
    local errorMods, warnMods = {}, {}
    local perMod = {}
    for _, entry in ipairs(ModMuxErrors.entries) do
        if ModMuxOrigin.isMod(entry.mod) then
            perMod[entry.mod] = perMod[entry.mod] or {errors = 0, warnings = 0}
            if entry.level == "error" then
                perMod[entry.mod].errors = perMod[entry.mod].errors + 1
                errorMods[entry.mod] = true
            else
                perMod[entry.mod].warnings = perMod[entry.mod].warnings + 1
                warnMods[entry.mod] = true
            end
        end
    end
    local errorCount, warnCount, errorLines = 0, 0, {t("mm_ov_errors_help"), ""}
    local modsSorted = {}
    for mod in pairs(perMod) do
        table.insert(modsSorted, mod)
    end
    table.sort(modsSorted, function(a, b)
        if perMod[a].errors ~= perMod[b].errors then
            return perMod[a].errors > perMod[b].errors
        end
        return ModMuxOrigin.title(a):lower() < ModMuxOrigin.title(b):lower()
    end)
    for _, mod in ipairs(modsSorted) do
        if errorMods[mod] then
            errorCount = errorCount + 1
        elseif warnMods[mod] then
            warnCount = warnCount + 1
        end
        if #errorLines < 10 then
            table.insert(errorLines, t("mm_ov_errorLine", ModMuxOrigin.title(mod), perMod[mod].errors, perMod[mod].warnings))
        end
    end
    local errorSummary = errorCount > 0 and t("mm_ov_errors_some", errorCount, warnCount)
        or (warnCount > 0 and t("mm_ov_errors_warn", warnCount) or t("mm_ov_none"))
    add("errors", t("mm_ov_errors"), errorSummary, errorCount > 0 and "broken" or (warnCount > 0 and "check" or "fine"), errorLines,
        ModMuxTabs.ERRORS)

    -- hints
    local findings = ModMuxReview.list(ModMux.settings.dismissed, false)
    local hintLines = {t("mm_ov_review_help"), ""}
    for i, finding in ipairs(findings) do
        if i <= 8 then
            table.insert(hintLines, "- " .. ModMuxTabs.findingTitle(finding))
        end
    end
    add("review", t("mm_ov_review"), #findings > 0 and t("mm_ov_review_some", #findings) or t("mm_ov_none"),
        #findings > 0 and "check" or "fine", hintLines, ModMuxTabs.REVIEW)

    -- performance
    local perfList = ModMuxPerf.list()
    local budget = ModMuxTabs.budgetMs()
    local perfLines = {t("mm_ov_perf_help"), ""}
    for i, entry in ipairs(perfList) do
        if i <= 6 then
            table.insert(perfLines, t("mm_ov_perfLine", ModMuxOrigin.title(entry.mod), entry.ms, entry.ms / budget * 100))
        end
    end
    local slowest = perfList[1]
    if not ModMuxPerf.installed then
        add("perf", t("mm_ov_perf"), t("mm_ov_perf_off"), "fine", perfLines, ModMuxTabs.PERFORMANCE)
    elseif slowest ~= nil then
        local share = slowest.ms / budget
        add("perf", t("mm_ov_perf"), t("mm_ov_perf_slowest", ModMuxOrigin.title(slowest.mod), slowest.ms),
            share >= 0.10 and "check" or "fine", perfLines, ModMuxTabs.PERFORMANCE)
    end

    -- waiting for the next load
    local pending = ModMuxTabs.pendingLines()
    local pendingDetail = {#pending > 0 and t("mm_ov_pending_help") or t("mm_ov_pending_none"), ""}
    for _, line in ipairs(pending) do
        table.insert(pendingDetail, "- " .. line)
    end
    local pendingRow = add("pending", t("mm_ov_pending"), #pending > 0 and t("mm_ov_pending_some", #pending) or t("mm_ov_none"),
        #pending > 0 and "check" or "fine", pendingDetail, nil)
    if #pending > 0 then
        table.insert(pendingRow.actions, action("undo", "mm_act_undoAll", 1, function()
            return {confirm = t("mm_confirm_undoAll"), onYes = function()
                ModMuxTabs.undoPending()
            end}
        end))
    end

    -- what ModMux can see
    local early = #ModMux.earlyMods()
    local watchDetail = {t("mm_ov_watch_help", #ModMuxOrigin.mods)}
    if early > 0 then
        table.insert(watchDetail, "")
        table.insert(watchDetail, ModMux.earlyText())
    end
    add("watch", t("mm_ov_watch"), t("mm_ov_watch_count", #ModMuxOrigin.mods - early, #ModMuxOrigin.mods),
        early > 0 and "check" or "fine", watchDetail, nil)

    return {columns = {t("mm_col_area"), t("mm_col_found"), "", t("mm_col_verdict")}, rows = rows,
        subHeader = t("mm_sub_overview"), emptyText = ""}
end

local BUILDERS = {ModMuxTabs.overviewModel, ModMuxTabs.conflictsModel, ModMuxTabs.keysModel, ModMuxTabs.errorsModel,
    ModMuxTabs.liveModel, ModMuxTabs.vehicleModel, ModMuxTabs.performanceModel, ModMuxTabs.reviewModel, ModMuxTabs.profilesModel}

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
