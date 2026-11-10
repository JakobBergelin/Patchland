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


## Chips for a linked river/railroad edge. Drought dries up rivers too.
static func feat_val(s: RunState, f: String) -> int:
	if s.boss == "drought" and f == "river":
		return 0
	return Defs.FEAT[f].chips


## How edge i of tile `a` meets edge (i+3)%6 of neighbour `b`:
## returns the feature linked across it ("river" / "rail") or "".
## Same feature on both sides links; a river also links straight into a water edge
## (rivers flow out of and into water, no special start tile needed).
static func feat_link(a: Tile, i: int, b: Tile) -> String:
	var o := (i + 3) % 6
	var fa := a.feat_at(i)
	var fb := b.feat_at(o)
	if fa != "" and fa == fb:
		return fa
	if fa == "river" and fb == "" and b.edge(o) == "water":
		return "river"
	if fb == "river" and fa == "" and a.edge(i) == "water":
		return "river"
	return ""


## True if a river on one side runs into a plain water edge on the other (a river
## mouth). That edge counts as a matched land edge, scored as water.
static func is_mouth(a: Tile, i: int, b: Tile) -> bool:
	var o := (i + 3) % 6
	var fa := a.feat_at(i)
	var fb := b.feat_at(o)
	return (fa == "river" and fb == "" and b.edge(o) == "water") or (fb == "river" and fa == "" and a.edge(i) == "water")


## True if the shared edge leaves a feature dangling (a cut line).
static func feat_cut(a: Tile, i: int, b: Tile) -> bool:
	var fa := a.feat_at(i)
	var fb := b.feat_at((i + 3) % 6)
	if fa == "" and fb == "":
		return false
	return feat_link(a, i, b) == ""


## Matched land edges plus linked feature edges of an entry (what a ray hit scores).
static func land_value(s: RunState, e: Dictionary) -> int:
	var c := 0
	var k: Vector2i = e.k
	for i in 6:
		var n = s.board.get(k + Hex.DIRS[i])
		if n == null:
			continue
		if is_mouth(e.tile, i, n.tile):
			c += chip_val(s, "water")  # a river mouth matches as water
			continue
		var m: String = e.tile.edge(i)
		if is_match(s, m, n.tile.edge((i + 3) % 6)):
			c += chip_val(s, m)
		var f := feat_link(e.tile, i, n.tile)
		if f != "":
			c += feat_val(s, f)
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


## The river or railroad network of feature `f` through `start`:
## {tiles, ends, open, f}: ends counts stations (rail) or places where the river
## runs into water; open counts feature edges still facing an empty spot.
## A line is closed when open == 0 and ends >= 2.
static func line_network(s: RunState, start: Dictionary, f: String) -> Dictionary:
	var seen := {start.k: true}
	var stack: Array = [start]
	var tiles: Array = []
	var ends := 0
	var open := 0
	while not stack.is_empty():
		var e: Dictionary = stack.pop_back()
		tiles.append(e)
		if f == "rail" and e.tile.is_station():
			ends += 1
		for i in 6:
			if e.tile.feat_at(i) != f:
				continue
			var nk: Vector2i = e.k + Hex.DIRS[i]
			var n = s.board.get(nk)
			if n == null:
				open += 1
				continue
			if f == "river" and n.tile.feat_at((i + 3) % 6) == "" and n.tile.edge((i + 3) % 6) == "water":
				ends += 1  # flows into water
				continue
			if seen.has(nk) or n.tile.feat_at((i + 3) % 6) != f:
				continue
			seen[nk] = true
			stack.append(n)
	return {"tiles": tiles, "ends": ends, "open": open, "f": f}


## The biome region of terrain `t` through `start` (tiles linked by matching
## t edges): {tiles, open, t} where open counts t edges facing an empty spot.
## A region is closed when open == 0.
static func terrain_region(s: RunState, start: Dictionary, t: String) -> Dictionary:
	var seen := {start.k: true}
	var stack: Array = [start]
	var tiles: Array = []
	var open := 0
	while not stack.is_empty():
		var e: Dictionary = stack.pop_back()
		tiles.append(e)
		for i in 6:
			if e.tile.edge(i) != t:
				continue
			var nk: Vector2i = e.k + Hex.DIRS[i]
			var n = s.board.get(nk)
			if n == null:
				open += 1
				continue
			if seen.has(nk) or n.tile.edge((i + 3) % 6) != t:
				continue
			seen[nk] = true
			stack.append(n)
	return {"tiles": tiles, "open": open, "t": t}


## Points for closing a biome region of n tiles (see Defs.REGION_BONUS).
static func region_bonus(s: RunState, n: int) -> int:
	if n < Defs.REGION_MIN:
		return 0
	var m := mini(n, Defs.REGION_CAP)
	return int(ceil(s.goal() * Defs.REGION_BONUS * m * (1.0 + m / Defs.REGION_GROWTH) / 10.0)) * 10


