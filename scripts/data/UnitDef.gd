class_name UnitDef
extends RefCounted
## A military unit type. Stats transcribed from the data-mined dirm2/parpio-battle
## values in the research doc. Units are goods with no upkeep; an army is a count per
## unit type. `tier` is a DURATION weight (not HP). Abilities drive the battle resolver.

var id: String
var display_name: String
var hp: int
var atk: int
var tier: int                ## duration weight; bosses are 100+
var abilities: Array[String] = []  ## "First","Last","Double","Triple","Ranged","Flank","Trample","Splash"
var is_boss: bool = false

func _init(p_id := "", p_name := "", p_hp := 1, p_atk := 0, p_tier := 1,
		p_abilities: Array[String] = [], p_boss := false) -> void:
	id = p_id
	display_name = p_name
	hp = p_hp
	atk = p_atk
	tier = p_tier
	abilities = p_abilities.duplicate()
	is_boss = p_boss

func has_ability(a: String) -> bool:
	return abilities.has(a)

func is_ranged() -> bool:
	return abilities.has("Ranged")
