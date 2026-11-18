"""Mock-ups of the ModMux page: runs ModMux in the offline test's fake game (fake mods, see tests/test_offline.py),
takes the real tab models (rows, details, buttons) and draws them in the page's own layout and colours
(gui/ModMuxFrame.xml) with headless Chrome, 1920x1080. They are previews for the README / the user, NOT in-game
screenshots: never upload them to ModHub.
Usage: python tools/make_preview.py            (needs lupa and Chrome)  -> previews/page_<tab>.png"""
import html
import os
import pathlib
import subprocess
import sys
import tempfile

project = pathlib.Path(__file__).resolve().parent.parent
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

# the test harness without its checks
src = (project / "tests" / "test_offline.py").read_text(encoding="utf-8")
harness = src[:src.index("# Launch 1: nothing set")]
ns = {"__file__": str(project / "tests" / "test_offline.py"), "__name__": "preview"}
exec(compile(harness, "test_offline.py", "exec"), ns)
ns["TITLES"].update({"FS25_AlphaWheels": "Alpha Wheels", "FS25_BetaHud": "Beta HUD", "FS25_NovaPhysics": "Nova Physics",
                     "FS25_OmegaPlus": "Omega Plus", "FS25_PiTools": "Pi Tools", "FS25_ZetaDrive": "Zeta Drive",
                     "FS25_ZetaDrive_v2": "Zeta Drive"})
Launch = ns["Launch"]

L = Launch()
L.load_mission()
L.frames(3, dt=4000)
L.env.ModMux.startHudScan()
L.frames(L.env.ModMux.HUD_SCAN_FRAMES + 2)

DUMP = r'''
local tab, view, selectId = ...
g_localPlayer = {getCurrentVehicle = function() return PREVIEW_VEHICLE end}
PREVIEW_VEHICLE = PREVIEW_VEHICLE or {typeName = "tractor", operatingTime = 412 * 3600000,
    spec_motorized = {motorTemperature = {value = 88}}, specializations = {NovaSpec},
    getFullName = function() return "Test Tractor 6R" end, getLastSpeed = function() return 18.6 end,
    getTotalMass = function() return 11.42 end, getDamageAmount = function() return 0.07 end,
    getWearTotalAmount = function() return 0.34 end, getIsMotorStarted = function() return true end,
    getMotorRpmPercentage = function() return 0.62 end,
    getWheels = function() return {
        {physics = {contact = 1, tireGroundFrictionCoeff = 0.92, frictionScale = 1, netInfo = {slip = 0.06}}},
        {physics = {contact = 1, tireGroundFrictionCoeff = 0.92, frictionScale = 1, netInfo = {slip = 0.05}}},
        {physics = {contact = 1, tireGroundFrictionCoeff = 0.71, frictionScale = 1, netInfo = {slip = 0.21}}},
        {physics = {contact = 1, tireGroundFrictionCoeff = 0.70, frictionScale = 1, netInfo = {slip = 0.24}}}} end}
-- a mock-up: plausible costs instead of the fake mods' empty functions
local costs = {FS25_AlphaWheels = 0.31, FS25_NovaPhysics = 1.84, FS25_OmegaPlus = 0.62, FS25_PiTools = 0.12}
for mod, ms in pairs(costs) do
    local stats = ModMuxPerf.getStats(mod)
    stats.ms, stats.peak = ms, ms * 2.6
    if stats.functions == 0 then stats.functions, stats.listeners = 2, 1 end
end
ModMuxPerf.frameMs = 14.3
local ui = {tab = tab, view = view, showDismissed = false}
local model = ModMuxTabs.build(ui)
local sel = 1
for i, row in ipairs(model.rows) do
    if row.id == selectId then sel = i end
end
local row = model.rows[sel]
local out = {columns = model.columns, subHeader = model.subHeader or "", footer = model.footer or "",
    footerColor = model.footerColor or "", empty = model.emptyText or "", sel = sel, rows = {},
    detailTitle = row ~= nil and row.detailTitle or "", detail = ModMuxFrame.detailLines(row, 24, 60), buttons = {}}
out.tabs = ModMuxTabs.tabTexts()
for i, r in ipairs(model.rows) do
    out.rows[i] = {cells = r.cells, colors = {r.colors and r.colors[1] or "", r.colors and r.colors[2] or "",
        r.colors and r.colors[3] or "", r.colors and r.colors[4] or ""}}
end
for _, a in ipairs(ModMuxTabs.actionsFor(model, row)) do
    table.insert(out.buttons, a.text)
end
return out
'''
dump = L.loader(f"return function(...) {DUMP} end", "@preview", L.env)


