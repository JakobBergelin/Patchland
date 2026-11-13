class_name Unlocks
## Achievements that unlock special tiles and relics. Unlocked ids are saved in
## the settings file (section "unlocks", key "ids"). Each achievement checks one
## RunState stat against a threshold; Game calls check() during play.

## Relics available from the start, and every achievement, built from the content
## data (data/content.tres): each special or relic with an unlock_stat has one.
## Achievement entries: {id, kind: "special"|"relic", stat, need, how}.
static var STARTER_RELICS: Array = []
static var LIST: Array = []


static func _static_init() -> void:
	rebuild()


static func rebuild() -> void:
	STARTER_RELICS.clear()
	LIST.clear()
	for k in Defs.SKEYS:
		var s: Dictionary = Defs.SPECIALS[k]
		if s.unlock_stat != "":
			LIST.append({"id": k, "kind": "special", "stat": s.unlock_stat, "need": s.unlock_need, "how": s.unlock_text})
	for r in Defs.RELICS:
		if r.starter:
			STARTER_RELICS.append(r.id)
		elif r.unlock_stat != "":
			LIST.append({"id": r.id, "kind": "relic", "stat": r.unlock_stat, "need": r.unlock_need, "how": r.unlock_text})


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


# ---------- Seasons (difficulty levels) ----------

## Highest Season the player may pick (1-based). Season 1 is always open;
## winning Season n opens Season n + 1.
static func seasons_open(path: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return 1
	return clampi(int(cfg.get_value("unlocks", "season", 1)), 1, Defs.SEASON_SCALE.size())


## Call after winning a run on `season`. Returns true if it opened a new Season.
static func record_win(path: String, season: int) -> bool:
	var open := seasons_open(path)
	if season < open or season >= Defs.SEASON_SCALE.size():
		return false
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("unlocks", "season", season + 1)
	cfg.save(path)
	return true
