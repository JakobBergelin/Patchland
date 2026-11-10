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
const FEATURE_CHANCE := 0.3  # of non-special tiles
const RIVER_SHARE := 0.55
const TWEIGHT := [["forest", 28], ["field", 24], ["meadow", 20], ["water", 14], ["village", 14]]

const SPECIALS := {
	"windmill": {"name": "Windmill", "dirs": [0, 2, 4], "len": 3, "desc": "Fires 3 rays, each 3 tiles long."},
	"lighthouse": {"name": "Lighthouse", "dirs": [0], "len": 99, "desc": "Fires 1 ray the way it faces, all the way to the edge of your land."},
	"belltower": {"name": "Bell tower", "dirs": [0, 1, 2, 3, 4, 5], "len": 1, "desc": "Rings all 6 neighbors."},
}
const SKEYS := ["windmill", "lighthouse", "belltower"]

const RELICS := [
	{"id": "saw", "name": "Sawmill", "t": "forest", "desc": "Forest edges give +4 chips."},
	{"id": "falu", "name": "Falu paint", "t": "village", "desc": "Village edges give +8 chips."},
	{"id": "mill", "name": "Watermill", "t": "water", "desc": "Each matched water edge adds +1 mult."},
	{"id": "harvest", "name": "Harvest fair", "t": "field", "desc": "+3 mult when a field edge matches."},
	{"id": "wild", "name": "Open meadow", "t": "meadow", "desc": "Meadow edges match any land."},
	{"id": "ferry", "name": "Ferryman", "t": "water", "desc": "Water and village edges match each other."},
	{"id": "plumb", "name": "Plumb line", "t": "village", "desc": "Perfect placements give ×3 mult instead of ×2."},
	{"id": "patch", "name": "Patchwork", "t": "meadow", "desc": "+4 mult when you match 3 or more kinds of land at once."},
	{"id": "almanac", "name": "Almanac", "t": "field", "desc": "Gains +1 mult for every perfect placement. Also counts in the harvest."},
	{"id": "mono", "name": "Monoculture", "t": "forest", "desc": "+40 chips for tiles with only one kind of land."},
	{"id": "carto", "name": "Cartographer", "t": "meadow", "desc": "+2 tiles every round."},
	{"id": "second", "name": "Second thoughts", "t": "water", "desc": "+2 redraws every round."},
	{"id": "goldsmith", "name": "Goldsmith", "t": "village", "desc": "Golden tiles show up three times as often."},
	{"id": "surveyor", "name": "Surveyor", "t": "field", "desc": "Quests also give +3 mult to your next placement."},
	{"id": "granary", "name": "Granary", "t": "field", "desc": "Field regions give double chips in the harvest."},
	{"id": "oak", "name": "Old oak", "t": "forest", "desc": "Forest regions of 6+ tiles give +3 mult in the harvest."},
	{"id": "miller", "name": "Miller", "t": "field", "desc": "Windmills fire twice."},
	{"id": "keeper", "name": "Lamplighter", "t": "water", "desc": "Each special tile that fires adds +2 mult instead of +1."},
	{"id": "rope", "name": "Bell rope", "t": "village", "desc": "Bell towers also ring tiles 2 steps away."},
	{"id": "architect", "name": "Architect", "t": "meadow", "desc": "Special tiles show up twice as often."},
]

const BOSSES := [
	{"id": "drought", "name": "Drought", "desc": "Water gives no chips this round, harvest included."},
	{"id": "blight", "name": "Blight", "desc": "Forest gives no chips this round, harvest included."},
	{"id": "lean", "name": "Lean year", "desc": "Villages give no chips this round, harvest included."},
	{"id": "fog", "name": "Fog", "desc": "You can’t see your next tile, and you get no redraws."},
	{"id": "short", "name": "Short season", "desc": "You get 3 fewer tiles this round."},
]

const BOSS_ROUNDS := [2, 5, 7]
const ROUNDS := 8
const GOALS := [1500, 5000, 12000, 35000, 75000, 110000, 240000, 420000]


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
