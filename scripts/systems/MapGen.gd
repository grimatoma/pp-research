class_name MapGen
extends RefCounted
## Seeded procedural island generator. Produces a roughly elliptical landmass with a
## beach ring, forest patches, a mountain cluster, and a meandering river that reaches
## the coast (so river-spot mills are placeable). Deterministic: same seed → same map.

const T := Constants.Terrain

static func generate(width: int, height: int, seed_value: int) -> Island:
	var isl := Island.new(width, height)
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
	return isl

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
