class_name TileNode
extends Node2D
## One tile on the board. The art is recorded once per tile+rotation (Godot keeps
## the canvas command list until queue_redraw), which acts as the baked texture.
## Position is the tile centre in world units * S0; drop/squash/hop go on `art`.

var tile: Tile
var born := 0.0  # msec, 0 = no drop animation
var bump := 0.0  # msec of last hop
var yo_px := 0.0  # current vertical offset in screen px (read by the fx layer)
var art: Node2D
var sail_node: Node2D
var _drawn_id := -2
var _drawn_rot := -1
var _drawn_special := "?"


func _init(t: Tile = null) -> void:
	tile = t
	art = Node2D.new()
	add_child(art)
	art.draw.connect(_draw_art)
	sail_node = Node2D.new()
	sail_node.position = Vector2(0, -TileArt.HUB * TileArt.S0)
	art.add_child(sail_node)
	sail_node.draw.connect(_draw_sails)


func set_tile(t: Tile) -> void:
	tile = t
	refresh()


## Re-records the art if the tile or its rotation changed.
func refresh() -> void:
	if tile == null:
		return
	if tile.id != _drawn_id or tile.rot != _drawn_rot or tile.special != _drawn_special:
		_drawn_id = tile.id
		_drawn_rot = tile.rot
		_drawn_special = tile.special
		art.queue_redraw()
		sail_node.queue_redraw()
	sail_node.visible = tile.special == "windmill"


## yo_units: vertical offset in tile units; sx/sy: squash, anchored at the tile bottom.
func apply_anim(yo_units: float, sx: float, sy: float) -> void:
	art.position = Vector2(0, yo_units + TileArt.BOX_BOTTOM * (1.0 - sy))
	art.scale = Vector2(sx, sy)


func set_mill_angle(a: float) -> void:
	sail_node.rotation = a


func _draw_art() -> void:
	if tile:
		TileArt.draw_tile(art, tile)


func _draw_sails() -> void:
	if tile and tile.special == "windmill":
		TileArt.sails(sail_node, Vector2.ZERO, 0.4 * TileArt.S0, 0.0)
