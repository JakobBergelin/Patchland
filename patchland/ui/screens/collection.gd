extends Control
## Collection: every special tile, relic and Season. Layout in collection.tscn;
## the cards are built here from the content data and the player's unlocks.

signal back_pressed

const TABS := ["Special tiles", "Relics", "Seasons"]
const FILTERS := ["All", "Common", "Fine", "Heirloom", "Locked"]

var settings_path := ""
var tab := 0
var filter := 0
var _tab_group := ButtonGroup.new()
var _filter_group := ButtonGroup.new()


func setup(path: String) -> void:
	settings_path = path
	var pr := Unlocks.progress(path)
	%Count.text = "%d / %d" % [pr.x, pr.y]
	%Bar.max_value = pr.y
	%Bar.value = pr.x
	_render()
	%Back.grab_focus.call_deferred()


func _ready() -> void:
	%Back.pressed.connect(func(): back_pressed.emit())
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = _tab_group
		b.theme_type_variation = &"TabButton"
		b.button_pressed = i == 0
		b.pressed.connect(func(): tab = i; _render())
		%Tabs.add_child(b)
	for i in FILTERS.size():
		var b := Button.new()
		b.text = FILTERS[i]
		b.toggle_mode = true
		b.button_group = _filter_group
		b.theme_type_variation = &"TabButton"
		b.add_theme_font_size_override("font_size", 14)
		b.button_pressed = i == 0
		b.pressed.connect(func(): filter = i; _render())
		%Filters.add_child(b)
	resized.connect(_fit_columns)


func _fit_columns() -> void:
	%Grid.columns = clampi(int((size.x - 140) / 330), 1, 4)


func _render() -> void:
	_fit_columns()
	%Filters.visible = tab == 1
	for c in %Grid.get_children():
		c.queue_free()
	match tab:
		0:
			for k in Defs.SKEYS:
				var sp: Dictionary = Defs.SPECIALS[k]
				var t := Tile.mono("meadow", hash(k) & 0x7fffffff)
				t.base = ["meadow", "field", "meadow", "forest", "meadow", "field"] as Array[String]
				t.special = k
				if sp.kind == "landmark":
					t.base = [sp.terrain, sp.terrain, "meadow", sp.terrain, sp.terrain, "field"] as Array[String]
				var kind_tag: String = {"ray": "Fires rays", "landmark": "Landmark", "wild": "Wild", "stones": "Harvest"}.get(sp.kind, "")
				%Grid.add_child(_card(t, sp.name, kind_tag, sp.desc, sp.unlock_text, Unlocks.is_unlocked(settings_path, k)))
		1:
			for r in Defs.RELICS:
				var unlocked := Unlocks.is_unlocked(settings_path, r.id)
				if filter == 4 and unlocked:
					continue
				if filter in [1, 2, 3] and r.rarity != filter - 1:
					continue
				var desc: String = r.desc + ("  Available from the start." if r.starter else "")
				%Grid.add_child(_card(Tile.mono(r.t, hash(r.id) & 0x7fffffff), r.name, Defs.RARITY_NAMES[r.rarity], desc, r.unlock_text, unlocked, r.rarity))
		2:
			var open := Unlocks.seasons_open(settings_path)
			for i in Defs.SEASON_SCALE.size():
				var scale: float = Defs.SEASON_SCALE[i]
				var t := Tile.mono(["meadow", "field", "forest", "water", "village"][i % 5], 100 + i)
				var desc := "Normal goals." if scale == 1.0 else "Goals ×%.2f." % scale
				var how := "Win a run on Season %d." % i
				%Grid.add_child(_card(t, "Season %d" % (i + 1), "Difficulty", desc, how, i + 1 <= open))


## A card: icon, name, a small tag, then what it does (unlocked) or how to unlock it.
func _card(tile: Tile, title: String, tag: String, desc: String, how: String, unlocked: bool, rarity := -1) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Card" if unlocked else &"CardLocked"
	p.custom_minimum_size = Vector2(310, 118)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var tv := TileView.new()
	tv.custom_minimum_size = Vector2(70, 70)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.tile = tile
	if not unlocked:
		tv.modulate = Color(0, 0, 0, 0.92)  # blacked-out silhouette
	row.add_child(tv)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.theme_type_variation = &"BoldLabel"
	name_l.text = title if unlocked else title + "  (locked)"
	if not unlocked:
		name_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	head.add_child(name_l)
	if tag != "":
		var pill := PanelContainer.new()
		pill.theme_type_variation = &"Pill"
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tl := Label.new()
		tl.theme_type_variation = &"SmallLabel"
		tl.text = tag
		if rarity == 2:
			tl.add_theme_color_override("font_color", Color("#e9b938"))
		elif rarity == 1:
			tl.add_theme_color_override("font_color", Color("#8fc3e8"))
		pill.add_child(tl)
		head.add_child(pill)
	col.add_child(head)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 190
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unlocked:
		body.theme_type_variation = &"MutedLabel"
		body.text = desc
	else:
		body.theme_type_variation = &"GoldLabel"
		body.add_theme_font_size_override("font_size", 14)
		body.text = "To unlock: " + how
	col.add_child(body)
	row.add_child(col)
	p.add_child(row)
	return p
