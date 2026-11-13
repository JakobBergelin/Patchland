class_name Board
extends Control
## The play area: camera, tiles (y-sorted), slots, ghost preview, indicators,
## ray previews, region highlight, pennants and fx. Emits input as signals.
##
## Mouse: hover previews, left click places, RIGHT CLICK ROTATES the tile
## (shift + right click rotates the other way), scroll wheel rotates too.

signal hovered(cell)  # cand Dictionary or null
signal clicked(cell)  # cand Dictionary or null
signal rotate_requested(dir: int)
signal speed_up_requested

var game  # Game (reads S, sel, cur_eval, harvesting, hl_region)
var fx := Fx.new()
var cam := {"x": 0.0, "y": 0.0, "size": 40.0}
var snap_cam := true
var shake_amp := 0.0
var punch := 0.0
var mill_angle := 0.0
var mill_fast_until := 0.0
var reduced := false

var nodes := {}  # Vector2i -> TileNode
var ghost: TileNode
var shaker: Node2D
var slot_layer: Node2D
var world: Node2D
var tile_layer: Node2D
var fx_layer: Node2D
var _down = null  # Vector2 of left-press position
var _dragging := false  # left or middle drag is panning the view
var _middle := false

const ZOOM_MIN := 0.45
const ZOOM_MAX := 4.0
const KEY_PAN_SPEED := 700.0  # screen px per second for WASD
## Player camera on top of the auto-fit: zoom factor and pan offset in world units.
var user_zoom := 1.0
var user_pan := Vector2.ZERO
var _auto := {}  # sticky automatic view, see _fit()
var _flashes: Array = []  # [{t, keys, t0, dur}] closed-area outlines


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	shaker = Node2D.new()
	add_child(shaker)
	slot_layer = Node2D.new()
	shaker.add_child(slot_layer)
	slot_layer.draw.connect(_draw_slots)
	world = Node2D.new()
	shaker.add_child(world)
	tile_layer = Node2D.new()
	tile_layer.y_sort_enabled = true
	world.add_child(tile_layer)
	ghost = TileNode.new()
	ghost.visible = false
	ghost.modulate.a = 0.92
	tile_layer.add_child(ghost)
	fx_layer = Node2D.new()
	shaker.add_child(fx_layer)
	fx_layer.draw.connect(_draw_fx)
	mouse_exited.connect(func(): hovered.emit(null))


func _draw() -> void:
	# soft radial-ish backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Pal.bg)
	var c := size / 2
	var r := maxf(size.x, size.y) * 0.62
	for k in range(8, 0, -1):
		var f := k / 8.0
		var col := Pal.bg2.lerp(Pal.bg, f)
		draw_set_transform(c, 0, Vector2(1.0, 0.75))
		draw_circle(Vector2.ZERO, r * f, col)
	draw_set_transform(Vector2.ZERO)


# ---------- tiles ----------

func clear_tiles() -> void:
	for n in nodes.values():
		n.queue_free()
	nodes.clear()
	fx.clear()
	_flashes.clear()
	shake_amp = 0
	punch = 0
	snap_cam = true
	reset_view()


func add_tile(entry: Dictionary, born: float) -> void:
	var n := TileNode.new(entry.tile)
	n.born = born
	n.position = Hex.wpos(entry.q, entry.r) * TileArt.S0
	tile_layer.add_child(n)
	n.refresh()
	nodes[entry.k] = n


func sync_tiles(board: Dictionary) -> void:
	for k in board:
		if not nodes.has(k):
			add_tile(board[k], 0)


func bump(k: Vector2i) -> void:
	if nodes.has(k):
		nodes[k].bump = Fx.now()


func shake(px: float) -> void:
	if not reduced:
		shake_amp = minf(8, maxf(shake_amp, px))


func punch_it(v: float) -> void:
	if not reduced:
		punch = maxf(punch, v)


func mill_fast() -> void:
	mill_fast_until = Fx.now() + 1500


# ---------- camera ----------

func fit_view(points: Array, w: float, h: float, pad: float, max_s: float) -> Dictionary:
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	for p in points:
		var wp := Hex.wpos(p.q, p.r)
		x0 = minf(x0, wp.x - Hex.SQ3 / 2 - 0.1)
		x1 = maxf(x1, wp.x + Hex.SQ3 / 2 + 0.1)
		y0 = minf(y0, wp.y - 1 - TileArt.PADT)
		y1 = maxf(y1, wp.y + 1 + TileArt.DEPTH + 0.1)
	var s := maxf(8, minf(minf((w - 2 * pad) / (x1 - x0), (h - 2 * pad) / (y1 - y0)), max_s))
	return {"size": s, "x": (x0 + x1) / 2, "y": (y0 + y1) / 2, "x0": x0, "x1": x1, "y0": y0, "y1": y1}


