extends Control
## How to play: a topic list and one page per topic with a small picture made of
## real tiles. Layout in rules.tscn; the topic texts and pictures are here.

signal back_pressed

const TOPICS := [
	["Basics", [
		"Lay hex tiles to grow a patch of countryside. Each round you get a stack of tiles; the current one sits in the tray, with the next two beside it.",
		"Hover a dashed spot to preview your tile there, right-click to turn it, and left-click to place it. Every edge that matches the land next to it scores.",
		"Reach the round's goal before your tiles run out. After each round you pick a relic that bends the rules in your favor. Clear all 8 rounds to win the run."]],
	["Scoring", [
		"Each matching edge adds its land's yield (village 8, water 6, field 5, forest 4, meadow 3) and +1 multiplier. Your placement scores yield × multiplier.",
		"Match every neighbor (at least two) for a Perfect: the multiplier doubles. Perfects in a row build a streak that adds even more.",
		"Golden tiles double their multiplier. Quest flags ask you to link a number of tiles of one land; finishing one gives +2 tiles and bonus points."]],
	["Harvest", [
		"When your tiles run out, the harvest scores the whole board: every region of linked land pays its yield per tile, and every 3 tiles in a region add +1 multiplier.",
		"So big connected areas matter more and more as the board grows. Your placements plus the harvest must reach the goal.",
		"Click during the harvest to speed it up."]],
	["Closing areas", [
		"An area of one land type is closed when none of its edges faces an empty spot any more, whether it's bordered by matching or other land.",
		"Closing an area of 3 or more tiles pays a bonus right away, and the bonus grows faster than the area: twice the tiles pays about three times as much."]],
	["Rivers & railroads", [
		"Some tiles carry a river or a railroad. Linking them across an edge adds extra yield and +1 multiplier, and a tile may never cut one.",
		"Railroads run between stations in cities; rivers flow out of and into water. A line that runs end to end is closed: it pays a bonus and scores again in the harvest. Closed lines get trains and boats."]],
	["Special tiles", [
		"Windmills, lighthouses and bell towers fire rays that score every tile they hit; hitting another special sets it off too.",
		"Landmarks (Scarecrow, Dam, Market, Hunting lodge, Beehive) double the harvest yield of the area of their land they stand in. Crossroads match any land. Standing stones add multiplier for every special on your land.",
		"Special tiles start locked: unlock them through achievements."]],
	["Relics & unlocks", [
		"After each round you pick one of three relics (two after a boss round). Common relics show up most, Fine ones less and Heirloom ones rarely.",
		"Most relics and every special tile start locked. Each has an achievement, like closing a big forest or beating a boss; see the Collection for what's left and how to get it. Unlocks take effect right away, even mid-run."]],
	["Seasons", [
		"Win a run to open the next Season. Each Season raises every goal, so your unlocks and good relic picks matter more and more.",
		"Pick the Season in the main menu before you start a run."]],
	["Controls", [
		"Left-click places. Right-click rotates (shift + right-click the other way); R / Q and Ctrl + scroll rotate too. X redraws, the arrow keys step through spots, Enter places.",
		"Scroll to zoom, drag or use WASD to move the view, F or a double-click on empty ground shows the whole board. F11 toggles fullscreen, Esc opens the menu."]],
]

var _group := ButtonGroup.new()


func _ready() -> void:
	%Back.pressed.connect(func(): back_pressed.emit())
	for i in TOPICS.size():
		var b := Button.new()
		b.text = TOPICS[i][0]
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = &"TabButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = i == 0
		b.pressed.connect(func(): show_topic(i))
		%Topics.add_child(b)
	show_topic(0)
	%Back.grab_focus.call_deferred()


func show_topic(i: int) -> void:
	%TopicTitle.text = TOPICS[i][0]
	for c in %Body.get_children():
		c.queue_free()
	for text in TOPICS[i][1]:
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 380
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 16)
		%Body.add_child(l)
	%Picture.list = _picture(i)
	%Picture.visible = not %Picture.list.is_empty()
	%Picture.queue_redraw()


