#!/usr/bin/env python3
"""Measure bar icons from a screenshot: width, height and vertical centre of each icon.

Drawn icons only line up with the bar's text glyphs if you measure them. This grabs a strip of the bar
with `grim`, keeps only pixels near the icon colour, splits them into icons by the gaps between them and
prints each icon's size and vertical centre in physical pixels, so you can compare icons to each other
(and to your own targets) instead of judging by eye.

  ./measure-bar.py --region "1040,0 240x30"        # logical px, grim -g syntax: "X,Y WxH"
  ./measure-bar.py --region "1040,0 240x30" --names chevron,robot,bluetooth,wifi,volume,display

Needs: grim, ImageMagick (`magick`). On a 2x display the capture is twice the logical size, so the bar
centre for a 30 px logical bar is y=30 (physical).

Caveat: dimmed parts (e.g. weak Wi-Fi bars at ~30% opacity) are not counted; use --fuzz higher or
--include-dim to measure the full ink.
"""
import argparse, os, re, subprocess, sys, tempfile


def theme_foreground():
    path = os.path.expanduser("~/.local/state/omarchy/current/theme/colors.toml")
    try:
        for line in open(path):
            m = re.match(r'\s*foreground\s*=\s*["\'](#[0-9A-Fa-f]{6})', line)
            if m:
                return m.group(1)
    except OSError:
        pass
    return "#ffffff"


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", required=True, help='grim region in logical pixels, e.g. "1040,0 240x30"')
    ap.add_argument("--color", default=theme_foreground(), help="icon colour (default: current theme foreground)")
    ap.add_argument("--fuzz", type=int, default=22, help="colour tolerance in percent (default 22)")
    ap.add_argument("--gap", type=int, default=5, help="empty columns that separate two icons (default 5)")
    ap.add_argument("--names", default="", help="comma-separated names for the icons, left to right")
    ap.add_argument("--include-dim", action="store_true", help="also count dimmed parts (luminance threshold)")
    ap.add_argument("--keep", action="store_true", help="keep the captured image and mask in the temp dir")
    a = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="measure-bar-")
    shot, mask = os.path.join(tmp, "bar.png"), os.path.join(tmp, "mask.png")
    run("grim", "-g", a.region, shot)
    if a.include_dim:
        run("magick", shot, "-colorspace", "Gray", "-threshold", "26%", "-morphology", "Open", "Disk:1.2", mask)
    else:
        run("magick", shot, "-fuzz", f"{a.fuzz}%", "-fill", "white", "-opaque", a.color,
            "-fill", "black", "+opaque", "white", "-threshold", "50%", mask)

    # column occupancy -> groups separated by >= gap empty columns
    txt = run("magick", mask, "-scale", "100%x1!", "-depth", "8", "txt:-")
    occ = [int(m.group(2)) > 20 for m in (re.match(r"(\d+),0: \((\d+)", l) for l in txt.splitlines()[1:]) if m]
    groups, start, last, gap = [], None, 0, 0
    for x, v in enumerate(occ):
        if v:
            if start is None:
                start = x
            last, gap = x, 0
        elif start is not None:
            gap += 1
            if gap >= a.gap:
                groups.append((start, last)); start = None
    if start is not None:
        groups.append((start, last))

    names = [n for n in a.names.split(",") if n]
    print(f"{'icon':<12}{'x':>5}{'w':>5}{'h':>5}{'centre-y':>10}   (physical px)")
    for i, (x0, x1) in enumerate(groups):
        out = run("magick", mask, "-crop", f"{x1 - x0 + 1}x{int(run('magick', 'identify', '-format', '%h', mask))}+{x0}+0",
                  "+repage", "-trim", "-format", "%w %h %Y", "info:").split()
        w, h, y = map(int, out)
        name = names[i] if i < len(names) else f"#{i + 1}"
        print(f"{name:<12}{x0:>5}{w:>5}{h:>5}{y + h / 2:>10.1f}")
    if a.keep:
        print("kept:", tmp)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"command failed: {' '.join(e.cmd)}\n{e.stderr}")
