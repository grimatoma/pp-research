class_name CustodianDef
extends RefCounted
## A Custodian: a permanent run-modifier picked at New Game+. Each is gated by a
## Reputation TIER (1/2/3/4/8) — Reputation is non-consumable, so a Custodian is
## available once your total Reputation reaches its cost (you never spend it down).
## Selecting Custodians and confirming restarts the world with those modifiers active.
##
## effect = { "type": String, "value": float }
##   start_cartography / start_creativity / start_coin — one-time starting grant
##   island_slots / army_cap_bonus / discovery_speed / creativity_mult /
##   trade_mult / battle_instant — persistent run modifier (folded into WorldSim._mods)

var id: String
var display_name: String
var rep_cost: int           ## Reputation tier required to pick it
var effect: Dictionary
var description: String

func _init(p_id := "", p_name := "", p_rep := 1, p_effect := {}, p_desc := "") -> void:
	id = p_id
	display_name = p_name
	rep_cost = p_rep
	effect = p_effect.duplicate()
	description = p_desc
