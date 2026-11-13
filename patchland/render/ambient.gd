class_name Ambient
extends RefCounted
## Small signs of life on the board: trains on closed railroads, boats on closed
## rivers and lakes, people in villages, deer in forests. Purely decorative:
## built from the board when it changes (rebuild), moved every frame (update),
## drawn in screen space by the Board's fx layer (draw). Caps keep it uncluttered.

const MAX_TRAINS := 3
const MAX_BOATS := 3
const MAX_PEOPLE := 8
const MAX_DEER := 3

var agents: Array = []
var smoke: Array = []  # [{pos, t, life}]
var _rng := RandomNumberGenerator.new()


func clear() -> void:
	agents.clear()
	smoke.clear()


static func _wedge_point(e: Dictionary, i: int, rng: RandomNumberGenerator, lo := 0.25, hi := 0.85) -> Vector2:
	var c := Hex.wpos(e.q, e.r)
	var a := -i * PI / 3
	var p1 := Vector2(cos(a - PI / 6), sin(a - PI / 6))
	var p2 := Vector2(cos(a + PI / 6), sin(a + PI / 6))
	for k in 12:
		var u := rng.randf()
		var v := rng.randf()
		if u + v >= lo and u + v <= hi:
			return c + p1 * u + p2 * v
	return c + (p1 + p2) / 3.0


## Points on the land of `t` across a region's tiles (for walkers and lake boats).
static func _land_points(tiles: Array, t: String, rng: RandomNumberGenerator, per_tile := 2) -> Array:
	var pts: Array = []
	for e in tiles:
		for i in 6:
			if e.tile.edge(i) == t:
				for k in per_tile:
					pts.append(_wedge_point(e, i, rng))
	return pts


## World-space path along a line network between two of its ends (stations, or
## the water a river runs into). Returns [] if there's no such pair.
static func _line_path(s: RunState, net: Dictionary) -> PackedVector2Array:
	var f: String = net.f
	var ends: Array = []  # [entry, end point]
	for e in net.tiles:
		if f == "rail" and e.tile.is_station():
			ends.append([e, Hex.wpos(e.q, e.r)])
		elif f == "river":
			for i in 6:
				var n = s.board.get(e.k + Hex.DIRS[i])
				if n != null and Rules.is_mouth(e.tile, i, n.tile) and e.tile.feat_at(i) == "river":
					var mid := (Hex.wpos(e.q, e.r) + Hex.wpos(n.q, n.r)) / 2.0
					ends.append([e, mid])
	if ends.size() < 2:
		return PackedVector2Array()
	var start: Dictionary = ends[0][0]
	var goal_e: Dictionary = ends[ends.size() - 1][0]
	# BFS through linked feature edges
	var prev := {start.k: null}
	var queue: Array = [start]
	while not queue.is_empty():
		var e: Dictionary = queue.pop_front()
		if e.k == goal_e.k:
			break
		for i in 6:
			if e.tile.feat_at(i) != f:
				continue
			var n = s.board.get(e.k + Hex.DIRS[i])
			if n == null or prev.has(n.k) or n.tile.feat_at((i + 3) % 6) != f:
				continue
			prev[n.k] = e
			queue.append(n)
	if not prev.has(goal_e.k):
		return PackedVector2Array()
	var chain: Array = []
	var cur = goal_e
	while cur != null:
		chain.push_front(cur)
		cur = prev[cur.k]
	var path := PackedVector2Array()
	path.append(ends[0][1])
	for e in chain:
		path.append(Hex.wpos(e.q, e.r))
	path.append(ends[ends.size() - 1][1])
	return path


func rebuild(s: RunState) -> void:
	clear()
	_rng.seed = s.board.size() * 7919 + 13
	var h := Rules.harvest_calc(s)
	var trains := 0
	var boats := 0
	var people := 0
	var deer := 0
	for r in h.regions:
		if r.t == "rail" or r.t == "river":
			var net := Rules.line_network(s, r.tiles[0], r.t)
			if net.open != 0:
				continue  # only closed lines get traffic
			if r.t == "rail" and trains >= MAX_TRAINS or r.t == "river" and boats >= MAX_BOATS:
				continue
			var path := _line_path(s, net)
			if path.size() < 2:
				continue
			agents.append({"kind": "train" if r.t == "rail" else "boat", "path": path, "d": _rng.randf() * 0.5, "dir": 1,
				"speed": 0.55 if r.t == "rail" else 0.3, "wait": _rng.randf() * 2.0, "pos": path[0], "head": Vector2.RIGHT})
			if r.t == "rail":
				trains += 1
			else:
				boats += 1
		elif r.t == "water" and r.n >= 3 and boats < MAX_BOATS:
			var pts := _land_points(r.tiles, "water", _rng, 1)
			if pts.size() >= 4:
				agents.append(_walker("sail", pts, 0.18))
				boats += 1
		elif r.t == "village" and people < MAX_PEOPLE:
			var pts := _land_points(r.tiles, "village", _rng, 2)
			var n := mini(3, maxi(1, (r.n + 1) / 2))
			for k in n:
				if people >= MAX_PEOPLE or pts.size() < 2:
					break
				agents.append(_walker("person", pts, 0.16))
				people += 1
		elif r.t == "forest" and r.n >= 4 and deer < MAX_DEER:
			var pts := _land_points(r.tiles, "forest", _rng, 2)
			if pts.size() >= 4:
				agents.append(_walker("deer", pts, 0.12))
				deer += 1


