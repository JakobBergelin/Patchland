class_name Rules
## Pure scoring rules. Board entries are Dictionaries:
## {q, r, k: Vector2i, tile: Tile, quest: Dictionary, prog: int, qdone: bool}
## Edge results in `per` are ints: -1 no neighbor, 0 mismatch, 1 match.


static func is_match(s: RunState, a: String, b: String) -> bool:
	if a == b:
		return true
	if s.has_relic("wild") and (a == "meadow" or b == "meadow"):
		return true
	if s.has_relic("ferry") and ((a == "water" and b == "village") or (a == "village" and b == "water")):
		return true
	return false


static func chip_val(s: RunState, t: String) -> int:
	if (s.boss == "drought" and t == "water") or (s.boss == "blight" and t == "forest") or (s.boss == "lean" and t == "village"):
		return 0
	var v: int = Defs.TER[t].chips
	if t == "forest" and s.has_relic("saw"):
		v += 4
	if t == "village" and s.has_relic("falu"):
		v += 8
	return v


static func land_value(s: RunState, e: Dictionary) -> int:
	var c := 0
	var k: Vector2i = e.k
	for i in 6:
		var n = s.board.get(k + Hex.DIRS[i])
		if n == null:
			continue
		var m: String = e.tile.edge(i)
		if is_match(s, m, n.tile.edge((i + 3) % 6)):
			c += chip_val(s, m)
	return c


static func special_len(s: RunState, tile: Tile) -> int:
	if tile.special == "belltower" and s.has_relic("rope"):
		return 2
	return Defs.SPECIALS[tile.special].len


static func ray_mult_per(s: RunState) -> int:
	return 2 if s.has_relic("keeper") else 1


## Fires every special in `starts`, chaining into specials they hit.
## Returns events: [{src, rays: [{d, hits: [{e, v}]}], chips, rep}]
static func resolve_rays(s: RunState, starts: Array) -> Array:
	var queued := {}
	var queue: Array = []
	var events: Array = []
	for st in starts:
		if not queued.has(st.k):
			queued[st.k] = true
			queue.append(st)
	while not queue.is_empty():
		var e: Dictionary = queue.pop_front()
		var times := 2 if e.tile.special == "windmill" and s.has_relic("miller") else 1
		for rep in times:
			var ev := {"src": e, "rays": [], "chips": 0, "rep": rep}
			var length := special_len(s, e.tile)
			for d in e.tile.special_dirs():
				var hits: Array = []
				for stp in range(1, length + 1):
					var n = s.board.get(e.k + Hex.DIRS[d] * stp)
					if n == null:
						break
					var v := land_value(s, n)
					hits.append({"e": n, "v": v})
					ev["chips"] += v
					if n.tile.special != "" and not queued.has(n.k):
						queued[n.k] = true
						queue.append(n)
				if not hits.is_empty():
					ev["rays"].append({"d": d, "hits": hits})
			events.append(ev)
	return events


