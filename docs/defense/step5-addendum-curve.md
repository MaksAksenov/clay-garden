# Stage 5, addendum: the top of the curve is unreachable — defense of the decision

## What the data showed

Autumn generation (16 slots, 40+ candidates each): **all** candidates have D 47–64 against targets of 58–90; almost
all of them have the bot reaching near-ideal in none of 100 runs (the "BOT" flag). The cause is a collision of two
decisions already made:

- the curve was built for a D scale where 100 means "32 items, 12 types, 7 mechanics, the bot never gets ★★★";
- the stage 5 defense limited the autumn hand to 16 (winter — 20 is proposed), so there would be no routine clicking.

With a hand of 16 the metric physically can't rise above ~70: N ≤ 0.67, K ≤ ~0.5, and G hits 1 (the bot fails
everything hard in the same way). Curve targets above ~70 are unreachable by any level we are willing to show the
player.

## Decisions

**A1. The curve's ceiling is the D of the hardest level we want** (hand ≤ 16–20): the curve is the same logistic
S-shape between a floor of 4 and a ceiling of 72, midpoint 40, steepness 12. Compared with the current one (target D
by slot):

| slot | 1 | 10 | 25 | 30 | 40 | 50 | 60 | 65 | 75 | 85 | 100 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| now | 4.0 | 7.3 | 17.5 | 22.7 | 36.0 | 51.9 | 67.8 | 74.8 | 86.2 | 93.8 | 100 |
| proposed | 4.0 | 6.7 | 17.2 | 22.9 | 36.9 | 50.9 | 61.2 | 64.6 | 68.8 | 70.8 | 72 |

Up to slot 50 the difference is ≤ 1 — **the finished spring and summer don't move**. Only the upper half changes: the
fastest growth stays in the middle (summer → early autumn), then a plateau — as an S-curve intends. For the player and
in the document, difficulty is shown as a percentage of the range: (D − 4) / (72 − 4) · 100 — that is, "0…100", as the
user asked.

**A2. The rejected alternative**: lift the hand limit (22 in autumn, 32 in winter) to reach the old targets. That
would be a curve for the curve's sake: difficulty would come from the volume of clicks, which is exactly what the
limit was against.

**A3. The "BOT" flag on the upper slots is not a level failure but a signal**: on the plateau the bot almost never
reaches near-ideal, so the G factor doesn't distinguish levels there. On the plateau levels are distinguished by
mechanics, tightness and "aha" (a greedy arrangement doesn't work). For such slots the "BOT" flag in the report is
informational, and the check is real playthroughs (the play log).

**A4. Generator: a hand theme without skew.** The "hammock — tree" link weighs 5 and drags the hammock into almost
every autumn hand. The weight of a link in theme selection is capped at 2, and the theme seed is the chapter's item
(already so) with probability 0.85.

## Defense result

Both critics: a ceiling of 72 is fitting, but honest if named as such ("100% = the hardest level we are willing to
show", not "32 items"). Both: on the plateau ±5 checks nothing — 40 slots in one corridor; the bot is blind there.

| Decision | Verdict | What changes |
| --- | --- | --- |
| A1 ceiling 72 | changed (both) | the corridor on the plateau (from slot 60) is ±3; the target is capped by the ceiling (`TARGET_MAX` removed); a check of the order within a chapter by slot type (trial ≥ puzzle ≥ practice ≥ warm-up by D); percentages are not shown to the player as a number. Conditions: the spring and summer report recomputed, the passports (hand sizes) checked; **a trial generation of winter with a hand of 20 — before acceptance** |
| A2 don't grow the hand | accepted (both) | the winter hand is 14…20 |
| A3 the "BOT" flag | changed (both) | a second indicator: the share of bot runs reaching the **interface ★★★** (92% of the ideal). Requirement ≥ 10%: otherwise ★★★ is almost unreachable for a human too — the slot is rejected. On the plateau this is what distinguishes levels. A live check via the log — additionally, when a human plays |
| A4 hand theme | accepted (both) | the weight of a link in theme selection is capped at 2; the report shows item frequency per season (one item in no more than 40% of the season's slots) |

**Checking the conditions:** the targets of slots 1–50 moved by no more than 1 (checked against `passports.txt`; the
hand sizes in the passports changed by ±1 for 6 slots — that's guidance for the generator, finished levels have their
own hands). The trial winter generation (slots 85 and 90, hand 20, no winter mechanics yet): D up to 66.1 against a
target of 72 — with two winter mechanics (+≈6) the ceiling is reachable. The new indicator "the bot gets the interface
★★★" distinguishes levels on the plateau: 0.12…0.97 at the same D ≈ 65.
