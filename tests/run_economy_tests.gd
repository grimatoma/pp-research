extends SceneTree
## Headless tests for the economy core (Database catalog + WorldSim tick). Run from
## the project root:
##   godot --headless --script res://tests/run_economy_tests.gd
## Exits 0 when every check passes, 1 on any failure (CI gate). Dependency-free
## harness in the puzzleDrag2 style. Database is a static class_name and WorldSim is
## a plain object, so no autoloads are required here.

const T := Constants.Terrain

var _checks := 0
var _failures := 0

func _initialize() -> void:
	print("\n── Pioneer Isles · economy tests ──────────────────")
	_test_catalog_loaded()
	_test_cascade_invariant()
	_test_production_basic()
	_test_production_chain_inputs()
	_test_connectivity_gate()
	_test_consumption_and_growth()
	_test_emigration()
	_test_payout()
	_test_upgrade_gate()
	_test_save_round_trip()
	_test_offline_catchup_determinism()
	_test_buildcost_producible()
	_test_save_preserves_timers()
	_test_mapgen_deterministic()
	_test_new_game_places_kontor()
	print("──────────────────────────────────────────────────")
	print("%d checks, %d failure(s)\n" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

# ── helpers ────────────────────────────────────────────────────────────────────

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", msg)
	else:
		_failures += 1
		print("  FAIL  ", msg)
		push_error("FAIL: " + msg)

# A controlled grass island with a water column on the left (column 0) so coastal
# buildings can be placed at column 1.
func _grid_island(w := 16, h := 16) -> Island:
	var isl := Island.new(w, h)
	isl.terrain.fill(T.GRASS)
	for y in h:
		isl.set_terrain(Vector2i(0, y), T.WATER)
	return isl

func _sim_with(isl: Island) -> WorldSim:
	var sim := WorldSim.new()
	sim.islands = [isl] as Array[Island]
	sim.active_index = 0
	sim.currencies = {"coin": 0.0, "cartography": 0.0, "favor": 0.0, "reputation": 0.0}
	sim.elapsed = 0.0
	return sim

func _place(isl: Island, id: String, origin: Vector2i) -> PlacedBuilding:
	return isl.place(Database.building(id), origin)

# ── tests ────────────────────────────────────────────────────────────────────

func _test_catalog_loaded() -> void:
	_check(Database.goods.size() >= 30, "catalog has >=30 goods (%d)" % Database.goods.size())
	_check(Database.building("pioneer_hut") != null, "catalog has pioneer_hut")
	_check(Database.building("fishery") != null, "catalog has fishery")
	_check(Database.tier("pioneers") != null, "catalog has pioneers tier")
	_check(Database.all_tiers().size() == 5, "5 urban tiers (%d)" % Database.all_tiers().size())

func _test_cascade_invariant() -> void:
	var ok := true
	for i in range(1, Database.all_tiers().size()):
		var prev: PopTierDef = Database.tier(Database.all_tiers()[i - 1])
		var cur: PopTierDef = Database.tier(Database.all_tiers()[i])
		for g in prev.luxury_needs:
			if Database.good(g) != null and Database.good(g).category == "service":
				continue
			if g == "hat":
				continue
			if not is_equal_approx(prev.luxury_needs[g], cur.basic_needs.get(g, -1.0)):
				ok = false
	_check(ok, "luxury cascade holds: basics(tier) == luxuries(prev) at equal rate")
	var merchants: PopTierDef = Database.tier("merchants")
	var paragons: PopTierDef = Database.tier("paragons")
	_check(merchants.luxury_needs.has("hat") and not paragons.basic_needs.has("hat"),
		"Hat is terminal (Merchant luxury, not Paragon basic)")

func _test_production_basic() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	_place(isl, "fishery", Vector2i(1, 6))
	sim.advance(200.0)
	_check(isl.qty("fish") >= 2.0, "fishery produced >=2 fish in 200s (%.1f)" % isl.qty("fish"))

func _test_production_chain_inputs() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	_place(isl, "apple_orchard", Vector2i(4, 4))
	_place(isl, "cider_maker", Vector2i(7, 7))
	sim.advance(1500.0)
	_check(isl.qty("cider") >= 1.0, "cider produced from apples (%.1f cider)" % isl.qty("cider"))
	_check(isl.qty("apple") < 7.0, "cider maker consumed apples (apples left %.1f)" % isl.qty("apple"))

func _test_connectivity_gate() -> void:
	var isl := _grid_island(40, 12)
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var far := _place(isl, "fishery", Vector2i(36, 8))
	sim._recompute_connectivity(isl)
	_check(not far.connected, "fishery 35 tiles away is disconnected")
	sim.advance(300.0)
	_check(isl.qty("fish") == 0.0, "disconnected fishery produced nothing")

func _test_consumption_and_growth() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "pioneer_hut", Vector2i(4, 4))
	hut.residents = 2
	isl.stockpile = {"fish": 100000.0, "water": 100000.0}
	sim.advance(60.0)
	_check(hut.residents > 2, "well-fed pioneers grew past 2 (now %d)" % hut.residents)
	_check(hut.residents <= 10, "pioneers respect the cap of 10 (now %d)" % hut.residents)