## The automatic view (whole board plus slots) before the player's zoom/pan.
## It is sticky so the camera stays calm while you play: it only zooms out when
## the board would no longer fit (or back in when there's far more room, e.g. the
## window grew), and it only moves as far as needed to keep everything on screen.
func _fit() -> Dictionary:
	var pts: Array = game.S.board.values() + game.S.cands.values()
	var f := fit_view(pts, size.x, size.y, 14, 58)
	if _auto.is_empty() or snap_cam:
		_auto = {"size": f.size, "x": f.x, "y": f.y}
		return _auto
	if f.size < _auto.size - 0.01 or f.size > _auto.size * 1.35:
		_auto.size = f.size
	var pad: float = 14.0 / _auto.size
	var half: Vector2 = size / _auto.size / 2.0 - Vector2(pad, pad)
	var lo := Vector2(f.x1, f.y1) - half  # centre at least here, so the right/bottom edge shows
	var hi := Vector2(f.x0, f.y0) + half  # and at most here, so the left/top edge shows
	_auto.x = f.x if lo.x > hi.x else clampf(_auto.x, lo.x, hi.x)
	_auto.y = f.y if lo.y > hi.y else clampf(_auto.y, lo.y, hi.y)
	return _auto


## Where the camera is heading: the auto-fit view, scaled by the player's zoom and
## shifted by their pan (so the view keeps following the board as it grows).
func _cam_target() -> Dictionary:
	var t := _fit()
	_clamp_pan(t)
	return {"size": t.size * user_zoom, "x": t.x + user_pan.x, "y": t.y + user_pan.y}


## Keeps the board within reach: the view centre stays inside the fitted area.
func _clamp_pan(fit: Dictionary) -> void:
	var half: Vector2 = size / fit.size / 2.0
	user_pan = user_pan.clamp(-half, half)


func _update_cam(dt: float) -> void:
	if size.x < 2 or size.y < 2 or game == null or game.S == null:
		return
	var t := _cam_target()
	if snap_cam or reduced:
		cam = t
		snap_cam = false
		return
	var k := minf(1, dt * 7)
	cam.x += (t.x - cam.x) * k
	cam.y += (t.y - cam.y) * k
	cam.size += (t.size - cam.size) * k


