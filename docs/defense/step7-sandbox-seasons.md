# Stage 7. Seasons in the free garden: defense of the technical decisions

Context. The 100-slot campaign is ready season by season (spring, summer, autumn, winter, All Year Round). The free
garden is currently always summer and has no coziness score: seasonal items appear in the palette after meeting them
in the campaign but look like summer, and the seasonal rules (falling leaves, ice, bare trees) aren't visible there.
From the concept: "in the free garden the season is the world's look, not a goal; there is one garden, the season
re-dresses it". Already done and defended: rules are tied to the board (season flags), a `Board` with a season and
flags, All Year Round as 4 boards over one arrangement, a row of buttons "Spring N · Summer N · Autumn N · Winter N"
on levels 96–100 (a press shows the island in that season, Tab — the next one), models of the snowman, campfire,
feeder, bare trees, snow on firs, ice; `terrain.build_cell(c, animate)` rebuilds one cell.

## Decisions

**D1. The player chooses the season, not the calendar.** A "Season: Summer" button in the corner panel (cycles) and
the Y key. The garden's season is saved in `garden.json` (a `season` field, version 2; old saves open in summer).

**D2. A smooth change — a wave from the center.** A change in ~2 s: cells and items are rebuilt in the new season one
after another from the island's center to its edges (delay ∝ distance), each with a clay "squash", as on placement.
No shader color blending: a rebuild wave is cheaper and reads as "the garden is changing clothes".

**D3. The "Wheel of the Year"** — a toggle in the corner panel: the season changes by itself every 3 game days (at
dawn); with time speed-up (T) a year passes in a couple of minutes. Off by default, saved in `garden.json`.

**D4. Seasonal items out of season change shape rather than disappear.** Only where the summer shape looks wrong: a
snowman outside winter — a puddle with a carrot, coals and a bucket; in winter — the beehive under a snow cap, the
hammock rolled up on its posts, the water lily frozen into the ice (matte), flowers — dry stems, pumpkins and
mushrooms — under snow caps. The rest (scarecrow, haystack, campfire, feeder, birdhouse, snowdrop, fence, bench,
lantern, stone, bush) suit any season. The player's arrangement never changes — only the look.

**D5. Coziness in the free garden is an optional counter**, a "Coziness" button in the corner panel. It shows the
same row as All Year Round: "Spring N · Summer N · Autumn N · Winter N", the selected season pressed, a press changes
the season. It counts by the season's rules (ice and bare trees in winter, falling leaves in autumn, the fence row —
always); no drought or snowdrifts (those are level properties). The hover hint above a cell follows the current
season's rules. Items don't sleep: in the free garden the season is a look, not a "sleeps" rule.

**D6. Seasonal wildlife and particles** — one particle system per island with per-season settings: spring — petals,
summer — as now (butterflies, bees at the beehive, fireflies at night), autumn — falling leaves, winter — snowflakes
and smoke over the campfire; butterflies don't fly in winter. Few particles, so as not to get in the way of sculpting.

**D7. Sculpting in winter without new tools.** The "water" tool places ice in winter (it's the same water — just the
look); there is no "snowdrift" tool: snowdrifts stay a level property. The palette — as now: basic items always,
seasonal ones after meeting them in the campaign (locked ones are not shown: a stage 3 decision).

**D8. Acceptance checks.** A test: every item is built in every season without errors (including "out of season");
the free garden score by season equals a `Board` with that season's flags; `garden.json` v2 is saved and read (on a
temporary path, without touching the player's garden), v1 is read as summer. Screenshots of the same garden in four
seasons and of the snowman and beehive "out of season". The references and the campaign don't shift (test_rules,
test_campaign, test_perfect).

## Defense result

