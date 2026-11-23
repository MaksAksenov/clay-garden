# Stage 2. Metric and generator: defense of the technical decisions

Context. The plan is 100 levels (4 seasons × 25) with difficulty along an S-curve: D(L) is a logistic curve
(midpoint 50, steepness 16), D from 0 to 100. A level's metric D (from the design document):
D = 100·(0.20·N + 0.15·K + 0.20·I + 0.25·G + 0.20·M), where N is the hand size, K the number of types, I the links
between the level's types (minuses ×2), G the "trap": the share of a "sensible player" bot's runs without ★★★ ×
min(1, n/10), M the number of mechanics. The bot places greedily (the best item–cell pair), then moves and swaps
items while coziness grows. Today all of this is a Python prototype in the drafts, outside the game. 90 new levels
are needed. They can't be assembled by hand, so stage 2 is tools: the metric, passports of the 100 slots, a
candidate generator, a report. There are no player-visible changes; the player will see the result in stages 3–6 —
the quality and evenness of the levels.

The engine after stage 1: rules as data (`scripts/scoring.gd`), a `Board`, an annealing solver with full recounts
(the reference run of 10 levels ~650 ms for 5,000 iterations), tests `tests/test_rules.gd`.

## Decisions

**D1. The bot and the metric are in GDScript, in the game, not in Python.** One source of rules: everything that is
counted is counted by the same code as in the game. The Python prototype is thrown away.

**D2. Incremental scoring.** `Scoring.delta(id, c, b)` recounts only the items within the radius of influence
(1 for adjacency and patterns, r for `near`; the radius is computed when the rules are compiled). The hint, the bot
and the solver use it (an annealing move = the difference of two deltas instead of a full recount). The expected
solver speed-up is ×5–10. Without it the generator won't fit in time: the bot makes tens of thousands of "what if
here" evaluations. Check: the stage 1 references (hints, the solver with a seed — a different trajectory is allowed,
but the same best result) + a random test "delta == the difference of totals" on 10,000 boards.

**D3. The passports of the 100 slots are computed, not written by hand.** `scripts/campaign.gd`: the curve D(L), the
unlock table (level → a new item or mechanic, as in the document), chapters, slot types within a chapter (intro −4,
practice −1, twist +1, puzzle +2, trial +4 relative to the curve), hand sizes by season. The passport of slot L =
season, chapter, type, target D, available items, a mandatory novelty.

**D4. The candidate generator** `tools/generate.gd` (headless) for one slot: the island silhouette from ~12
hand-drawn templates (rotation and mirroring) + height noise (hills — from summer, when the view exists) + ponds; the
hand — from the available items, with the mandatory novelty, sized by the passport. For each candidate: a quick
solver, the bot (P(★★★) from 20 runs), D. Filter: |D − target| ≤ 5; the novelty scores points in the best solution
(otherwise the level doesn't teach it); an "intro" has few best solutions. The best 5 → the full solver (star
thresholds) → a candidates file.

**D5. Manual finishing stays.** A human picks the slot's level from the 5 candidates (in these stages — me, checking
with an `--explain` screenshot): is the island pretty, does the idea read; a human writes the name and the hint. The
generator writes no texts.

**D6. Levels move into data.** `data/campaign.json` (100 levels: map, hand, fixed items, season, thresholds, ideal,
D, generation seed). `levels.gd` stays the API (`Levels.LEVELS`) but reads the file. The current 10 levels move to
their new slots (the table in the document).

**D7. A report** `tools/report.gd`: a table of all levels — target D, actual D, deviation, P(★★★), ideal,
thresholds; flags "out of corridor", "the novelty isn't needed for the ideal", "the level is harder than the next
chapter trial". Plus a CSV for a chart. The report is a season's acceptance criterion in stages 3–6.

**D8. Time budget:** generating one slot ≤ 60 s, the whole campaign ≤ 1.5 h in the background; a full recount of
thresholds and D for all 100 levels ≤ 10 min. A seed per slot — generation is reproducible.

## Defense result

