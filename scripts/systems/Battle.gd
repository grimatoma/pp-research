class_name Battle
extends RefCounted
## Deterministic auto-battle resolver (PP2 milestone M8). Offensive-only: a player army
## attacks a static Orc camp. Resolution model (from the research doc):
##
## - Rounds until one side is wiped. Each round has 3 phases: First → Normal → Last.
##   A unit acts in a phase by its strike ability: First→1, Last→3, Double→1&3,
##   Triple→all, none→Normal only. A unit killed in an earlier phase doesn't act later.
## - All actors in a phase strike SIMULTANEOUSLY (damage is computed from the phase-start
##   state, then applied together). Overkill is wasted (Trample/Splash would carry — not
##   yet modelled). Non-Flank attackers spread across enemy targets; Flank picks the
##   lowest-max-HP enemy.
## - Ranged units can only be TARGETED once all melee on their side are dead.
## - Crit doubles damage; crit chance = 0.8 player / 0.6 Orc / 0.5 boss (seeded RNG, so
##   the whole battle is reproducible).
## - WIN IF ALL ENEMIES DIE — even if all your units also die.
##
## Armies are Dictionary[unit_id -> count]. Exotic boss abilities (Splash, Armageddon,
## Lightning Bolt, Summon, Revive, …) are recognised in the data but not yet resolved.

const PHASE_FIRST := 0
const PHASE_NORMAL := 1
const PHASE_LAST := 2
const PHASES := [PHASE_FIRST, PHASE_NORMAL, PHASE_LAST]
const MAX_ROUNDS := 4000  ## safety bound (every round deals damage, so this is a backstop)

## Resolve a battle. Returns:
## { winner:"attacker"|"defender", rounds:int, attacker_survivors:{id:count},
##   defender_survivors:{id:count}, duration_seconds:float }
static func resolve(attacker_army: Dictionary, defender_army: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var atk := _expand(attacker_army, true)
	var dfn := _expand(defender_army, false)
	var rounds := 0
	while _alive_count(atk) > 0 and _alive_count(dfn) > 0 and rounds < MAX_ROUNDS:
		rounds += 1
		for phase in PHASES:
			_resolve_phase(atk, dfn, phase, rng)
			if _alive_count(atk) == 0 or _alive_count(dfn) == 0:
				break
	var dfn_left := _alive_count(dfn)
	return {
		"winner": "attacker" if dfn_left == 0 else "defender",
		"rounds": rounds,
		"attacker_survivors": _count(atk),
		"defender_survivors": _count(dfn),
		"duration_seconds": duration_seconds(attacker_army, defender_army),
	}

## Battle wall-clock: (Σ tier×count over BOTH armies) × lerp(18,28, Σ/1000) s, cap 12h.
static func duration_seconds(attacker_army: Dictionary, defender_army: Dictionary) -> float:
	var s := 0
	for army in [attacker_army, defender_army]:
		for uid in army:
			var def := Database.unit(uid)
			if def != null:
				s += def.tier * int(army[uid])
	var per_unit := lerpf(18.0, 28.0, clampf(s / 1000.0, 0.0, 1.0))
	return minf(float(s) * per_unit, 12.0 * 3600.0)

# ── internals ────────────────────────────────────────────────────────────────

static func _expand(army: Dictionary, player_side: bool) -> Array:
	var out: Array = []
	for uid in army:
		var def := Database.unit(uid)
		if def == null:
			continue
		var crit := 0.5 if def.is_boss else (0.8 if player_side else 0.6)
		for _i in int(army[uid]):
			out.append({"id": uid, "def": def, "hp": def.hp, "crit": crit, "incoming": 0})
	return out

static func _alive_count(army: Array) -> int:
	var n := 0
	for u in army:
		if u.hp > 0:
			n += 1
	return n

static func _alive(army: Array) -> Array:
	return army.filter(func(u): return u.hp > 0)

static func _acts_in_phase(def: UnitDef, phase: int) -> bool:
	if def.has_ability("Triple"):
		return true
	if def.has_ability("Double"):
		return phase == PHASE_FIRST or phase == PHASE_LAST
	if def.has_ability("First"):
		return phase == PHASE_FIRST
	if def.has_ability("Last"):
		return phase == PHASE_LAST
	return phase == PHASE_NORMAL

static func _resolve_phase(atk: Array, dfn: Array, phase: int, rng: RandomNumberGenerator) -> void:
	for u in atk:
		u.incoming = 0
	for u in dfn:
		u.incoming = 0
	# Targeting uses the phase-start alive snapshot (simultaneity).
	var dfn_alive := _alive(dfn)
	var atk_alive := _alive(atk)
	_strike(atk, dfn_alive, phase, rng)
	_strike(dfn, atk_alive, phase, rng)
	for u in atk:
		if u.incoming > 0:
			u.hp -= u.incoming
	for u in dfn:
		if u.incoming > 0:
			u.hp -= u.incoming

static func _strike(attackers: Array, enemy_alive: Array, phase: int, rng: RandomNumberGenerator) -> void:
	if enemy_alive.is_empty():
		return
	var melee := enemy_alive.filter(func(u): return not u.def.is_ranged())
	var pool: Array = melee if not melee.is_empty() else enemy_alive
	var idx := 0
	for a in attackers:
		if a.hp <= 0 or not _acts_in_phase(a.def, phase):
			continue
		var target: Dictionary
		if a.def.has_ability("Flank"):
			target = _lowest_max_hp(pool)
		else:
			target = pool[idx % pool.size()]
		var dmg: int = a.def.atk
		if rng.randf() < a.crit:
			dmg *= 2
		target.incoming += dmg
		idx += 1

static func _lowest_max_hp(pool: Array) -> Dictionary:
	var best: Dictionary = pool[0]
	for u in pool:
		if u.def.hp < best.def.hp:
			best = u
	return best

static func _count(army: Array) -> Dictionary:
	var out: Dictionary = {}
	for u in army:
		if u.hp > 0:
			out[u.id] = int(out.get(u.id, 0)) + 1
	return out
