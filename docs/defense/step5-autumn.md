# Stage 5. Autumn: defense of the technical decisions

Context. Autumn is slots 51–75, the steepest part of the curve (D ≈ 50 → 89). Chapters: Vegetable Patch (51–55),
Scarecrow (56–60), Falling Leaves (61–65), Haystack (66–70), Harvest (71–75). Novelties: pumpkins (51), a straight
fence — the "chain" (54), the scarecrow (56), falling leaves — the rules change (61), the haystack and the "cap" (66).
The fence is unlocked since summer (34). Already in place: "Vegetable Patch" (54, D 39.7 — far below the target 54.4),
"Tight Island" (57, the bot almost never reaches near-ideal), "Big Garden" (65).
The honesty rule applies: any change in points is visible at the source, every rule has a phrase, a card doesn't talk
about locked items. Drought showed the recipe: a level property (a flag) + the `Board.make` factory + a consistency
test.

## Decisions

**D1. Pumpkins** — unchanged (fence +2, pumpkins +1, tree −1).

**D2. The fence chain** — a new rule type `line`: every fence standing in a straight row of 3+ fences (along one
axis, consecutive) gets +1. A row of 3 gives +3 on top of normal adjacency, a row of 5 — +5. Hint: hovering a fence
shows a mark "row of N: +N" and highlights the row. Radius of influence: a long row changes the points of distant
fences, so `delta` for fences recounts the whole row (along the axis up to the first non-fence), not a diamond — this
is recorded as an invariant, and the "delta == the difference of totals" test runs on boards with long fences.

**D3. Scarecrow**: +1 for each pumpkin within 2 steps (the `near` type), while a birdhouse/feeder near the scarecrow
(within 2 steps) gets −2 ("birds are scared"). A radius diamond — like the beehive's.

**D4. Falling leaves — the rules change: a level flag `leaf_fall`** (from slot 61), not the whole season. The rules
have conditional entries: `{"t": "adj", "of": "tree", "v": -1, "unless": "leaf_fall"}` and `{"t": "adj", "of": "tree",
"v": 1, "when": "leaf_fall"}` for pumpkins ("the leaves cover them"), mushrooms get tree +3 instead of +2. The rules
are compiled separately for each set of flags (a cache), and the `Board.make` factory picks the set. The card shows
the rule in effect and a note "falling leaves: tree +1 instead of −1". On the island — fallen leaves around the trees.

**D5. The haystack and the cap** — the `cap` type: the haystack gets +2 for a pumpkin or fence neighbor, but counts no
more than two such neighbors; each further neighbor of any kind −1 ("crowded"). Hint: "haystack: counts 2 of 3".

**D6. The autumn palette** (a table, like spring): ochre grass, yellow-red tree crowns, falling leaves last.

**D7. Moved levels**: "Vegetable Patch" (D 39.7 at slot 54 with target 54.4) — move to slot 51/52 (pumpkins) or 53;
"Tight Island" (BOT flag) — keep it if a human can complete it: it has been in the player's progress with ★★ since
stage 2.

**D8. Autumn levels** — like summer: intros and warm-ups by hand (with items already standing, if the novelty is a
pattern or a radius), the rest — the generator and the curator; the report and autosolve are the acceptance
criterion.

## Defense result

