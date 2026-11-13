@tool
class_name ContentDB
extends Resource
## All editable game content in one place (data/content.tres).

@export var specials: Array[SpecialDef] = []
@export var relics: Array[RelicDef] = []
@export_group("Rounds")
## Round goals for Season 1 (one per round).
@export var goals: PackedInt32Array = []
@export var tiles_per_round := 10
## Goal multiplier per Season (Season 1 first). Winning a Season unlocks the next.
@export var season_goal_scale: PackedFloat32Array = []
## Draft weight per rarity (Common, Fine, Heirloom).
@export var rarity_weights: PackedFloat32Array = [6.0, 3.0, 1.0]
