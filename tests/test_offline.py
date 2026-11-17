"""Offline test of FS25_ModMux in the game's Lua version (5.1, through lupa) with a small fake game.

The fake game works like the real one where ModMux depends on it: no debug library, every mod runs in its own
environment table (registered under the mod's name in the global table, except one), the game's globals sit behind
that environment's metatable __index, and g_currentModName names the mod only while its scripts load. It has Utils with
the real wrapper semantics, a few classes, a vehicle type, mod event listeners, and fake mods that fight over functions
the way real mods do (appended / overwritten / plain replacements that keep or drop the old function, a change put on
an object instead of the class), one of them loading before ModMux. Several launches share one modSettings folder, so
settings, the evidence, the boot marker, safe mode and profiles carry over.

Usage: python tests/test_offline.py          (needs: pip install lupa)"""
import os
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET

from lupa import lua51

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = tempfile.mkdtemp(prefix="modmux_test_")
PROFILE = os.path.join(WORK, "profile").replace("\\", "/") + "/"
SAVEGAME = os.path.join(WORK, "savegame1").replace("\\", "/")
os.makedirs(PROFILE)
os.makedirs(SAVEGAME)

FAILURES = []
MISSING_TEXTS = set()


def check(condition, message):
    if not condition:
        FAILURES.append(message)
        print("FAIL:", message)


def load_texts(lang):
    root = ET.parse(os.path.join(PROJ, "translations", f"l10n_{lang}.xml")).getroot()
    return {e.get("name"): e.get("text") for e in root.iter("text")}


TEXTS = load_texts("en")
TEXTS_DE = load_texts("de")
MODDESC = ET.parse(os.path.join(PROJ, "modDesc.xml")).getroot()
SCRIPTS = [e.get("filename") for e in MODDESC.iter("sourceFile")]

# ---------------------------------------------------------------------------------------------------------------
# Static checks
# ---------------------------------------------------------------------------------------------------------------

check(set(TEXTS) == set(TEXTS_DE), "l10n_en and l10n_de have different keys")
lua_files = sorted(os.path.relpath(os.path.join(d, f), PROJ).replace("\\", "/")
                   for d, _, fs in os.walk(os.path.join(PROJ, "scripts")) for f in fs if f.endswith(".lua"))
check(sorted(SCRIPTS) == lua_files, f"modDesc sourceFiles {SCRIPTS} != scripts {lua_files}")
for rel in lua_files:
    src = open(os.path.join(PROJ, rel), encoding="utf-8").read()
    check(re.search(r"(?<![\w.:])x?pcall\b", src) is None, f"{rel}: pcall/xpcall (TestRunner forbids them, even in comments)")
    for i, line in enumerate(src.splitlines(), 1):
        check(len(line) <= 200, f"{rel}:{i} longer than 200 characters")
    check(re.search(r"\bgoto\b|//|\bcontinue\b", src) is None, f"{rel}: Lua 5.2+ syntax")
    for key in re.findall(r'"(mm_[A-Za-z_]+)"', src):
        if not key.endswith("_"):
            check(key in TEXTS, f"{rel}: text key {key} missing in l10n")
gui = ET.parse(os.path.join(PROJ, "gui", "ModMuxFrame.xml")).getroot()
ids = {e.get("id") for e in gui.iter() if e.get("id")}
for needed in ["headerIcon", "mainPaging", "subHeader", "rowList", "emptyText", "detailTitle", "footerText", "colHead[4]",
               "detailLine[24]", "mainTabs[6]"]:
    check(needed in ids, f"gui id {needed} missing")
for e in gui.iter():
    for attr in ("text",):
        value = e.get(attr) or ""
        if value.startswith("$l10n_"):
            check(value[6:] in TEXTS, f"gui text {value} missing")

# ---------------------------------------------------------------------------------------------------------------
# Engine stubs on the Python side: GIANTS-style XML, files
# ---------------------------------------------------------------------------------------------------------------


