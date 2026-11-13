class_name Unlocks
## Achievements that unlock special tiles and relics. Unlocked ids are saved in
## the settings file (section "unlocks", key "ids"). Each achievement checks one
## RunState stat against a threshold; Game calls check() during play.

## Relics available from the start.
const STARTER_RELICS := ["saw", "falu", "mill", "harvest", "carto", "second", "mono", "granary"]

## kind: "special" (a special tile, id = Defs.SKEYS entry) or "relic" (id = relic id).
## stat: a RunState property; need: the value that unlocks it.
const LIST := [
	{"id": "windmill", "kind": "special", "stat": "rounds_cleared", "need": 1, "how": "Clear your first round."},
	{"id": "lighthouse", "kind": "special", "stat": "rivers_closed", "need": 1, "how": "Close a river: water at both ends and no open end."},
	{"id": "belltower", "kind": "special", "stat": "rounds_cleared", "need": 3, "how": "Clear round 3."},
	{"id": "ferry", "kind": "relic", "stat": "rails_closed", "need": 1, "how": "Close a railroad between stations."},
	{"id": "plumb", "kind": "relic", "stat": "best_streak", "need": 4, "how": "Make a streak of 4 Perfect placements."},
	{"id": "patch", "kind": "relic", "stat": "biggest_closed", "need": 6, "how": "Close an area of 6 or more tiles."},
	{"id": "wild", "kind": "relic", "stat": "closed_meadow_max", "need": 5, "how": "Close a meadow of 5 or more tiles."},
	{"id": "oak", "kind": "relic", "stat": "closed_forest_max", "need": 8, "how": "Close a forest of 8 or more tiles."},
	{"id": "almanac", "kind": "relic", "stat": "perfects", "need": 12, "how": "Make 12 Perfect placements in one run."},
	{"id": "surveyor", "kind": "relic", "stat": "quests", "need": 3, "how": "Complete 3 quests in one run."},
	{"id": "goldsmith", "kind": "relic", "stat": "gold_perfects", "need": 1, "how": "Get a Perfect with a golden tile."},
	{"id": "keeper", "kind": "relic", "stat": "chains", "need": 1, "how": "Set off a ray chain: a special tile's ray hits another special tile."},
	{"id": "miller", "kind": "relic", "stat": "best_harvest", "need": 20000, "how": "Score 20,000 or more in one harvest."},
	{"id": "rope", "kind": "relic", "stat": "bosses_beaten", "need": 1, "how": "Beat a boss round."},
	{"id": "architect", "kind": "relic", "stat": "rounds_cleared", "need": 8, "how": "Clear all 8 rounds."},
]


static func achievement(id: String) -> Dictionary:
	for a in LIST:
		if a.id == id:
			return a
	return {}


static func load_ids(path: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return []
	var ids = cfg.get_value("unlocks", "ids", [])
	return ids if ids is Array else []


static func _save_ids(path: String, ids: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("unlocks", "ids", ids)
	cfg.save(path)


static func is_unlocked(path: String, id: String) -> bool:
	return STARTER_RELICS.has(id) or load_ids(path).has(id)


static func specials(path: String) -> Array:
	var ids := load_ids(path)
	return Defs.SKEYS.filter(func(k): return ids.has(k))


static func relics(path: String) -> Array:
	var ids := load_ids(path)
	var out: Array = []
	for r in Defs.RELICS:
		if STARTER_RELICS.has(r.id) or ids.has(r.id):
			out.append(r.id)
	return out


## Number unlocked / total, counting starter relics as unlocked.
static func progress(path: String) -> Vector2i:
	var total := Defs.SKEYS.size() + Defs.RELICS.size()
	var n := STARTER_RELICS.size()
	var ids := load_ids(path)
	for a in LIST:
		if ids.has(a.id):
			n += 1
	return Vector2i(n, total)


## Checks every locked achievement against the run's stats, saves new unlocks,
## and returns the achievements unlocked just now.
static func check(path: String, s: RunState) -> Array:
	var ids := load_ids(path)
	var fresh: Array = []
	for a in LIST:
		if ids.has(a.id):
			continue
		var v = s.get(a.stat)
		if v != null and int(v) >= a.need:
			ids.append(a.id)
			fresh.append(a)
	if not fresh.is_empty():
		_save_ids(path, ids)
	return fresh
