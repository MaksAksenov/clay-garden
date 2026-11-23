"""Checks that check_play catches violations: on deliberately broken copies of an APK, a project and a store listing.

Run: py -X utf8 test_check_play.py <good APK> <Godot project root> [<16:9 shot> <shot wider than 2:1>]
The good APK and project are not changed: everything broken is built in a temporary folder.
"""
import shutil
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check_play as cp  # noqa: E402

failures = []


def run(fn, *args, mode="debug"):
    cp.results.clear()
    cp.MODE = mode
    fn(*args)
    return list(cp.results)


def expect(rows, status, needle, what):
    if not any(s == status and needle in t for s, _, t in rows):
        failures.append(f"not caught: {what} (expected {status} «{needle}»)")


def bad_elf(align: int) -> bytes:
    """A minimal 64-bit ELF with one PT_LOAD of the given alignment."""
    eh = bytearray(64)
    eh[:4] = b"\x7fELF"
    eh[4], eh[5] = 2, 1
    struct.pack_into("<Q", eh, 0x20, 64)          # e_phoff
    struct.pack_into("<HH", eh, 0x36, 56, 1)      # e_phentsize, e_phnum
    ph = bytearray(56)
    struct.pack_into("<I", ph, 0, 1)              # PT_LOAD
    struct.pack_into("<Q", ph, 0x30, align)
    return bytes(eh + ph)


def png(w: int, h: int, alpha: bool) -> bytes:
    """A PNG header without data — check_play reads only IHDR."""
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + ihdr + b"\0\0\0\0"


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    good_apk, project = sys.argv[1], Path(sys.argv[2])
    sdk = cp.find_sdk()
    tmp = Path(tempfile.mkdtemp(prefix="check_play_"))
    try:
        # 1. A good build: no errors in debug, in release — exactly three release items
        needed = cp.check_project(project)
        rows = run(cp.check_apk, good_apk, sdk, needed)
        if any(s == "FAIL" for s, _, _ in rows):
            failures.append("the good APK gave FAIL in debug mode: " + str([t for s, _, t in rows if s == "FAIL"]))
        rows = run(cp.check_apk, good_apk, sdk, None, mode="release")
        for needle in ("temporary package name", "debuggable", "debug certificate"):
            expect(rows, "FAIL", needle, f"release: {needle}")

        # version: APK ≠ config/version
        bv = tmp / "ver"
        bv.mkdir()
        (bv / "project.godot").write_text('config/name="Game"\nconfig/version="9.9"\n', encoding="utf-8")
        cp.check_project(bv)
        rows = run(cp.check_apk, good_apk, sdk, None)
        expect(rows, "FAIL", "≠ config/version «9.9»", "versionName doesn't match the project")

        # 2. A bad APK: a development file, a library aligned to 4 KB, an uncompressed one off a 16 KB boundary, a broken signature
        bad_apk = tmp / "bad.apk"
        shutil.copy(good_apk, bad_apk)
        with zipfile.ZipFile(bad_apk, "a") as z:
            z.writestr("assets/tests/leak.gd", "extends Node")
            z.writestr("assets/store/en/screenshots/01.png", b"x")
            z.writestr(zipfile.ZipInfo("lib/arm64-v8a/libbad.so"), bad_elf(4096), compress_type=zipfile.ZIP_STORED)
        rows = run(cp.check_apk, str(bad_apk), sdk, {"VIBRATE", "INTERNET"})
        expect(rows, "FAIL", "libbad.so (alignment 4096)", "ELF aligned to 4 KB")
        expect(rows, "FAIL", "zip offset not a multiple of 16 KB", "uncompressed library off a 16 KB boundary")
        expect(rows, "FAIL", "assets/tests/leak.gd", "development file in the build")
        expect(rows, "FAIL", "assets/store/", "store listing in the build")
        expect(rows, "FAIL", "missing INTERNET", "permission for a code API")
        expect(rows, "FAIL", "signature", "signature after changing the APK")

        # 3. A bad project: a Russian name, no monochrome layer, network in code, save folder tied to the name
        bp = tmp / "proj"
        (bp / "scripts").mkdir(parents=True)
        (bp / "project.godot").write_text('[application]\nconfig/name="Пластилиновый сад"\n', encoding="utf-8")
        (bp / "export_presets.cfg").write_text('[preset.0.options]\nlauncher_icons/main_192x192="res://i.png"\n',
                                               encoding="utf-8")
        (bp / "scripts" / "net.gd").write_text("var r := HTTPRequest.new()\n", encoding="utf-8")
        rows = run(cp.check_project, bp)
        expect(rows, "FAIL", "the default must be English", "Russian config/name")
        expect(rows, "FAIL", "its own logo", "no monochrome layer")
        expect(rows, "WARN", "save folder", "saves depend on the name")
        expect(rows, "WARN", "license notice", "no license notice")
        if "INTERNET" not in cp.check_project(bp):
            failures.append("not caught: HTTPRequest in code → INTERNET")

        # 4. A bad store listing
        st = tmp / "store"
        (st / "en").mkdir(parents=True)
        (st / "ru").mkdir()
        (st / "screenshots").mkdir()
        (st / "en" / "title.txt").write_text("Clay Garden: A Cozy Island Story", encoding="utf-8")  # 32 > 30
        (st / "en" / "short.txt").write_text("Grow a cozy clay garden.", encoding="utf-8")
        (st / "en" / "full.txt").write_text("A garden.", encoding="utf-8")
        (st / "ru" / "title.txt").write_text("Пластилиновый сад", encoding="utf-8")
        (st / "ru" / "short.txt").write_text("Уютный сад.", encoding="utf-8")       # no full.txt
        (st / "icon-512.png").write_bytes(png(1024, 1024, True))
        (st / "feature-graphic.png").write_bytes(png(1024, 500, True))
        (st / "screenshots" / "wide.png").write_bytes(png(1600, 720, False))
        (st / "screenshots" / "alpha.png").write_bytes(png(1920, 1080, True))
        rows = run(cp.check_store, st)
        expect(rows, "FAIL", "en/title.txt: 32 of 30", "title too long")
        expect(rows, "FAIL", "ru/full.txt: no file", "no full description")
        expect(rows, "FAIL", "1024×1024, needs 512×512", "icon is not 512")
        expect(rows, "FAIL", "has transparency (needs PNG without alpha", "feature graphic with alpha")
        expect(rows, "FAIL", "ratio 2.22", "screenshot wider than 2:1")
        expect(rows, "FAIL", "alpha.png 1920×1080: has transparency", "screenshot with alpha")
        expect(rows, "OK", "en: 2 screenshots", "screenshot count (shared set)")
        (st / "ru" / "screenshots").mkdir()
        (st / "ru" / "screenshots" / "one.png").write_bytes(png(1920, 1080, False))
        rows = run(cp.check_store, st)
        expect(rows, "FAIL", "ru: 1 screenshots", "a language's own set has fewer than two")

        # 5. Real game shots, if given
        if len(sys.argv) >= 4:
            for p in sys.argv[3:]:
                print(f"shot {Path(p).name}: {cp.image_info(Path(p))}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print("FAILURE:\n  " + "\n  ".join(failures))
        return 1
    print("check_play catches every planted violation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
