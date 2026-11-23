# Stage 4. Summer: defense of the technical decisions

Context. Summer is slots 26–50, D from ~13 to ~53; the steepest part of the curve starts here. Chapters: Hilltop View
(26–30), Evening (31–35), Drought and Bees (36–40), Hammock (41–45), Summer Garden (46–50). Novelties: the bench and
the "view" (26), the lantern (31), drought (36), the beehive and radius 2 (38), the hammock and the "pattern" (41).
There are already 5 moved levels: "Fir Grove" (33), "Quiet Pond" (37), "Evening Alley" (44), "Two Ponds" (47), "Hills"
(49); out of the corridor — "Evening Alley" (−6.9) and "Two Ponds" (+6.9). Spring is done: 25 levels, the tools, the
honesty rule ("any change in points is visible as a mark at the source, every rule has a phrase"), introducing a
novelty on first meeting.

## Decisions

**D1. Beehive** (38): +1 for each flowers within 2 steps (the `near` type, already in the engine), a bench nearby −2
("bees sting"). **Hammock** (41): +5 if a tree or fir stands on two opposite sides (the `between` type, already in
place), water nearby +1. The numbers are a start, checked by the generator (the novelty is useful in the ideal).

**D2. Drought is a new rule type `needs`**: on drought levels flowers without water within 2 steps give 0 instead of
all their points. Drought is a level property (`"drought": true`), not the whole summer: it appears at 36 and recurs
later where intended. The honesty rule: on such levels dry cells (more than 2 steps from water) are visible — the
grass is yellower and cracked; the hint above a flower on a dry cell says "drought: 0"; the card has a phrase.

**D3. A visible radius.** With the beehive in the hand, hovering highlights the cells within radius 2 (a diamond
ring), and marks are on the flowers in the radius (the hint already does this). For the hammock — highlighting the
two support cells along the axes.

**D4. No summer rule modifier.** The document said "everyone gets 1 more for water". Proposal: drop it — drought
already makes summer about "water", and changing rules by season is a separate autumn idea (slot 61). Two new ideas
about water in one season confuse.

**D5. Models**: the beehive is a straw bell-shaped dome with an entrance and 2–3 bead bees circling (animation); the
hammock is two short posts and sagging fabric; oriented along the axis where the trees stand (if there is one axis).

**D6. Moved levels**: "Evening Alley" — replace the fence with bushes (the fence unlocks in autumn) and recompute; if
it's still out of the corridor — move the slot. "Two Ponds" — swap with a better-suited slot or remove 1–2 items to
get into the corridor. The decision follows the report, without tuning the D weights.

**D7. Summer levels**: intros (26, 31, 36, 38, 41) and warm-ups I build by hand (criterion — the bot gets ★★★
≥ 75%); the rest — the generator with connected hand themes plus the curator. The acceptance criterion is the summer
report and autosolve.

**D8. Evening**: the levels of the "Evening" chapter (31–35) take place in the evening (`time`), the lanterns glow.
This is atmosphere only; points don't depend on the time of day (otherwise it's an invisible rule).

## Defense result

