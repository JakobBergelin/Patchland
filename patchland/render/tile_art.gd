class_name TileArt
## Procedural tile art (port of renderTile and friends). Every function draws on
## `ci` inside its draw callback, in tile-local units where the tile centre is
## (0, 0) and the hex radius is S0. Nothing here touches game rules.

const S0 := 48.0
const DEPTH := 0.24
const PADT := 0.6
const PADS := 0.1
const HUB := 0.38  # windmill hub height above tile centre, in tile radii
## Sprite box around the tile, relative to the tile centre.
const BOX_W := (Hex.SQ3 + 2 * PADS) * S0
const BOX_TOP := -(PADT + 1) * S0
const BOX_BOTTOM := (1 + DEPTH + PADS) * S0
const BOX_H := BOX_BOTTOM - BOX_TOP

const SHADOW := Color(0, 0, 0, 0.18)


static func hex_pts(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60 * k - 30)
		pts.append(c + Vector2(cos(a), sin(a)) * s)
	return pts


static func stroke_hex(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	var pts := hex_pts(c, s)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w, true)


static func ellipse_pts(c: Vector2, rx: float, ry: float, n := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_colored_polygon(ellipse_pts(c, rx, ry), col)


## Upper half disc (canvas arc from PI to 0), closed by its chord.
static func half_disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI + PI * k / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)


static func poly(ci: CanvasItem, pts: Array, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), col)


static func rect(ci: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h), col)


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var a := k * PI / 4 - PI / 2
		var rr := r * 0.32 if k % 2 else r
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


static func tree(ci: CanvasItem, x: float, y: float, h: float, kind: int, shade: float) -> void:
	ellipse(ci, Vector2(x + h * 0.1, y), h * 0.3, h * 0.11, SHADOW)
	var trunk := Color("#5b4330")
	if kind == 0:
		var w := h * 0.4
		var dark := Color("#2c6340") if shade < 0.5 else Color("#28573b")
		var lite := Color("#3f8653") if shade < 0.5 else Color("#3a7a50")
		rect(ci, x - h * 0.04, y - h * 0.18, h * 0.08, h * 0.18, trunk)
		for k in 2:
			var by := y - h * 0.12 - k * h * 0.32
			var ty := by - h * 0.56
			var ww := w * (1 - k * 0.28)
			poly(ci, [Vector2(x, ty), Vector2(x + ww, by), Vector2(x - ww, by)], dark)
			poly(ci, [Vector2(x, ty), Vector2(x, by), Vector2(x - ww, by)], lite)
	else:
		rect(ci, x - h * 0.04, y - h * 0.32, h * 0.08, h * 0.32, trunk)
		var r := h * 0.3
		ci.draw_circle(Vector2(x, y - h * 0.58), r, Color("#3e7d45") if shade < 0.5 else Color("#4a7f3a"))
		ci.draw_circle(Vector2(x - r * 0.3, y - h * 0.58 - r * 0.3), r * 0.55, Color("#5aa05a") if shade < 0.5 else Color("#6aa64a"))


static func house(ci: CanvasItem, x: float, y: float, sz: float, flip: bool) -> void:
	var f := func(px: float, py: float) -> Vector2:
		return Vector2(2 * x - px if flip else px, py)
	var w := sz
	var hg := sz * 0.7
	var dx := sz * 0.45
	var dy := -sz * 0.25
	var ph := sz * 0.42
	var L := x - w / 2
	var R := x + w / 2
	var B := y
	var T := y - hg
	ellipse(ci, f.call(x + dx * 0.45, y + 1), w * 0.85, sz * 0.24, Color(0, 0, 0, 0.2))
	poly(ci, [f.call(R, B), f.call(R + dx, B + dy), f.call(R + dx, T + dy), f.call(R, T)], Color("#7c231f"))
	var front := Color("#a8322b")
	poly(ci, [f.call(L, T), f.call(R, T), f.call(R, B), f.call(L, B)], front)
	poly(ci, [f.call(L, T), f.call(x, T - ph), f.call(R, T)], front)
	poly(ci, [f.call(x, T - ph), f.call(x + dx, T - ph + dy), f.call(R + dx + sz * 0.06, T + dy + sz * 0.05), f.call(R + sz * 0.06, T + sz * 0.05)], Color("#3d3633"))
	var trim := Color("#f4efe6")
	ci.draw_polyline(PackedVector2Array([f.call(L - 0.4, T + 0.4), f.call(x, T - ph), f.call(R + 0.4, T + 0.4)]), trim, 0.9, true)
	ci.draw_line(f.call(L + 0.4, T), f.call(L + 0.4, B), trim, 0.9, true)
	ci.draw_line(f.call(R - 0.4, T), f.call(R - 0.4, B), trim, 0.9, true)
	var wx0: float = x - w * 0.32
	var wy0: float = B - hg * 0.68
	poly(ci, [f.call(wx0, wy0), f.call(wx0 + w * 0.2, wy0), f.call(wx0 + w * 0.2, wy0 + w * 0.2), f.call(wx0, wy0 + w * 0.2)], Color("#f6d77a"))
	var dx0: float = x + w * 0.08
	var dy0: float = B - hg * 0.6
	poly(ci, [f.call(dx0, dy0), f.call(dx0 + w * 0.2, dy0), f.call(dx0 + w * 0.2, B), f.call(dx0, B)], Color("#3a2420"))