func _walker(kind: String, pts: Array, speed: float) -> Dictionary:
	var p: Vector2 = pts[_rng.randi_range(0, pts.size() - 1)]
	var colors := [Color("#c0392b"), Color("#2d6c9a"), Color("#e2bb57"), Color("#7cb342"), Color("#8e44ad"), Color("#ecf0f1")]
	return {"kind": kind, "pts": pts, "pos": p, "target": p, "speed": speed * (0.8 + _rng.randf() * 0.4),
		"wait": _rng.randf() * 2.0, "head": Vector2.RIGHT, "col": colors[_rng.randi_range(0, colors.size() - 1)], "phase": _rng.randf() * TAU}


func _pick_target(a: Dictionary) -> void:
	# the next stop: a nearby point, so walkers don't cut across other land
	var best: Vector2 = a.pos
	for k in 6:
		var p: Vector2 = a.pts[_rng.randi_range(0, a.pts.size() - 1)]
		var d: float = p.distance_to(a.pos)
		if d > 0.05 and d < 0.9:
			best = p
			break
	a.target = best


func update(dt: float) -> void:
	for a in agents:
		if a.wait > 0:
			a.wait -= dt
			continue
		if a.has("path"):
			_move_on_path(a, dt)
		else:
			var to: Vector2 = a.target - a.pos
			var step: float = a.speed * dt
			if to.length() <= step:
				a.pos = a.target
				a.wait = (0.6 + _rng.randf() * 2.5) * (2.0 if a.kind == "deer" else 1.0)
				_pick_target(a)
			else:
				a.head = to.normalized()
				a.pos += a.head * step
	for i in range(smoke.size() - 1, -1, -1):
		smoke[i].t += dt
		if smoke[i].t >= smoke[i].life:
			smoke.remove_at(i)


func _move_on_path(a: Dictionary, dt: float) -> void:
	var path: PackedVector2Array = a.path
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	a.d += a.speed * dt * a.dir
	if a.d >= total or a.d <= 0:
		a.d = clampf(a.d, 0, total)
		a.dir = -a.dir
		a.wait = 1.5 + _rng.randf()  # pause at the station / river mouth
	var left: float = a.d
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if left <= seg or i == path.size() - 2:
			var t := clampf(left / maxf(seg, 0.001), 0, 1)
			a.pos = path[i].lerp(path[i + 1], t)
			var h: Vector2 = (path[i + 1] - path[i]).normalized() * a.dir
			if h != Vector2.ZERO:
				a.head = h
			break
		left -= seg
	if a.kind == "train" and _rng.randf() < dt * 3.0 and smoke.size() < 24:
		smoke.append({"pos": a.pos + a.head * 0.12 + Vector2(0, -0.2), "t": 0.0, "life": 1.2})


## Draws everything in screen space. ws: world -> screen; size: px per world unit.
func draw(ci: CanvasItem, ws: Callable, size: float) -> void:
	var u := size / 48.0  # 1.0 at the default zoom
	for sm in smoke:
		var k: float = sm.t / sm.life
		var p: Vector2 = ws.call(sm.pos + Vector2(0.05 * k, -0.35 * k))
		ci.draw_circle(p, (2.0 + 4.0 * k) * u, Color(0.92, 0.92, 0.92, 0.55 * (1.0 - k)))
	var now := Time.get_ticks_msec() / 1000.0
	for a in agents:
		var p: Vector2 = ws.call(a.pos)
		match a.kind:
			"train":
				_draw_train(ci, p, a.head, u)
			"boat":
				_draw_boat(ci, p, a.head, u, now)
			"sail":
				_draw_boat(ci, p, a.head, u, now, true)
			"person":
				_draw_person(ci, p, a, u, now)
			"deer":
				_draw_deer(ci, p, a, u)