Both critics' main finding: rules must not change **silently and retroactively**. An unconditional fence chain would
raise the ideal of summer levels with fences (the fence is unlocked since 34): an outdated `perfect`, false crowns, an
invisible rule. Second (#2): a global cache of compiled rules with switching flags is a bug waiting to happen.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 pumpkins | accepted | — |
| D2 chain | changed (both) | the rule is local: a fence is in a row of 3+ ⇔ there are 3 consecutive fences on its axis including it — 2 cells in each direction are enough; the fence's own radius is 2, no special case in `delta`. At a crossing of two rows — +1 once. **It applies from slot 54 (campaign flag `line`)**, not in summer; the intro is a banner "The fence learned something new", and the card line appears only where the rule applies. Test: swapping a fence and a non-fence in the middle of a row |
| D3 scarecrow | changed (both) | there is no "feeder" yet — that rule is removed. The direction is reversed: the scarecrow **gives** — every pumpkin within 2 steps of a scarecrow gets +1 (marks on the pumpkins); the birdhouse gets −2 from a scarecrow nearby (2 steps). The solver budget is re-measured |
| D4 falling leaves | changed (both) | the campaign flag `leaf_fall` is on **all** slots from 61 to 75 (autumn doesn't go back); one rule change: pumpkins get tree +1 instead of −1 (mushrooms are untouched). Compiled rules are **stored in the board** (`Board.make` puts in the set for its flags), and `_points` gets them as a parameter; an unknown flag in `when`/`unless` is a data error; a banner on first meeting; a consistency test |
| D5 haystack | changed (both) | only a cap: a pumpkin or fence nearby +2, but no more than twice (no "crowding" −1): an order-free formula, 2·min(k, 2) |
| D6 palette | changed (#1) | ochre grass; falling leaves and leaves under trees — **only on falling-leaves levels** (it's their sign); drought doesn't occur in autumn |
| D7 old levels | changed (both) | "Vegetable Patch" → slot 53, before the chain turns on (its ideal doesn't change) — a marked exception "an old level easier than the curve". Levels whose ideal the new rules change ("Tight Island" 57, "Big Garden" 65) get a new id with `replaces`: stars carry over, the record and the crown don't |
| D8 autumn levels | changed (#1) | the hand is no more than 16: difficulty comes from tightness and mechanics, not from the volume of clicks |

Beyond the defense: **introducing mechanics** (drought, chain, falling leaves) — a banner on first meeting, as with
items (the summer drought didn't have one — fixed here as well).

Acceptance criteria: a test "the ideal in data = the engine" over all levels (the solver finds no more than
recorded); the references and the spring and summer reports didn't shift; consistency of falling leaves and the
chain; unknown flags are caught; every rule has a phrase; the autumn report, autosolve of 25 slots, screenshots.

## During stage 5 (data and fixes)

- **An addendum about the curve** — a separate defense: `step5-addendum-curve.md` (ceiling 72, plateau corridor ±3,
  the indicator "the bot gets the interface ★★★" ≥ 10%, item frequency).
- **A metric bug found on autumn candidates**: the M (mechanics) and I (links) factors counted only the old rule
  types — the metric didn't see the chain, the cap, drought or falling leaves; and links were counted over all rules,
  including inactive conditional ones (the pumpkin had both "tree −1" and "tree +1"). Fixed: only the rules in effect
  at this slot are counted, plus all of the level's mechanics (per the M spec — "rules beyond plain adjacency"). This
  raises the D of summer drought levels by ≈ 3 — checked by the report.
- **Themes of chapters without a new item** ("Falling Leaves") were taken at random — hammocks and firs, where falling
  leaves play no part. Now the chapter's mechanic sets the theme seed (falling leaves — pumpkins and tree, the chain —
  the fence).
- "A Rest in the Woods" (45) was replaced by another candidate: after fixing its ideal (65 → 67, found by the "ideal =
  engine" check) its D moved +9.6. "Tight Island" and "Big Garden" are marked exceptions (old levels with player
  progress, hands above the autumn ceiling).
- An item's card also shows what it **gives** others at a distance: the scarecrow has no rules of its own, and its
  card was empty (the "every id has everything" test caught it).

## Stage 5 result (done)

| Criterion | Result |
| --- | --- |
| the ideal in data = the engine | `tests/test_perfect.gd`: 75 levels, 0 with an outdated ideal (the chain and falling leaves didn't raise the ideal of old levels; in summer the check found an understated ideal for "A Rest in the Woods" — fixed before autumn) |
| spring–autumn references | `tests/test_rules.gd` — 32,481 checks, 0 failures; the solver 646 ms (budget 745) |
| consistency | the chain and falling leaves: the game's factory, the solver and the generator's contribution give one total; `delta` == the difference of totals on boards with autumn flags and with a fence swap in the middle of a row; a typo in a flag is caught |
| data and cards | `tests/test_campaign.gd` — 2,940 checks, 0 failures (every item has everything, no "dead rules") |
| autumn filled | 25 of 25: 6 by hand (intros and a warm-up), 16 from the generator, 3 old ones (marked exceptions: "Vegetable Patch", "Tight Island", "Big Garden") |
| autumn report | after the swaps 63↔64 and 69↔70 all new slots are in the corridor (±3 on the plateau), the order within chapters holds; the interface ★★★ is reachable everywhere (the bot gets it ≥ 10%) |
| autosolve | 25 of 25 — ★★★ |
| screenshots | the autumn palette, the falling-leaves banner (shown first at slot 61), the pumpkin card "tree +1 (falling leaves)", the fence-row banner and hints |

Known and recorded: in summer the bench is in the hand on 15 of 25 slots, the lantern on 11 (the 40% limit was
introduced for autumn and winter; in summer the bench is the season's central item) — to check with real play. Fixed a
bug in the debug flag `--explain`: it also deleted the new hint marks.
