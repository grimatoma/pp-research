class_name WorldSim
extends RefCounted
## The live world (LAYER 2 in the spec): islands, placed buildings, the shared
## stockpiles, the 6 global currencies, population, and the game clock. Owns the
## deterministic per-tick resolution and idle/offline catch-up.
##
## It is a plain RefCounted object (not an autoload) so the whole sim is reachable
## headless in `--script` test runs. The `Game` autoload owns one instance and ticks
## it; UI connects to these signals. Matches the spec's "one WorldState object".
##
## PER-TICK RESOLUTION ORDER (fixed, golden-asserted):
##   1. connectivity → 2. production → 3. consumption/needs →
##   4. population dynamics → 5. economy payout.

signal economy_ticked(delta_seconds: float)
signal building_placed(building_id: String, cell: Vector2i)
signal building_removed(cell: Vector2i)
signal population_changed(tier_id: String, residents: int, total: int)
signal needs_unmet(tier_id: String, missing_good: String)
signal tier_unlocked(tier_id: String)
signal notify(text: String, level: String)

const MAX_STEP := 2.0           ## seconds per integration sub-tick
const GROW_INTERVAL := 6.0      ## seconds of full basics before +1 resident
const EMIGRATE_INTERVAL := 10.0 ## seconds of unmet basics before −1 resident
const FAVOR_PER_PARAGON_PER_MIN := 0.2  ## CHOSEN DEFAULT (Paragon Favor output)

var islands: Array[Island] = []
var active_index: int = 0
var currencies: Dictionary = {"coin": 0.0, "cartography": 0.0, "favor": 0.0, "reputation": 0.0}
var unlocked_tiers: Array = ["pioneers"]
var elapsed: float = 0.0        ## total simulated game seconds
var _last_emit: float = 0.0     ## throttle the economy_ticked UI signal

# ── lifecycle ────────────────────────────────────────────────────────────────

func active_island() -> Island:
	if islands.is_empty():
		return null
	return islands[active_index]

## Fresh run: one generated temperate island with a coastal Kontor and a small
## starting stockpile so the player can build immediately.
func new_game(seed_value := 1337) -> void:
	islands.clear()
	currencies = {"coin": 200.0, "cartography": 0.0, "favor": 0.0, "reputation": 0.0}
	unlocked_tiers = ["pioneers"]
	elapsed = 0.0
	var isl := MapGen.generate(32, 32, seed_value)
	isl.stockpile = {"wood": 80.0, "plank": 30.0}
	islands.append(isl)
	active_index = 0
	_place_starting_kontor(isl)
	_recompute_connectivity(isl)

