# Stage 11. App icon: defense of the technical decisions

The user's task: make an app icon. Right now the APK has the default Godot icon (the export warns "No project icon
specified"), and so does the PC window.

## Decisions

**D1. The icon is a script render of the game's real models** (`tools/make_icon.gd`): a piece of island from
`terrain.gd` and items from `items.gd`, lighting and tone mapping as in the game, an orthographic isometric view like
the game's camera. Not drawn by hand: the icon looks exactly like the game (clay, the same colors), the project rule
"not a single hand-drawn image" holds, and when the models change the icon is rebuilt with one command.

**D2. The subject is one of four variants** (`icon/candidates/_all.png` large, `_launcher.png` — 192, 96 and 48 px on
dark wallpaper in a rounded mask):
- **A** — a 3×3 island: tree, fir, flowers, bench, a pond with a water lily;
- **B** — a 2×2 island: a tree on a rise, a mushroom, flowers, a pond with a water lily;
- **C** — one block with a big tree;
- **D** — a 3×3 island: fir, tree, bush, flowers, lantern, pond.

**D3. The background is the game's sky**: a vertical blue gradient and soft clouds at the bottom (the island "floats",
as in the game).

**D4. Android — an adaptive icon**: the foreground (the island in a safe zone of 66% of 432 px; the launcher crops to
its own mask shape), the background (sky) separately, a monochrome silhouette for Android 13+ themed icons; plus a
regular 192 px one. PC — the project's `config/icon` (1024 px). iOS — later (needs a Mac).

**D5. Files** — `icon/icon.png`, `icon/android_*.png` in the repository (the export consumes them), the generator next
to them; the chosen variant — `icon/chosen.txt`.

**D6. Check** — an export without the icon warning; `aapt dump badging` of the APK shows the icon and the adaptive
layers; a screenshot of the icon in a launcher mask at 48 px.

## Defense result

Both critics chose **B** (a tree on a rise, a red mushroom, flowers, a pond): at 48 px the tree, the red cap and the
blue pond read, the "island with a ledge" silhouette is recognizable, and you can see that items are placed on the
island. A and D are mush at 48 px; C reads, but it's "just a tree on a cube" and doesn't convey a garden. The player's
main finding: **the background is too pale** — on light wallpaper the icon dissolves (the dark backdrop in the check
hid this). The skeptic's main finding: **the export doesn't know about the icon** (neither `config/icon` nor
`launcher_icons/*` is set) and **the safe zone was computed wrong** — the mask circle is 66 dp of 108 (61%, 264 px of
432), not 66%; the background clouds go under the mask.

| Decision | Verdict | What changes |
| --- | --- | --- |
| D1 rendering the models | accepted (both) | the generator refuses to run without a window (headless renders nothing); everything on fixed seeds, the "summer" season, time of day plays no part; the PNGs are committed |
| D2 variant | B (both) | the mushroom 20% bigger; the roots shorter and more even (the column doesn't pull the composition down); variants A, C, D stay in the generator only for comparison |
| D3 background | changed (player, skeptic) | a more saturated and warmer sky: turquoise at the top → warm peach at the horizon; the murky clouds removed, replaced by two small crisp clouds higher up (in the mask's visible zone); a soft shadow under the island — separates the silhouette from the background |
| D4 adaptive icon | changed (skeptic) | the island fits a 264 px circle centered at 216 (by the opaque-pixel bounds, checked in the generator); the adaptive background is the same gradient without clouds at the edges; **no monochrome layer** — a white blob is worse than a colored icon |
| D5 files | changed (skeptic) | `config/icon="res://icon/icon.png"`; in the Android preset — `launcher_icons/main_192x192`, `adaptive_foreground_432x432`, `adaptive_background_432x432` (names checked against the Godot 4.7.2 binary); `icon/candidates/*` excluded from the export; `chosen.txt` isn't needed — a constant in the generator |
| D6 check | extended (both) | `aapt2 dump badging` and taking the APK apart (`mipmap-*`, the adaptive XML with foreground/background); a screenshot on light, dark and busy wallpapers among "other" tiles at 48 px; in a round mask |

## Stage 11 results

**Done.** `tools/make_icon.gd` renders variant B (a 2×2 island: a tree on a rise, a mushroom 20% bigger, flowers, a
pond with a water lily) with the game's real models and produces: `icon/icon.png` 1024 px (`config/icon` — the PC
window), `android_192.png`, the adaptive `android_foreground.png` (the island in the safe circle: the farthest pixel
128 of 132 px — checked in the generator) and `android_background.png` (turquoise → peach), `android_monochrome.png`,
the review sheet `icon/preview.png`. The Android preset sets all four `launcher_icons/*`; the candidates and the
review sheet are excluded from the APK.

**Found along the way (reverses one defense decision).** We decided not to make a monochrome layer ("a white blob is
worse than a colored icon"). Taking the built APK apart showed: if the layer is empty, Godot puts **its own logo** into
`icon_monochrome`, and on a Pixel with themed icons on, the game would have Godot's head. So there is a monochrome
layer — not a blob but a toned silhouette (darker parts denser): the crown, the mushroom cap, the pond and the block
edges read (`shots/icon_themed.png` — in three theme palettes).

**Checks.** An export without the "No project icon" warning; the APK has `res/mipmap-*/icon*.webp` at all densities,
`mipmap-anydpi-v26/icon.xml` with `background`, `foreground`, `monochrome` (`aapt2 dump xmltree`); the icons were
unpacked from the APK and checked by eye — ours, not Godot's; the review sheet — light, dark and busy wallpapers, 96
and 48 px among other tiles, a round mask (`shots/icon_preview.png`). iOS — later (Mac).

**Fixed after the build: the default name.** `config/name` was Russian, so on a phone in any language other than
English and Russian (German, French, Ukrainian…) the launcher label would have been «Пластилиновый сад». The stage's
check looked only at the default `application-label` on a Russian system and missed the other 87 locales. Now
`config/name="Clay Garden"`, and the Russian name is only in `name_localized`. Since `user://` on PC is built from
`config/name`, the old save folder is pinned with `config/custom_user_dir_name` — the player's garden and progress
stayed in place (md5 checked). Check: `aapt2 dump badging` — 88 locales "Clay Garden", `ru` — «Пластилиновый сад».
