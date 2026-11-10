extends SceneTree
## Visual smoke test (needs a real window, not --headless). Starts the game,
## dismisses the intro, hovers a slot, right-clicks to rotate, places a tile
## and saves screenshots. Pass an output folder after `--`:
## godot --path . -s res://tests/screenshot.gd -- C:/tmp/shots

var out_dir := "user://shots"
var game: Game


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await _wait(2)
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _mouse(pos: Vector2, button := MOUSE_BUTTON_NONE, pressed := false) -> void:
	if button == MOUSE_BUTTON_NONE:
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.global_position = pos
		root.push_input(mm)
	else:
		var mb := InputEventMouseButton.new()
		mb.position = pos
		mb.global_position = pos
		mb.button_index = button
		mb.pressed = pressed
		root.push_input(mb)


func _cand_screen() -> Vector2:
	# pick the legal slot + rotation that matches the most edges, and turn the tile to it
	var best = null
	var best_score := -1
	var best_rot := game.S.cur.rot
	var rot0 := game.S.cur.rot
	for c in game.S.cands.values():
		for rot in 6:
			game.S.cur.rot = rot
			if not Rules.can_place(game.S, c.q, c.r, game.S.cur):
				continue
			var ev := Rules.evaluate(game.S, c.q, c.r, game.S.cur)
			var score: int = ev.matches + ev.feat_matches
			if score > best_score or (score == best_score and rot == rot0):
				best_score = score
				best = c
				best_rot = rot
	game.S.cur.rot = best_rot
	game.refresh_eval()
	return game.board.global_position + game.board.to_s(best.q, best.r)


func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await _wait(30)
	await _shot("01_intro")
	game.close_overlay()
	game.started = true
	game.round_banner()
	await _wait(150)
	var p := _cand_screen()
	_mouse(p)
	await _wait(20)
	await _shot("02_hover")
	var rot0: int = game.S.cur.rot
	_mouse(p, MOUSE_BUTTON_RIGHT, true)
	_mouse(p, MOUSE_BUTTON_RIGHT, false)
	await _wait(20)
	print("right-click rotation: %d -> %d" % [rot0, game.S.cur.rot])
	await _shot("03_after_right_click")
	p = _cand_screen()  # the rotation may have made that spot illegal (it would cut a line)
	_mouse(p)
	await _wait(2)
	_mouse(p, MOUSE_BUTTON_LEFT, true)
	_mouse(p, MOUSE_BUTTON_LEFT, false)
	await _wait(25)
	await _shot("04_scoring")
	# play a few more tiles quickly
	for n in 8:
		await _wait(150)
		if game.S.busy:
			continue
		var q := _cand_screen()
		_mouse(q)
		await _wait(3)
		_mouse(q, MOUSE_BUTTON_LEFT, true)
		_mouse(q, MOUSE_BUTTON_LEFT, false)
		await _wait(2)
		if not game.S.busy:
			# synthetic mouse input is dropped while the real cursor is outside the window
			game._on_click(game.board.hit_test(q - game.board.global_position))
	await _wait(160)
	_mouse(_cand_screen())
	await _wait(10)
	await _shot("05_board")
	# camera: scroll to zoom toward a tile, middle-drag to pan, then reset
	var z0: float = game.board.cam.size
	var zp := _cand_screen()
	for k in 4:
		var wh := InputEventMouseButton.new()
		wh.button_index = MOUSE_BUTTON_WHEEL_UP
		wh.pressed = true
		wh.factor = 1.0
		wh.position = zp
		wh.global_position = zp
		root.push_input(wh)
		await _wait(1)
	_mouse(zp, MOUSE_BUTTON_MIDDLE, true)
	var mm := InputEventMouseMotion.new()
	mm.position = zp + Vector2(-120, 40)
	mm.global_position = mm.position
	mm.relative = Vector2(-120, 40)
	mm.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(mm)
	_mouse(zp + Vector2(-120, 40), MOUSE_BUTTON_MIDDLE, false)
	await _wait(10)
	print("zoom: cam size %.1f -> %.1f, user_zoom %.2f, pan %s" % [z0, game.board.cam.size, game.board.user_zoom, game.board.user_pan])
	await _shot("05b_zoomed")
	game.board.reset_view()
	await _wait(60)
	print("reset: cam size %.1f" % game.board.cam.size)
	# fullscreen on and back off (restores the saved setting)
	var was_fs: bool = game.is_fullscreen()
	game.toggle_fullscreen()
	await _wait(45)
	print("fullscreen: %s, window %s%s" % [game.is_fullscreen(), DisplayServer.window_get_size(), "" if game.is_fullscreen() else "  (the OS did not apply it; the window may not have focus)"])
	await _shot("05c_fullscreen")
	game.set_fullscreen(was_fs)
	await _wait(20)
	# finish the round, then capture the harvest and whatever overlay follows
	game.S.round_score += 100000  # make sure the goal is reached so the draft shows
	while game.S.tiles_left > 0:
		await _wait(20)
		if game.S.busy:
			continue
		var q := _cand_screen()
		_mouse(q)
		await _wait(2)
		_mouse(q, MOUSE_BUTTON_LEFT, true)
		_mouse(q, MOUSE_BUTTON_LEFT, false)
		await _wait(2)
		if not game.S.busy:
			# synthetic mouse input is dropped while the real cursor is outside the window
			game._on_click(game.board.hit_test(q - game.board.global_position))
	while not game.harvesting:
		await _wait(5)
	await _wait(150)
	await _shot("06_harvest")
	while not game.overlay.visible:
		await _wait(10)
	await _wait(40)
	await _shot("07_draft")
	quit()
