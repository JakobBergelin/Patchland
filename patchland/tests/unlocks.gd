extends SceneTree
## Unlock rules (headless): godot --headless --path . -s res://tests/unlocks.gd

const CFG := "user://test_unlocks.cfg"
var failures := 0


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


static func mk(base: Array, feats := {}) -> Tile:
	var t := Tile.mono("meadow", 1)
	t.id = randi()
	for i in 6:
		t.base[i] = base[i]
	for i in feats:
		t.feat[i] = feats[i]
	return t


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

	# --- fresh profile ---
	check(Unlocks.specials(CFG).is_empty(), "no special tiles unlocked at first")
	check(Unlocks.relics(CFG).size() == Unlocks.STARTER_RELICS.size(), "only the %d starter relics at first" % Unlocks.STARTER_RELICS.size())
	check(Defs.SKEYS.size() == 10 and Defs.RELICS.size() == 38, "content.tres loads 10 special tiles and 38 relics")
	var pr := Unlocks.progress(CFG)
	check(pr == Vector2i(Unlocks.STARTER_RELICS.size(), Defs.SKEYS.size() + Defs.RELICS.size()), "progress counts starters: %s" % pr)
	check(Unlocks.LIST.size() + Unlocks.STARTER_RELICS.size() == pr.y, "every special and relic is either a starter or has an achievement")

	# --- dealing and drafting respect the allowed lists ---
	var s := RunState.new()
	s.allowed_specials = []
	s.allowed_relics = Unlocks.relics(CFG)
	s.new_run(4)
	var specials_seen := 0
	for n in 3000:
		if s.make_tile().special != "":
			specials_seen += 1
	check(specials_seen == 0, "no specials dealt while none are unlocked")
	s.allowed_specials = ["windmill"]
	var kinds := {}
	for n in 3000:
		var t := s.make_tile()
		if t.special != "":
			kinds[t.special] = true
	check(kinds.keys() == ["windmill"], "only unlocked specials are dealt (%s)" % [kinds.keys()])
	var offered := {}
	for n in 200:
		for r in s.draft_pool():
			offered[r.id] = true
	check(offered.keys().all(func(id): return Unlocks.STARTER_RELICS.has(id)), "the relic draft only offers unlocked relics")
	var all_s := RunState.new()
	check(all_s.allowed_specials.size() == Defs.SKEYS.size() and all_s.allowed_relics.size() == Defs.RELICS.size(), "by default (sims, test runs) everything is allowed")

	# --- every achievement unlocks when its stat is reached, once ---
	var r := RunState.new()
	r.new_run(1)
	check(Unlocks.check(CFG, r).is_empty(), "a fresh run unlocks nothing")
	for a in Unlocks.LIST:
		r.set(a.stat, maxi(int(r.get(a.stat)), a.need))  # several share a stat: keep the highest
	var got := Unlocks.check(CFG, r)
	check(got.size() == Unlocks.LIST.size(), "all %d achievements can unlock (%d)" % [Unlocks.LIST.size(), got.size()])
	check(Unlocks.check(CFG, r).is_empty(), "each unlocks only once")
	check(Unlocks.specials(CFG).size() == Defs.SKEYS.size() and Unlocks.relics(CFG).size() == Defs.RELICS.size(), "after that everything is unlocked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	r.new_run(1)
	r.rounds_cleared = 1
	var one := Unlocks.check(CFG, r)
	check(one.size() == 1 and one[0].id == "windmill", "clearing round 1 unlocks the windmill")

	# --- stats are tracked during play ---
	var p := RunState.new()
	p.new_run(2)
	p.board.clear()
	p.board[Vector2i(-1, 1)] = RunState.make_entry(-1, 1, mk(["water", "field", "water", "water", "forest", "meadow"]))
	p.board[Vector2i(0, 1)] = RunState.make_entry(0, 1, mk(["forest", "forest", "field", "meadow", "meadow", "field"], {3: "river", 4: "river"}))
	var wet := mk(["field", "water", "meadow", "forest", "meadow", "field"])
	p.board[Vector2i(-1, 2)] = RunState.make_entry(-1, 2, wet)
	p.finish_placement(p.board[Vector2i(-1, 2)], Rules.evaluate(p, -1, 2, wet))
	check(p.rivers_closed == 1, "closing a river counts for the Lighthouse")
	p.boss = "drought"
	p.round_idx = 2
	p.mark_cleared()
	check(p.rounds_cleared == 3 and p.bosses_beaten == 1, "clearing a boss round counts rounds and bosses")
	var fake := {"perfect": true, "nb": 2, "total": 0, "events": [{"rays": [1]}, {"rays": [1]}], "feat_matches": 0}
	var gt := mk(["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"])
	gt.gold = true
	p.board[Vector2i(5, 5)] = RunState.make_entry(5, 5, gt)
	p.finish_placement(p.board[Vector2i(5, 5)], fake)
	check(p.gold_perfects == 1 and p.chains == 1, "golden Perfects and ray chains are counted")

	print("FAILURES: %d" % failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	quit(1 if failures else 0)
