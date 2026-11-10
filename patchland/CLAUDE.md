# Patchland (Godot port)

Patchland is a hex tile-placement roguelite: Dorfromantik's edge matching plus Balatro's chips × mult scoring, relics and rising goals. This Godot 4 project is a port of a finished web prototype.

**Reference implementation:** `reference/patchland.html` (single file, plain JS + canvas). It is the source of truth for rules, numbers, drawing and feel. When in doubt, match it.

## Hard constraints
- **No asset files for art or audio.** Every visual is drawn in code (CanvasItem `draw_*` calls, baked to textures where useful). Sound is synthesized at runtime (`AudioStreamGenerator`). This keeps Steam's AI disclosure to nothing beyond code assistance.
- The only allowed external assets are fonts (Bricolage Grotesque, OFL) and the GodotSteam plugin later.
- Keep game rules free of rendering code so they can be tested headless.

## Architecture
- `core/` — pure GDScript, no nodes: `HexGrid` (axial coords, pointy-top, DIRS = E, NE, NW, W, SW, SE), `Tile` (6 edge terrains, rotation, gold/quest/special flags), `Rules` (match check, `evaluate()` placement scoring, `harvest_calc()`, `resolve_rays()`, region BFS, quests), `RunState` (round, goals, relics, bosses, streak, almanac).
- `render/` — `TileArt` bakes one texture per tile+rotation (port `renderTile`, trees, houses, hay, bushes, windmill/lighthouse/bell tower, pennants, sails); `Board` node draws tiles depth-sorted by y, ghost preview, match indicators, ray previews, region highlight.
- `fx/` — particles, floating text, rings, beams, screen shake and zoom punch, tween-based drop/squash/hop.
- `audio/` — synth helpers (tone with slide, filtered noise hit) and the `sfx` set from the reference.
- `ui/` — HUD (round, score, goal bar with "on pace" segment, tiles left), relic strip, tray (current/next tile, chips × mult readout, hint), overlays (intro, relic draft, game over, win), banners, toasts.
- `tests/` — headless scripts, including a greedy bot that plays full runs and prints per-round scores (used to set goals).

## Rules summary (see reference for exact numbers)
- Terrain chips: village 8, water 6, field 5, forest 4, meadow 3.
- Placement: each matching edge adds its chips and +1 mult (base mult 1). Perfect (2+ neighbors, all match) ×2 mult. Golden tiles ×2. Perfect streak adds +streak mult.
- Special tiles (~10%): windmill (3 rays, length 3), lighthouse (1 ray to the edge of the land, rotates), bell tower (6 neighbors). Each hit adds the hit tile's matched-edge chips; hitting another special fires it; each firing special adds +1 mult.
- Quests (~17% of tiles): link N tiles of a terrain via matching edges → +2 tiles and bonus points.
- Round: 12 tiles, then the harvest scores every region of 2+ linked tiles (chips per tile × size, +1 mult per 3 tiles) and fires all specials. Placement points + harvest must reach the goal.
- 8 rounds, goals `[600, 4000, 10000, 34000, 78000, 130000, 340000, 480000]` (rebalanced in Godot, see Balance below; the reference used `[1500, 5000, 12000, 35000, 75000, 110000, 240000, 420000]`). Bosses on rounds 3, 6 and 8; beating one gives two relic picks.
- 20 relics, listed in the reference's `RELICS` array.

### Rivers and railroads (Godot-only, not in the reference)
- About 30% of non-special tiles carry a river (55%) or a railroad, drawn over their land. Feature tiles keep their normal mix of 1-4 biomes; feature edges never sit on water edges.
- **Linking:** a river or rail edge that meets the same feature across an edge adds its chips (river 6, rail 8) and +1 mult, like a matching land edge. A river edge that runs into a plain water edge (a river mouth, `Rules.is_mouth`) counts as a matched land edge scored as water (6 chips, +1 mult), so it never breaks a perfect placement; it is not scored a second time as a river link. Ray hits count these links too. Drought zeroes river chips.
- **No cutting:** a placement is illegal if any shared edge leaves a river or track dangling (`Rules.line_breaks` / `feat_cut`): rail must meet rail, and a river must meet river or water. If the current tile has no legal spot in any rotation, the rule is lifted for that tile (`RunState.line_rule_lifted`).
- **Railroads start and end in cities:** a station is a rail tile with exactly one rail edge, leaving from a village edge. Track pieces (2-3 rail edges) are only dealt while a railroad on the board has an open end; otherwise railroads come as stations. Rivers have no start tile: river pieces are dealt while a river end or a water edge is open, otherwise no river is dealt.
- **Harvest:** a railroad network scores only between 2+ stations; a river network only once it reaches water at 2+ ends. Then: feature chips per tile, +1 mult per 3 tiles, +1 mult per end.
- **Closing a line** (no open ends, finished at both ends) pays an immediate bonus: `Defs.CLOSE_BONUS` (river 1.2%, rail 1.5%) of the round goal per tile, up to 10 tiles (`Rules.close_bonus`, `RunState.closed_lines`). A water tile that catches an open river end closes it too.
- **Closing a biome area** (a region of one land type, linked by matching edges, with no edge of that land facing an empty spot; bordered by matching or other land) pays an immediate bonus that grows faster than its size: `goal * REGION_BONUS * n * (1 + n / REGION_GROWTH)` for n tiles (min 3, capped at 16; `Rules.region_bonus`, `RunState.closed_regions`). Covering a region's last open edge with any land closes it. `RunState.closing_bonus` sums line and area bonuses for the preview hint and the bots.

