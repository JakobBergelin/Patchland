# Patchland (Godot port)

Patchland is a hex tile-placement roguelite: lay tiles so their edges match the land beside them, score each placement as yield × multiplier, collect relics and beat rising goals. This Godot 4 project is a port of a finished web prototype.

**Terminology:** players see **yield** (base points) and **multiplier**. The code still calls them `chips` and `mult` (e.g. `ev.chips`, `Pal.chips`, `FEAT[f].chips`); keep player-facing text on yield/multiplier. Don't name other games in code, text or docs.

**Reference implementation:** `reference/patchland.html` (single file, plain JS + canvas). It is the source of truth for rules, numbers, drawing and feel. When in doubt, match it.

## Hard constraints
- **No asset files for art or audio.** Every visual is drawn in code (CanvasItem `draw_*` calls, baked to textures where useful). Sound is synthesized at runtime (`AudioStreamGenerator`). This keeps Steam's AI disclosure to nothing beyond code assistance.
- The only allowed external assets are fonts (Bricolage Grotesque, OFL) and the GodotSteam plugin later.
- Keep game rules free of rendering code so they can be tested headless.

## Architecture
- `data/` — **editable content**: `content.tres` (a `ContentDB` resource) holds every special tile (`SpecialDef`), relic (`RelicDef`), unlock condition, the Season 1 goals, tiles per round, Season goal scales and rarity weights. Edit it in the Inspector; `Defs` loads it at startup (`Defs.load_content`) into `SPECIALS` / `SKEYS` / `RELICS` / `GOALS`. Ids are referenced by the rules code and saves, so don't rename them.
- `core/` — pure GDScript, no nodes: `Hex` (axial coords, pointy-top, DIRS = E, NE, NW, W, SW, SE), `Tile` (6 edge terrains, rotation, gold/quest/special flags, rivers/rails), `Rules` (match check, `evaluate()` placement scoring, `harvest_calc()`, `resolve_rays()`, regions, lines), `RunState` (round, goals, relics, bosses, streak, achievement stats), `Unlocks` (achievements, Seasons), `Scores`.
- `render/` — `TileArt` records each tile's drawing once per tile+rotation (terrain, trees, houses, every special structure, pennants, sails); `Board` draws tiles depth-sorted by y, ghost preview, indicators, ray previews, highlights; `Ambient` adds trains, boats, people and deer.
- `fx/` — particles, floating text, rings, beams, screen shake and zoom punch.
- `audio/` — synth helpers (tone with slide, filtered noise hit) and the sfx set.
- `ui/` — `game.gd` (HUD, tray, run flow, sheets for the relic draft and run end), `theme/patchland_theme.tres` (all fonts, colours and button/panel styles as type variations: PrimaryButton, GoldButton, GhostButton, TabButton, Sheet, Card, CardLocked, Pill, Rail, TitleLabel, HeadingLabel, …), `screens/` (main menu, collection, rules, scoreboard as `.tscn` scenes with small scripts that fill content and emit signals).
- `tests/` — headless rule tests, window tests with screenshots, and the bot sims used to set goals.

