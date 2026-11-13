@tool
class_name RelicDef
extends Resource
## A relic. Edit in the Inspector via data/content.tres.

## Stable id used by the rules code and saves (don't rename).
@export var id := ""
@export var name := ""
## Land type used for its icon colour.
@export var terrain := "meadow"
@export_multiline var desc := ""
## Draft odds: Common shows up most, Heirloom least.
@export_enum("Common", "Fine", "Heirloom") var rarity := 0
## Available without unlocking.
@export var starter := false
@export_group("Unlock")
@export var unlock_stat := ""
@export var unlock_need := 0
@export var unlock_text := ""
