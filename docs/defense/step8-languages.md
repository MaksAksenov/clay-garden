# Stage 8. Languages: defense of the technical decisions

The user's task: switching the language from Russian to English and a framework so new languages are easy to add.
Today all text is Russian literals in code: the interface (`ui.gd`, ~60), rules cards and hints above a cell
(`scoring.gd describe`, ~30 player-facing), chapter and season names (`campaign.gd`), item names (`items.gd`), intro
banners (`main.gd`), 100 level names and hints (`data/levels.json`). Rule data error messages and slot type
descriptions are for the developer; we leave them alone.

## Decisions

**D1. Our own small module `scripts/i18n.gd`, dictionaries as JSON `lang/<code>.json`.** A flat "key → string" map
plus `_meta` (`name` — the language's own name, `code`). Files are found automatically at startup: a new language =
copy `en.json` to `de.json` and translate, no code changes. Not the built-in `TranslationServer` with CSV/PO: those
need an editor import step, while our interface builds its text in code anyway; our own module is 60 lines and can be
tested headless.

**D2. Semantic keys** (`ui.menu.sandbox`, `card.per_neighbor`, `item.tree`), not Russian text as the key: editing a
Russian phrase doesn't break a translation. Substitutions are named `{n}`, `{item}` (word order differs between
languages), not `%s`. The fallback chain: the chosen language → English → Russian → the key itself (it shows what is
missing).

**D3. Level texts.** The Russian `name`/`hint` stay in `levels.json` — it's the authoring language (drafts →
`add_levels`). Translations are in the language file by permanent id: `level.<id>.name`, `level.<id>.hint`. No
translation — show the Russian from the data.

**D4. Rules cards are assembled from templates** (`card.per_neighbor`: "For each neighbor: {list}"), with item names
from `item.<id>`. Grammatical cases ("on a snowdrift/ice") are separate terrain keys (`terrain.on.snow`), no grammar
engine; plurals aren't needed (numbers are placed in phrases so the form doesn't change).

**D5. The switch.** A "Язык: Русский / Language: English" button in the menu (cycling through the found languages)
and the L key in the menu. The choice is stored in a new `user://settings.json` (the garden and progress are
untouched). First start — the system language if there is such a file, otherwise English. Switching instantly
rewrites the captions of the menu, the palette, the corner (`ui.retranslate()`); 3D hints and cards are built on the
fly and pick up the language themselves.

**D6. Acceptance checks.** A test `tests/test_i18n.gd`: every key called in code (`I18n.t("…")`) exists in Russian
and English; the languages have one set of keys; the `{…}` substitutions match; each of the 100 levels has an English
name and hint; every item's card in English has no Cyrillic and no leftover `{…}`; the Russian cards match the current
ones (a `describe` reference). Screenshots of the menu, a level and the garden in both languages.

## Defense result

Main finding #2 (the skeptic): the danger isn't missing keys but strings that **never went through** translation at
all: Russian grammar in `phrase` (`" или "`, `" (листопад)"`, `capitalize()` giving "Tree Or Pine"), constants like
`MECH_INTRO`, captions assembled once. A "keys exist" test doesn't see them — what's needed is a pseudo-language, a
walk over the interface tree and a search for Cyrillic in code. Main finding #1 (the player): today's player with an
English Windows would suddenly see English after the update; and the English must be cozy, not literal.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 module and JSON | accepted (both) + extended | languages are looked up in `res://lang/` and `user://lang/` (your own translation without rebuilding); the README says honestly: other scripts (CJK, Arabic) need a font |
| D2 keys, `{n}` | accepted (both) | — |
| D3 level texts | changed (both) | **one path**: the Russian names and hints move from `levels.json` to `lang/ru.json` (a one-off migration), `add_levels` writes there and warns if a changed Russian text has a translation (stale); the fallback language is English, Russian is nobody's fallback (no Cyrillic in other languages); a glossary of item names for hints; adaptation rather than literal translation ("Shady Nook") |
| D4 cards | changed (both) | templates are whole phrases per language; the list connector `list.or`, the falling-leaves suffix, the terrain — keys; our own "first letter uppercase" instead of `capitalize()`; room for plural forms is marked, "any language" is not promised; the Russian cards are byte-for-byte as before the rebuild (the reference is captured before it) |
| D5 switch | changed (both) | no L key; a "Language: …" button in the menu **and** in the corner panel; switching **rebuilds the interface entirely** and returns to the current mode (no manual `retranslate()` that goes stale); first start: there is a `garden.json`/`progress.json` but no settings → Russian; a brand-new player → a "Русский / English" choice screen; the system language — `OS.get_locale_language()` to highlight an option |
| D6 checks | changed (both) | + a pseudo-language `--lang=xx` (every string in `[!…!]`, the forgotten ones are visible on a screenshot); a walk over the interface tree in English (menu, garden, level, card, result, hidden panels) — not a single Cyrillic letter; a search for Cyrillic literals in player-facing code with a list of exceptions (developer messages); no Cyrillic in English levels; ru / en / xx screenshots. A human proofread of the 100 English names is an open item for the user |

