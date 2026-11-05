#!/usr/bin/env python3
"""The top strip of the wallpaper, as the screen shows it, for SketchyBar's background (2026-11-05).

SketchyBar draws it under its pills, opaque: macOS still slides its auto-hidden menu bar in at the top edge, but
under the bar (level 25 over 24), so it never shows, and the bar still looks transparent. Run by theme-apply.sh at
each wallpaper change, so the strip always matches the current wallpaper.

Usage: bar-strip.py <image> [out] [height_pt]   (default out ~/.cache/macos-config/bar-strip.png, height 39)
The wallpaper is assumed in macOS's default "Fill Screen" mode: scaled to cover the screen, centred, cropped."""
import os, subprocess, sys, tempfile


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    vals = [int(l.split(":")[1]) for l in out.splitlines() if "pixel" in l]
    return vals[0], vals[1]


def screen():
    """Main screen size in points and backing scale, from Hammerspoon (falls back to this Mac's values)."""
    try:
        out = subprocess.run(["timeout", "5", "/opt/homebrew/bin/hs", "-c",
                              "local s=hs.screen.mainScreen() local f=s:fullFrame() "
                              "local m=s:currentMode() return f.w..' '..f.h..' '..(m.scale or 2)"],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=8).stdout.split()
        return float(out[-3]), float(out[-2]), float(out[-1])
    except Exception:
        return 2074.0, 1340.0, 2.0


def main():
    img = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.cache/macos-config/bar-strip.png")
    h_pt = float(sys.argv[3]) if len(sys.argv) > 3 else 39.0
    iw, ih = size(img)
    sw, sh, scale = screen()
    k = max(sw / iw, sh / ih)                 # points per image pixel ("Fill Screen")
    crop_w = round(sw / k)
    crop_h = max(1, round(h_pt / k))
    off_x = round((iw * k - sw) / 2 / k)
    off_y = round((ih * k - sh) / 2 / k)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "strip.png")
        subprocess.run(["sips", "-s", "format", "png", "-c", str(crop_h), str(crop_w),
                        "--cropOffset", str(off_y), str(off_x), img, "--out", tmp], check=True, capture_output=True)
        subprocess.run(["sips", "-z", str(round(h_pt * scale)), str(round(sw * scale)), tmp, "--out", out],
                       check=True, capture_output=True)
    print(f"{out}: {round(sw * scale)}x{round(h_pt * scale)} px from {img} (crop {crop_w}x{crop_h} at {off_x},{off_y})")


if __name__ == "__main__":
    main()
