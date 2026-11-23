# Stage 6. Winter: defense of the technical decisions

Context. Winter is slots 76–100, the curve's plateau (after the stage 5 addendum: D ≈ 69 → 72, corridor ±3, the
indicator "the bot gets the interface ★★★" ≥ 10% is mandatory, the winter hand ≤ 20 — already accepted). Chapters:
Ice and Snow (76–80), Campfire (81–85), Bird Feeder (86–90), Winter Garden (91–95), All Year Round (96–100).
Novelties: the snowman and ice (76), snowdrifts and warmth (79), the campfire (81), the feeder (86), All Year Round
(96). In winter there are no flowers, water lilies, mushrooms or pumpkins (until 96). Already done and defended: rules
are tied to the board (a set for the slot's flags), conditional rules `when`/`unless`, campaign flags by slot,
introducing mechanics, the "ideal in data = engine" test, the honesty rule. The autumn hand is capped at 16.

## Decisions

**D1. Ice** (from 76, an `ice` flag on all winter slots): the water is frozen — "water nearby" rules don't apply (an
`unless: ice` condition), and only the snowman can stand on ice (a skating rink). Ice is visible: bluish-white cells.

**D2. Snowdrifts and warmth** (from 79): some of a level's cells are snowdrifts (a map property, the `*` symbol). A new
rule type `cold`: an item on a snowdrift gives 0 if there is no heat source (a lantern or campfire) within 2 steps.
Warmth depends on items — so everyone who freezes has a far rule about the lantern and the campfire (radius 2);
`delta` already handles this (a far neighbor is recounted only when a heat source is placed). Hint: "cold: 0" above an
item on a cold snowdrift, a warmth diamond when hovering a lantern or campfire.

