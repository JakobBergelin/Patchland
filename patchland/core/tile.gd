class_name Tile
extends RefCounted
## A hex tile: six edge terrains (in base order), a rotation and optional flags.

static var _next_id := 1

var id := 0
var base: Array[String] = []
var rot := 0
var art_seed := 0
var gold := false
## Empty when the tile has no quest, otherwise {"t": terrain, "need": int}.
var quest: Dictionary = {}
## "" or one of Defs.SKEYS.
var special := ""
## Edge features in base order: "" or one of Defs.FKEYS ("river", "rail").
var feat: Array[String] = ["", "", "", "", "", ""]


func edge(i: int) -> String:
	return base[(i + rot) % 6]


func feat_at(i: int) -> String:
	return feat[(i + rot) % 6]


## The tile's feature type, or "" if it has none.
func feature() -> String:
	for f in feat:
		if f != "":
			return f
	return ""


## An end piece of feature `f`: exactly one edge of it. Lines start and end here.
func is_end(f: String) -> bool:
	return feat.count(f) == 1


## A station: where a railroad starts or ends, always in a village.
func is_station() -> bool:
	return is_end("rail")


## Adds a river or railroad. Through pieces cross 2-3 land (non-water) edges.
## Railroads start and end at stations (one rail edge, leaving from a village edge).
## Rivers have no end pieces: they flow out of and into water edges on the board.
## open_lines[f] == false means nothing of that feature can be continued on the
## board: railroads then come as stations, rivers are not dealt at all.
func add_feature(rng: RandomNumberGenerator, f: String, open_lines := {}) -> void:
	var allowed: Array[int] = []
	for i in 6:
		if base[i] != "water":
			allowed.append(i)
	if allowed.size() < 2:
		return
	Defs.shuffle(allowed, rng)
	var n := 2 if rng.randf() < 0.88 else 3
	if f == "river":
		# rivers need no start tile: they flow out of water already on the board
		if not open_lines.get(f, true):
			return
	elif not open_lines.get(f, true) or rng.randf() < 0.4:
		# station: the railroad starts/ends here, leaving from a village edge
		var village: Array[int] = []
		for i in 6:
			if base[i] == "village":
				village.append(i)
		if village.is_empty():
			base[allowed[0]] = "village"
			village.append(allowed[0])
		feat[village[rng.randi_range(0, village.size() - 1)]] = f
		return
	n = mini(n, allowed.size())
	for k in n:
		feat[allowed[k]] = f


## Makes the land suit the special: a landmark gets at least 3 edges of the land
## type whose area it boosts (so it can sit inside that area).
func fit_special(rng: RandomNumberGenerator) -> void:
	if Defs.special_kind(special) != "landmark":
		return
	var t: String = Defs.SPECIALS[special].terrain
	var have := base.count(t)
	var others: Array[int] = []
	for i in 6:
		if base[i] != t:
			others.append(i)
	Defs.shuffle(others, rng)
	while have < 3 and not others.is_empty():
		base[others.pop_back()] = t
		have += 1


func is_wild() -> bool:
	return special == "crossroads"


func has_quest() -> bool:
	return not quest.is_empty()


func special_dirs() -> Array[int]:
	var out: Array[int] = []
	for b in Defs.SPECIALS[special].dirs:
		out.append((b - rot + 6) % 6)
	return out


func kinds() -> Array[String]:
	var out: Array[String] = []
	for t in base:
		if not out.has(t):
			out.append(t)
	return out


static func pick_terrain(rng: RandomNumberGenerator) -> String:
	var total := 0
	for tw in Defs.TWEIGHT:
		total += tw[1]
	var x := rng.randf() * total
	for tw in Defs.TWEIGHT:
		x -= tw[1]
		if x < 0:
			return tw[0]
	return "meadow"


static func make(rng: RandomNumberGenerator, min_kinds := 0, plain := false, relics: Array = [], round_idx := 0, open_lines := {}, specials: Array = Defs.SKEYS) -> Tile:
	var roll := rng.randf()
	var k := 1 if roll < 0.18 else (2 if roll < 0.62 else (3 if roll < 0.94 else 4))
	k = maxi(k, min_kinds)
	var kinds_list: Array[String] = []
	while kinds_list.size() < k:
		var t := pick_terrain(rng)
		if not kinds_list.has(t):
			kinds_list.append(t)
	var lens: Array[int] = []
	for i in k:
		lens.append(1)
	for i in range(k, 6):
		lens[rng.randi_range(0, k - 1)] += 1
	var run: Array[String] = []
	for i in k:
		for j in lens[i]:
			run.append(kinds_list[i])
	var off := rng.randi_range(0, 5)
	var tile := Tile.new()
	tile.id = _next_id
	_next_id += 1
	for i in 6:
		tile.base.append(run[(i + off) % 6])
	tile.art_seed = rng.randi_range(0, 999999999)
	if not plain:
		var special_chance := 0.2 if relics.has("architect") else 0.1
		var gold_chance := 0.18 if relics.has("goldsmith") else 0.06
		# only unlocked special tiles can be dealt; with none unlocked, no specials at all
		if not specials.is_empty() and rng.randf() < special_chance:
			tile.special = specials[rng.randi_range(0, specials.size() - 1)]
			tile.fit_special(rng)
		else:
			# rivers/railroads are independent of the gold/quest roll; specials never get one
			if rng.randf() < Defs.FEATURE_CHANCE:
				tile.add_feature(rng, "river" if rng.randf() < Defs.RIVER_SHARE else "rail", open_lines)
			if rng.randf() < gold_chance:
				tile.gold = true
			elif rng.randf() < 0.17:
				var lvl := int(round_idx / 3)
				tile.quest = {"t": kinds_list[rng.randi_range(0, kinds_list.size() - 1)], "need": 3 + rng.randi_range(0, 2) + lvl}
	return tile


## A single-terrain tile used for relic card art.
static func mono(t: String, seed_val: int) -> Tile:
	var tile := Tile.new()
	tile.id = -1
	for i in 6:
		tile.base.append(t)
	tile.art_seed = seed_val
	return tile
