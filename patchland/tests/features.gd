extends SceneTree
## Rivers / railroads check. Builds a board by hand, asserts the rules, and (when
## run with a window) saves screenshots of a blocked and a legal spot.
## godot --path . -s res://tests/features.gd -- <output folder>
## godot --headless --path . -s res://tests/features.gd   (asserts only)

var failures := 0


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


## base: six terrains in edge order (E, NE, NW, W, SW, SE); feats: {edge: feature}
static func mk(base: Array, feats := {}) -> Tile:
	var t := Tile.mono("meadow", randi() % 100000)
	t.id = randi()
	for i in 6:
		t.base[i] = base[i]
	for i in feats:
		t.feat[i] = feats[i]
	return t


func build(s: RunState) -> void:
	s.board.clear()
	var put := func(q: int, r: int, t: Tile):
		s.board[Vector2i(q, r)] = RunState.make_entry(q, r, t)
	# railroad: station (0,0) -> junction (1,0) -> station (2,0); the junction's SE end is open
	put.call(0, 0, mk(["village", "village", "meadow", "forest", "forest", "village"], {0: "rail"}))
	put.call(1, 0, mk(["field", "meadow", "meadow", "field", "forest", "field"], {3: "rail", 0: "rail", 5: "rail"}))
	put.call(2, 0, mk(["meadow", "field", "village", "village", "village", "meadow"], {3: "rail"}))
	# river: flows out of a water edge of (-1,1) through (0,1), and runs on SW into the open
	put.call(-1, 1, mk(["water", "field", "water", "water", "forest", "meadow"]))
	put.call(0, 1, mk(["forest", "forest", "field", "meadow", "meadow", "field"], {3: "river", 4: "river"}))
	s.recompute_cands()
	s.refresh_line_rule()
	s.harvest_base = Rules.harvest_calc(s).total


func region_of(h: Dictionary, t: String):
	for r in h.regions:
		if r.t == t:
			return r
	return null


