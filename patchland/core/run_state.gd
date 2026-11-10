class_name RunState
extends RefCounted
## Whole-run state plus the rule-level actions (no rendering, no timing).

var rng := RandomNumberGenerator.new()
var board := {}  # Vector2i -> entry Dictionary (see Rules)
var cands := {}  # Vector2i -> {q, r, k}
var mill_count := 0

var round_idx := 0
var round_score := 0
var total := 0
var tiles_left := 0
var redraws := 0
var relics: Array[String] = []
var almanac := 0
var streak := 0
var best_streak := 0
var quests := 0
var perfects := 0
var best_harvest := 0
var survey_bonus := 0
var cur: Tile
var nxt: Tile
var busy := false
var picks := 0
var boss := ""
var harvest_base := 0
var boss_order: Array = []
## True when the current tile has no spot that keeps every river and railroad
## intact, so the "don't cut a line" rule is lifted for that tile only.
var line_rule_lifted := false


func has_relic(id: String) -> bool:
	return relics.has(id)


func goal() -> int:
	return Defs.GOALS[round_idx]


func make_tile(min_kinds := 0, plain := false) -> Tile:
	return Tile.make(rng, min_kinds, plain, relics, round_idx, {"river": has_open("river") or has_open_water(), "rail": has_open("rail")})


## True if some edge of feature `f` on the board faces an empty spot (a line is open).
## Track is only dealt while a railroad is open; otherwise railroads come as
## stations that start a new line.
func has_open(f: String) -> bool:
	for e in board.values():
		for i in 6:
			if e.tile.feat_at(i) == f and not board.has(e.k + Hex.DIRS[i]):
				return true
	return false


## True if a water edge on the board faces an empty spot, so a river could flow out of it.
func has_open_water() -> bool:
	for e in board.values():
		for i in 6:
			if e.tile.edge(i) == "water" and e.tile.feat_at(i) == "" and not board.has(e.k + Hex.DIRS[i]):
				return true
	return false


static func make_entry(q: int, r: int, tile: Tile) -> Dictionary:
	return {"q": q, "r": r, "k": Vector2i(q, r), "tile": tile, "quest": tile.quest, "prog": 1, "qdone": false}


func new_run(seed_val := -1) -> void:
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	board.clear()
	round_idx = 0
	round_score = 0
	total = 0
	relics.clear()
	almanac = 0
	streak = 0
	best_streak = 0
	quests = 0
	perfects = 0
	best_harvest = 0
	survey_bonus = 0
	picks = 0
	var ids: Array = []
	for b in Defs.BOSSES:
		ids.append(b.id)
	boss_order = Defs.shuffle(ids, rng).slice(0, Defs.BOSS_ROUNDS.size())
	board[Vector2i.ZERO] = make_entry(0, 0, make_tile(3, true))
	recompute_cands()
	start_round()


func recompute_cands() -> void:
	cands.clear()
	mill_count = 0
	for e in board.values():
		if e.tile.special == "windmill":
			mill_count += 1
		for d in Hex.DIRS:
			var k: Vector2i = e.k + d
			if not board.has(k) and not cands.has(k):
				cands[k] = {"q": k.x, "r": k.y, "k": k}


func start_round() -> void:
	round_score = 0
	var bi := Defs.BOSS_ROUNDS.find(round_idx)
	boss = boss_order[bi] if bi >= 0 else ""
	tiles_left = 12 + (2 if has_relic("carto") else 0) - (3 if boss == "short" else 0)
	redraws = 0 if boss == "fog" else 2 + (2 if has_relic("second") else 0)
	cur = make_tile()
	nxt = make_tile()
	busy = false
	refresh_line_rule()
	harvest_base = Rules.harvest_calc(self).total


func refresh_line_rule() -> void:
	line_rule_lifted = false
	if cur != null:
		line_rule_lifted = not Rules.has_legal_spot(self, cur)


func rotate_cur(dir: int) -> void:
	cur.rot = (cur.rot + (1 if dir > 0 else 5)) % 6


func redraw() -> bool:
	if busy or redraws <= 0:
		return false
	redraws -= 1
	cur = nxt
	nxt = make_tile()
	refresh_line_rule()
	return true


## Puts the current tile on the board. Scoring is applied by finish_placement().
## Returns {} (and changes nothing) if the placement would cut a railroad.
func place(q: int, r: int) -> Dictionary:
	if not Rules.can_place(self, q, r, cur):
		return {}
	var tile := cur
	var ev := Rules.evaluate(self, q, r, tile)
	var entry := make_entry(q, r, tile)
	board[entry.k] = entry
	var events: Array = Rules.resolve_rays(self, [entry]) if tile.special != "" else []
	tiles_left -= 1
	busy = true
	survey_bonus = 0
	cur = nxt
	nxt = make_tile()
	recompute_cands()
	refresh_line_rule()
	return {"entry": entry, "ev": ev, "events": events}


## Applies the placement score, streak and quest completion.
## Returns {perfect_streak, streak_lost, quests: [{e, bonus}], line: {tiles, ends, f} or {}}.
func finish_placement(entry: Dictionary, ev: Dictionary) -> Dictionary:
	round_score += ev.total
	total += ev.total
	var res := {"perfect_streak": 0, "streak_lost": false, "quests": [], "line": {}}
	# a river or railroad that now runs end to end (lake to lake, station to station)
	var f: String = entry.tile.feature()
	if f != "" and ev.feat_matches > 0:
		var net := Rules.line_network(self, entry, f)
		if net.ends >= 2:
			res.line = net
	if ev.perfect:
		streak += 1
		perfects += 1
		best_streak = maxi(best_streak, streak)
		if has_relic("almanac"):
			almanac += 1
		res.perfect_streak = streak
	elif ev.nb > 0:
		res.streak_lost = streak >= 2
		streak = 0
	for e in board.values():
		if e.quest.is_empty() or e.qdone:
			continue
		e.prog = Rules.region_size(self, e, e.quest.t)
		if e.prog >= e.quest.need:
			e.qdone = true
			var bonus: int = e.quest.need * 25 * (round_idx + 1)
			tiles_left += 2
			round_score += bonus
			total += bonus
			quests += 1
			if has_relic("surveyor"):
				survey_bonus += 3
			res.quests.append({"e": e, "bonus": bonus})
	harvest_base = Rules.harvest_calc(self).total
	return res


func apply_harvest(points: int) -> void:
	round_score += points
	total += points
	best_harvest = maxi(best_harvest, points)


func cleared() -> bool:
	return round_score >= goal()


func is_last_round() -> bool:
	return round_idx == Defs.ROUNDS - 1


func draft_pool() -> Array:
	var pool: Array = []
	for r in Defs.RELICS:
		if not has_relic(r.id):
			pool.append(r)
	return Defs.shuffle(pool, rng).slice(0, 3)


func next_round() -> void:
	round_idx += 1
	start_round()
