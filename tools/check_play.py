"""Local check of a build and a store listing against Google Play requirements.

Checks what can be checked without the Play Console:
  * APK — target/min SDK, 64-bit, 16 KB pages, signature, debuggable, package name, permissions, names per locale,
    adaptive icon, leaked development files, size;
  * Godot project — English default name, permissions for the APIs used, monochrome icon layer,
    pinned save folder, license notice;
  * store listing (the store/ folder) — text lengths, 512 icon, 1024×500 feature graphic, screenshots.

Run:
  py -X utf8 check_play.py --apk build/android/game.apk --project . [--store store] [--mode release]

Debug mode (the default) is for a debug build: what only a release must have (a release signing key,
not debuggable, a real package name) is shown as "RELEASE", not as an error. Exit code 1 if there is a FAIL.

Play requirements as of 2026-11-22 are the constants below; when the rules change, update only them (with a date and a link).
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

# ── Requirements (checked 2026-11-22) ────────────────────────────────────────────────────────────────
# https://support.google.com/googleplay/android-developer/answer/11926878 — new apps and updates: API 36 from 2026-08-31
MIN_TARGET_SDK = 36
# https://developer.android.com/guide/practices/page-sizes — 16 KB for 64-bit native libraries (updates — from 2027-02-01)
PAGE_16K = 16384
# https://support.google.com/googleplay/android-developer/answer/9866151 — listing graphics
ICON_SIZE = (512, 512)
ICON_MAX_BYTES = 1024 * 1024
FEATURE_SIZE = (1024, 500)
SHOT_MIN_SIDE, SHOT_MAX_SIDE, SHOT_MAX_RATIO = 320, 3840, 2.0
SHOT_MIN_COUNT, SHOT_MAX_COUNT = 2, 8
TEXT_LIMITS = {"title.txt": 30, "short.txt": 80, "full.txt": 4000}

# Permissions Play requires to justify (declaration, form) or that change the Data safety answers
SENSITIVE = {
    "INTERNET": "network: data can be transmitted — the Data safety answers must be justified",
    "ACCESS_FINE_LOCATION": "location", "ACCESS_COARSE_LOCATION": "location",
    "ACCESS_BACKGROUND_LOCATION": "background location (separate declaration)",
    "CAMERA": "camera", "RECORD_AUDIO": "microphone", "READ_CONTACTS": "contacts",
    "READ_SMS": "SMS (restricted permission)", "SEND_SMS": "SMS (restricted permission)",
    "READ_CALL_LOG": "call log (restricted permission)", "CALL_PHONE": "phone calls",
    "READ_PHONE_STATE": "phone state", "READ_EXTERNAL_STORAGE": "storage",
    "WRITE_EXTERNAL_STORAGE": "storage", "MANAGE_EXTERNAL_STORAGE": "all files access (restricted permission)",
    "READ_MEDIA_IMAGES": "photos (declaration)", "READ_MEDIA_VIDEO": "videos (declaration)",
    "QUERY_ALL_PACKAGES": "list of apps (restricted permission)",
    "REQUEST_INSTALL_PACKAGES": "installing packages (restricted permission)",
    "SYSTEM_ALERT_WINDOW": "drawing over other apps", "AD_ID": "advertising ID (declaration)",
    "POST_NOTIFICATIONS": "notifications",
}
# Engine API → the permission it needs (searched in the project's scripts, except tests/ and tools/)
API_PERMISSIONS = {
    "vibrate_handheld": "VIBRATE",
    "HTTPRequest": "INTERNET", "HTTPClient": "INTERNET", "WebSocketPeer": "INTERNET",
    "StreamPeerTCP": "INTERNET", "PacketPeerUDP": "INTERNET", "ENetMultiplayerPeer": "INTERNET",
}
# Development files that don't belong in a build
LEAK_PATTERNS = [r"(^|/)tests?/", r"(^|/)tools/", r"(^|/)docs/", r"(^|/)shots/", r"(^|/)screenshots/",
                 r"drafts/", r"candidates/", r"\.bak$", r"(^|/)\.git/", r"\.keystore$", r"\.jks$", r"(^|/)store/"]
CYRILLIC = re.compile("[" + chr(0x400) + "-" + chr(0x4FF) + "]")   # the whole Cyrillic block (no literal letters here)

# ── Output ───────────────────────────────────────────────────────────────────────────────────────────
results: list[tuple[str, str, str]] = []
MODE = "debug"
PROJECT_VERSION: str | None = None   # the project's config/version (when --project is given)


def report(status: str, area: str, text: str) -> None:
    results.append((status, area, text))


def release_only(ok: bool, area: str, good: str, bad: str) -> None:
    """A release-only requirement: in debug mode a violation is marked "RELEASE", not an error."""
    if ok:
        report("OK", area, good)
    else:
        report("FAIL" if MODE == "release" else "RELEASE", area, bad)


# ── SDK tools ────────────────────────────────────────────────────────────────────────────────────────
def find_sdk() -> Path | None:
    for c in [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
              os.path.expandvars(r"%LOCALAPPDATA%\CodexTools\android-sdk")]:
        if c and Path(c, "build-tools").is_dir():
            return Path(c)
    return None


def build_tool(sdk: Path, name: str) -> Path | None:
    versions = sorted(Path(sdk, "build-tools").iterdir(), key=lambda p: [int(x) if x.isdigit() else 0
                                                                          for x in re.split(r"[.-]", p.name)])
    for v in reversed(versions):
        for ext in ("", ".exe", ".bat"):
            p = v / (name + ext)
            if p.exists():
                return p
    return None


def run(cmd: list, env: dict | None = None) -> str:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env)
    return r.stdout + r.stderr


# ── APK ──────────────────────────────────────────────────────────────────────────────────────────────
def elf_load_align(data: bytes) -> tuple[int, int]:
    """(bitness, smallest PT_LOAD alignment) of an ELF file."""
    if data[:4] != b"\x7fELF":
        return 0, 0
    bits = 64 if data[4] == 2 else 32
    if bits == 64:
        phoff = struct.unpack_from("<Q", data, 0x20)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
        al_off, fmt = 0x30, "<Q"
    else:
        phoff = struct.unpack_from("<I", data, 0x1C)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
        al_off, fmt = 0x1C, "<I"
    aligns = [struct.unpack_from(fmt, data, phoff + i * phentsize + al_off)[0]
              for i in range(phnum) if struct.unpack_from("<I", data, phoff + i * phentsize)[0] == 1]
    return bits, min(aligns) if aligns else 0


def zip_data_offset(path: str, info: zipfile.ZipInfo) -> int:
    with open(path, "rb") as f:
        f.seek(info.header_offset)
        hdr = f.read(30)
    n, e = struct.unpack_from("<HH", hdr, 26)
    return info.header_offset + 30 + n + e


def check_apk(apk: str, sdk: Path | None, project_perms: set[str] | None) -> None:
    A = "APK"
    size_mb = os.path.getsize(apk) / 1024 / 1024
    z = zipfile.ZipFile(apk)
    names = z.namelist()

    # 64-bit and 16 KB — no SDK needed, from the file itself
    libs = [i for i in z.infolist() if i.filename.startswith("lib/") and i.filename.endswith(".so")]
    abis = sorted({i.filename.split("/")[1] for i in libs})
    if not libs:
        report("OK", A, "no native libraries — 64-bit and 16 KB don't apply")
    else:
        has64 = any(a in ("arm64-v8a", "x86_64") for a in abis)
        report("OK" if has64 else "FAIL", A, f"ABI: {', '.join(abis)}" + ("" if has64 else " — no 64-bit"))
        bad = []
        for i in libs:
            bits, al = elf_load_align(z.read(i.filename))
            if bits == 64 and al < PAGE_16K:
                bad.append(f"{i.filename} (alignment {al})")
            if i.compress_type == zipfile.ZIP_STORED and zip_data_offset(apk, i) % PAGE_16K:
                bad.append(f"{i.filename} (uncompressed, zip offset not a multiple of 16 KB)")
        report("FAIL" if bad else "OK", A, "16 KB pages: " + ("; ".join(bad) if bad else
                                                                 f"all libraries aligned ({len(libs)})"))

    leaks = [n for n in names if any(re.search(p, n.removeprefix("assets/")) for p in LEAK_PATTERNS)]
    report("FAIL" if leaks else "OK", A, "development files in the build: " + (", ".join(leaks[:8]) if leaks else "none"))
    report("INFO", A, f"size {size_mb:.1f} MB")

    if not sdk:
        report("WARN", A, "Android SDK not found (ANDROID_HOME) — manifest and signature not checked")
        return
    aapt2 = build_tool(sdk, "aapt2")
    badging = run([aapt2, "dump", "badging", apk])

    def field(pattern: str) -> str:
        m = re.search(pattern, badging)
        return m.group(1) if m else ""

    pkg, vcode, vname = field(r"package: name='([^']*)'"), field(r"versionCode='([^']*)'"), field(r"versionName='([^']*)'")
    target = int(field(r"targetSdkVersion:'(\d+)'") or 0)
    min_sdk = field(r"(?:minSdkVersion|sdkVersion):'(\d+)'")
    report("OK" if target >= MIN_TARGET_SDK else "FAIL", A, f"targetSdk {target} (needs ≥ {MIN_TARGET_SDK})")
    report("INFO", A, f"minSdk {min_sdk}, version {vname} (code {vcode}) — the code grows with every upload")
    if PROJECT_VERSION is not None:
        same = vname == PROJECT_VERSION
        report("OK" if same else "FAIL", A, f"versionName «{vname}» " + ("= config/version" if same else
               f"≠ config/version «{PROJECT_VERSION}» — the game and the store will show different versions"))
    release_only(not pkg.startswith(("com.example", "org.example", "com.godot.game")), A,
                 f"package name {pkg}", f"temporary package name {pkg} (it can't change after publishing)")

    labels = dict(re.findall(r"application-label(?:-([\w-]+))?:'([^']*)'", badging))
    default = labels.get("", "")
    en = labels.get("en", default)
    distinct = sorted(set(labels.values()))
    ok = default == en and not CYRILLIC.search(default)
    report("OK" if ok else "FAIL", A, f"default name «{default}»" +
           ("" if ok else f" — not English (en: «{en}»); every language without a translation will see it") +
           f"; variants: {', '.join('«' + d + '»' for d in distinct)}")

    manifest = run([aapt2, "dump", "xmltree", apk, "--file", "AndroidManifest.xml"])
    debuggable = re.search(r"android:debuggable\(0x0101000f\)=(?:true|\(type 0x12\)0xffffffff)", manifest)
    release_only(not debuggable, A, "debuggable is off", "debuggable=true (Play won't accept it)")

    icon_xml = field(r"application-icon-\d+:'([^']*\.xml)'")
    if icon_xml:
        tree = run([aapt2, "dump", "xmltree", apk, "--file", icon_xml])
        layers = [l for l in ("background", "foreground", "monochrome") if f"E: {l}" in tree]
        report("OK" if len(layers) == 3 else "WARN", A, f"adaptive icon: {', '.join(layers) or 'no layers'}"
               + ("" if "monochrome" in layers else " — without a monochrome layer the themed icon won't be ours"))
    else:
        report("WARN", A, "no adaptive icon (raster only)")

    perms = set(re.findall(r"uses-permission: name='android\.permission\.(\w+)'", run([aapt2, "dump", "permissions", apk])))
    perms |= set(re.findall(r"uses-permission: name='com\.google\.android\.gms\.permission\.(\w+)'", badging))
    report("INFO", A, "permissions: " + (", ".join(sorted(perms)) or "none"))
    for p in sorted(perms & SENSITIVE.keys()):
        report("WARN", A, f"{p}: {SENSITIVE[p]}")
    if "INTERNET" not in perms:
        report("OK", A, "no network — Data safety: the app transmits nothing (provable from the manifest)")
    if project_perms is not None:
        missing = project_perms - perms
        extra = perms & SENSITIVE.keys() - project_perms
        report("FAIL" if missing else "OK", A, "permissions for the code's APIs: " +
               (f"missing {', '.join(sorted(missing))} — the feature silently fails" if missing else "all present"))
        if extra:
            report("WARN", A, f"sensitive permissions with no API in the code: {', '.join(sorted(extra))}")

    jh = os.environ.get("JAVA_HOME") or os.path.expandvars(r"%LOCALAPPDATA%\CodexTools\jdk-17")
    apksigner = build_tool(sdk, "apksigner")
    if apksigner and Path(jh).is_dir():
        env = dict(os.environ, JAVA_HOME=jh)
        sig = run([apksigner, "verify", "-v", "--print-certs", apk], env=env)
        schemes = [v for v in ("v2", "v3") if re.search(rf"Verified using {v} scheme.*: true", sig)]
        report("OK" if schemes else "FAIL", A, f"signature: schemes {', '.join(schemes) or 'no v2/v3'}")
        dn = re.search(r"Signer #1 certificate DN: (.*)", sig)
        dn = dn.group(1).strip() if dn else "?"
        release_only("Android Debug" not in dn, A, f"certificate {dn}", f"debug certificate ({dn})")
    else:
        report("WARN", A, "apksigner or JDK not found — signature not checked")


# ── Godot project ────────────────────────────────────────────────────────────────────────────────────
def check_project(root: Path) -> set[str]:
    global PROJECT_VERSION
    P = "project"
    proj = (root / "project.godot").read_text(encoding="utf-8")
    ver = re.search(r'^config/version="([^"]*)"', proj, re.M)
    PROJECT_VERSION = ver.group(1) if ver else ""
    report("OK" if PROJECT_VERSION else "WARN", P, f"config/version «{PROJECT_VERSION}»" +
           ("" if PROJECT_VERSION else " — empty: only the export preset knows the version"))
    name = re.search(r'^config/name="([^"]*)"', proj, re.M)
    name = name.group(1) if name else ""
    loc = re.search(r"config/name_localized=\{(.*?)\}", proj, re.S)
    loc_map = dict(re.findall(r'"([\w-]+)"\s*:\s*"([^"]*)"', loc.group(1))) if loc else {}
    report("FAIL" if CYRILLIC.search(name) else "OK", P, f"config/name «{name}»" +
           (" — the default must be English" if CYRILLIC.search(name) else ""))
    report("INFO", P, "localized names: " + (", ".join(f"{k}={v}" for k, v in loc_map.items()) or "none"))
    if "use_custom_user_dir=true" not in proj:
        report("WARN", P, "the PC save folder depends on config/name — renaming will \"lose\" the saves")

    presets = (root / "export_presets.cfg").read_text(encoding="utf-8") if (root / "export_presets.cfg").exists() else ""
    if presets:
        mono = re.search(r'launcher_icons/adaptive_monochrome_432x432="([^"]+)"', presets)
        report("OK" if mono else "FAIL", P, "monochrome icon layer " +
               ("set" if mono else "not set — Godot will put its own logo into the APK"))

    scripts = [p for p in root.rglob("*.gd") if not set(p.relative_to(root).parts[:1]) & {"tests", "tools", ".godot", "addons"}]
    code = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in scripts)
    needed = {perm for api, perm in API_PERMISSIONS.items() if re.search(rf"\b{api}\b", code)}
    report("INFO", P, "permissions the code needs: " + (", ".join(sorted(needed)) or "none"))
    lic = re.search(r"get_license_text|get_copyright_info|get_license_info", code)
    report("OK" if lic else "WARN", P, "Godot license notice " +
           ("is shown" if lic else "not found — MIT requires including it (an About / Licenses screen)"))
    return needed


# ── Store listing ────────────────────────────────────────────────────────────────────────────────────
def image_info(path: Path) -> tuple[int, int, bool] | None:
    """(width, height, has transparency) for PNG and JPEG without third-party libraries."""
    b = path.read_bytes()
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack_from(">II", b, 16)
        return w, h, b[25] in (4, 6) or b"tRNS" in b[:4096]
    if b[:2] == b"\xff\xd8":
        i = 2
        while i < len(b) - 9:
            if b[i] != 0xFF:
                i += 1
                continue
            m = b[i + 1]
            if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack_from(">HH", b, i + 5)
                return w, h, False
            i += 2 + struct.unpack_from(">H", b, i + 2)[0]
    return None


def check_store(store: Path) -> None:
    S = "store"
    langs = [d for d in sorted(store.iterdir()) if d.is_dir() and d.name != "screenshots"]
    if not langs:
        report("FAIL", S, "no language folders with title.txt / short.txt / full.txt")
    for d in langs:
        for fname, limit in TEXT_LIMITS.items():
            f = d / fname
            if not f.exists():
                report("FAIL", S, f"{d.name}/{fname}: no file")
                continue
            n = len(f.read_text(encoding="utf-8").strip())
            report("OK" if 0 < n <= limit else "FAIL", S, f"{d.name}/{fname}: {n} of {limit} characters")

    def one(pattern: str, label: str, want: tuple[int, int], alpha_ok: bool, max_bytes: int | None = None) -> None:
        files = sorted(glob.glob(str(store / pattern)))
        if not files:
            report("FAIL", S, f"{label}: no file ({pattern})")
            return
        p = Path(files[0])
        info = image_info(p)
        if not info:
            report("FAIL", S, f"{label}: {p.name} — not PNG or JPEG")
            return
        w, h, alpha = info
        probs = []
        if (w, h) != want:
            probs.append(f"{w}×{h}, needs {want[0]}×{want[1]}")
        if alpha and not alpha_ok:
            probs.append("has transparency (needs PNG without alpha or JPEG)")
        if max_bytes and p.stat().st_size > max_bytes:
            probs.append(f"{p.stat().st_size // 1024} KB > {max_bytes // 1024} KB")
        report("FAIL" if probs else "OK", S, f"{label} {p.name}: " + ("; ".join(probs) if probs else f"{w}×{h}"))

    one("icon*512*.png", "icon", ICON_SIZE, True, ICON_MAX_BYTES)
    one("feature*.*", "feature graphic", FEATURE_SIZE, False)

    def images(d: Path) -> list[Path]:
        return [Path(p) for p in sorted(glob.glob(str(d / "*"))) if p.lower().endswith((".png", ".jpg", ".jpeg"))]

    common = images(store / "screenshots")   # shared fallback set; a language may have its own <lang>/screenshots/
    all_shots: list[Path] = []
    for d in langs or [store]:
        shots = images(d / "screenshots") or common
        ok_count = SHOT_MIN_COUNT <= len(shots) <= SHOT_MAX_COUNT
        report("OK" if ok_count else "FAIL", S, f"{d.name}: {len(shots)} screenshots (needs {SHOT_MIN_COUNT}–{SHOT_MAX_COUNT})")
        all_shots += [p for p in shots if p not in all_shots]
    for p in all_shots:
        info = image_info(p)
        if not info:
            report("FAIL", S, f"screenshot {p.name}: not PNG or JPEG")
            continue
        w, h, alpha = info
        probs = []
        if min(w, h) < SHOT_MIN_SIDE or max(w, h) > SHOT_MAX_SIDE:
            probs.append(f"sides outside {SHOT_MIN_SIDE}–{SHOT_MAX_SIDE}")
        if max(w, h) / min(w, h) > SHOT_MAX_RATIO:
            probs.append(f"ratio {max(w, h) / min(w, h):.2f} > {SHOT_MAX_RATIO:g} (16:9 for games)")
        if alpha:
            probs.append("has transparency")
        rel = p.relative_to(store).as_posix()
        report("FAIL" if probs else "OK", S, f"screenshot {rel} {w}×{h}" + (": " + "; ".join(probs) if probs else ""))


# ── Entry point ──────────────────────────────────────────────────────────────────────────────────────
def main() -> int:
    global MODE
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apk", help="the built APK")
    ap.add_argument("--project", help="Godot project root (project.godot)")
    ap.add_argument("--store", help="store listing folder: <lang>/title|short|full.txt, icon-512.png, "
                                    "feature-graphic.png, screenshots/")
    ap.add_argument("--mode", choices=["debug", "release"], default="debug")
    a = ap.parse_args()
    MODE = a.mode
    if not (a.apk or a.project or a.store):
        ap.error("give at least one of --apk, --project, --store")

    needed = check_project(Path(a.project)) if a.project else None
    if a.apk:
        check_apk(a.apk, find_sdk(), needed)
    if a.store:
        if Path(a.store).is_dir():
            check_store(Path(a.store))
        else:
            report("FAIL", "store", f"folder {a.store} does not exist")
    elif MODE == "release":
        report("WARN", "store", "the store listing was not checked (--store)")

    order = {"FAIL": 0, "RELEASE": 1, "WARN": 2, "OK": 3, "INFO": 4}
    print(f"check_play — {MODE} mode, Play requirements as of 2026-11-22\n")
    for st, area, text in sorted(results, key=lambda r: (order[r[0]], r[1])):
        print(f"{st:6} {area:7} {text}")
    counts = {k: sum(1 for r in results if r[0] == k) for k in order}
    print("\nTotal: " + ", ".join(f"{k} {v}" for k, v in counts.items() if v))
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
