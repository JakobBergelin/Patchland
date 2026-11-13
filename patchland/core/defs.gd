class_name Defs
## Static game data, ported 1:1 from reference/patchland.html.

const TER := {
	"forest": {"name": "Forest", "chips": 4, "top": "#4f8d58", "dark": "#2f6040"},
	"field": {"name": "Field", "chips": 5, "top": "#e2bb57", "dark": "#b38a2c"},
	"meadow": {"name": "Meadow", "chips": 3, "top": "#a8cd7a", "dark": "#76a052"},
	"water": {"name": "Water", "chips": 6, "top": "#5d9dc7", "dark": "#3c78a3"},
	"village": {"name": "Village", "chips": 8, "top": "#d2c4ab", "dark": "#a8977c"},
}
const TKEYS := ["forest", "field", "meadow", "water", "village"]

## Edge features drawn over the land. Linking the same feature across an edge
## scores its chips and +1 mult; linked networks score again in the harvest.
const FEAT := {
	"river": {"name": "River", "chips": 6, "top": "#4a90c4", "dark": "#2f6d9e"},
	"rail": {"name": "Railroad", "chips": 8, "top": "#9a7b5c", "dark": "#5b4636"},
}
const FKEYS := ["river", "rail"]
## Bonus for closing a line (no open ends, both ends finished), as a share of the
## round goal per tile in the line (counted up to 10 tiles).
const CLOSE_BONUS := {"river": 0.012, "rail": 0.015}
## Bonus for closing a biome region (no edge of its land faces an empty spot):
## goal * REGION_BONUS * n * (1 + n / REGION_GROWTH), so bigger areas pay more
## than proportionally. Regions under REGION_MIN tiles don't count; n is capped.
const REGION_BONUS := 0.004
const REGION_GROWTH := 4.0
const REGION_MIN := 3
const REGION_CAP := 16
const FEATURE_CHANCE := 0.3  # of non-special tiles
const RIVER_SHARE := 0.55
const TWEIGHT := [["forest", 28], ["field", 24], ["meadow", 20], ["water", 14], ["village", 14]]

## Special tiles and relics come from data/content.tres (edit them in the Inspector).
## SPECIALS: id -> {id, name, desc, kind, dirs, len, terrain, unlock_*}; SKEYS: ids in order.
## RELICS: [{id, name, t, desc, rarity, starter, unlock_*}].
static var SPECIALS := {}
static var SKEYS: Array = []
static var RELICS: Array = []
static var RARITY_WEIGHTS: Array = [6.0, 3.0, 1.0]
const RARITY_NAMES := ["Common", "Fine", "Heirloom"]

const BOSSES := [
	{"id": "drought", "name": "Drought", "desc": "Water gives no yield this round, harvest included."},
	{"id": "blight", "name": "Blight", "desc": "Forest gives no yield this round, harvest included."},
	{"id": "lean", "name": "Lean year", "desc": "Villages give no yield this round, harvest included."},
	{"id": "fog", "name": "Fog", "desc": "You can’t see your next tiles, and you get no redraws."},
	{"id": "short", "name": "Short season", "desc": "You get 3 fewer tiles this round."},
]

const BOSS_ROUNDS := [2, 5, 7]
const ROUNDS := 8
## Tiles dealt each round and Season 1 goals, from content.tres.
static var TILES_PER_ROUND := 10
static var GOALS: Array = []
## Goal multiplier per Season; winning a Season unlocks the next.
static var SEASON_SCALE: Array = [1.0]


const CONTENT_PATH := "res://data/content.tres"


static func _static_init() -> void:
	load_content(load(CONTENT_PATH))


## Fills SPECIALS, RELICS, GOALS etc. from a ContentDB resource.
static func load_content(db: ContentDB) -> void:
	SPECIALS.clear()
	SKEYS.clear()
	RELICS.clear()
	for s in db.specials:
		SKEYS.append(s.id)
		SPECIALS[s.id] = {"id": s.id, "name": s.name, "desc": s.desc, "kind": s.kind, "dirs": Array(s.dirs), "len": s.length,
			"terrain": s.terrain, "unlock_stat": s.unlock_stat, "unlock_need": s.unlock_need, "unlock_text": s.unlock_text}
	for r in db.relics:
		RELICS.append({"id": r.id, "name": r.name, "t": r.terrain, "desc": r.desc, "rarity": r.rarity, "starter": r.starter,
			"unlock_stat": r.unlock_stat, "unlock_need": r.unlock_need, "unlock_text": r.unlock_text})
	GOALS = Array(db.goals)
	TILES_PER_ROUND = db.tiles_per_round
	SEASON_SCALE = Array(db.season_goal_scale) if not db.season_goal_scale.is_empty() else [1.0]
	RARITY_WEIGHTS = Array(db.rarity_weights)


static func special_kind(id: String) -> String:
	return SPECIALS[id].kind if SPECIALS.has(id) else ""


static func relic(id: String) -> Dictionary:
	for r in RELICS:
		if r.id == id:
			return r
	return {}


static func boss(id: String) -> Dictionary:
	for b in BOSSES:
		if b.id == id:
			return b
	return {}


static func top(t: String) -> Color:
	return Color.html(FEAT[t].top if FEAT.has(t) else TER[t].top)


static func dark(t: String) -> Color:
	return Color.html(FEAT[t].dark if FEAT.has(t) else TER[t].dark)


static func name_of(t: String) -> String:
	return FEAT[t].name if FEAT.has(t) else TER[t].name


static func fmt(n: float) -> String:
	var v := int(round(n))
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func shuffle(a: Array, rng: RandomNumberGenerator) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