static func hay(ci: CanvasItem, x: float, y: float, s: float) -> void:
	var r := s * 0.075
	ellipse(ci, Vector2(x + 1, y), r * 1.25, r * 0.45, Color(0, 0, 0, 0.16))
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI + PI * k / 12.0
		pts.append(Vector2(x, y - r * 0.4) + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(x + r, y))
	pts.append(Vector2(x - r, y))
	ci.draw_colored_polygon(pts, Color("#c79630"))
	ci.draw_circle(Vector2(x - r * 0.35, y - r * 0.75), r * 0.4, Color("#e8c06a"))


static func bush(ci: CanvasItem, x: float, y: float, s: float) -> void:
	var r := s * 0.07
	ellipse(ci, Vector2(x + 1, y), r * 1.3, r * 0.45, Color(0, 0, 0, 0.15))
	ci.draw_circle(Vector2(x, y - r * 0.6), r, Color("#5f9246"))
	ci.draw_circle(Vector2(x - r * 0.3, y - r * 0.9), r * 0.5, Color("#7cae58"))


static func taper(x: float, by: float, bw: float, tw: float, h: float, t0: float, t1: float) -> Array:
	var w0 := lerpf(bw, tw, t0)
	var w1 := lerpf(bw, tw, t1)
	var y0 := by - h * t0
	var y1 := by - h * t1
	return [Vector2(x - w0, y0), Vector2(x + w0, y0), Vector2(x + w1, y1), Vector2(x - w1, y1)]


