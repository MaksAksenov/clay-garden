# Stage 10. Touch: defense of the technical decisions

The user's task: adapt the game for touch screens (Android; iOS later). A debug APK already builds, but the game is
built entirely around the mouse and keyboard.

What currently depends on the mouse (`scripts/main.gd`, `scripts/ui.gd`):
- **Hover is the game's main hint.** The cursor over a cell (`_update_hover` → `hover_cell`): a highlight, the item's
  "ghost", how much it gives and what the neighbors get (`_update_preview`), labels like "drought: 0", the warmth
  diamond, the beehive radius. A finger has no hover.
- Left click — place (can drag, "painting"), right click — remove / return to the hand, R — rotate the item, Q/E —
  rotate the island, the wheel — zoom, WASD and the middle button — the camera, 1…0 — pick an item, H — the hint,
  Tab/Y — seasons.
- The interface is designed for 1600×900 (`canvas_items`, `expand`). On a phone (screen height ~68 mm in landscape) a
  36 px button ≈ 2.7 mm, a 98 px palette ≈ 7 mm; the garden palette has up to 19 buttons of 84 px, wider than the
  screen.
- The left panel is a list of keys; tooltips (`tooltip_text`) don't appear on touch.

## Decisions

**D1. Touch mode.** `touch_mode` turns on on Android/iOS, and on a computer with a touch screen — on the first touch
(and turns off when a real mouse moves). The `--touch` flag is for checking on a computer. Godot turns touches into
mouse clicks by default (`emulate_mouse_from_touch`) — we keep that: the interface buttons rely on it; but in touch
mode the world (the island) listens only to `InputEventScreenTouch/Drag` and ignores emulated mouse events (`device ==
DEVICE_ID_EMULATION`), so one touch doesn't act twice.

**D2. Placing: "try → confirm" on a level, one tap in the garden.** On a level, tapping a cell makes it "tried": the
highlight, the ghost and the whole hover hint (points, neighbors, words) — like the cursor, only still. A second tap on
the same cell places; a tap on another cell moves the try. This keeps the main thing on a level — seeing the points
before deciding. In the free garden there are no stakes: a tap places the item or applies the terrain tool right away,
but the coziness counter hint (if it's on) also goes through trying.

**D3. Removing — a long press** (0.45 s without moving) on an item: in the garden it removes, on a level it returns to
the hand (fixed items — a toast, as now). A short vibration (`Input.vibrate_handheld(25)`) and the same sound. The
"Remove" tool in the garden stays.

**D4. Camera.** One finger dragged more than 12 px — moves the camera (not placing and not trying). Two fingers: a
pinch — zoom, a two-finger rotation — the island rotates in 90° steps (like Q/E) when the angle exceeds 35°. A tap =
released before 0.45 s with less than 12 px of movement.

**D5. On-screen buttons instead of keys.** A round "rotate item" button above the palette when the fence, bench or
hammock is in the hand (R). Rotating the island — the gesture (D4) and a pair of ⟲ ⟳ buttons nearby. Digits, H, Tab, Y,
T, M are already duplicated by buttons (the palette, the corner panel, the All Year Round row). In touch mode the list
of keys on the left is replaced by a short gesture cheat sheet (shown on entering the garden and on the first levels,
the "?" button — again).

**D6. Sizes.** In touch mode the interface window shrinks to a logical height of ~600 px on a phone and ~760 px on a
tablet (`content_scale_factor` from the physical screen height via DPI) — everything gets bigger; buttons no smaller
than 60 px (≈ 7 mm on a phone). The palette scrolls horizontally with a finger if it doesn't fit. The corner panel
collapses into a clock and a "☰" button; a press expands the list (time, season, coziness, settings, menu). Margins
for the camera cutout — from `DisplayServer.get_display_safe_area()`. The level menu (5×5 cards) at a height of 600 —
narrower cards, check with a screenshot.

**D7. Android details.** The system "Back" button = Esc (close a window, from a level/the garden — to the menu; in the
menu — minimize the app, not exit with a loss). When the app goes to the background (`NOTIFICATION_APPLICATION_PAUSED`)
the garden and settings are saved at once. Orientation — landscape by sensor (`sensor_landscape`). The app name — by
the system language (`config/name_localized`: «Пластилиновый сад» / "Clay Garden").

**D8. Graphics on a phone.** Android uses the Mobile renderer. The clay and water shaders are checked with a
screenshot on a computer with `--rendering-method mobile`. For mobile — lighter settings via `.mobile` project
overrides (shadows 2048, lower shadow softness, MSAA 2×). Performance — only on a real phone (an open item).

**D9. Acceptance checks.** `tests/test_touch.gd`: synthetic `InputEventScreenTouch/Drag` — trying and confirming,
moving the try, a tap in the garden places right away, a long press returns to the hand, a finger drag moves the
camera and places nothing, a pinch zooms, a two-finger rotation — by 90°, the emulated mouse doesn't place a second
time, the rotate-item button, "Back" = Esc, a pause saves; in mouse mode everything is as before (the other tests).
Layout: at the phone's logical size (1333×600) buttons no smaller than 60 px, nothing goes off screen or overlaps (the
palette, the corner panel, the HUD, the menu, the settings, the reset window). `--touch` screenshots in a phone-sized
window with `--rendering-method mobile`. Rebuilding the APK.

