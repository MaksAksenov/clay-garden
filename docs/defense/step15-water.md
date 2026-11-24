# Stage 15. Water finds its level; waterfalls: defense of the technical decisions

The owner, looking at the README garden screenshot (translated): "the water area sits higher than the land — make a
separate test that this can't happen. And if a water cube is on the island's edge, a waterfall should run down from it
(it fades out at the bottom of the dark block, it doesn't go off screen)."

What is in the code now:
- A cell has one column height (`terrain.heights`); a water cell (`terrain.water`) draws its water at the column top
  (`build_cell`: sand, then a water slab at `top − 0.23`). Water and land heights are independent.
- Levels: `parse_map` gives every `~` the height 2. Gardens: `generate` sets pond cells to height 2. The player in the
  garden can raise, lower and toggle water on any cell.
- Measured: **34 of 100 levels** and **118 of 200 generated gardens** (seed 7, the README one, included) have a water
  cell higher than an orthogonal land neighbor — always a pond at 2 with a rim at 1. **108 water sides** face the
  island's edge (no land) — where waterfalls belong.
- Scoring reads heights in one place: "view" (a bench higher than all its neighbors). Lowering those ponds flips the
  view of 4 cells in 4 levels; only levels 37 and 99 have a bench in hand, and the solver's ideal stays 42 and 281
  (the data's values) — no level changes its stars or needs a new id.

## Decisions

**D1. One rule: water finds its level.** A pond is a set of orthogonally connected water cells; it has one level — the
lowest of its cells' heights and of the land cells on its rim (never below 1). Every water cell of a pond is set to
that level. A land rim cell is never lower than the pond next to it; two touching water cells never differ. A side
with no land (the island's edge) is open — that is where a waterfall falls. One static function
`Terrain.settled(land, water) -> land` applies the rule; `parse_map`, `generate`, loading a saved garden and every
garden edit go through it, and the test uses it as the oracle.

**D2. Levels.** `parse_map` settles the map: the 34 levels' ponds drop from 2 to 1. The level data (`data/levels.json`)
stays as written — the settling is a property of the engine, not of each map. `test_perfect` guards the ideals.

**D3. The garden: edits keep the rule.** After raise / lower / water on a cell, the cell's pond (and the ponds next to it)
is settled at once:
- lowering a rim cell below a pond — the pond sinks with it (all its cells), as real water would run out;
- water on a cell higher than a land neighbor — the cell sinks to the rim's level (the water "digs" its bed);
- raise on a water cell — refused ("nope" and a toast "Water stays level — raise the land around it"), since the cell
  would sink right back.
Each change is visible: the sinking cells animate like any edit. Rejected: refusing every edit that breaks the rule
(the player couldn't drain a pond by digging, which is the natural gesture).

**D4. Undo covers everything one edit changed.** An undo entry becomes a set of cells with their states before the edit
(the edited cell plus every cell the settling moved); undo restores them all at once. Entries stay one per edit.

**D5. Saved gardens.** Loading a garden settles it once (a garden made before this stage may have raised ponds); the
file is rewritten on the next ordinary save. The player's items stay; an item on a cell that sinks sinks with it.

**D6. Waterfalls.** On each side of a water cell with no land neighbor: a sheet of falling water from the water's
surface down the column's side to the bottom of the dark root block (`bottoms[c]`), slightly narrower than the side,
streaks scrolling down (a shader, no textures), opaque at the lip and fading out to nothing at the bottom, with a little
foam at the lip. Never below the column's bottom. In winter (and All Year Round's winter view) it is frozen: the ice
color, no motion, a few icicle bumps at the bottom. Built in `build_cell`; an edit that adds or removes a neighbor
rebuilds the neighbors' columns too. Not a collision shape: taps go to the column as before.

**D7. Checks.** A new `tests/test_water.gd`:
- the invariant (no water above a land neighbor, no step between touching water cells) on all 100 levels as the game
  loads them, on 200 generated gardens, and after 2,000 random garden edits (raise / lower / water) from a seed;
- undo after each random edit restores every cell exactly;
- the edit cases of D3 one by one;
- waterfalls exist exactly on the open sides (count = open sides), none on inner sides, each ends at its column's
  bottom (± 0.01) and never lower, frozen in winter;
- `test_perfect` — the ideals unchanged.
Screenshots: the README garden (seed 7) and a level with edge water, summer and winter, PC and phone.

## Defense result

Main finding #1 (both critics): **refusing "raise" on water is a dead end, and its toast would teach something false.**
Raising the rim and tapping the pond again would still be refused, since one raised water cell sinks straight back; a
pond that sank could only come back up by removing and re-pouring the water. Raise on a water cell lifts **the whole
pond** by one when every land cell on its rim is at least that high; otherwise it is refused and the toast says so.

Main finding #2 (both): **items on the other cells a settling moves would float.** `_after_terrain` runs only for the
edited cell; it must run for every moved cell (a lily, a snowman on ice), and undo must do the same.

Main finding #3 (the skeptic): **a waterfall is the island's first transparent surface.** A corner cell has two sheets;
alpha blending would flicker between them as the island turns. The sheet uses dithered transparency (a screen-space
pattern, drawn as opaque), sits just outside the water slab (no z-fighting) and lays its streaks out in world height
(no stretching on tall columns).

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 one rule | accepted (both) | + tests: `settled` is idempotent and never changes a land cell; `has_view` is the only scoring path that reads heights |
| D2 levels | accepted with checks (skeptic) | `test_perfect` checks one direction only: for levels 37 and 99 the solver must reach `perfect` exactly with the settled maps; `test_rules`' golden boards are rebuilt through `parse_map` — the result is recorded below |
| D3 garden edits | changed (both) | raise on water lifts the pond when its rim allows, else "nope" + a true toast; lowering a water cell drops the whole pond (as before, documented); raising an empty cell next to a pond can drain it — a case of the test; every moved cell gets `_after_terrain`; the first time an edit moves water a one-time toast "Water runs down to its lowest bank". Rejected (me): a staggered ripple of the sinking — all moved cells animate together, as one edit |
| D4 undo | changed (skeptic) | snapshot heights and water before a terrain edit, store the difference as `extra` in the same entry `{c, s, extra}`; undo restores those cells' terrain without settling again, rebuilds them and their items' heights |
| D5 saved gardens | changed (both) | settled before the columns are built, not marked dirty (the file changes only on the next ordinary save); a one-time toast "Your pond found its level" only if the load moved something. Rejected (me): an animated settling on load — the toast says what happened, an animation of a garden that was never shown settled is a second surprise |
| D6 waterfalls | changed (both) | slow, low-contrast streaks, the brightest part at the lip; dithered alpha; at 0.52 from the cell center (outside the 1.0 slab); streaks in world Y; the sheet narrows and fades out to the column's bottom; winter — an opaque short ice sheet (≤ 0.9 below the lip) ending in icicles; neighbors rebuilt only when their land appears or disappears, without animation; the season wave rebuilds them through `build_cell` |
| D7 checks | changed (both) | + solver = perfect for 37 / 99, + golden result, + item heights after every random edit, + undo of 2,000 edits back to the start exactly, + a saved garden with a raised pond loads settled and its file is unchanged until a save, + the load toast only when something moved, + screenshots of a corner cell at 4 yaws, an inner-hole waterfall, winter |

## Stage 15 results

**Done.**
- `scripts/terrain.gd`: `settled(land, water)` (one level per pond — the lowest of its cells and its land rim, never
  below 1; idempotent, never moves land), `pond_cells`, `settle()` (returns the moved cells), `raise_pond` (the whole
  pond up by one when the rim allows, else the low rim cells), `open_sides`. `parse_map` and `generate` settle; land that
  appears or disappears rebuilds the water cells next to it (their waterfalls change).
- Waterfalls (`_waterfall`), in clay like the rest of the island: the water rolls over the lip as a soft bead, runs down
  as one smooth flattened taper with two soft beads along it, and ends in a drop whose lowest point is exactly the
  column's bottom; opaque, the ponds' gloss and colors (`shaders/waterfall.gdshader`: slow, faint highlights drifting
  down in world height). Winter: a short sheet of ice ending in icicles. Taps still go to the column.
- `scripts/main.gd`: every garden terrain edit settles and lifts the items of every moved cell (`_settle_terrain`); raise
  on water goes through `raise_pond` (refused with a true toast otherwise); undo entries keep the other changed cells
  (`extra`) and restore them without settling again; a loaded garden is settled before it is built, not marked dirty,
  and says "Your pond found its level" once if something moved. Three toasts in both languages.

**Found along the way.**
- The first waterfall — a flat dithered sheet — was rejected by the owner on sight: "they look bad and unnatural". The
  sheet read as a flat overlay with a grainy edge, not as clay. Rebuilt from clay pieces (a bead, a taper, beads, drops),
  opaque; the dithering is gone, and with it the sorting question.
- `test_rules`' golden boards pass with settled maps: no golden layout depended on a raised pond.
- No generated garden has a waterfall: the generator always puts its pond inside the island. They appear on 50 levels
  (108 open sides, many on corner cells) and in gardens where the player brings water to the edge.

**Checks.** `test_water` — 146 checks, 0 failures: the rule (a raised pond, idempotence, land never moves, an open side
doesn't lower a pond), all 100 levels as parsed and as loaded, 200 generated gardens, the solver reaches exactly 42 and
281 on levels 37 and 99, the D3 cases (raise refused / raised with the rim at 3, a rim lowered twice drains the pond and
two undos bring it and the rim back, water on a high cell digs down to its bank and undo restores it, an edge pond gets
a waterfall, new land beside it drains it and removes the fall, undo restores both), 2,000 random edits — the rule
holds, every edit undoes exactly and redoes the same, items follow their cells, one waterfall per open side, each
ending at its column's bottom; winter falls frozen; an old saved garden with a raised pond loads settled, says so once,
its file untouched until a save, and says nothing on the next load. The other suites green (`test_rules` 32,509,
`test_touch` 5,346, `test_i18n` 20,184 …), `test_perfect` — 100 levels. Screenshots: level 2's corner pond at 4 yaws,
level 30 on the phone, level 84 in winter, the README and store sets retaken.
