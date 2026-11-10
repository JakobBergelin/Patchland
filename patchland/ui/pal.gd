class_name Pal
## UI colours and fonts (the reference's CSS variables). Light or dark follows the OS.

static var bg := Color("#dce4e0")
static var bg2 := Color("#eef2ef")
static var ink := Color("#1e2c29")
static var soft := Color("#3d4945")
static var panel := Color("#f6f8f6")
static var line := Color(30 / 255.0, 44 / 255.0, 41 / 255.0, 0.24)
static var chips := Color("#2d6c9a")
static var mult := Color("#a3312b")
static var slot := Color(30 / 255.0, 44 / 255.0, 41 / 255.0, 0.62)
static var gold := Color("#c99412")
static var font: Font
static var bold: Font


static func init() -> void:
	if DisplayServer.is_dark_mode():
		bg = Color("#141b19")
		bg2 = Color("#23312d")
		ink = Color("#f2f7f5")
		soft = Color("#bdcbc6")
		panel = Color("#212c29")
		line = Color(228 / 255.0, 235 / 255.0, 232 / 255.0, 0.24)
		chips = Color("#4f93c6")
		mult = Color("#c9473f")
		slot = Color(228 / 255.0, 235 / 255.0, 232 / 255.0, 0.66)
		gold = Color("#e9b938")
	# System fonts only (no font files shipped yet). Bricolage Grotesque is used if installed.
	var names := PackedStringArray(["Bricolage Grotesque", "Segoe UI", "Helvetica Neue", "Arial", "sans-serif"])
	var f := SystemFont.new()
	f.font_names = names
	f.font_weight = 500
	font = f
	var b := SystemFont.new()
	b.font_names = names
	b.font_weight = 800
	bold = b


static func named(c: String) -> Color:
	match c:
		"chips":
			return chips
		"mult":
			return mult
		"gold":
			return gold
		"soft":
			return soft
		"ink":
			return ink
	return Color.html(c) if Color.html_is_valid(c) else ink
