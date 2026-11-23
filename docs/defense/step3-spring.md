# Stage 3. Spring: defense of the technical decisions

Context. Spring is slots 1–25, D from 0 to ~18, chapter by chapter: Sprouts (1–5), Shade (6–10), Stones and Pond
(11–15), Fir Grove (16–20), Spring Garden (21–25). Novelties: flowers and water (1), bush (4), tree and the first
minus (7), snowdrop (9), stones (12), water lily (15), fir (18), fixed "sprouts" (20), mushrooms (21), birdhouse (23).
There are already two spring levels: "First Bed" (22) and "Shady Corner" (24). 23 new ones are needed.
The stage 2 tools are ready: passports, generator, metric, report, play log.

Live data (stage 2): the user completed 9 of the 10 old levels with ★★★ on only one, while the bot gets ★★★ in
30–70% of runs. The ★★★ threshold today = the solver's ideal (on big levels the ideal minus 2–4%).

## Decisions

**D1. Snowdrop** (slot 9): stones +2, water +1, tree −1 ("it needs light, and stones warm up").
**Birdhouse** (slot 23): tree +2, bush +1, another birdhouse nearby −2 ("birds divide territory").
The scarecrow rule comes in autumn, with the scarecrow. The numbers are a start; the solver will show whether they
break levels (the novelty must be useful in the ideal — a generator check).

**D2. Models** — procedural clay like the rest: the snowdrop is white bells on thin stems, the birdhouse a little
house on a post with a round entrance. Live thumbnails in the palette — as now.

**D3. A spring palette** on spring levels: lighter, yellower grass, pink blossom speckles on tree crowns, rare petals
in the air. The level's season sets the palette. The general seasonal palette mechanism (free garden, 4 seasons) is
finished in stage 7; here — only spring and summer (as now).

**D4. A season map in the menu** instead of the 5×2 grid: tabs "Spring / Summer / Autumn / Winter", in a tab —
5 chapter rows of 5 slots, each chapter named; empty slots — "coming soon". Stars for the season and in total.

**D5. Gentler level unlocking.** Today it's strictly in order (the next one after ★ on the previous). With 100 levels
and the old ones moved, this breaks: the player has already completed slots 22, 24, 33… while slots 1–21 are new — by
the old rule, completed levels would become locked. Proposal: a chapter is unlocked if the previous chapter has ≥ 3
starred levels; inside an unlocked chapter levels go in any order; a level with progress is always unlocked. A season
— after ★ on the previous season's finale or if the season already has progress.

