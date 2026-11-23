"""Everything in the repository is in English; Russian lives only in the localization package.

Fails (exit 1) on Cyrillic in any tracked or new file outside the allowlist below. Each allowlist entry says why.
Run from the project folder:  py -X utf8 tools/check_english.py
"""
import fnmatch
import re
import subprocess
import sys

CYRILLIC = re.compile("[" + chr(0x400) + "-" + chr(0x4FF) + "]")   # the whole Cyrillic block (no literal letters here)
ALLOWED = {
    "lang/ru.json": "the Russian localization package",
    "tests/golden_cards_ru.json": "reference Russian rules cards (localization test data)",
    "tests/golden_scores.json": "old-engine references that include the Russian card texts",
    "tests/test_rules.gd": "asserts on the Russian card text (Russian localization tests)",
    "tests/test_i18n.gd": "the Cyrillic regex and an assert on the Russian HUD title",
    "tests/test_touch.gd": "the key-name regex matches the Russian mouse terms",
    "tools/test_check_play.py": "a deliberately Russian app name and store texts as bad test data",
    "project.godot": "the Russian localized app name and the pinned PC save folder name",
    "README.md": "the real PC save folder name and the Russian localized app name",
    "docs/defense/*": "quotations of Russian localization strings in the decision records",
    "docs/legal/ip-review.md": "the Russian titles checked for conflicts are the subject of the review",
}
SKIP_EXT = (".png", ".jpg", ".jpeg", ".webp", ".import", ".ogg", ".wav")


def allowed(path: str) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in ALLOWED)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], capture_output=True, text=True,
                           encoding="utf-8").stdout.split("\n")
    bad = []
    for f in files:
        if not f or f.endswith(SKIP_EXT) or allowed(f):
            continue
        try:
            lines = open(f, encoding="utf-8").read().split("\n")
        except (UnicodeDecodeError, OSError):
            continue
        for i, line in enumerate(lines, 1):
            if CYRILLIC.search(line):
                bad.append(f"{f}:{i}: {line.strip()[:100]}")
    if bad:
        print("Cyrillic outside the localization package:\n  " + "\n  ".join(bad))
        return 1
    print("check_english: no Cyrillic outside the localization package")
    return 0


if __name__ == "__main__":
    sys.exit(main())
