class_name BuildingDef
extends RefCounted
## A placeable building. Producers carry a RecipeDef; houses carry a tier id; storage
## buildings (Kontor/warehouse) project a connectivity range. Whole-tile footprints,
## no rotation, no assigned-worker counts — faithful to PP2.

const ANY_LAND := -1  ## terrain_req sentinel: any of Constants.LAND_TERRAINS

var id: String
var display_name: String
var category: String                 ## "house" | "food" | "raw" | "production" | "storage" | "civic"
var region: String = ""              ## climate gate: "" = any | "temperate" | "tropical" | "northern"
var terrain_req: int = ANY_LAND      ## Constants.Terrain value, or ANY_LAND
var needs_coast: bool = false        ## must be adjacent to WATER (Kontor, shipyard)
var size: Vector2i = Vector2i.ONE    ## footprint in tiles
var tier_unlock: String = ""         ## population tier id that unlocks it ("" = from start)
var cost: Dictionary = {}            ## good_id -> int, one-time build cost

var recipe: RecipeDef = null         ## production recipe (null for houses / pure storage)

var is_house: bool = false
var house_tier: String = ""          ## PopTierDef id this house belongs to (lowest tier)

var is_storage: bool = false         ## provides connectivity + holds the shared stockpile
var storage_range: int = 0           ## Chebyshev tiles of connectivity it projects

var is_shipyard: bool = false        ## lets the island build ships (naval logistics)
var is_palace: bool = false          ## the prestige Palace (Foundation + 5 stages)

var color: Color = Color("c8a06a")   ## placeholder fill
var sprite_path: String = ""         ## res:// PixelLab sprite (optional)

func _init(p_id := "", p_name := "", p_category := "production") -> void:
	id = p_id
	display_name = p_name
	category = p_category

## Convenience: number of tiles this building occupies.
func tile_area() -> int:
	return size.x * size.y