Main finding #2 (the skeptic): a wave assembled from deferred `_clear_items`/`_place_item` calls makes the garden's
**data** incomplete for 2 s — autosave (0.8 s), closing the window, the score and the hint would see half a garden; a
repeated change would give double nodes, and `_place_item` would play 40 "plops". The cure: the wave changes only the
**look** (the node inside a record), the data is unchanged, there is one controller. Main finding #1 (the player): a
coziness counter easily turns a "garden for the soul" into an exam, and dry stems turn a winter flowerbed into a
graveyard.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 the player chooses the season | changed (both) | spring and summer — always, autumn — after slot 51, winter — after 76 (we don't spoil ice and bare trees); `terrain.season` is set on load **before** `build_all` and the first item — a saved winter opens straight in winter, without a wave; the sandbox's `_season()` is the garden's season |
| D2 wave | changed (both) | one controlling wave in `_process`: rebuilds the look of cells and items with distance < r(t); the `items[c]` record stays, only `node`/`sway` change; no sounds; a repeated change instantly finishes the current wave and starts a new one; input isn't blocked, a placement during the wave is right away in the new season |
| D3 "Wheel of the Year" | **rejected** (skeptic) / changed (player) | not done: an automatic change starts a wave in the middle of sculpting and moves the numbers by itself; bring it back if asked |
| D4 out-of-season shapes | changed (both) | flowers in winter **sleep under the snow** (caps) rather than dry out; the snowman's puddle is small, with a carrot and a bucket, unlike a water cell; the hammock is rolled up; the water lily is frozen in; caps are one function `_snow_cap`. The `leaf_fall` parameter of `Items.build` **stays**: slots 51–60 are autumn without falling leaves; in the sandbox it = "autumn" |
| D5 coziness counter | changed (both) | **off** by default; one number "Coziness · Winter N" (not the All Year Round row: items sleep there and not here — different things should look different); no thresholds, records or crowns; marks above a cell — only with the counter on; flags — **by progress** (the row after 54, falling leaves after 61, winter after 76), otherwise the rule is invisible; the factory `Board.for_sandbox(…)`; placement uses the summer terrain (no snowman on ice), so a season change removes nothing |
| D6 particles | changed (both) | no new system: butterflies don't fly in winter, fireflies — in summer; snowflakes and petals last, outside cell selection |
| D7 sculpting in winter | accepted | — |
| D8 checks | changed (both) | added: 10 quick changes — the node count after the wave equals the original, `items` unchanged; a save mid-wave writes the whole garden and the target season; loading v2 "winter" — winter right away; sandbox flags by progress; a screenshot "the winter flowerbed isn't dead" |

Stage 7 acceptance criteria: the wave test (nodes, data, saving mid-wave); `garden.json` v2 round-trip on a temporary
path, v1 — summer; the sandbox score = `Board.for_sandbox`; the references and the campaign didn't shift; screenshots of
the garden in 4 seasons.

## Stage 7 results

**Done following the defense.**
- The player chooses the garden's season: a "Season: …" button in the corner panel and the Y key; spring and summer —
  always, autumn — after slot 51, winter — after 76 (`Campaign.sandbox_seasons`, `Progress.reached`); saved in
  `garden.json` v2, v1 opens in summer; the season is set before the island is built.
- The re-dressing wave: one controlling wave in `_process` (`_start_wave/_step_wave/_finish_wave/_redress`), changes
  only the item and cell nodes, the `items[c]` record is unchanged, no sounds; a repeated change finishes the current
  wave; the same wave is used for switching seasons in All Year Round.
- Out-of-season shapes (`items.gd`): a snowman outside winter — a puddle with a carrot, coals and a bucket; in winter
  the beehive under a cap (bees inside), the hammock rolled up, the water lily frozen and closed, flowers sleep under
  the snow as colored buds, pumpkins and mushrooms in snow caps; caps are one function `_snow_cap`.
- The coziness counter: a "Coziness: on/off" button, off by default; one number "Coziness · Winter N", no thresholds
  or records; marks above a cell in the garden — only with the counter on; the board `Board.for_sandbox` — flags by
  progress (the row from 54, falling leaves from 61, winter from 76), placement uses the summer terrain.
- In winter butterflies don't fly and there are no fireflies. The "Wheel of the Year", new particles, snowflakes — not
  done (defense).

**Checks.** `tests/test_sandbox.gd` — 258 checks, 0 failures: every item is built in every season (and the bee and
light nodes are in place); seasons and flags by progress; the snowman doesn't stand on ice in the garden; in winter
water doesn't count; 10 quick season changes — the node count after the wave equals the original, the garden data is
unchanged, every record has a live node; a save mid-wave writes the whole garden and the target season; a saved winter
opens in winter without a wave; v1 — summer; the garden board is `for_sandbox`. The player's garden is untouched (the
test's own save path). Screenshots: `shots/garden_{spring,summer,autumn,winter}.png`, `shots/year100_{summer,winter}.png`.