## Rules summary (see reference for exact numbers)
- Terrain yield: village 8, water 6, field 5, forest 4, meadow 3.
- Placement: each matching edge adds its yield and +1 multiplier (base multiplier 1). Perfect (2+ neighbors, all match) ×2 multiplier. Golden tiles ×2. Perfect streak adds +streak multiplier.
- Special tiles: chance `0.06 + 0.014 × unlocked kinds` (×2 with Architect), so unlocking more kinds means more specials, never fewer of each. Ray kinds: windmill (3 rays, length 3), lighthouse (1 ray to the edge of the land), bell tower (6 neighbors); each hit adds the hit tile's matched-edge yield, hitting another special fires it, each firing special adds +1 multiplier (`resolve_rays` only reports specials that actually fired). Landmarks (Scarecrow/field, Dam/water, Market/village, Hunting lodge/forest, Beehive/meadow) multiply their own land's area yield in the harvest (×2, ×3 with Stonemason) and add +2 multiplier to it; they're dealt with 3+ edges of their land (`Tile.fit_special`). Crossroads: all edges match any land. Standing stones: +1 harvest multiplier per special on the board.
- Quests (~17% of tiles): link N tiles of a terrain via matching edges → +2 tiles and bonus points.
- Round: 10 tiles (`Defs.TILES_PER_ROUND`; the reference used 12), then the harvest scores every region of 2+ linked tiles (yield per tile × size, +1 multiplier per 3 tiles) and fires all specials. Placement points + harvest must reach the goal.
- 8 rounds; Season 1 goals `[500, 2600, 6000, 18000, 34000, 62000, 110000, 170000]` in `content.tres` (see Balance; the reference used `[1500, 5000, 12000, 35000, 75000, 110000, 240000, 420000]`). Bosses on rounds 3, 6 and 8; beating one gives two relic picks.
- **Seasons** (difficulty): goals × `season_goal_scale` `[1, 1.4, 1.9, 2.4, 3]`, ramping in over the first 4 rounds (`RunState.goal`). Winning a Season opens the next (`Unlocks.record_win`); pick it in the main menu.
- 38 relics (the reference's 20 plus 18 Godot-only) with rarity Common / Fine / Heirloom; the draft draws 3 by `rarity_weights` (6 / 3 / 1). Harvest-wide multiplier sources (Almanac, Fishing village, Junction, Jeweler, Standing stones) come back from `harvest_calc` as `extras` and get their own harvest step.

### Rivers and railroads (Godot-only, not in the reference)
- About 30% of non-special tiles carry a river (55%) or a railroad, drawn over their land. Feature tiles keep their normal mix of 1-4 biomes; feature edges never sit on water edges.
- **Linking:** a river or rail edge that meets the same feature across an edge adds its yield (river 6, rail 8) and +1 multiplier, like a matching land edge. A river edge that runs into a plain water edge (a river mouth, `Rules.is_mouth`) counts as a matched land edge scored as water (6 yield, +1 multiplier), so it never breaks a perfect placement; it is not scored a second time as a river link. Ray hits count these links too. Drought zeroes river yield.
- **No cutting:** a placement is illegal if any shared edge leaves a river or track dangling (`Rules.line_breaks` / `feat_cut`): rail must meet rail, and a river must meet river or water. If the current tile has no legal spot in any rotation, the rule is lifted for that tile (`RunState.line_rule_lifted`).
- **Railroads start and end in cities:** a station is a rail tile with exactly one rail edge, leaving from a village edge. Track pieces (2-3 rail edges) are only dealt while a railroad on the board has an open end; otherwise railroads come as stations. Rivers have no start tile: river pieces are dealt while a river end or a water edge is open, otherwise no river is dealt.
- **Harvest:** a railroad network scores only between 2+ stations; a river network only once it reaches water at 2+ ends. Then: feature yield per tile, +1 multiplier per 3 tiles, +1 multiplier per end.
- **Closing a line** (no open ends, finished at both ends) pays an immediate bonus: `Defs.CLOSE_BONUS` (river 1.2%, rail 1.5%) of the round goal per tile, up to 10 tiles (`Rules.close_bonus`, `RunState.closed_lines`). A water tile that catches an open river end closes it too.
- **Closing a biome area** (a region of one land type, linked by matching edges, with no edge of that land facing an empty spot; bordered by matching or other land) pays an immediate bonus that grows faster than its size: `goal * REGION_BONUS * n * (1 + n / REGION_GROWTH)` for n tiles (min 3, capped at 16; `Rules.region_bonus`, `RunState.closed_regions`). Covering a region's last open edge with any land closes it. `RunState.closing_bonus` sums line and area bonuses for the preview hint and the bots.

## Port order
1. Core rules + headless bot simulation matching the reference's results.
2. Tile art and board rendering.
3. Input (tap/click to preview and place, rotate, redraw, keyboard), HUD and tray.
4. Placement and harvest scoring sequences with all juice.
5. Overlays, saving best score, settings (mute).
6. Steam (GodotSteam), achievements.

- The tray shows the current tile plus the next two (`RunState.nxt`, `nxt2`); the Fog boss hides both.
## Menus, tutorial and scoreboard
- Launch opens the **main menu** (Play, Tutorial, Scoreboard, How to play, Quit). Esc or the HUD ≡ button opens it as a pause menu during a run (Continue / New run). First-time players (no `tutorial_done` setting) get the Tutorial suggested.
- **Tutorial** (`ui/tutorial.gd`): a guided first round with a fixed seed, goal `Tutorial.GOAL` and `Tutorial.TILES` tiles (`RunState.goal_override`). Steps advance on events Game reports via `_tut(event)` ("hover", "rotate", "place") or a Next button; the callout lives in the top-left of the board. It ends after the harvest, with no relic draft and no scoreboard entry.
- **Scoreboard** (`core/scores.gd`): the top 10 finished runs (score, rounds reached, won, relics, date) in the settings file, section `scores`. The best run shown in menus is its top entry. The end-of-run sheet shows the rank.
- The **? button** opens the rules sheet (`show_rules`); Back returns to where it was opened from (`overlay_back`).

## Unlocks and collection
- All 10 special tiles and 30 of the 38 relics are locked at first and unlock through 40 achievements, one per item (`unlock_stat` / `unlock_need` / `unlock_text` on each def in `content.tres`; `Unlocks.LIST` is built from them). Each checks one RunState stat (e.g. Windmill = clear round 1, Lighthouse = close a river, Crossroads = a Perfect with 5+ neighbors). Relics marked `starter` (8) are always available. Unlocked ids and the highest open Season are saved in the settings file (section `unlocks`).
- `RunState.allowed_specials` / `allowed_relics` limit what `Tile.make` deals and what `draft_pool` offers. They default to everything (sims, tests, test runs); Game sets them from the player's unlocks before `new_run()`.
- Game calls `_check_unlocks()` after each placement, at round end (after `RunState.mark_cleared()`) and on game over; new unlocks join the current run at once and show a toast and on the end sheet. The tutorial and test runs never unlock anything.
- **Collection** (main menu, `ui/screens/collection.tscn`): tabs for special tiles, relics (with rarity filters) and Seasons; locked items are black silhouettes with how to unlock them, unlocked ones say what they do.
- **Test run** switch in the main menu: the next run has everything unlocked and records no score or achievements (`Game.test_run`, per run `run_is_test`).
- The bot sim takes `--profile all|mid|starter` (what it has unlocked) and `--season N`.

## Ambient life (decorative)
`render/ambient.gd`, rebuilt by the Board whenever tiles change: trains shuttle between stations on closed railroads (with smoke), boats sail closed rivers and drift on lakes of 3+ water tiles, people walk village areas (1 per 2 tiles, max 3 each), deer wander forests of 4+ tiles. Hard caps (3 trains, 3 boats, 8 people, 3 deer) keep it uncluttered; disabled with reduced motion.

## Controls
Hover a dashed slot to preview, left click places. **Right click rotates the tile clockwise** (shift + right click: counter-clockwise), on the board or on the tray tile. Ctrl + scroll, R/E/Q, the Rotate button and clicking (or scrolling on) the tray tile also rotate. X redraws, arrows cycle slots, Enter/Space places, M mutes. Clicking during the harvest speeds it up.

Camera: scroll zooms toward the cursor (0.45x to 4x of the auto-fit), left-drag (past 10 px) or middle-drag pans, WASD pans, +/- zoom, F / Home or double-clicking empty ground resets to the auto-fit view. Trackpad pinch and two-finger pan work too. The player view is stored as `Board.user_zoom` / `user_pan` on top of the auto-fit, so it keeps following the board as it grows. The automatic view is sticky (`Board._fit`): it only zooms out when the board would no longer fit and only moves as far as needed to keep everything on screen, so the camera stays calm while placing. Screen shake is capped at 8 px and placement shake stays small (big shakes are for the harvest and round end).

Fullscreen: F11, Alt+Enter or the HUD button; the choice is saved in `user://patchland.cfg`. It cannot work while the game runs embedded in the editor's Game tab (Godot 4.4+ default); the game detects that (`Engine.is_embedded_in_editor()`) and shows a toast saying to turn off "Embed Game on Next Play". The board spans the whole window while the HUD, relic strip and tray stay `Game.CONTENT_W` wide.

## Implementation notes
- Main scene `main.tscn` → `ui/game.gd` (builds the HUD and tray in code, owns `RunState`, runs `after()`/`step_q()` timed sequences like the reference). Full-screen screens are opened with `open_screen(path, kind)` inside the overlay; small sheets (draft, run end, tutorial end) use `open_overlay()`.
- Tile "baking": each `TileNode` records its `draw_*` commands once per tile+rotation; Godot keeps the canvas command list until `queue_redraw()`. Windmill sails are a child node rotated each frame.
- `Board` layers: slots and fx are drawn in screen space (port of `ws()`), tiles live in a y-sorted world layer scaled by the camera.
- Board entries are Dictionaries (`{q, r, k, tile, quest, prog, qdone}`); edge results in `per` are ints (-1 none, 0 mismatch, 1 match).
- Fonts are `SystemFont`s (Bricolage Grotesque if installed, else Segoe UI/Arial) until the OFL font file is added; they live in the theme. The game always uses its dark palette (`ui/pal.gd`, matching the theme).

## Testing
Run headless from the project folder, for example:
`godot --headless --path . -s res://tests/run_sim.gd -- --runs 3 --seed 1`
(on Windows, use the `_console.exe` build of Godot so output prints to the terminal). Run the simulation after any balance or rules change. A run takes ~30 s.

Rivers/railroads rule checks: `godot --headless --path . -s res://tests/features.gd` (add `-- <output folder>` without `--headless` to also save screenshots of a blocked and a legal spot). Run after any change to lines, dealing or scoring.

Menus test (needs a window): `godot --path . -s res://tests/menus.gd -- <output folder>` walks the main menu, the whole tutorial, a real run with Esc pause, the rules sheet, the scoreboard, unlocking, the Collection and a test run (own settings file).

Unlock rules (headless): `godot --headless --path . -s res://tests/unlocks.gd`. New tiles and relics do what they say (headless): `godot --headless --path . -s res://tests/content.gd`.

Visual smoke test (needs a window, not `--headless`): `godot --path . -s res://tests/screenshot.gd -- <output folder>` plays the opening, right-clicks to rotate (prints the rotation change), zooms and pans the camera, toggles fullscreen on and back, finishes round 1 and saves PNGs of each stage.

### Balance
Goals are set from bot runs. Two bots: `greedy` (every slot and rotation plus harvest look-ahead, and picks the relic that helps its board most: an expert) and `casual` (half the slots, 3 rotations, random relic: a person scanning the board).
- `GODOT=<console exe> tests/runs.sh [procs] [runs_per_proc] [season]` plays whole runs (a miss ends the run) for each bot and unlock profile and prints win rates.
- `GODOT=<console exe> PROFILE=starter|mid|all tests/balance.sh [procs] [runs_per_proc]` prints per-round p25/median/p75 scores (`--nofail`) next to the goals.

Current numbers (24 runs per line):

| Profile, Season | greedy wins | casual |
|---|---|---|
| starter (fresh), Season 1 | 17% | 0% wins, reaches ~round 3 |
| mid (ray specials, half the relics), Season 1 | 100% | 62% |
| all unlocked, Season 1 | 100% | 67% |
| all unlocked, Season 3 | 96% | 8% |
| all unlocked, Season 5 | 54% | 0% |

So a fresh profile has to unlock things to win, unlocks clearly make runs stronger (late-round scores roughly ×3 from starter to all), and Seasons keep it hard once everything is unlocked. Re-run after any scoring or content change.

## Backlog (not yet built)
Closing regions that bloom and cascade into neighbors; ripple scoring through neighbors that become perfect; tile transformations (water surrounded by fields becomes farmland, villages merge into towns); relics that fire in a player-chosen order; retriggers; relics that scale up over a run.