def py(value):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys):
            return [py(value[i]) for i in range(1, len(keys) + 1)]
        return {k: py(v) for k, v in value.items()}
    return value


TABS = ["OVERVIEW", "CONFLICTS", "KEYS", "ERRORS", "LIVE", "VEHICLE", "PERFORMANCE", "REVIEW", "PROFILES"]
COLORS = {"good": "#78b30f", "warn": "#e8b021", "bad": "#e35c4d", "dim": "#8c8c8c", "": "#aaaaa5"}
CSS = """
body{margin:0;width:1920px;height:1080px;font-family:'Segoe UI',Arial,sans-serif;color:#ebebeb;
  background:radial-gradient(ellipse at 30% 20%,#3d4a2e,#141812 70%);overflow:hidden}
.shade{position:absolute;inset:0;background:rgba(10,12,9,.82)}
.mock{position:absolute;right:24px;top:18px;font-size:15px;color:#e8b021;letter-spacing:1px}
.pages{position:absolute;left:170px;top:22px;display:flex;gap:6px}
.pages div{width:56px;height:56px;border-radius:4px;background:#22251f;opacity:.55}
.pages div.on{background:#8dc63f;opacity:1;display:flex;align-items:center;justify-content:center}
.head{position:absolute;left:170px;top:104px;display:flex;align-items:center;gap:18px}
.head .ic{width:64px;height:64px;background:#8dc63f;border-radius:4px;display:flex;align-items:center;justify-content:center}
.head h1{margin:0;font-size:34px;font-weight:700;letter-spacing:1px;text-transform:uppercase}
.tabs{position:absolute;left:170px;top:196px;display:flex}
.tabs div{width:175px;height:57px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:18px;
  color:#aaaaa5;letter-spacing:1px}
.tabs div.on{color:#fff;background:linear-gradient(#2c3420,#1c1d1b);border-bottom:3px solid #8dc63f}
.line{position:absolute;left:170px;width:1580px;height:2px;background:#8dc63f}
.sub{position:absolute;left:170px;top:268px;font-size:15px;font-weight:700;color:#aaaaa5;text-transform:uppercase}
.cols{position:absolute;left:170px;top:302px;width:1000px;font-size:14px;font-weight:700;color:#6e7069;text-transform:uppercase}
.cols span{position:absolute}
.list{position:absolute;left:170px;top:338px;width:1000px}
.row{height:40px;margin-bottom:4px;background:#1c1d1b;position:relative;font-size:15px}
.row.sel{background:#323c1c;outline:2px solid #8dc63f}
.row span{position:absolute;top:0;line-height:40px;white-space:nowrap;overflow:hidden}
.row .s{text-align:right;font-weight:700;font-size:13px;text-transform:uppercase}
.empty{position:absolute;left:170px;top:600px;width:1000px;text-align:center;color:#8c8c8c;font-size:18px}
.det{position:absolute;left:1190px;top:302px;width:558px;height:678px;background:#1c1d1b;border:1px solid #2e302b}
.det h2{margin:10px 18px 8px;font-size:19px;white-space:nowrap;overflow:hidden}
.det p{margin:0 18px;height:26px;line-height:26px;font-size:15px;color:#cdcdc8;white-space:pre}
.foot{position:absolute;left:190px;top:996px;font-size:16px}
.btns{position:absolute;left:170px;bottom:14px;display:flex;gap:28px;font-size:17px;font-weight:600}
.btns span b{display:inline-block;min-width:26px;padding:2px 7px;margin-right:8px;border-radius:4px;background:#ebebeb;
  color:#1c1d1b;font-size:13px;text-align:center}
"""
XS = [12, 440, 680, 836]
WS = [420, 230, 150, 152]
KEYS = ["A", "X", "Y", "...", "...", "..."]


