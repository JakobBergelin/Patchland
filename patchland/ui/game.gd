class_name Game
extends Control
## Main controller: builds the UI, owns the RunState, runs placement and harvest
## sequences (timed callbacks), and handles input.

## Where settings and the best score are saved. Tests point this at their own file
## (set before adding the node) so they never touch the player's settings.
var settings_path := "user://patchland.cfg"
const SHEET_W := 430.0

var S: RunState
var sel = null  # cand Dictionary {q, r, k} or null
var cur_eval = null
var calc_hold = null
var shown := 0
var started := false
var test_run := false  # menu switch: everything unlocked, no scoreboard entry, no achievements
var unlocked_this_run: Array = []  # achievements earned during the current run
var run_is_test := false  # the current run was started as a test run
var season_pick := 1  # Season (difficulty) chosen in the menu for the next run
var run_active := false  # a run (or the tutorial) is in progress; the menu offers Continue
var tut: Tutorial = null  # set while the tutorial runs
var tut_hidden := false
var overlay_kind := ""  # "menu", "rules", "scores", "draft", "end"
var overlay_back := "board"  # where Back returns from rules/scoreboard
var last_rank := 0  # scoreboard rank of the run that just ended (0 = none)
var _end_title := ""
var _end_body := ""
var harvesting := false
var hl_region = null  # {t, keys: Array[Vector2i]}
var reduced := false
var muted := false
var hero: Array = []

var _seq: Array = []  # [{at, fn}]
var _steps: Array = []  # [{delay, fn}]
var _step_at := 0.0
var _step_speed := 1.0
var _tweens := {}
var _toast_until := 0.0

var sfx: Sfx
var board: Board
var app: VBoxContainer
var round_lbl: Label
var score_lbl: Label
var goal_lbl: Label
var proj_lbl: Label
var tiles_lbl: Label
var bar: GoalBar
var mute_icon: IconView
var relic_box: HBoxContainer
var cur_view: TileView
var nxt_view: TileView
var nxt2_view: TileView
var chips_panel: PanelContainer
var mult_panel: PanelContainer
var chips_lbl: Label
var mult_lbl: Label
var total_lbl: Label
var streak_panel: PanelContainer
var streak_lbl: Label
var hint_lbl: Label
var rot_btn: Button
var redraw_btn: Button
var redraw_badge: Label
var place_btn: Button
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var toast_panel: PanelContainer
var toast_lbl: Label
var overlay: ColorRect
var sheet: PanelContainer
var sheet_box: VBoxContainer
var sheet_scroll: ScrollContainer
var sheet_center: CenterContainer
var screen: Control = null  # the full-screen scene shown in the overlay (menu, collection, ...)
var hud_m: MarginContainer
var rel_m: MarginContainer
var tray_m: MarginContainer
var fs_icon: IconView
var tut_panel: PanelContainer
var tut_title: Label
var tut_text: Label
var tut_next: Button
var tut_wait: Label
const CONTENT_W := 1180.0


# ======================================================================
# setup
# ======================================================================

func _ready() -> void:
	Pal.init()
	RenderingServer.set_default_clear_color(Pal.bg)
	DisplayServer.window_set_min_size(Vector2i(760, 680))
	# fonts, colours and button/panel styles: edit ui/theme/patchland_theme.tres in the editor
	theme = load("res://ui/theme/patchland_theme.tres")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	sfx = Sfx.new()
	sfx.muted = muted
	add_child(sfx)
	_build_ui()
	resized.connect(_layout)
	_layout()
	new_run()
	show_main_menu()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		muted = cfg.get_value("game", "muted", false)
		if cfg.get_value("game", "fullscreen", false) and DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save_setting(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("game", key, value)
	cfg.save(settings_path)


func _get_setting(key: String, default):
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		return cfg.get_value("game", key, default)
	return default


## Best run = top of the scoreboard.
func get_best() -> int:
	return Scores.best(settings_path)


## The board uses the whole window; the HUD, relic strip and tray stay a readable
## width (CONTENT_W) in the middle, which matters in fullscreen on wide screens.
func _layout() -> void:
	app.position = Vector2.ZERO
	app.size = size
	var side := maxf(0, (size.x - CONTENT_W) / 2)
	hud_m.add_theme_constant_override("margin_left", int(side + 16))
	hud_m.add_theme_constant_override("margin_right", int(side + 16))
	rel_m.add_theme_constant_override("margin_left", int(side + 16))
	rel_m.add_theme_constant_override("margin_right", int(side + 16))
	tray_m.add_theme_constant_override("margin_left", int(side))
	tray_m.add_theme_constant_override("margin_right", int(side))
	render_fullscreen()


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool) -> void:
	# A game embedded in the editor's Game tab can't change its window mode.
	if Engine.is_embedded_in_editor():
		toast("Fullscreen doesn't work inside the editor's Game tab. Turn off \"Embed Game on Next Play\" there and run again (F5), or run the exported game.")
		return
	# Windows ignores mode changes for a window without focus, so bring it forward first.
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_setting("fullscreen", on)
	render_fullscreen()


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


func render_fullscreen() -> void:
	if fs_icon:
		fs_icon.kind = "windowed" if is_fullscreen() else "fullscreen"


# ---------- ui helpers ----------