static func region_size(s: RunState, start: Dictionary, t: String) -> int:
	var seen := {start.k: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var e: Dictionary = stack.pop_back()
		for i in 6:
			if e.tile.edge(i) != t:
				continue
			var nk: Vector2i = e.k + Hex.DIRS[i]
			if seen.has(nk):
				continue
			var n = s.board.get(nk)
			if n == null or n.tile.edge((i + 3) % 6) != t:
				continue
			seen[nk] = true
			stack.append(n)
	return seen.size()


static func harvest_calc(s: RunState) -> Dictionary:
	var regions: Array = []
	for t in Defs.TKEYS:
		var seen := {}
		for e in s.board.values():
			if seen.has(e.k) or not e.tile.base.has(t):
				continue
			seen[e.k] = true
			var comp: Array = []
			var stack: Array = [e]
			while not stack.is_empty():
				var x: Dictionary = stack.pop_back()
				comp.append(x)
				for i in 6:
					if x.tile.edge(i) != t:
						continue
					var nk: Vector2i = x.k + Hex.DIRS[i]
					if seen.has(nk):
						continue
					var n = s.board.get(nk)
					if n == null or n.tile.edge((i + 3) % 6) != t:
						continue
					seen[nk] = true
					stack.append(n)
			if comp.size() >= 2:
				var per := chip_val(s, t) * (2 if t == "field" and s.has_relic("granary") else 1)
				var m := int(comp.size() / 3) + (3 if t == "forest" and s.has_relic("oak") and comp.size() >= 6 else 0)
				regions.append({"t": t, "tiles": comp, "n": comp.size(), "per": per, "chips": per * comp.size(), "mult": m})
	var chips := 0
	var mult := 1
	for r in regions:
		chips += r.chips
		mult += r.mult
	if s.has_relic("almanac"):
		mult += s.almanac
	var specials: Array = []
	for e in s.board.values():
		if e.tile.special != "":
			specials.append(e)
	var events := resolve_rays(s, specials)
	var fired := 0
	for ev in events:
		chips += ev.chips
		if not ev.rays.is_empty():
			fired += 1
	mult += fired * ray_mult_per(s)
	return {"regions": regions, "events": events, "chips": chips, "mult": mult, "total": chips * mult}


## Scores placing `tile` at (q, r) without changing the board.
static func evaluate(s: RunState, q: int, r: int, tile: Tile) -> Dictionary:
	var k := Vector2i(q, r)
	var chips := 0
	var nb := 0
	var matches := 0
	var water := 0
	var field := false
	var kinds := {}
	var per: Array[int] = []
	var edge_chips: Array[int] = [0, 0, 0, 0, 0, 0]
	for i in 6:
		var n = s.board.get(k + Hex.DIRS[i])
		if n == null:
			per.append(-1)
			continue
		nb += 1
		var mine := tile.edge(i)
		var ok := is_match(s, mine, n.tile.edge((i + 3) % 6))
		per.append(1 if ok else 0)
		if not ok:
			continue
		matches += 1
		kinds[mine] = true
		var c := chip_val(s, mine)
		edge_chips[i] = c
		chips += c
		if mine == "water":
			water += 1
		if mine == "field":
			field = true
	var events: Array = []
	var ray_chips := 0
	var ray_fired := 0
	if tile.special != "":
		var temp := {"q": q, "r": r, "k": k, "tile": tile, "quest": {}, "prog": 0, "qdone": false}
		s.board[k] = temp
		events = resolve_rays(s, [temp])
		s.board.erase(k)
		for ev in events:
			ray_chips += ev.chips
			if not ev.rays.is_empty():
				ray_fired += 1
	var perfect := nb >= 2 and matches == nb
	if matches == 0 and ray_chips == 0:
		return {"chips": 0, "mult": 0, "total": 0, "nb": nb, "matches": matches, "per": per, "perfect": false,
			"edge_chips": edge_chips, "chip_add": 0, "adds": [], "muls": [], "base_mult": 0, "events": events, "ray_chips": 0}
	var adds: Array = []
	if s.has_relic("mill") and water > 0:
		adds.append(["Watermill", water])
	if s.has_relic("harvest") and field:
		adds.append(["Harvest fair", 3])
	if s.has_relic("patch") and kinds.size() >= 3:
		adds.append(["Patchwork", 4])
	if s.has_relic("almanac") and s.almanac > 0:
		adds.append(["Almanac", s.almanac])
	if s.survey_bonus > 0:
		adds.append(["Surveyor", s.survey_bonus])
	if perfect and s.streak > 0:
		adds.append(["Streak", s.streak])
	if ray_fired > 0:
		adds.append(["Ray chain" if ray_fired > 1 else "Rays", ray_fired * ray_mult_per(s)])
	var chip_add := 40 if s.has_relic("mono") and tile.kinds().size() == 1 else 0
	chips += chip_add + ray_chips
	var mult := 1 + matches
	for a in adds:
		mult += a[1]
	var muls: Array = []
	if perfect:
		muls.append(["Perfect", 3 if s.has_relic("plumb") else 2])
	if tile.gold:
		muls.append(["Golden", 2])
	for m in muls:
		mult *= m[1]
	return {"chips": chips, "mult": mult, "total": chips * mult, "nb": nb, "matches": matches, "per": per, "perfect": perfect,
		"edge_chips": edge_chips, "chip_add": chip_add, "adds": adds, "muls": muls, "base_mult": 1 + matches, "events": events, "ray_chips": ray_chips}


static func count_hits(events: Array) -> int:
	var n := 0
	for ev in events:
		for ray in ev.rays:
			n += ray.hits.size()
	return n
