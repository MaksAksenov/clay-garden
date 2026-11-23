# Stage 9. Settings: defense of the technical decisions

The user's task: a separate settings screen — a gear button in the main menu, one page with the basic settings:
sound (master volume, music, effects), language (flags next to the languages; ideally a carousel on a button, switching
instantly, without a restart), a progress reset in a separate confirmation window, where the button has to be held
for 3 seconds while a bar on the button fills up over those 3 seconds.

What exists now: sounds are synthesized at startup (`scripts/sfx.gd`), all of them go to one Master bus, and there is
only "Sound: on/off" (a button in the corner panel and M, not saved). **The game has no music.** Birds by day and
crickets at night are the same `sfx.play`. Language: a "Language: …" button in the menu and in the corner panel,
cycling; switching rebuilds the interface entirely (`set_language`), the choice is in `user://settings.json`.
Progress is `user://progress.json`, the garden `garden.json`, the calibration log `playlog.json`.

## Decisions

**D1. The settings screen is an overlay in `ui.gd`** in the common style (a dim + a centered panel, like the menu and
the result). It opens with a gear in the top-right corner of the main menu panel; it closes with a "Done" button, Esc
or a click on the dim. The "Language: …" buttons in the menu and the corner panel are removed — the language changes
in one place. "Sound on/off" in the corner panel and M stay as a quick "quiet" right in the game (it mutes the master
bus and doesn't touch the volumes).

**D2. Three audio buses — Master, Music, Effects**, created in code (`AudioServer.add_bus`), without a bus layout
file. Sliders 0–100%, volume via `linear_to_db`, 0% — the bus is muted. Audible right away: while dragging "Effects",
a "plop" sounds every ~0.15 s so you can hear the level. Birds and crickets go to the Effects bus. Defaults:
80 / 60 / 80.

**D3. Music is generative, synthesized in code** (like all sounds — not a single file). At startup ~10 music box
notes are synthesized (pentatonic, a soft attack, a long tail) — about 0.3 s of work; every beat the sequencer picks
the next note by a random walk over the scale, sometimes a rest, sometimes a two-note chord — the music doesn't
repeat and doesn't tire with a loop. Tempo and scale depend slightly on the time of day (quieter and sparser at
night). The Music bus. Without this the "Music" slider would move silence.

