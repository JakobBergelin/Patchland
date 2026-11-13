extends SceneTree
## Headless bot. Plays full runs and prints per-round scores (used to set goals).
## godot --headless --path . -s res://tests/run_sim.gd -- --runs 10 --seed 1
##   --bot greedy   (default) best placement + harvest gain, all slots and rotations
##   --bot simple   placement score only, no harvest look-ahead
##   --bot casual   like simple, but only looks at about half the slots and 3 of the 6
##                  rotations each turn (a rough model of a person scanning the board)
##   --nofail       keep playing after a missed goal, to measure every round's potential
##   --profile all|mid|starter   what the bot has unlocked (default all)
##   --season N     difficulty level (goal scale), default 1
## Each run also prints a "SCORES <bot> s1,s2,..." line for aggregating parallel runs.


func _init() -> void:
	var runs := 3
	var seed0 := 1
	var bot := "greedy"
	var nofail := false
	var profile := "all"
	var season := 1
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
		elif args[i] == "--profile" and i + 1 < args.size():
			profile = args[i + 1]
		elif args[i] == "--season" and i + 1 < args.size():
			season = int(args[i + 1])
	var reached: Array[int] = []
	reached.resize(Defs.ROUNDS + 1)
	reached.fill(0)
	var t0 := Time.get_ticks_msec()
	for n in runs:
		var res := play_run(seed0 + n, bot, nofail, profile, season)
		reached[clampi(res.cleared, 0, Defs.ROUNDS)] += 1
		print("run %d (%s): cleared %d/%d, total %s  rounds: %s" % [n + 1, bot, res.cleared, Defs.ROUNDS, Defs.fmt(res.total), res.labels])
		print("SCORES %s %s" % [bot, ",".join(res.raw)])
	print("rounds cleared histogram (0..8): ", reached)
	print("done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


var bot_rng := RandomNumberGenerator.new()


func play_run(seed_val: int, bot: String, nofail: bool, profile := "all", season := 1) -> Dictionary:
	bot_rng.seed = seed_val * 7 + 3
	var s := RunState.new()
	s.season = season
	apply_profile(s, profile)
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
		s.record_harvest(h)
		labels.append("%s/%s" % [Defs.fmt(s.round_score), Defs.fmt(s.goal())])
		raw.append(str(s.round_score))
		if not s.cleared() and cleared < 0:
			cleared = s.round_idx
			if not nofail:
				break
		if s.is_last_round():
			break
		s.mark_cleared()
		s.picks = 2 if s.boss != "" else 1
		for p in s.picks:
			var pool := s.draft_pool()
			if not pool.is_empty():
				s.relics.append(choose_relic(s, pool) if bot == "greedy" else pool[0].id)
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
			# every bot counts closing bonuses (the preview shows them to players)
			var k: Vector2i = c.k
			s.board[k] = RunState.make_entry(c.q, c.r, s.cur)
			score += s.closing_bonus(s.board[k])
			if bot == "greedy":
				score += Rules.harvest_calc(s).total - s.harvest_base
			s.board.erase(k)
			if score > best.score:
				best = {"score": score, "q": c.q, "r": c.r, "rot": rot}
	s.cur.rot = base_rot
	return best


## What the bot has unlocked: "all" (default), "starter" (a fresh profile: no
## specials, starter relics) or "mid" (the 3 ray specials and half the relics).
static func apply_profile(s: RunState, profile: String) -> void:
	if profile == "starter":
		s.allowed_specials = []
		s.allowed_relics = Unlocks.STARTER_RELICS.duplicate()
	elif profile == "mid":
		s.allowed_specials = ["windmill", "lighthouse", "belltower"]
		var ids: Array = Defs.RELICS.map(func(r): return r.id)
		s.allowed_relics = ids.slice(0, ids.size() / 2)


## Rough value of relics whose benefit doesn't show in the current harvest
## (extra tiles, redraws, placement bonuses), as a share of that harvest.
const RELIC_FLAT := {
	"carto": 0.35, "architect": 0.3, "plumb": 0.25, "pathfinder": 0.2, "almanac": 0.2, "second": 0.12,
	"herald": 0.15, "momentum": 0.15, "oldmaps": 0.15, "bellows": 0.15, "keeper": 0.15, "wild": 0.15,
	"trellis": 0.15, "hedgerows": 0.15, "clover": 0.1, "goldsmith": 0.1, "miller": 0.1, "prospector": 0.1,
	"patch": 0.1, "ferry": 0.1, "mill": 0.1, "harvest": 0.1,
}


## The expert bot picks the relic that helps its board most: the gain in the
## current harvest with the relic, plus a flat estimate for indirect relics.
static func choose_relic(s: RunState, pool: Array) -> String:
	var base: int = maxi(1, Rules.harvest_calc(s).total)
	var best_id: String = pool[0].id
	var best_v := -INF
	for r in pool:
		s.relics.append(r.id)
		var gain: float = Rules.harvest_calc(s).total - base
		s.relics.pop_back()
		var v: float = gain + base * RELIC_FLAT.get(r.id, 0.06)
		if v > best_v:
			best_v = v
			best_id = r.id
	return best_id
