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
- 8 rounds, goals `[1500, 5000, 12000, 35000, 75000, 110000, 240000, 420000]`. Bosses on rounds 3, 6 and 8; beating one gives two relic picks.
- 20 relics, listed in the reference's `RELICS` array.

## Port order
1. Core rules + headless bot simulation matching the reference's results.
2. Tile art and board rendering.
3. Input (tap/click to preview and place, rotate, redraw, keyboard), HUD and tray.
4. Placement and harvest scoring sequences with all juice.
5. Overlays, saving best score, settings (mute).
6. Steam (GodotSteam), achievements.

## Controls
Hover a dashed slot to preview, left click places. **Right click rotates the tile clockwise** (shift + right click: counter-clockwise), on the board or on the tray tile. Scroll wheel, R/E/Q, the Rotate button and clicking the tray tile also rotate. X redraws, arrows cycle slots, Enter/Space places, M mutes. Clicking during the harvest speeds it up.

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

Visual smoke test (needs a window, not `--headless`): `godot --path . -s res://tests/screenshot.gd -- <output folder>` plays the opening, right-clicks to rotate (prints the rotation change), finishes round 1 and saves PNGs of each stage.

## Backlog (not yet built)
Closing regions that bloom and cascade into neighbors; ripple scoring through neighbors that become perfect; tile transformations (water surrounded by fields becomes farmland, villages merge into towns); relics that fire in a player-chosen order; retriggers; relics that scale up over a run.