static func structure(ci: CanvasItem, kind: String, x: float, y: float, s: float) -> void:
	var by := y + s * 0.12
	ellipse(ci, Vector2(x + s * 0.07, by), s * 0.2, s * 0.07, Color(0, 0, 0, 0.22))
	var shade := Color(0, 0, 0, 0.1)
	if kind == "windmill":
		var bw := s * 0.13
		var tw := s * 0.08
		var h := s * (0.12 + HUB)
		poly(ci, taper(x, by, bw, tw, h, 0, 1), Color("#efe6d4"))
		poly(ci, [Vector2(x, by), Vector2(x + bw, by), Vector2(x + tw, by - h), Vector2(x, by - h)], shade)
		var wood := Color("#5a4a3e")
		poly(ci, [Vector2(x - tw - s * 0.03, by - h), Vector2(x, by - h - s * 0.12), Vector2(x + tw + s * 0.03, by - h)], wood)
		rect(ci, x - s * 0.03, by - s * 0.11, s * 0.06, s * 0.11, wood)
	elif kind == "lighthouse":
		var bw := s * 0.11
		var tw := s * 0.07
		var h := s * 0.66
		var red := Color("#b23a30")
		poly(ci, taper(x, by, bw, tw, h, 0, 1), Color("#f4f0e8"))
		poly(ci, taper(x, by, bw, tw, h, 0.22, 0.38), red)
		poly(ci, taper(x, by, bw, tw, h, 0.6, 0.76), red)
		poly(ci, [Vector2(x, by), Vector2(x + bw, by), Vector2(x + tw, by - h), Vector2(x, by - h)], shade)
		var ty := by - h
		ci.draw_circle(Vector2(x, ty - s * 0.08), s * 0.2, Color(1, 0.886, 0.478, 0.35))
		rect(ci, x - tw * 1.3, ty - s * 0.02, tw * 2.6, s * 0.035, Color("#3d3633"))
		rect(ci, x - tw * 0.8, ty - s * 0.12, tw * 1.6, s * 0.1, Color("#ffe27a"))
		poly(ci, [Vector2(x - tw * 1.1, ty - s * 0.12), Vector2(x, ty - s * 0.24), Vector2(x + tw * 1.1, ty - s * 0.12)], red)
	else:
		var hw := s * 0.1
		var h := s * 0.4
		var d := s * 0.07
		poly(ci, [Vector2(x + hw, by), Vector2(x + hw + d, by - d * 0.6), Vector2(x + hw + d, by - h - d * 0.6), Vector2(x + hw, by - h)], Color("#7c231f"))
		rect(ci, x - hw, by - h, hw * 2, h, Color("#a8322b"))
		var trim := Color("#f4efe6")
		ci.draw_line(Vector2(x - hw + 0.5, by), Vector2(x - hw + 0.5, by - h), trim, 1.0, true)
		ci.draw_line(Vector2(x + hw - 0.5, by), Vector2(x + hw - 0.5, by - h), trim, 1.0, true)
		rect(ci, x - hw * 0.55, by - h * 0.9, hw * 1.1, h * 0.3, Color("#2d201c"))
		half_disc(ci, Vector2(x, by - h * 0.72), hw * 0.36, Color("#f1c34a"))
		poly(ci, [Vector2(x - hw - s * 0.02, by - h), Vector2(x + hw * 0.2, by - h - s * 0.3), Vector2(x + hw + d, by - h - d * 0.6), Vector2(x + hw + s * 0.02, by - h)], Color("#3d3633"))
		ci.draw_circle(Vector2(x + hw * 0.2, by - h - s * 0.31), s * 0.022, Color("#f1c34a"))


## Windmill sails around `c`, radius r, angle a.
static func sails(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var wood := Color("#5a4a3e")
	var cloth := Color(0.969, 0.945, 0.89, 0.95)
	var edge_col := Color(0.353, 0.29, 0.243, 0.6)
	for k in 4:
		var ang := a + k * PI / 2
		var u := Vector2(cos(ang), sin(ang))
		var n := Vector2(-u.y, u.x)
		ci.draw_line(c, c + u * r, wood, maxf(1, r * 0.07), true)
		var w := r * 0.26
		var pts := PackedVector2Array([c + u * r * 0.22, c + u * r, c + u * r + n * w, c + u * r * 0.22 + n * w])
		ci.draw_colored_polygon(pts, cloth)
		pts.append(pts[0])
		ci.draw_polyline(pts, edge_col, maxf(0.6, r * 0.03), true)
	ci.draw_circle(c, maxf(1.2, r * 0.08), Color("#3d3633"))


static func _quad(a: Vector2, c: Vector2, b: Vector2, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts


static func _clipped_polyline(ci: CanvasItem, line: PackedVector2Array, clip: PackedVector2Array, col: Color, w: float) -> void:
	for piece in Geometry2D.intersect_polyline_with_polygon(line, clip):
		if piece.size() >= 2:
			ci.draw_polyline(piece, col, w, true)


## Midpoint of screen edge i (E = 0, counter-clockwise), at radius = apothem.
static func edge_mid(i: int, s: float) -> Vector2:
	var a := -i * PI / 3
	return Vector2(cos(a), sin(a)) * s * 0.866


## Centre-lines of the tile's river/railroad: one curve through the centre for
## two edges, otherwise spokes from each edge to the centre.
static func feature_lines(tile: Tile, s: float) -> Array:
	var edges: Array[int] = []
	for i in 6:
		if tile.feat_at(i) != "":
			edges.append(i)
	var out: Array = []
	if edges.size() == 2:
		out.append(_quad(edge_mid(edges[0], s), Vector2.ZERO, edge_mid(edges[1], s), 14))
	else:
		for i in edges:
			out.append(_quad(edge_mid(i, s), edge_mid(i, s) * 0.5, Vector2.ZERO, 6))
	return out


static func _near_lines(p: Vector2, lines: Array, dist: float) -> bool:
	for line in lines:
		for k in line.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])) < dist:
				return true
	return false


