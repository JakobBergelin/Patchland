extends SceneTree
## Headless greedy bot. Plays full runs and prints per-round scores.
## godot --headless --path . -s res://tests/run_sim.gd -- --runs 10 --seed 1


func _init() -> void:
	var runs := 3
	var seed0 := 1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size():
			seed0 = int(args[i + 1])
	var reached: Array[int] = []
	reached.resize(Defs.ROUNDS + 1)
	reached.fill(0)
	var t0 := Time.get_ticks_msec()
	for n in runs:
		var res := play_run(seed0 + n)
		reached[res.cleared] += 1
		print("run %d: cleared %d/%d, total %s  rounds: %s" % [n + 1, res.cleared, Defs.ROUNDS, Defs.fmt(res.total), res.scores])
	print("rounds cleared histogram (0..8): ", reached)
	print("done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func play_run(seed_val: int) -> Dictionary:
	var s := RunState.new()
	s.new_run(seed_val)
	var scores: Array[String] = []
	while true:
		while s.tiles_left > 0:
			var best := best_move(s)
			if best.score <= 0 and s.redraws > 0:
				s.redraw()
				continue
			s.cur.rot = best.rot
			var res := s.place(best.q, best.r)
			s.finish_placement(res.entry, res.ev)
			s.busy = false
		var h := Rules.harvest_calc(s)
		s.apply_harvest(int(round(float(h.chips) * h.mult)))
		scores.append("%s/%s" % [Defs.fmt(s.round_score), Defs.fmt(s.goal())])
		if not s.cleared():
			return {"cleared": s.round_idx, "total": s.total, "scores": scores}
		if s.is_last_round():
			return {"cleared": Defs.ROUNDS, "total": s.total, "scores": scores}
		s.picks = 2 if s.boss != "" else 1
		for p in s.picks:
			var pool := s.draft_pool()
			if not pool.is_empty():
				s.relics.append(pool[0].id)
		s.next_round()
	return {}


func best_move(s: RunState) -> Dictionary:
	var best := {"score": -1, "q": 0, "r": 0, "rot": 0}
	var base_rot := s.cur.rot
	for c in s.cands.values():
		for rot in 6:
			s.cur.rot = rot
			var ev := Rules.evaluate(s, c.q, c.r, s.cur)
			var k: Vector2i = c.k
			s.board[k] = RunState.make_entry(c.q, c.r, s.cur)
			var harvest: int = Rules.harvest_calc(s).total
			s.board.erase(k)
			var score: int = ev.total + harvest - s.harvest_base
			if score > best.score:
				best = {"score": score, "q": c.q, "r": c.r, "rot": rot}
	s.cur.rot = base_rot
	return best
