# Stage 13. Unlocking by stars: defense of the technical decisions

The user's task: by default only Spring is open; the other seasons are locked, like levels. Levels open in fives
(chapters). To open the next five you need at least 5 stars in the previous one ("open to discussion"), i.e. every
level passed with at least one star; it could also be 10 (every level at two stars, or a three-star level makes up for
a one-star one).

What exists now (stage 3, D5):
- `Progress.is_unlocked(i, progress)` — one function for the whole game. A chapter (5 slots) is open if it is the
  first one; or the previous chapter has ≥ 3 levels with at least one star; or the chapter itself has any progress
  (then entirely). Season boundaries follow the same rule. Inside an open chapter the levels go in any order.
- The menu season tabs (`ui.gd::_fill_menu`) can always be clicked; the levels of a locked chapter show "N · locked".
- "Next" in the result window leads to the next unlocked level (`next_unlocked`); without one it goes to the menu.
- Stars: ★ 60% of the ideal, ★★ 80%, ★★★ 92%. On the first 25 levels the bot gets ★★★ in 86–100% of runs; the
  player's own log: ★★★ on levels 1–5 within 4–19 s each (one 0★ and one 2★ first try).
- The free garden's seasons depend on the farthest completed slot (`Progress.reached`), not on this rule.
- The player's real progress has old levels that moved to later slots during stages 3–6 (slots 24, 33, 35, 42, 48 …):
  such a player has progress in summer chapters without having passed spring.

## Decisions

**D1. A chapter opens by the sum of stars in the previous chapter**, not by the number of starred levels: the sum
lets three stars make up for a weaker level, as the user described. One function (`is_unlocked`) as before.

**D2. The threshold is 10 of 15** (an average of ★★): ★ at 60% is reached by just placing everything, so 5 stars
would barely be a gate; ★★ at 80% asks for thought, while a level the player is stuck on can stay at 0★ if the others
make up for it (3+3+2+2+0). A constant `CHAPTER_STARS` in `progress.gd`.

**D3. Seasons are locked the same way:** a season tab is clickable only when its first chapter is open. A locked tab
is drawn dimmed with a lock and its star count is hidden; a tap shows a toast "Summer opens after 10 stars in
Spring Awakening".

**D4. The player sees the way forward:** in the menu, the caption of each open chapter shows its stars "★ 7 / 10"
until the next chapter opens (then just the name). Locked level cards keep "N · locked".

**D5. Nothing that is open now gets locked:** a chapter with any progress stays open entirely (as before); a season is
open if any of its chapters is open. Progress data doesn't change (no migration).

**D6. The moment of unlocking is celebrated:** if this result opened a new chapter, the result window says "New
chapter: Shade"; if it opened a season — "Summer is open!". "Next" still leads to the next unlocked level; at the end
of a chapter without enough stars it goes to the menu (the caption shows how many are missing).

**D7. Debug flags stay unrestricted:** `--level=N` starts any level (screenshots, tests); the free garden is
unchanged.

**D8. Checks:** `test_campaign` — the sum rule on synthetic progress (9 stars — closed, 10 — open; 3+3+2+2+0 — open;
season tabs; a chapter with progress stays open; the first chapter is always open); the player's real progress file
loaded read-only — everything that was open before stays open; `test_i18n`/`test_touch` — the new strings in both
languages and the menu layout; screenshots of the menu with a locked season and the chapter counter (PC and phone).

## Defense result

Main finding #1 (the player): **10 breaks the promise of D2 itself.** Leaving a stuck level at 0★ with 10 needs two
★★★ in the same chapter, and in winter the bot gets ★★★ on some levels in only 17% of runs (slots 77, 93): a calm
"you can't lose" game would put up a skill wall exactly where the levels are hardest. And 5 by a *sum* is not "every
level ★": 3+2+0+0+0 would open the next chapter after two levels. **8 of 15** is "every level ★ and three better",
and it also allows ★★ on four levels with one skipped — no ★★★ needed. Spring won't feel any of these values (★★★ in
4–19 s); the threshold matters in autumn and winter.