## Zooms by `factor`, keeping the world point under `screen_pos` fixed.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	if game == null or game.S == null:
		return
	var fit := _fit()
	var under: Vector2 = (screen_pos - size / 2) / cam.size + Vector2(cam.x, cam.y)
	user_zoom = clampf(user_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var new_size: float = fit.size * user_zoom
	var centre: Vector2 = under - (screen_pos - size / 2) / new_size
	user_pan = centre - Vector2(fit.x, fit.y)
	_clamp_pan(fit)
	cam = {"size": new_size, "x": fit.x + user_pan.x, "y": fit.y + user_pan.y}


## Moves the view by a screen-space delta (dragging the board along with the mouse).
func pan_by(screen_delta: Vector2) -> void:
	if game == null or game.S == null:
		return
	var d: Vector2 = screen_delta / cam.size
	user_pan -= d
	var fit := _fit()
	_clamp_pan(fit)
	cam.x = fit.x + user_pan.x
	cam.y = fit.y + user_pan.y


## Back to the automatic whole-board view.
func reset_view() -> void:
	user_zoom = 1.0
	user_pan = Vector2.ZERO


func is_view_default() -> bool:
	return is_equal_approx(user_zoom, 1.0) and user_pan.length() < 0.01


func ws(p: Vector2) -> Vector2:
	return size / 2 + cam.size * (p - Vector2(cam.x, cam.y))


func to_s(q: int, r: int) -> Vector2:
	return ws(Hex.wpos(q, r))


func view_rect() -> Rect2:
	var w: Vector2 = size / cam.size
	return Rect2(Vector2(cam.x, cam.y) - w / 2, w)


func hit_test(local: Vector2):
	if game == null or game.S == null:
		return null
	var w: Vector2 = (local - size / 2) / cam.size + Vector2(cam.x, cam.y)
	return game.S.cands.get(Hex.from_world(w))


# ---------- per frame ----------

func _tile_anim(n: TileNode, now: float) -> Vector3:
	var yo := 0.0
	var sx := 1.0
	var sy := 1.0
	if reduced:
		return Vector3(yo, sx, sy)
	if n.born > 0:
		var d := now - n.born
		if d < 170:
			var k := d / 170
			yo = -(1 - k) * (1 - k) * 0.9
		elif d < 420:
			var k := (d - 170) / 250
			var s := sin(k * PI) * (1 - k)
			sy = 1 - 0.14 * s
			sx = 1 + 0.09 * s
	if n.bump > 0:
		var k := (now - n.bump) / 280
		if k >= 0 and k < 1:
			yo -= 0.2 * sin(k * PI)
	return Vector3(yo, sx, sy)  # yo in tile radii


func _process(dt: float) -> void:
	if game == null or game.S == null:
		return
	var now := Fx.now()
	fx.reduced = reduced
	fx.update(dt)
	if shake_amp > 0:
		shake_amp = maxf(0, shake_amp - dt * (shake_amp * 9 + 3))
	if punch > 0:
		punch = maxf(0, punch - dt * (punch * 10 + 0.02))
	if not reduced:
		mill_angle += dt * (9.0 if now < mill_fast_until else 1.1)
	_key_pan(dt)
	_update_cam(dt)

	var off := Vector2.ZERO
	if shake_amp > 0:
		# smooth wobble (a few Hz) rather than a new random jump every frame
		off = Vector2(sin(now / 17.0) + 0.5 * sin(now / 7.3), cos(now / 13.0) + 0.5 * cos(now / 5.9)) / 1.5 * shake_amp
	var c := size / 2
	var p := 1.0 + punch
	shaker.position = off + c - c * p
	shaker.scale = Vector2(p, p)
	world.position = c - Vector2(cam.x, cam.y) * cam.size
	var k: float = cam.size / TileArt.S0
	world.scale = Vector2(k, k)

	for n in nodes.values():
		var a := _tile_anim(n, now)
		n.apply_anim(a.x * TileArt.S0, a.y, a.z)
		n.yo_px = a.x * cam.size
		var wp: Vector2 = n.position / TileArt.S0
		n.set_mill_angle(mill_angle + (wp.x + wp.y) * cam.size * 0.01)

	var S: RunState = game.S
	var show_ghost: bool = game.sel != null and S.cur != null and not S.busy
	ghost.visible = show_ghost
	if show_ghost:
		ghost.set_tile(S.cur)
		ghost.position = Hex.wpos(game.sel.q, game.sel.r) * TileArt.S0
		var yo := -(0.14 + (0.0 if reduced else 0.035 * sin(now / 260.0)))
		ghost.apply_anim(yo * TileArt.S0, 1, 1)
		ghost.yo_px = yo * cam.size
		ghost.set_mill_angle(mill_angle)
		var blocked: bool = game.cur_eval != null and not game.cur_eval.get("blocked", []).is_empty()
		ghost.modulate = Color(1, 0.62, 0.6, 0.8) if blocked else Color(1, 1, 1, 0.92)
	slot_layer.queue_redraw()
	fx_layer.queue_redraw()


# ---------- drawing ----------

func _draw_slots() -> void:
	if game == null or game.S == null or game.harvesting:
		return
	var s: float = cam.size
	var dash := maxf(2, s * 0.11)
	for cnd in game.S.cands.values():
		var cp := to_s(cnd.q, cnd.r)
		var pts := TileArt.hex_pts(cp, s * 0.9)
		if game.sel != null and game.sel.k == cnd.k:
			slot_layer.draw_colored_polygon(pts, Color(1, 1, 1, 0.32))
		for i in 6:
			slot_layer.draw_dashed_line(pts[i], pts[(i + 1) % 6], Pal.slot, maxf(1.8, s * 0.035), dash, true, true)


func _screen_of(k: Vector2i) -> Vector2:
	var n: TileNode = nodes.get(k)
	return to_s(k.x, k.y) + Vector2(0, n.yo_px if n else 0.0)


func _draw_fx() -> void:
	if game == null or game.S == null:
		return
	var ci := fx_layer
	var s: float = cam.size
	var now := Fx.now()
	var S: RunState = game.S

	# closed-area flashes: a fading outline around a just-closed biome region
	for i in range(_flashes.size() - 1, -1, -1):
		var fl: Dictionary = _flashes[i]
		var ft: float = (now - fl.t0) / fl.dur
		if ft >= 1:
			_flashes.remove_at(i)
			continue
		var fa := 1.0 - ft * ft
		var fc := Defs.top(fl.t)
		fc.a = 0.55 * fa
		for k in fl.keys:
			var fp := _screen_of(k)
			ci.draw_colored_polygon(TileArt.hex_pts(fp, s * 0.92), Color(1, 1, 1, 0.16 * fa))
			TileArt.stroke_hex(ci, fp, s * 0.94, fc, maxf(2, s * 0.09) + 4)
			TileArt.stroke_hex(ci, fp, s * 0.94, Color(1, 1, 1, 0.9 * fa), maxf(1.5, s * 0.05))

	# region highlight during the harvest
	var hl = game.hl_region
	if hl != null:
		var glow := Defs.dark(hl.t)
		glow.a = 0.45
		for k in hl.keys:
			var p := _screen_of(k)
			TileArt.stroke_hex(ci, p, s * 0.94, glow, maxf(1.5, s * 0.07) + 5)
			TileArt.stroke_hex(ci, p, s * 0.94, Color(1, 1, 1, 0.95), maxf(1.5, s * 0.07))

	# golden tiles: a soft pulsing ring so they stand out on a busy board
	var pulse := 0.5 + 0.5 * sin(now / 420.0)
	for gk in nodes:
		var gn: TileNode = nodes[gk]
		if gn.tile != null and gn.tile.gold:
			var gp := _screen_of(gk)
			TileArt.stroke_hex(ci, gp, s * (1.0 + 0.04 * pulse), Color(1, 0.82, 0.25, 0.25 + 0.35 * pulse), maxf(2, s * 0.06))
	if ghost.visible and S.cur != null and S.cur.gold:
		var gg := to_s(game.sel.q, game.sel.r) + Vector2(0, ghost.yo_px)
		TileArt.stroke_hex(ci, gg, s * (1.0 + 0.04 * pulse), Color(1, 0.82, 0.25, 0.25 + 0.35 * pulse), maxf(2, s * 0.06))

	# quest pennants
	for k in nodes:
		var e = S.board.get(k)
		if e == null or e.quest.is_empty():
			continue
		var p := _screen_of(k)
		if not e.qdone:
			TileArt.pennant(ci, Pal.bold, p, s, e.quest, e.prog)
		elif e.has("done_at"):
			var t: float = (now - e.done_at) / 700.0
			if t < 1:
				TileArt.pennant(ci, Pal.bold, p - Vector2(0, t * s * 0.6), s, e.quest, e.quest.need, 1 - t, 1 + t * 0.5)

	# ghost extras
	if ghost.visible:
		var gp := to_s(game.sel.q, game.sel.r) + Vector2(0, ghost.yo_px)
		if S.cur.has_quest():
			TileArt.pennant(ci, Pal.bold, gp, s, S.cur.quest, 1, 0.9)
		_draw_indicators(gp, s)
		_draw_ray_preview(s)

	fx.draw(ci, ws, s)


func _draw_indicators(c: Vector2, s: float) -> void:
	var ev = game.cur_eval
	if ev == null:
		return
	var ci := fx_layer
	for i in 6:
		var m: int = ev.per[i]
		if m < 0:
			continue
		var a := -i * PI / 3
		var r := s * 0.84
		var a1 := a - PI / 6 + 0.13
		var a2 := a + PI / 6 - 0.13
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var p2 := c + Vector2(cos(a2), sin(a2)) * r
		if m == 1:
			var w := maxf(3.5, s * 0.11)
			ci.draw_line(p1 + Vector2(0, 1), p2 + Vector2(0, 1), Color(0, 0, 0, 0.55), w + 3, true)
			ci.draw_line(p1, p2, Color.WHITE, w, true)
		else:
			var w := maxf(3, s * 0.09)
			ci.draw_dashed_line(p1 + Vector2(0, 1), p2 + Vector2(0, 1), Color(0, 0, 0, 0.55), w + 3, s * 0.075, true, true)
			ci.draw_dashed_line(p1, p2, Color("#ff5247"), w, s * 0.075, true, true)
	# river / railroad links, and edges where the tile would cut one
	var blocked: Array = ev.get("blocked", [])
	for i in 6:
		var fp: int = ev.feat_per[i]
		var p := c + TileArt.edge_mid(i, s * 0.7)
		var rad := maxf(3.5, s * 0.085)
		if blocked.has(i):
			var d := rad * 1.1
			for pair in [[Vector2(-d, -d), Vector2(d, d)], [Vector2(-d, d), Vector2(d, -d)]]:
				ci.draw_line(p + pair[0] + Vector2(0, 1), p + pair[1] + Vector2(0, 1), Color(0, 0, 0, 0.4), maxf(3, s * 0.08) + 1.5, true)
				ci.draw_line(p + pair[0], p + pair[1], Color("#e5534b"), maxf(3, s * 0.08), true)
		elif fp == 1:
			ci.draw_circle(p + Vector2(0, 1), rad + 1.5, Color(0, 0, 0, 0.3))
			ci.draw_circle(p, rad + 1.5, Color.WHITE)
			ci.draw_circle(p, rad, Defs.top(ev.feat_kind[i]))
		elif fp == 0:
			ci.draw_arc(p, rad, 0, TAU, 16, Color(0.9, 0.33, 0.29, 0.85), maxf(1.5, s * 0.035), true)


func _draw_ray_preview(s: float) -> void:
	var ev = game.cur_eval
	if ev == null or ev.events.is_empty():
		return
	var ci := fx_layer
	var col := Color(1, 0.925, 0.627, 0.95)
	for e in ev.events:
		var own: bool = e.src.q == game.sel.q and e.src.r == game.sel.r
		var sp := to_s(e.src.q, e.src.r) + Vector2(0, (ghost.yo_px if own else 0.0) - s * 0.2)
		for ray in e.rays:
			var last: Dictionary = ray.hits[ray.hits.size() - 1].e
			var lp := to_s(last.q, last.r) - Vector2(0, s * 0.1)
			ci.draw_dashed_line(sp + Vector2(0, 1), lp + Vector2(0, 1), Color(0, 0, 0, 0.35), maxf(2, s * 0.06) + 1, s * 0.11, true, true)
			ci.draw_dashed_line(sp, lp, col, maxf(2, s * 0.06), s * 0.11, true, true)
			for h in ray.hits:
				ci.draw_circle(to_s(h.e.q, h.e.r) - Vector2(0, s * 0.1), maxf(3, s * 0.1), Color(1, 0.925, 0.627, 0.98))


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# drag with the left (past a small threshold) or middle button to move the view
		if _middle or (_down != null and (_dragging or mm.position.distance_to(_down) > 10)):
			_dragging = true
			pan_by(mm.relative)
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		else:
			hovered.emit(hit_test(mm.position))
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		pan_by(-event.delta * 12)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if mb.double_click and not (game and game.harvesting) and hit_test(mb.position) == null:
						reset_view()  # double-click empty ground: back to the whole board
					_down = mb.position
					_dragging = false
				elif _down != null:
					var was_drag := _dragging
					_down = null
					_dragging = false
					mouse_default_cursor_shape = Control.CURSOR_ARROW
					if game and game.harvesting:
						speed_up_requested.emit()
					elif not was_drag:
						clicked.emit(hit_test(mb.position))
			MOUSE_BUTTON_MIDDLE:
				_middle = mb.pressed
				if not mb.pressed:
					_dragging = false
					mouse_default_cursor_shape = Control.CURSOR_ARROW
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					if game and game.harvesting:
						speed_up_requested.emit()
					else:
						# keep the preview under the cursor, then rotate
						hovered.emit(hit_test(mb.position))
						rotate_requested.emit(-1 if mb.shift_pressed else 1)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP:
				# scroll zooms toward the cursor; ctrl + scroll rotates the tile
				if mb.pressed:
					var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
					if mb.ctrl_pressed:
						rotate_requested.emit(-1 if up else 1)
					else:
						zoom_at(mb.position, pow(1.12, mb.factor if mb.factor > 0 else 1.0) if up else 1.0 / pow(1.12, mb.factor if mb.factor > 0 else 1.0))
		accept_event()


## WASD moves the view while no overlay is open.
func _key_pan(dt: float) -> void:
	if game.overlay != null and game.overlay.visible:
		return
	var d := Vector2(
		int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	if d != Vector2.ZERO:
		pan_by(-d.normalized() * KEY_PAN_SPEED * dt)


## Briefly outlines a just-closed biome region (`keys` are its tiles).
func flash_region(t: String, keys: Array, ms: float) -> void:
	_flashes.append({"t": t, "keys": keys, "t0": Fx.now(), "dur": ms})
