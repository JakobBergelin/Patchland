extends SceneTree
## New special tiles and relics do what they say (headless):
## godot --headless --path . -s res://tests/content.gd

var failures := 0


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


static func mk(base: Array, special := "") -> Tile:
	var t := Tile.mono("meadow", 1)
	t.id = randi()
	for i in 6:
		t.base[i] = base[i]
	t.special = special
	return t


static func fresh(relics: Array = []) -> RunState:
	var s := RunState.new()
	s.new_run(3)
	s.board.clear()
	for r in relics:
		s.relics.append(r)
	return s


func put(s: RunState, q: int, r: int, t: Tile) -> void:
	s.board[Vector2i(q, r)] = RunState.make_entry(q, r, t)


func region(h: Dictionary, t: String):
	for r in h.regions:
		if r.t == t:
			return r
	return null


func _run() -> void:
	var F6 := ["field", "field", "field", "field", "field", "field"]
	var M6 := ["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"]

	# --- landmarks ---
	var s := fresh()
	put(s, 0, 0, mk(F6))
	put(s, 1, 0, mk(F6))
	var plain_per: int = region(Rules.harvest_calc(s), "field").per
	put(s, 0, 1, mk(F6, "scarecrow"))
	var fr = region(Rules.harvest_calc(s), "field")
	check(fr.landmarks == 1 and fr.per == plain_per * 2, "a Scarecrow doubles its field area's yield (%d -> %d)" % [plain_per, fr.per])
	s.relics.append("stonemason")
	check(region(Rules.harvest_calc(s), "field").per == plain_per * 3, "Stonemason makes it triple")
	var s2 := fresh()
	put(s2, 0, 0, mk(M6))
	put(s2, 1, 0, mk(M6, "scarecrow"))
	check(region(Rules.harvest_calc(s2), "meadow").get("landmarks", 0) == 0, "a landmark only boosts its own land type")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lm := mk(["water", "water", "forest", "meadow", "village", "village"], "market")
	lm.fit_special(rng)
	check(lm.base.count("village") >= 3, "landmark tiles are dealt with at least 3 edges of their land")

	# --- crossroads ---
	var c := fresh()
	put(c, 0, 0, mk(["forest", "water", "village", "field", "meadow", "water"]))
	var cr := mk(M6, "crossroads")
	var ev := Rules.evaluate(c, 1, 0, cr)
	check(ev.matches == 1, "Crossroads matches any land")
	put(c, 2, 0, mk(["village", "village", "village", "water", "village", "village"]))
	var ev2 := Rules.evaluate(c, 1, 0, cr)
	check(ev2.matches == 2 and ev2.perfect, "Crossroads between two different lands is a Perfect")

	# --- standing stones ---
	var st := fresh()
	put(st, 0, 0, mk(M6, "stones"))
	put(st, 1, 0, mk(M6, "windmill"))
	put(st, 2, 0, mk(M6, "market"))
	var h := Rules.harvest_calc(st)
	var stones_x: Array = h.extras.filter(func(x): return x[0] == "Standing stones")
	check(stones_x.size() == 1 and stones_x[0][1] == 3, "Standing stones add +1 multiplier per special tile (3)")

	# --- matching relics ---
	var t := fresh(["trellis"])
	check(Rules.is_match(t, "field", "meadow") and not Rules.is_match(fresh(), "field", "meadow"), "Trellis: field and meadow match")
	check(Rules.is_match(fresh(["hedgerows"]), "forest", "field"), "Hedgerows: field and forest match")

	# --- placement relics ---
	var cp := fresh(["compost"])
	put(cp, 0, 0, mk(["meadow", "forest", "forest", "meadow", "forest", "forest"]))
	put(cp, 2, 0, mk(F6))
	var cev := Rules.evaluate(cp, 1, 0, mk(["water", "meadow", "meadow", "meadow", "meadow", "meadow"]))
	check(cev.chip_add == 2, "Compost: +2 yield for each edge that doesn't match")
	var gs := fresh(["clover"])
	put(gs, 0, 0, mk(M6))
	var g := mk(M6)
	g.gold = true
	var gev := Rules.evaluate(gs, 1, 0, g)
	check(gev.muls.any(func(m): return m[0] == "Golden" and m[1] == 3), "Lucky clover: golden tiles ×3")
	var mo := fresh(["momentum"])
	mo.streak = 3
	put(mo, 0, 0, mk(M6))
	put(mo, 0, 1, mk(M6))
	var mev := Rules.evaluate(mo, 1, 0, mk(M6))
	check(mev.adds.any(func(a): return a[0] == "Streak" and a[1] == 6), "Momentum: streak counts double")
	var pr := fresh(["prospector"])
	pr.quests = 4
	put(pr, 0, 0, mk(M6))
	check(Rules.evaluate(pr, 1, 0, mk(M6)).adds.any(func(a): return a[0] == "Prospector" and a[1] == 4), "Prospector: +1 multiplier per quest this run")

	# --- bonus relics ---
	var b := fresh()
	b.round_idx = 4  # a mid-run goal so rounding to tens doesn't hide the ×3
	var net := {"f": "rail", "tiles": [1, 2, 3], "ends": 2}
	var base_rail := Rules.close_bonus(b, net)
	b.relics.append("railway")
	check(Rules.close_bonus(b, net) >= base_rail * 3 - 10, "Railway company: closing a railroad pays ×3")
	var fb := fresh(["fence"])
	check(Rules.region_bonus(fb, 6) >= Rules.region_bonus(fresh(), 6) * 2 - 10, "Fence builder: area bonus ×2")

	# --- harvest relics ---
	var hv := fresh(["fishing", "junction", "jeweler"])
	hv.rivers_closed = 2
	hv.rails_closed = 3
	var gt := mk(M6)
	gt.gold = true
	put(hv, 0, 0, gt)
	var hx: Array = Rules.harvest_calc(hv).extras
	var names: Array = hx.map(func(x): return "%s %d" % [x[0], x[1]])
	check(names.has("Fishing village 2") and names.has("Junction 3") and names.has("Jeweler 2"), "Fishing village, Junction and Jeweler add harvest multiplier %s" % [names])

	# --- round start relics ---
	var rs := RunState.new()
	rs.new_run(8)
	rs.relics.append("herald")
	rs.round_idx = 2
	rs.boss_order = ["drought", "fog", "lean"]
	rs.start_round()
	check(rs.boss == "drought" and rs.tiles_left == Defs.TILES_PER_ROUND + 3, "Herald: +3 tiles in boss rounds")
	var om := RunState.new()
	om.new_run(9)
	om.relics.append("oldmaps")
	om.start_round()
	check(om.cur.special != "", "Old maps: the first tile of the round is special (%s)" % om.cur.special)
	var pf := RunState.new()
	pf.new_run(10)
	pf.relics.append("pathfinder")
	pf.big_closes = 5
	pf.start_round()
	check(pf.tiles_left == Defs.TILES_PER_ROUND + 3, "Pathfinder: +1 tile per big closed area, up to +3")

	# --- rarity draft ---
	var dr := RunState.new()
	dr.new_run(11)
	var counts := [0, 0, 0]
	for n in 600:
		for r in dr.draft_pool():
			counts[r.rarity] += 1
	var per_relic := [0.0, 0.0, 0.0]
	var sizes := [0, 0, 0]
	for r in Defs.RELICS:
		sizes[r.rarity] += 1
	for i in 3:
		per_relic[i] = float(counts[i]) / sizes[i]
	check(per_relic[0] > per_relic[1] and per_relic[1] > per_relic[2], "Common relics are offered most and Heirloom least (per relic: %s)" % [per_relic.map(func(x): return snappedf(x, 0.1))])

	# --- seasons ---
	var se := RunState.new()
	se.new_run(1)
	var g1 := se.goal()
	se.season = 3
	check(se.goal() > g1, "a higher Season raises the goal (%d -> %d)" % [g1, se.goal()])

	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)