**D4. Language as a carousel:** `◀  [flag] Русский  ▶` with dots for the number of languages below it. Pressing an
arrow changes the language at once: the interface is rebuilt, and the settings screen is open again in the same
place. Flags **are drawn from an SVG written in the language dictionary** (`_meta.flag`,
`Image.load_svg_from_string`) — a new language brings its flag along with the translation, there are no image files;
emoji flags won't do (Windows doesn't render them). No flag — a badge with the language code ("DE"). English uses the
UK flag (a language, not a country; that's the convention in game menus). Flags also appear on the language choice
screen at first start.

**D5. Progress reset.** At the bottom of the settings screen — an unobtrusive "Reset progress…" button. It opens a
separate window: what will be lost (numbers: "★ 57 of 300, crowns: 4"), what stays (the free garden, language and
sound), and the buttons "Cancel" and "Hold for 3 seconds to reset". While the button is held, a bar fills it from left
to right (3 s, linear); release early and the bar quickly drains back (0.4 s), nothing is reset. Once it reaches the
end — `progress.json` becomes empty progress, the window closes, a "Progress reset" toast, the menu is redrawn
(spring, chapter 1). The `playlog.json` log (calibration data) and the garden are untouched.

**D6. Storage.** `settings.json` — `{"lang", "vol": {"master", "music", "effects"}}`; the old language-only file is
read. Mute via M is not saved (as now). It's written when the slider is released, not on every step. The settings and
progress paths become fields (like the garden's `save_path`), so tests write to their own files.

**D7. Acceptance checks.** `tests/test_settings.gd`: the buses are created, a slider → the bus volume, 0% → mute; the
settings are written and read (our own path), the old format is read; the carousel goes through all languages in a
circle, after each change there is one interface, the settings screen is open again, the text is in the new
language; flags are built for ru and en, without a flag — a badge; reset: holding for 1 s and releasing — progress is
intact, the bar drained; holding for 3 s — progress is empty, the garden is intact; Esc closes. `test_i18n` picks up
the new keys (both dictionaries). Screenshots: settings ru/en, the reset window with the bar halfway.

## Defense result

Main finding #1 (the skeptic): **the player's saves are at risk** — `_save_progress` and `_save_settings` go to the
real paths (constants), scene tests are protected only by `save_enabled`, and the progress reset adds the most
destructive write in the game. Until the paths become fields set before `_ready`, and a test compares the player's
files before and after a run, the stage is not done. Main finding #2 (the player): **the garden after a reset** —
autumn and winter in the garden are locked again, while `garden.json` may be wintry; the protocol said nothing about
what the player would see. And a general one: the hold must be driven by `button_down`/`button_up` and cancelled on
everything that doesn't send a release (focus loss, Esc), otherwise the bar sticks.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 overlay | changed (both) | the gear is also in the corner panel (one click from the garden and a level), instead of the language button; Esc and a click on the dim close only the top window; during a hold Esc only cancels the hold; the "Sound on/off" button and M mute the master bus |
| D2 buses | changed (both) | buses are looked up by name before being created (one `AudioServer` per process, Main is created many times in tests); 0% — `set_bus_mute`, not `-inf` dB; an "80%" caption next to the slider, a 5% step; the drag "plop" no more often than every 0.2 s; all `sfx.gd` players on Effects |
| D3 music | changed (both) | a minimum: pentatonic, a random walk, rests, a note every 1.4–3 s, a return to the tonic every ~40 s; no time-of-day dependence or two-note chords; notes are synthesized once per process (a static cache); a 2 s fade-in; on a level the music is quieter (×0.6) — it doesn't get in the way of thinking; 40% by default; music is off in tests via a flag |
| D4 carousel and flags | accepted with edits (both) | a flag is rasterized once with a size margin and cached by code; an SVG longer than 4 KB, an error or an empty image → a badge with the code; no text or filters in the SVG, the UK flag is simplified; the caption has a fixed width (the arrows don't jump); the dots under the carousel are clickable; language names are their own names; the change is deferred, after the rebuild the settings screen is open again, the menu's season tab is kept |
| D5 reset | changed (both) | the hold via `button_down`/`button_up` + a check every frame that the mouse button is still held; cancelled on window focus loss and Esc; the frame step is limited to 1/15 s (a stall won't reset in one frame); fires once; before the reset `progress.json` is copied to `progress.bak.json`; "Cancel" is bigger and on the left, the reset button is a warm terracotta, not red; no progress — "nothing to reset", no button; holding Space/Enter also fills the bar; the reset also clears `seen` (novelties are introduced again); **the garden**: its data is untouched, but if its season is now locked — on entry the garden changes to summer in a wave and a toast explains that autumn and winter come back in the campaign |
| D6 storage | changed (both) | `settings.json` = language + volumes (a language change can no longer erase the volumes); reading with type checks and a 0–1 clamp, anything missing takes the default; writing 0.5 s after the last change (catches the keyboard too), when the screen closes and when the window closes; writing to a temporary file and renaming |
| D7 tests | changed (both) | the `settings_path`/`progress_path` paths are fields, tests set their own before `add_child`; the test compares the hashes of the player's `progress.json`, `garden.json`, `settings.json`, `playlog.json` before and after a run; the hold uses real `InputEventMouseButton`s, the frame step is manual; early release, Esc and focus loss — cancel; the garden after a reset; the gear from a level and the garden; "one interface" — after waiting a frame. How the music sounds and how the flags look — only by ear and screenshots |

Rejected: pausing the level under the settings (a level has no timers affecting play), renaming "Sound" to "Quiet"
(the button does exactly what it did before, and players know it).

## Stage 9 results

**Done.** The settings screen (`ui.gd`): a gear in the main menu and "Settings" in the corner panel of the garden and
a level; three sliders (master, music, effects; an "80%" caption, a 5% step, a "plop" no more often than every
0.2 s); a language carousel `◀ flag Name ▶` with flags of all languages below it — switching is instant, the
interface is rebuilt, the settings are open again, the sliders and the menu tab are in place; "Reset progress…" → a
confirmation window (what will be lost in numbers, what stays, "Cancel" bigger and on the left, a warm reset button
with a bar, hold for 3 s with the mouse or Space/Enter). Buses Master ← Music, Effects (`sfx.gd`), generative music
box music (`music.gd`, notes in a static cache, a fade-in, ×0.6 on a level). Flags and icons are SVG in code / the
dictionary (`_meta.flag`), rasterized once; no flag — a badge with the code. Windows over the menu have an opaque
panel (in the first screenshot the menu showed through the settings text — fixed). `settings.json` = language +
volumes, written with a 0.5 s delay, when the screen and the window close, via a temporary file; `--lang` is not
saved. Reset: a copy in `progress.bak.json`, empty progress (and `seen`), the menu on spring, a toast; a garden season
locked after the reset becomes summer in a wave on entry, the plantings are intact. The progress, settings and log
paths are fields (tests set their own). The "Language: …" button was removed from the menu and the corner — the
language lives in the settings.

**Checks.** `tests/test_settings.gd` — 80 checks, 0 failures: reading volumes (junk, limits), flags (ru, en, a broken
and a long SVG → no flag → a badge), buses are created and don't multiply with a second Main, a slider → the bus
volume, 0% → mute, "quiet" doesn't touch the volumes, Esc closes only the top window, writing and reading the settings
(the old format), a full carousel circle (one interface, the settings open, the new language's text and flag), the back
arrow and a flag; the reset with real mouse presses: released early, Esc, focus loss, a release off the button, a 5 s
frame — progress intact, the bar drains; Space for 3 s — reset once, the file is empty, `.bak` exists, the menu on
spring; without progress — no reset button; the garden after the reset is summery, the items intact; "Settings" from
the garden and a level. **The player's files (`progress.json`, `progress.bak.json`, `garden.json`, `settings.json`,
`playlog.json`) are compared by md5 before and after — unchanged.** `test_i18n` (18,613) accounts for the own names on
the flags; `test_rules` 32,528, `test_campaign` 5,581, `test_perfect` 100/100, `test_sandbox` 258 — green.
Screenshots: `shots/settings_ru.png`, `settings_en.png`, `reset_ru.png`, `reset_en.png` (the bar halfway,
`--resetbar=0.5`), `menu_gear_ru.png`, `garden_corner_ru.png`.

**Open.** Tests can't say how the music sounds — it needs listening (the note density and the default volume of 40%
are constants at the top of `music.gd`).
