# IP review (2026-11-23)

A check, when the repository went public, that the game doesn't use anyone else's copyrighted work, trademarks or
patented methods. It combines our own review with two independent reviews of the same code; every finding was checked
at its source before acting on it. It is an engineer's review from public sources, not legal advice.

## What ships in the game

| Part | Origin | Status |
| --- | --- | --- |
| Code (`scripts/`, `tools/`, `tests/`) | written for this project | ours, MIT |
| Models, terrain, clouds, icons, flags | built from primitives / SVG paths in code | ours |
| Music, sounds | synthesized in code (`music.gd`, `sfx.gd`): a pentatonic random walk, no melodies taken | ours |
| Shaders | written for this project | ours |
| Shader hash | a draft used Dave Hoskins' "Hash without Sine" (Shadertoy `4djSRW`, MIT) without its notice; **replaced** by our own integer hash built on Chris Wellons' `lowbias32` finalizer (public domain), and the Git history was squashed, so the repository holds no copy of it | fixed |
| Bump mapping | the surface-gradient formula from M. S. Mikkelsen, "Bump Mapping Unparametrized Surfaces on the GPU" (2010), cited in both shaders. A method is not protected by copyright; the ten lines follow the paper's math (Listing 1), which leaves little room for a different expression | cited |
| Font | Godot's built-in Open Sans SemiBold (OFL-1.1) | listed in About |
| Engine | Godot 4.7.2 (MIT) and its `thirdparty/` | About: license, 102 components, 19 license texts |
| Mozilla CA certificates | embedded by Godot (`thirdparty/certs/ca-bundle.crt`, MPL-2.0); MPL 3.2 asks to say where the source form is | About: a source link on the component (`ui.gd::SOURCE_LINKS`, the running engine's release tag) |
| Android libraries | AndroidX (with `android.support` compat classes), Kotlin and kotlinx.coroutines, Guava ListenableFuture, JSpecify, JetBrains annotations (Apache-2.0); LLVM libc++ from the NDK, shipped as `libc++_shared.so` (Apache-2.0 with LLVM Exceptions). Animal Sniffer was listed but doesn't ship (only a stray string in the dex, no class) — removed | About: `ui.gd::ANDROID_LIBS`, checked against the APK by `tools/check_notices.py` |
| libc++ notices | its own `LICENSE.TXT` — the LLVM exceptions and the legacy UIUC / MIT notices with their copyright lines — from the toolchain revision the `.so` was built from (`toolchain/llvm-project` `5e96669f`, clang 21), unchanged | `legal/libcxx-LICENSE.txt`, exported and shown in About's Android block |
| Python tools | standard library only; not shipped | — |
| Flags (language picker) | national flags: state symbols are not subject to copyright (Civil Code of the RF, art. 1259 p. 6) | ok |

"Made with Godot Engine" is a use allowed by the Godot trademark policy; the Godot logo is not used (stage 11 replaced
it in the monochrome icon).

`tools/check_notices.py` was run on the debug APK built from Godot 4.7.2's template (3,887 classes, `libc++_shared.so`,
`libgodot_android.so`). A release AAB built with Gradle may ship a different set: run it again on that build, and
check that the libc++ text still matches the NDK in use. Repository documents (`docs/*`) are excluded from the export;
`legal/*.txt` is included.

## Names

- **"Clay Garden" / «Пластилиновый сад»**: no game with this name on Steam, Google Play, the App Store or itch.io. An
  independent review reports a Turkish combined mark "Clay Garden" (No. 2019/65687, class 41 — entertainment services,
  in force until 2029-07-10); we couldn't open the register (TMview refuses automated access) to confirm it. Before a
  store release, check the USPTO, EUIPO, WIPO, Rospatent and TÜRKPATENT registers for the chosen countries; if Turkey
  is one of them, look at that mark's services first.
- **Level names** that matched well-known works were **renamed** (ids and saves unchanged):

  | id | was | now |
  | --- | --- | --- |
  | `evening_alley` | Summer Nights / «Подмосковные вечера» (a song still under copyright in Russia) | Lanterns at Dusk / «Фонари в сумерках» |
  | `summer_garden` | Endless Summer / «Бесконечное лето» (a Russian video game of that name; a 1966 film) | Height of Summer / «Макушка лета» |
  | `harvest` | Harvest Moon (a video game trademark of Natsume) / «Праздник урожая» | Harvest Festival / «Праздник урожая» |
  | `winter_came` | The Snowman / «Снеговик-почтовик» (a 1955 Soyuzmultfilm cartoon) | The First Snowman / «Первый снеговик» |
  | `one_lantern` | Home Alone / «Один дома» (a film and trademark) | A Single Lantern / «Один фонарь» |

  Under Russian law an original title is protected together with its work (art. 1259 p. 7). Kept as common phrases
  rather than recognizable titles: High Noon / «Ровно в полдень», Winter Wonderland / «Зимняя сказка», King of the Hill,
  The Bodyguard, A Bench with a View, Still Waters / «В тихом омуте», Four Seasons / «Времена года» (Vivaldi and
  Tchaikovsky are in the public domain).

## Mechanics and patents

Placing items for adjacency points (Islanders, 2019; many board games), stars for a level and unlocking by stars
(Angry Birds, 2009; Retry) are game rules, which copyright doesn't protect. No active patent on them was found, and
the prior art is wide. An independent review compared the independent claims of 13 granted patents with the game and
found no full match; the closest (titles, owners and status checked on Google Patents, claim reading not repeated here):

- **US9373213B1**, Zynga, "Adaptive object placement in computer-implemented games", active until 2033: needs a
  recursive update of nearby objects that changes a displayed property; our scoring and the season wave (`main.gd`,
  cells change independently by distance from the center) don't do that.
- **US12268966B2**, Zynga, "Automated generation of custom content for computer-implemented games", active until about
  2040: generates level variants from behavior data of a subset of players. Our levels are a static campaign,
  built without reading any play log.
- **US20250269285A1**, Echo Chunk, "Procedural generation and solvability assessment of interactive content" — an
  application, pending, not a granted patent. Claim 1 as published (generate content procedurally, extract features,
  compute a measure from them, output by the measure) read on the level generator and bot metric that built the
  campaign (kept outside this repository), not on the game: players get fixed level data. A pending
  application can't be infringed; **watch it** — if it is granted with that claim, generating new levels that way needs
  a decision.

**Check again before** generating or tuning levels from players' behavior (the play log, analytics), generating levels
on the player's device, adding helpers or boosters to unlocking, or adding special touch gestures beyond pan, pinch and
long press.

A real freedom-to-operate search is a patent attorney's job; this review doesn't replace it.

## Note

The Git history is a single commit: earlier drafts were squashed on 2026-11-23. It records what is in the repository,
not where each piece came from. Everything was made by the owner with an AI assistant; there were no other
contributors. In some countries (the US in particular) protection of AI-generated material may be limited; that
doesn't infringe anyone's rights and doesn't affect the MIT license.
