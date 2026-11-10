class_name IconView
extends Control
## Small vector icons: "sound_on", "sound_off", or "hex" (terrain dot).

var kind := "hex":
	set(v):
		kind = v
		queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2
	if kind == "hex":
		var pts := PackedVector2Array()
		for k in 6:
			var a := deg_to_rad(60 * k - 90)
			pts.append(c + Vector2(cos(a) * size.x / 2, sin(a) * size.y / 2))
		draw_colored_polygon(pts, color)
		return
	var s := minf(size.x, size.y) / 24.0
	var o := c - Vector2(12, 12) * s
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	draw_colored_polygon(PackedVector2Array([P.call(4, 9), P.call(8, 9), P.call(13, 5), P.call(13, 19), P.call(8, 15), P.call(4, 15)]), color)
	if kind == "sound_on":
		draw_arc(P.call(12, 12), 5 * s, -0.8, 0.8, 10, color, 2 * s, true)
		draw_arc(P.call(12, 12), 8.5 * s, -0.8, 0.8, 14, color, 2 * s, true)
	else:
		draw_line(P.call(17, 9), P.call(22, 15), color, 2 * s, true)
		draw_line(P.call(22, 9), P.call(17, 15), color, 2 * s, true)
