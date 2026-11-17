-- ModMux: things worth a look, each with its evidence.
--   duplicate     two active mods that look like the same mod (same name apart from a copy / version suffix, same
--                 title, or the same file hash)
--   incompatible  a pair listed in config/knownIncompatible.xml (shipped) or in the player's own
--                 modSettings/FS25_ModMux/knownIncompatible.xml
--   hard          one mod switches off changes of another (lost changes, grouped per pair of mods)
--   hud           two mods drew on the same part of the screen during a HUD scan
-- Findings the player dismissed stay hidden (by id) until restored.

ModMuxReview = {}

ModMuxReview.findings = {}
ModMuxReview.hudFindings = {}
ModMuxReview.knownPairs = {}
ModMuxReview.hudScanState = "never"   -- never | running | done
ModMuxReview.HUD_MIN_AREA = 0.0004   -- share of the screen two mods must both cover (about 2 % x 2 %)

function ModMuxReview.normalizeName(name)
    local n = tostring(name):lower():gsub("%.zip$", "")
    n = n:gsub("%s*%(%d+%)$", "")
    for _, suffix in ipairs({"[_%-%s]*copy$", "[_%-]update$", "[_%-]old$", "[_%-]new$", "[_%-]backup$"}) do
        n = n:gsub(suffix, "")
    end
    n = n:gsub("[_%-]v?%d+[%d_%.]*$", "")
    return n
end

function ModMuxReview.normalizeTitle(title)
    local t = tostring(title or ""):lower()
    t = t:gsub("fs25", ""):gsub("v?%d+[%._]%d+[%._%d]*", ""):gsub("[^%a%d]", "")
    return t
end

--- reads <knownIncompatible><pair a="FS25_X" b="FS25_Y" reason="..."/></knownIncompatible> into ModMuxReview.knownPairs
function ModMuxReview.loadKnownPairs(paths)
    local pairsList = {}
    for _, path in ipairs(paths) do
        if path ~= nil and fileExists(path) then
            local xml = loadXMLFile("ModMuxKnownIncompatible", path)
            if xml ~= nil and xml ~= 0 then
                local i = 0
                while true do
                    local key = string.format("knownIncompatible.pair(%d)", i)
                    if not hasXMLProperty(xml, key) then
                        break
                    end
                    local a, b = getXMLString(xml, key .. "#a"), getXMLString(xml, key .. "#b")
                    if a ~= nil and b ~= nil and a ~= "" and b ~= "" then
                        table.insert(pairsList, {a = a, b = b, reason = getXMLString(xml, key .. "#reason") or ""})
                    end
                    i = i + 1
                end
                delete(xml)
            end
        end
    end
    ModMuxReview.knownPairs = pairsList
end

local function pairId(kind, a, b)
    if b ~= nil and b < a then
        a, b = b, a
    end
    return kind .. ":" .. a .. (b ~= nil and ("|" .. b) or "")
end

local function addDuplicates(findings, mods)
    local groups = {}
    local function group(kind, key, mod)
        if key == nil or key == "" then
            return
        end
        local id = kind .. "=" .. key
        groups[id] = groups[id] or {kind = kind, key = key, mods = {}}
        table.insert(groups[id].mods, mod)
    end
    for _, mod in ipairs(mods) do
        if not mod.isDLC and mod.name ~= ModMux.MOD_NAME then
            group("name", ModMuxReview.normalizeName(mod.name), mod)
            group("title", ModMuxReview.normalizeTitle(mod.title), mod)
            if type(mod.fileHash) == "string" and mod.fileHash ~= "" then
                group("hash", mod.fileHash, mod)
            end
        end
    end
    local seen = {}
    local ids = {}
    for id in pairs(groups) do
        table.insert(ids, id)
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local g = groups[id]
        if #g.mods >= 2 then
            local names = {}
            for _, mod in ipairs(g.mods) do
                table.insert(names, mod.name)
            end
            table.sort(names)
            local fid = "duplicate:" .. table.concat(names, "|")
            if not seen[fid] then
                seen[fid] = true
                local evidence = {}
                for _, mod in ipairs(g.mods) do
                    table.insert(evidence, {key = "mm_ev_modLine", args = {mod.name, tostring(mod.title),
                        tostring(mod.version or "?"), tostring(mod.author or "?")}})
                end
                table.insert(evidence, {key = "mm_ev_dupReason_" .. g.kind})
                table.insert(findings, {id = fid, kind = "duplicate", mods = names, evidence = evidence, severity = 2})
            end
        end
    end
end

