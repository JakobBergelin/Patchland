@tool
class_name SpecialDef
extends Resource
## A special tile. Edit in the Inspector via data/content.tres.

## Stable id used by the rules code and saves (don't rename).
@export var id := ""
@export var name := ""
@export_multiline var desc := ""
## "ray" fires rays (dirs/length), "landmark" doubles its area's harvest yield,
## "wild" matches any land, "stones" adds multiplier per special tile.
@export_enum("ray", "landmark", "wild", "stones") var kind := "ray"
## Ray directions in base orientation (0 = E, counter-clockwise).
@export var dirs: PackedInt32Array = []
@export var length := 0
## Landmarks: the land type whose area they boost.
@export var terrain := ""
@export_group("Unlock")
## RunState stat checked by the achievement, and the value that unlocks it.
@export var unlock_stat := ""
@export var unlock_need := 0
@export var unlock_text := ""
