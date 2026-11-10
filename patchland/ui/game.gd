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
var hud_m: MarginContainer
var rel_m: MarginContainer
var tray_m: MarginContainer
var fs_icon: IconView
const CONTENT_W := 1180.0


# ======================================================================
# setup
# ======================================================================

func _ready() -> void:
	Pal.init()
	RenderingServer.set_default_clear_color(Pal.bg)
	DisplayServer.window_set_min_size(Vector2i(760, 680))
	var th := Theme.new()
	th.default_font = Pal.font
	th.default_font_size = 15
	th.set_color("font_color", "Label", Pal.ink)
	theme = th
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	sfx = Sfx.new()
	sfx.muted = muted
	add_child(sfx)
	_build_ui()
	resized.connect(_layout)
	_layout()
	new_run()
	show_intro()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		muted = cfg.get_value("game", "muted", false)
		if cfg.get_value("game", "fullscreen", false) and DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save_setting(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("game", key, value)
	cfg.save(settings_path)


func get_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		return cfg.get_value("game", "best", 0)
	return 0


func save_best(n: int) -> void:
	if n > get_best():
		_save_setting("best", n)


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
	var bg := Pal.mult if primary else Pal.bg2
	var border := Color(0, 0, 0, 0) if primary else Pal.line
	b.add_theme_stylebox_override("normal", _sb(bg, radius, border, 1))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.06) if primary else bg.darkened(0.04), radius, Pal.soft if not primary else border, 1))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.08), radius, border, 1))
	b.add_theme_stylebox_override("disabled", _sb(Color(bg, 0.4), radius, Color(border, border.a * 0.4), 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color.WHITE if primary else Pal.ink
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_color_override("font_focus_color", fc)
	b.add_theme_color_override("font_disabled_color", Color(fc, 0.4))
	b.add_theme_font_override("font", Pal.bold)
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
	var help_btn := _icon_btn()
	help_btn.text = "?"
	help_btn.tooltip_text = "How to play"
	help_btn.pressed.connect(show_intro)
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

	var readout := VBoxContainer.new()
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.alignment = BoxContainer.ALIGNMENT_CENTER
	readout.add_theme_constant_override("separation", 6)
	row.add_child(readout)
	var calc := HBoxContainer.new()
	calc.add_theme_constant_override("separation", 6)
	readout.add_child(calc)
	chips_panel = PanelContainer.new()
	chips_panel.add_theme_stylebox_override("panel", _sb(Pal.chips, 10, Color(0, 0, 0, 0), 0, Vector4(10, 2, 10, 2)))
	chips_lbl = _lbl("0", 22, Color.WHITE, true)
	chips_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chips_lbl.custom_minimum_size.x = 24
	chips_panel.add_child(chips_lbl)
	calc.add_child(chips_panel)
	calc.add_child(_lbl("×", 18, Pal.soft))
	mult_panel = PanelContainer.new()
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
	sheet = PanelContainer.new()
	var sheet_sb := _sb(Pal.panel, 20, Color(0, 0, 0, 0), 0, Vector4(22, 22, 22, 20))
	sheet_sb.shadow_color = Color(0, 0, 0, 0.25)
	sheet_sb.shadow_size = 24
	sheet_sb.shadow_offset = Vector2(0, 12)
	sheet.add_theme_stylebox_override("panel", sheet_sb)
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

func new_run() -> void:
	_seq.clear()
	_steps.clear()
	harvesting = false
	hl_region = null
	board.clear_tiles()
	S = RunState.new()
	S.new_run()
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
	if S.has_relic("almanac") and S.almanac > 0:
		step_q(250, func():
			acc.mult += S.almanac
			show_calc(acc.chips, acc.mult)
			pop(mult_panel)
			sfx.mult(0)
			toast("Almanac +%d mult" % S.almanac))
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
				board.fx.float_at(lp.x, lp.y - 1.2, ("%s ×%d, %d %s: +%d mult" % [Defs.name_of(r.t), r.n, r.ends, "stations" if r.t == "rail" else "water ends", r.mult]) if r.has("ends") else ("%s ×%d: +%d mult" % [Defs.name_of(r.t), r.n, r.mult]), "mult", 0.9, true, 1000)
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
				board.fx.float_at(sp.x, sp.y - 1.3, "%s +%d mult" % [Defs.SPECIALS[src.tile.special].name, add], "mult", 0.9, true, 1000)
				sfx.mult(6)
				board.shake(1.5))
	step_q(700, func():
		var total := int(round(float(acc.chips) * acc.mult))
		S.apply_harvest(total)
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
		var close_pts := 0
		for net in S.closed_lines(S.board[k]):
			close_pts += Rules.close_bonus(S, net)
		cur_eval.close_bonus = close_pts
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
		return out + "%s: %s Every tile hit scores its land again, and hitting another special sets it off. " % [Defs.SPECIALS[t.special].name, Defs.SPECIALS[t.special].desc]
	if t.is_station():
		out += "Station: railroads start and end in cities. A line between two stations scores in the harvest, +1 mult per station. "
	elif t.feature() == "rail":
		out += "Railroad: link track for +8 chips and +1 mult per edge. Track must meet track. "
	elif t.feature() == "river":
		out += "River: flows out of and into water. Link it for +6 chips and +1 mult per edge; it can't be cut. A river that reaches water at both ends scores in the harvest. "
	if t.has_quest():
		return out + "Quest: link %d %s tiles through matching edges. " % [t.quest.need, Defs.TER[t.quest.t].name.to_lower()]
	if t.gold:
		return out + "Golden tile: its mult is doubled. "
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
		h += " Links %s: +%d chips, +%d mult." % [" and ".join(kinds), cur_eval.feat_sum, cur_eval.feat_matches]
	var hits := Rules.count_hits(cur_eval.events)
	if hits:
		h += " Rays hit %d tile%s for +%d chips." % [hits, "s" if hits > 1 else "", cur_eval.ray_chips]
	var extras: Array[String] = []
	if cur_eval.chip_add:
		extras.append("Monoculture +%d chips" % cur_eval.chip_add)
	for a in cur_eval.adds:
		extras.append("%s +%d" % [a[0], a[1]])
	for m in cur_eval.muls:
		extras.append("%s ×%d" % [m[0], m[1]])
	if not extras.is_empty():
		h += " " + ", ".join(extras) + "."
	elif not cur_eval.matches and not hits and not cur_eval.feat_matches:
		h += " Rotate to find a match."
	if cur_eval.get("close_bonus", 0):
		h += " Closes a line: +%s bonus." % Defs.fmt(cur_eval.close_bonus)
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

func open_overlay() -> void:
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


func close_overlay() -> void:
	overlay.visible = false
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


func show_intro() -> void:
	if hero.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		hero = ClusterView.hero_cluster(rng)
	open_overlay()
	sheet_box.add_child(_lbl("Patchland", 46, Pal.ink, true))
	var cv := ClusterView.new()
	cv.list = hero
	cv.custom_minimum_size = Vector2(SHEET_W - 44, 150)
	sheet_box.add_child(cv)
	sheet_box.add_child(_para("Lay hex tiles to grow a patch of countryside. Every edge that matches the land beside it adds its chips and +1 mult, and matching every neighbor doubles the mult."))
	sheet_box.add_child(_para("When your tiles run out, the harvest scores every region of linked land on the whole board, and bigger regions add more mult. Your placements plus the harvest must reach the goal."))
	sheet_box.add_child(_para("Windmills, lighthouses and bell towers fire rays that score every tile they hit, and a ray that hits another special tile sets it off too. Golden tiles, quest flags, perfect streaks and boss rounds (3, 6 and 8) add extra twists."))
	sheet_box.add_child(_para("Rivers and railroads score extra when they link across an edge. Railroads run between stations in cities, rivers flow out of and into water, and you can never place a tile that cuts one. A line that runs end to end scores again in the harvest."))
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 12)
	legend.add_theme_constant_override("v_separation", 6)
	var order: Array = Defs.TKEYS.duplicate()
	order.sort_custom(func(a, b): return Defs.TER[a].chips > Defs.TER[b].chips)
	order.append_array(Defs.FKEYS)
	for t in order:
		var it := HBoxContainer.new()
		it.add_theme_constant_override("separation", 6)
		var ic := IconView.new()
		ic.kind = "hex"
		ic.color = Defs.top(t)
		ic.custom_minimum_size = Vector2(12, 13)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		it.add_child(ic)
		it.add_child(_lbl(Defs.name_of(t), 14, Pal.soft))
		it.add_child(_lbl(str((Defs.FEAT[t] if Defs.FEAT.has(t) else Defs.TER[t]).chips), 14, Pal.ink, true))
		legend.add_child(it)
	sheet_box.add_child(legend)
	sheet_box.add_child(_para("Rotate by right-clicking (shift + right-click turns the other way), Ctrl + scroll, R / Q, the Rotate button, or by clicking your tile. Redraw swaps your tile for the next one. Scroll to zoom, drag or use WASD to move the view, and press F (or double-click empty ground) to see the whole board again. F11 toggles fullscreen.", 14, Pal.soft))
	var best := get_best()
	if best > 0:
		sheet_box.add_child(_para("Best run: %s points" % Defs.fmt(best), 14, Pal.soft))
	var b := _go_button("Back to the board" if started else "Start run", func():
		var first := not started
		started = true
		close_overlay()
		if first:
			round_banner())
	sheet_box.add_child(b)
	b.grab_focus.call_deferred()


func end_round() -> void:
	save_best(S.total)
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
		col.add_child(nm)
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
	for it in [[Defs.fmt(S.best_harvest), "Best harvest"], [str(S.perfects), "Perfects"], [str(S.best_streak), "Best streak"], [str(S.quests), "Quests"], [str(S.lines_closed), "Lines closed"], [str(S.relics.size()), "Relics"]]:
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


func _end_sheet(title: String, body: String) -> void:
	save_best(S.total)
	open_overlay()
	sheet_box.add_child(_lbl(title, 28, Pal.ink, true))
	sheet_box.add_child(_para(body))
	sheet_box.add_child(_stats())
	sheet_box.add_child(_para("Best run: %s points" % Defs.fmt(get_best()), 14, Pal.soft))
	var b := _go_button("New run", func():
		close_overlay()
		new_run())
	sheet_box.add_child(b)
	b.grab_focus.call_deferred()


func game_over() -> void:
	_end_sheet("The harvest came up short", "Round %d ended at %s of %s. Your run scored %s points in total." % [S.round_idx + 1, Defs.fmt(S.round_score), Defs.fmt(S.goal()), Defs.fmt(S.total)])


func win() -> void:
	_end_sheet("All 8 rounds cleared", "Your countryside held up. The run scored %s points with %d relics." % [Defs.fmt(S.total), S.relics.size()])
