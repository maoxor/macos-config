#!/usr/bin/env python3
"""A READABLE base16 palette from an image (no dependencies: sips + the standard library).

Usage: python3 -I scripts/palette-from-image.py <image> <output.nix> [name]

How (Stylix's raw generation gave 8 accents of the same hue):
- background (base00-03): hue of the image's most colourful tones, in shadow (towards violet, lightness 0.16);
- text (base04-07): dominant hue of the light areas, very light and barely saturated;
- accents (base08-0F): one fixed hue family per role (red, orange, gold, green, cyan, blue, purple, brown) so
  they stay distinct, each pulled (±20°) towards a hue really present in the image when there is one;
- WCAG contrast >= 4.5:1 for every accent and the text on the background (lightness raised if needed).
"""
import colorsys
import math
import os
import struct
import subprocess
import sys
import tempfile

ROLES = [  # (key, target hue in degrees, saturation, HLS lightness, comment)
    ("base08", 355, 0.75, 0.66, "red: errors, deletions"),
    ("base09", 28, 0.80, 0.64, "orange: constants"),
    ("base0A", 45, 0.85, 0.70, "gold: warnings"),
    ("base0B", 140, 0.45, 0.62, "green: success, additions, strings"),
    ("base0C", 185, 0.60, 0.64, "cyan: escapes, info"),
    ("base0D", 212, 0.65, 0.62, "blue: functions, links, system accent"),
    ("base0E", 275, 0.55, 0.72, "purple: keywords"),
    ("base0F", 25, 0.45, 0.55, "brown: deprecated"),
]


def pixels(path):
    """Shrink the image to a 96x54 24-bit BMP with sips; return the list of (r, g, b) in 0..1."""
    with tempfile.TemporaryDirectory() as d:
        bmp = os.path.join(d, "p.bmp")
        subprocess.run(["sips", "-s", "format", "bmp", "-z", "54", "96", path, "--out", bmp],
                       check=True, capture_output=True)
        data = open(bmp, "rb").read()
    off = struct.unpack_from("<I", data, 10)[0]
    w, h = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    step, h = bpp // 8, abs(h)
    row = (w * step + 3) & ~3
    out = []
    for y in range(h):
        for x in range(w):
            i = off + y * row + x * step
            b, g, r = data[i], data[i + 1], data[i + 2]
            out.append((r / 255, g / 255, b / 255))
    return out


def hue_mean(hues_w):
    """Weighted circular mean of hues (degrees)."""
    sx = sum(w * math.cos(math.radians(h)) for h, w in hues_w)
    sy = sum(w * math.sin(math.radians(h)) for h, w in hues_w)
    if abs(sx) + abs(sy) < 1e-9:
        return None
    return math.degrees(math.atan2(sy, sx)) % 360


def hexc(h, l, s):
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360, max(0, min(1, l)), max(0, min(1, s)))
    return "%02x%02x%02x" % tuple(round(c * 255) for c in (r, g, b))


