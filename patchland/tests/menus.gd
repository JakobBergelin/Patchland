extends SceneTree
## Main menu, tutorial, pause menu, rules sheet and scoreboard flow (needs a window).
## godot --path . -s res://tests/menus.gd -- <output folder>

const CFG := "user://test_menus.cfg"
var game: Game
var out_dir := ""
var failures := 0


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if out_dir == "":
		return
	await create_timer(0.5).timeout  # let fades finish
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _legal_move() -> bool:
	for c in game.S.cands.values():
		for rot in 6:
			game.S.cur.rot = rot
			if Rules.can_place(game.S, c.q, c.r, game.S.cur):
				game.set_sel(c, true)
				return true
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ""
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))  # start as a first-time player
	game = load("res://main.tscn").instantiate()
	game.settings_path = CFG
	root.add_child(game)
	await _wait(30)

	# --- main menu at launch ---
	check(game.overlay.visible and game.overlay_kind == "menu", "launch shows the main menu")
	check(not game.run_active, "no run in progress at launch")
	await _shot("m1_menu")

	# --- tutorial ---
	game.start_tutorial()
	await _wait(10)
	check(game.tut != null and game.tut.step == 0 and game.tut_panel.visible, "tutorial starts with its callout")
	check(game.S.goal() == Tutorial.GOAL and game.S.tiles_left == Tutorial.TILES, "tutorial uses its own goal and tile count")
	await _shot("m2_tutorial")
	game._tut_next()
	check(game.tut.step == 1, "Next advances a reading step")
	game._on_hover(game.S.cands.values()[0])
	check(game.tut.step == 2, "hovering a spot advances 'Preview a spot'")
	game.rotate(1)
	check(game.tut.step == 3, "rotating advances 'Rotate'")
	_legal_move()
	game.place()
	check(game.tut.step == 4, "placing advances 'Place it'")
	await _wait(5)
	await _shot("m3_tutorial_scoring")
	while game.tut != null and not game.tut.is_last():
		game._tut_next()
	check(game.tut.is_last(), "reading steps lead to 'Finish the round'")
	# play out the tutorial round
	var guard := 0
	while not game.overlay.visible and guard < 20000:
		if not game.S.busy and _legal_move():
			game.place()
		await process_frame
		guard += 1
	check(game.overlay.visible and game.overlay_kind == "end", "the tutorial round ends with its summary")
	check(game.tut == null and not game.run_active, "tutorial is over")
	print("tutorial result: %s of %s" % [game.S.round_score, game.S.goal()])
	await _shot("m4_tutorial_end")
	check(Scores.load_list(CFG).is_empty(), "the tutorial isn't put on the scoreboard")

	# --- a real run, pause with Esc ---
	game.start_play()
	await _wait(10)
	check(game.run_active and game.tut == null and not game.overlay.visible, "Play starts a real run")
	check(game.S.goal() == Defs.GOALS[0] and game.S.tiles_left == Defs.TILES_PER_ROUND, "real run uses the normal goal and tiles")
	game._on_escape()
	await _wait(5)
	check(game.overlay_kind == "menu", "Esc opens the menu during a run")
	await _shot("m5_pause_menu")
	game._on_escape()
	check(not game.overlay.visible, "Esc again resumes")

	# --- rules sheet on the ? button ---
	game.show_rules("board")
	check(game.overlay_kind == "rules", "? opens the rules sheet")
	await _shot("m6_rules")
	game._overlay_back()
	check(not game.overlay.visible, "Back returns to the board")

	# --- end of run goes on the scoreboard ---
	game.S.total = 12345
	game.game_over()
	await _wait(5)
	check(game.last_rank == 1 and Scores.best(CFG) == 12345, "a finished run is recorded as #1")
	await _shot("m7_run_end")
	Scores.record(CFG, {"score": 50000, "rounds": 8, "won": true, "relics": 9, "best_harvest": 1, "date": "2026-11-12"})
	Scores.record(CFG, {"score": 3000, "rounds": 2, "won": false, "relics": 2, "best_harvest": 1, "date": "2026-11-12"})
	game.show_scoreboard("end")
	await _wait(5)
	var list := Scores.load_list(CFG)
	check(list.size() == 3 and list[0].score == 50000 and list[2].score == 3000, "scoreboard keeps runs sorted best first")
	await _shot("m8_scoreboard")
	game._overlay_back()
	check(game.overlay_kind == "end", "Back from the scoreboard returns to the run summary")
	game.show_main_menu()
	check(not game.run_active and game.overlay_kind == "menu", "menu after a finished run offers Play, not Continue")
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)
