class_name ResearchDef
extends RefCounted
## One Creativity research perk. Perks live in a per-tier "tree" (available once that
## population tier is reached) plus an endless "infinite" tree of repeatable perks with
## escalating cost. Effects are applied as global economy modifiers in WorldSim.
##
## effect = { "type": String, "key": String (optional good id), "value": float }
##   "tax_mult"        — adds `value` to the Coin payout multiplier (0.10 = +10%)
##   "creativity_mult" — adds `value` to the Creativity generation multiplier
##   "prod_mult_all"   — adds `value` to every producer's output multiplier
##   "prod_mult"       — adds `value` to output multiplier for the good `key`
##   "build_cost_flat" — reduces build cost of good `key` by `value` units

var id: String
var display_name: String
var tree: String        ## a tier id ("pioneers".."paragons") or "infinite"
var description: String
var cost: int           ## base Creativity cost (repeatable perks scale by rank)
var effect: Dictionary
var repeatable: bool = false

func _init(p_id := "", p_name := "", p_tree := "pioneers", p_cost := 10,
		p_effect := {}, p_desc := "", p_repeatable := false) -> void:
	id = p_id
	display_name = p_name
	tree = p_tree
	cost = p_cost
	effect = p_effect.duplicate()
	description = p_desc
	repeatable = p_repeatable