**D6. The ★★★ threshold is 95% of the ideal, and the ideal gets a separate "Perfect" mark** (a crown on the card and
in the result). Rationale — live data: a person almost never gets ★★★ when ★★★ = the ideal. The player's stars only
grow: on load the stars are recomputed from the record by the new thresholds. The D metric is recomputed with the new
threshold (G will get smaller — the curve's targets stay, the corridor is re-evaluated by the report).

**D7. Introducing a novelty in the game.** On the level where an item first appears, at the start — a banner "New
item: snowdrop" with its rules card; the item is highlighted in the palette.

**D8. 23 spring levels — the generator + curator selection.** For each slot: 40 candidates → 5 finalists → a choice
by the solution screenshot and ASCII; criteria — the generator's checks (corridor, novelty usefulness, slot type),
variety of silhouettes in a row, "does the idea read"; I write the name and the hint myself. The spring report is
the acceptance criterion.

## Defense result

Critic #2's main finding: the ★★★ threshold is at once a number in the interface, an input of the metric (G) and a
field in the data. Changing it without decoupling would make D lose its behavioral factor, and the thresholds in the
JSON and the generator would drift apart. Critic #1's main finding: the snowdrop's "stones +2" rule at slot 9 is dead
— stones unlock at 12.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 items | changed (both) | snowdrop: **bush +2**, water +1, stones +1, tree −1 (grows under bushes — the bush is unlocked from slot 3, stones are a bonus for later). The birdhouse is unchanged. A test "every id has everything": rules, name, model, ASCII letter (the letter moves to the item catalog — one source). "Sprouts" are not an item, they are fixed items of already familiar types |
| D2 models | accepted | a screenshot at game scale: the snowdrop is distinguishable from flowers (the models are enlarged) |
| D3 palette | changed (#2) | no "machinery": a `PALETTE[season]` table with spring and summer filled in; the free garden is summer; petals come last. Check: hint marks are readable on light grass |
| D4 season map | accepted | + a crown counter next to the stars |
| D5 unlocking | changed (both) | one function `Progress.is_unlocked` + a test. A chapter is unlocked if: it's the first; or the previous chapter has ≥ 3 starred levels; or it has progress itself (then entirely). Season boundaries follow the same rule (no wall at the finale). "Next" leads to the next unlocked level |
| D6 ★★★ and "Perfect" | changed (both) | decoupling: `scripts/stars.gd` — one function for interface thresholds from the ideal (★ 60%, ★★ 80%, ★★★ = floor(92%), but no higher than ideal−1) and a separate bot goal for the metric (ideal − floor(ideal/40), independent of the interface). Thresholds are no longer stored in the JSON — they are computed on load. **92% was chosen from the player's records**: 95% would give ★★★ on 2 of their 9 levels, 90% — on 7, 92% — on 5. The "Perfect" crown is a flag in progress. Progress v3: stars = max(saved, by the new thresholds from the record). If the player beat the solver's ideal — a special celebration in the result |
| D7 intro | changed (both) | on the player's first meeting with an item (`seen` in progress), not by slot number. The banner shows both the novelty's rules and who likes it |
| D8 levels | changed (both) | generation — after D6. Intros and slots 1–3 I build by hand (at D targets ≈ 0 the corridor distinguishes nothing), the generator only as a solver-checker. Slot 3 is the bush (was 4). An "intro" position without a novelty is renamed "warm-up". "First Bed" stays at 22: its D (11) is in the corridor there; at slot 5 it would be +6 higher |

Stage 3 acceptance criteria: the v3 migration (stars don't drop, the crown doesn't disappear) and `is_unlocked` —
by tests; the D of the ten old levels moved by no more than 2 (or the discrepancy is explained); the "every id has
everything" test; the spring report — all 25 slots filled, in the corridor; screenshots of the new menu, palette,
intro, models.

## Stage 3 result (done)

| Criterion | Result |
| --- | --- |
| v3 migration, `is_unlocked`, "every id has everything", thresholds | `tests/test_campaign.gd` — 589 checks, 0 failures; `tests/test_rules.gd` — 32,438, 0 failures |
| D of the old levels after decoupling | a shift of up to 5.2 (not ≤ 2): the old ★★★ threshold was manual and inconsistent (somewhere the ideal, somewhere ideal−2). Now the bot's goal is one rule "ideal − floor(ideal/40)". We didn't bend the rule to the old numbers. "Fir Grove" moved closer to the curve, "Two Ponds" moved away from it — fixed in stage 4 |
| spring filled | 25 of 25: 14 by hand (slots 1–3, intros, warm-ups), 9 from the generator, 2 moved |
| spring report | 0 flags. Warm-ups and intros are judged by content (the bot gets ★★★ ≥ 75%), the rest by the D corridor ±5 |
| autosolve | 25 of 25 — ★★★ with the ideal in the real game |
| screenshots | the season map (a new player and migrated progress), the spring palette, the snowdrop intro, marks on light grass |

What changed along the way, beyond the defense (each — from data, not by eye):
- **The curve's floor.** The simplest real level (3 flowers by a pond) has D = 3.9; levels with a meaningful choice
  (6 items, 3 linked types) — 10–12. Spring targets of 0–8 would require boring levels. The curve now starts at
  D = 4 (`Campaign.FLOOR`), with the same shape and steepness.
- **The generator builds a connected hand "theme"** — items with rules between them, and no more than half the hand
  of one type. The first candidates had "no soul": 5 water lilies, firs next to birdhouses with no shared rules.
- **The novelty card and banner show only items unlocked by that slot**: on level 1 the flowers card talked about a
  bench the player would only see in summer.
- **Slot 8 is a "twist", not an intro**: the "first minus" entry in the unlock table made it an intro, and the
  generator produced three bushes. The conflict of two trees is the essence of a twist, not a new rule type.
- No "twist" candidate with 4–5 items passed the formal check (a greedy arrangement < 25% ★★★): on such small hands
  it can hardly be met. Candidates where the twist idea reads (two diagonal trees sharing bushes) were taken — a
  curator's decision, recorded.
- The debug flag `--newplayer` (progress as for a new player).
