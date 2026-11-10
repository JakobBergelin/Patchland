class_name TileView
extends Control
## Draws one tile fitted into the control (tray current/next, relic cards).

signal rotate_clicked(dir: int)

var tile: Tile:
	set(v):
		tile = v
		queue_redraw()
var fogged := false:
	set(v):
		fogged = v
		queue_redraw()
var interactive := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(func(): pivot_offset = size / 2)
	pivot_offset = size / 2


func _draw() -> void:
	if tile == null:
		return
	if fogged:
		var c := Pal.soft
		c.a = 0.5
		var r := minf(size.x, size.y) * 0.36
		draw_colored_polygon(TileArt.hex_pts(size / 2, r), c)
		var fs := int(round(size.y * 0.38))
		var f := Pal.bold
		var base := size.y / 2 + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
		draw_string(f, Vector2(0, base), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)
		return
	TileArt.draw_fitted(self, Pal.bold, Rect2(Vector2.ZERO, size), tile)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			rotate_clicked.emit(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			rotate_clicked.emit(-1 if event.shift_pressed else 1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rotate_clicked.emit(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			rotate_clicked.emit(-1)
			accept_event()