class Engine:
    def __init__(self):
        self.xml = {}
        self.files = {}
        self.next = 1
        self.log = []

    def new_id(self):
        i = self.next
        self.next += 1
        return i

    @staticmethod
    def parse(path):
        attr = None
        if "#" in path:
            path, attr = path.split("#", 1)
        parts = []
        for seg in path.split("."):
            m = re.match(r"^([^()]+)(?:\((\d+)\))?$", seg)
            parts.append((m.group(1), int(m.group(2) or 0)))
        return parts, attr

    def node(self, xml_id, path, create=False):
        root = self.xml[xml_id][0]
        parts, attr = self.parse(path)
        if parts[0][0] != root.tag:
            return None, attr
        node = root
        for tag, idx in parts[1:]:
            children = [c for c in node if c.tag == tag]
            if idx < len(children):
                node = children[idx]
            elif create:
                while len(children) <= idx:
                    children.append(ET.SubElement(node, tag))
                node = children[idx]
            else:
                return None, attr
        return node, attr

    def loadXMLFile(self, name, path):
        try:
            root = ET.parse(path).getroot()
        except Exception:
            return 0
        i = self.new_id()
        self.xml[i] = (root, path)
        return i

    def createXMLFile(self, name, path, root):
        i = self.new_id()
        self.xml[i] = (ET.Element(root), path)
        return i

    def get(self, xml_id, path):
        node, attr = self.node(int(xml_id), path)
        if node is None:
            return None
        return node.get(attr) if attr else node.text

    def getXMLString(self, xml_id, path):
        return self.get(xml_id, path)

    def getXMLInt(self, xml_id, path):
        v = self.get(xml_id, path)
        return int(float(v)) if v is not None else None

    def getXMLBool(self, xml_id, path):
        v = self.get(xml_id, path)
        return None if v is None else v.lower() == "true"

    def set(self, xml_id, path, value):
        node, attr = self.node(int(xml_id), path, create=True)
        if attr:
            node.set(attr, value)
        else:
            node.text = value

    def setXMLString(self, xml_id, path, value):
        self.set(xml_id, path, str(value))

    def setXMLInt(self, xml_id, path, value):
        self.set(xml_id, path, str(int(value)))

    def setXMLBool(self, xml_id, path, value):
        self.set(xml_id, path, "true" if value else "false")

    def hasXMLProperty(self, xml_id, path):
        node, attr = self.node(int(xml_id), path)
        return node is not None and (attr is None or node.get(attr) is not None)

    def saveXMLFile(self, xml_id):
        root, path = self.xml[int(xml_id)]
        ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)

    def delete(self, handle):
        handle = int(handle)
        self.xml.pop(handle, None)
        if handle in self.files:
            path, chunks = self.files.pop(handle)
            with open(path, "w", encoding="utf-8") as f:
                f.write("".join(chunks))

    def createFile(self, path, mode):
        i = self.new_id()
        self.files[i] = (path, [])
        return i

    def fileWrite(self, handle, text):
        self.files[int(handle)][1].append(text)

    def fileExists(self, path):
        return os.path.exists(path)

    def createFolder(self, path):
        os.makedirs(path, exist_ok=True)

    def getUserProfileAppPath(self):
        return PROFILE

    def getText(self, key):
        if key not in TEXTS:
            MISSING_TEXTS.add(key)
            return key
        return TEXTS[key]

    def logLine(self, text):
        self.log.append(text)


PY_FUNCTIONS = ["loadXMLFile", "createXMLFile", "getXMLString", "getXMLInt", "getXMLBool", "setXMLString", "setXMLInt",
                "setXMLBool", "hasXMLProperty", "saveXMLFile", "delete", "createFile", "fileWrite", "fileExists",
                "createFolder", "getUserProfileAppPath"]

# ---------------------------------------------------------------------------------------------------------------
# The fake game (its chunks are named like the game's files, so ModMux sees them as the game's)
# ---------------------------------------------------------------------------------------------------------------

UTILS = r'''
Utils = {}
function Utils.appendedFunction(oldFunc, newFunc)
    if oldFunc ~= nil then
        return function(...)
            oldFunc(...)
            newFunc(...)
        end
    end
    return newFunc
end
function Utils.prependedFunction(oldFunc, newFunc)
    if oldFunc ~= nil then
        return function(...)
            newFunc(...)
            oldFunc(...)
        end
    end
    return newFunc
end
function Utils.overwrittenFunction(oldFunc, newFunc)
    return function(self, ...)
        return newFunc(self, oldFunc, ...)
    end
end
'''

