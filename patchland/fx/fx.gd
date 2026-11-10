class_name Fx
extends RefCounted
## Particles, floating text, rings and beams. Positions are in world units
## (hex radius = 1); drawing converts to screen through a Board.

var parts: Array = []
var floats: Array = []
var rings: Array = []
var beams: Array = []
var reduced := false


func clear() -> void:
	parts.clear()
	floats.clear()
	rings.clear()
	beams.clear()


func busy() -> bool:
	return not (parts.is_empty() and floats.is_empty() and rings.is_empty() and beams.is_empty())


static func now() -> float:
	return float(Time.get_ticks_msec())


func burst(x: float, y: float, n: int, colors: Array, o := {}) -> void:
	var speed: float = o.get("speed", 2.2)
	var up: float = o.get("up", 1.5)
	var grav: float = o.get("grav", 6.0)
	var life: float = o.get("life", 0.7)
	var size: float = o.get("size", 0.07)
	var spread: float = o.get("spread", TAU)
	var dir: float = o.get("dir", -PI / 2)
	var shape: String = o.get("shape", "sq")
	var drag: float = o.get("drag", 0.0)
	for i in n:
		var a := dir + (randf() - 0.5) * spread
		var sp := speed * (0.4 + randf() * 0.8)
		parts.append({"x": x, "y": y, "vx": cos(a) * sp, "vy": sin(a) * sp - up * randf(), "g": grav,
			"life": life * (0.6 + randf() * 0.6), "t": 0.0, "c": colors[randi() % colors.size()],
			"s": size * (0.6 + randf() * 0.8), "rot": randf() * 6, "vr": (randf() - 0.5) * 12, "shape": shape, "drag": drag})


func dust(wx: float, wy: float) -> void:
	if reduced:
		return
	var cols := [Color("#b8a588"), Color("#9c8a6c"), Color("#cdbfa3")]
	for k in 14:
		var a := PI * (0.05 + 0.9 * randf())
		var cs := cos(a)
		var sn := sin(a)
		parts.append({"x": wx + cs * 0.9, "y": wy + sn * 0.75 + 0.15, "vx": cs * 1.1, "vy": sn * 0.35 - 0.2, "g": 0.0, "drag": 4.0,
			"life": 0.45 + randf() * 0.25, "t": 0.0, "c": cols[k % 3], "s": 0.1 + randf() * 0.06, "rot": 0.0, "vr": 0.0, "shape": "dust"})


func ring(x: float, y: float, dur: float, c: Color, grow: float) -> void:
	rings.append({"x": x, "y": y, "t0": now(), "dur": dur, "c": c, "grow": grow})


func beam(x1: float, y1: float, x2: float, y2: float) -> void:
	beams.append({"x1": x1, "y1": y1, "x2": x2, "y2": y2, "t0": now()})


func float_at(x: float, y: float, text: String, color: String, scale := 1.0, stamp := false, dur := 1100.0, rise := 26.0) -> void:
	floats.append({"x": x, "y": y, "text": text, "color": color, "scale": scale, "stamp": stamp, "dur": dur, "rise": rise, "t0": now()})
	if floats.size() > 60:
		floats = floats.slice(floats.size() - 60)


func edge_fx(wx: float, wy: float, i: int, c: int, terr: String) -> void:
	var a := -i * PI / 3
	var ex := wx + cos(a) * 0.87
	var ey := wy + sin(a) * 0.87
	if not reduced:
		burst(ex, ey, 6, [Defs.top(terr), Color.WHITE], {"speed": 1.6, "up": 1.2, "grav": 5.0, "life": 0.5, "size": 0.06})
	float_at(ex, ey - 0.3, "+%d" % c, "chips" if c else "soft", 0.75, false, 700, 18)


func perfect_fx(wx: float, wy: float, tile: Tile) -> void:
	ring(wx, wy, 520, Color.WHITE, 1.3)
	if not reduced:
		var cols: Array = []
		for t in tile.kinds():
			cols.append(Defs.top(t))
		cols.append(Color.WHITE)
		burst(wx, wy - 0.2, 26, cols, {"speed": 3.4, "up": 2.5, "grav": 7.0, "life": 0.9})


func gold_fx(wx: float, wy: float) -> void:
	ring(wx, wy, 520, Color("#f5c542"), 1.0)
	if not reduced:
		burst(wx, wy - 0.2, 18, [Color("#f5c542"), Color("#fff3b0"), Color("#e2a91a")], {"speed": 2.8, "up": 2.0, "grav": 5.0, "life": 0.9, "shape": "star"})


