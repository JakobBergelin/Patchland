class_name Tutorial
extends RefCounted
## Guided first round. Each step has a text and either an event that advances it
## (the player does the thing) or a Next button. Game calls notify(event) from
## its input/placement code and shows the current step in a callout.

const SEED := 20261113
const GOAL := 220
const TILES := 8

## event: "" = advance with the Next button; otherwise advance when Game reports it.
const STEPS := [
	{"title": "Welcome to Patchland", "text": "You grow a patch of countryside one hex tile at a time. The tile in the bottom-left corner is the one you place next; the two small ones beside it come after.", "event": ""},
	{"title": "Preview a spot", "text": "Move the mouse over a dashed spot on the board to see your tile there. Solid white edges match the land next to them; red dashes don't.", "event": "hover"},
	{"title": "Rotate", "text": "Right-click to turn the tile (shift + right-click turns it back). Try to make as many edges match as you can.", "event": "rotate"},
	{"title": "Place it", "text": "Left-click to place the tile. Every matching edge adds its yield and +1 multiplier.", "event": "place"},
	{"title": "Yield × multiplier", "text": "That's your score for the tile: the blue yield times the red multiplier. Match every neighbor and it's a Perfect, which doubles the multiplier. Perfects in a row build a streak.", "event": ""},
	{"title": "The goal", "text": "The bar at the top is your round score; the lighter part shows what the harvest would add right now. Reach the goal before your tiles run out.", "event": ""},
	{"title": "Bonuses", "text": "Close an area of one land type (no open edge left) for a bonus that grows with its size. Rivers and railroads pay extra when you link them, and a tile may never cut one.", "event": ""},
	{"title": "Look around", "text": "Scroll to zoom, drag or use WASD to move the view, and press F to see the whole board again.", "event": ""},
	{"title": "Finish the round", "text": "Place the rest of your tiles. When they run out, the harvest scores every linked region on the board. Reach %s to finish the tutorial." % GOAL, "event": "end"},
]

var step := 0


func current() -> Dictionary:
	return STEPS[step]


func is_last() -> bool:
	return step >= STEPS.size() - 1


## Advances when `event` is what the current step waits for. Returns true if it moved.
func notify(event: String) -> bool:
	if current().event == event and not is_last():
		step += 1
		return true
	return false


func next() -> void:
	if not is_last():
		step += 1
