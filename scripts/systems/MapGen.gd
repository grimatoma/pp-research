class_name MapGen
extends RefCounted
## Seeded procedural island generator. Produces a roughly elliptical landmass with a
## beach ring, forest patches, a mountain cluster, and a meandering river that reaches
## the coast (so river-spot mills are placeable). Deterministic: same seed → same map.

const T := Constants.Terrain

## Generate an island. `num_camps` Orc forts are placed in the outer ring (away from
## the centre where the Kontor lands); set `warchief` to a boss unit id to make one camp
## a warchief fort (clearing it grants a Cartography point). `region` tags the climate.
static func generate(width: int, height: int, seed_value: int, region := "temperate",
		num_camps := 2, warchief := "") -> Island:
	var isl := Island.new(width, height)
	isl.region = region
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var coast := FastNoiseLite.new()
	coast.seed = seed_value
	coast.frequency = 0.09
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 7
	forest.frequency = 0.16

	var cx := width / 2.0
	var cy := height / 2.0
	var maxr: float = min(width, height) * 0.46

	# Base landmass: distance falloff perturbed by noise → grass / beach / water.
	for y in height:
		for x in width:
			var dx := (x - cx) / maxr
			var dy := (y - cy) / maxr
			var dist := sqrt(dx * dx + dy * dy)
			var edge := dist + coast.get_noise_2d(x, y) * 0.18
			var t := T.WATER
			if edge < 0.84:
				t = T.GRASS
			elif edge < 1.0:
				t = T.BEACH
			isl.set_terrain(Vector2i(x, y), t)

	# Forest patches: high-frequency noise carves woodland out of interior grass.
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if isl.get_terrain(c) == T.GRASS and forest.get_noise_2d(x, y) > 0.28:
				isl.set_terrain(c, T.FOREST)

	# Mountain cluster: one blob in the interior.
	_add_mountains(isl, rng)
	# A river from the interior to the sea.
	_carve_river(isl, rng)
	# Orc forts blocking buildable land (offensive-only PvE — they never attack).
	_add_camps(isl, rng, num_camps, warchief)
	return isl

# ── Orc camps ────────────────────────────────────────────────────────────────

static func _add_camps(isl: Island, rng: RandomNumberGenerator, count: int, warchief: String) -> void:
	var size := Vector2i(3, 3)
	var placed := 0
	var next_id := 1
	var cx := isl.width / 2.0
	var cy := isl.height / 2.0
	var min_d: float = min(isl.width, isl.height) * 0.22  ## keep clear of the Kontor core
	for _attempt in range(600):
		if placed >= count:
			break
		var x := rng.randi_range(2, isl.width - size.x - 2)
		var y := rng.randi_range(2, isl.height - size.y - 2)
		var origin := Vector2i(x, y)
		if Vector2(x - cx, y - cy).length() < min_d:
			continue
		if not _area_is_grass(isl, origin, size):
			continue
		if _overlaps_camp(isl, origin, size):
			continue
		var camp := OrcCamp.new(next_id, origin, size)
		next_id += 1
		# First camp can be the warchief fort (tougher + a Cartography reward).
		var threat := rng.randi_range(1, 2)
		if warchief != "" and placed == 0:
			camp.boss = warchief
			camp.display_name = Database.unit(warchief).display_name + "'s Fort" \
				if Database.unit(warchief) else "Warchief's Fort"
			camp.army = _camp_army(rng, 3)
		else:
			camp.display_name = "Orc Camp"
			camp.army = _camp_army(rng, threat)
		isl.camps.append(camp)
		placed += 1

static func _area_is_grass(isl: Island, origin: Vector2i, size: Vector2i) -> bool:
	for dy in size.y:
		for dx in size.x:
			if isl.get_terrain(origin + Vector2i(dx, dy)) != T.GRASS:
				return false
	return true

static func _overlaps_camp(isl: Island, origin: Vector2i, size: Vector2i) -> bool:
	for camp in isl.camps:
		for dy in range(-1, size.y + 1):
			for dx in range(-1, size.x + 1):
				if camp.contains(origin + Vector2i(dx, dy)):
					return true
	return false

## Defender composition by threat (1 = weak, beatable with early Militia/Archers).
static func _camp_army(rng: RandomNumberGenerator, threat: int) -> Dictionary:
	match threat:
		1:
			return {"orcling": rng.randi_range(4, 7), "orc_grunt": rng.randi_range(2, 3)}
		2:
			return {"orcling": rng.randi_range(4, 6), "orc_grunt": rng.randi_range(4, 6),
				"orc_archer": rng.randi_range(2, 3)}
		_:
			return {"orc_grunt": rng.randi_range(6, 9), "orc_archer": rng.randi_range(3, 5),
				"orc_brute": rng.randi_range(2, 4)}

static func _add_mountains(isl: Island, rng: RandomNumberGenerator) -> void:
	# Pick an interior grass tile as the cluster centre.
	var center := _random_land(isl, rng)
	if center == Vector2i(-1, -1):
		return
	var blob_radius := rng.randi_range(3, 5)
	for dy in range(-blob_radius, blob_radius + 1):
		for dx in range(-blob_radius, blob_radius + 1):
			var c := center + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d <= blob_radius - rng.randf() * 1.5:
				var t := isl.get_terrain(c)
				if t == T.GRASS or t == T.FOREST:
					isl.set_terrain(c, T.MOUNTAIN)

static func _carve_river(isl: Island, rng: RandomNumberGenerator) -> void:
	# Start near the centre, step toward a random edge, carving river over land.
	var pos := Vector2(isl.width / 2.0, isl.height / 2.0)
	var angle := rng.randf() * TAU
	var dir := Vector2(cos(angle), sin(angle))
	for _i in range(200):
		var c := Vector2i(roundi(pos.x), roundi(pos.y))
		if not isl.in_bounds(c):
			break
		var t := isl.get_terrain(c)
		if t == T.WATER:
			break  # reached the sea
		if t == T.GRASS or t == T.FOREST or t == T.BEACH:
			isl.set_terrain(c, T.RIVER)
		# meander a little each step
		angle += rng.randf_range(-0.4, 0.4)
		dir = Vector2(cos(angle), sin(angle))
		pos += dir

static func _random_land(isl: Island, rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in range(400):
		var x := rng.randi_range(isl.width / 4, isl.width * 3 / 4)
		var y := rng.randi_range(isl.height / 4, isl.height * 3 / 4)
		var c := Vector2i(x, y)
		if isl.get_terrain(c) == T.GRASS:
			return c
	return Vector2i(-1, -1)