## Points for closing a line: a share of the round goal per tile, so the reward
## stays meaningful in every round (Defs.CLOSE_BONUS).
static func close_bonus(s: RunState, net: Dictionary) -> int:
	var pct: float = Defs.CLOSE_BONUS[net.f]
	return int(ceil(s.goal() * pct * mini(net.tiles.size(), 10) / 10.0)) * 10


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
	# river and railroad networks: they only score once they run end to end
	# (water to water, station to station); +1 mult per 3 tiles and per end
	for f in Defs.FKEYS:
		var seen := {}
		for e in s.board.values():
			if seen.has(e.k) or not e.tile.feat.has(f):
				continue
			var net := line_network(s, e, f)
			for x in net.tiles:
				seen[x.k] = true
			if net.ends >= 2:
				var per := feat_val(s, f)
				var n: int = net.tiles.size()
				regions.append({"t": f, "tiles": net.tiles, "n": n, "per": per, "chips": per * n, "mult": int(n / 3) + net.ends, "ends": net.ends})
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


## Edges where placing `tile` at (q, r) would cut a river or railroad: a feature
## on one side of a shared edge that the other side doesn't continue (river
## into rail counts too). Placement is illegal if any exist.
static func line_breaks(s: RunState, q: int, r: int, tile: Tile) -> Array[int]:
	var out: Array[int] = []
	var k := Vector2i(q, r)
	for i in 6:
		var n = s.board.get(k + Hex.DIRS[i])
		if n == null:
			continue
		if feat_cut(tile, i, n.tile):
			out.append(i)
	return out


static func can_place(s: RunState, q: int, r: int, tile: Tile) -> bool:
	return s.line_rule_lifted or line_breaks(s, q, r, tile).is_empty()


## True if `tile` fits somewhere in some rotation without cutting a railroad.
static func has_legal_spot(s: RunState, tile: Tile) -> bool:
	var rot0 := tile.rot
	var ok := false
	for c in s.cands.values():
		for rot in 6:
			tile.rot = rot
			if line_breaks(s, c.q, c.r, tile).is_empty():
				ok = true
				break
		if ok:
			break
	tile.rot = rot0
	return ok


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
	# feat_per: -1 no feature on either side (or no neighbor), 0 broken, 1 linked
	var feat_per: Array[int] = []
	var feat_chips: Array[int] = [0, 0, 0, 0, 0, 0]
	var feat_kind: Array[String] = ["", "", "", "", "", ""]  # which feature linked on each edge
	var feat_matches := 0
	var feat_sum := 0
	for i in 6:
		var n = s.board.get(k + Hex.DIRS[i])
		if n == null:
			per.append(-1)
			feat_per.append(-1)
			continue
		nb += 1
		var fm := tile.feat_at(i)
		var ft: String = n.tile.feat_at((i + 3) % 6)
		var fl := feat_link(tile, i, n.tile)
		var mouth := is_mouth(tile, i, n.tile)
		if (fm == "" and ft == "") or mouth:
			feat_per.append(-1)  # a river mouth is scored below as a matched water edge
		elif fl != "":
			feat_per.append(1)
			feat_kind[i] = fl
			var fc := feat_val(s, fl)
			feat_chips[i] = fc
			feat_sum += fc
			feat_matches += 1
		else:
			feat_per.append(0)
		var mine := "water" if mouth else tile.edge(i)
		var ok := mouth or is_match(s, mine, n.tile.edge((i + 3) % 6))
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
	var breaks: Array[int] = [] if s.line_rule_lifted else line_breaks(s, q, r, tile)
	if matches == 0 and feat_matches == 0 and ray_chips == 0:
		return {"chips": 0, "mult": 0, "total": 0, "nb": nb, "matches": matches, "per": per, "perfect": false,
			"edge_chips": edge_chips, "chip_add": 0, "adds": [], "muls": [], "base_mult": 0, "events": events, "ray_chips": 0,
			"feat_per": feat_per, "feat_chips": feat_chips, "feat_kind": feat_kind, "feat_matches": 0, "feat_sum": 0, "blocked": breaks}
	chips += feat_sum
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
	var mult := 1 + matches + feat_matches
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
		"edge_chips": edge_chips, "chip_add": chip_add, "adds": adds, "muls": muls, "base_mult": 1 + matches + feat_matches, "events": events, "ray_chips": ray_chips,
		"feat_per": feat_per, "feat_chips": feat_chips, "feat_kind": feat_kind, "feat_matches": feat_matches, "feat_sum": feat_sum, "blocked": breaks}


static func count_hits(events: Array) -> int:
	var n := 0
	for ev in events:
		for ray in ev.rays:
			n += ray.hits.size()
	return n