local function addKnownPairs(findings, mods)
    local byLower = {}
    for _, mod in ipairs(mods) do
        byLower[mod.name:lower()] = mod
    end
    for _, entry in ipairs(ModMuxReview.knownPairs) do
        local a, b = byLower[entry.a:lower()], byLower[entry.b:lower()]
        if a ~= nil and b ~= nil and a ~= b then
            local evidence = {{key = "mm_ev_knownPair"}}
            if entry.reason ~= "" then
                table.insert(evidence, {text = entry.reason})
            end
            table.insert(findings, {id = pairId("incompatible", a.name, b.name), kind = "incompatible", mods = {a.name, b.name},
                evidence = evidence, severity = 3, flat = true})
        end
    end
end

--- one finding per (mod whose changes are lost, mod that replaced them)
local function addHardConflicts(findings, conflicts)
    local groups, order = {}, {}
    for _, conflict in ipairs(conflicts) do
        if conflict.kind == "lost" then
            for _, entry in ipairs(conflict.lost) do
                for _, owner in ipairs(conflict.slot ~= nil and conflict.slot.mods or {}) do
                    if owner ~= entry.mod then
                        local id = "hard:" .. entry.mod .. ">" .. owner
                        if groups[id] == nil then
                            groups[id] = {id = id, kind = "hard", mods = {entry.mod, owner}, functions = {}, seen = {},
                                severity = 3, flat = true}
                            table.insert(order, id)
                        end
                        if not groups[id].seen[conflict.id] then
                            groups[id].seen[conflict.id] = true
                            table.insert(groups[id].functions, conflict.id)
                        end
                    end
                end
            end
        end
    end
    for _, id in ipairs(order) do
        local g = groups[id]
        g.evidence = {{key = "mm_ev_hardCount", args = {#g.functions}}}
        for i, fid in ipairs(g.functions) do
            if i > 8 then
                table.insert(g.evidence, {key = "mm_ev_more", args = {#g.functions - 8}})
                break
            end
            table.insert(g.evidence, {text = "  " .. fid})
        end
        g.seen = nil
        table.insert(findings, g)
    end
end

function ModMuxReview.build(conflicts)
    local findings = {}
    addKnownPairs(findings, ModMuxOrigin.mods)
    addHardConflicts(findings, conflicts or {})
    addDuplicates(findings, ModMuxOrigin.mods)
    ModMuxReview.findings = findings
    return findings
end

local function screenPart(x, y)
    local h = x < 0.33 and "left" or (x > 0.66 and "right" or "center")
    local v = y < 0.33 and "bottom" or (y > 0.66 and "top" or "middle")
    return v, h
end

--- turns a finished HUD scan (mod -> rectangles) into findings
function ModMuxReview.onHudScan(rects)
    local mods = {}
    for mod in pairs(rects) do
        table.insert(mods, mod)
    end
    table.sort(mods)
    local findings = {}
    for i = 1, #mods do
        for j = i + 1, #mods do
            local a, b = mods[i], mods[j]
            local area, best = 0, nil
            for _, ra in ipairs(rects[a]) do
                for _, rb in ipairs(rects[b]) do
                    local ix = math.min(ra.x + ra.w, rb.x + rb.w) - math.max(ra.x, rb.x)
                    local iy = math.min(ra.y + ra.h, rb.y + rb.h) - math.max(ra.y, rb.y)
                    if ix > 0 and iy > 0 then
                        local overlap = ix * iy
                        area = area + overlap
                        if best == nil or overlap > best.area then
                            best = {area = overlap, x = math.max(ra.x, rb.x) + ix / 2, y = math.max(ra.y, rb.y) + iy / 2}
                        end
                    end
                end
            end
            if best ~= nil and area >= ModMuxReview.HUD_MIN_AREA then
                local v, h = screenPart(best.x, best.y)
                table.insert(findings, {id = pairId("hud", a, b), kind = "hud", mods = {a, b}, severity = 1,
                    evidence = {{key = "mm_ev_hudWhere", args = {"mm_pos_" .. v, "mm_pos_" .. h}, argKeys = true},
                        {key = "mm_ev_hudArea", args = {string.format("%.1f", area * 100)}}}})
            end
        end
    end
    ModMuxReview.hudFindings = findings
    ModMuxReview.hudScanState = "done"
    if ModMux.onReviewChanged ~= nil then
        ModMux.onReviewChanged()
    end
end

--- every finding, the HUD ones last; dismissed ones only when asked for
function ModMuxReview.list(dismissed, showDismissed)
    local list = {}
    for _, source in ipairs({ModMuxReview.findings, ModMuxReview.hudFindings}) do
        for _, finding in ipairs(source) do
            local isDismissed = dismissed[finding.id] == true
            if showDismissed or not isDismissed then
                finding.dismissed = isDismissed
                table.insert(list, finding)
            end
        end
    end
    return list
end

--- findings that deserve the on-screen warning: flatly incompatible pairs nobody dismissed
function ModMuxReview.flatCount(dismissed)
    local count = 0
    for _, finding in ipairs(ModMuxReview.findings) do
        if finding.flat and not dismissed[finding.id] then
            count = count + 1
        end
    end
    return count
end