def page(tab, data, icon_uri):
    rows = []
    for i, row in enumerate(data["rows"][:14], 1):
        cells = row["cells"] + [""] * (4 - len(row["cells"]))
        spans = []
        for c in range(4):
            style = f"left:{XS[c]}px;width:{WS[c]}px"
            cls = ' class="s"' if c == 3 else ""
            color = row["colors"][c] if row.get("colors") else ""
            if color:
                style += f";color:{COLORS[color]}"
            elif c == 3:
                style += ";color:#aaaaa5"
            spans.append(f'<span{cls} style="{style}">{html.escape(str(cells[c]))}</span>')
        rows.append(f'<div class="row{" sel" if i == data["sel"] else ""}">{"".join(spans)}</div>')
    cols = "".join(f'<span style="left:{XS[i]}px">{html.escape(str(c))}</span>' for i, c in enumerate(data["columns"]))
    detail = "".join(f"<p>{html.escape(str(line))}</p>" for line in data["detail"])
    tabs = "".join(f'<div class="{"on" if i == tab else ""}">{html.escape(str(name))}</div>'
                   for i, name in enumerate(data.get("tabs") or TABS, 1))
    pages = "".join('<div></div>' for _ in range(9)) + f'<div class="on"><img src="{icon_uri}" width="40"></div>'
    buttons = '<span><b>Esc</b>Back</span>' + "".join(f"<span><b>&#9679;</b>{html.escape(str(b))}</span>" for b in data["buttons"])
    empty = f'<div class="empty">{html.escape(str(data["empty"]))}</div>' if not data["rows"] else ""
    foot_color = COLORS.get(data["footerColor"], "#8c8c8c")
    return f"""<html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="shade"></div>
<div class="mock">MOCK-UP, NOT IN GAME</div>
<div class="pages">{pages}</div>
<div class="head"><div class="ic"><img src="{icon_uri}" width="48"></div><h1>ModMux</h1></div>
<div class="tabs">{tabs}</div><div class="line" style="top:253px"></div>
<div class="sub">{html.escape(str(data["subHeader"]))}</div>
<div class="cols">{cols}</div><div class="line" style="top:332px;width:1000px;height:1px;background:#3a3d36"></div>
<div class="list">{"".join(rows)}</div>{empty}
<div class="det"><h2>{html.escape(str(data["detailTitle"]))}</h2>{detail}</div>
<div class="line" style="top:984px;height:1px;background:#3a3d36"></div>
<div class="foot" style="color:{foot_color}">{html.escape(str(data["footer"]))}</div>
<div class="btns">{buttons}</div></body></html>"""


def render(markup, out):
    work = pathlib.Path(tempfile.mkdtemp(prefix="modmux_preview_"))
    page_file = work / "page.html"
    page_file.write_text(markup, encoding="utf-8")
    png = work / "shot.png"
    p = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={work / 'chrome'}",
                          "--window-size=1920,1080", f"--screenshot={png}", "--timeout=3000", page_file.as_uri()],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        p.wait(60)
    except subprocess.TimeoutExpired:
        p.kill()
    out.write_bytes(png.read_bytes())


from PIL import Image  # noqa: E402

icon_png = pathlib.Path(tempfile.mkdtemp()) / "tab.png"
icon = Image.open(project / "gui" / "modMux_tabIcon.dds").convert("RGBA")
dark = Image.new("RGBA", icon.size, (0, 0, 0, 0))
dark.paste((20, 24, 18, 255), mask=icon.split()[3])
dark.save(icon_png)
icon_uri = icon_png.as_uri()

SHOTS = [
    ("overview", 1, 1, None),
    ("conflicts_pairs", 2, 1, "pair:FS25_OmegaPlus>FS25_NovaPhysics"),
    ("conflicts_simple", 2, 2, "mod:FS25_NovaPhysics"),
    ("conflicts_advanced", 2, 4, "Vehicle.draw"),
    ("conflicts_category", 2, 3, None),
    ("keys", 3, 1, None),
    ("errors", 4, 1, None),
    ("live", 5, 1, None),
    ("vehicle", 6, 1, None),
    ("performance", 7, 1, "perf:FS25_NovaPhysics"),
    ("review", 8, 1, None),
]
outdir = project / "previews"
outdir.mkdir(exist_ok=True)
for name, tab, view, select in SHOTS:
    data = py(dump(tab, view, select))
    data.setdefault("rows", [])
    data.setdefault("detail", [])
    data.setdefault("buttons", [])
    data.setdefault("columns", [])
    out = outdir / f"page_{name}.png"
    render(page(tab, data, icon_uri), out)
    print(out)
