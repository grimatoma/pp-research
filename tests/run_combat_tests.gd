extends SceneTree
## Headless tests for the deterministic auto-battle resolver (Battle.gd / UnitDef).
##   godot --headless --script res://tests/run_combat_tests.gd
## Exits 0 on success, 1 on any failure.

# preload forces the Battle script to compile so its static methods bind in the
# headless --script harness (a global-class static call can't bind to an
# as-yet-uncompiled script here; in a normal game run B.resolve(...) is fine).
const B := preload("res://scripts/systems/Battle.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	print("\n── Pioneer Isles · combat tests ───────────────────")
	_test_unit_catalog()
	_test_determinism()
	_test_stronger_army_wins()
	_test_win_on_mutual_death()
	_test_ranged_protected_by_melee()
	_test_duration_formula()
	_test_trample_carries_overkill()
	_test_bulletproof_immune_to_ranged()
	_test_determinism_with_boss_abilities()
	print("──────────────────────────────────────────────────")
	print("%d checks, %d failure(s)\n" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", msg)
	else:
		_failures += 1
		print("  FAIL  ", msg)
		push_error("FAIL: " + msg)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _test_unit_catalog() -> void:
	_check(Database.unit("militia") != null, "unit catalog has militia")
	_check(Database.unit("crossbowman").atk == 90, "crossbowman atk == 90")
	_check(Database.unit("bula").is_boss, "Bula is flagged a boss")
	_check(Database.unit("cannoneer").has_ability("Last"), "cannoneer has Last strike")

func _test_determinism() -> void:
	var a := {"militia": 8, "archer": 4}
	var d := {"orc_grunt": 6, "orc_archer": 3}
	var o1 := B.resolve(a.duplicate(), d.duplicate(), _rng(123))
	var o2 := B.resolve(a.duplicate(), d.duplicate(), _rng(123))
	_check(o1.winner == o2.winner, "same seed → same winner")
	_check(o1.rounds == o2.rounds, "same seed → same round count (%d)" % o1.rounds)
	_check(o1.attacker_survivors == o2.attacker_survivors, "same seed → same attacker survivors")
	_check(o1.defender_survivors == o2.defender_survivors, "same seed → same defender survivors")

func _test_stronger_army_wins() -> void:
	var o := B.resolve({"knight": 20}, {"orc_grunt": 5}, _rng(7))
	_check(o.winner == "attacker", "20 knights beat 5 orc grunts")
	_check(int(o.attacker_survivors.get("knight", 0)) > 0, "knights survive the rout")

func _test_win_on_mutual_death() -> void:
	# Two lone crossbowmen (atk 90 ≥ hp 15) both die in the same Normal phase.
	# Win-if-all-enemies-die means the ATTACKER wins even when wiped too.
	var o := B.resolve({"crossbowman": 1}, {"crossbowman": 1}, _rng(1))
	_check(o.winner == "attacker", "mutual death → attacker wins (all enemies dead)")
	_check(o.attacker_survivors.is_empty(), "attacker also wiped in the mutual kill")
	_check(o.defender_survivors.is_empty(), "defender wiped")

func _test_ranged_protected_by_melee() -> void:
	# A lone crossbowman must target the melee Grunt before the ranged Archer, so the
	# Archer is the survivor when the crossbowman trades its life.
	var o := B.resolve({"crossbowman": 1}, {"orc_grunt": 1, "orc_archer": 1}, _rng(1))
	_check(o.winner == "defender", "crossbowman trades down to the camp")
	_check(o.defender_survivors == {"orc_archer": 1},
		"ranged Archer survives behind the melee Grunt (melee targeted first)")

func _test_duration_formula() -> void:
	# S = Σ tier×count = (1×10) + (1×5) = 15; per = lerp(18,28,0.015) = 18.15.
	var dur := B.duration_seconds({"militia": 10}, {"orc_grunt": 5})
	_check(is_equal_approx(dur, 15.0 * 18.15), "duration formula: 15×18.15 = %.2f s" % dur)
	# Capped at 12h for huge armies.
	var capped := B.duration_seconds({"knight": 100000}, {"bula": 100})
	_check(capped <= 12.0 * 3600.0 + 0.001, "duration caps at 12h")

func _test_trample_carries_overkill() -> void:
	# A lone Cannoneer (Trample, 80 atk, Last) splashes its overkill across the 3
	# orclings (10 HP each), clearing them in one strike → a single round.
	var o := B.resolve({"cannoneer": 1}, {"orcling": 3}, _rng(2))
	_check(o.winner == "attacker", "Trample Cannoneer wins")
	_check(o.rounds == 1, "Trample clears all three orclings in one strike (1 round)")

func _test_bulletproof_immune_to_ranged() -> void:
	# Saukron is Bulletproof — a ranged army deals zero and loses, but a melee army
	# of comparable strength breaks through.
	var ranged := B.resolve({"crossbowman": 250}, {"saukron": 1}, _rng(3))
	_check(ranged.winner == "defender", "Bulletproof Saukron is immune to a ranged army")
	var melee := B.resolve({"knight": 500}, {"saukron": 1}, _rng(3))
	_check(melee.winner == "attacker", "a strong melee army defeats Bulletproof Saukron")

func _test_determinism_with_boss_abilities() -> void:
	# A boss with Splash/Last (Bula) must still resolve identically for a fixed seed.
	var a := {"knight": 40, "archer": 20}
	var d := {"bula": 1, "orc_grunt": 8}
	var o1 := B.resolve(a.duplicate(), d.duplicate(), _rng(99))
	var o2 := B.resolve(a.duplicate(), d.duplicate(), _rng(99))
	_check(o1.winner == o2.winner and o1.rounds == o2.rounds,
		"boss-ability battles stay deterministic for a fixed seed")
