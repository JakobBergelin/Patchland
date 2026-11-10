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


func edge(i: int) -> String:
	return base[(i + rot) % 6]


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


static func make(rng: RandomNumberGenerator, min_kinds := 0, plain := false, relics: Array = [], round_idx := 0) -> Tile:
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
		if rng.randf() < special_chance:
			tile.special = Defs.SKEYS[rng.randi_range(0, Defs.SKEYS.size() - 1)]
		elif rng.randf() < gold_chance:
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
