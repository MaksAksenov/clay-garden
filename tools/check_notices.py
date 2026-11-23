"""Checks that About's Android block (ui.gd::ANDROID_LIBS) matches what a built APK really ships.

Godot's own notices (Engine.get_copyright_info / get_license_info) cover the engine and its thirdparty/ code, but not
the Java/Kotlin libraries in the Android template or the NDK C++ runtime. This tool reads the APK's dex class
definitions and native libraries, maps them to library families and fails on:
- a family present in the APK but missing from ANDROID_LIBS (a notice we owe);
- an ANDROID_LIBS entry with nothing of it in the APK (a notice for code we don't ship);
- a class package no family knows (a new dependency: decide its family and notice).

Usage: py -X utf8 tools/check_notices.py [path/to.apk]   (default: build/android/clay-garden-debug.apk)
Rerun after any change of the Godot version, the export template or a move to a Gradle build.
"""
from __future__ import annotations

import re
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# family -> (class package prefixes, native library names). "Godot" is covered by the engine's own notices.
FAMILIES = {
    "Godot": (("org/godotengine/", "com/godot/"), ("libgodot_android.so",)),
    "AndroidX (Jetpack) libraries": (("androidx/", "android/support/"), ()),
    "Kotlin Standard Library, kotlinx.coroutines": (("kotlin/", "kotlinx/coroutines/"), ()),
    "Guava: ListenableFuture": (("com/google/common/",), ()),
    "JSpecify annotations": (("org/jspecify/",), ()),
    "JetBrains Java Annotations": (("org/jetbrains/annotations/", "org/intellij/lang/annotations/"), ()),
    "Animal Sniffer Annotations": (("org/codehaus/mojo/animal_sniffer/",), ()),
    "LLVM libc++ (Android NDK C++ runtime)": ((), ("libc++_shared.so",)),
}


def _uleb(b: bytes, o: int) -> tuple[int, int]:
    r = s = 0
    while True:
        x = b[o]
        o += 1
        r |= (x & 0x7F) << s
        s += 7
        if x < 0x80:
            return r, o


def class_defs(dex: bytes) -> list[str]:
    """Descriptors of the classes a dex defines (not merely references), e.g. 'androidx/core/Foo;'."""
    sid_off = struct.unpack_from("<I", dex, 0x3C)[0]
    tid_off = struct.unpack_from("<I", dex, 0x44)[0]
    cd_n, cd_off = struct.unpack_from("<II", dex, 0x60)
    out = []
    for i in range(cd_n):
        type_idx = struct.unpack_from("<I", dex, cd_off + 32 * i)[0]
        str_idx = struct.unpack_from("<I", dex, tid_off + 4 * type_idx)[0]
        data = struct.unpack_from("<I", dex, sid_off + 4 * str_idx)[0]
        _, o = _uleb(dex, data)
        out.append(dex[o:dex.index(b"\0", o)].decode("utf-8", "replace")[1:])   # drop the leading 'L'
    return out


def listed_libs() -> list[str]:
    code = (ROOT / "scripts" / "ui.gd").read_text(encoding="utf-8")
    block = re.search(r"const ANDROID_LIBS := \[(.*?)\n\]", code, re.S)
    return re.findall(r'^\s*\["([^"]+)"', block.group(1), re.M) if block else []


def main() -> int:
    apk = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "android" / "clay-garden-debug.apk"
    if not apk.exists():
        print(f"no APK at {apk} — build it first (README: Build the APK)")
        return 2
    z = zipfile.ZipFile(apk)
    classes = [c for n in z.namelist() if re.fullmatch(r"classes\d*\.dex", n) for c in class_defs(z.read(n))]
    natives = {Path(n).name for n in z.namelist() if n.startswith("lib/") and n.endswith(".so")}

    found: dict[str, int] = {}
    unknown: dict[str, int] = {}
    for c in classes:
        fam = next((f for f, (pre, _) in FAMILIES.items() if c.startswith(pre)), None)
        if fam:
            found[fam] = found.get(fam, 0) + 1
        else:
            pkg = "/".join(c.split("/")[:2])
            unknown[pkg] = unknown.get(pkg, 0) + 1
    for so in natives:
        fam = next((f for f, (_, libs) in FAMILIES.items() if so in libs), None)
        if fam:
            found[fam] = found.get(fam, 0) + 1
        else:
            unknown["lib/" + so] = 1

    listed = listed_libs()
    fails = []
    print(f"{apk.name}: {len(classes)} classes, native: {', '.join(sorted(natives))}")
    for fam, n in sorted(found.items()):
        state = "engine notices" if fam == "Godot" else ("listed" if fam in listed else "NOT LISTED")
        print(f"  {n:5}  {fam} — {state}")
        if state == "NOT LISTED":
            fails.append(f"ships but missing from ANDROID_LIBS: {fam}")
    for lib in listed:
        if lib not in FAMILIES:
            fails.append(f"ANDROID_LIBS entry this tool doesn't know: {lib}")
        elif lib not in found:
            fails.append(f"listed in ANDROID_LIBS but not in the APK: {lib}")
    for pkg, n in sorted(unknown.items()):
        fails.append(f"unknown package ({n} classes): {pkg}")
    for f in fails:
        print("FAIL " + f)
    print("OK: About's Android block matches the APK" if not fails else f"{len(fails)} problem(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
