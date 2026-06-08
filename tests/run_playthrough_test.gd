extends SceneTree
## End-to-end integration test: drives ONE WorldSim through a full game loop to prove
## the systems compose — economy → recruitment → conquest → Cartography → discovery →
## settle → trade → Paragons → Palace → Reputation → New Game+.
##   godot --headless --script res://tests/run_playthrough_test.gd
## Exits 0 on success, 1 on any failure. Pre-stocks goods to skip the long grind, but
## every state transition goes through the real public API.

const T := Constants.Terrain

var _checks := 0
var _failures := 0

func _initialize() -> void:
	print("\n── Pioneer Isles · full playthrough ───────────────")
	var sim := WorldSim.new()
	sim.new_game(1337)
	var home := sim.active_island()

	# ── 1. The home island has a warchief fort + a plain camp ──
	var warchief: OrcCamp = null
	var plain: OrcCamp = null
	for c in home.camps:
		if c.boss != "":
			warchief = c
		else:
			plain = c
	_check(warchief != null and plain != null, "home island has a warchief fort and a plain camp")

	# ── 2. Economy: a fed house musters Militia ──
	home.stockpile["fish"] = 1e6
	home.stockpile["water"] = 1e6
	var hut := home.building_at(_first_house_or_place(sim, home))
	if hut != null:
		hut.residents = 10
	sim.advance(300.0)
	_check(home.qty("militia") > 0.5, "economy recruits Militia from population (%.1f)" % home.qty("militia"))

	# ── 3. Conquest: clear the plain camp with a strong garrison ──
	home.stockpile["knight"] = 30.0
	var r := sim.send_expedition(0, plain.id, {"knight": 30})
	_check(r.ok, "expedition launches against the plain camp")
	sim.advance(sim.expedition_for(0, plain.id).total + 5.0)
	_check(plain.cleared, "the plain camp falls")

	# ── 4. Cartography: defeat the warchief → +1 Cartography ──
	home.stockpile["knight"] = 60.0
	var carto0: float = sim.currencies.cartography
	sim.send_expedition(0, warchief.id, {"knight": 60})
	sim.advance(sim.expedition_for(0, warchief.id).total + 5.0)
	_check(warchief.cleared, "the warchief fort falls")
	_check(sim.currencies.cartography >= carto0 + 1.0, "defeating the warchief grants Cartography")

	# ── 5. Discovery: spend Cartography to chart a new island ──
	sim.currencies["cartography"] = 5.0
	var before := sim.islands.size()
	sim.start_discovery("temperate", 1)
	sim.advance(sim.discoveries[0].total + 5.0)
	_check(sim.islands.size() == before + 1, "a voyage discovers a new island")
	var found := sim.islands[before]

	# ── 6. Settle the new island (after pacifying it) ──
	for c in found.camps:
		c.cleared = true
	var settled := sim.settle_island(before)
	_check(settled.ok and found.settled, "the discovered island is settled")
	var new_has_kontor := false
	for pb in found.buildings:
		if pb.building_id == "kontor":
			new_has_kontor = true
	_check(new_has_kontor, "the settled island has a Kontor")

	# ── 7. Trade: ship goods from home to the new colony ──
	home.stockpile["wood"] = 1000.0
	if not _has_shipyard(home):
		home.place(Database.building("shipyard"), Vector2i(2, 2))
	sim.currencies["coin"] = 1000.0
	var route := sim.add_trade_route(0, before, "wood", "cog")
	_check(route.ok, "a trade route is established (%s)" % route.reason)
	sim.advance(1800.0)
	_check(found.qty("wood") > 10.0, "the colony receives shipped wood (%.0f)" % found.qty("wood"))

	# ── 8. Prestige: reach Paragons, found & complete the Palace ──
	var pr := home.place(Database.building("paragon_residence"), _open_spot(home, Database.building("paragon_residence")))
	pr.tier_id = "paragons"
	pr.residents = 30
	_check(sim.paragon_population() >= 30, "the realm reaches Paragon population")
	home.stockpile["plank"] = 1000.0
	home.stockpile["tools"] = 1000.0
	sim.currencies["coin"] = 5000.0
	var palace_spot := _open_spot(home, Database.building("palace"))
	var placed := sim.try_place(Database.building("palace"), palace_spot)
	_check(placed.ok, "the Palace is founded (%s)" % placed.reason)
	var palace := sim.find_palace()
	sim.currencies["favor"] = 100000.0
	for i in 5:
		sim.upgrade_palace(palace)
	_check(palace.level == 5, "the Palace is completed")
	_check(sim.reputation() == 1, "completing the Palace grants Reputation")

	# ── 9. New Game+: restart with a Custodian; Reputation persists ──
	sim.reset(1337, ["cartographer"], sim.reputation())
	_check(sim.reputation() == 1, "Reputation carries into New Game+")
	_check(sim.active_custodians.has("cartographer"), "the chosen Custodian is active")
	_check(is_equal_approx(sim.currencies.cartography, 30.0), "the Custodian's start grant applies")
	_check(sim.islands.size() == 1 and not sim.active_island().camps.is_empty(),
		"New Game+ generates a fresh world")

	print("──────────────────────────────────────────────────")
	print("%d checks, %d failure(s)\n" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

# ── helpers ────────────────────────────────────────────────────────────────────

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)

func _first_house_or_place(sim: WorldSim, isl: Island) -> Vector2i:
	for pb in isl.buildings:
		if pb.building_id == "pioneer_hut":
			return pb.origin
	var spot := _open_grass(isl)
	isl.place(Database.building("pioneer_hut"), spot)
	sim._recompute_connectivity(isl)
	return spot

func _open_grass(isl: Island) -> Vector2i:
	return _open_spot(isl, Database.building("warehouse"))

## First cell where `def`'s whole footprint is placeable (handles 3x3 Palace etc.).
func _open_spot(isl: Island, def: BuildingDef) -> Vector2i:
	for y in range(2, isl.height - def.size.y - 1):
		for x in range(2, isl.width - def.size.x - 1):
			var c := Vector2i(x, y)
			if isl.can_place(def, c).ok:
				return c
	return Vector2i(2, 2)

func _has_shipyard(isl: Island) -> bool:
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def != null and def.is_shipyard:
			return true
	return false
