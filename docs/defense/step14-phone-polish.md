# Stage 14. Phone polish after the first device run: defense of the technical decisions

The owner installed the v0.9 debug APK on a Pixel 10 Pro XL and played. The task, in the owner's words (translated):

1. "Tapping the menu on a level opens it, but a second tap… opens it again! It should close. Only a tap on a free area
   closes it."
2. "Tapping the item's description drop-down shifts the camera by 10–15% of the screen; closing it shifts it back.
   That looks really bad. No camera jerks at all."
3. "The 'Back to hand' button looks foreign. Make it just a trash-can icon. 'Undo' is probably fine, though it overlaps
   the trash a bit — keep it. Put the two in a row. Remove the 'Place' button: we place with a double tap on the cell
   (or a mouse click on PC). The spot where 'Back to hand' / 'Place' appeared is cleared — no button there. The trash
   and undo buttons go vertically along the right edge of the screen."
4. "Rotation. Remove the rotate button. On a touchscreen: the island's center is the scene's center, the vertical axis
   is fixed for orbiting. A drag no longer moves the camera — it rotates the island around that axis by any angle.
   On PC Q/E still rotate by 90°, plus a mouse drag. After a free rotation Q/E finish the turn to the next fixed
   position in that direction (if less than 10° remain to it — to the one after)."
5. "Equal paddings everywhere — between elements and to the screen edges. Use UI/UX best practices."
6. "The level end — full screen with a dimmed background. The '?' hint — full screen with a dim too. The menu as well,
   not a drop-down. Think how to make it architecturally beautiful."
7. "If we do all this, it may be worth 1.0." — the version number is the owner's decision; not defended here.

What is in the code now (`scripts/ui_phone.gd`, `scripts/ui.gd`, `scripts/main.gd`):
- "≡" opens `corner` (a drop-down under the button) and `catcher`, a full-screen control that closes it on
  `InputEventScreenTouch` press. **Bug 1 cause:** the catcher hides on the touch press; the same tap then arrives as an
  emulated mouse press on "≡", which is no longer covered, and toggles the drawer open again. "?" (`memo`) has the
  same path.
- **Bug 2 cause:** `main._update_camera` sets `cam.h_offset = (-0.12 if card_collapsed else -0.25) * cam.size` on a
  level — the island's screen position depends on the rules card's collapsed state.
- The action cluster at the bottom right: `act_rot_item`, `act_rot_island`, `act_undo` in a row; `act_main` ("Place" /
  "Back to hand" / "Remove") above it. Placement: tap = try (ghost + "+N"), a second tap on the same cell no sooner than
  `CONFIRM_GUARD` = 0.25 s = place; long press on an item = back to hand / remove.
- One finger drag pans the camera (`_pan_screen` moves `pivot.position`, clamped to ±8), pinch zooms (7…24),
  `act_rot_island` / Q / E add ±90° to `yaw_target`. PC: left drag paints, right click removes, middle drag and WASD
  pan, the wheel zooms. Picking is a physics ray (`_pick`) — independent of the yaw.
- Margins: `SIDE` = 48 on both sides (the camera hole), `TOP` = 20, `BOTTOM` = 24; gaps 8 / 10 / 12 by place.
- Overlays: settings, About, the reset confirm, the language picker are full-screen dims (`_dim()` + `_center_panel`)
  with their own open/close code and `close_top()` order; the phone result is the left half with a light dim; the
  drawer and the cheat sheet are drop-downs.

## Decisions

**D1. One overlay layer for every window (the "sheet" stack).** A small class `Sheets` in `ui.gd` owns all modal
windows: the drawer ("≡"), the cheat sheet ("?"), the level result, settings, About, the reset confirm, the language
picker. One API: `open(name)`, `close(name)`, `close_top()`, `top()`, `is_open()`. Each sheet is a full-rect scrim
(one dim color token) with a centered panel (one panel style, one max width per kind). The stack decides: what Back /
Esc closes (the top), whether the world gets input (no, while any sheet is open — `is_over_ui` asks the stack), what a
tap on the scrim does (per sheet: `dismiss_on_scrim` — yes for the drawer, the cheat sheet, settings, About; no for
the result, the confirm and the picker, which need a choice). The scrim acts on **release**, and both the touch event
and its emulated mouse twin are consumed by the scrim — this fixes bug 1 by design, not by a timer. The "≡" and "?"
buttons stay under the scrim: a second tap on them is a tap on the scrim, so it closes. A short fade (0.12 s) on open
and close. The desktop layout uses the same stack for the windows it already has (settings, About, confirm, picker,
result); its corner panel stays as it is. Rejected: keeping per-window code and adding a guard against the duplicate
event (every new window would repeat the bug).