## Stage 8 results

**Done.** `scripts/i18n.gd` (dictionaries from `res://lang` and `user://lang`, English fallback, the `xx`
pseudo-language, `signed`, `cap_first`, level texts by id); `lang/ru.json` and `lang/en.json` — 355 keys each: the
interface, items (`item.*` — titles, `noun.*` — words inside phrases), tools, seasons, chapters, mechanic banners,
hints above a cell, rules cards as whole phrases, 100 level names and hints. The Russian level texts moved from
`levels.json` to `lang/ru.json`; `add_levels` writes there and prints a stale-translation warning. The English level
texts are an adaptation, not a calque ("A Shady Nook"), with the same words as the cards (Fir, Stones, Beehive, Feeder,
Water Lily). A "Language: …" button in the menu and the corner panel; switching rebuilds the interface entirely and
returns to the current mode; the choice is in `user://settings.json`; first start: a player of the earlier version →
Russian, a new one → the choice screen (the system language first).

**Found along the way.** The Russian haystack card read "Тыквы Или Забор рядом" — `capitalize()` raised every word;
now "Тыквы или забор рядом". The other 234 of 240 Russian cards match the pre-rebuild reference byte for byte.

**Checks.** `tests/test_i18n.gd` — 17,024 checks, 0 failures: the same keys and substitutions in all languages; every
key the code builds exists; the Russian cards = the reference `tests/golden_cards_ru.json`; the English ones have no
Cyrillic, `{…}` or raw keys; player-facing code has no Russian strings bypassing the dictionary; the first-start
language rule; a translation from `user://lang`; a walk through the whole interface in English (the menu for all
seasons, the garden in all seasons with the counter, levels from spring to All Year Round with the card of every item,
results with 0–3 stars); switching the language on the fly — one interface, the mode came back. The other tests are
green. Screenshots: `shots/en_menu.png`, `en_level79.png`, `en_level60.png`, `en_garden_winter.png`, `ru_menu.png`,
`lang_picker.png`, `xx_level97.png` (the pseudo-language — everything in brackets).

**Open.** A human proofread of the English texts (especially the level names) and one playthrough of the first
chapter in English.

**Name proofreading (2026-11-22).** The 100 level names were proofread by a separate agent (Haiku 5.5): English is
the source, Russian an adaptation, light seasonal pop-culture references (`docs/naming/level_names_proposal.md`).
Applied with three Russian corrections: 19 «Фруктовый сад» ("Fruit Garden", rather than «Редкий сад», which drifted
from "The Orchard"), 35 «Подмосковные вечера» (a classic song title: white nights are never dark, and the level is an
evening with lanterns), 75 «Праздник урожая» ("Harvest Festival", instead of the calque «Урожайная луна»). 23 English
and 26 Russian names changed; the drafts were updated so `add_levels` doesn't bring the old ones back. On a phone the
name on a menu card is on one line (cards span the panel's width, the font is fitted but no smaller than 12).

**"Russian by default" audit (after stage 11).** Found and fixed: the rule "a garden exists, no language chosen →
Russian" (for a player of the earlier Russian version) would have fired on a phone too, where there was no earlier
version — now it's PC only, and on a phone such a player sees the language choice; `I18n.lang` before a choice is
English, not Russian. Checked clean: `en.json` has no Cyrillic, scenes and code have no player-visible Russian strings
bypassing the dictionaries.

**English by default for the repository (2026-11-22).** Before publishing, the code comments, tool and test output,
README and docs were moved to English; Russian stays only in the localization package (`lang/ru.json` and its test
references — the Russian cards, the Russian level names in the naming notes). The level drafts and `add_levels` now
author texts in English (`lang/en.json`). Developer reports (`tools/report.gd`, `tools/passports.gd`) use the default
language, English.
