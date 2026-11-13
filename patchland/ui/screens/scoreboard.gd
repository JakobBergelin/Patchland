extends Control
## Top runs on this computer. Layout in scoreboard.tscn.

signal back_pressed


func _ready() -> void:
	%Back.pressed.connect(func(): back_pressed.emit())
	%Back.grab_focus.call_deferred()


## highlight: 1-based rank of the run that just ended (0 = none).
func setup(path: String, highlight := 0) -> void:
	var list := Scores.load_list(path)
	%Empty.visible = list.is_empty()
	%Grid.get_parent().visible = not list.is_empty()
	for c in %Grid.get_children():
		c.queue_free()
	for h in ["#", "Score", "Reached", "Season", "Date"]:
		%Grid.add_child(_cell(h, &"SmallLabel"))
	for i in list.size():
		var e: Dictionary = list[i]
		var hl := i == highlight - 1
		var won: bool = e.get("won", false)
		%Grid.add_child(_cell(str(i + 1), &"BoldLabel", hl))
		var sc := _cell(Defs.fmt(e.score), &"BoldLabel", hl)
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%Grid.add_child(sc)
		%Grid.add_child(_cell("Won all %d" % Defs.ROUNDS if won else "Round %d" % (int(e.get("rounds", 0)) + 1), &"GoldLabel" if won else &"", hl))
		%Grid.add_child(_cell(str(e.get("season", 1)), &"", hl))
		%Grid.add_child(_cell(str(e.get("date", "")), &"MutedLabel", hl))


func _cell(text: String, variation: StringName, highlight := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if highlight:
		l.add_theme_color_override("font_color", Color("#e9b938"))
	return l