GAME = r'''
CALLS = {}
LOGS = {}
NOTES = {}
CONSOLE = {}
local function call(name) table.insert(CALLS, name) end
for _, name in ipairs(PY_FUNCTIONS) do
    local f = PY[name]
    _G[name] = function(...) return f(...) end
end
function getTimeSec() return os.clock() end
function getDate(format) return "2026-11-17 12:00" end
local function logLine(kind, fmt, ...) table.insert(LOGS, kind .. ": " .. string.format(fmt, ...)) end
Logging = {info = function(...) logLine("info", ...) end, warning = function(...) logLine("warning", ...) end,
    error = function(...) logLine("error", ...) end}
function addConsoleCommand(name) CONSOLE[name] = true end
function removeConsoleCommand(name) CONSOLE[name] = nil end
FileAccess = {WRITE = 2}

Vehicle = {}
function Vehicle.update(self, dt) call("game:update") end
function Vehicle.draw(self) call("game:draw") end
function Vehicle.getSpeedLimit(self) return 10 end
function Vehicle.getFullName(self) call("game:name") end
function Vehicle.saveToXMLFile(self) call("game:save") end
HUD = {}
function HUD.drawSpeed(self) call("game:drawSpeed") end
function HUD.drawControlledEntityHUD(self) call("game:hud") end
WheelPhysics = {}
function WheelPhysics.updateContact(self) call("game:contact") end
Mission00 = {}
function Mission00.loadMission00Finished(self) end
FSBaseMission = {INGAME_NOTIFICATION_INFO = 1, INGAME_NOTIFICATION_CRITICAL = 2, INGAME_NOTIFICATION_OK = 3}
function FSBaseMission.saveSavegame(self) SAVED = (SAVED or 0) + 1 end
SpecializationUtil = {}
function SpecializationUtil.registerOverwrittenFunction(objectType, name, func)
    if objectType.functions[name] ~= nil then
        objectType.functions[name] = Utils.overwrittenFunction(objectType.functions[name], func)
    end
end
g_modEventListeners = {}
function addModEventListener(listener) table.insert(g_modEventListeners, listener) end

function Class(members, base)
    members.superClass = function() return base end
    return {__index = setmetatable(members, {__index = base})}
end
TabbedMenuFrameElement = {}
function TabbedMenuFrameElement.new(target, mt) return setmetatable({}, mt) end
function TabbedMenuFrameElement:onGuiSetupFinished() end
function TabbedMenuFrameElement:onFrameOpen() end
function TabbedMenuFrameElement:onFrameClose() end
function TabbedMenuFrameElement:update(dt) end
function TabbedMenuFrameElement:setMenuButtonInfo(buttons) self.shownButtons = buttons end
function TabbedMenuFrameElement:setMenuButtonInfoDirty() end
function TabbedMenuFrameElement:getIsVisible() return true end
InputAction = {MENU_BACK = "MENU_BACK", MENU_ACCEPT = "MENU_ACCEPT", MENU_EXTRA_1 = "MENU_EXTRA_1", MENU_EXTRA_2 = "MENU_EXTRA_2",
    MENU_ACTIVATE = "MENU_ACTIVATE", MENU_CANCEL = "MENU_CANCEL", MENU_EXTRA_3 = "MENU_EXTRA_3"}
GuiUtils = {getUVs = function() return {0, 0, 1, 1} end}
FocusManager = {setFocus = function() end}
DIALOGS = {}
YesNoDialog = {show = function(callback, target, text) table.insert(DIALOGS, text) callback(target, true) end}
TextInputDialog = {show = function(callback, target, default) callback(target, "Typed " .. default, true) end}
InfoDialog = {show = function(text) table.insert(DIALOGS, text) end}
RenderText = {ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2}
function renderOverlay() end
function renderText() end
function drawFilledRect() end
function setTextAlignment() end
function getTextWidth(size, text) return size * 0.5 * #text end
WheelContactType = {NONE = 0, GROUND = 1, GROUND_HEIGHT = 2, OBJECT = 3}
FarmManager = {SPECTATOR_FARM_ID = 0}
g_farmManager = {farms = {{farmId = 1}}, getFarms = function(self) return self.farms end}
g_vehicleTypeManager = {types = {tractor = {name = "tractor", functions = {getSpeedLimit = Vehicle.getSpeedLimit},
    eventListeners = {onUpdate = {}}}}, getTypes = function(self) return self.types end}
g_i18n = {getText = function(self, key) return PY.getText(key) end}
g_currentMission = {missionInfo = {savegameDirectory = SAVEGAME}, hud = {drawSpeed = HUD.drawSpeed},
    getIsServer = function() return true end,
    addIngameNotification = function(self, kind, text) table.insert(NOTES, text) end}
g_modIsLoaded = {}
g_modManager = {getActiveMods = function(self) return MODS end,
    getModByName = function(self, name) for _, m in ipairs(MODS) do if m.modName == name then return m end end end}
'''

# loads before ModMux (its name sorts first): its Utils change can't be seen
MODS_BEFORE = {
    "ACM_EarlyBird": r'''
Vehicle.getFullName = Utils.appendedFunction(Vehicle.getFullName, function(self) table.insert(CALLS, "early:name") end)
''',
}

MODS_AFTER = {
    "FS25_AlphaWheels": r'''
AlphaWheels = {}
Vehicle.update = Utils.appendedFunction(Vehicle.update, function(self, dt) table.insert(CALLS, "alpha:update") end)
AlphaSpec = {}
function AlphaSpec.getSpeedLimit(self, superFunc) return superFunc(self) + 1 end
SpecializationUtil.registerOverwrittenFunction(g_vehicleTypeManager.types.tractor, "getSpeedLimit", AlphaSpec.getSpeedLimit)
function AlphaWheels:loadMap() end
function AlphaWheels:update(dt) end
addModEventListener(AlphaWheels)
''',
    "FS25_BetaHud": r'''
HUD.drawControlledEntityHUD = Utils.overwrittenFunction(HUD.drawControlledEntityHUD, function(self, superFunc)
    table.insert(CALLS, "beta:hud")
    superFunc(self)
end)
local originalSave = Vehicle.saveToXMLFile
Vehicle.saveToXMLFile = function(self, ...)
    originalSave(self, ...)
end
''',
    "FS25_NovaPhysics": r'''
NovaPhysics = {}
Vehicle.update = Utils.appendedFunction(Vehicle.update, function(self, dt) table.insert(CALLS, "nova:update") end)
Vehicle.draw = Utils.appendedFunction(Vehicle.draw, function(self) table.insert(CALLS, "nova:draw") end)
HUD.drawControlledEntityHUD = Utils.appendedFunction(HUD.drawControlledEntityHUD, function(self) table.insert(CALLS, "nova:hud") end)
WheelPhysics.updateContact = Utils.prependedFunction(WheelPhysics.updateContact, function(self) table.insert(CALLS, "nova:contact") end)
Vehicle.saveToXMLFile = Utils.appendedFunction(Vehicle.saveToXMLFile, function(self) end)
Vehicle.getFullName = Utils.appendedFunction(Vehicle.getFullName, function(self) table.insert(CALLS, "nova:name") end)
NovaSpec = {}
function NovaSpec.getSpeedLimit(self, superFunc) return superFunc(self) * 2 end
function NovaSpec.onUpdate(self, dt) end
SpecializationUtil.registerOverwrittenFunction(g_vehicleTypeManager.types.tractor, "getSpeedLimit", NovaSpec.getSpeedLimit)
table.insert(g_vehicleTypeManager.types.tractor.eventListeners.onUpdate, NovaSpec)
function NovaPhysics:loadMap()
    -- a change put on an object, not on the class: must not count as lost when the class changes later
    g_currentMission.hud.drawSpeed = Utils.appendedFunction(g_currentMission.hud.drawSpeed, function() end)
end
function NovaPhysics:update(dt) end
addModEventListener(NovaPhysics)
''',
    "FS25_OmegaPlus": r'''
OmegaPlus = {}
HUD.drawControlledEntityHUD = Utils.overwrittenFunction(HUD.drawControlledEntityHUD, function(self, superFunc)
    table.insert(CALLS, "omega:hud")
    superFunc(self)
end)
function OmegaPlus:loadMap()
    -- replaces the function without passing on what was there: Nova's draw change is lost
    Vehicle.draw = function(self) table.insert(CALLS, "omega:draw") end
end
function OmegaPlus:update(dt) OMEGA_UPDATES = (OMEGA_UPDATES or 0) + 1 end
function OmegaPlus:draw() renderOverlay(1, 0.80, 0.80, 0.10, 0.10) end
addModEventListener(OmegaPlus)
''',
    "FS25_PiTools": r'''
PiTools = {}
function PiTools:loadMap()
    HUD.drawSpeed = Utils.appendedFunction(HUD.drawSpeed, function(self) table.insert(CALLS, "pi:drawSpeed") end)
end
function PiTools:draw() renderText(0.82, 0.82, 0.02, "hello world") end
addModEventListener(PiTools)
''',
    "FS25_ZetaDrive": r'''
ZetaDrive = {}
local oldContact = WheelPhysics.updateContact
WheelPhysics.updateContact = function(self)
    oldContact(self)
    table.insert(CALLS, "zeta:contact")
end
function ZetaDrive:loadMap()
    HUD.drawSpeed = function(self) table.insert(CALLS, "zeta:drawSpeed") end
end
addModEventListener(ZetaDrive)
''',
    "FS25_ZetaDrive_v2": "",
}