**D2. The camera never moves because of the interface.** The island's screen position is a function of the layout's
reserved areas only: on a level the island is centered in the free area right of the **expanded** rules card's width,
whether the card is open or collapsed; opening or closing any sheet doesn't touch the camera. The offset is computed
once per mode and window size, not per frame from UI state. Rejected: animating the shift smoothly (still a jerk).

**D3. Actions: a vertical column at the right edge; no action button over the play area.** The column, top to bottom:
"rotate item" (only for a rotatable item), "trash", "undo" — 56 px round icon buttons, vertically centered between
the top bar and the dock, at the right margin. `act_main` and `act_rot_island` are removed. Trash: enabled when the
tried cell holds an item that can go back (not fixed); a press returns it to the hand (level) or removes it (garden),
like a long press. Placement on a level: tap = try, a second tap on the same cell = place — the guard drops from
0.25 s to 0.06 s (it only filters a duplicate event), so a quick double tap places. A tap on an empty cell while an
item is tried moves the try. PC is unchanged: a click places. The coach tips and the cheat sheet say "double tap to
place". Rejected: a drag-from-dock-to-cell placement (a new gesture, not asked).

**D4. Orbit rotation around the island's center.** The camera pivot is fixed at the island's center (level: the map's
center; garden: the grid center); pan is removed on both touch and PC (no `_pan`, no WASD). The pitch stays 35°; only
the yaw changes, by any angle.
- Touch: one finger drag beyond `TAP_SLOP` rotates: yaw += Δx × (π / screen width) — a full-width drag is a half turn;
  a short release inertia (decays in ~0.3 s). The drag cancels the try-tap and the long press, as the pan did. Pinch
  zooms (7…24) around the fixed center.
- PC: Q / E rotate to the next fixed position (45° + k·90°) in that direction; if less than 10° remain to it, to the one
  after. A middle-button drag rotates freely; so does a left drag that **starts off the island** (sky), since a left
  drag over cells paints. The wheel zooms.
- A level starts at the nearest fixed position, as now.
Rejected: two-finger pan in the garden (the owner fixed the center; zoom out shows the whole island).

**D5. One spacing token.** `GAP` = 16 logical px (on the 1333×600 canvas ≈ 36 physical px) is the margin to every screen
edge and the distance between neighboring elements: "≡" ↔ the top bar ↔ "?", the bar ↔ the card, the card ↔ the dock,
the column buttons, the dock ↔ the edges. The camera cutout is added only where the system safe area says so (not a
fixed 48 px on both sides). Panels: content padding 12, radius 20; inner rounded elements radius = 20 − 12 (concentric).
Touch targets ≥ 56 logical px; text ≥ 15 px. The layout test checks the gaps numerically.

**D6. The sheets' content.**
- "≡" drawer: a centered panel "Level 38 · Beehive" (or "Garden") with the rare buttons in a 2-column grid: time, restart
  / new island (double press as now), coziness (garden), settings, to the menu; a "Close" button.
- "?" cheat sheet: a centered panel with the gestures for this mode (tap — try, double tap — place, hold — back to hand,
  drag — rotate, pinch — zoom, trash, undo), each with a small icon; a "Got it" button.
- Result: a centered panel over a full dim (as on PC), the island visible behind the dim; buttons as now.

**D7. Checks.** `test_touch`: the drawer and the cheat sheet open and close with a real touch press/release plus the
emulated mouse event (bug 1 reproduced first, failing on the old code); the island's screen position is identical with
the card open and collapsed and with any sheet open (bug 2); a drag changes the yaw and never the pivot; Q/E from
45°+30° / 45°+85° / −30° land on the expected positions; a quick double tap places, a tap on an item enables the trash,
the trash returns it to the hand, undo restores it; the layout at 1333×600, 1200×600 and 1333×750 in both languages:
every visible element's distance to the screen edge and to its neighbors equals `GAP` ±1, no overlaps, targets ≥ 56;
every sheet covers the full screen and blocks the world. Phone screenshots (Mobile renderer, 1600×720) of a level, the
garden, each sheet and the result for the owner before acceptance.

