"""Genera el ícono de la app (Android + iOS) desde cero: C itálica DM Serif + tijeras de costura.
uso: python tool/make_icon.py [--preview salida.png]    (requiere Pillow)"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CLAY, CREAM, MUSTARD = (160, 80, 43), (246, 239, 228), (217, 164, 65)
FONT = ROOT / 'assets/fonts/DMSerifDisplay-Italic.ttf'
S = 2048  # supersampling; se reduce al final


def scissors(d, cx, cy, size, angle, color):
    """Tijeras abiertas, con las hojas hacia `angle` (radianes)."""
    ca, sa = math.cos(angle), math.sin(angle)
    tr = lambda x, y: (cx + x * ca - y * sa, cy + x * sa + y * ca)
    for side in (-1, 1):
        # hoja: triángulo largo y fino, abierto ±13°
        a = side * math.radians(13)
        pts = [(-.2, -.11), (1.5, 0), (-.2, .11)]
        rot = [(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)) for x, y in pts]
        d.polygon([tr(x * size, y * size) for x, y in rot], fill=color)
        # mango: brazo + anillo
        hx, hy = -.78, side * .36
        d.line([tr(0, 0), tr(hx * size, hy * size)], fill=color, width=round(size * .16))
        r, w = .28 * size, round(size * .13)
        x, y = tr((hx - .22) * size, (hy + side * .1) * size)
        d.ellipse([x - r, y - r, x + r, y + r], outline=color, width=w)
    x, y = tr(0, 0)
    d.ellipse([x - size * .08, y - size * .08, x + size * .08, y + size * .08], fill=MUSTARD)


def art(bg=True, mono=None, scale=1.0):
    """Arte a S×S. bg=False: solo primer plano (ícono adaptativo). mono: color único (ícono temático)."""
    img = Image.new('RGBA', (S, S), CLAY + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = lambda col: mono or col
    k = scale
    o = S * (1 - k) / 2
    P = lambda v: o + v * S * k  # coordenadas relativas (0..1) dentro del área útil
    if mono is None:  # sol boho detrás de la C (no va en el monocromo: se confundiría con la C)
        r = S * k * .15
        d.ellipse([P(.68) - r, P(.30) - r, P(.68) + r, P(.30) + r], fill=c(MUSTARD))
    font = ImageFont.truetype(str(FONT), round(S * k * .82))
    d.text((P(.37), P(.48)), 'C', font=font, fill=c(CREAM), anchor='mm')
    # tijeras en la boca de la C, cortando hacia la derecha por una línea punteada
    y = P(.53)
    scissors(d, P(.56), y, S * k * .14, 0, c(CREAM))
    for x0 in (.80, .86):  # dos guiones completos
        d.line([(P(x0), y), (P(x0 + .035), y)], fill=c(CREAM), width=round(S * k * .024))
    return img


def save(img, path, size, alpha=True):
    out = img.resize((size, size), Image.LANCZOS)
    if not alpha:
        out = out.convert('RGB')
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)


def main():
    if '--preview' in sys.argv:
        save(art(), Path(sys.argv[sys.argv.index('--preview') + 1]), 1024)
        return
    res = ROOT / 'android/app/src/main/res'
    full, fg, mono = art(), art(bg=False, scale=.66), art(bg=False, mono=(255, 255, 255), scale=.66)
    for dpi, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        save(full, res / f'mipmap-{dpi}/ic_launcher.png', px)
        save(fg, res / f'mipmap-{dpi}/ic_launcher_foreground.png', px * 108 // 48)
        save(mono, res / f'mipmap-{dpi}/ic_launcher_monochrome.png', px * 108 // 48)
    (res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
    (res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n', encoding='utf-8')
    (res / 'values/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % CLAY, encoding='utf-8')
    # iOS: todos los tamaños que pide el asset catalog, sin transparencia
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for e in json.loads((ios / 'Contents.json').read_text())['images']:
        px = round(float(e['size'].split('x')[0]) * int(e['scale'][0]))
        save(full, ios / e['filename'], px, alpha=False)
    print('íconos generados')


if __name__ == '__main__':
    main()