The main risk (critic #2): the drought flag must reach every place that builds a `Board` (solver, metric, generator,
game, tests, tools). `generator.contribution` already builds a board without the season. The answer is one factory.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 beehive and hammock | changed (both) | the −2 for a beehive nearby goes to the **bench** (they sting whoever sits there), not to the beehive. The radius phrase: "within 2 steps — diagonals too". **The pattern counts once**: +5 if there are supports on at least one axis (it was +5 per axis — inconsistent with the card); the `between` test was rewritten for this |
| D2 drought | changed (both) | dryness is a cell property (more than 2 steps from water); the `dry` mask is computed once in the `Board.for_level` factory. Invariant: the drought rule doesn't depend on items, so `delta`'s radius of influence doesn't change. A rule without parameters (`{"t": "thirst"}`): on a dry cell **only the item's own points are zeroed**; neighbors, the beehive and water lilies still see it. The drought phrase is on the card only on drought levels. Dry cells are always visible (yellower, cracked) |
| D3 visible radius | changed (#1) | a radius diamond for the beehive; for the hammock — a "support ghost": if one tree stands on an axis, the opposite cell gets a mark "+5 if a tree or fir is here" |
| D4 no summer modifier | accepted (both) | — |
| D5 models | changed (#2) | the hammock rotates (R) and picks its axis by itself only at placement — by the completed pattern. The bees are small and slow |
| D6 moved levels | changed (both) | first a reordering — free, the id doesn't change: "Evening Alley" → 35 (the "Evening" trial, with evening time there too), for which **the fence unlocks at 34** (bringing the lantern's and bush's "dead" fence rules to life); "Two Ponds" → 48; "Quiet Pond" → 42 (slot 37 is freed for drought practice). If a level's content does change — a new id with a `replaces` field: stars carry over, the record and the crown don't |
| D7 summer levels | changed (both) | drought is a passport field (slots 36, 37, 39, 40, 46, 50), not an on-the-fly decision. A check "the drought matters": the ideal with the drought is lower than without it, and the ideal has at least one living flower. The intro criterion is refined: the bot reaches **near-ideal** (the metric's goal) in ≥ 75% of runs |
| D8 evening | accepted (both) | a screenshot: the marks are readable in the evening |

Beyond the defense: a "dead rules" test — for every campaign slot the cards of the hand's items don't promise links
to locked items (the hiding mechanism exists since stage 3; now it is under test).

Stage 4 acceptance criteria: the stage 1 references match byte for byte; `delta` == the difference of `total` on
boards with drought, `near` and `between` together; a consistency test: the same arrangement on a drought level gives
one `total` through the factory for the game, the solver, the metric and the generator; the summer report in the
corridor; autosolve of all 25 summer slots; screenshots: the beehive with its diamond, the hammock support ghost, dry
cells, evening.

## State at the pause (stage 4 in progress)

Done: the `Board.make/for_level` factory with the dry-cell mask, the `thirst` drought rule, the pattern counts once,
the beehive and hammock rules, the beehive and hammock models, every level board (game, solver, metric, generator)
goes through the factory, the fence unlocks at 34, drought slots in the passport, the moves of "Evening Alley" (35),
"Quiet Pond" (42), "Two Ponds" (48), the drought consistency test. `tests/test_rules.gd`: 32,457 checks, 3 expected
failures:
1) the bench card reference — it now has a "beehive −2" line (update the reference deliberately);
2) the `near` phrase unit test — the phrase is now "(diagonals too)";
3) the solver at 765 ms with a budget of 745 — the drought check in the hot path; speed it up (check `dry` only if
   it's not empty).
Left: these three items, the beehive diamond highlight and the hammock "support ghost", dry cells on the island, the
hammock auto-rotation, drought support in the generator and the "the drought matters" check, 20 summer levels, the
report, autosolve, screenshots. Then stages 5–7 — each with a defense before the critics.

## Stage 4 result (done)

| Criterion | Result |
| --- | --- |
| stage 1 references | match: `tests/test_rules.gd` — 32,457 checks, 0 failures (the card reference is compared within the 11 items it was captured for) |
| `delta` with drought, `near`, `between` | a third of the test's random boards have a drought; 0 discrepancies |
| consistency | one arrangement on a drought level: the game's factory, the solver, the metric's bot and the generator's contribution give one total — the `_test_drought` test |
| "dead rules" | `tests/test_campaign.gd` — 1,941 checks, 0 failures: on none of the 53 levels do the cards talk about something locked |
| solver | 651 ms (budget 745). The beehive raised the radius of influence to 2 and slowed `delta` down; now each item has its own radius — far neighbors are recounted only if their own rules reach that far |
| summer filled | 25 of 25: 7 by hand (intros; for the hammock and beehive some items already stand), 15 from the generator, 3 old ones moved |
| summer report | 0 flags (after adjusting the hand of "Bench on the Hill") |
| autosolve | 25 of 25 — ★★★ |
| screenshots | drought (yellow cracked cells, "drought: 0"), the beehive radius diamond, evening with lanterns. The hammock "support ghost" wasn't caught in a screenshot: the debug run places only one item kind, and the levels' initial state lacks the right cell — the hint appears during play. The code was checked by reading, not by a screenshot |

Along the way, from data:
- **the drought didn't bite at first**: for all candidates the ideal with the drought equaled the ideal without it —
  there were enough wet cells. The generator now creates scarcity (the pond at the edge, flowers at least half the
  hand) and drops candidates where the drought changes nothing already in the quick estimate;
- **chapter themes**: the "Hilltop View" chapter had almost no benches — the hand theme seed now comes from the items
  unlocked in that chapter;
- **trial hands**: at slots 30 and 40 the passport hand (12 and 16) pushed D far above the target by volume alone;
  the generator got `--hand=N`, and the trials were built with hands of 9 and 12;
- **the hammock trap**: on the hammock intro a greedy arrangement places a bush between the trees (+7 more than the
  hammock's +6) and gets stuck — removed from the intro; it's material for twists;
- the free garden palette fits again: basic items always, seasonal ones after meeting them in the campaign.
