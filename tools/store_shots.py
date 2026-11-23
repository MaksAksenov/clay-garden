"""Google Play listing shots (stage 12): 16:9 screenshots per language, the 1024×500 graphic, the 512 icon, a thumbnail sheet.

Run (from the project folder):  py -X utf8 tools/store_shots.py [--only 01_garden,feature] [--langs ru,en]

What it does:
  * runs the game once per frame: Mobile renderer, 1920×1080, phone layout (--touch), no one-time captions
    (--nocoach), always --nosave --fresh and an explicit language; randomness is fixed with --shot (the frame repeats);
  * writes store/<lang>/screenshots/NN_<subject>.png, store/feature-graphic.png, store/icon-512.png;
  * checks that each file is new and the right size; compares md5 of the player's files before and after (untouched);
  * builds the thumbnail sheet shots/store_contact.png (≈ as in Play) — the main acceptance check: a human looks at it.
The Mobile renderer on PC uses desktop shadows — slightly better than on a phone; this is a store frame, not "as on a phone".
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# console build of Godot 4.7.2: the GODOT_CONSOLE variable, otherwise the CodexTools folder
GODOT = Path(os.environ.get("GODOT_CONSOLE") or
             os.path.expandvars(r"%LOCALAPPDATA%\CodexTools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"))
SIZE = (1920, 1080)
# subjects (stage 12 defense): the first two say "cozy" and "this is a puzzle"
SHOTS = [
    ("01_garden", ["--sandbox", "--fresh", "--seed=7", "--time=0.78", "--zoom=11"]),
    ("02_level", ["--level=45", "--autosolve", "--midplay"]),
    ("03_perfect", ["--level=47", "--autosolve"]),
    ("04_autumn", ["--sandbox", "--fresh", "--seed=11", "--season=autumn", "--zoom=11"]),
    ("05_year", ["--level=98", "--autosolve", "--yearview=winter", "--nocard"]),
]
FEATURE = ["--sandbox", "--fresh", "--seed=7", "--time=0.78", "--zoom=9", "--noui"]
PLAYER_FILES = ["garden.json", "progress.json", "progress.bak.json", "settings.json", "playlog.json"]


def user_dir() -> Path:
    proj = (ROOT / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'^config/custom_user_dir_name="([^"]+)"', proj, re.M)
    name = m.group(1) if m else "Godot/app_userdata/" + re.search(r'^config/name="([^"]+)"', proj, re.M).group(1)
    return Path(os.environ["APPDATA"]) / name


def hashes() -> dict:
    d = user_dir()
    return {f: hashlib.md5((d / f).read_bytes()).hexdigest() if (d / f).exists() else "-" for f in PLAYER_FILES}


def png_size(p: Path) -> tuple[int, int]:
    b = p.read_bytes()[:24]
    return struct.unpack(">II", b[16:24])


def shoot(out: Path, size: tuple[int, int], args: list[str], touch: bool) -> str | None:
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    t0 = time.time()
    cmd = [str(GODOT), "--rendering-method", "mobile", "--resolution", f"{size[0]}x{size[1]}", "--path", str(ROOT),
           "--", "--nosave", "--nocoach", *(["--touch"] if touch else []), *args, f"--shot={out.as_posix()}"]
    try:
        subprocess.run(cmd, capture_output=True, timeout=180)
    except subprocess.TimeoutExpired:
        return "timeout"
    if not out.exists() or out.stat().st_mtime < t0:
        return "file not written"
    if png_size(out) != size:
        return f"size {png_size(out)}, needs {size}"
    return None


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="ru,en")
    ap.add_argument("--only", default="", help="comma-separated: subject names, feature, art")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    store = ROOT / "store"
    store.mkdir(exist_ok=True)
    (store / ".gdignore").touch()   # the editor doesn't import the listing PNGs (and they won't leak into the APK)
    before = hashes()
    errors = []
    for lang in a.langs.split(","):
        for name, args in SHOTS:
            if only and name not in only:
                continue
            out = store / lang / "screenshots" / f"{name}.png"
            err = shoot(out, SIZE, ["--fresh", f"--lang={lang}", *args], touch=True)
            print(f"{lang}/{name}: {err or 'ok'}")
            if err:
                errors.append(f"{lang}/{name}: {err}")
    if not only or "feature" in only:
        err = shoot(store / "feature-graphic.png", (1024, 500), ["--lang=en", *FEATURE], touch=False)
        print(f"feature-graphic: {err or 'ok'}")
        if err:
            errors.append("feature-graphic: " + err)
    if not only or "art" in only:
        r = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--script", "res://tools/store_art.gd",
                            "--", f"--langs={a.langs}"], capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=180)
        lines = [l for l in r.stdout.splitlines() if l.startswith(("store_art", "ERROR"))]
        print("\n".join(lines))
        if not any("done" in l for l in lines):
            errors.append("store_art did not run")
    after = hashes()
    if after != before:
        errors.append(f"player files changed: {before} -> {after}")
    else:
        print("player files untouched (md5)")
    if errors:
        print("ERRORS:\n  " + "\n  ".join(errors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
