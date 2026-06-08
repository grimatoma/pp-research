class_name Island
extends RefCounted
## One island: a square grid of terrain-typed tiles, the buildings placed on it, and
## the shared stockpile of goods. Buildings occupy whole-tile rectangles. No roads —
## connectivity is proximity to a storage building (resolved by Sim/Logistics).

var width: int = 32
var height: int = 32
var island_name: String = "Verdant Isle"
var region: String = "temperate"                     ## climate region (temperate/tropical/northern)
var terrain: PackedInt32Array = PackedInt32Array()   ## width*height, row-major
var buildings: Array[PlacedBuilding] = []
var stockpile: Dictionary = {}                       ## good_id -> float
var camps: Array[OrcCamp] = []                       ## Orc forts blocking buildable land
var discovered: bool = true                          ## false until a discovery ship arrives
var settled: bool = false                            ## kept & built on (vs handed over / turned in)
var _occupancy: Dictionary = {}                      ## Vector2i -> index into `buildings`

const T := Constants.Terrain

func _init(p_width := 32, p_height := 32) -> void:
	width = p_width
	height = p_height
	terrain.resize(width * height)
	terrain.fill(T.WATER)

# ── grid helpers ──────────────────────────────────────────────────────────────

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func _idx(c: Vector2i) -> int:
	return c.y * width + c.x

func get_terrain(c: Vector2i) -> int:
	if not in_bounds(c):
		return T.WATER
	return terrain[_idx(c)]

