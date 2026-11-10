class_name GoalBar
extends Control
## Score bar: solid fill for the round score, a lighter segment for the projection
## ("on pace" turns it gold), red when the goal is reached.

var fill := 0.0
var proj := 0.0
var pace := false
var done := false
var _fill_shown := 0.0
var _proj_shown := 0.0


func set_values(f: float, p: float, is_pace: bool, is_done: bool) -> void:
	fill = clampf(f, 0, 1)
	proj = clampf(p, 0, 1 - fill)
	pace = is_pace
	done = is_done


func _process(dt: float) -> void:
	var k := minf(1, dt * 12)
	var nf := lerpf(_fill_shown, fill, k)
	var np := lerpf(_proj_shown, proj, k)
	if absf(nf - _fill_shown) > 0.0001 or absf(np - _proj_shown) > 0.0001:
		_fill_shown = nf
		_proj_shown = np
		queue_redraw()


func _bar(x: float, w: float, col: Color) -> void:
	if w <= 0.5:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(size.y / 2))
	draw_style_box(sb, Rect2(x, 0, w, size.y))


func _draw() -> void:
	_bar(0, size.x, Pal.line)
	var pc := Pal.gold if pace else Pal.chips
	pc.a = 0.6 if pace else 0.32
	_bar(size.x * _fill_shown, size.x * _proj_shown, pc)
	_bar(0, size.x * _fill_shown, Pal.mult if done else Pal.chips)