static func _offset_line(line: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in line.size():
		var a: Vector2 = line[maxi(0, k - 1)]
		var b: Vector2 = line[mini(line.size() - 1, k + 1)]
		var d := (b - a).normalized()
		out.append(line[k] + Vector2(-d.y, d.x) * off)
	return out


static func draw_feature(ci: CanvasItem, tile: Tile, lines: Array, s: float) -> void:
	var f := tile.feature()
	if f == "" or lines.is_empty():
		return
	var edges := tile.feat.count(f)
	var hub := edges != 2  # an end or a junction meets in the middle
	if f == "river":
		var bank := Color("#3b6f8f")
		var water := Defs.top("river")
		var lake := edges == 1
		var lr := s * (0.3 if lake else 0.19)  # a lake is a wide pool in the middle
		for line in lines:
			ci.draw_polyline(line, bank, s * 0.25, true)
		if hub:
			ellipse(ci, Vector2.ZERO, lr, lr * (0.78 if lake else 1.0), bank)
		for line in lines:
			ci.draw_polyline(line, water, s * 0.18, true)
		if hub:
			var inner := lr - s * 0.035
			ellipse(ci, Vector2.ZERO, inner, inner * (0.78 if lake else 1.0), water)
		for line in lines:
			ci.draw_polyline(_offset_line(line, s * 0.035), Color(1, 1, 1, 0.35), 1.0, true)
		if lake:
			# ripples and reeds
			for k in 2:
				var y := -s * 0.06 + k * s * 0.1
				ci.draw_line(Vector2(-s * 0.1 + k * s * 0.05, y), Vector2(s * 0.04 + k * s * 0.05, y), Color(1, 1, 1, 0.45), 1.0, true)
			for k in 3:
				var x := lr * 0.75 - k * 2.2
				ci.draw_line(Vector2(x, lr * 0.55), Vector2(x - 0.8, lr * 0.55 - s * 0.09), Color("#4f7a3a"), 1.1, true)
	else:
		var ballast := Color("#b9a58a")
		for line in lines:
			ci.draw_polyline(line, ballast, s * 0.2, true)
		if hub:
			ci.draw_circle(Vector2.ZERO, s * 0.1, ballast)
		var sleeper := Color("#6b4f3a")
		for line in lines:
			var travelled := 0.0
			var next := 2.0
			for k in line.size() - 1:
				var a: Vector2 = line[k]
				var b: Vector2 = line[k + 1]
				var seg := a.distance_to(b)
				var d := (b - a) / maxf(seg, 0.001)
				var nrm := Vector2(-d.y, d.x)
				while next <= travelled + seg:
					var p := a + d * (next - travelled)
					ci.draw_line(p - nrm * s * 0.1, p + nrm * s * 0.1, sleeper, 1.6, true)
					next += 4.2
				travelled += seg
		var steel := Color("#4a4a52")
		for line in lines:
			ci.draw_polyline(_offset_line(line, s * 0.055), steel, 1.1, true)
			ci.draw_polyline(_offset_line(line, -s * 0.055), steel, 1.1, true)



## A small station building where a railroad ends (drawn with the deco so it depth-sorts).
static func station(ci: CanvasItem, x: float, y: float, s: float) -> void:
	var w := s * 0.34
	var h := s * 0.17
	var dx := s * 0.1
	var dy := -s * 0.07
	var L := x - w / 2
	var R := x + w / 2
	var B := y + s * 0.08
	var T := B - h
	ellipse(ci, Vector2(x + dx * 0.5, B + 1), w * 0.7, s * 0.1, Color(0, 0, 0, 0.22))
	# platform
	poly(ci, [Vector2(L - s * 0.05, B), Vector2(R + s * 0.05, B), Vector2(R + s * 0.05 + dx, B + dy), Vector2(L - s * 0.05 + dx, B + dy)], Color("#cfc3ae"))
	# side wall, front wall
	poly(ci, [Vector2(R, B), Vector2(R + dx, B + dy), Vector2(R + dx, T + dy), Vector2(R, T)], Color("#a8822f"))
	rect(ci, L, T, w, h, Color("#e2b649"))
	# roof
	var roof := Color("#5a4a3e")
	poly(ci, [Vector2(L - s * 0.04, T), Vector2(R + s * 0.04, T), Vector2(R + s * 0.04 + dx, T + dy), Vector2(L - s * 0.04 + dx, T + dy)], roof)
	poly(ci, [Vector2(L - s * 0.04, T), Vector2(R + s * 0.04, T), Vector2(R + s * 0.04, T + s * 0.035), Vector2(L - s * 0.04, T + s * 0.035)], roof.darkened(0.2))
	# windows, door, clock
	var win := Color("#f6d77a")
	rect(ci, L + w * 0.1, T + h * 0.35, w * 0.16, h * 0.3, win)
	rect(ci, R - w * 0.26, T + h * 0.35, w * 0.16, h * 0.3, win)
	rect(ci, x - w * 0.09, T + h * 0.3, w * 0.18, h * 0.7, Color("#3a2420"))
	ci.draw_circle(Vector2(x, T - s * 0.05), s * 0.035, Color("#f4efe6"))
	ci.draw_arc(Vector2(x, T - s * 0.05), s * 0.035, 0, TAU, 12, roof, 0.8, true)


## Draws a whole tile centred on (0, 0).
static func draw_tile(ci: CanvasItem, tile: Tile) -> void:
	var s := S0
	var d := DEPTH * s
	var C := Vector2.ZERO
	var wc := func(i: int) -> Array:
		var a := -i * PI / 3
		return [Vector2(cos(a - PI / 6), sin(a - PI / 6)) * s, Vector2(cos(a + PI / 6), sin(a + PI / 6)) * s]

	# side faces (the two visible lower walls)
	for i in [4, 5]:
		var t := tile.edge(i)
		var pp: Array = wc.call(i)
		var p1: Vector2 = pp[0]
		var p2: Vector2 = pp[1]
		var face := [p1, p2, p2 + Vector2(0, d), p1 + Vector2(0, d)]
		var face_col := Color("#8a6a1c") if tile.gold else (Color("#3a6584") if t == "water" else Color("#6e5841"))
		poly(ci, face, face_col)
		poly(ci, [p1, p2, p2 + Vector2(0, d * 0.32), p1 + Vector2(0, d * 0.32)], Color("#d9a926") if tile.gold else Defs.dark(t))
		poly(ci, face, Color(0, 0, 0, 0.2) if i == 5 else Color(0, 0, 0, 0.05))
		if tile.feat_at(i) == "river":
			# the river spills over the side of the tile
			var m := (p1 + p2) / 2
			var u := (p2 - p1).normalized() * s * 0.09
			poly(ci, [m - u, m + u, m + u + Vector2(0, d), m - u + Vector2(0, d)], Defs.top("river").darkened(0.12))
			ci.draw_line(m + Vector2(0, d * 0.3), m + Vector2(0, d * 0.9), Color(1, 1, 1, 0.4), 1.0, true)

	# top wedges
	for i in 6:
		var t := tile.edge(i)
		var pp: Array = wc.call(i)
		var tri := PackedVector2Array([C, pp[0], pp[1]])
		ci.draw_colored_polygon(tri, Defs.top(t))
		tri.append(C)
		ci.draw_polyline(tri, Defs.top(t), 0.8, true)

	# per-wedge detail, collecting depth-sorted decorations
	var deco: Array = []
	var flines := feature_lines(tile, s)
	var fclear := s * (0.2 if tile.feature() == "river" else 0.17)
	var R := RandomNumberGenerator.new()
	for i in 6:
		var t := tile.edge(i)
		var bi := (i + tile.rot) % 6
		R.seed = tile.art_seed + bi * 7919
		var pp: Array = wc.call(i)
		var p1: Vector2 = pp[0]
		var p2: Vector2 = pp[1]
		var tri := PackedVector2Array([C, p1, p2])
		var lo0 := 0.42 if tile.special != "" or tile.is_station() else 0.2
		var pt := func(lo: float, hi: float) -> Vector2:
			lo = maxf(lo, lo0)
			for k in 24:
				var u := R.randf()
				var v := R.randf()
				if u + v > hi or u + v < lo:
					continue
				var cand := p1 * u + p2 * v
				if not flines.is_empty() and _near_lines(cand, flines, fclear):
					continue  # keep trees and houses off the river / track
				return cand
			return (p1 + p2) / 3.0
		if t == "field":
			var ux := (p2 - p1).normalized()
			var nx := Vector2(-ux.y, ux.x)
			var col := Defs.dark("field")
			col.a = 0.5
			var sp := 3.6
			var o := -s + R.randf() * sp
			while o < s:
				var m := nx * o
				_clipped_polyline(ci, PackedVector2Array([m - ux * s, m + ux * s]), tri, col, 1.3)
				o += sp
			if R.randf() < 0.35:
				var p: Vector2 = pt.call(0.45, 0.9)
				deco.append({"y": p.y, "k": "hay", "p": p})
		elif t == "water":
			var n := 2 + int(R.randf() * 2)
			for k in n:
				var p: Vector2 = pt.call(0.15, 0.95)
				var w := s * 0.09
				var line := _quad(p - Vector2(w, 0), p + Vector2(-w / 2, -w * 0.6), p, 6)
				line.append_array(_quad(p, p + Vector2(w / 2, w * 0.6), p + Vector2(w, 0), 6))
				_clipped_polyline(ci, line, tri, Color(1, 1, 1, 0.7), 1.3)
		elif t == "meadow":
			var n := 5 + int(R.randf() * 4)
			var flowers := [Color("#ffffff"), Color("#f3d55b"), Color("#e993b5"), Color("#c8a7ec")]
			for k in n:
				var p: Vector2 = pt.call(0.15, 0.95)
				if R.randf() < 0.55:
					ci.draw_polyline(PackedVector2Array([p + Vector2(-1.6, -2.2), p, p + Vector2(1.6, -2.2)]), Defs.dark("meadow"), 1.0, true)
				else:
					ci.draw_circle(p, 1.3, flowers[int(R.randf() * 4)])
			if R.randf() < 0.3:
				var p: Vector2 = pt.call(0.45, 0.9)
				deco.append({"y": p.y, "k": "bush", "p": p})
		elif t == "forest":
			var n := 3 + int(R.randf() * 3) - (1 if tile.special != "" else 0)
			for k in n:
				var p: Vector2 = pt.call(0.15, 0.9)
				var h := s * (0.22 + R.randf() * 0.12)
				var kind := 0 if R.randf() < 0.72 else 1
				var shade := R.randf()
				deco.append({"y": p.y, "k": "tree", "p": p, "h": h, "kind": kind, "shade": shade})
		elif t == "village":
			var col := Defs.dark("village")
			col.a = 0.5
			for k in 5:
				var p: Vector2 = pt.call(0.1, 0.95)
				rect(ci, p.x - 1, p.y - 0.7, 2, 1.4, col)
			var n := 1 if tile.special != "" else (1 if R.randf() < 0.5 else 2)
			for k in n:
				var p: Vector2 = pt.call(0.3, 0.8)
				var sz := s * (0.13 + R.randf() * 0.04)
				var flip := R.randf() < 0.5
				deco.append({"y": p.y, "k": "house", "p": p, "sz": sz, "flip": flip})

	draw_feature(ci, tile, flines, s)
	stroke_hex(ci, C, s, Color(0, 0, 0, 0.38), 1.4)
	for i in [1, 2, 3]:
		var pp: Array = wc.call(i)
		ci.draw_line(pp[0], pp[1], Color(1, 1, 1, 0.4), 1.6, true)
	if tile.gold:
		stroke_hex(ci, C, s - 1.4, Color("#f5c542"), 2.8)
		stroke_hex(ci, C, s - 3.8, Color(1, 0.94, 0.706, 0.6), 1.0)
	if tile.special != "" and tile.special != "belltower":
		for dd in tile.special_dirs():
			var a := -dd * PI / 3
			var u := Vector2(cos(a), sin(a))
			var n := Vector2(-u.y, u.x)
			var m := s * 0.72
			var w := s * 0.1
			var arrow := PackedVector2Array([u * (m - w) + n * w, u * m, u * (m - w) - n * w])
			var shadow_arrow := PackedVector2Array()
			for p in arrow:
				shadow_arrow.append(p + Vector2(0, 0.8))
			ci.draw_polyline(shadow_arrow, Color(0, 0, 0, 0.3), 2.6, true)
			ci.draw_polyline(arrow, Color(1, 0.973, 0.839, 0.95), 2.0, true)
	if tile.special != "":
		deco.append({"y": s * 0.12, "k": "structure"})
	if tile.is_station():
		deco.append({"y": s * 0.08, "k": "station"})
	deco.sort_custom(func(a, b): return a.y < b.y)
	for o in deco:
		match o.k:
			"hay":
				hay(ci, o.p.x, o.p.y, s)
			"bush":
				bush(ci, o.p.x, o.p.y, s)
			"tree":
				tree(ci, o.p.x, o.p.y, o.h, o.kind, o.shade)
			"house":
				house(ci, o.p.x, o.p.y, o.sz, o.flip)
			"structure":
				structure(ci, tile.special, 0, 0, s)
			"station":
				station(ci, 0, 0, s)
	if tile.gold:
		star(ci, Vector2(s * 0.46, -s * 0.52), s * 0.15, Color("#fff3b0"))
		star(ci, Vector2(-s * 0.5, s * 0.18), s * 0.09, Color("#fff3b0"))


## Quest pennant. `size` is the on-screen tile radius; drawn around `pos`.
static func pennant(ci: CanvasItem, font: Font, pos: Vector2, size: float, quest: Dictionary, prog: int, alpha := 1.0, scale := 1.0) -> void:
	var c := Defs.top(quest.t)
	c.a = alpha
	var white := Color(1, 1, 1, alpha)
	ci.draw_set_transform(pos, 0, Vector2(scale, scale))
	if size < 18:
		ci.draw_circle(Vector2(size * 0.3, -size * 0.95), 4, c)
		ci.draw_arc(Vector2(size * 0.3, -size * 0.95), 4, 0, TAU, 16, white, 1.5, true)
		ci.draw_set_transform(Vector2.ZERO)
		return
	var px := size * 0.28
	var top := -size * 1.15
	var base := -size * 0.15
	var fw := size * 0.8
	var fh := size * 0.36
	ci.draw_line(Vector2(px, base), Vector2(px, top), Color(0.29, 0.227, 0.173, alpha), maxf(1.2, size * 0.04), true)
	ci.draw_rect(Rect2(px + 2, top + 2, fw * 0.9, fh), Color(0, 0, 0, 0.18 * alpha))
	var flag := PackedVector2Array([Vector2(px, top), Vector2(px + fw, top), Vector2(px + fw - fh * 0.3, top + fh / 2), Vector2(px + fw, top + fh), Vector2(px, top + fh)])
	ci.draw_colored_polygon(flag, c)
	flag.append(flag[0])
	ci.draw_polyline(flag, Color(1, 1, 1, 0.85 * alpha), 1.0, true)
	var fs := maxi(6, int(round(fh * 0.62)))
	var txt := "%d/%d" % [mini(prog, quest.need), quest.need]
	var mid := top + fh / 2 + 0.5
	var baseline := mid + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0
	var tp := Vector2(px + fh * 0.3, baseline)
	ci.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.4 * alpha))
	ci.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
	ci.draw_set_transform(Vector2.ZERO)


## Draws a tile fitted into `rect` (tray previews, relic cards).
static func draw_fitted(ci: CanvasItem, font: Font, area: Rect2, tile: Tile, with_pennant := true) -> void:
	var sc := minf(area.size.x / BOX_W, area.size.y / BOX_H) * 0.96
	var dw := BOX_W * sc
	var dh := BOX_H * sc
	var ox := area.position.x + (area.size.x - dw) / 2
	var oy := area.position.y + (area.size.y - dh) / 2 + 2
	var centre := Vector2(ox + dw / 2, oy - BOX_TOP * sc)
	ci.draw_set_transform(centre, 0, Vector2(sc, sc))
	draw_tile(ci, tile)
	if tile.special == "windmill":
		sails(ci, Vector2(0, -HUB * S0), 0.4 * S0, 0.5)
	ci.draw_set_transform(Vector2.ZERO)
	if with_pennant and tile.has_quest():
		pennant(ci, font, centre, S0 * sc, tile.quest, 1)