## Defense result

Main finding #1 (the skeptic): **tapping an interface button would place an item under it.** Godot gives the button an
emulated mouse event, but the `InputEventScreenTouch` itself still reaches the world's `_unhandled_input`. A finger
that started over the interface is marked "interface" by its index until released, and the world ignores it;
`is_over_ui` knows all the panels. Main finding #2 (the player): **there is no undo and no protection from accidental
placement**, and the gestures are invisible: nobody will guess "a second tap on the same cell" or a long press — every
hidden gesture needs a visible button.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 touch mode | changed (both) | the mode = `OS.has_feature("mobile")` or `--touch`; no automatic switching by the mouse (it would flicker on a laptop with a touchpad); in touch mode the world listens to no mouse at all; `--touch` on PC turns mouse input into touches so it can be checked without a phone |
| D2 trying | changed (both) | on a level: a tap — try (ghost, points, neighbors — like hover; the finger is already gone, the hint isn't covered); confirming — a second tap (no sooner than 0.25 s: a double tap doesn't place) **or a ✓ button above the cell**; a tap off the island clears the try. In the garden a tap places right away (on release), no "painting" with a finger. **Undo ↶** (10 steps) in the garden and on a level, Ctrl+Z on PC. Rejected: "drag from the hand" — it conflicts with one-finger camera movement, and trying already shows the points before deciding |
| D3 long press | changed (both) | an explicit finger state machine (tap / long / drag / two fingers), after a long press the release does nothing; a ring fill from 0.2 s; **a visible duplicate**: a tap on a placed item tries it and shows a ↩ button (back to hand / remove); vibration — a toggle in the settings (touch only), on by default |
| D4 camera | changed (both) | the drag threshold is 26 px (not 12); a pinch — zoom; **the two-finger rotation is removed** (it conflicts with the pinch and is fragile) — only the ⟲ ⟳ buttons; releasing one finger mid-pinch gives neither a tap nor a jump |
| D5 buttons | changed (player) | the action buttons (↶, ⟲, ⟳, rotate item) are in the bottom-right corner above the palette, under the thumb; the cheat sheet — short one-time banners on the first try, the first placement, entering the garden (not a list), the "?" button — the cheat sheet/card again |
| D6 sizes | changed (both) | a logical size of 1333×600 (`content_scale_size`, no DPI formula); buttons ≥ 56 px; the palette in a scroll with a `scroll_deadzone`; the corner panel doesn't collapse but shrinks (without "Sound" — it's in the settings); the level score and the garden coziness are always visible; the cutout safe area is converted to logical px. Deferred: "palette on the left" for left-handed players, filtering the palette by category |
| D7 Android | changed (skeptic) | "Back" — `NOTIFICATION_WM_GO_BACK_REQUEST`, `quit_on_go_back=false`; it closes the top window, from a level and the garden — to the menu, in the menu a second press within 2 s exits (Godot can't minimize), saving before exit; an app pause saves at once; orientation `sensor_landscape`, the name by the system language |
| D8 graphics | accepted (both) | `.mobile` shadow overrides (2048, softness 1); a `--rendering-method mobile` screenshot — shaders and the look (Mobile has no SSAO — barely noticeable); performance and heat — only on a phone, an open item |
| D9 checks | extended (both) | + a tap on an interface button doesn't place in the world; finger tremor below the threshold is still a tap; a double tap faster than 0.25 s doesn't place; releasing a finger mid-pinch; undo of every kind of action; the layout at 1333×600 with nothing off screen or overlapping. Only on a phone: real tremor, the cutout, scrolling, performance — an open item and one playtest counting mistaken placements |

## D10. The phone layout — a redo after the user's feedback

The user's feedback on the screenshots: "the layout is awful". They are right: D6 squeezed the desktop layout instead
of making a mobile one. The corner panel is 7 text buttons, a quarter of the screen; the palette with captions is the
bottom quarter and is cut off at the edge; the action buttons hang separately and run into the panel; the banner goes
under the panel; on a level two big text panels leave the island a narrow strip.

Principle: **the world is the main thing, the interface is thin edges; rare things on demand; frequent things under
the thumbs.**

- **Top left — "≡"** (56 px): a drawer (clock, time ×1/×30, new island / restart, season, coziness, settings, the
  level menu). Closed by a tap outside or by a choice. No corner panel on a phone.
- **Top center — a thin bar**: a level — "38 · Beehive · Coziness 2 ★★★" on one line (≈ 52 px); the level hint — in
  the "?" card. All Year Round — the season row under the bar. Garden — a coziness bar only if the counter is on.
- **Top right — "?"**: the rules card of the selected item (on a level) or the gesture cheat sheet (in the garden), as
  a panel under the button. On a level the card is open on entry and collapses on the first try — the rules are
  visible when needed and don't get in the way of placing.
- **Bottom — one row**: an item dock of 76 px icons without captions (on a level — a "×2" badge; the name — in the
  card), scrolling if it doesn't fit; on the right in the same row — "undo", "rotate island", "rotate item" (only for
  the fence, bench, hammock). Rotating the island — one clockwise button (4 presses — a full circle).