**D3. Snowman** (76): on a snowdrift or ice +2; a fir nearby +1; warmth within 2 steps −3 (it melts). **Campfire**
(81): warms (a heat source); a bench nearby +2 (the bench's rule); trees and firs next to the campfire −2 (sparks —
the campfire's rule). **Feeder** (86): fir +2, tree +1, a birdhouse nearby +1, a campfire nearby −2.

**D4. One winter modifier**: the trees are bare, so two trees next to each other no longer bother each other
(`unless: winter` on the rule "tree −1 for a tree"). The document also had "fir +1" — I'm dropping it: one change per
season, like falling leaves.

**D5. All Year Round** (96–100): one arrangement is scored by the rules of all four seasons, coziness = the sum. A
seasonal item out of its season "sleeps" (0 points of its own, but neighbors see it). The hint shows 4 numbers
(spring/summer/autumn/winter). Implementation — four boards with different flags over one arrangement; the solver and
the bot work with the sum.

**D6. The winter hand is 14–20** — already accepted in the stage 5 addendum. On the plateau levels differ not by D
(it's almost constant) but by the novelty of the layout: every winter chapter brings a novelty (76 ice and the
snowman, 79 snowdrifts, 81 the campfire, 86 the feeder, 96 All Year Round), and on late slots the generator combines
mechanics and fixed obstacles.

**D7. The winter palette**: snow caps on the top faces (white grass), bare trees, snow on firs, ice instead of water;
snowflakes last. Not used in the free garden yet (that's stage 7).

**D8. Winter levels** — like autumn: intros by hand (with items already standing for radii), the rest — the generator
and the curator; the report and autosolve are the acceptance criterion. The generator gets snowdrifts (`*`) on some
cells from slot 79.

## Defense result

Main finding #2: the **"where an item can go"** rules are coded as "on water or on land" in about ten places (the
solver writes `"lily"` directly twice, the metric, the generator, the game). The snowman "on land and on ice" is a
third variant: forget one place and the solver won't place it, the ideal and the thresholds will lie. The cure is one
function. Main finding #1: ice in its current form only **takes away** 75 levels' worth of the intuition "start from
the water".

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 ice | changed (both) | one winter flag `winter` (ice follows from it, no separate `ice`); "water nearby" rules are switched off **in one place** — when the rule set for winter is assembled, not with `unless` on each. In return familiar items get a link to ice: stones and the bench get ice nearby +1 ("a rink"), the card notes "water: ice in winter". One "Winter is here" banner at 76. **`Board.cells_for(id)` is the single placement rule** for the game, solver, bot and generator + a consistency test |
| D2 snowdrifts and warmth | changed (both) | snowdrifts are a level's **list of cells** `"snow": [[x, z], …]` (not a map symbol: it would eat the height); a mask in `Board.make`. `cold`: an item on a snowdrift gives 0 of its own points if there is no lantern or campfire within 2 steps (the lantern/campfire warm themselves; the snowman doesn't freeze; neighbors see a cold item — as with drought). The check happens before the fast path; freezing items have a far rule "about the lantern and campfire". A `delta` test swapping a heat source and a frozen item at distance 2. A warmth diamond on hover, "cold: 0" before placing, warmth in the lantern and campfire cards. A generator check: snowdrifts matter (without warmth the ideal is lower), and a heat source is in the hand |
| D3 items | changed (both) | the snowman's "on a snowdrift or ice +2" is a declared type `on` (a bonus for the terrain under the item) with data validation and a phrase. The campfire isn't an outcast: sparks on firs are removed; the campfire gets a bench nearby +2 and a snowman within 2 steps −3 (it melts — the snowman's rule). The feeder is unchanged |
| D4 modifier | accepted | one: the trees are bare — two trees next to each other don't bother each other (`unless: winter`) |
| D5 All Year Round | changed (both) | simplified: 4 boards over **one shared dictionary** of items (a move changes all at once; total and delta are sums); only explicit seasonal differences count — water/ice, falling leaves, bare trees (no drought or cold); one sum above the cell, 4 numbers on the card; a season switch (1–4) redraws the island. Slot 100 is a celebration finale, the hardest is 99. The generation budget is recorded |
| D6 hand and novelties | accepted | — |
| D7 palette | changed (#1) | a snowdrift is a mound (a shape, not just a color), ice is glossy blue; marks on white — checked with a screenshot |
| D8 levels | changed (both) | generator checks as for drought: snowdrifts matter; a level with snowdrifts has a heat source |

Stage 6 acceptance criteria: `cells_for` and its test; `delta` == the difference of totals with `cold`; "ideal in data
= engine" on winter and All Year Round; the spring–autumn references didn't shift; the winter report; autosolve;
screenshots of snowdrifts, the warmth diamond, ice.

## Stage 6 results

**Done.** Core: `Board.placeable/can_place` — the single placement rule (game, solver, bot, generator); winter is one
flag `winter` (water → ice in one place of rule assembly, stones and the bench get ice +1, trees are bare); snowdrifts
are a list of cells `snow`, `cold` and warmth (lantern, campfire, radius 2), the `on` type (the snowman on a snowdrift
or ice); All Year Round — 4 seasonal boards over one items dictionary, total/delta are sums, seasonal items "sleep".
Models of the snowman, the campfire (flickering light), the feeder, bare trees, snow on firs; ice, mound snowdrifts,
winter grass. The "Winter is here" and "Snowdrifts" banners, "cold: 0", the warmth diamond, cards with warmth and "can
stand on ice". All Year Round has a row "Spring N · Summer N · Autumn N · Winter N" (a press or Tab shows the island in
that season).

**Levels.** 25 winter slots: 7 by hand (intros 76, 79, 81, 86, warm-up 91, All Year Round 96, the celebration finale
100) and 18 from the generator with the curator (`data/drafts/winter_hand.json`, `winter_gen.json`). The campaign is
**100 of 100**. Report: 0 levels failed the checks; all generated winter slots are in the ±3 corridor (deviation
≤ 2.7); "the bot gets the interface ★★★" ≥ 0.17 everywhere (threshold 0.1); the hardest in All Year Round is 99 (D
74.6), slot 100 is a celebration (the FINALE flag, defended). Autosolve: the solver places every winter hand
(screenshots `shots/w91.png`, `shots/year100_*.png`).

**Found and fixed at acceptance.**
- The generator set a candidate's slot number **at the very end** — the solver and the metric evaluated candidates
  without campaign flags (no ice, bare trees, All Year Round; in autumn — no row or falling leaves). The final data
  didn't suffer (add_levels and the report recompute with the slot), but the winter selection was blind: regenerated.
- The metric counted "water" as a mechanic in winter, when water is ice; fixed (a mechanic only if the rule applies).
- The beehive and the hammock got into winter hands — removed (`WINTER_GONE`), just as they "sleep" in winter in All
  Year Round.
- Trials with a hand of 20 (80, 85) and the twist at 83 came out above the corridor — the hand was reduced
  (`--hand=17/15`), as in autumn.
- The ideal of slot 98 in the data was understated by 1 (the "ideal = engine" test) — fixed.
- The long "Winter is here" banner went under the corner panel — banners now wrap by words.

**Known.** In winter the snowman (17 of 25), the bench and the campfire (16), the lantern (14) are frequent — the
same skew as the bench in summer; on the plateau D is almost constant, so in chapters 16, 18, 19 the trial is slightly
easier than the puzzle by D (within the ±3 noise). The D weights are still not calibrated by real winter playthroughs.