func _run() -> void:
	var s := RunState.new()
	s.new_run(5)
	build(s)
	var plain := mk(["meadow", "meadow", "forest", "forest", "field", "field"])

	# --- ends ---
	check(s.board[Vector2i(0, 0)].tile.is_station(), "one-edge rail tile is a station")
	check(not s.board[Vector2i(1, 0)].tile.is_station(), "junction is not a station")
	check(Rules.feat_link(s.board[Vector2i(0, 1)].tile, 3, s.board[Vector2i(-1, 1)].tile) == "river", "a river flowing out of a water edge is linked (no start tile)")

	# --- railroads can't be cut ---
	check(not Rules.can_place(s, 1, 1, plain), "plain tile against an open rail end is blocked")
	var before := s.board.size()
	s.cur = plain
	check(s.place(1, 1).is_empty() and s.board.size() == before, "RunState.place refuses a blocked spot")
	var track := mk(["meadow", "field", "meadow", "meadow", "forest", "forest"], {2: "rail", 5: "rail"})
	check(Rules.can_place(s, 1, 1, track), "track that meets the open end is legal")
	var ev := Rules.evaluate(s, 1, 1, track)
	check(ev.feat_matches == 1 and ev.feat_sum == Defs.FEAT.rail.chips, "linking one rail edge scores +%d chips, +1 mult" % Defs.FEAT.rail.chips)
	var cut := mk(["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"], {0: "rail", 3: "rail"})
	check(not Rules.line_breaks(s, 3, 0, cut).is_empty(), "track running into a plain edge is blocked")
	var wrong := mk(["meadow", "field", "meadow", "meadow", "forest", "forest"], {2: "river", 5: "river"})
	check(not Rules.can_place(s, 1, 1, wrong), "a river can't continue a railroad")

	# --- rivers can't be cut either ---
	check(not Rules.can_place(s, -1, 2, plain), "plain tile against an open river end is blocked")
	var through := mk(["field", "meadow", "meadow", "forest", "meadow", "field"], {1: "river", 4: "river"})
	check(Rules.can_place(s, -1, 2, through), "river piece that meets the open end is legal")
	var rev := Rules.evaluate(s, -1, 2, through)
	check(rev.feat_matches == 1 and rev.feat_sum == Defs.FEAT.river.chips, "linking one river edge scores +%d chips" % Defs.FEAT.river.chips)
	var watery := mk(["field", "water", "meadow", "forest", "meadow", "field"])
	check(Rules.can_place(s, -1, 2, watery), "a water edge can take the open river end (it flows into water)")
	var wev := Rules.evaluate(s, -1, 2, watery)
	check(wev.per[1] == 1 and wev.edge_chips[1] == Defs.TER.water.chips and wev.feat_matches == 0,
		"river into water is a matched edge, scored once as water (+%d chips, +1 mult)" % Defs.TER.water.chips)
	check(wev.perfect, "so a river mouth doesn't break a perfect placement")
	var lv_tile: Dictionary = s.board[Vector2i(0, 1)]
	s.board[Vector2i(-1, 2)] = RunState.make_entry(-1, 2, watery)
	check(Rules.land_value(s, lv_tile) >= Defs.TER.water.chips, "ray hits score the mouth as a water match too")
	s.board.erase(Vector2i(-1, 2))
	var into_rail := mk(["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"], {0: "river", 3: "river"})
	check(not Rules.line_breaks(s, 3, 0, into_rail).is_empty(), "a river can't run into a station's plain edge")

	# --- harvest: only lines that run end to end ---
	var h := Rules.harvest_calc(s)
	var rail_r = region_of(h, "rail")
	check(rail_r != null and rail_r.ends == 2 and rail_r.n == 3, "station-to-station railroad scores in the harvest")
	check(rail_r != null and rail_r.mult == 1 + 2, "line mult = tiles/3 + 1 per end")
	check(region_of(h, "river") == null, "a river with only one water end does not score yet")
	s.board[Vector2i(-1, 2)] = RunState.make_entry(-1, 2, mk(["meadow", "water", "meadow", "forest", "field", "field"]))
	var river_r = region_of(Rules.harvest_calc(s), "river")
	check(river_r != null and river_r.ends == 2 and river_r.n == 1 and river_r.mult == 2, "a river that reaches water at both ends scores in the harvest")
	s.board.erase(Vector2i(2, 0))
	check(region_of(Rules.harvest_calc(s), "rail") == null, "a railroad without two stations does not score")
	build(s)

	# --- never stuck ---
	var hog := mk(["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"], {0: "rail", 1: "rail", 2: "rail", 3: "rail", 4: "rail", 5: "rail"})
	s.cur = hog
	s.refresh_line_rule()
	check(s.line_rule_lifted == not Rules.has_legal_spot(s, hog), "rule lifted exactly when no legal spot exists")

	# --- dealing: pieces only while a line is open ---
	check(s.has_open("rail") and s.has_open("river"), "this board has an open railroad and an open river")
	var deal := func(state: RunState) -> Dictionary:
		var c := {"rail_piece": 0, "station": 0, "river_piece": 0, "river_end": 0}
		for n in 1500:
			var t := state.make_tile()
			if t.is_station():
				c.station += 1
			elif t.feature() == "rail":
				c.rail_piece += 1
			elif t.feature() == "river":
				c.river_piece += 1
				if t.is_end("river"):
					c.river_end += 1
		return c
	var open_c: Dictionary = deal.call(s)
	check(open_c.rail_piece > 0 and open_c.river_piece > 0 and open_c.river_end == 0, "open lines: track and river pieces are dealt, no river start tiles %s" % open_c)
	# a board with nothing open: one tile, no water, no features
	var closed := RunState.new()
	closed.new_run(9)
	closed.board.clear()
	closed.board[Vector2i.ZERO] = RunState.make_entry(0, 0, mk(["meadow", "forest", "field", "village", "meadow", "forest"]))
	closed.recompute_cands()
	check(not closed.has_open("rail") and not closed.has_open("river") and not closed.has_open_water(), "a dry board with no lines has nothing open")
	var closed_c: Dictionary = deal.call(closed)
	check(closed_c.rail_piece == 0 and closed_c.river_piece == 0 and closed_c.station > 0,
		"nothing open: railroads come only as stations, no rivers %s" % closed_c)
	# water alone is enough for rivers
	closed.board[Vector2i.ZERO].tile.base[2] = "water"
	check(closed.has_open_water(), "an open water edge counts")
	var wet_c: Dictionary = deal.call(closed)
	check(wet_c.river_piece > 0 and wet_c.rail_piece == 0, "open water: river pieces are dealt %s" % wet_c)

	# --- random tiles ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var counts := {"river": 0, "rail": 0, "stations": 0, "mixed": 0, "feature_tiles": 0}
	var bad := []
	for n in 4000:
		var t := Tile.make(rng)
		var f := t.feature()
		if f == "":
			continue
		counts[f] += 1
		counts.feature_tiles += 1
		if t.kinds().size() >= 2:
			counts.mixed += 1
		if t.special != "":
			bad.append("feature on a special")
		if t.is_station():
			counts.stations += 1
			if t.base[t.feat.find("rail")] != "village":
				bad.append("station off a village edge")
		elif f == "river" and t.is_end("river"):
			bad.append("river start tile")
		for i in 6:
			if t.feat[i] != "" and t.base[i] == "water":
				bad.append("feature edge on water")
	print("4000 tiles: ", counts)
	check(bad.is_empty(), "stations on village edges, no river start tiles, no features on water or specials %s" % [bad.slice(0, 3)])
	check(counts.mixed > counts.feature_tiles * 0.7, "most river/railroad tiles have more than one biome (%d of %d)" % [counts.mixed, counts.feature_tiles])

	# --- screenshots (skipped headless) ---
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and args.size() > 0:
		await _shots(args[0])
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)


func _shots(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game: Game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game.close_overlay()
	game.started = true
	build(game.S)
	# let the river run into water at its other end too, so both kinds of line are complete
	game.S.board[Vector2i(-1, 2)] = RunState.make_entry(-1, 2, mk(["meadow", "water", "meadow", "forest", "field", "field"]))
	game.S.recompute_cands()
	game.board.clear_tiles()
	game.board.sync_tiles(game.S.board)
	game.board.snap_cam = true
	game.S.cur = mk(["meadow", "meadow", "forest", "forest", "field", "field"])
	game.set_sel(game.S.cands[Vector2i(1, 1)], true)
	game.update_all()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join("f1_blocked.png"))
	game.S.cur = mk(["meadow", "field", "field", "meadow", "forest", "forest"], {2: "rail", 4: "rail"})
	game.set_sel(game.S.cands[Vector2i(1, 1)], true)
	game.update_all()
	# rotate with right clicks until the track meets the open end
	for k in 6:
		if Rules.can_place(game.S, 1, 1, game.S.cur):
			break
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		mb.pressed = true
		mb.position = game.board.global_position + game.board.to_s(1, 1)
		mb.global_position = mb.position
		root.push_input(mb)
		await process_frame
		await process_frame
	check(Rules.can_place(game.S, 1, 1, game.S.cur), "right-click rotation found the legal orientation")
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join("f2_legal.png"))
	print("saved feature screenshots")