def lum(hx):
    def ch(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(hx[i:i + 2]) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# Light theme when ~/.config/macos-config/theme-light exists (home-manager creates it from profile.nix lightTheme).
LIGHT = os.path.exists(os.path.expanduser("~/.config/macos-config/theme-light"))
STEP = -0.02 if LIGHT else 0.02  # accents darken on a light background, lighten on a dark one


def main():
    img, out = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else os.path.splitext(os.path.basename(img))[0]
    px = [colorsys.rgb_to_hls(*p) for p in pixels(img)]  # (h 0..1, l, s)
    dark = [(h * 360, s) for h, l, s in px if l < 0.35 and s > 0.08]
    light = [(h * 360, s) for h, l, s in px if l > 0.65 and s > 0.05]
    vivid = [(h * 360, s * (1 - abs(l - 0.5) * 2)) for h, l, s in px if s > 0.25 and 0.2 < l < 0.85]
    tones = [(h * 360, s) for h, l, s in px if s > 0.12 and 0.25 < l < 0.85]  # raw saturation, for softening
    tinted = [(h * 360, s) for h, l, s in px if s > 0.08]
    # Background hue: the image's most colourful tones (the flowers of a misty scene), not its overall
    # average nor its shadows, which drift to a dull navy.
    bright = [(h * 360, s) for h, l, s in px if s > 0.45 and 0.2 < l < 0.85]
    hd = hue_mean(bright) if len(bright) > 50 else (hue_mean(tinted) or (hue_mean(dark) if dark else 220))
    hl = hue_mean(light) if light else hd
    sd = 0.30
    # The dark background is that tone in shadow: a cool hue shifts ~20° towards violet (lavender at dusk
    # reads indigo; kept as is it falls into navy), lightness 0.16. Chosen 2026-10-21 from Ghostty previews.
    hb = min(hd + 20, 270) if 190 <= hd <= 260 else hd
    # Warm tone (red, orange, yellow): any tint of it in shadow reads maroon/brown, and the light areas of such an
    # image give a pink text. The background and text are then a neutral charcoal and off-white, and the terminals
    # more opaque so the warm wallpaper barely shows through (2026-11-03: a red-on-black fractal turned every
    # window brown; saturation 0.12 still read brown next to the red image, 0.03 does not).
    warm = hd >= 330 or hd <= 60
    l0, sd, st = (0.11, 0.03, 0.03) if warm else (0.16, sd, 0.45)
    opacity = 0.95 if warm else 0.88
    if LIGHT:
        # Light variant: the background is a pale shade of the colourful tone (lightness 0.78), dark text.
        pal = {
            "base00": hexc(hd, 0.78, 0.45), "base01": hexc(hd, 0.72, 0.42), "base02": hexc(hd, 0.64, 0.40),
            "base03": hexc(hd, 0.38, 0.25),
            "base04": hexc(hd, 0.26, 0.30), "base05": hexc(hd, 0.12, 0.40), "base06": hexc(hd, 0.08, 0.40),
            "base07": hexc(hd, 0.05, 0.40),
        }
    else:
      pal = {
        "base00": hexc(hb, l0, sd), "base01": hexc(hb, l0 + 0.04, sd * 0.85), "base02": hexc(hb, l0 + 0.12, sd * 0.7),
        "base03": hexc(hb, 0.50, sd * 0.35),
        "base04": hexc(hl, 0.72, min(0.25, st)), "base05": hexc(hl, 0.88, st), "base06": hexc(hl, 0.92, st),
        "base07": hexc(hl, 0.95, st),
    }
    bg = pal["base00"]
    for key in (() if LIGHT else ("base04", "base05")):
        l = 0.72 if key == "base04" else 0.88
        while contrast(pal[key], bg) < (4.5 if key == "base04" else 10) and l < 0.97:
            l += 0.02; pal[key] = hexc(hl, l, min(0.25, st) if key == "base04" else st)
    notes, chosen = {}, []
    dist = lambda a, b: min(abs(a - b), 360 - abs(a - b))
    # The blue accent (links, border, system accent) is the colourful tone itself when it is blue-violet.
    vivid_tone = None
    if len(bright) > 50 and 200 <= hd <= 260:
        bs = [(l, s) for h, l, s in px if s > 0.45 and 0.2 < l < 0.85]
        vivid_tone = (hd, 0.72, min(0.65, max(0.50, sum(s for _, s in bs) / len(bs))))
    for key, target, s, l, note in ROLES:
        if key == "base0D" and vivid_tone:
            h, l, s = vivid_tone
            c = hexc(h, l, s)
            while contrast(c, bg) < 4.5 and 0.1 < l < 0.9:
                l += STEP; c = hexc(h, l, s)
            pal[key] = c; chosen.append(h)
            notes[key] = f"{note} (hue {round(h)}°, the image's colourful tone)"
            continue
        # Narrower pull window for orange and gold (otherwise both are pulled to the same image hue)
        window = {"base09": 8, "base0A": 15}.get(key, 22)
        near = [(h, w) for h, w in vivid if dist(h, target) <= window]
        h = target
        if sum(w for _, w in near) > 0.5:
            m = hue_mean(near)
            if m is not None:
                h = m
        # Keep at least 20° from the accents already placed (except brown, distinct by its lightness):
        # on collision, move to 20° from the neighbour, on the side of its reference hue.
        if key != "base0F":
            for _ in range(8):
                clash = [c for c in chosen if dist(c, h) < 20]
                if not clash:
                    break
                c = clash[0]
                side = 1 if ((target - c + 540) % 360 - 180) >= 0 else -1
                h = (c + 20 * side) % 360
            chosen.append(h % 360)
        # A hue taken from a soft image (mist, pastel) stays soft: saturation follows the image's tones of that
        # hue and lightness rises, instead of the fixed vivid default (a royal blue on a lavender wallpaper).
        if h != target:
            st = [x for hh, x in tones if dist(hh, h) <= 15]
            if st:
                img_s = sum(st) / len(st)
                if img_s < s / 1.6:
                    s, l = max(0.35, img_s * 1.6), max(l, 0.70)
        c = hexc(h, l, s)
        while contrast(c, bg) < 4.5 and 0.1 < l < 0.9:
            l += STEP; c = hexc(h, l, s)
        pal[key] = c
        notes[key] = f"{note} (hue {round(h)}°{', from the image' if h != target else ''})"
    lines = [f'# Generated by scripts/palette-from-image.py from {os.path.basename(img)}: do not edit by hand.',
             '{', f'  scheme = "{name}"; author = "macos-config (auto)";',
             f'  opacity = {opacity}; # Ghostty: the blurred wallpaper shows through slightly']
    for i in range(16):
        k = f"base0{i:X}"
        lines.append(f'  {k} = "{pal[k]}";' + (f' # {notes[k]}' if k in notes else ''))
    lines.append('}')
    open(out, "w").write("\n".join(lines) + "\n")
    worst = min(contrast(pal[f"base0{i:X}"], bg) for i in range(8, 16))
    print(f"{out}: background #{bg} (hue {round(hd)}°), text #{pal['base05']}, minimum accent contrast {worst:.1f}:1")


if __name__ == "__main__":
    main()