Main finding #2 (the skeptic): with a real gate, "every open level is played, the next chapter is still closed"
becomes a normal state, and the code handled it badly: the default menu tab fell back to Spring for an autumn player,
and `next_unlocked` searched the whole campaign — for an old save it jumped over a closed chapter to one that is open
only by its old progress. Also D3 contradicted D5 (a season opens by its *first* chapter vs by *any* chapter).

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 sum of stars | accepted (both) | `Progress.open_chapters` computes the open set once per menu fill / result (it was rebuilt per card); `chapter_stars`, `chapter_need`, `season_open` — one source for the menu, the result and the tests |
| D2 threshold | changed (both) | **8 of 15** (`NEED_PER_FIVE`); a chapter with fewer levels needs ceil(1.6 per level), so a short chapter is never impossible |
| D3 seasons | changed (both) | a season is open if **any** of its chapters is open (agrees with D5); a locked tab stays clickable (to see what's ahead), dimmed, a lock right before the name instead of the star count; instead of a toast (which overlapped the tabs and is hidden in screenshot runs) the line under the grid says "Summer opens after 8 stars in Spring Garden" |
| D4 chapter counter | changed (both) | "★ 5 / 8" as a small second line only on the open chapter whose next one is closed, never on the last chapter; the name is fitted to one line so the row doesn't grow on a phone; a locked chapter's name is dimmer. Declined: a toast on tapping a locked card — the counter and the season line already say what to do, and a toast in the menu needs its own placement |
| D5 nothing gets locked | accepted (both) | — |
| D6 the unlock moment | changed (both) | open chapters before / after the result are compared; "New chapter: Shade", "Summer is open!", otherwise "Sprouts: ★ 5 of 8 to open the next chapter"; "Next" goes only to the next slot if its chapter is open — it never jumps over a closed one; the default menu tab is the first open level without stars, otherwise the farthest open season |
| D7 debug flags | accepted, documented | `--level=N` saves progress (and opens its chapter) unless `--nosave` — said in the README; `--season=` in the menu opens that tab (screenshots of a locked season) |
| D8 checks | changed (skeptic) | no test reads the player's real file — an old-save fixture with the same ids (slots 22, 24, 33, 35, 42, 48) instead |

## Stage 13 results

**Done.** `scripts/progress.gd`: `open_chapters`, `chapter_stars`, `chapter_need`, `season_open`, `NEED_PER_FIVE = 8`,
`next_unlocked` stops at a closed chapter. `ui.gd`: locked season tabs (a lock icon drawn in code, centered with the
name), the chapter caption with a "★ n / 8" line, the season line under the grid, the default tab. `main.gd`: the
result line about unlocking (`_unlock_note`), `--season=` for the menu tab. Five new strings in `en` and `ru`; the
Russian "season is open" avoids grammatical gender ("Новый сезон: Лето!").

**Checks.** `test_campaign` — 5,768 checks, 0 failures: only Spring open for a new player; the sum cases
(1+1+1+1+1 and 2+2+1+1+1 closed; 2+2+2+1+1, 2+2+2+2+0, 3+3+1+1+0, 3+3+2+0+0 open; 3+3+1+0+0 closed), "Next" at the end
of a chapter follows the gate; a two-star spring opens summer, 7 stars in its last chapter don't; the old-save fixture —
every level with progress open, the gap closed, "Next" never jumps. `test_i18n` — 20,109: the whole menu in English for
a new player, the locked-season line on summer, autumn and winter. `test_touch`, `test_settings`, `test_sandbox`,
`test_rules` are green. Screenshots: the menu (PC, English; phone, Russian), a locked summer and winter tab, the result
window with the chapter line (phone, Russian).

**Open.** A playthrough of a late chapter by a person: whether 8 feels right in winter.