Both critics accepted the direction. Both found the same real bug: progress is stored by level number, and after the
move the player's stars would stick to other levels. Both pointed out that G is noisy and computed from the wrong
thresholds.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 GDScript | accepted with a condition | the Python prototype is not deleted: it goes to `tools/prototype/`, and the D of ten levels is compared (difference ≤ 3) |
| D2 incremental | changed (#2) | expect ×1.5–3 for the solver, not ×5–10. The solver's trajectory with a seed must match **exactly**. A test "delta == the difference of totals" on synthetic `near`/`between` and with swaps of neighboring items |
| D3 passports | changed (#1) | the slot type is set by content, not by a D shift: intro — a novelty and a small hand; twist — a greedy arrangement doesn't get ★★★; puzzle — tight (≤ 1.4 cells per item) or fixed items; trial — the chapter's biggest hand. The table of 100 passports is reviewed before generation |
| D4 generator | changed (both) | the novelty must be useful: in the ideal arrangement its contribution (how much coziness is lost if it's removed) is no less than the average contribution of the other items. G is computed from the thresholds of the **full** solver, 60 bot runs, only for the 5 finalists of 40 candidates. The "few best solutions" criterion is dropped. The "aha" indicator (a greedy arrangement below ★★★) goes into the report |
| D5 finishing | changed | the candidates file has an ASCII map and the ideal; all can be rejected and regenerated. Live calibration of D (ρ ≥ 0.7 with felt difficulty) is possible only on human play: we add a local play log (time to ★★★, returns to hand), and the D weights are provisional until then and marked so in the report |
| D6 data | changed (both) | a level has a permanent `id`; progress is stored by `id`; the old `progress.json` is migrated; numbers from JSON are converted to int; a test "JSON → the same levels" |
| D7 report | changed | curator note columns ("idea", "aha"), monotony flags (the same island template or the same idea in a row), the 10 hand-made levels — in the report as calibration |
| D8 budget | changed (#2) | measure `delta` first, then set the budget. All randomness only from the passed `rng` |

Normalization of the D factors (it was only in the document, now in the code `metric.gd`): N = log2(n/4)/3,
K = (k−2)/10, I = (pluses + 2·minuses)/40, M = m/7, all clamped to 0…1; G = (1 − P★★★)·min(1, n/10).

Stage 2 acceptance criteria: `delta` tests and the exact solver trajectory; the D of ten levels matches the
prototype (≤ 3); D is stable across two bot seeds (≤ 2); progress migration is covered by a test; JSON gives the same
10 levels; the passport table is reviewed; the generator produces candidates for a trial slot within budget.

## Stage 2 result (done)

| Criterion | Result |
| --- | --- |
| `delta` and the exact solver trajectory | the test "delta == the difference of totals" on 10,000 random boards with `near`, `between` and neighbor swaps — 0 discrepancies; the solver with seed 99 gives the same result as before stage 1 |
| speed-up | as critic #2 predicted, a move through `delta` on small boards is slower than a full recount (746 vs 610 ms). The solver is hybrid: `delta` from 16 items. The bot always uses `delta` |
| comparison with the prototype | the bot is the same (a tie-breaking bias was found and fixed: replacement with probability 0.3 depended on the traversal order; now a uniform choice in both bots). The discrepancy is ≤ 2.2 in D |
| D stability | 300 bot runs (adaptive: batches of 50, stop when the error of P ≤ 0.025): the difference between two seeds ≤ 1.3 |
| data | `data/levels.json`, permanent `id`s, sorted by slot; `tests/test_campaign.gd` — 164 checks, 0 failures; the `progress.json` migration is covered by a test and checked on the player's real progress (in memory, without writing) |
| passports | `docs/passports.txt` reviewed: the target is capped at 97 (100 is unreachable); three levels out of the corridor found |
| generator | slot 5 — 5 s, slot 29 — 18 s, slot 59 — 79 s. The measured budget: the whole campaign ≤ 1.5 h, a big slot ≤ 2 min (60 s doesn't hold for big slots; the answer is not to cut the solver but to accept it: generation is one-off) |
| report | `tools/report.gd` -> `docs/report.txt`, `docs/report.csv`. Out of the corridor: "Quiet Pond" +7.3, "Two Ponds" +5.0, "Vegetable Patch" −12.9 — fixed in their seasons |
| play log | `user://playlog.json`: time, placements, returns, stars — for calibrating D |

**The first live data.** The user's `progress.json` has 9 completed levels. ★★★ is only on one ("Vegetable Patch").
The shortfall from the ideal (1 − record/ideal) doesn't agree with D: ρ ≈ −0.23 (n = 9; the data is mixed with
learning — the levels went in order — and with persistence). We don't change the D weights on 9 points, but there is
a conclusion for stage 3: a bot that tries the whole board gets ★★★ in 30–70% of runs, a human almost never. A ★★★
threshold = the ideal is probably too strict for people. Taken to the stage 3 defense.

New generator signals: on big autumn levels the bot almost never gets ★★★ (P < 0.05), G hits the ceiling — the "BOT"
flag in the report. It's the same ★★★ threshold problem.