func set_terrain(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		terrain[_idx(c)] = t

## All footprint cells for a building def placed with top-left at `origin`.
func cells_for(def: BuildingDef, origin: Vector2i) -> Array:
	var out: Array = []
	for dy in def.size.y:
		for dx in def.size.x:
			out.append(origin + Vector2i(dx, dy))
	return out

func is_occupied(c: Vector2i) -> bool:
	return _occupancy.has(c)

## A cell blocked by an uncleared Orc camp (cannot build there until conquered).
func is_blocked_by_camp(c: Vector2i) -> bool:
	for camp in camps:
		if not camp.cleared and camp.contains(c):
			return true
	return false

func camp_at(c: Vector2i) -> OrcCamp:
	for camp in camps:
		if camp.contains(c):
			return camp
	return null

func active_camps() -> Array:
	return camps.filter(func(c): return not c.cleared)

func building_at(c: Vector2i) -> PlacedBuilding:
	if _occupancy.has(c):
		return buildings[_occupancy[c]]
	return null

func _is_adjacent_to(c: Vector2i, t: int) -> bool:
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if get_terrain(c + d) == t:
			return true
	return false

# ── placement validation ───────────────────────────────────────────────────────

## Returns {"ok": bool, "reason": String}. Mirrors PP2 terrain "Remarks".
func can_place(def: BuildingDef, origin: Vector2i) -> Dictionary:
	var cells := cells_for(def, origin)
	var touches_river := false
	for c in cells:
		if not in_bounds(c):
			return {"ok": false, "reason": "Out of bounds"}
		if is_occupied(c):
			return {"ok": false, "reason": "Tile occupied"}
		if is_blocked_by_camp(c):
			return {"ok": false, "reason": "Orc camp — clear it first"}
		var t := get_terrain(c)
		if t == T.WATER:
			return {"ok": false, "reason": "Cannot build on ocean"}
		if t == T.RIVER:
			touches_river = true
		match def.terrain_req:
			BuildingDef.ANY_LAND:
				if t != T.GRASS:
					return {"ok": false, "reason": "Needs clear grass"}
			T.FOREST:
				if t != T.FOREST:
					return {"ok": false, "reason": "Needs forest tiles"}
			T.MOUNTAIN:
				if t != T.MOUNTAIN:
					return {"ok": false, "reason": "Needs a mountain"}
			T.BEACH:
				if t != T.BEACH:
					return {"ok": false, "reason": "Build next to the beach"}
			T.RIVER:
				if t != T.GRASS and t != T.RIVER:
					return {"ok": false, "reason": "Needs a river spot"}
	if def.terrain_req == T.RIVER and not touches_river:
		# allow if any footprint tile borders a river
		var borders := false
		for c in cells:
			if _is_adjacent_to(c, T.RIVER):
				borders = true
				break
		if not borders:
			return {"ok": false, "reason": "Must sit on a straight river spot"}
	if def.needs_coast:
		# "On the coast" = bordering the shoreline (ocean OR beach). Grass never
		# touches deep water directly (a beach ring separates them), so accept either.
		var coastal := false
		for c in cells:
			if _is_adjacent_to(c, T.WATER) or _is_adjacent_to(c, T.BEACH):
				coastal = true
				break
		if not coastal:
			return {"ok": false, "reason": "Must be built next to the ocean"}
	return {"ok": true, "reason": ""}

# ── mutation ────────────────────────────────────────────────────────────────────

func place(def: BuildingDef, origin: Vector2i) -> PlacedBuilding:
	var pb := PlacedBuilding.new(def.id, origin)
	if def.is_house:
		pb.tier_id = def.house_tier
		pb.residents = 1  ## a fresh house starts with one pioneer family
	var idx := buildings.size()
	buildings.append(pb)
	for c in cells_for(def, origin):
		_occupancy[c] = idx
	return pb

func remove_at(c: Vector2i) -> bool:
	if not _occupancy.has(c):
		return false
	var idx: int = _occupancy[c]
	var pb := buildings[idx]
	var def := Database.building(pb.building_id)
	if def != null:
		for cc in cells_for(def, pb.origin):
			_occupancy.erase(cc)
	buildings.remove_at(idx)
	_reindex()
	return true

func _reindex() -> void:
	_occupancy.clear()
	for i in buildings.size():
		var pb := buildings[i]
		var def := Database.building(pb.building_id)
		if def == null:
			continue
		for c in cells_for(def, pb.origin):
			_occupancy[c] = i

# ── stockpile ────────────────────────────────────────────────────────────────────

func qty(good_id: String) -> float:
	return float(stockpile.get(good_id, 0.0))

func add(good_id: String, amount: float) -> void:
	stockpile[good_id] = qty(good_id) + amount

func take(good_id: String, amount: float) -> float:
	var have := qty(good_id)
	var taken: float = min(have, amount)
	stockpile[good_id] = have - taken
	return taken

# ── persistence ──────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var blds: Array = []
	for pb in buildings:
		blds.append(pb.to_dict())
	var camp_list: Array = []
	for camp in camps:
		camp_list.append(camp.to_dict())
	return {
		"width": width,
		"height": height,
		"island_name": island_name,
		"region": region,
		"terrain": Array(terrain),
		"buildings": blds,
		"stockpile": stockpile.duplicate(),
		"camps": camp_list,
		"discovered": discovered,
		"settled": settled,
	}

static func from_dict(d: Dictionary) -> Island:
	var isl := Island.new(int(d.get("width", 32)), int(d.get("height", 32)))
	isl.island_name = String(d.get("island_name", "Verdant Isle"))
	isl.region = String(d.get("region", "temperate"))
	isl.discovered = bool(d.get("discovered", true))
	isl.settled = bool(d.get("settled", false))
	var terr: Array = d.get("terrain", [])
	if terr.size() == isl.width * isl.height:
		isl.terrain = PackedInt32Array(terr)
	for bd in d.get("buildings", []):
		isl.buildings.append(PlacedBuilding.from_dict(bd))
	var sp: Dictionary = d.get("stockpile", {})
	for k in sp:
		isl.stockpile[k] = float(sp[k])
	for cd in d.get("camps", []):
		isl.camps.append(OrcCamp.from_dict(cd))
	isl._reindex()
	return isl