func quest_fx(wx: float, wy: float) -> void:
	ring(wx, wy, 700, Color("#f5c542"), 2.0)
	if not reduced:
		burst(wx, wy - 0.8, 24, [Color("#f5c542"), Color("#fff3b0"), Color.WHITE], {"speed": 3.0, "up": 2.5, "grav": 6.0, "life": 1.0, "shape": "star"})


## view: Rect2 of the visible world area.
func clear_fx(view: Rect2, amount := 1.0) -> void:
	if reduced:
		return
	var cols: Array = []
	for t in Defs.TKEYS:
		cols.append(Defs.top(t))
	cols.append(Color.WHITE)
	cols.append(Color("#f5c542"))
	var cx := view.get_center().x
	for k in 5:
		burst(cx + (k - 2) * view.size.x / 5, view.position.y, int(round(18 * amount)), cols,
			{"speed": 2.0, "up": 0.0, "grav": 4.0, "life": 1.8, "dir": PI / 2, "spread": 1.6, "size": 0.1})


func update(dt: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p.t += dt
		if p.t >= p.life:
			parts.remove_at(i)
			continue
		p.vy += p.g * dt
		var dr := maxf(0, 1 - p.drag * dt)
		p.vx *= dr
		p.vy *= dr
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.rot += p.vr * dt


## Draws beams, rings, particles and floats in screen space.
## ws: Callable(Vector2 world) -> Vector2 screen; size: px per world unit.
func draw(ci: CanvasItem, ws: Callable, size: float) -> void:
	var t := now()
	for i in range(beams.size() - 1, -1, -1):
		var b: Dictionary = beams[i]
		var k: float = (t - b.t0) / 480.0
		if k >= 1:
			beams.remove_at(i)
			continue
		var p1: Vector2 = ws.call(Vector2(b.x1, b.y1))
		var p2: Vector2 = ws.call(Vector2(b.x2, b.y2))
		var off := size * 0.25
		var a: float = 1 - k
		var s1 := p1 - Vector2(0, off)
		var s2 := p2 - Vector2(0, off * 0.4)
		var wide := size * 0.24
		ci.draw_line(s1, s2, Color(1, 0.839, 0.353, 0.55 * a), wide, true)
		ci.draw_circle(s1, wide / 2, Color(1, 0.839, 0.353, 0.55 * a))
		ci.draw_circle(s2, wide / 2, Color(1, 0.839, 0.353, 0.55 * a))
		ci.draw_line(s1, s2, Color(1, 0.984, 0.902, a), maxf(1.5, size * 0.06), true)

	for i in range(rings.size() - 1, -1, -1):
		var g: Dictionary = rings[i]
		var k: float = (t - g.t0) / g.dur
		if k >= 1:
			rings.remove_at(i)
			continue
		var c: Color = g.c
		c.a = 1 - k
		TileArt.stroke_hex(ci, ws.call(Vector2(g.x, g.y)), size * (0.95 + k * g.grow), c, maxf(1, size * 0.1 * (1 - k)))

	for p in parts:
		var pos: Vector2 = ws.call(Vector2(p.x, p.y))
		var a: float = 1 - p.t / p.life
		var s: float = p.s * size
		var c: Color = p.c
		if p.shape == "dust":
			c.a = a * 0.55
			s *= 1 + p.t / p.life * 1.5
			ci.draw_circle(pos, s / 2, c)
		elif p.shape == "star":
			c.a = a
			TileArt.star(ci, pos, s * 0.8, c)
		else:
			c.a = a
			ci.draw_set_transform(pos, p.rot)
			ci.draw_rect(Rect2(-s / 2, -s / 4, s, s / 2), c)
			ci.draw_set_transform(Vector2.ZERO)

	var font := Pal.bold
	for i in range(floats.size() - 1, -1, -1):
		var f: Dictionary = floats[i]
		var k: float = (t - f.t0) / f.dur
		if k >= 1:
			floats.remove_at(i)
			continue
		var pos: Vector2 = ws.call(Vector2(f.x, f.y))
		var yy: float = pos.y - (0.0 if reduced else k * f.rise)
		var sc2: float = 1.6 - 0.6 * (k / 0.15) if f.stamp and not reduced and k < 0.15 else 1.0
		var alpha: float = 1.0 if k < 0.7 else 1 - (k - 0.7) / 0.3
		var fs := maxi(6, int(round((13 + size * 0.15) * f.scale * sc2)))
		var w := 1200.0
		var bgc := Pal.bg
		bgc.a = alpha
		var col := Pal.named(f.color)
		col.a = alpha
		var tp := Vector2(pos.x - w / 2, yy)
		ci.draw_string_outline(font, tp, f.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 8, bgc)
		ci.draw_string(font, tp, f.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
