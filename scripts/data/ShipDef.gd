class_name ShipDef
extends RefCounted
## A ship hull used to move goods (never population) on inter-island trade routes.
## Stats transcribed from the research spec's ship roster. The central naval gate is
## region-locked starters (Cog/Caravel, Barque/Skiff) vs region-crossing hulls
## (Hulk and up): only a crossing hull can trade between climate regions.

var id: String
var display_name: String
var region: String          ## home region of the hull
var goods_per_hour: float   ## throughput on a route
var coin_cost: int          ## one-time build cost (Coin)
var cross_region: bool      ## can it sail between climate regions?

func _init(p_id := "", p_name := "", p_region := "temperate", p_gph := 60.0,
		p_cost := 100, p_cross := false) -> void:
	id = p_id
	display_name = p_name
	region = p_region
	goods_per_hour = p_gph
	coin_cost = p_cost
	cross_region = p_cross
