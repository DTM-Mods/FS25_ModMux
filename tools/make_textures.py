"""Makes ModMux's textures (needs Pillow 13+, which writes DXT1 / DXT5 .dds without mipmaps):
  gui/modMux_ui.dds       64x64 plain white (DXT1, opaque): tinted row / panel fills of the ModMux page
  gui/modMux_tabIcon.dds  256x256 white multiplexer symbol on transparent (DXT5): the ESC menu tab and page header
  icon_ModMux.dds         512x512 DXT1 mod icon, from icon_ModMux.png (made by _brand/tools/make_icons.py --modhub modMux)
Usage: python -I tools/make_textures.py"""
import pathlib
from PIL import Image, ImageDraw

project = pathlib.Path(__file__).resolve().parent.parent
gui = project / "gui"
gui.mkdir(exist_ok=True)

Image.new("RGB", (64, 64), (255, 255, 255)).save(gui / "modMux_ui.dds", pixel_format="DXT1")

# tab icon: drawn 4x and scaled down for smooth edges. Three inputs, the multiplexer, one output with an arrow.
S = 4
size = 256 * S
img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
d = ImageDraw.Draw(img)
white = (255, 255, 255, 255)
w = 14 * S


def p(x, y):
    return (x * S, y * S)


for y in (70, 128, 186):
    d.line([p(30, y), p(92, y)], fill=white, width=w)
    d.ellipse([p(18, y - 17), p(52, y + 17)], fill=white)
body = [p(90, 30), p(176, 72), p(176, 184), p(90, 226)]
d.polygon(body, outline=white, fill=None, width=w)
d.line([p(150, 128), p(108, 78)], fill=white, width=11 * S)
d.ellipse([p(138, 116), p(162, 140)], fill=white)
d.line([p(176, 128), p(206, 128)], fill=white, width=w)
d.polygon([p(200, 102), p(240, 128), p(200, 154)], fill=white)
img.resize((256, 256), Image.LANCZOS).save(gui / "modMux_tabIcon.dds", pixel_format="DXT5")
img.resize((256, 256), Image.LANCZOS).save(project / "tools" / "tabIcon_preview.png")

png = project / "icon_ModMux.png"
if png.exists():
    icon = Image.open(png).convert("RGB").resize((512, 512), Image.LANCZOS)
    icon.save(project / "icon_ModMux.dds", pixel_format="DXT1")
    print("icon_ModMux.dds from icon_ModMux.png")
else:
    print("icon_ModMux.png missing: run _brand/tools/make_icons.py <brand> <work> --modhub modMux first")
print("gui/modMux_ui.dds, gui/modMux_tabIcon.dds written")
