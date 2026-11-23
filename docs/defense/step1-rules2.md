# Stage 1. Rules 2.0: defense of the technical decisions

Context: Clay Garden is a cozy Godot game. The player arranges items on an island, and the goal is "coziness":
every item gives 1 point plus points for neighbors on its 4 sides (`scripts/scoring.gd`, the dictionary
`RULES[who][neighbor] = points`). There are 10 levels now. The plan is 100 levels in 4 seasons of 25. As difficulty
grows, new rule types appear: radius 2 (the beehive likes flowers within 2 cells), a pattern (hammock +5 between two
trees), a chain (a straight fence of 3+ segments), a cap (the haystack counts no more than 2 neighbors), a condition
(drought: flowers without water within 2 cells give 0), terrain (snowdrift, ice), a seasonal modifier (in autumn
pumpkins get tree +1 instead of −1). Stage 1 rebuilds the scoring engine so all of this can be expressed. There are no
player-visible changes at this stage.

Current code: `scoring.gd` — `item_points`, `total`, `preview` (gain and marks for the 4 neighbors), `describe`
(card text), `solve` (simulated annealing for star thresholds). Callers: `main.gd` (6 places), `ui.gd` (describe),
`solve.gd`.

## Decisions

**D1. Rules as data.** `RULES[id]` becomes a list of rules of different types:
`{"t":"adj","of":"bush","v":2}`, `{"t":"water","v":2}`, `{"t":"view","v":2}`, `{"t":"near","of":"flowers","r":2,"v":1}`,
`{"t":"between","of":["tree","pine"],"v":5}`, `{"t":"line","min":3,"v":3}`, `{"t":"cap","max":2,"over":-1}`,
`{"t":"needs","what":"water","r":2}`. One interpreter computes an item's points from its list.
The alternative — a code function per special item (`if id == "hammock": ...`) — is rejected: such rules can't be
shown on a card, can't change by season, and the solver and hints would drift apart.

**D2. Board state is one `Board` object** (items, heights, water, snow/ice, season) instead of the triple of
arguments `(items, land, water)` in every function. Otherwise every new terrain mechanic changes the signatures of
all functions and all calls.

**D3. The season is a scoring parameter.** `SEASON_MODS[season][id]` — rules that replace or add to the base ones.
A level stores its season; in the free garden the season is the current one.

**D4. A hint = the difference of two counts.** `preview(id, c)`: count all items' points without the new one and
with it; the gain = the difference of the sums, the marks = which items' points changed (not only the 4 neighbors).
Today the hint repeats the adjacency logic separately — with radii and patterns it would lie. The cost: two full
counts per mouse hover (≤ 32 items — microseconds).

**D5. The rules card is generated from data** (`describe`), including special types and seasonal modifiers
("in autumn: tree +1 instead of −1"). A new rule without card text is impossible.

**D6. Implement all 8 rule types at once**, even though stage 1 levels use only 3 (adjacency, water, view).
For: the types are already described in the plan; the interpreter is small; unit tests on synthetic boards catch
errors before levels exist. Against: YAGNI, the rules may change after a playtest.

**D7. Regression.** Before the rebuild, capture "golden" values: for each of the 10 levels, 200 random arrangements
+ the solver's arrangement → totals with the old code. After the rebuild — the same totals, or the stage is not
done. Plus a test script `scripts/test_rules.gd` (headless) with unit tests for each rule type.

**D8. The solver stays** (annealing with full recounts), only moved to `Board`. If it gets slow — compute the gain
only over the affected cells; measure first.

## Defense result

Critics: #1 "Player and game designer", #2 "Skeptic: producer and engineer". Both accepted D1, D2 and D8. Both
required changes to D4 and D6; D3 and D7 got amendments.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 rules as data | accepted with an amendment (#2) | on load the rules are validated (an unknown type or item is an error) and compiled into a fast form: a neighbor dictionary, a water number, etc. The interpreter doesn't compare strings inside the annealing |
| D2 Board | accepted (#2: data only) | `board.gd` — four fields, no methods |
| D3 season | changed | `Board` has only a `season` field. `SEASON_MODS` arrive with the first autumn level. In the free garden the player chooses the season, not the calendar (#1): otherwise the score changes by itself. Recorded for stage 7 |
| D4 hint | changed | the gain = the difference of counts, but the marks keep today's meaning: the source cell shows what the new item gets from it, plus what the item on it gets from the new one. Water gets a mark too. For adjacency rules the hint stays byte-for-byte the same — the reference checks this |
| D5 card | changed | a human template phrase for each rule type. The card text of the 11 current items matches the old one to the character. Test: every rule has a phrase |
| D6 all 8 types | changed | implement the 3 types in use (adjacency, water, view) and 2 architecture "scouts": `near` (radius) and `between` (pattern). `line`, `cap`, `needs` and seasonal modifiers — when a level needs them, and after a paper playtest (#1: an invisible penalty feels like a punishment) |
| D7 regression | extended | references from the old code: totals and each item's points in 2,010 arrangements, 590 hints (gain and marks), the texts of 11 cards, the solver with seed 99 (the same result) |
| D8 solver | accepted with a criterion | budget: the reference solver ≤ 1.5 × 497 ms, the whole `solve.gd` ≤ 1.5 × 71.5 s |

The honesty rule (#1) is adopted for all stages: any change in points from hovering is visible as a mark on the
source cell, and every rule has a clear phrase on the card. A rule type that doesn't pass this check doesn't get into
the game.

Stage 1 acceptance criteria: all references match, the `near` and `between` unit tests pass, the time budget is
met; in the game, levels 4, 6 and 7 support hovering, placing, returning to the hand and autosolve.

## Stage 1 result (done)

- `scripts/board.gd` — the board as data. `scripts/scoring.gd` — rules as data of five types
  (`adj`, `water`, `view`, `near`, `between`), validation and compilation on load, a hint = the difference of counts
  with marks on source cells, template phrases for the card.
- `tests/test_rules.gd`: 28,381 checks, 0 failures. The totals and each item's points in 2,010 arrangements match,
  as do 590 hints (gain and marks), the texts of 11 cards and the solver with seed 99. The `near` and `between` unit
  tests and the data checks (catching 3 of 3 planted errors) pass.
- Speed: the reference solver 651–661 ms (old 497, budget 745); the whole `solve.gd` 93 s (old 71.5, budget 107).
  The star thresholds of all 10 levels are the same.
- In the game: autosolve on levels 4, 6, 7 — ★★★ with the same scores (48, 46, 56); the hover hint and the card are
  unchanged; returning an item to the hand with the right button (a new debug flag `--rclick`) — coziness 48 → 43,
  the bench is back in the hand.
