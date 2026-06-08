class_name OrcCamp
extends RefCounted
## A static Orc fort on an island (PP2 milestone M8). Blocks its footprint tiles until
## an expedition clears it; clearing opens the land for building and, for a warchief
## camp, grants a Cartography point. Orcs never attack — combat is offensive-only.

var id: int = 0
var origin: Vector2i = Vector2i.ZERO   ## top-left tile of the blocked footprint
var size: Vector2i = Vector2i(3, 3)    ## footprint in tiles
var army: Dictionary = {}              ## defender unit_id -> count (full strength)
var boss: String = ""                  ## warchief unit id, or "" for a plain camp
var cleared: bool = false              ## true once defeated (land becomes buildable)
var display_name: String = "Orc Camp"

func _init(p_id := 0, p_origin := Vector2i.ZERO, p_size := Vector2i(3, 3)) -> void:
	id = p_id
	origin = p_origin
	size = p_size

## All footprint cells this camp blocks.
func cells() -> Array:
	var out: Array = []
	for dy in size.y:
		for dx in size.x:
			out.append(origin + Vector2i(dx, dy))
	return out

func contains(c: Vector2i) -> bool:
	return c.x >= origin.x and c.y >= origin.y \
		and c.x < origin.x + size.x and c.y < origin.y + size.y

## Full army incl. the boss (defenders, as a unit_id -> count Dictionary).
func full_army() -> Dictionary:
	var a := army.duplicate()
	if boss != "":
		a[boss] = int(a.get(boss, 0)) + 1
	return a

func to_dict() -> Dictionary:
	return {
		"id": id,
		"origin": [origin.x, origin.y],
		"size": [size.x, size.y],
		"army": army.duplicate(),
		"boss": boss,
		"cleared": cleared,
		"display_name": display_name,
	}

static func from_dict(d: Dictionary) -> OrcCamp:
	var c := OrcCamp.new()
	c.id = int(d.get("id", 0))
	var o: Array = d.get("origin", [0, 0])
	c.origin = Vector2i(int(o[0]), int(o[1]))
	var s: Array = d.get("size", [3, 3])
	c.size = Vector2i(int(s[0]), int(s[1]))
	var a: Dictionary = d.get("army", {})
	for k in a:
		c.army[k] = int(a[k])
	c.boss = String(d.get("boss", ""))
	c.cleared = bool(d.get("cleared", false))
	c.display_name = String(d.get("display_name", "Orc Camp"))
	return c