func _draw_train(ci: CanvasItem, p: Vector2, head: Vector2, u: float) -> void:
	var dir := head if head != Vector2.ZERO else Vector2.RIGHT
	var n := Vector2(-dir.y, dir.x)
	var cars := [[0.0, Color("#b03a2e"), true], [-1.0, Color("#2e6f9e"), false], [-2.0, Color("#2e6f9e"), false]]
	for c in cars:
		var cp: Vector2 = p + dir * (c[0] * 9.0 * u) - Vector2(0, 3.0 * u)
		var hl := dir * 4.2 * u
		var hw := n * 2.6 * u
		var body := PackedVector2Array([cp - hl - hw, cp + hl - hw, cp + hl + hw, cp - hl + hw])
		ci.draw_colored_polygon(body, Color(0, 0, 0, 0.35) if false else c[1])
		var ol := body.duplicate()
		ol.append(body[0])
		ci.draw_polyline(ol, Color("#1d1d1d"), 1.0 * u, true)
		if c[2]:
			ci.draw_rect(Rect2(cp + dir * 1.5 * u - Vector2(1.2, 4.5) * u, Vector2(2.4, 2.4) * u), Color("#1d1d1d"))
		else:
			ci.draw_line(cp - hw * 0.4, cp + hw * 0.4, Color(1, 0.95, 0.7, 0.9), 1.4 * u, true)


func _draw_boat(ci: CanvasItem, p: Vector2, head: Vector2, u: float, now: float, sail := false) -> void:
	var bob := sin(now * 2.2 + p.x * 0.05) * 0.8 * u
	var c := p + Vector2(0, bob - 1.5 * u)
	var s := 1.0 if head.x >= 0 else -1.0
	var hull := PackedVector2Array([c + Vector2(-6 * s, 0) * u, c + Vector2(6 * s, 0) * u, c + Vector2(4 * s, 3) * u, c + Vector2(-4.5 * s, 3) * u])
	ci.draw_colored_polygon(hull, Color("#7a4b2a"))
	ci.draw_line(c + Vector2(-6 * s, 0) * u, c + Vector2(6 * s, 0) * u, Color("#f4efe6"), 1.0 * u, true)
	if sail:
		ci.draw_line(c, c + Vector2(0, -10) * u, Color("#4a3a2c"), 1.0 * u, true)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.6 * s, -9.5) * u, c + Vector2(6 * s, -1.5) * u, c + Vector2(0.6 * s, -1.5) * u]), Color("#fbf6ea"))
	else:
		ci.draw_circle(c + Vector2(-1 * s, -2.2) * u, 1.6 * u, Color("#e8c08a"))
	# wake
	ci.draw_line(c + Vector2(-7 * s, 3.2) * u, c + Vector2(-11 * s, 3.6) * u, Color(1, 1, 1, 0.45), 1.0 * u, true)


func _draw_person(ci: CanvasItem, p: Vector2, a: Dictionary, u: float, now: float) -> void:
	var walking: bool = a.wait <= 0
	var step := sin(now * 9.0 + a.phase) * 1.2 * u if walking else 0.0
	ci.draw_line(p + Vector2(-0.8 * u + step * 0.5, 0), p + Vector2(0, -3.0 * u), Color("#3a2a20"), 1.0 * u, true)
	ci.draw_line(p + Vector2(0.8 * u - step * 0.5, 0), p + Vector2(0, -3.0 * u), Color("#3a2a20"), 1.0 * u, true)
	ci.draw_line(p + Vector2(0, -3.0 * u), p + Vector2(0, -6.2 * u), a.col, 2.2 * u, true)
	ci.draw_circle(p + Vector2(0, -7.6 * u), 1.4 * u, Color("#f0c9a0"))


func _draw_deer(ci: CanvasItem, p: Vector2, a: Dictionary, u: float) -> void:
	var s := 1.0 if a.head.x >= 0 else -1.0
	var body := Color("#9c6b3f")
	ci.draw_line(p + Vector2(-2.5 * s, 0) * u, p + Vector2(-2.5 * s, -3.5) * u, body.darkened(0.3), 1.0 * u, true)
	ci.draw_line(p + Vector2(2.5 * s, 0) * u, p + Vector2(2.5 * s, -3.5) * u, body.darkened(0.3), 1.0 * u, true)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-3.6 * s, -3.2) * u, p + Vector2(3.6 * s, -3.2) * u, p + Vector2(3.2 * s, -6.0) * u, p + Vector2(-3.4 * s, -5.8) * u]), body)
	var grazing: bool = a.wait > 0
	var neck := Vector2(3.4 * s, -5.6) * u
	var headp := p + (Vector2(5.4 * s, -2.6) * u if grazing else Vector2(5.0 * s, -8.8) * u)
	ci.draw_line(p + neck, headp, body, 1.6 * u, true)
	ci.draw_circle(headp, 1.4 * u, body)
	if not grazing:
		ci.draw_line(headp, headp + Vector2(-0.6 * s, -2.8) * u, Color("#e8dcc4"), 0.8 * u, true)
		ci.draw_line(headp, headp + Vector2(1.0 * s, -2.6) * u, Color("#e8dcc4"), 0.8 * u, true)
	ci.draw_circle(p + Vector2(-3.8 * s, -5.6) * u, 0.9 * u, Color("#f4efe6"))
