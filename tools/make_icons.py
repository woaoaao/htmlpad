"""生成 AppIcon 所需的全部尺寸 PNG（源图 1024x1024）。"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "HTMLPad", "Assets.xcassets", "AppIcon.appiconset")

S = 1024


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def find_font(names):
    for path in names:
        if os.path.exists(path):
            return path
    return None


def make_base():
    top = (0x12, 0x1B, 0x2E)
    bottom = (0x33, 0x1C, 0x54)
    img = Image.new("RGB", (S, S), top)
    px = img.load()
    for y in range(S):
        color = lerp(top, bottom, y / (S - 1))
        for x in range(S):
            px[x, y] = color

    d = ImageDraw.Draw(img, "RGBA")

    # 淡淡的网格点，营造代码编辑器的感觉
    step = 64
    for y in range(step, S, step):
        for x in range(step, S, step):
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(255, 255, 255, 18))

    font_path = find_font([
        r"C:\Windows\Fonts\consolab.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\segoeuib.ttf",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ])
    if font_path is None:
        raise SystemExit("找不到可用字体")

    glyph = "</>"
    font = ImageFont.truetype(font_path, 380)
    box = d.textbbox((0, 0), glyph, font=font)
    gw, gh = box[2] - box[0], box[3] - box[1]
    gx = (S - gw) / 2 - box[0]
    gy = S * 0.42 - gh / 2 - box[1]

    # 描边阴影 + 主题色主体
    d.text((gx + 8, gy + 10), glyph, font=font, fill=(0, 0, 0, 110))
    d.text((gx, gy), glyph, font=font, fill=(0x58, 0xA6, 0xFF, 255))

    label = "HTML"
    lfont = ImageFont.truetype(font_path, 118)
    lbox = d.textbbox((0, 0), label, font=lfont)
    lw = lbox[2] - lbox[0]
    lx = (S - lw) / 2 - lbox[0]
    ly = S * 0.70
    d.text((lx, ly), label, font=lfont, fill=(0xE6, 0xED, 0xF3, 255))

    return img


def main():
    base = make_base()
    base.save(os.path.join(OUT, "icon-1024.png"), "PNG")

    targets = {
        "icon-20@2x.png": 40, "icon-20@3x.png": 60,
        "icon-29@2x.png": 58, "icon-29@3x.png": 87,
        "icon-40@2x.png": 80, "icon-40@3x.png": 120,
        "icon-60@2x.png": 120, "icon-60@3x.png": 180,
        "icon-20@1x.png": 20, "icon-20@2x-ipad.png": 40,
        "icon-29@1x.png": 29, "icon-29@2x-ipad.png": 58,
        "icon-40@1x.png": 40, "icon-40@2x-ipad.png": 80,
        "icon-76@1x.png": 76, "icon-76@2x.png": 152,
        "icon-83.5@2x.png": 167,
    }
    for name, size in targets.items():
        base.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name), "PNG")

    print("wrote", len(targets) + 1, "icons to", OUT)


if __name__ == "__main__":
    main()