func _place_starting_kontor(isl: Island) -> void:
	var def := Database.building("kontor")
	var center := Vector2i(isl.width / 2, isl.height / 2)
	for radius in range(0, max(isl.width, isl.height)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var origin := center + Vector2i(dx, dy)
				if isl.can_place(def, origin).ok:
					isl.place(def, origin)
					return

# ── the tick ──────────────────────────────────────────────────────────────────

## Advance the simulation by `dt` real seconds, split into stable sub-ticks.
func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	var remaining := dt
	while remaining > 0.0001:
		var step: float = min(remaining, MAX_STEP)
		_tick(step)
		remaining -= step
		elapsed += step
	_last_emit += dt
	if _last_emit >= 0.2:
		_last_emit = 0.0
		economy_ticked.emit(dt)

func _tick(dt: float) -> void:
	for isl in islands:
		_recompute_connectivity(isl)
		_phase_production(isl, dt)
		_phase_population(isl, dt)

# Phase 1: who is within range of a storage building (no roads — pure proximity).
func _recompute_connectivity(isl: Island) -> void:
	var storages: Array = []
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def != null and def.is_storage:
			storages.append({"center": _center(def, pb.origin), "range": def.storage_range})
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def == null:
			continue
		if def.is_storage:
			pb.connected = true
			continue
		var c := _center(def, pb.origin)
		pb.connected = false
		for s in storages:
			var d: Vector2i = c - s.center
			if max(abs(d.x), abs(d.y)) <= int(s.range):
				pb.connected = true
				break

func _center(def: BuildingDef, origin: Vector2i) -> Vector2i:
	return origin + Vector2i(def.size.x / 2, def.size.y / 2)

# Phase 2: production. Each whole iteration consumes inputs from island storage and
# adds the output. Starved buildings hold at most one iteration of banked progress.
func _phase_production(isl: Island, dt: float) -> void:
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def == null or def.recipe == null:
			continue
		pb.active = false
		if not pb.connected:
			continue
		var r := def.recipe
		pb.progress += dt
		if pb.progress < r.iteration_time:
			continue
		var iters := int(pb.progress / r.iteration_time)
		for good_id in r.inputs:
			var amt: float = r.inputs[good_id]
			if amt > 0.0:
				iters = min(iters, int(isl.qty(good_id) / amt))
		iters = max(iters, 0)
		if iters > 0:
			for good_id in r.inputs:
				isl.take(good_id, float(r.inputs[good_id]) * iters)
			if r.output != "":
				isl.add(r.output, r.output_qty * iters)
			pb.progress -= iters * r.iteration_time
			pb.active = true
		else:
			pb.progress = min(pb.progress, r.iteration_time)

# Phases 3-5: per house, consume needs, move residents, pay out.
func _phase_population(isl: Island, dt: float) -> void:
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def == null or not def.is_house:
			continue
		var tier := Database.tier(pb.tier_id)
		if tier == null:
			continue
		if not pb.connected:
			pb.active = false
			continue
		var basics := _consume_needs(isl, tier.basic_needs, pb.residents, dt)
		var lux := _consume_needs(isl, tier.luxury_needs, pb.residents, dt)
		pb.active = pb.residents > 0
		# Phase 4: population dynamics — basics drive occupancy with hysteresis.
		if basics.all_met:
			pb.unmet_time = 0.0
			pb.satisfied_time += dt
			if pb.residents < tier.max_residents and pb.satisfied_time >= GROW_INTERVAL:
				pb.satisfied_time = 0.0
				pb.residents += 1
				population_changed.emit(pb.tier_id, pb.residents, total_population())
		else:
			pb.satisfied_time = 0.0
			pb.unmet_time += dt
			if pb.unmet_time >= EMIGRATE_INTERVAL and pb.residents > 0:
				pb.unmet_time = 0.0
				pb.residents -= 1
				needs_unmet.emit(pb.tier_id, _first_missing(isl, tier))
				population_changed.emit(pb.tier_id, pb.residents, total_population())
		# Phase 5: economy payout — scales with luxury satisfaction fraction.
		if pb.residents > 0:
			if tier.coin_per_resident_per_min > 0.0:
				currencies["coin"] += tier.coin_per_resident_per_min / 60.0 \
					* pb.residents * lux.ratio * dt
			else:
				currencies["favor"] += FAVOR_PER_PARAGON_PER_MIN / 60.0 \
					* pb.residents * lux.ratio * dt

## Consume each need good from the island stockpile at residents/denominator per sec.
## Returns {"ratio": min fraction met across goods, "all_met": every good fully met}.
func _consume_needs(isl: Island, needs: Dictionary, residents: int, dt: float) -> Dictionary:
	if residents <= 0 or needs.is_empty():
		return {"ratio": 1.0, "all_met": true}
	var min_ratio := 1.0
	var all_met := true
	for good_id in needs:
		var denom: float = needs[good_id]
		if denom <= 0.0:
			continue
		var want: float = residents * (1.0 / denom) * dt
		if want <= 0.0:
			continue
		var got := isl.take(good_id, want)
		var ratio: float = got / want
		min_ratio = min(min_ratio, ratio)
		if ratio < 0.999:
			all_met = false
	return {"ratio": min_ratio, "all_met": all_met}

func _first_missing(isl: Island, tier: PopTierDef) -> String:
	for good_id in tier.basic_needs:
		if isl.qty(good_id) <= 0.0:
			return good_id
	return ""

# ── house upgrade (the cascade ascension) ──────────────────────────────────────

## Upgrade-eligible when at max residents AND every basic + luxury need has a
## comfortable buffer, and a higher tier exists. Player-triggered (PP2-faithful).
func can_upgrade(pb: PlacedBuilding) -> bool:
	var def := Database.building(pb.building_id)
	if def == null or not def.is_house:
		return false
	var tier := Database.tier(pb.tier_id)
	if tier == null or Database.next_tier_id(pb.tier_id) == "":
		return false
	if pb.residents < tier.max_residents:
		return false
	var isl := active_island()
	return _peek_needs(isl, tier.basic_needs, pb.residents) \
		and _peek_needs(isl, tier.luxury_needs, pb.residents)

func _peek_needs(isl: Island, needs: Dictionary, residents: int) -> bool:
	for good_id in needs:
		var denom: float = needs[good_id]
		if denom <= 0.0:
			continue
		# "supplied" = at least a minute's buffer of this good is on hand.
		if isl.qty(good_id) < residents * (1.0 / denom) * 60.0:
			return false
	return true

## Upgrade a house in place to the next tier; unlocks that tier's buildings.
func upgrade_house(pb: PlacedBuilding) -> bool:
	if not can_upgrade(pb):
		return false
	var next_id := Database.next_tier_id(pb.tier_id)
	var next_tier := Database.tier(next_id)
	var next_house := ""
	for bid in Database.buildings:
		var b: BuildingDef = Database.buildings[bid]
		if b.is_house and b.house_tier == next_id:
			next_house = bid
			break
	if next_house == "":
		return false
	pb.building_id = next_house
	pb.tier_id = next_id
	pb.residents = min(pb.residents, next_tier.max_residents)
	pb.satisfied_time = 0.0
	if not unlocked_tiers.has(next_id):
		unlocked_tiers.append(next_id)
		tier_unlocked.emit(next_id)
	active_island()._reindex()
	population_changed.emit(next_id, pb.residents, total_population())
	notify.emit("A house ascended to %s!" % next_tier.display_name, "good")
	return true

# ── placement API (used by the build UI) ───────────────────────────────────────

func can_afford(def: BuildingDef) -> bool:
	var isl := active_island()
	for good_id in def.cost:
		var need: float = def.cost[good_id]
		var have: float = currencies[good_id] if currencies.has(good_id) else isl.qty(good_id)
		if have < need:
			return false
	return true

func try_place(def: BuildingDef, origin: Vector2i) -> Dictionary:
	var isl := active_island()
	var check := isl.can_place(def, origin)
	if not check.ok:
		return check
	if not can_afford(def):
		return {"ok": false, "reason": "Not enough materials"}
	for good_id in def.cost:
		var amt: float = def.cost[good_id]
		if currencies.has(good_id):
			currencies[good_id] -= amt
		else:
			isl.take(good_id, amt)
	isl.place(def, origin)
	_recompute_connectivity(isl)
	building_placed.emit(def.id, origin)
	return {"ok": true, "reason": ""}

func demolish(cell: Vector2i) -> bool:
	var isl := active_island()
	if isl.remove_at(cell):
		_recompute_connectivity(isl)
		building_removed.emit(cell)
		return true
	return false

# ── aggregates for UI ──────────────────────────────────────────────────────────

func total_population() -> int:
	var n := 0
	for isl in islands:
		for pb in isl.buildings:
			n += pb.residents
	return n

func population_by_tier() -> Dictionary:
	var out: Dictionary = {}
	for isl in islands:
		for pb in isl.buildings:
			if pb.residents > 0 and pb.tier_id != "":
				out[pb.tier_id] = int(out.get(pb.tier_id, 0)) + pb.residents
	return out

func coin() -> float:
	return currencies.get("coin", 0.0)

# ── persistence (offline catch-up happens here) ─────────────────────────────────

func to_dict() -> Dictionary:
	var isl_list: Array = []
	for isl in islands:
		isl_list.append(isl.to_dict())
	return {
		"islands": isl_list,
		"active_index": active_index,
		"currencies": currencies.duplicate(),
		"unlocked_tiers": unlocked_tiers.duplicate(),
		"elapsed": elapsed,
		"saved_at_unix": Time.get_unix_time_from_system(),
	}

func from_dict(d: Dictionary) -> void:
	islands.clear()
	for isl_d in d.get("islands", []):
		islands.append(Island.from_dict(isl_d))
	active_index = int(d.get("active_index", 0))
	currencies = {"coin": 0.0, "cartography": 0.0, "favor": 0.0, "reputation": 0.0}
	var cur: Dictionary = d.get("currencies", {})
	for k in cur:
		currencies[k] = float(cur[k])
	unlocked_tiers = d.get("unlocked_tiers", ["pioneers"])
	elapsed = float(d.get("elapsed", 0.0))
	for isl in islands:
		_recompute_connectivity(isl)
	# Idle/offline catch-up: simulate bounded wall-clock elapsed since the save.
	var saved_at: float = float(d.get("saved_at_unix", 0.0))
	if saved_at > 0.0:
		var away: float = clampf(Time.get_unix_time_from_system() - saved_at,
			0.0, Constants.MAX_OFFLINE_SECONDS)
		if away > 1.0:
			advance(away)
			notify.emit("Welcome back — simulated %d min away." % int(away / 60.0), "info")