func _test_emigration() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "pioneer_hut", Vector2i(4, 4))
	hut.residents = 8
	isl.stockpile = {}
	sim.advance(60.0)
	_check(hut.residents < 8, "starved pioneers emigrated (now %d)" % hut.residents)

func _test_payout() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "colonist_house", Vector2i(4, 4))
	hut.residents = 10
	isl.stockpile = {
		"fish": 1e6, "water": 1e6, "sausage": 1e6, "cider": 1e6, "community": 1e6,
		"soap": 1e6, "fabric": 1e6, "bread": 1e6, "education": 1e6,
	}
	var before: float = sim.coin()
	sim.advance(60.0)
	_check(sim.coin() > before, "colonists paid coin income (%.1f)" % sim.coin())

func _test_upgrade_gate() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "pioneer_hut", Vector2i(4, 4))
	hut.residents = 10
	isl.stockpile = {"fish": 1e6, "water": 1e6, "sausage": 1e6, "cider": 1e6, "community": 1e6}
	sim._recompute_connectivity(isl)
	_check(sim.can_upgrade(hut), "pioneer hut at cap with all needs met is upgrade-eligible")
	var ok := sim.upgrade_house(hut)
	_check(ok and hut.building_id == "colonist_house", "upgraded to colonist_house")
	_check(hut.tier_id == "colonists", "tier is now colonists")
	_check(sim.unlocked_tiers.has("colonists"), "colonists tier unlocked")

func _test_save_round_trip() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "pioneer_hut", Vector2i(4, 4))
	hut.residents = 5
	isl.stockpile = {"fish": 42.0, "wood": 17.0}
	sim.currencies["coin"] = 999.0
	var d := sim.to_dict()
	var sim2 := WorldSim.new()
	sim2.from_dict(d)
	_check(is_equal_approx(sim2.coin(), 999.0), "save round-trip preserves coin")
	var r_isl := sim2.active_island()
	_check(is_equal_approx(r_isl.qty("fish"), 42.0), "save round-trip preserves stockpile")
	var found := false
	for pb in r_isl.buildings:
		if pb.building_id == "pioneer_hut" and pb.residents == 5:
			found = true
	_check(found, "save round-trip preserves the house and residents")

func _test_offline_catchup_determinism() -> void:
	# advance(a)+advance(b) == advance(a+b) for ARBITRARY splits (non-multiples of the
	# tick quantum) AND a starvable chain (cider starves as apples deplete), exercising
	# both the population timers and the production starvation path.
	var a := _grid_island()
	var sim_a := _sim_with(a)
	_place(a, "kontor", Vector2i(1, 1))
	_place(a, "apple_orchard", Vector2i(4, 4))
	_place(a, "cider_maker", Vector2i(7, 7))
	var hut_a := _place(a, "pioneer_hut", Vector2i(4, 8))
	hut_a.residents = 3
	a.stockpile = {"fish": 1e6, "water": 1e6}
	sim_a.advance(1000.0)

	var b := _grid_island()
	var sim_b := _sim_with(b)
	_place(b, "kontor", Vector2i(1, 1))
	_place(b, "apple_orchard", Vector2i(4, 4))
	_place(b, "cider_maker", Vector2i(7, 7))
	var hut_b := _place(b, "pioneer_hut", Vector2i(4, 8))
	hut_b.residents = 3
	b.stockpile = {"fish": 1e6, "water": 1e6}
	sim_b.advance(317.3)
	sim_b.advance(412.9)
	sim_b.advance(269.8)

	_check(is_equal_approx(a.qty("cider"), b.qty("cider")),
		"split==single for cider (%.3f vs %.3f)" % [a.qty("cider"), b.qty("cider")])
	_check(is_equal_approx(a.qty("apple"), b.qty("apple")),
		"split==single for apples (%.3f vs %.3f)" % [a.qty("apple"), b.qty("apple")])
	_check(hut_a.residents == hut_b.residents,
		"split==single for residents (%d vs %d)" % [hut_a.residents, hut_b.residents])

