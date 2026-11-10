extends SceneTree
## Headless bot. Plays full runs and prints per-round scores (used to set goals).
## godot --headless --path . -s res://tests/run_sim.gd -- --runs 10 --seed 1
##   --bot greedy   (default) best placement + harvest gain, all slots and rotations
##   --bot simple   placement score only, no harvest look-ahead
##   --bot casual   like simple, but only looks at about half the slots and 3 of the 6
##                  rotations each turn (a rough model of a person scanning the board)
##   --nofail       keep playing after a missed goal, to measure every round's potential
## Each run also prints a "SCORES <bot> s1,s2,..." line for aggregating parallel runs.


func _init() -> void:
	var runs := 3
	var seed0 := 1
	var bot := "greedy"
	var nofail := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size():
			seed0 = int(args[i + 1])
		elif args[i] == "--bot" and i + 1 < args.size():
			bot = args[i + 1]
		elif args[i] == "--nofail":
			nofail = true
	var reached: Array[int] = []
	reached.resize(Defs.ROUNDS + 1)
	reached.fill(0)
	var t0 := Time.get_ticks_msec()
	for n in runs:
		var res := play_run(seed0 + n, bot, nofail)
		reached[clampi(res.cleared, 0, Defs.ROUNDS)] += 1
		print("run %d (%s): cleared %d/%d, total %s  rounds: %s" % [n + 1, bot, res.cleared, Defs.ROUNDS, Defs.fmt(res.total), res.labels])
		print("SCORES %s %s" % [bot, ",".join(res.raw)])
	print("rounds cleared histogram (0..8): ", reached)
	print("done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


var bot_rng := RandomNumberGenerator.new()


func play_run(seed_val: int, bot: String, nofail: bool) -> Dictionary:
	bot_rng.seed = seed_val * 7 + 3
	var s := RunState.new()
	s.new_run(seed_val)
	var labels: Array[String] = []
	var raw: Array[String] = []
	var cleared := -1
	while true:
		while s.tiles_left > 0:
			var best := best_move(s, bot)
			if best.score <= 0 and s.redraws > 0:
				s.redraw()
				continue
			s.cur.rot = best.rot
			var res := s.place(best.q, best.r)
			if res.is_empty():
				push_error("bot picked an illegal move")
				return {"cleared": -1, "total": s.total, "labels": labels, "raw": raw}
			s.finish_placement(res.entry, res.ev)
			s.busy = false
		var h := Rules.harvest_calc(s)
		s.apply_harvest(int(round(float(h.chips) * h.mult)))
		labels.append("%s/%s" % [Defs.fmt(s.round_score), Defs.fmt(s.goal())])
		raw.append(str(s.round_score))
		if not s.cleared() and cleared < 0:
			cleared = s.round_idx
			if not nofail:
				break
		if s.is_last_round():
			break
		s.picks = 2 if s.boss != "" else 1
		for p in s.picks:
			var pool := s.draft_pool()
			if not pool.is_empty():
				s.relics.append(pool[0].id)
		s.next_round()
	if cleared < 0:
		cleared = Defs.ROUNDS
	return {"cleared": cleared, "total": s.total, "labels": labels, "raw": raw}


func best_move(s: RunState, bot: String) -> Dictionary:
	var best := {"score": -1, "q": 0, "r": 0, "rot": 0}
	var base_rot := s.cur.rot
	var cands: Array = s.cands.values()
	if bot == "casual":
		Defs.shuffle(cands, bot_rng)
		cands = cands.slice(0, maxi(2, ceili(cands.size() * 0.5)))
	for c in cands:
		var rots: Array = [0, 1, 2, 3, 4, 5]
		if bot == "casual":
			Defs.shuffle(rots, bot_rng)
			rots = rots.slice(0, 3)
		for rot in rots:
			s.cur.rot = rot
			if not Rules.can_place(s, c.q, c.r, s.cur):
				continue
			var ev := Rules.evaluate(s, c.q, c.r, s.cur)
			var score: int = ev.total
			if bot == "greedy":
				var k: Vector2i = c.k
				s.board[k] = RunState.make_entry(c.q, c.r, s.cur)
				score += Rules.harvest_calc(s).total - s.harvest_base
				s.board.erase(k)
			if score > best.score:
				best = {"score": score, "q": c.q, "r": c.r, "rot": rot}
	s.cur.rot = base_rot
	return best