## Port order
1. Core rules + headless bot simulation matching the reference's results.
2. Tile art and board rendering.
3. Input (tap/click to preview and place, rotate, redraw, keyboard), HUD and tray.
4. Placement and harvest scoring sequences with all juice.
5. Overlays, saving best score, settings (mute).
6. Steam (GodotSteam), achievements.

## Controls
Hover a dashed slot to preview, left click places. **Right click rotates the tile clockwise** (shift + right click: counter-clockwise), on the board or on the tray tile. Ctrl + scroll, R/E/Q, the Rotate button and clicking (or scrolling on) the tray tile also rotate. X redraws, arrows cycle slots, Enter/Space places, M mutes. Clicking during the harvest speeds it up.

Camera: scroll zooms toward the cursor (0.45x to 4x of the auto-fit), left-drag (past 10 px) or middle-drag pans, WASD pans, +/- zoom, F / Home or double-clicking empty ground resets to the auto-fit view. Trackpad pinch and two-finger pan work too. The player view is stored as `Board.user_zoom` / `user_pan` on top of the auto-fit, so it keeps following the board as it grows. The automatic view is sticky (`Board._fit`): it only zooms out when the board would no longer fit and only moves as far as needed to keep everything on screen, so the camera stays calm while placing. Screen shake is capped at 8 px and placement shake stays small (big shakes are for the harvest and round end).

Fullscreen: F11, Alt+Enter or the HUD button; the choice is saved in `user://patchland.cfg`. The board spans the whole window while the HUD, relic strip and tray stay `Game.CONTENT_W` wide.

## Implementation notes
- Main scene `main.tscn` → `ui/game.gd` (builds all UI in code, owns `RunState`, runs `after()`/`step_q()` timed sequences like the reference).
- Tile "baking": each `TileNode` records its `draw_*` commands once per tile+rotation; Godot keeps the canvas command list until `queue_redraw()`. Windmill sails are a child node rotated each frame.
- `Board` layers: slots and fx are drawn in screen space (port of `ws()`), tiles live in a y-sorted world layer scaled by the camera.
- Board entries are Dictionaries (`{q, r, k, tile, quest, prog, qdone}`); edge results in `per` are ints (-1 none, 0 mismatch, 1 match).
- Fonts are `SystemFont`s (Bricolage Grotesque if installed, else Segoe UI/Arial) until the OFL font file is added. Colours follow the OS light/dark mode (`ui/pal.gd`).

## Testing
Run headless from the project folder, for example:
`godot --headless --path . -s res://tests/run_sim.gd -- --runs 3 --seed 1`
(on Windows, use the `_console.exe` build of Godot so output prints to the terminal). Run the simulation after any balance or rules change. A run takes ~30 s.

Rivers/railroads rule checks: `godot --headless --path . -s res://tests/features.gd` (add `-- <output folder>` without `--headless` to also save screenshots of a blocked and a legal spot). Run after any change to lines, dealing or scoring.

Visual smoke test (needs a window, not `--headless`): `godot --path . -s res://tests/screenshot.gd -- <output folder>` plays the opening, right-clicks to rotate (prints the rotation change), zooms and pans the camera, toggles fullscreen on and back, finishes round 1 and saves PNGs of each stage.

### Balance
Goals are set from bot runs. `GODOT=<console exe> tests/balance.sh [procs] [runs_per_proc]` runs `run_sim.gd --nofail` in parallel for the `greedy` bot (every slot and rotation, plus harvest look-ahead: an expert) and the `casual` bot (half the slots, 3 rotations: a person scanning the board), and prints per-round p25/median/p75 next to the goals. Targets used for the current goals: casual clears rounds 1-4 about 80-90% of the time and rounds 7-8 about 40-55%; greedy clears every early round and rounds 7-8 about 70-80%. Whole runs (stopping at a miss), with closing bonuses counted by both bots: greedy won 16 of 24, casual 9 of 24. Re-run after any scoring change.

## Backlog (not yet built)
Closing regions that bloom and cascade into neighbors; ripple scoring through neighbors that become perfect; tile transformations (water surrounded by fields becomes farmland, villages merge into towns); relics that fire in a player-chosen order; retriggers; relics that scale up over a run.
