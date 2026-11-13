extends Control
## Title screen and pause menu. Layout lives in main_menu.tscn; this script only
## fills in the dynamic bits and reports button presses as signals.

signal continue_pressed
signal play_pressed
signal tutorial_pressed
signal collection_pressed
signal scoreboard_pressed
signal rules_pressed
signal quit_pressed
signal season_changed(season: int)
signal test_run_toggled(on: bool)

var season := 1
var seasons_open := 1


## info: {run_active, run_info, first_time, season, seasons_open, test_run, best,
##        progress: Vector2i, next_unlock, hero: Array}
func setup(info: Dictionary) -> void:
	var active: bool = info.run_active
	%RunInfo.visible = active
	%RunInfo.text = info.get("run_info", "")
	%Continue.visible = active
	%Play.visible = not active
	%NewRun.visible = active
	%Play.text = "Play" if not info.first_time else "Play a run"
	%Tutorial.theme_type_variation = &"GoldButton" if info.first_time and not active else &""
	season = info.season
	seasons_open = info.seasons_open
	_render_season()
	%TestRun.button_pressed = info.test_run
	%Best.text = "Best run: %s points" % Defs.fmt(info.best) if info.best > 0 else ("New here? Start with the tutorial." if info.first_time else "")
	var pr: Vector2i = info.progress
	%ProgressLabel.text = "Collection  %d / %d unlocked" % [pr.x, pr.y]
	%ProgressBar.max_value = pr.y
	%ProgressBar.value = pr.x
	%NextUnlock.text = info.get("next_unlock", "")
	%Hero.list = info.hero
	%Hero.queue_redraw()
	%Quit.visible = OS.get_name() != "Web"
	(%Continue if active else (%Tutorial if info.first_time else %Play)).grab_focus.call_deferred()


func _ready() -> void:
	%Continue.pressed.connect(func(): continue_pressed.emit())
	%Play.pressed.connect(func(): play_pressed.emit())
	%NewRun.pressed.connect(func(): play_pressed.emit())
	%Tutorial.pressed.connect(func(): tutorial_pressed.emit())
	%Collection.pressed.connect(func(): collection_pressed.emit())
	%Scoreboard.pressed.connect(func(): scoreboard_pressed.emit())
	%Rules.pressed.connect(func(): rules_pressed.emit())
	%Quit.pressed.connect(func(): quit_pressed.emit())
	%TestRun.toggled.connect(func(on): test_run_toggled.emit(on))
	%SeasonPrev.pressed.connect(func(): _step_season(-1))
	%SeasonNext.pressed.connect(func(): _step_season(1))


func _step_season(d: int) -> void:
	season = clampi(season + d, 1, seasons_open)
	_render_season()
	season_changed.emit(season)


func _render_season() -> void:
	%SeasonLabel.text = "Season %d" % season
	%SeasonPrev.disabled = season <= 1
	%SeasonNext.disabled = season >= seasons_open
	var scale: float = Defs.SEASON_SCALE[season - 1]
	var total := Defs.SEASON_SCALE.size()
	if seasons_open < total and season == seasons_open:
		%SeasonInfo.text = ("Normal goals" if scale == 1.0 else "Goals ×%.2f" % scale) + "  ·  win to open Season %d" % (season + 1)
	else:
		%SeasonInfo.text = "Normal goals" if scale == 1.0 else "Goals ×%.2f" % scale