TITLES = {"FS25_ZetaDrive": "Zeta Drive", "FS25_ZetaDrive_v2": "Zeta Drive", "ACM_EarlyBird": "Early Bird"}
# a mod whose environment the game doesn't keep under its name: ModMux learns it while the mod loads
UNREGISTERED = {"FS25_PiTools"}
MODMUX = "FS25_0_ModMux"


class Launch:
    """One start of the game: fresh Lua, the same modSettings folder."""

    def __init__(self, farms=1, modmux=MODMUX):
        self.engine = Engine()
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        self.g = g
        g.PY = self.lua.table_from({name: getattr(self.engine, name) for name in PY_FUNCTIONS + ["getText"]})
        g.PY_FUNCTIONS = self.lua.table_from(PY_FUNCTIONS)
        g.SAVEGAME = SAVEGAME
        self.loader = self.lua.eval('''function(src, chunkname, env)
            local f, e = loadstring(src, chunkname)
            if not f then error(e) end
            if env ~= nil then setfenv(f, env) end
            return f()
        end''')
        self.run(UTILS, "@dataS/scripts/utils/Utils.lua")
        self.run(GAME, "@dataS/scripts/game.lua")
        # the game hides the debug library from mods
        self.lua.execute("debug = nil")
        if farms == 0:
            self.lua.execute("g_farmManager.farms = {}")
        names = sorted(list(MODS_BEFORE) + [modmux] + list(MODS_AFTER), key=str.lower)
        mods = []
        for name in names:
            mods.append({"modName": name, "title": TITLES.get(name, name[5:]), "modDir": f"C:/mods/{name}/",
                         "version": "1.0.0.0", "author": "Tester"})
        g.MODS = self.lua.table_from([self.lua.table_from(m) for m in mods])
        # like the game: an environment per mod whose lookups fall through to the game's globals, and
        # g_currentModName / g_currentModDirectory (game globals) only while the mod's scripts load
        self.make_env = self.lua.eval('''function(name, register)
            local env = setmetatable({}, {__index = _G})
            if register then rawset(_G, name, env) end
            g_modIsLoaded[name] = true
            g_currentModName = name
            g_currentModDirectory = "C:/mods/" .. name .. "/"
            return env
        end''')
        self.done_loading = self.lua.eval('''function() g_currentModName = nil g_currentModDirectory = nil end''')
        for name in names:
            env = self.make_env(name, name not in UNREGISTERED)
            if name == modmux:
                for rel in SCRIPTS:
                    src = open(os.path.join(PROJ, rel), encoding="utf-8").read()
                    self.loader(src, f"@C:/mods/{modmux}/{rel}", env)
                self.env = env
            else:
                src = MODS_BEFORE.get(name, MODS_AFTER.get(name))
                self.loader(src, f"@C:/mods/{name}/scripts/main.lua", env)
            self.done_loading()

    def run(self, src, chunkname):
        return self.loader(src, chunkname, None)

    def lua_in_env(self, src):
        """runs Lua inside ModMux's environment (to reach ModMux's tables)"""
        return self.loader(src, "@test", self.env)

    def load_mission(self):
        self.lua.execute('''
            for _, listener in ipairs(g_modEventListeners) do
                if listener.loadMap ~= nil then listener:loadMap("map") end
            end
            Mission00.loadMission00Finished({})
            -- ModMux does its work on its first update after the mission loaded
            for _, listener in ipairs(g_modEventListeners) do
                if listener.update ~= nil then listener:update(0) end
            end
        ''')

    def frames(self, count, dt=16):
        self.lua.execute(f'''
            for i = 1, {count} do
                for _, listener in ipairs(g_modEventListeners) do
                    if listener.update ~= nil then listener:update({dt}) end
                end
                for _, listener in ipairs(g_modEventListeners) do
                    if listener.draw ~= nil then listener:draw() end
                end
                for _, spec in ipairs(g_vehicleTypeManager.types.tractor.eventListeners.onUpdate) do
                    spec.onUpdate({{}}, {dt})
                end
            end''')

    def calls(self, code):
        self.lua.execute("CALLS = {}")
        self.lua.execute(code)
        calls = self.g.CALLS
        return [calls[i] for i in range(1, len(calls) + 1)]

    def conflict(self, cid):
        return self.env.ModMuxScan.conflictById[cid]

    def play(self, code, times):
        """runs game code a number of times, then lets ModMux read its probes"""
        self.lua.execute(f"for i = 1, {times} do {code} end")
        return self.env.ModMux.checkEvidence()


