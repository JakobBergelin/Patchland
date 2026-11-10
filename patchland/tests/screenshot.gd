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
	# pick the candidate slot that matches the most edges
	var best = null
	var best_score := -1
	for c in game.S.cands.values():
		var ev := Rules.evaluate(game.S, c.q, c.r, game.S.cur)
		if ev.matches > best_score:
			best_score = ev.matches
			best = c
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
	await _wait(160)
	_mouse(_cand_screen())
	await _wait(10)
	await _shot("05_board")
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
	while not game.harvesting:
		await _wait(5)
	await _wait(150)
	await _shot("06_harvest")
	while not game.overlay.visible:
		await _wait(10)
	await _wait(40)
	await _shot("07_draft")
	quit()