- **Banners** — under the top bar, width ≤ 560, never under panels.
- **The button above the tried cell, "remove"** — as text "Back to hand" / "Remove" (a "download" icon read wrongly).
  ✓ — as an icon.
- Check: a layout test (nothing overlaps, everything on screen, buttons ≥ 56 px, the world is free: top ≤ 72 px,
  bottom ≤ 100 px on a level without All Year Round) and phone screenshots: the menu, the garden, levels spring /
  winter / All Year Round.

### D10: the designer's mockups and the defense result

The user asked to put a separate designer agent (Haiku 5.5) on the layout and to use the Pixel 10 Pro XL screen
(1344×2992, 486 ppi, 20:9; in landscape a logical canvas of 1336×600, ×2.24). The designer made
`docs/design/phone-layout.md` and seven mockups `docs/design/phone_*.svg`. The critics accepted the basis (the world in
the center, "≡" for rare things, a thin bar, "?" on the right, the dock at the bottom, 56–76 px buttons, the menu grid)
and changed the following:

| Designer's decision | Verdict | What changes |
| --- | --- | --- |
| Land tools (raise, lower, water, remove) — in the dock behind a scroll | changed (both) | a separate permanent group of 4 tiles to the right of the items; only the items scroll |
| A ✓ + "Back to hand" bubble above the cell | changed (both) | **no bubble**: above the island only the ghost and "+2" (the bubble covered the neighbors the score is built on and ran into the dock and the season row); "Place" / "Back to hand" / "Remove" — a button in the bottom-right cluster under the thumb, appearing while trying; a second tap on the cell also places |
| The rules card collapses after the first try | changed (both) | it doesn't collapse by itself (the rules are needed exactly while trying); the whole card header is a collapse/expand button; the state is in `main` (survives a language change); the level hint is in the card |
| A tooltip on a long press in the dock | rejected (skeptic) | it conflicts with "back to hand", there are no tooltips on touch: the name is in a chip above the dock (garden) and in the card header (level); a 16 px "×N" badge |
| "≡": time, new island, season, coziness, hint, settings, menu | changed (both) | "Hint" removed (there's "?"), the passive clock on a level removed; **the season** — a tap on the garden's top bar ("Summer · Morning 08:41"), coziness — in the same bar when on; "Restart" — a double press, like "New island" |
| The "rotate item" slot always present (40% when not possible) | changed (player) | the button appears only when the item rotates (a pale one looks broken) |
| Toasts at y 96 / 124 | changed (skeptic) | one rule: under the top bar (on a level — under the All Year Round row), width 560 |
| Settings in two columns, RU/EN flags | changed (both) | two columns, wider sliders; the carousel and flags are built in a loop over languages (the carousel is the user's request, it stays) |
| The level result in the center | changed (player) | the result card is shifted aside, the dim is lighter — the garden just built stays visible |
| The menu without a panel on the dim | rejected (me) | cream cards and captions on a dark dim would need a second theme for the captions inside the buttons; the menu panel already fits on a phone — the panel stays, without a subtitle |
| A 48 px safe area on the sides | accepted (skeptic) | a constant 48 margin on the sides only in the phone layout; the desktop one doesn't change: the phone layout is a separate interface subclass (`scripts/ui_phone.gd`), chosen with `touch_mode` |
| Test | extended (skeptic) | layout at 1333×600 **and** 1200×600; "≡" and "?" open on every screen; the rules card doesn't overlap the dock on any of the 100 levels; the action button while trying; the card state after a language change |

## Stage 10 results

**Done.** Touch mode (`OS.has_feature("mobile")` or `--touch`): a finger state machine (tap / long press with a ring
/ camera drag / pinch), a finger over the interface is ignored by the world, in touch mode the mouse is only for
buttons. A level: try → confirm (a second tap no sooner than 0.25 s or "Place"); the garden: a tap places right away.
Undo of 10 steps (the cell before the action: land and item; on a level — through the hand; Ctrl+Z on PC). "Back", the
app pause, orientation, the name by language, `.mobile` shadows. **The phone layout is a separate subclass
`scripts/ui_phone.gd`** based on the designer's mockups with the critics' edits (D10); the desktop layout is
untouched.

**Found along the way.** The first version (D6 — a squeezed desktop layout) was rightly rejected by the user; the
layout test of the new version caught at once: on winter levels the rules card overlapped the dock by 42 px (now it
scrolls), at a width of 1200 the bar overlapped the card (now the bar is centered in the free space), three-digit star
thresholds stuck together, the level result covered the garden just built, and the "Improve" button hid the result
bypassing `hide_result`.

**Checks.** `tests/test_touch.gd` — 3,264 checks, 0 failures: gestures and trying, undo of every kind of action,
"Back", the pause, a tap on the interface doesn't reach the world; the layout at 1333×600 and 1200×600 in both
languages (the menu for all seasons, the settings, the reset, the garden, the garden with "≡" and "?", levels from
spring to All Year Round with a try and the cheat sheet, the result): everything on screen, nothing overlaps, buttons ≥
56 px, the 48 px side margins are free; the rules card doesn't overlap the dock on any of the 100 levels for any hand
item (the smallest gap is 12 px); the card state survives a language change; the player's files are untouched (md5).
The other tests are green. Phone screenshots (1600×720, the Mobile renderer): `shots/phone_*.png`. The APK was rebuilt.

**Open.** A check on the Pixel 10 Pro XL: real finger tremor, the dock scrolling, the camera cutout, performance and
heat; one playtest counting mistaken placements. The level 97 hint mentioned Tab — on a phone that's the season row
(fixed later with `_touch` text variants).