def lua_quote(text):
    return "[==[" + text + "]==]"


def lua_list(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


def boot_state():
    path = os.path.join(PROFILE, "modSettings", "FS25_ModMux", "boot.xml")
    return ET.parse(path).getroot().get("state") if os.path.exists(path) else None


def settings_path():
    return os.path.join(PROFILE, "modSettings", "FS25_ModMux", "settings.xml")


# ---------------------------------------------------------------------------------------------------------------
# Launch 1: nothing set, everything detected
# ---------------------------------------------------------------------------------------------------------------
print("launch 1: detection")
L = Launch()
ModMux, Scan, Origin = L.env.ModMux, L.env.ModMuxScan, L.env.ModMuxOrigin
check(Origin.hasFenv, "function owners readable through getfenv")
check(Origin.globalsVia == "game function", f"game globals found through a game function ({Origin.globalsVia})")
check(Scan.installed, "hook recorder installed")
check(L.lua.eval("FS25_0_ModMux") is not None and L.lua.eval("g_modMux") is not None, "g_modMux is in the game's globals")
L.load_mission()
ids = sorted(Scan.conflictById[k].id for k in Scan.conflictById)
print("  conflicts:", ids)
pi_env = Origin.modEnvs["FS25_PiTools"]
check(Origin.learned >= 1 and pi_env is not None and Origin.ofFunction(pi_env.PiTools.loadMap) == "FS25_PiTools",
      "an unregistered mod environment is learned while it loads")
check(ModMux.loadPosition() == 2 and lua_list(ModMux.earlyMods()) == ["ACM_EarlyBird"], "one mod loads before ModMux")
check(L.conflict("Vehicle.getFullName") is None, "the early mod's change can't be seen (looks like the game's)")

c = L.conflict("Vehicle.update")
check(c is not None and c.kind == "shared", "Vehicle.update is shared")
check(c is not None and lua_list(c.mods) == ["FS25_AlphaWheels", "FS25_NovaPhysics"], "Vehicle.update mods in load order")

c = L.conflict("Vehicle.draw")
check(c is not None and c.kind == "replaced", "Vehicle.draw: Nova's change hidden under Omega's replacement (may skip)")
if c is not None:
    hidden = lua_list(c.hidden)
    check(len(hidden) == 1 and hidden[0].mod == "FS25_NovaPhysics" and hidden[0].replacer == "FS25_OmegaPlus"
          and hidden[0].state == "hidden", "Vehicle.draw hidden entry is Nova, under Omega, not known yet")
    check(lua_list(c.slot.mods) == ["FS25_OmegaPlus"], "Vehicle.draw now holds only Omega")

c = L.conflict("HUD.drawSpeed")
check(c is not None and c.kind == "replaced", "HUD.drawSpeed: Pi's change hidden under Zeta's replacement")
if c is not None:
    check([e.mod for e in lua_list(c.hidden)] == ["FS25_PiTools"], "HUD.drawSpeed: only Pi, Nova's object hook not counted")

c = L.conflict("HUD.drawControlledEntityHUD")
check(c is not None and c.kind == "overwrite", "HUD.drawControlledEntityHUD may block (Omega wraps the others)")
check(c is not None and lua_list(c.mods) == ["FS25_BetaHud", "FS25_NovaPhysics", "FS25_OmegaPlus"], "HUD mods in order")
check(c is not None and c.category == "hud", "HUD category")

c = L.conflict("Vehicle.saveToXMLFile")
check(c is not None and c.locked and c.lockReason == "save", "Vehicle.saveToXMLFile is locked (save)")

c = L.conflict("WheelPhysics.updateContact")
check(c is not None and c.kind == "replaced" and c.category == "wheels", "updateContact: Nova's change hidden under Zeta's")
if c is not None:
    check(c.layers[1].kind == "replace" and c.floor is None, "Zeta's plain replacement is a closed box")

types = [Scan.conflictById[k] for k in Scan.conflictById if Scan.conflictById[k].type == "types"]
check(len(types) == 1 and types[0].key == "getSpeedLimit" and lua_list(types[0].types) == ["tractor"], "vehicle type chain found")

check(L.calls("Vehicle.draw({})") == ["omega:draw"], "Vehicle.draw runs only Omega before any lever")
check(L.calls("Vehicle.update({}, 16)") == ["game:update", "alpha:update", "nova:update"], "Vehicle.update natural order")
check(L.calls("Vehicle.getFullName({})") == ["game:name", "early:name", "nova:name"], "probes don't change what runs")

# playing: the probes tell whether the hidden changes still run
check(not L.play("Vehicle.draw({})", 5), "a few runs are not enough for a verdict on a change that never ran")
check(L.play("Vehicle.draw({}) HUD.drawSpeed({}) WheelPhysics.updateContact({})", 25), "verdicts after playing")
c = L.conflict("Vehicle.draw")
check(c.kind == "lost" and lua_list(c.lost)[0].mod == "FS25_NovaPhysics" and lua_list(c.lost)[0].calls >= 20,
      "Vehicle.draw: Omega's version never passes Nova's change on (lost)")
c = L.conflict("HUD.drawSpeed")
check(c.kind == "lost" and lua_list(c.lost)[0].mod == "FS25_PiTools", "HUD.drawSpeed: Pi's change is lost")
c = L.conflict("WheelPhysics.updateContact")
check(c.kind == "overwrite" and lua_list(c.hidden)[0].state == "runs", "updateContact: Zeta's version still runs Nova's (may block)")
check(Scan.conflicts[1].kind == "lost", "lost conflicts sorted first after the verdicts")
evidence = os.path.join(PROFILE, "modSettings", "FS25_ModMux", "evidence.xml")
check(os.path.exists(evidence) and open(evidence, encoding="utf-8").read().count("<item") == 3, "evidence.xml keeps the 3 verdicts")
lines = lua_list(L.env.ModMuxTabs.explain(L.conflict("Vehicle.draw")))
check(any("not once" in line for line in lines), f"explanation says the change never ran: {lines}")

review = L.env.ModMuxReview
fids = sorted(review.findings[i].id for i in range(1, len(review.findings) + 1))
print("  review:", fids)
check("duplicate:FS25_ZetaDrive|FS25_ZetaDrive_v2" in fids, "duplicate Zeta found")
check("hard:FS25_NovaPhysics>FS25_OmegaPlus" in fids, "hard conflict Omega switches off Nova")
check("hard:FS25_PiTools>FS25_ZetaDrive" in fids, "hard conflict Zeta switches off Pi")

report = os.path.join(PROFILE, "modSettings", "FS25_ModMux", "ModMux.log")
check(os.path.exists(report) and "Vehicle.draw" in open(report, encoding="utf-8").read(), "ModMux.log written with the conflicts")
check(boot_state() == "loading", "boot marker 'loading' while the first seconds run (timers are structural)")
check(L.env.ModMuxPerf.installed, "timers installed")
L.frames(3, dt=4000)
check(boot_state() == "ok", "boot marker 'ok' after 10 s of play")
perf = L.env.ModMuxPerf
check(perf.stats["FS25_OmegaPlus"] is not None and perf.stats["FS25_OmegaPlus"].functions >= 2, "Omega listener timed")
check(perf.stats["FS25_NovaPhysics"] is not None and perf.stats["FS25_NovaPhysics"].functions >= 2, "Nova listener + spec timed")
check(len(lua_list(L.g.NOTES)) >= 1, "start warning shown")

# HUD scan: Omega's overlay and Pi's text overlap at the top right
check(ModMux.startHudScan(), "HUD scan starts")
L.frames(ModMux.HUD_SCAN_FRAMES + 2)
hud = [review.hudFindings[i].id for i in range(1, len(review.hudFindings) + 1)]
check(hud == ["hud:FS25_OmegaPlus|FS25_PiTools"], f"HUD overlap Omega/Pi found: {hud}")
check(L.lua.eval("renderText") is not None and review.hudScanState == "done", "HUD scan finished")

# console
out = ModMux.consolePick(ModMux, "Vehicle.update", "FS25_NovaPhysics")
check("Saved" in out, "console pick saved")
out = ModMux.consolePick(ModMux, "Vehicle.saveToXMLFile", "FS25_NovaPhysics")
check("Locked" in out, "console pick refuses a locked conflict")
summary = ModMux.consoleSummary(ModMux)
check("Vehicle.draw" in summary, "console summary lists conflicts")

# settings for the next launch (as a player would set them in the Switchboard)
L.lua_in_env('''
    ModMux.settings.picks["Vehicle.draw"] = {mode = "shared"}
    ModMux.settings.rank = {"FS25_PiTools"}
    ModMux.settings.categoryRank.hud = {"FS25_BetaHud"}
    ModMux.settings.hibernate["FS25_OmegaPlus"] = true
    ModMux.saveSettings()
''')
check(ModMux.pendingCount() >= 4, "changes wait for the next load")
L.lua.execute("for _, l in ipairs(g_modEventListeners) do if l.deleteMap then l:deleteMap() end end")

# ---------------------------------------------------------------------------------------------------------------
# Launch 2: the levers apply
# ---------------------------------------------------------------------------------------------------------------
print("launch 2: levers")
L = Launch()
L.load_mission()
check(L.conflict("Vehicle.draw").kind == "lost", "launch 2: Vehicle.draw lost from the evidence of launch 1")
applied = L.env.ModMuxLevers.applied
for cid in ["Vehicle.update", "Vehicle.draw", "HUD.drawSpeed", "HUD.drawControlledEntityHUD"]:
    a = applied[cid]
    check(a is not None and a.done, f"{cid} rebuilt ({a.status if a is not None else 'no plan'})")
check(applied["Vehicle.saveToXMLFile"] is None, "locked conflict untouched")
check(L.calls("Vehicle.update({}, 16)") == ["game:update", "nova:update"], "winner Nova: Alpha muted")
check(L.calls("Vehicle.draw({})") == ["omega:draw", "nova:draw"], "shared chain: Nova's lost change runs again")
check(L.calls("HUD.drawSpeed({})") == ["zeta:drawSpeed", "pi:drawSpeed"], "rank: Pi outranks Zeta, its change is back on top")
check(L.calls("HUD.drawControlledEntityHUD({})") == ["beta:hud", "omega:hud", "game:hud", "nova:hud"],
      "category rank: Beta outermost in the HUD category")
check(L.calls("WheelPhysics.updateContact({})") == ["nova:contact", "game:contact", "zeta:contact"], "untouched chain still runs")
L.frames(2)
check(L.g.OMEGA_UPDATES is None, "parked Omega: its update doesn't run")
check(L.env.ModMuxPerf.parked["FS25_OmegaPlus"] is not None, "Omega counted as parked")
check(L.env.ModMux.pendingCount() == 0, "nothing pending after the levers applied")
# re-scanning after the levers must not show the rebuilt chains as new lost changes
check(L.conflict("Vehicle.draw").after is not None, "chain after the levers kept for display")
# no structural change finished: simulate a crash in the first seconds (no frames, no deleteMap)
check(boot_state() == "loading", "boot marker 'loading' while levers are fresh")

# ---------------------------------------------------------------------------------------------------------------
# Launch 3: safe mode after the crash
# ---------------------------------------------------------------------------------------------------------------
print("launch 3: safe mode after an unfinished start")
L = Launch()
check(L.env.ModMux.safeMode and L.env.ModMux.safeReason == "lastLaunch", "safe mode after the unfinished start")
L.load_mission()
check(L.calls("Vehicle.draw({})") == ["omega:draw"], "safe mode: no lever applied")
check(not L.env.ModMuxPerf.installed, "safe mode: no timers")
check('leversSuspended="true"' in open(settings_path(), encoding="utf-8").read(), "levers stay suspended")
L.frames(1, dt=20000)
L.lua_in_env("ModMux.resumeLevers()")
check(L.env.ModMux.pendingCount() >= 1, "resuming the levers waits for the next load")

# ---------------------------------------------------------------------------------------------------------------
# Launch 4: kill switch
# ---------------------------------------------------------------------------------------------------------------
print("launch 4: kill switch")
kill = os.path.join(PROFILE, "modSettings", "FS25_ModMux", "MODMUX_SAFE_MODE.txt")
open(kill, "w").close()
L = Launch()
check(L.env.ModMux.safeReason == "killSwitch" and not L.env.ModMuxScan.installed, "kill switch: recorder off, safe mode")
L.load_mission()
check(L.calls("Vehicle.draw({})") == ["omega:draw"], "kill switch: nothing applied")
os.remove(kill)

# ---------------------------------------------------------------------------------------------------------------
# Launch 5: a savegame with farms loads without any
# ---------------------------------------------------------------------------------------------------------------
print("launch 5: abnormal load")
with open(os.path.join(SAVEGAME, "farms.xml"), "w", encoding="utf-8") as f:
    f.write('<farms><farm farmId="1"/><farm farmId="2"/></farms>')
L = Launch(farms=0)
L.load_mission()
check(L.env.ModMux.blockSaves, "saves blocked")
L.lua.execute("FSBaseMission.saveSavegame({})")
check(L.g.SAVED is None, "the save didn't happen")
check(boot_state() == "abnormal", "boot marker 'abnormal'")
L2 = Launch()
check(L2.env.ModMux.safeReason == "abnormal", "next start in safe mode after the abnormal load")
os.remove(os.path.join(SAVEGAME, "farms.xml"))

# ---------------------------------------------------------------------------------------------------------------
# Launch 6: the Switchboard (every tab, view, row and button), profiles, live settings, vehicle
# ---------------------------------------------------------------------------------------------------------------
print("launch 6: switchboard")
L = Launch()
L.lua_in_env("ModMux.resumeLevers()")
L = Launch()
L.load_mission()
L.frames(3, dt=4000)
check(not L.env.ModMux.safeMode, "levers back on")

ui_test = r'''
local results = {errors = {}, rows = 0, actions = 0}
-- a vehicle to look at
g_localPlayer = {getCurrentVehicle = function() return VEHICLE end}
VEHICLE = {typeName = "tractor", operatingTime = 7200000, spec_motorized = {motorTemperature = {value = 92}},
    specializations = {NovaSpec},
    getFullName = function() return "Test Tractor" end, getLastSpeed = function() return 23.4 end,
    getTotalMass = function() return 8.25 end, getDamageAmount = function() return 0.6 end,
    getWearTotalAmount = function() return 0.1 end, getIsMotorStarted = function() return true end,
    getMotorRpmPercentage = function() return 0.5 end,
    getWheels = function() return {{physics = {contact = 1, tireGroundFrictionCoeff = 0.9, frictionScale = 1, netInfo = {slip = 0.4}}}} end}
-- a mod's live setting through the public API
LIVE_VALUE = 5
g_modMux.registerLiveSetting({id = "test.width", modName = "FS25_PiTools", title = "Width", kind = "number", min = 1, max = 9,
    step = 2, get = function() return LIVE_VALUE end, set = function(v) LIVE_VALUE = v end, description = "How wide"})

local function fake()
    local e = {elements = {}, textColor = {1, 1, 1, 1}}
    function e:setText(t) self.text = t end
    function e:setVisible(v) self.visible = v end
    function e:setTextColor(r, g, b, a) self.color = {r, g, b, a} end
    function e:setSelected(v) self.selected = v end
    function e:setState(v) self.state = v end
    function e:setTexts(v) self.texts = v end
    function e:setImageFilename(v) self.image = v end
    function e:setImageUVs() end
    function e:reloadData() end
    function e:setSelectedItem() end
    function e:setDataSource() end
    function e:setDelegate() end
    return e
end
local frame = ModMuxFrame.new()
frame.headerIcon, frame.mainPaging, frame.subHeader, frame.footerText, frame.emptyText = fake(), fake(), fake(), fake(), fake()
frame.detailTitle, frame.rowList = fake(), fake()
frame.colHead, frame.detailLine, frame.mainTabs = {}, {}, {}
for i = 1, 4 do frame.colHead[i] = fake() end
for i = 1, 24 do frame.detailLine[i] = fake() end
for i = 1, 6 do frame.mainTabs[i] = fake() end
frame:initialize()
frame:onGuiSetupFinished()
local cell = {attrs = {}}
function cell:getAttribute(name) self.attrs[name] = self.attrs[name] or fake() return self.attrs[name] end
cell.elements = {}

for tab = 1, 6 do
    local views = tab == 1 and 3 or 1
    for view = 1, views do
        frame.ui.view = view
        frame:showTab(tab)
        local count = #frame.model.rows
        if count == 0 then
            -- an empty list still has the tab's own buttons (Save as new, Scan HUD, ...)
            for slot = 1, 6 do
                if frame.actionBySlot[slot] ~= nil and frame.actionBySlot[slot].id ~= "view" then
                    frame:onSlotPressed(slot)
                    results.actions = results.actions + 1
                    results.maxProfiles = math.max(results.maxProfiles or 0, #ModMuxProfiles.list)
                end
            end
        end
        for index = 1, count do
            frame:populateCellForItemInSection(frame.rowList, 1, index, cell)
            frame:onListSelectionChanged(frame.rowList, 1, index)
            results.rows = results.rows + 1
            for slot = 1, 6 do
                if frame.actionBySlot[slot] ~= nil and frame.actionBySlot[slot].id ~= "view" then
                    frame:onSlotPressed(slot)
                    results.actions = results.actions + 1
                    results.maxProfiles = math.max(results.maxProfiles or 0, #ModMuxProfiles.list)
                    -- the list may have changed: keep going with the same index if it still exists
                    if #frame.model.rows < index then break end
                    frame:onListSelectionChanged(frame.rowList, 1, index)
                end
            end
        end
        frame:update(600)
    end
end
results.vehicleRows = #(ModMuxVehicle.rows(VEHICLE) or {})
results.liveValue = LIVE_VALUE
results.profiles = results.maxProfiles or 0
results.dialogs = #DIALOGS
results.wrapped = #ModMuxFrame.wrap(string.rep("word ", 40), 30)
return results
'''
res = L.lua_in_env(ui_test)
print(f"  rows {res.rows}, button presses {res.actions}, vehicle rows {res.vehicleRows}, dialogs {res.dialogs}")
check(res.rows >= 20, "the Switchboard showed rows on its tabs")
check(res.actions >= 20, "buttons pressed")
check(res.vehicleRows >= 10, "vehicle rows")
check(res.profiles >= 1, "profile saved through the dialog")
check(res.wrapped >= 6, "detail text wraps")
report_text = L.env.ModMux.buildReport()
check("CONFLICTS" in report_text, "report builds after the UI test")

# profiles round trip
L.lua_in_env('''
    ModMux.settings.rank = {"FS25_ZetaDrive"}
    ModMuxProfiles.saveCurrent("Round trip")
    ModMux.settings.rank = {}
    ModMuxProfiles.apply(ModMuxProfiles.indexOf("Round trip"))
''')
check(lua_list(L.env.ModMux.settings.rank) == ["FS25_ZetaDrive"], "profile restores the ranking")
L7 = Launch()
check(L7.env.ModMuxProfiles is not None, "launch after the UI test")
L7.load_mission()
check(L7.env.ModMuxProfiles.indexOf("Round trip") is not None, "profiles kept on disk")

# a step of ModMux's own work that stops with an error is logged and skipped, never passed on to the game
ok = L7.env.ModMux.guard("test step", L7.lua.eval("function() error('boom') end"))
check(ok is False, "guard catches an error in ModMux's own work")
check(any("test step" in L7.g.LOGS[i] for i in range(1, len(L7.g.LOGS) + 1)), "guard logs the error")

# ---------------------------------------------------------------------------------------------------------------
# Launch 8: the zip renamed back to FS25_ModMux: ModMux loads after some mods and says so
# ---------------------------------------------------------------------------------------------------------------
print("launch 8: loaded late")
L8 = Launch(modmux="FS25_ModMux")
L8.load_mission()
check(L8.env.ModMux.loadPosition() == 4, "three mods load before FS25_ModMux")
check(L8.conflict("HUD.drawControlledEntityHUD") is not None, "later mods are still watched")
check("loaded before ModMux" in L8.env.ModMux.buildReport(), "report names the mods loaded before ModMux")

check(not MISSING_TEXTS, f"texts used but missing in l10n: {sorted(MISSING_TEXTS)}")

if os.environ.get('MODMUX_KEEP') is None:
    shutil.rmtree(WORK, ignore_errors=True)
else:
    print('kept', WORK)
if FAILURES:
    print(f"\n{len(FAILURES)} FAILED")
    sys.exit(1)
print("\nALL OK")