func _sb(bg: Color, radius := 0, border := Color(0, 0, 0, 0), bw := 0, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


func _lbl(text: String, fs: int, col: Color = Pal.ink, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", Pal.bold)
	return l


func _para(text: String, fs := 15, col: Color = Pal.ink, width := SHEET_W - 44) -> Label:
	var l := _lbl(text, fs, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func _style_button(b: Button, primary := false, radius := 12) -> void:
	# looks come from the theme (ui/theme/patchland_theme.tres): Button / PrimaryButton
	b.theme_type_variation = &"PrimaryButton" if primary else &""
	b.add_theme_font_size_override("font_size", 16)


func _btn(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 46
	_style_button(b, primary)
	return b


func _icon_btn() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(36, 36)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _sb(Pal.panel if st != "hover" else Pal.bg2, 18, Pal.line, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Pal.ink)
	b.add_theme_color_override("font_hover_color", Pal.ink)
	b.add_theme_font_override("font", Pal.bold)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _small_stat(caption: String) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.add_child(_lbl(caption, 14, Pal.soft))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var b := _lbl("", 21, Pal.ink, true)
	row.add_child(b)
	box.add_child(row)
	return [box, b, row]


func _build_ui() -> void:
	app = VBoxContainer.new()
	app.add_theme_constant_override("separation", 0)
	add_child(app)

	# --- HUD ---
	hud_m = MarginContainer.new()
	for side in [["left", 16], ["right", 16], ["top", 12], ["bottom", 6]]:
		hud_m.add_theme_constant_override("margin_" + side[0], side[1])
	app.add_child(hud_m)
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 12)
	hud_m.add_child(hud)
	var rs := _small_stat("Round")
	round_lbl = rs[1]
	rs[2].add_child(_lbl("/8", 14, Pal.soft))
	hud.add_child(rs[0])

	var goal := VBoxContainer.new()
	goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal.add_theme_constant_override("separation", 3)
	var grow := HBoxContainer.new()
	score_lbl = _lbl("0", 21, Pal.ink, true)
	grow.add_child(score_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(spacer)
	goal_lbl = _lbl("Goal 0", 15, Pal.soft, true)
	grow.add_child(goal_lbl)
	goal.add_child(grow)
	bar = GoalBar.new()
	bar.custom_minimum_size.y = 10
	goal.add_child(bar)
	proj_lbl = _lbl("", 14, Pal.soft)
	proj_lbl.clip_text = true
	goal.add_child(proj_lbl)
	hud.add_child(goal)

	var ts := _small_stat("Tiles")
	tiles_lbl = ts[1]
	hud.add_child(ts[0])

	var mute_btn := _icon_btn()
	mute_btn.tooltip_text = "Sound (M)"
	mute_icon = IconView.new()
	mute_icon.color = Pal.ink
	mute_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	mute_icon.offset_left = 9
	mute_icon.offset_top = 9
	mute_icon.offset_right = -9
	mute_icon.offset_bottom = -9
	mute_btn.add_child(mute_icon)
	mute_btn.pressed.connect(toggle_mute)
	var mb_wrap := CenterContainer.new()
	mb_wrap.add_child(mute_btn)
	hud.add_child(mb_wrap)
	var fs_btn := _icon_btn()
	fs_btn.tooltip_text = "Fullscreen (F11)"
	fs_icon = IconView.new()
	fs_icon.color = Pal.ink
	fs_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	fs_icon.offset_left = 9
	fs_icon.offset_top = 9
	fs_icon.offset_right = -9
	fs_icon.offset_bottom = -9
	fs_btn.add_child(fs_icon)
	fs_btn.pressed.connect(toggle_fullscreen)
	var fs_wrap := CenterContainer.new()
	fs_wrap.add_child(fs_btn)
	hud.add_child(fs_wrap)
	var menu_btn := _icon_btn()
	menu_btn.text = "≡"
	menu_btn.tooltip_text = "Menu (Esc)"
	menu_btn.pressed.connect(func(): if not harvesting: show_main_menu())
	var mn_wrap := CenterContainer.new()
	mn_wrap.add_child(menu_btn)
	hud.add_child(mn_wrap)
	var help_btn := _icon_btn()
	help_btn.text = "?"
	help_btn.tooltip_text = "How to play"
	help_btn.pressed.connect(show_rules.bind("board"))
	var hb_wrap := CenterContainer.new()
	hb_wrap.add_child(help_btn)
	hud.add_child(hb_wrap)
	render_mute()

	# --- relic strip ---
	rel_m = MarginContainer.new()
	rel_m.add_theme_constant_override("margin_left", 16)
	rel_m.add_theme_constant_override("margin_right", 16)
	rel_m.add_theme_constant_override("margin_bottom", 8)
	app.add_child(rel_m)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size.y = 36
	rel_m.add_child(scroll)
	relic_box = HBoxContainer.new()
	relic_box.add_theme_constant_override("separation", 6)
	relic_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(relic_box)

	# --- stage ---
	board = Board.new()
	board.game = self
	board.reduced = reduced
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.add_child(board)
	board.hovered.connect(_on_hover)
	board.clicked.connect(_on_click)
	board.rotate_requested.connect(func(dir): if not overlay.visible: rotate(dir))
	board.speed_up_requested.connect(speed_up)

	banner = VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.modulate.a = 0
	banner_title = _lbl("", 48, Pal.ink, true)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_constant_override("outline_size", 14)
	banner_title.add_theme_color_override("font_outline_color", Pal.bg)
	banner_sub = _lbl("", 16, Pal.soft, true)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_constant_override("outline_size", 8)
	banner_sub.add_theme_color_override("font_outline_color", Pal.bg)
	banner.add_child(banner_title)
	banner.add_child(banner_sub)
	board.add_child(banner)

	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_theme_stylebox_override("panel", _sb(Pal.ink, 10, Color(0, 0, 0, 0), 0, Vector4(14, 8, 14, 8)))
	toast_lbl = _lbl("", 14, Pal.bg, true)
	toast_panel.add_child(toast_lbl)
	toast_panel.modulate.a = 0
	board.add_child(toast_panel)

	# tutorial callout, top-left of the board
	tut_panel = PanelContainer.new()
	var tsb := _sb(Pal.panel, 14, Pal.gold, 2, Vector4(16, 12, 16, 12))
	tsb.shadow_color = Color(0, 0, 0, 0.3)
	tsb.shadow_size = 12
	tut_panel.add_theme_stylebox_override("panel", tsb)
	tut_panel.position = Vector2(16, 14)
	tut_panel.visible = false
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tut_title = _lbl("", 17, Pal.gold, true)
	tv.add_child(tut_title)
	tut_text = _para("", 15, Pal.ink, 360)
	tv.add_child(tut_text)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	tut_next = _btn("Next", true)
	tut_next.custom_minimum_size = Vector2(96, 38)
	tut_next.pressed.connect(_tut_next)
	trow.add_child(tut_next)
	tut_wait = _lbl("Do it on the board to continue", 14, Pal.soft)
	tut_wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(tut_wait)
	var tspacer := Control.new()
	tspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tspacer)
	var tskip := _btn("Skip tutorial")
	tskip.custom_minimum_size = Vector2(0, 38)
	tskip.add_theme_font_size_override("font_size", 14)
	tskip.pressed.connect(_tut_skip)
	trow.add_child(tskip)
	tv.add_child(trow)
	tut_panel.add_child(tv)
	board.add_child(tut_panel)

	# --- tray ---
	var tray := PanelContainer.new()
	var tray_sb := _sb(Pal.panel, 0, Pal.line, 1, Vector4(16, 12, 16, 14))
	tray_sb.corner_radius_top_left = 18
	tray_sb.corner_radius_top_right = 18
	tray_sb.border_width_bottom = 0
	tray.add_theme_stylebox_override("panel", tray_sb)
	tray_m = MarginContainer.new()
	app.add_child(tray_m)
	tray_m.add_child(tray)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	tray.add_child(row)

	var hand := HBoxContainer.new()
	hand.add_theme_constant_override("separation", 10)
	hand.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(hand)
	var cur_box := PanelContainer.new()
	cur_box.add_theme_stylebox_override("panel", _sb(Pal.bg2, 16, Pal.line, 1))
	cur_box.custom_minimum_size = Vector2(86, 86)
	cur_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cur_box.tooltip_text = "Current tile: click or right-click to rotate"
	cur_view = TileView.new()
	cur_view.interactive = true
	cur_view.rotate_clicked.connect(func(dir): rotate(dir))
	cur_box.add_child(cur_view)
	hand.add_child(cur_box)
	var nxt_box := VBoxContainer.new()
	nxt_box.add_theme_constant_override("separation", 2)
	nxt_box.size_flags_vertical = Control.SIZE_SHRINK_END
	nxt_view = TileView.new()
	nxt_view.custom_minimum_size = Vector2(46, 46)
	nxt_view.modulate.a = 0.85
	nxt_box.add_child(nxt_view)
	var nl := _lbl("Next", 12, Pal.soft)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nxt_box.add_child(nl)
	hand.add_child(nxt_box)
	# the tile after next: smaller and fainter, so the order reads left to right
	var nxt2_box := VBoxContainer.new()
	nxt2_box.add_theme_constant_override("separation", 2)
	nxt2_box.size_flags_vertical = Control.SIZE_SHRINK_END
	nxt2_view = TileView.new()
	nxt2_view.custom_minimum_size = Vector2(36, 36)
	nxt2_view.modulate.a = 0.6
	nxt2_box.add_child(nxt2_view)
	var nl2 := _lbl("Then", 12, Pal.soft)
	nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nxt2_box.add_child(nl2)
	hand.add_child(nxt2_box)

	var readout := VBoxContainer.new()
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.alignment = BoxContainer.ALIGNMENT_CENTER
	readout.add_theme_constant_override("separation", 6)
	row.add_child(readout)
	var calc := HBoxContainer.new()
	calc.add_theme_constant_override("separation", 6)
	readout.add_child(calc)
	chips_panel = PanelContainer.new()
	chips_panel.tooltip_text = "Yield: the points this placement earns before the multiplier"
	chips_panel.add_theme_stylebox_override("panel", _sb(Pal.chips, 10, Color(0, 0, 0, 0), 0, Vector4(10, 2, 10, 2)))
	chips_lbl = _lbl("0", 22, Color.WHITE, true)
	chips_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chips_lbl.custom_minimum_size.x = 24
	chips_panel.add_child(chips_lbl)
	calc.add_child(chips_panel)
	calc.add_child(_lbl("×", 18, Pal.soft))
	mult_panel = PanelContainer.new()
	mult_panel.tooltip_text = "Multiplier: the yield is multiplied by this"
	mult_panel.add_theme_stylebox_override("panel", _sb(Pal.mult, 10, Color(0, 0, 0, 0), 0, Vector4(10, 2, 10, 2)))
	mult_lbl = _lbl("0", 22, Color.WHITE, true)
	mult_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mult_lbl.custom_minimum_size.x = 24
	mult_panel.add_child(mult_lbl)
	calc.add_child(mult_panel)
	calc.add_child(_lbl("=", 18, Pal.soft))
	total_lbl = _lbl("0", 26, Pal.ink, true)
	calc.add_child(total_lbl)
	streak_panel = PanelContainer.new()
	streak_panel.add_theme_stylebox_override("panel", _sb(Pal.gold, 99, Color(0, 0, 0, 0), 0, Vector4(9, 3, 9, 3)))
	streak_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	streak_lbl = _lbl("", 13, Color("#241a00"), true)
	streak_panel.add_child(streak_lbl)
	streak_panel.visible = false
	calc.add_child(streak_panel)
	hint_lbl = _lbl("", 15, Pal.soft)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# fixed three-line height: the hint changes with every hovered slot, and a
	# changing height would resize the board above it and make the camera jump
	hint_lbl.custom_minimum_size = Vector2(120, ceilf(3 * Pal.font.get_height(15) + 3 * hint_lbl.get_theme_constant("line_spacing")) + 2)
	hint_lbl.max_lines_visible = 3
	hint_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	readout.add_child(hint_lbl)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.custom_minimum_size.x = 340
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	rot_btn = _btn("Rotate")
	rot_btn.tooltip_text = "Rotate (right-click, Ctrl + scroll, R / Q)"
	rot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_btn.size_flags_stretch_ratio = 1.0
	rot_btn.pressed.connect(func(): rotate(1))
	actions.add_child(rot_btn)
	redraw_btn = _btn("")
	redraw_btn.tooltip_text = "Redraw (X)"
	redraw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redraw_btn.pressed.connect(redraw)
	var rb_row := HBoxContainer.new()
	rb_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rb_row.add_theme_constant_override("separation", 6)
	rb_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rb_l := _lbl("Redraw", 16, Pal.ink, true)
	rb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb_row.add_child(rb_l)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _sb(Pal.line, 99, Color(0, 0, 0, 0), 0, Vector4(6, 0, 6, 0)))
	redraw_badge = _lbl("2", 13, Pal.ink, true)
	redraw_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	redraw_badge.custom_minimum_size.x = 10
	badge.add_child(redraw_badge)
	rb_row.add_child(badge)
	redraw_btn.add_child(rb_row)
	actions.add_child(redraw_btn)
	place_btn = _btn("Place", true)
	place_btn.tooltip_text = "Place (Enter)"
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_btn.size_flags_stretch_ratio = 1.35
	place_btn.pressed.connect(place)
	actions.add_child(place_btn)

	# --- overlay ---
	overlay = ColorRect.new()
	overlay.color = Color(16 / 255.0, 24 / 255.0, 22 / 255.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	sheet_center = center
	sheet = PanelContainer.new()
	sheet.theme_type_variation = &"Sheet"
	sheet.custom_minimum_size.x = SHEET_W
	center.add_child(sheet)
	sheet_scroll = ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.custom_minimum_size.x = SHEET_W - 44
	sheet.add_child(sheet_scroll)
	sheet_box = VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 10)
	sheet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(sheet_box)
	overlay.resized.connect(_fit_sheet)


# ======================================================================
# timing
# ======================================================================

func after(ms: float, fn: Callable) -> void:
	_seq.append({"at": Fx.now() + ms, "fn": fn})


func step_q(delay: float, fn: Callable) -> void:
	_steps.append({"delay": delay, "fn": fn})


func _process(dt: float) -> void:
	var t := Fx.now()
	var i := 0
	while i < _seq.size():
		if t >= _seq[i].at:
			var f: Dictionary = _seq[i]
			_seq.remove_at(i)
			f.fn.call()
		else:
			i += 1
	while not _steps.is_empty() and t >= _step_at:
		var s: Dictionary = _steps.pop_front()
		s.fn.call()
		_step_at = t + s.delay / _step_speed
	if S == null:
		return
	if shown != S.round_score:
		var diff := S.round_score - shown
		shown += signi(diff) * maxi(1, ceili(absi(diff) * 0.16))
		if (diff > 0 and shown > S.round_score) or (diff < 0 and shown < S.round_score):
			shown = S.round_score
		render_score()
	# low-tiles pulse
	if S.tiles_left <= 3 and not harvesting and not reduced:
		tiles_lbl.add_theme_color_override("font_color", Pal.mult)
		tiles_lbl.pivot_offset = tiles_lbl.size / 2
		var k := 1.0 + 0.09 * (1.0 - cos(t / 900.0 * TAU))
		tiles_lbl.scale = Vector2(k, k)
	else:
		tiles_lbl.add_theme_color_override("font_color", Pal.ink)
		tiles_lbl.scale = Vector2.ONE
	if toast_panel.modulate.a > 0 and t > _toast_until:
		toast_panel.modulate.a = maxf(0, toast_panel.modulate.a - dt * 5)
	toast_panel.position = Vector2((board.size.x - toast_panel.size.x) / 2, 10)


# ======================================================================
# run flow
# ======================================================================

## Starts a run. `tutorial` uses a fixed seed, an easy goal and fewer tiles,
## and shows the guided callouts.
func new_run(seed_val := -1, tutorial := false) -> void:
	_seq.clear()
	_steps.clear()
	harvesting = false
	hl_region = null
	board.clear_tiles()
	S = RunState.new()
	S.season = 1 if tutorial else season_pick
	# which specials and relics can show up: your unlocks, or everything on a test run
	run_is_test = test_run and not tutorial
	if not run_is_test and not tutorial:
		S.allowed_specials = Unlocks.specials(settings_path)
		S.allowed_relics = Unlocks.relics(settings_path)
	unlocked_this_run.clear()
	S.new_run(seed_val)
	tut = null
	tut_hidden = false
	last_rank = 0
	if tutorial:
		tut = Tutorial.new()
		S.goal_override = Tutorial.GOAL
		S.tiles_left = Tutorial.TILES
	render_tutorial()
	board.sync_tiles(S.board)
	_after_start_round()
	board.snap_cam = true


func _after_start_round() -> void:
	shown = 0
	calc_hold = null
	set_sel(null, true)
	update_all()
	if started:
		round_banner()


func round_banner() -> void:
	if S.boss != "":
		var b := Defs.boss(S.boss)
		show_banner("Boss: " + b.name, b.desc, true)
		sfx.boss()
		board.shake(3)
	else:
		show_banner("Round %d" % (S.round_idx + 1), "Goal " + Defs.fmt(S.goal()))


# ---------- placing ----------

func place() -> void:
	if sel == null or S.cur == null or S.busy:
		return
	var q: int = sel.q
	var r: int = sel.r
	if not Rules.can_place(S, q, r, S.cur):
		sfx.dud()
		board.shake(1.5)
		toast("That would cut a river or railroad. Rotate it or try another spot.")
		return
	var res := S.place(q, r)
	if res.is_empty():
		return
	_tut("place")
	var entry: Dictionary = res.entry
	var ev: Dictionary = res.ev
	var events: Array = res.events
	var tile: Tile = entry.tile
	var w := Hex.wpos(q, r)
	var wx := w.x
	var wy := w.y
	board.add_tile(entry, Fx.now())
	set_sel(null, true)
	calc_hold = null
	update_all()
	show_calc(0, 0, 0)
	_set_calc_idle(false)
	sfx.drop()
	after(170, func():
		board.fx.dust(wx, wy)
		sfx.land()
		board.shake(1.0))

	var t := 250.0
	var run := {"chips": 0, "mult": 0}
	var step := 0
	var gap := 80.0 if ev.matches > 4 else 95.0
	for i in 6:
		if ev.per[i] != 1:
			continue
		var c: int = ev.edge_chips[i]
		var st := step
		step += 1
		after(t, func():
			run.chips += c
			show_calc(run.chips, run.mult)
			pop(chips_panel)
			board.fx.edge_fx(wx, wy, i, c, tile.edge(i))
			board.bump(Vector2i(q, r) + Hex.DIRS[i])
			sfx.tick(st + S.streak))
		t += gap
	# linked rivers and railroads
	for i in 6:
		if ev.feat_per[i] != 1:
			continue
		var fc: int = ev.feat_chips[i]
		var f: String = ev.feat_kind[i]
		var stf := step
		step += 1
		after(t, func():
			run.chips += fc
			show_calc(run.chips, run.mult)
			pop(chips_panel)
			board.fx.edge_fx(wx, wy, i, fc, f)
			var a := -i * PI / 3
			board.fx.float_at(wx + cos(a) * 0.6, wy + sin(a) * 0.6 - 0.75, Defs.name_of(f), "chips", 0.6, false, 800, 14)
			board.bump(Vector2i(q, r) + Hex.DIRS[i])
			sfx.tick(stf + S.streak + 2))
		t += gap
	if ev.chip_add:
		var st2 := step
		after(t, func():
			run.chips += ev.chip_add
			show_calc(run.chips, run.mult)
			pop(chips_panel)
			board.fx.float_at(wx, wy - 1.25, "Monoculture +%d" % ev.chip_add, "chips", 0.85)
			sfx.tick(st2 + 4))
		t += 150
	for e2 in events:
		var src: Dictionary = e2.src
		var sp := Hex.wpos(src.q, src.r)
		after(t, func():
			board.bump(src.k)
			board.fx.ring(sp.x, sp.y, 420, Color("#ffe27a"), 0.6)
			sfx.zap()
			board.mill_fast())
		t += 120
		for ray in e2.rays:
			for h in ray.hits:
				var st3 := step
				step += 1
				after(t, func():
					run.chips += h.v
					show_calc(run.chips, run.mult)
					pop(chips_panel)
					var hp := Hex.wpos(h.e.q, h.e.r)
					board.fx.beam(sp.x, sp.y, hp.x, hp.y)
					board.bump(h.e.k)
					board.fx.float_at(hp.x, hp.y - 0.5, "+%d" % h.v, "chips" if h.v else "soft", 0.75, false, 700, 18)
					sfx.tick(st3 + S.streak))
				t += 85
	if ev.matches or ev.ray_chips:
		after(t, func():
			run.mult = ev.base_mult
			show_calc(run.chips, run.mult)
			pop(mult_panel)
			sfx.mult(0))
		t += 130
		for j in ev.adds.size():
			var a: Array = ev.adds[j]
			after(t, func():
				run.mult += a[1]
				show_calc(run.chips, run.mult)
				pop(mult_panel)
				board.fx.float_at(wx, wy - 1.2, "%s +%d" % [a[0], a[1]], "mult", 0.85)
				sfx.mult(j + 1))
			t += 160
		for m in ev.muls:
			after(t, func():
				run.mult *= m[1]
				show_calc(run.chips, run.mult)
				pop(mult_panel)
				if m[0] == "Perfect":
					board.fx.float_at(wx, wy - 0.35, "Perfect ×%d" % m[1], "mult", 1.35, true, 950)
					board.fx.perfect_fx(wx, wy, tile)
					sfx.perfect(S.streak)
					board.shake(2.5)
					board.punch_it(0.012)
					board.bump(entry.k)
				else:
					board.fx.float_at(wx, wy - 0.35, "Golden ×%d" % m[1], "gold", 1.35, true, 950)
					board.fx.gold_fx(wx, wy)
					sfx.gold()
					board.shake(2)
					board.punch_it(0.008))
			t += 280
	after(t, func(): finish_placement(entry, ev))


func finish_placement(entry: Dictionary, ev: Dictionary) -> void:
	var w := Hex.wpos(entry.q, entry.r)
	var res := S.finish_placement(entry, ev)
	show_calc(ev.chips, ev.mult, ev.total)
	pop(total_lbl)
	pop(score_lbl)
	calc_hold = ev
	var g := float(S.goal())
	if ev.total > 0:
		board.fx.float_at(w.x, w.y - 1.1, "+" + Defs.fmt(ev.total), "mult" if ev.perfect else "ink", 1.3, true, 1200)
		sfx.total(ev.total / g)
		board.shake(minf(4, 0.8 + 3 * ev.total / g))
	else:
		board.fx.float_at(w.x, w.y - 1.1, "+0", "soft", 1)
		sfx.dud()
	if ev.perfect:
		if S.streak >= 2:
			board.fx.float_at(w.x, w.y - 1.8, "Streak %d" % S.streak, "gold", 0.9, true, 1000)
	elif res.streak_lost:
		board.fx.float_at(w.x, w.y - 1.8, "Streak lost", "soft", 0.8)
	for qd in res.quests:
		var e: Dictionary = qd.e
		e["done_at"] = Fx.now()
		var qp := Hex.wpos(e.q, e.r)
		board.fx.quest_fx(qp.x, qp.y)
		board.fx.float_at(qp.x, qp.y - 1.7, "Quest: +2 tiles, +" + Defs.fmt(qd.bonus), "gold", 1, true, 1400)
		sfx.quest()
	for ln in res.lines:
		# a river or railroad was closed: celebrate along the whole line and pay the bonus
		var net: Dictionary = ln.net
		for x in net.tiles:
			board.bump(x.k)
			var xp := Hex.wpos(x.q, x.r)
			board.fx.ring(xp.x, xp.y, 650, Defs.top(net.f), 0.7)
			board.fx.burst(xp.x, xp.y - 0.3, 8, [Defs.top(net.f), Color.WHITE], {"speed": 2.2, "up": 1.8, "grav": 5.0, "life": 0.8})
		var verb := "River closed" if net.f == "river" else "Railroad closed"
		board.fx.float_at(w.x, w.y - 2.3, "%s: +%s" % [verb, Defs.fmt(ln.bonus)], "gold", 1.15, true, 1600)
		board.shake(2)
		sfx.quest()
	var lift: float = 2.3 + 0.6 * res.lines.size()
	for rg in res.regions:
		# a biome area was closed: outline it, ripple across its tiles and pay the size bonus
		var reg: Dictionary = rg.reg
		var keys: Array = []
		var centre := Vector2.ZERO
		for x in reg.tiles:
			keys.append(x.k)
			var xp := Hex.wpos(x.q, x.r)
			centre += xp
			board.fx.ring(xp.x, xp.y, 700, Defs.top(reg.t), 0.45)
			board.bump(x.k)
		centre /= reg.tiles.size()
		board.flash_region(reg.t, keys, 900)
		board.fx.burst(centre.x, centre.y - 0.4, mini(40, 8 + 2 * reg.tiles.size()), [Defs.top(reg.t), Color.WHITE, Color("#f5c542")], {"speed": 3.0, "up": 2.2, "grav": 6.0, "life": 0.9})
		board.fx.float_at(centre.x, centre.y - lift, "%s closed ×%d: +%s" % [Defs.name_of(reg.t), reg.tiles.size(), Defs.fmt(rg.bonus)], "gold", minf(1.6, 1.0 + 0.04 * reg.tiles.size()), true, 1700)
		lift += 0.6
		board.shake(minf(4, 1 + 0.25 * reg.tiles.size()))
		if reg.tiles.size() >= 8:
			sfx.clear()
		else:
			sfx.quest()
	_check_unlocks()
	if S.tiles_left <= 0:
		after(450, start_harvest)
	else:
		S.busy = false
	update_all()


# ---------- harvest ----------

func start_harvest() -> void:
	S.busy = true
	harvesting = true
	set_sel(null, true)
	var H := Rules.harvest_calc(S)
	_steps.clear()
	_step_speed = 1
	_step_at = Fx.now()
	var ticks := 0
	for r in H.regions:
		ticks += r.n
	ticks += Rules.count_hits(H.events)
	var gap := maxf(16, minf(80, 4800.0 / maxi(1, ticks)))
	var acc := {"chips": 0, "mult": 1, "done": 0}
	var pitch := func() -> int:
		var p := mini(22, int(floor(acc.done * 20.0 / maxi(1, ticks))))
		acc.done += 1
		return p
	step_q(900, func():
		show_banner("Harvest", "Every region scores. Click to speed up.")
		sfx.gong()
		_set_calc_idle(false)
		show_calc(0, 1, 0)
		update_calc()
		render_score())
	# relic and Standing stones multipliers that apply to the whole harvest
	for xi in H.extras.size():
		var x: Array = H.extras[xi]
		step_q(260, func():
			acc.mult += x[1]
			show_calc(acc.chips, acc.mult)
			pop(mult_panel)
			sfx.mult(xi)
			board.fx.float_at(board.cam.x, board.cam.y - 1.6 - 0.7 * xi, "%s +%d multiplier" % [x[0], x[1]], "mult", 0.95, true, 1300))
	var regs: Array = H.regions.duplicate()
	regs.sort_custom(func(a, b): return a.chips < b.chips or (a.chips == b.chips and a.n < b.n))
	for r in regs:
		var keys: Array = []
		for e in r.tiles:
			keys.append(e.k)
		step_q(0, func(): hl_region = {"t": r.t, "keys": keys})
		for e in r.tiles:
			step_q(gap, func():
				acc.chips += r.per
				show_calc(acc.chips, acc.mult)
				pop(chips_panel)
				board.bump(e.k)
				var p := Hex.wpos(e.q, e.r)
				board.fx.float_at(p.x, p.y - 0.55, "+%d" % r.per, "chips" if r.per else "soft", 0.7, false, 650, 16)
				if gap < 30:
					sfx.soft(pitch.call())
				else:
					sfx.tick(pitch.call()))
		var last: Dictionary = r.tiles[r.tiles.size() - 1]
		var lp := Hex.wpos(last.q, last.r)
		if r.mult:
			step_q(maxf(110, gap * 2), func():
				acc.mult += r.mult
				show_calc(acc.chips, acc.mult)
				pop(mult_panel)
				board.fx.float_at(lp.x, lp.y - 1.2, ("%s ×%d, %d %s: +%d multiplier" % [Defs.name_of(r.t), r.n, r.ends, "stations" if r.t == "rail" else "water ends", r.mult]) if r.has("ends") else ("%s ×%d: +%d multiplier" % [Defs.name_of(r.t), r.n, r.mult]), "mult", 0.9, true, 1000)
				sfx.mult(mini(10, r.mult))
				board.shake(minf(3, 0.5 + r.mult * 0.5)))
		else:
			step_q(maxf(30, gap), func(): pass)
	step_q(0, func(): hl_region = null)
	for ev in H.events:
		var src: Dictionary = ev.src
		var sp := Hex.wpos(src.q, src.r)
		step_q(maxf(100, gap * 2), func():
			board.bump(src.k)
			board.fx.ring(sp.x, sp.y, 420, Color("#ffe27a"), 0.6)
			sfx.zap()
			board.mill_fast())
		for ray in ev.rays:
			for h in ray.hits:
				step_q(maxf(30, gap * 1.2), func():
					acc.chips += h.v
					show_calc(acc.chips, acc.mult)
					pop(chips_panel)
					var hp := Hex.wpos(h.e.q, h.e.r)
					board.fx.beam(sp.x, sp.y, hp.x, hp.y)
					board.bump(h.e.k)
					board.fx.float_at(hp.x, hp.y - 0.55, "+%d" % h.v, "chips" if h.v else "soft", 0.7, false, 650, 16)
					sfx.tick(pitch.call()))
		if not ev.rays.is_empty():
			step_q(160, func():
				var add := Rules.ray_mult_per(S)
				acc.mult += add
				show_calc(acc.chips, acc.mult)
				pop(mult_panel)
				board.fx.float_at(sp.x, sp.y - 1.3, "%s +%d multiplier" % [Defs.SPECIALS[src.tile.special].name, add], "mult", 0.9, true, 1000)
				sfx.mult(6)
				board.shake(1.5))
	step_q(700, func():
		var total := int(round(float(acc.chips) * acc.mult))
		S.apply_harvest(total)
		S.record_harvest(H)
		var g := float(S.goal())
		show_calc(acc.chips, acc.mult, total)
		pop(total_lbl)
		pop(score_lbl)
		board.fx.float_at(board.cam.x, board.cam.y - 0.5, "Harvest +" + Defs.fmt(total), "ink", 2, true, 1800, 20)
		board.fx.clear_fx(board.view_rect(), 0.5)
		sfx.big(total / g)
		board.shake(minf(8, 3 + 4 * total / g))
		board.punch_it(0.025))
	step_q(1300, func():
		harvesting = false
		_step_speed = 1
		if S.cleared():
			board.fx.clear_fx(board.view_rect(), 1)
			sfx.clear()
			board.shake(4)
			show_banner("Goal reached", "%s of %s" % [Defs.fmt(S.round_score), Defs.fmt(S.goal())])
			after(1400, end_round)
		else:
			sfx.fail()
			board.shake(5)
			show_banner("The harvest came up short", "%s of %s" % [Defs.fmt(S.round_score), Defs.fmt(S.goal())], true)
			after(1600, game_over)
		update_all())


func speed_up() -> void:
	if harvesting and _step_speed == 1:
		_step_speed = 4
		toast("Speeding up")


# ---------- tile actions ----------

func rotate(dir: int) -> void:
	if S == null or S.cur == null or S.busy:
		return
	S.rotate_cur(dir)
	sfx.rotate()
	_spin(cur_view, dir)
	refresh_eval()
	draw_previews()
	_tut("rotate")


func redraw() -> void:
	if S == null or not S.redraw():
		return
	sfx.redraw()
	_swap(cur_view)
	refresh_eval()
	update_all()


func set_sel(h, force := false, audible := false) -> void:
	if not force and ((sel != null and h != null and sel.k == h.k) or (sel == null and h == null)):
		return
	sel = h
	if h != null:
		calc_hold = null
		if audible:
			sfx.select()
	refresh_eval()
	if h != null:
		_tut("hover")


func refresh_eval() -> void:
	cur_eval = Rules.evaluate(S, sel.q, sel.r, S.cur) if sel != null and S.cur != null else null
	if cur_eval != null:
		var k: Vector2i = sel.k
		S.board[k] = RunState.make_entry(sel.q, sel.r, S.cur)
		var n := 0
		for e in S.board.values():
			if not e.quest.is_empty() and not e.qdone and Rules.region_size(S, e, e.quest.t) >= e.quest.need:
				n += 1
		cur_eval.quests = n
		cur_eval.harvest = Rules.harvest_calc(S).total
		# what this placement would close (rivers, railroads, biome regions) and its bonus
		var close_pts := 0
		var closes: Array[String] = []
		for net in S.closed_lines(S.board[k]):
			close_pts += Rules.close_bonus(S, net)
			closes.append(Defs.name_of(net.f).to_lower())
		for reg in S.closed_regions(S.board[k]):
			close_pts += Rules.region_bonus(S, reg.tiles.size())
			closes.append("%s (%d tiles)" % [Defs.name_of(reg.t).to_lower(), reg.tiles.size()])
		cur_eval.close_bonus = close_pts
		cur_eval.closes = closes
		S.board.erase(k)
	update_calc()
	update_buttons()
	render_score()


func cycle(dir: int) -> void:
	if S == null or S.busy:
		return
	var arr: Array = S.cands.values()
	if arr.is_empty():
		return
	arr.sort_custom(func(a, b):
		if a.r != b.r:
			return a.r < b.r
		return (a.q + a.r / 2.0) < (b.q + b.r / 2.0))
	var idx := -1 if dir > 0 else 0
	if sel != null:
		for i in arr.size():
			if arr[i].k == sel.k:
				idx = i
	set_sel(arr[(idx + dir + arr.size()) % arr.size()], false, true)


# ======================================================================
# HUD
# ======================================================================

func _anim(c: Control, key: String) -> Tween:
	var id := str(c.get_instance_id()) + key
	if _tweens.has(id) and _tweens[id].is_valid():
		_tweens[id].kill()
	var tw := c.create_tween()
	_tweens[id] = tw
	return tw


func pop(c: Control) -> void:
	if reduced:
		return
	c.pivot_offset = c.size / 2
	c.scale = Vector2(1.3, 1.3)
	_anim(c, "pop").tween_property(c, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spin(c: Control, dir: int) -> void:
	if reduced:
		return
	c.pivot_offset = c.size / 2
	c.rotation = deg_to_rad(-35 * dir)
	c.scale = Vector2(0.9, 0.9)
	var tw := _anim(c, "spin")
	tw.set_parallel(true)
	tw.tween_property(c, "rotation", 0.0, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT)


func _swap(c: Control) -> void:
	if reduced:
		return
	c.pivot_offset = c.size / 2
	c.rotation = 0
	c.modulate.a = 0
	c.scale = Vector2(0.7, 0.7)
	var tw := _anim(c, "spin")
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)


func show_calc(c: int, m: int, t := -1) -> void:
	chips_lbl.text = Defs.fmt(c)
	mult_lbl.text = Defs.fmt(m)
	if t >= 0:
		total_lbl.text = Defs.fmt(t)


func _set_calc_idle(idle: bool) -> void:
	var a := 0.32 if idle else 1.0
	chips_panel.modulate.a = a
	mult_panel.modulate.a = a
	total_lbl.modulate.a = a


func update_all() -> void:
	round_lbl.text = str(S.round_idx + 1)
	goal_lbl.text = "Goal " + Defs.fmt(S.goal())
	tiles_lbl.text = str(S.tiles_left)
	render_score()
	render_relics()
	draw_previews()
	update_calc()
	update_buttons()


func render_score() -> void:
	if S == null:
		return
	var g := float(S.goal())
	var extra := 0
	if not harvesting:
		extra = (cur_eval.total + cur_eval.harvest) if cur_eval != null else S.harvest_base
	var pace := S.round_score + extra
	score_lbl.text = Defs.fmt(shown)
	bar.set_values(shown / g, extra / g, not harvesting and pace >= g, shown >= g)
	if harvesting:
		proj_lbl.text = "Harvesting…"
	elif cur_eval != null:
		proj_lbl.text = "With this tile: " + Defs.fmt(pace)
	else:
		proj_lbl.text = "On pace for " + Defs.fmt(pace)


func _pill(text: String, dot: Color, is_boss: bool, desc: String, extra := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.add_theme_stylebox_override("panel", _sb(Pal.mult if is_boss else Pal.panel, 99, Color(0, 0, 0, 0) if is_boss else Pal.line, 1, Vector4(9, 4, 11, 4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := IconView.new()
	ic.kind = "hex"
	ic.color = Color.WHITE if is_boss else dot
	ic.custom_minimum_size = Vector2(11, 12)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := _lbl(text, 13, Color.WHITE if is_boss else Pal.ink, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	if extra != "":
		var x := _lbl(extra, 13, Pal.mult, true)
		x.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(x)
	p.add_child(row)
	p.tooltip_text = desc
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			toast(desc))
	return p


func render_relics() -> void:
	for c in relic_box.get_children():
		c.queue_free()
	if S.boss != "":
		var b := Defs.boss(S.boss)
		relic_box.add_child(_pill("Boss: " + b.name, Color.WHITE, true, b.desc))
	for id in S.relics:
		var r := Defs.relic(id)
		relic_box.add_child(_pill(r.name, Defs.top(r.t), false, r.desc, ("+%d" % S.almanac) if id == "almanac" else ""))
	if relic_box.get_child_count() == 0:
		var e := _lbl("Relics you pick after each round show up here.", 13, Pal.soft)
		e.custom_minimum_size.y = 28
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		relic_box.add_child(e)


func tile_hint(t: Tile) -> String:
	if t == null:
		return ""
	var out := ""
	if S != null and S.line_rule_lifted:
		out += "No spot keeps every river and railroad intact, so this tile may cut one. "
	if t.special != "":
		var sp: Dictionary = Defs.SPECIALS[t.special]
		var extra := " Every tile hit scores its land again, and hitting another special sets it off." if sp.kind == "ray" else ""
		return out + "%s: %s%s " % [sp.name, sp.desc, extra]
	if t.is_station():
		out += "Station: railroads start and end in cities. A line between two stations scores in the harvest, +1 multiplier per station. "
	elif t.feature() == "rail":
		out += "Railroad: link track for +8 yield and +1 multiplier per edge. Track must meet track. "
	elif t.feature() == "river":
		out += "River: flows out of and into water. Link it for +6 yield and +1 multiplier per edge; it can't be cut. A river that reaches water at both ends scores in the harvest. "
	if t.has_quest():
		return out + "Quest: link %d %s tiles through matching edges. " % [t.quest.need, Defs.TER[t.quest.t].name.to_lower()]
	if t.gold:
		return out + "Golden tile: its multiplier is doubled. "
	return out


func update_calc() -> void:
	if S == null:
		return
	streak_panel.visible = S.streak >= 2
	streak_lbl.text = "Streak %d" % S.streak
	if S.busy:
		_set_hint("Harvesting. Click the board to speed it up." if harvesting else "Scoring…")
		return
	if cur_eval == null:
		_set_calc_idle(true)
		if calc_hold != null:
			show_calc(calc_hold.chips, calc_hold.mult, calc_hold.total)
		else:
			show_calc(0, 0, 0)
		_set_hint(tile_hint(S.cur) + "Hover a dashed spot, or use the arrow keys, to preview your tile. Right-click to rotate. Scroll to zoom, drag or WASD to move the view, F to see the whole board.")
		return
	if not cur_eval.blocked.is_empty():
		_set_calc_idle(true)
		show_calc(0, 0, 0)
		_set_hint("Blocked: this would cut a river or railroad. Every river and track edge must meet the same on the other side. Rotate it or try another spot.")
		return
	_set_calc_idle(false)
	show_calc(cur_eval.chips, cur_eval.mult, cur_eval.total)
	var h := "%d of %d edges match." % [cur_eval.matches, cur_eval.nb]
	if cur_eval.feat_matches:
		var kinds: Array[String] = []
		for i in 6:
			if cur_eval.feat_per[i] == 1:
				var nm := Defs.name_of(cur_eval.feat_kind[i]).to_lower()
				if not kinds.has(nm):
					kinds.append(nm)
		h += " Links %s: +%d yield, +%d multiplier." % [" and ".join(kinds), cur_eval.feat_sum, cur_eval.feat_matches]
	var hits := Rules.count_hits(cur_eval.events)
	if hits:
		h += " Rays hit %d tile%s for +%d yield." % [hits, "s" if hits > 1 else "", cur_eval.ray_chips]
	var extras: Array[String] = []
	if cur_eval.chip_add:
		extras.append("Monoculture +%d yield" % cur_eval.chip_add)
	for a in cur_eval.adds:
		extras.append("%s +%d" % [a[0], a[1]])
	for m in cur_eval.muls:
		extras.append("%s ×%d" % [m[0], m[1]])
	if not extras.is_empty():
		h += " " + ", ".join(extras) + "."
	elif not cur_eval.matches and not hits and not cur_eval.feat_matches:
		h += " Rotate to find a match."
	if cur_eval.get("close_bonus", 0):
		h += " Closes %s: +%s bonus." % [", ".join(cur_eval.closes), Defs.fmt(cur_eval.close_bonus)]
	if cur_eval.quests:
		h += (" Finishes %d quests." % cur_eval.quests) if cur_eval.quests > 1 else " Finishes a quest."
	var dh: int = cur_eval.harvest - S.harvest_base
	if dh > 0:
		h += " Harvest +%s." % Defs.fmt(dh)
	h += " Click to place, right-click to rotate."
	_set_hint(h)


## Sets the hint; the full text is also its tooltip in case the three lines cut it short.
func _set_hint(text: String) -> void:
	hint_lbl.text = text
	hint_lbl.tooltip_text = text


func update_buttons() -> void:
	place_btn.disabled = sel == null or S == null or S.busy or (cur_eval != null and not cur_eval.blocked.is_empty())
	redraw_btn.disabled = S == null or S.busy or S.redraws <= 0
	redraw_badge.get_parent().modulate.a = 0.4 if redraw_btn.disabled else 1.0
	redraw_badge.get_parent().get_parent().modulate.a = 0.4 if redraw_btn.disabled else 1.0
	rot_btn.disabled = S == null or S.busy
	redraw_badge.text = str(S.redraws if S else 0)


func draw_previews() -> void:
	cur_view.tile = S.cur
	nxt_view.tile = S.nxt
	nxt_view.fogged = S.boss == "fog"
	nxt2_view.tile = S.nxt2
	nxt2_view.fogged = S.boss == "fog"


func toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_panel.reset_size()
	toast_panel.modulate.a = 1
	_toast_until = Fx.now() + 2400


func show_banner(title: String, sub: String, is_boss := false) -> void:
	banner_title.text = title
	banner_sub.text = sub
	banner_title.add_theme_color_override("font_color", Pal.mult if is_boss else Pal.ink)
	banner.size = Vector2(board.size.x * 0.92, 0)
	banner.reset_size()
	banner.size.x = board.size.x * 0.92
	var base := Vector2(board.size.x * 0.04, board.size.y * 0.4 - banner.size.y / 2)
	banner.pivot_offset = banner.size / 2
	var tw := _anim(banner, "banner")
	if reduced:
		banner.position = base
		banner.scale = Vector2.ONE
		banner.modulate.a = 0
		tw.tween_property(banner, "modulate:a", 1.0, 0.3)
		tw.tween_interval(1.3)
		tw.tween_property(banner, "modulate:a", 0.0, 0.4)
		return
	banner.position = base + Vector2(0, banner.size.y * 0.12)
	banner.scale = Vector2(0.9, 0.9)
	banner.modulate.a = 0
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.24)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.24).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "position", base, 0.24).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.32)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.44)
	tw.tween_property(banner, "position", base - Vector2(0, banner.size.y * 0.12), 0.44)


func render_mute() -> void:
	mute_icon.kind = "sound_off" if muted else "sound_on"


func toggle_mute() -> void:
	muted = not muted
	sfx.muted = muted
	_save_setting("muted", muted)
	if muted:
		sfx.stop_all()
	else:
		sfx.select()
	render_mute()
	toast("Sound off" if muted else "Sound on")


# ======================================================================
# input
# ======================================================================

func _on_hover(h) -> void:
	if S == null or S.busy or overlay.visible:
		return
	set_sel(h)


func _on_click(h) -> void:
	if S == null or S.busy or overlay.visible or h == null:
		return
	set_sel(h)
	place()


## Fullscreen works everywhere, even with an overlay open: F11 or Alt+Enter.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_on_escape()
			get_viewport().set_input_as_handled()


## Esc: open the menu during play; on a sub-screen go back; in the pause menu resume.
func _on_escape() -> void:
	if not overlay.visible:
		if run_active and not harvesting:
			show_main_menu()
		return
	match overlay_kind:
		"rules", "scores", "collection":
			_overlay_back()
		"menu":
			if run_active:
				_resume()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if overlay.visible or S == null:
		return
	# camera keys work at any time, harvest included
	match event.keycode:
		KEY_W, KEY_A, KEY_S, KEY_D:
			return  # held keys, handled by the board each frame
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			board.zoom_at(board.size / 2, 1.2)
			get_viewport().set_input_as_handled()
			return
		KEY_MINUS, KEY_KP_SUBTRACT:
			board.zoom_at(board.size / 2, 1 / 1.2)
			get_viewport().set_input_as_handled()
			return
		KEY_HOME, KEY_F:
			board.reset_view()
			get_viewport().set_input_as_handled()
			return
	if harvesting:
		speed_up()
		return
	match event.keycode:
		KEY_R, KEY_E:
			rotate(1)
		KEY_Q:
			rotate(-1)
		KEY_X:
			redraw()
		KEY_M:
			toggle_mute()
		KEY_RIGHT, KEY_DOWN:
			cycle(1)
		KEY_LEFT, KEY_UP:
			cycle(-1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			place()
		_:
			return
	get_viewport().set_input_as_handled()


# ======================================================================
# overlays
# ======================================================================

func _drop_screen() -> void:
	if screen != null:
		screen.queue_free()
		screen = null


## Opens the overlay with the small sheet (drafts, run summaries).
func open_overlay() -> void:
	_drop_screen()
	sheet_center.visible = true
	for c in sheet_box.get_children():
		sheet_box.remove_child(c)
		c.queue_free()
	overlay.visible = true
	set_sel(null, true)
	_fit_sheet.call_deferred()
	if not reduced:
		sheet.pivot_offset = Vector2(SHEET_W / 2, 200)
		sheet.modulate.a = 0
		sheet.scale = Vector2(0.97, 0.97)
		var tw := _anim(sheet, "sheet")
		tw.set_parallel(true)
		tw.tween_property(sheet, "modulate:a", 1.0, 0.28)
		tw.tween_property(sheet, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Opens the overlay with a full-screen scene (ui/screens/*.tscn) and returns it.
func open_screen(path: String, kind: String) -> Control:
	_drop_screen()
	for c in sheet_box.get_children():
		c.queue_free()
	sheet_center.visible = false
	overlay.visible = true
	overlay_kind = kind
	set_sel(null, true)
	screen = load(path).instantiate()
	overlay.add_child(screen)
	if not reduced:
		screen.modulate.a = 0
		_anim(screen, "screen").tween_property(screen, "modulate:a", 1.0, 0.22)
	return screen


func close_overlay() -> void:
	overlay.visible = false
	overlay_kind = ""
	_drop_screen()
	sheet_center.visible = true
	for c in sheet_box.get_children():
		c.queue_free()


## Sizes the sheet to its content, scrolling when it is taller than the window.
func _fit_sheet() -> void:
	if not overlay.visible:
		return
	var want := sheet_box.get_combined_minimum_size().y
	sheet_scroll.custom_minimum_size.y = minf(want, maxf(200, overlay.size.y - 80))
	sheet_scroll.scroll_vertical = 0


func _go_button(text: String, fn: Callable) -> Button:
	var b := _btn(text, true)
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 50
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(fn)
	return b




## A row of buttons sharing the sheet width.
func _button_row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


func _menu_button(text: String, fn: Callable, primary := false) -> Button:
	var b := _btn(text, primary)
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(fn)
	return b


func _hero_view(h := 150.0) -> ClusterView:
	if hero.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		hero = ClusterView.hero_cluster(rng)
	var cv := ClusterView.new()
	cv.list = hero
	cv.custom_minimum_size = Vector2(SHEET_W - 44, h)
	return cv


# ---------- main menu ----------

func _resume() -> void:
	close_overlay()


func start_play() -> void:
	close_overlay()
	new_run()
	started = true
	run_active = true
	round_banner()
	if run_is_test:
		toast("Test run: everything unlocked. Not recorded on the scoreboard.")


func start_tutorial() -> void:
	close_overlay()
	new_run(Tutorial.SEED, true)
	started = true
	run_active = true
	show_banner("Tutorial", "Goal %s" % Defs.fmt(S.goal()))


func _focus_first_button() -> void:
	for c in sheet_box.get_children():
		if c is Button:
			c.grab_focus.call_deferred()
			return


# ---------- rules sheet (the ? button) ----------

func _overlay_back() -> void:
	if overlay_back == "menu":
		show_main_menu()
	elif overlay_back == "end":
		_show_end_again()
	else:
		close_overlay()


# ---------- scoreboard ----------

# ---------- tutorial callout ----------

func _tut(event: String) -> void:
	if tut != null and tut.notify(event):
		render_tutorial()


func render_tutorial() -> void:
	tut_panel.visible = tut != null and not tut_hidden
	if tut == null:
		return
	var st: Dictionary = tut.current()
	tut_title.text = "%s  ·  %d/%d" % [st.title, tut.step + 1, Tutorial.STEPS.size()]
	tut_text.text = st.text
	tut_next.visible = st.event == "" or tut.is_last()
	tut_next.text = "Got it" if tut.is_last() else "Next"
	tut_wait.visible = st.event != "" and not tut.is_last()
	tut_panel.reset_size()
	if not reduced:
		tut_panel.pivot_offset = tut_panel.size / 2
		tut_panel.modulate.a = 0.0
		var tw := _anim(tut_panel, "tut")
		tw.tween_property(tut_panel, "modulate:a", 1.0, 0.22)


func _tut_next() -> void:
	if tut == null:
		return
	if tut.is_last():
		tut_hidden = true
		render_tutorial()
		return
	tut.next()
	render_tutorial()


func _tut_skip() -> void:
	_save_setting("tutorial_done", true)
	tut = null
	run_active = false
	render_tutorial()
	show_main_menu()


func show_tutorial_end(cleared: bool) -> void:
	open_overlay()
	overlay_kind = "end"
	run_active = false
	if cleared:
		_save_setting("tutorial_done", true)
	sheet_box.add_child(_lbl("Tutorial complete" if cleared else "Not quite", 30, Pal.ink, true))
	var body := "You reached %s of %s. In a real run there are %d rounds with rising goals, and after each round you pick a relic that bends the rules in your favor." % [Defs.fmt(S.round_score), Defs.fmt(S.goal()), Defs.ROUNDS] if cleared \
		else "You reached %s of %s. Try to match more edges and close areas of land, then the harvest has more to score." % [Defs.fmt(S.round_score), Defs.fmt(S.goal())]
	sheet_box.add_child(_para(body))
	tut = null
	render_tutorial()
	sheet_box.add_child(_menu_button("Play a real run" if cleared else "Try the tutorial again", start_play if cleared else start_tutorial, true))
	sheet_box.add_child(_menu_button("Main menu", show_main_menu))
	_focus_first_button()


# ---------- rounds and run end ----------

func end_round() -> void:
	S.mark_cleared()
	_check_unlocks()
	if tut != null:
		show_tutorial_end(true)
		return
	if S.is_last_round():
		win()
		return
	S.picks = 2 if S.boss != "" else 1
	show_draft(true)


func show_draft(first: bool) -> void:
	var pool := S.draft_pool()
	if pool.is_empty():
		close_overlay()
		S.next_round()
		_after_start_round()
		return
	var title := "One more relic"
	var body := "Pick your second relic."
	if first:
		title = (Defs.boss(S.boss).name + " beaten") if S.boss != "" else ("Round %d cleared" % (S.round_idx + 1))
		body = "You scored %s against a goal of %s. " % [Defs.fmt(S.round_score), Defs.fmt(S.goal())]
		body += "Boss rounds pay double, so you get two relics. Pick the first." if S.boss != "" else "Pick a relic to keep for the rest of the run."
	open_overlay()
	overlay_kind = "draft"
	sheet_box.add_child(_lbl(title, 28, Pal.ink, true))
	sheet_box.add_child(_para(body))
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	sheet_box.add_child(cards)
	for i in pool.size():
		var r: Dictionary = pool[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(SHEET_W - 44, 78)
		card.focus_mode = Control.FOCUS_ALL
		card.add_theme_stylebox_override("normal", _sb(Pal.bg2, 14, Pal.line, 1))
		card.add_theme_stylebox_override("hover", _sb(Pal.bg2, 14, Pal.soft, 1))
		card.add_theme_stylebox_override("pressed", _sb(Pal.bg2.darkened(0.05), 14, Pal.soft, 1))
		card.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), 14, Pal.chips, 2))
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 12 if side in ["left", "right"] else 10)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		var tv := TileView.new()
		tv.custom_minimum_size = Vector2(54, 54)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.tile = Tile.mono(r.t, hash(r.id) & 0x7fffffff)
		row.add_child(tv)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		var nm := _lbl(r.name, 17, Pal.ink, true)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_theme_constant_override("separation", 8)
		head.add_child(nm)
		if r.rarity > 0:
			# Fine (blue) and Heirloom (gold) relics are rarer: flag them
			var rl := _lbl(Defs.RARITY_NAMES[r.rarity], 13, Color("#8fc3e8") if r.rarity == 1 else Pal.gold, true)
			rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			head.add_child(rl)
			card.add_theme_stylebox_override("normal", _sb(Pal.bg2, 14, Pal.gold if r.rarity == 2 else Color("#8fc3e8"), 1))
		col.add_child(head)
		var ds := _para(r.desc, 14, Pal.soft, SHEET_W - 44 - 24 - 54 - 12)
		ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ds)
		row.add_child(col)
		m.add_child(row)
		card.add_child(m)
		var rid: String = r.id
		card.pressed.connect(func(): _pick_relic(rid))
		cards.add_child(card)
		if not reduced:
			card.modulate.a = 0
			var tw := card.create_tween()
			tw.tween_interval(0.07 * i)
			tw.tween_property(card, "modulate:a", 1.0, 0.3)
		if i == 0:
			card.grab_focus.call_deferred()


func _pick_relic(id: String) -> void:
	S.relics.append(id)
	sfx.pick()
	S.picks -= 1
	if S.picks > 0:
		show_draft(false)
	else:
		close_overlay()
		toast(Defs.relic(id).name + " added")
		S.next_round()
		_after_start_round()


func _stats() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for it in [[Defs.fmt(S.best_harvest), "Best harvest"], [str(S.perfects), "Perfects"], [str(S.best_streak), "Best streak"], [str(S.quests), "Quests"], [str(S.lines_closed), "Lines closed"], [str(S.regions_closed), "Areas closed"], [str(S.biggest_closed), "Biggest closed area"], [str(S.relics.size()), "Relics"]]:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", _sb(Pal.bg2, 12, Color(0, 0, 0, 0), 0, Vector4(10, 8, 10, 8)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(_lbl(it[0], 20, Pal.ink, true))
		v.add_child(_lbl(it[1], 13, Pal.soft))
		p.add_child(v)
		g.add_child(p)
	return g


## End of a real run: records it on the scoreboard and shows the summary.
func _end_sheet(title: String, body: String, won: bool) -> void:
	run_active = false
	last_rank = 0 if run_is_test else Scores.record(settings_path, Scores.make_entry(S, won))
	_end_title = title
	_end_body = body
	_show_end_again()


func _show_end_again() -> void:
	open_overlay()
	overlay_kind = "end"
	sheet_box.add_child(_lbl(_end_title, 28, Pal.ink, true))
	if last_rank == 1:
		sheet_box.add_child(_lbl("New best run!", 20, Pal.gold, true))
	elif last_rank > 0:
		sheet_box.add_child(_lbl("#%d on your scoreboard" % last_rank, 18, Pal.gold, true))
	sheet_box.add_child(_para(_end_body))
	if run_is_test:
		sheet_box.add_child(_para("Test run: not recorded on the scoreboard and no achievements earned.", 14, Pal.soft))
	elif not unlocked_this_run.is_empty():
		var got: Array[String] = []
		for a in unlocked_this_run:
			got.append(_unlock_name(a))
		sheet_box.add_child(_para("Unlocked this run: " + ", ".join(got), 16, Pal.gold))
	sheet_box.add_child(_stats())
	sheet_box.add_child(_menu_button("New run", start_play, true))
	sheet_box.add_child(_button_row([
		_menu_button("Scoreboard", show_scoreboard.bind("end")),
		_menu_button("Main menu", show_main_menu),
	]))
	_focus_first_button()


func game_over() -> void:
	_check_unlocks()
	if tut != null:
		show_tutorial_end(false)
		return
	_end_sheet("The harvest came up short", "Round %d ended at %s of %s. Your run scored %s points in total." % [S.round_idx + 1, Defs.fmt(S.round_score), Defs.fmt(S.goal()), Defs.fmt(S.total)], false)


func win() -> void:
	var body := "Your countryside held up. The run scored %s points with %d relics." % [Defs.fmt(S.total), S.relics.size()]
	if not run_is_test and Unlocks.record_win(settings_path, S.season):
		body += " Season %d is now open: tougher goals for a bigger challenge." % (S.season + 1)
		season_pick = S.season + 1
	_end_sheet("Season %d cleared" % S.season, body, true)


# ---------- unlocks and collection ----------

## Checks achievements after play events; unlocked items join this run at once.
func _check_unlocks() -> void:
	if tut != null or run_is_test or S == null:
		return
	var fresh := Unlocks.check(settings_path, S)
	if fresh.is_empty():
		return
	var names: Array[String] = []
	for a in fresh:
		unlocked_this_run.append(a)
		if a.kind == "special":
			if not S.allowed_specials.has(a.id):
				S.allowed_specials.append(a.id)
		elif not S.allowed_relics.has(a.id):
			S.allowed_relics.append(a.id)
		names.append(_unlock_name(a))
	toast("Unlocked: %s! See Collection in the menu." % ", ".join(names))
	sfx.clear()


func _unlock_name(a: Dictionary) -> String:
	return Defs.SPECIALS[a.id].name if a.kind == "special" else Defs.relic(a.id).name



# ---------- full-screen scenes (ui/screens) ----------

const MENU_SCENE := "res://ui/screens/main_menu.tscn"
const COLLECTION_SCENE := "res://ui/screens/collection.tscn"
const RULES_SCENE := "res://ui/screens/rules.tscn"
const SCOREBOARD_SCENE := "res://ui/screens/scoreboard.tscn"


## Title screen at launch, and the pause menu (Esc) during a run.
func show_main_menu() -> void:
	var m = open_screen(MENU_SCENE, "menu")
	season_pick = clampi(season_pick, 1, Unlocks.seasons_open(settings_path))
	var info := ""
	if run_active:
		info = ("Tutorial" if tut != null else "Season %d · Round %d of %d" % [S.season, S.round_idx + 1, Defs.ROUNDS]) + " · %s points" % Defs.fmt(S.round_score if tut != null else S.total)
	if hero.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		hero = ClusterView.hero_cluster(rng)
	m.setup({
		"run_active": run_active, "run_info": info, "first_time": not _get_setting("tutorial_done", false),
		"season": season_pick, "seasons_open": Unlocks.seasons_open(settings_path), "test_run": test_run,
		"best": get_best(), "progress": Unlocks.progress(settings_path), "next_unlock": _next_unlock_text(), "hero": hero,
	})
	m.continue_pressed.connect(_resume)
	m.play_pressed.connect(start_play)
	m.tutorial_pressed.connect(start_tutorial)
	m.collection_pressed.connect(func(): show_collection("menu"))
	m.scoreboard_pressed.connect(func(): show_scoreboard("menu"))
	m.rules_pressed.connect(func(): show_rules("menu"))
	m.quit_pressed.connect(func(): get_tree().quit())
	m.season_changed.connect(func(s): season_pick = s)
	m.test_run_toggled.connect(func(on): test_run = on)


## The next couple of achievements still locked, for the menu's progress card.
func _next_unlock_text() -> String:
	var ids := Unlocks.load_ids(settings_path)
	var lines: Array[String] = []
	for a in Unlocks.LIST:
		if not ids.has(a.id):
			lines.append("%s: %s" % [_unlock_name(a), a.how])
			if lines.size() == 2:
				break
	return "Everything unlocked!" if lines.is_empty() else "Next up  ·  " + "\n".join(lines)


## How to play. `back` is where Back returns: "board", "menu" or "end".
func show_rules(back := "board") -> void:
	overlay_back = back
	var r = open_screen(RULES_SCENE, "rules")
	r.back_pressed.connect(_overlay_back)


func show_scoreboard(back := "menu") -> void:
	overlay_back = back
	var sb = open_screen(SCOREBOARD_SCENE, "scores")
	sb.setup(settings_path, last_rank)
	sb.back_pressed.connect(_overlay_back)


## Every special tile, relic and Season: unlocked ones say what they do, locked
## ones are blacked out and say how to unlock them.
func show_collection(back := "menu") -> void:
	overlay_back = back
	var c = open_screen(COLLECTION_SCENE, "collection")
	c.setup(settings_path)
	c.back_pressed.connect(_overlay_back)