func _test_buildcost_producible() -> void:
	# Every build-cost good and every recipe input must be producible somewhere in the
	# catalog (currencies exempt) — catches "consumer transcribed, extractor omitted"
	# soft-locks like the clay→brick→Merchant's Mansion chain.
	var produced := {}
	for id in Database.buildings:
		var b: BuildingDef = Database.buildings[id]
		if b.recipe != null and b.recipe.output != "":
			produced[b.recipe.output] = true
	var missing: Array = []
	for id in Database.buildings:
		var b: BuildingDef = Database.buildings[id]
		var wanted: Array = b.cost.keys()
		if b.recipe != null:
			wanted += b.recipe.inputs.keys()
		for g in wanted:
			var gd := Database.good(g)
			if gd != null and gd.category == "currency":
				continue
			if not produced.has(g) and not missing.has(g):
				missing.append(g)
	_check(missing.is_empty(),
		"every build-cost/recipe input is producible (missing: %s)" % str(missing))

func _test_save_preserves_timers() -> void:
	var isl := _grid_island()
	var sim := _sim_with(isl)
	_place(isl, "kontor", Vector2i(1, 1))
	var hut := _place(isl, "pioneer_hut", Vector2i(4, 4))
	hut.residents = 4
	hut.unmet_time = 7.5
	hut.satisfied_time = 3.25
	var sim2 := WorldSim.new()
	sim2.from_dict(sim.to_dict())
	var r := sim2.active_island()
	var found := false
	for pb in r.buildings:
		if pb.building_id == "pioneer_hut":
			found = is_equal_approx(pb.unmet_time, 7.5) and is_equal_approx(pb.satisfied_time, 3.25)
	_check(found, "save round-trip preserves hysteresis timers")

func _test_mapgen_deterministic() -> void:
	var m1 := MapGen.generate(32, 32, 4242)
	var m2 := MapGen.generate(32, 32, 4242)
	var same := m1.terrain == m2.terrain
	_check(same, "MapGen is deterministic for a fixed seed")
	# Sanity: the island has buildable grass, a coast, and a river.
	var counts := {}
	for t in m1.terrain:
		counts[t] = int(counts.get(t, 0)) + 1
	_check(int(counts.get(T.GRASS, 0)) > 100, "generated island has ample grass")
	_check(int(counts.get(T.WATER, 0)) > 50, "generated island has surrounding ocean")
	_check(int(counts.get(T.RIVER, 0)) > 0, "generated island has a river")

func _test_new_game_places_kontor() -> void:
	# Regression: the coastal Kontor must place on a *generated* island (beach ring),
	# otherwise nothing is ever connected. Check several seeds.
	var placed_all := true
	for seed_value in [1337, 99, 7, 20240601]:
		var sim := WorldSim.new()
		sim.new_game(seed_value)
		var isl := sim.active_island()
		var has_kontor := false
		for pb in isl.buildings:
			if pb.building_id == "kontor":
				has_kontor = true
		if not has_kontor:
			placed_all = false
	_check(placed_all, "new_game places a coastal Kontor on generated islands (all seeds)")
	# And a building placed next to that Kontor is connected.
	var sim2 := WorldSim.new()
	sim2.new_game(1337)
	var isl2 := sim2.active_island()
	var kontor: PlacedBuilding = null
	for pb in isl2.buildings:
		if pb.building_id == "kontor":
			kontor = pb
	var connected_ok := false
	if kontor != null:
		# Find a grass tile near the Kontor for a well, place it, check connectivity.
		var well := Database.building("well")
		for radius in range(1, 10):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var o: Vector2i = kontor.origin + Vector2i(dx, dy)
					if isl2.can_place(well, o).ok:
						var pb := isl2.place(well, o)
						sim2._recompute_connectivity(isl2)
						connected_ok = pb.connected
						break
				if connected_ok:
					break
			if connected_ok:
				break
	_check(connected_ok, "a building placed near the Kontor is connected")