static func _t(base: Array, special := "", gold := false, feats := {}) -> Tile:
	var t := Tile.mono("meadow", base.hash() & 0xffff)
	for k in 6:
		t.base[k] = base[k]
	t.special = special
	t.gold = gold
	for k in feats:
		t.feat[k] = feats[k]
	return t


## A small board illustrating topic i.
func _picture(i: int) -> Array:
	var M := ["meadow", "meadow", "meadow", "meadow", "meadow", "meadow"]
	var Fi := ["field", "field", "field", "field", "field", "field"]
	var Fo := ["forest", "forest", "forest", "forest", "forest", "forest"]
	var W := ["water", "water", "water", "water", "water", "water"]
	var V := ["village", "village", "village", "village", "village", "village"]
	match i:
		0:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			return ClusterView.hero_cluster(rng)
		1:
			return [{"q": 0, "r": 0, "tile": _t(["field", "forest", "forest", "meadow", "meadow", "field"], "", true)},
				{"q": 1, "r": 0, "tile": _t(Fi)}, {"q": 0, "r": -1, "tile": _t(Fo)}, {"q": -1, "r": 0, "tile": _t(M)}, {"q": 0, "r": 1, "tile": _t(M)}]
		2:
			return [{"q": 0, "r": 0, "tile": _t(Fi)}, {"q": 1, "r": 0, "tile": _t(Fi)}, {"q": -1, "r": 1, "tile": _t(Fi)}, {"q": 0, "r": 1, "tile": _t(Fi)},
				{"q": 1, "r": -1, "tile": _t(Fo)}, {"q": -1, "r": 0, "tile": _t(W)}]
		3:
			return [{"q": 0, "r": 0, "tile": _t(Fo)}, {"q": 1, "r": 0, "tile": _t(["forest", "forest", "meadow", "forest", "meadow", "meadow"])},
				{"q": 0, "r": -1, "tile": _t(["meadow", "meadow", "meadow", "meadow", "forest", "forest"])}, {"q": -1, "r": 0, "tile": _t(M)}, {"q": 0, "r": 1, "tile": _t(M)}, {"q": -1, "r": 1, "tile": _t(M)}, {"q": 1, "r": -1, "tile": _t(M)}]
		4:
			return [{"q": -1, "r": 0, "tile": _t(V, "", false, {0: "rail"})}, {"q": 0, "r": 0, "tile": _t(["meadow", "field", "field", "meadow", "meadow", "field"], "", false, {0: "rail", 3: "rail"})},
				{"q": 1, "r": 0, "tile": _t(V, "", false, {3: "rail"})}, {"q": -1, "r": 1, "tile": _t(W)}, {"q": 0, "r": 1, "tile": _t(["forest", "forest", "field", "meadow", "meadow", "field"], "", false, {3: "river", 0: "river"})}, {"q": 1, "r": 1, "tile": _t(W)}]
		5:
			return [{"q": -1, "r": 0, "tile": _t(M, "windmill")}, {"q": 0, "r": 0, "tile": _t(["field", "field", "field", "meadow", "field", "field"], "scarecrow")},
				{"q": 1, "r": 0, "tile": _t(M, "lighthouse")}, {"q": -1, "r": 1, "tile": _t(M, "stones")}, {"q": 0, "r": 1, "tile": _t(M, "crossroads")}, {"q": 1, "r": -1, "tile": _t(V, "market")}]
		6:
			return [{"q": 0, "r": 0, "tile": _t(Fi, "", true)}, {"q": 1, "r": 0, "tile": _t(V)}, {"q": -1, "r": 0, "tile": _t(W)}]
		7:
			return [{"q": 0, "r": 0, "tile": _t(Fo, "lodge")}, {"q": 1, "r": 0, "tile": _t(Fo)}, {"q": 0, "r": 1, "tile": _t(Fo)}, {"q": -1, "r": 1, "tile": _t(W, "dam")}]
	return []
