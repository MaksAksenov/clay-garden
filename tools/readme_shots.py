"""README screenshots: the desktop layout, English, 1600×900, into screenshots/.

Run (from the project folder):  py -X utf8 tools/readme_shots.py [--only day,menu]

Every frame runs with --nosave --nocoach --lang=en; the menu uses --newplayer (empty progress, the player's own
progress file is not read). Randomness is fixed by --shot, so the frames repeat. The player's files are compared by
md5 before and after.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time

from store_shots import GODOT, ROOT, hashes, png_size

SIZE = (1600, 900)
GARDEN = ["--sandbox", "--fresh", "--seed=7"]
SHOTS = [
    ("day", [*GARDEN, "--time=0.42"]),
    ("night", [*GARDEN, "--time=0.9"]),
    ("menu", ["--newplayer", "--time=0.42"]),
    ("level", ["--level=45", "--autosolve", "--midplay"]),   # --midplay: an item back in hand, no result window
    ("winter_level", ["--level=84", "--autosolve", "--midplay"]),
    ("year_round", ["--level=100", "--autosolve", "--yearview=winter"]),
    ("garden_spring", [*GARDEN, "--season=spring", "--time=0.42"]),
    ("garden_summer", [*GARDEN, "--season=summer", "--time=0.42"]),
    ("garden_autumn", [*GARDEN, "--season=autumn", "--time=0.42"]),
    ("garden_winter", [*GARDEN, "--season=winter", "--time=0.42"]),
]


def shoot(name: str, args: list[str]) -> str | None:
    out = ROOT / "screenshots" / f"{name}.png"
    if out.exists():
        out.unlink()
    t0 = time.time()
    cmd = [str(GODOT), "--resolution", f"{SIZE[0]}x{SIZE[1]}", "--path", str(ROOT),
           "--", "--nosave", "--nocoach", "--lang=en", *args, f"--shot={out.as_posix()}"]
    try:
        subprocess.run(cmd, capture_output=True, timeout=180)
    except subprocess.TimeoutExpired:
        return "timeout"
    if not out.exists() or out.stat().st_mtime < t0:
        return "file not written"
    if png_size(out) != SIZE:
        return f"size {png_size(out)}, needs {SIZE}"
    return None


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated shot names")
    only = set(filter(None, ap.parse_args().only.split(",")))
    before = hashes()
    errors = []
    for name, args in SHOTS:
        if only and name not in only:
            continue
        err = shoot(name, args)
        print(f"{name}: {err or 'ok'}")
        if err:
            errors.append(f"{name}: {err}")
    if hashes() != before:
        errors.append("player files changed")
    else:
        print("player files untouched (md5)")
    if errors:
        print("ERRORS:\n  " + "\n  ".join(errors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
