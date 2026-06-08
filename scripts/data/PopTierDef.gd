class_name PopTierDef
extends RefCounted
## A population tier (Pioneers → Colonists → Townsmen → Merchants → Paragons in the
## temperate region). Needs are per-resident consumption denominators: a value of
## 10800 means "1 unit per 10800 seconds, per resident".
##
## THE LUXURY CASCADE (heart of the game): a tier's `luxury_needs` are EXACTLY the
## next tier's `basic_needs` — same good AND same rate. Database asserts this.

var id: String
var display_name: String
var order: int = 0                 ## 0 = lowest (Pioneers)

## good_id -> seconds-per-unit-per-resident. Basics keep residents from emigrating.
var basic_needs: Dictionary = {}
## good_id -> seconds-per-unit-per-resident. Luxuries pay out Coin and enable upgrade.
var luxury_needs: Dictionary = {}

var max_residents: int = 10        ## residents a single house of this tier holds
var coin_per_resident_per_min: float = 0.0  ## tax income while needs are met

func _init(p_id := "", p_name := "", p_order := 0) -> void:
	id = p_id
	display_name = p_name
	order = p_order

## Per-resident-per-second consumption rate for a need good (basics + luxuries merged).
func need_rate(good_id: String) -> float:
	var denom := 0.0
	if basic_needs.has(good_id):
		denom = float(basic_needs[good_id])
	elif luxury_needs.has(good_id):
		denom = float(luxury_needs[good_id])
	if denom <= 0.0:
		return 0.0
	return 1.0 / denom

## All goods this tier consumes (basics + luxuries).
func all_need_goods() -> Array:
	var goods := basic_needs.keys()
	for g in luxury_needs.keys():
		if not goods.has(g):
			goods.append(g)
	return goods