## Defense result

Main finding #1 (both critics): **a fixed center plus close zoom makes the garden's edge unreachable.** The garden is
18×18; at the closest zoom no yaw brings its outer cells on screen. The zoom range has to come from the map: the
closest zoom is the one at which every land cell stays in the free area at any yaw. For a level that changes little;
for the garden it removes most of the zoom-in — a trade-off the owner decides (see "Open").

Main finding #2 (the player): **Android's edge swipe is the system Back.** In landscape a rotation drag that starts at
the side edge would call `go_back()`, which leaves the level for the menu mid-puzzle. On a phone Back inside a level or
the garden opens the "≡" sheet instead; only its "Menu" button leaves.

Main finding #3 (the skeptic): **bug 1's diagnosis is a guess.** In Godot the emulated mouse twin may arrive before the
touch; then the catcher closes on the mouse press and the following touch press isn't marked as interface — a tap that
closes the settings can place an item in the garden. The fix must not depend on the order: a scrim reacts only to a
left-button **release whose press started on it**, and a sheet is closed by name.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 sheet stack | accepted with changes (both) | `scripts/sheets.gd` registers every window; react only to a release whose press began on the scrim (both event orders are harmless); close by name, not `close_top()` (hiding a control sends a fake release to it); **close is instant** (`visible = false` at once — `visible` stays the single source of truth, only the opening fades in); the newest sheet is moved on top; Back / Esc per-sheet hook (the confirm's hold-cancel); a grep test: no `.visible =` writes on sheet nodes outside `sheets.gd` |
| D2 fixed island position | changed (skeptic) | the shift is computed in **pixels** (the free area's center minus the screen center) and converted each frame with the current zoom: `h_offset = −s.x · size / H`; the free area also excludes the action column; check: the projected pivot = the free area's center ±1 px at zoom min / max, yaw 0 / 37 / 45°, three window sizes, card open / collapsed, any sheet open |
| D3 action column | changed (player) | anchored **bottom-right** (undo at the dock's height, trash above, a reserved slot for "rotate item" above it — nothing moves under the thumb when it appears); the trash is always visible, disabled without a selection, a tap on it then says "Tap an item first"; the selected item keeps its highlight; in the garden a tap on an occupied cell with an item tool selects it silently (no "nope"); the guard 0.25 s → 0.06 s (tests: +0.1 s places, +0.0 s doesn't); the tips say "tap again", shown until the 3rd placement. Rejected (me): the item flying to its dock tile — the "×N" badge already counts up, a fly animation is beyond the task |
| D4 orbit | changed (both) | a drag sets the yaw **directly** (no lag under the finger), smoothing only for Q / E and the snap; release inertia with `yaw_vel`, reset on level start, menu and in tests; a touch during the spin stops it and isn't a tap; a soft snap: after the spin stops, within 10° of 45° + k·90° the island eases into it, other angles stay; Q / E count from `yaw_target`: `floor((y − 45°) / 90°) ± 1` with the < 10° rule (cases: E from 45°, 44.99°, 75°, 130° → 135, 135, 135, 225; Q from −30°, −40° → −45, −135; near 3600°); the zoom range per map (finding #1); a middle-button drag or a left drag started off the island rotates on PC |
| D5 one gap | accepted with changes (both) | `GAP` = 16; the safe area is re-applied on every size change, **one symmetric side inset** (the max of left and right) so a flip doesn't move the layout; the safe area is printed once to the log for the device check; the rounded screen corners — checked on the device |
| D6 sheet content | changed (player), owner's request kept | the result is a centered panel over a full dim, as the owner asked, but opens **1 s after** the last placement (input blocked) so the finished island and its "+N" are seen first; the dim is lighter (0.35) so the garden stays visible behind it; the cheat sheet starts with "tap again — place"; icons only where they already exist |
| D7 checks | changed (skeptic) | bug 1 is reproduced through the real input path (`Input.parse_input_event` + flush, emulation on) and with hand-made twins in both orders; explicit pairs for the gap check; all the cases above; new flags `--sheet=drawer/help` and `--yaw=` for the screenshots; `--drawer` goes through the stack |

## Stage 14 results

**Done.**
- `scripts/sheets.gd` — the one owner of modal windows: `add / open / close / toggle / back / dismiss`, a scrim reacts
  only to a left-button release whose press began on it, close is instant (`visible` stays the truth), the newest sheet
  is moved on top and fades in. `ui.gd` registers the result, the language picker (Back passes through), settings, About
  and the reset window; `ui_phone.gd` adds "≡" (`drawer`) and "?" (`help`). No code writes a sheet's `visible` any more
  (a test greps for it).
- `ui_phone.gd` rebuilt on `GAP` = 16: "≡" and "?" in the top corners, the top bar and the garden chip centered over the
  free area, the rules card one gap under "≡", the dock from the left edge, the action column (rotate item — a reserved
  slot, trash, undo) at the bottom right; `act_main` and `act_rot_island` are gone. The safe area is re-applied on every
  size change with one symmetric side inset and printed once to the log. "≡" and "?" are centered panels over a dim;
  the result is centered over a lighter dim (0.35).
- `main.gd`: the camera orbits the island's fixed center — a drag sets the yaw directly (a full screen width is half a
  turn), release inertia (`yaw_vel`, ~0.3 s), a touch during a spin stops it and isn't a tap, a soft snap within 10° of
  45° + k·90°; Q / E by `next_yaw` (counted from `yaw_target`, skipping a position closer than 10°); a middle drag or a
  left drag started off the island turns it on PC; pan and WASD removed. The island is drawn at the free area's center
  (`_frame_island`: the pixel shift converted with the current zoom). The zoom range per map (`fit_size`): the closest
  zoom keeps every land cell inside the free area at any yaw, recomputed when the mode, the level, the free area or the
  garden's land changes. The result opens 1 s after the last placement (`result_wait`; the world, undo and Back wait).
  Back in a level or the garden on a phone opens "≡". A second tap on the same cell places after 0.06 s (a quick double
  tap); the "tap again" tip repeats until the 3rd placement. The trash (`main.trash`): the selected item back to the hand
  / removed, a hint without a selection, the fixed-item toast for a fixed one. In the garden a tap on an item with an
  item tool selects it silently.
- Texts in both languages: the cheat sheets (tap again first, trash, undo, drag to turn), the tips, the PC help (no WASD),
  "How to play", "Close", "Got it", the trash hint. README: controls, the touch table, the phone layout, new flags
  `--sheet=` and `--yaw=`.
- The version is **1.0** (`config/version`), `versionCode` 2 — the owner's decision.

**Found along the way.**
- The garden's zoom limit was first computed over the whole 18×18 grid with room for items: the island came out tiny.
  It is computed over the land (cell tops) and recomputed when the garden grows.
- The first test of "a tap on the dim doesn't reach the world" tapped the "≡" panel itself: on level 1 the whole island
  fits under the panel. The check moved to the garden, zoomed in past its limit (as `--zoom=` does) so cells show beside
  the panel.

**Checks.** `test_touch` — 5,346 checks, 0 failures: Q / E cases (45°, 44.99°, 75°, 130°, −30°, −40°, 3645°), the soft
snap, try → duplicate event doesn't place → 0.1 s later places, a drag turns with zero lag and never moves the pivot, a
touch stops a spin, the trash (hint, select, return), undo, the column doesn't move when "rotate item" toggles, "≡" and
"?" through `root.push_input` with the touch and the mouse twin in both orders (open, close by a second tap, a tap on
the dim closes and doesn't place), no direct `visible` writes, the island at the free area's center ±1 px at the closest
and farthest zoom, yaw 0 / 37 / 45°, card open / collapsed, a sheet open (levels 1, 38, 97), every cell inside the free
area at the closest zoom at 24 yaws (levels) and 12 yaws (garden), the pending result, Back opens "≡" in a level, the
gap of 16 to the edges and between explicit neighbors at 1333×600, 1200×600, 1333×750 in both languages, the sheets on
screen, no phone text about keys.

**Open.** A device pass on the Pixel: the event order of a real tap, the edge swipe, the rounded corners and the safe
area printed in the log, the feel of the rotation speed and inertia.
