class_name Database
extends RefCounted
## Static catalog: goods, buildings, recipes, and population tiers — the const data
## layer (LAYER 1 in the spec). All-static so it is reachable headless (in
## `--script` test runs, before any scene tree / autoload exists), matching the
## puzzleDrag2 house style. Built lazily on first access.
##
## All gameplay numbers (per-resident consumption denominators, recipe iteration
## times, costs) are transcribed from the data-mined PP2 values in
## docs/pp2-spec-extract.json; invented numbers (service rates, per-resident coin
## output, footprints) are marked CHOSEN DEFAULT in docs/SPEC.html.

const T := Constants.Terrain

static var goods: Dictionary = {}        ## id -> GoodDef
static var buildings: Dictionary = {}    ## id -> BuildingDef
static var tiers: Dictionary = {}        ## id -> PopTierDef
static var tier_order: Array[String] = [] ## tier ids, lowest → highest
static var research_perks: Dictionary = {} ## id -> ResearchDef
static var research_order: Array[String] = [] ## perk ids, catalog order
static var units: Dictionary = {}        ## id -> UnitDef
static var ships: Dictionary = {}        ## id -> ShipDef
static var ship_order: Array[String] = [] ## ship ids, roster order
static var custodians: Dictionary = {}   ## id -> CustodianDef (prestige run-modifiers)
static var custodian_order: Array[String] = []
static var _built := false

## Build the catalog as soon as the class is loaded, so even direct reads of the
## static `goods`/`buildings`/`tiers` dictionaries (e.g. from UI) are populated.
static func _static_init() -> void:
	_ensure()

static func _ensure() -> void:
	if _built:
		return
	_built = true
	_build_goods()
	_build_tiers()
	_build_buildings()
	_build_research()
	_build_units()
	_build_ships()
	_build_custodians()
	_assert_cascade()
	_assert_need_goods_exist()

# ── accessors ────────────────────────────────────────────────────────────────

static func good(id: String) -> GoodDef:
	_ensure()
	return goods.get(id, null)

static func building(id: String) -> BuildingDef:
	_ensure()
	return buildings.get(id, null)

static func tier(id: String) -> PopTierDef:
	_ensure()
	return tiers.get(id, null)

static func all_tiers() -> Array:
	_ensure()
	return tier_order

static func good_name(id: String) -> String:
	_ensure()
	var g: GoodDef = goods.get(id, null)
	return g.display_name if g != null else id

static func next_tier_id(id: String) -> String:
	_ensure()
	var i := tier_order.find(id)
	if i >= 0 and i + 1 < tier_order.size():
		return tier_order[i + 1]
	return ""

static func research_perk(id: String) -> ResearchDef:
	_ensure()
	return research_perks.get(id, null)

static func all_research() -> Array:
	_ensure()
	return research_order

static func unit(id: String) -> UnitDef:
	_ensure()
	return units.get(id, null)

static func ship(id: String) -> ShipDef:
	_ensure()
	return ships.get(id, null)

static func all_ships() -> Array:
	_ensure()
	return ship_order

static func custodian(id: String) -> CustodianDef:
	_ensure()
	return custodians.get(id, null)

static func all_custodians() -> Array:
	_ensure()
	return custodian_order

## The warchief boss that guards an island of the given size (12→34, step 2).
static func warchief_for_size(size: int) -> String:
	_ensure()
	var roster := ["bula", "durz", "hork", "aguk", "kultan", "mazoga",
		"durgash", "zrall", "krashek", "selzok", "saukron", "nurzhel"]
	var idx: int = clampi((size - 12) / 2, 0, roster.size() - 1)
	return roster[idx]

## Favor earned by handing an island of `size` to the Paragons (spec formula, line 379):
## Max(0,(Size-26)*16) + 2^((Min(Size,26)-10)/2 - 1).
static func favor_for_size(size: int) -> float:
	var linear: float = maxf(0.0, float(size - 26) * 16.0)
	var expo: float = pow(2.0, float(mini(size, 26) - 10) / 2.0 - 1.0)
	return linear + expo

## Buildings placeable given the set of unlocked tier ids (always includes ungated).
static func unlocked_buildings(unlocked_tiers: Array) -> Array:
	_ensure()
	var out: Array = []
	for id in buildings:
		var b: BuildingDef = buildings[id]
		if b.tier_unlock == "" or unlocked_tiers.has(b.tier_unlock):
			out.append(b)
	return out

# ── goods ────────────────────────────────────────────────────────────────────

static func _g(id: String, name: String, category := "material", color := Color.WHITE) -> void:
	goods[id] = GoodDef.new(id, name, category, color)

static func _build_goods() -> void:
	# currencies (global, live in WorldSim — not per-island storage)
	_g("coin", "Coin", "currency", Color("f2c94c"))
	_g("cartography", "Cartography", "currency", Color("9b51e0"))
	_g("favor", "Favor", "currency", Color("eb5757"))
	_g("reputation", "Reputation", "currency", Color("2d9cdb"))
	# services (modelled as goods routed through the stockpile; CHOSEN-DEFAULT rates)
	_g("water", "Water", "service", Color("56ccf2"))
	_g("community", "Community", "service", Color("f2994a"))
	_g("education", "Education", "service", Color("bb6bd9"))
	_g("medical_care", "Medical Care", "service", Color("eb5757"))
	# raw & intermediate
	_g("wood", "Wood", "raw", Color("8d6242"))
	_g("plank", "Plank", "material", Color("c19a6b"))
	_g("apple", "Apple", "raw", Color("d64550"))
	_g("pig", "Pig", "raw", Color("e8a0a0"))
	_g("wheat", "Wheat", "raw", Color("e6c34d"))
	_g("flour", "Flour", "material", Color("efe7c8"))
	_g("yarn", "Yarn", "material", Color("d9c8a0"))
	_g("cattle", "Cattle", "raw", Color("a07850"))
	_g("hide", "Hide", "material", Color("b08858"))
	_g("tallow", "Tallow", "material", Color("efe0a8"))
	_g("potash", "Potash", "material", Color("b8b0a0"))
	_g("rock_salt", "Rock Salt", "raw", Color("e0d8d0"))
	_g("salt", "Salt", "material", Color("f4f0ec"))
	_g("coal", "Coal", "raw", Color("3a3a3a"))
	_g("hops", "Hops", "raw", Color("8fae5d"))
	_g("malt", "Malt", "material", Color("c9a24a"))
	_g("limestone", "Limestone", "raw", Color("cfc8b8"))
	_g("mortar", "Mortar", "material", Color("b0a890"))
	_g("clay", "Clay", "raw", Color("b5651d"))
	_g("brick", "Brick", "material", Color("b14a3a"))
	_g("iron_ore", "Iron Ore", "raw", Color("8a7a6a"))
	_g("iron_ingot", "Iron Ingot", "material", Color("9aa0a8"))
	_g("tools", "Tools", "material", Color("7a8088"))
	_g("marble", "Marble", "raw", Color("eae6df"))
	_g("copper_ore", "Copper Ore", "raw", Color("b87333"))
	_g("copper_ingot", "Copper Ingot", "material", Color("d98a4a"))
	_g("gold_ore", "Gold Ore", "raw", Color("d4af37"))
	_g("gold_ingot", "Gold Ingot", "material", Color("f2c94c"))
	_g("grape", "Grapes", "raw", Color("6b3fa0"))
	_g("paper", "Paper", "material", Color("f4f0e6"))
	# tropical raws (imported via trade routes from tropical isles)
	_g("sugar", "Sugar", "raw", Color("f0ead8"))
	_g("cacao", "Cacao", "raw", Color("6f4e37"))
	_g("tobacco", "Tobacco", "raw", Color("8a7b3a"))
	# population-need goods
	_g("fish", "Fish", "food", Color("6fb7c4"))
	_g("sausage", "Sausage", "food", Color("c4564a"))
	_g("cider", "Cider", "food", Color("e0a93a"))
	_g("bread", "Bread", "food", Color("d9a85a"))
	_g("soap", "Soap", "luxury", Color("e8e0f0"))
	_g("fabric", "Fabric", "luxury", Color("9a6fb0"))
	_g("beer", "Beer", "luxury", Color("d8a23a"))
	_g("leather", "Leather", "luxury", Color("8a5a30"))
	# higher-tier need goods (advanced / imported chains — catalog entries)
	_g("cauldron", "Cauldron", "luxury", Color("5a5a5a"))
	_g("coffee", "Coffee", "luxury", Color("6f4e37"))
	_g("jam", "Jam", "luxury", Color("c0392b"))
	_g("hat", "Hat", "luxury", Color("34495e"))
	_g("tobacco_pipe", "Tobacco Pipe", "luxury", Color("8d6e63"))
	_g("pastry", "Pastry", "luxury", Color("e6b35a"))
	_g("caviar", "Caviar", "luxury", Color("2c2c2c"))
	_g("gold_jewelry", "Gold Jewelry", "luxury", Color("f2c94c"))
	_g("perfume", "Perfume", "luxury", Color("e784c4"))
	# Paragon luxuries (top-tier; producers are future end-game content — these are
	# registered so the catalog/UI/asserts are consistent and Favor can pay out once
	# their chains exist).
	_g("shoe", "Shoe", "luxury", Color("8a5a30"))
	_g("glasses", "Glasses", "luxury", Color("b0c4de"))
	_g("book", "Book", "luxury", Color("6b4423"))
	_g("chocolate_candy", "Chocolate Candy", "luxury", Color("5b3a29"))
	_g("noble_garment", "Noble Garment", "luxury", Color("7d3c98"))
	_g("wine", "Wine", "luxury", Color("722f37"))
	# ── weapons (consumed by training buildings) ──────────────────────────────
	_g("bow", "Bow", "tool", Color("9a7b4f"))
	_g("copper_sword", "Copper Sword", "tool", Color("d98a4a"))
	_g("iron_sword", "Iron Sword", "tool", Color("c0c4cc"))
	_g("cannon", "Cannon", "tool", Color("4a4a4a"))
	# ── military units (stored as goods in the island garrison; no upkeep) ─────
	# Recruited from population (militia) or trained from militia + a weapon.
	_g("militia", "Militia", "unit", Color("c9a24a"))
	_g("archer", "Archer", "unit", Color("8fae5d"))
	_g("footsoldier", "Footsoldier", "unit", Color("a05a3a"))
	_g("crossbowman", "Crossbowman", "unit", Color("6f9bd1"))
	_g("knight", "Knight", "unit", Color("d0d4dc"))
	_g("cannoneer", "Cannoneer", "unit", Color("5a5a5a"))
	# Higher units kept in the catalog for battle/enemy use & future training.
	_g("longbow_archer", "Longbow Archer", "unit", Color("7fae6d"))
	_g("cavalry", "Cavalry", "unit", Color("b08858"))
	_g("cuirassier", "Cuirassier", "unit", Color("b0b4bc"))

# ── population tiers (the luxury cascade) ──────────────────────────────────────

static func _build_tiers() -> void:
	# Per-resident consumption is "1 unit / N seconds" — N transcribed verbatim from
	# the wiki (high confidence). Services use CHOSEN-DEFAULT denominators.
	var SERVICE_WATER := 1200.0
	var SERVICE_COMMUNITY := 2000.0
	var SERVICE_EDU := 2400.0
	var SERVICE_MED := 3000.0

	var pioneers := PopTierDef.new("pioneers", "Pioneers", 0)
	pioneers.max_residents = 10
	pioneers.basic_needs = {"fish": 3780.0, "water": SERVICE_WATER}
	pioneers.luxury_needs = {"sausage": 10800.0, "cider": 9450.0, "community": SERVICE_COMMUNITY}
	pioneers.coin_per_resident_per_min = 0.6  # CHOSEN DEFAULT (output rate unpublished)

	var colonists := PopTierDef.new("colonists", "Colonists", 1)
	colonists.max_residents = 15
	colonists.basic_needs = {"fish": 3780.0, "sausage": 10800.0, "cider": 9450.0,
		"water": SERVICE_WATER, "community": SERVICE_COMMUNITY}
	colonists.luxury_needs = {"soap": 12600.0, "fabric": 20160.0, "bread": 16800.0,
		"education": SERVICE_EDU}
	colonists.coin_per_resident_per_min = 1.2

	var townsmen := PopTierDef.new("townsmen", "Townsmen", 2)
	townsmen.max_residents = 20
	townsmen.basic_needs = {"soap": 12600.0, "fabric": 20160.0, "bread": 16800.0,
		"water": SERVICE_WATER, "community": SERVICE_COMMUNITY, "education": SERVICE_EDU}
	townsmen.luxury_needs = {"cauldron": 45400.0, "beer": 17900.0, "leather": 22100.0,
		"coffee": 20900.0, "jam": 13400.0, "medical_care": SERVICE_MED}
	townsmen.coin_per_resident_per_min = 2.4

	var merchants := PopTierDef.new("merchants", "Merchants", 3)
	merchants.max_residents = 25
	merchants.basic_needs = {"cauldron": 45400.0, "beer": 17900.0, "leather": 22100.0,
		"coffee": 20900.0, "jam": 13400.0,
		"water": SERVICE_WATER, "community": SERVICE_COMMUNITY, "education": SERVICE_EDU,
		"medical_care": SERVICE_MED}
	merchants.luxury_needs = {"hat": 8000.0, "tobacco_pipe": 9000.0, "pastry": 8000.0,
		"caviar": 36000.0, "gold_jewelry": 12400.0, "perfume": 12400.0}
	merchants.coin_per_resident_per_min = 4.8

	var paragons := PopTierDef.new("paragons", "Paragons", 4)
	paragons.max_residents = 30
	# Paragon basics == Merchant luxuries EXCEPT Hat (the one terminal good).
	paragons.basic_needs = {"tobacco_pipe": 9000.0, "pastry": 8000.0,
		"caviar": 36000.0, "gold_jewelry": 12400.0, "perfume": 12400.0,
		"community": SERVICE_COMMUNITY, "education": SERVICE_EDU, "medical_care": SERVICE_MED}
	paragons.luxury_needs = {"shoe": 6120.0, "glasses": 6120.0, "book": 17485.0,
		"chocolate_candy": 10200.0, "noble_garment": 17485.0, "wine": 8160.0}
	paragons.coin_per_resident_per_min = 0.0  # Paragons output Favor, not Coin

	for t in [pioneers, colonists, townsmen, merchants, paragons]:
		tiers[t.id] = t
		tier_order.append(t.id)

## Golden assertion of the luxury cascade: a tier's NON-SERVICE basic needs equal the
## previous tier's NON-SERVICE luxuries (same good AND rate) — except Hat (terminal).
static func _assert_cascade() -> void:
	const TERMINAL := ["hat"]
	for i in range(1, tier_order.size()):
		var prev: PopTierDef = tiers[tier_order[i - 1]]
		var cur: PopTierDef = tiers[tier_order[i]]
		for good_id in prev.luxury_needs:
			var gd: GoodDef = goods.get(good_id, null)
			if gd != null and gd.category == "service":
				continue
			if good_id in TERMINAL:
				continue
			var lux_rate: float = prev.luxury_needs[good_id]
			var basic_rate: float = cur.basic_needs.get(good_id, -1.0)
			assert(is_equal_approx(lux_rate, basic_rate),
				"Cascade broken: %s lux %s != %s basic" % [prev.id, good_id, cur.id])

## Every good referenced by ANY tier's needs must be a defined GoodDef — catches the
## "top tier's luxuries never validated by the cascade loop" class of omission.
static func _assert_need_goods_exist() -> void:
	for tid in tier_order:
		var t: PopTierDef = tiers[tid]
		for d in [t.basic_needs, t.luxury_needs]:
			for good_id in d:
				assert(goods.has(good_id),
					"Tier %s references undefined good '%s'" % [tid, good_id])

# ── research (Creativity perks) ──────────────────────────────────────────────

static func _rp(id: String, name: String, tree: String, cost: int, effect: Dictionary,
		desc: String, repeatable := false) -> void:
	research_perks[id] = ResearchDef.new(id, name, tree, cost, effect, desc, repeatable)
	research_order.append(id)

static func _build_research() -> void:
	# Per-tier trees (available once the tier is reached) + an endless Infinite tree.
	_rp("sawmillry", "Sawmillry", "pioneers", 15,
		{"type": "prod_mult", "key": "plank", "value": 1.0},
		"Sawmills double their plank output.")
	_rp("axehammer", "Axehammer", "pioneers", 25,
		{"type": "build_cost_flat", "key": "wood", "value": 3.0},
		"Every building costs 3 less Wood.")
	_rp("slack_time", "Slack Time", "colonists", 35,
		{"type": "creativity_mult", "value": 0.20},
		"+20% Creativity generation.")
	_rp("optimized_accounting", "Optimized Accounting", "colonists", 40,
		{"type": "tax_mult", "value": 0.10},
		"Inhabitants pay +10% Coin.")
	_rp("thrifty_masons", "Thrifty Masons", "townsmen", 50,
		{"type": "build_cost_flat", "key": "plank", "value": 5.0},
		"Every building costs 5 less Plank.")
	_rp("guild_methods", "Guild Methods", "townsmen", 60,
		{"type": "prod_mult_all", "value": 0.10},
		"All workshops produce +10%.")
	_rp("fine_accounting", "Fine Accounting", "merchants", 90,
		{"type": "tax_mult", "value": 0.15},
		"Inhabitants pay a further +15% Coin.")
	# Exploration / region unlocks (gate the multi-island world).
	_rp("better_spyglasses", "Better Spyglasses", "colonists", 40,
		{"type": "discovery_speed", "value": -0.35},
		"Island discoveries are 35% faster.")
	_rp("bannerman", "Bannerman", "colonists", 50,
		{"type": "army_cap_bonus", "value": 50.0},
		"Send up to +50 units in a single expedition.")
	_rp("war_drums", "War Drums", "townsmen", 55,
		{"type": "battle_time_cut", "value": 600.0},
		"Battles finish 10 minutes sooner.")
	_rp("tropical_islands", "Tropical Islands", "townsmen", 25,
		{"type": "unlock_region", "value": "tropical"},
		"Charter the Tropical region — coffee, sugar, cacao, tobacco.")
	_rp("northern_islands", "Northern Islands", "merchants", 175,
		{"type": "unlock_region", "value": "northern"},
		"Charter the Northern region — a pure extraction frontier.")
	_rp("better_relations", "Better Relations", "infinite", 200,
		{"type": "island_slots", "value": 1.0},
		"+1 island you can keep. Repeatable; cost rises each rank.", true)
	# Infinite tree — repeatable, escalating cost.
	_rp("infinite_industry", "Infinite Industry", "infinite", 80,
		{"type": "prod_mult_all", "value": 0.05},
		"+5% to all production. Repeatable; cost rises each rank.", true)
	_rp("infinite_wealth", "Infinite Wealth", "infinite", 80,
		{"type": "tax_mult", "value": 0.05},
		"+5% Coin from inhabitants. Repeatable; cost rises each rank.", true)

# ── military units (HP/Atk/Tier/abilities from dirm2/parpio-battle) ───────────

static func _u(id: String, name: String, hp: int, atk: int, tier: int,
		abilities: Array[String], boss := false) -> void:
	units[id] = UnitDef.new(id, name, hp, atk, tier, abilities, boss)

static func _build_units() -> void:
	# Player units (recruited from population + training buildings).
	_u("militia", "Militia", 15, 5, 1, [])
	_u("archer", "Archer", 10, 20, 1, ["Ranged"])
	_u("footsoldier", "Footsoldier", 40, 15, 1, [])
	_u("longbow_archer", "Longbow Archer", 10, 15, 2, ["Double", "Ranged"])
	_u("cavalry", "Cavalry", 5, 5, 2, ["First", "Flank"])
	_u("knight", "Knight", 90, 20, 3, [])
	_u("crossbowman", "Crossbowman", 15, 90, 3, ["Ranged"])
	_u("cuirassier", "Cuirassier", 120, 10, 4, ["First"])
	_u("cannoneer", "Cannoneer", 60, 80, 4, ["Last", "Ranged", "Flank", "Trample"])
	# Orc enemies (generic camp units + a sample warchief).
	_u("orcling", "Orcling", 10, 4, 1, [])
	_u("orc_grunt", "Orc Grunt", 30, 10, 1, [])
	_u("orc_archer", "Orc Archer", 15, 14, 1, ["Ranged"])
	_u("orc_brute", "Orc Brute", 80, 22, 2, [])
	# The 12 warchief bosses (one per island size 12→34 step 2; HP NOT monotonic —
	# Mazoga tankiest). `tier` here is the DURATION weight (100-600), NOT health.
	# Stats transcribed verbatim from the research spec.
	_u("bula",    "Warchief Bula",    2500,  150, 100, ["Ranged", "Last", "Splash"], true)
	_u("durz",    "Warchief Durz",    1100,  300, 140, ["Ranged", "First", "Splash"], true)
	_u("hork",    "Warchief Hork",    12000, 100, 180, ["Ranged", "Last", "Splash", "Flank"], true)
	_u("aguk",    "Warchief Aguk",    7000,  250, 220, ["Last", "Splash"], true)
	_u("kultan",  "Warchief Kul'Tan", 10000, 500, 260, ["Armageddon", "Ranged", "Triple"], true)
	_u("mazoga",  "Warchief Mazoga",  120000, 100, 300, ["Last", "Splash"], true)
	_u("durgash", "Warchief Durgash", 40000, 500, 340, ["Ranged", "First", "Splash"], true)
	_u("zrall",   "Warchief Zrall",   45000, 100, 380, ["LightningBolt", "First", "Splash"], true)
	_u("krashek", "Warchief Krashek", 35000, 1500, 460, ["Confusion", "First", "Splash"], true)
	_u("selzok",  "Warchief Selzok",  10000, 250, 500, ["Summon", "Ranged", "Last", "Splash"], true)
	_u("saukron", "Warchief Saukron", 15000, 3000, 540, ["Bulletproof", "Last", "Splash", "Spiky"], true)
	_u("nurzhel", "Warchief Nur'Zhel", 75000, 1250, 600, ["Revive", "Ranged", "First", "Splash"], true)

# ── ships (inter-island trade hulls; goods/h + Coin cost from the spec roster) ─

static func _s(id: String, name: String, region: String, gph: float, cost: int, cross: bool) -> void:
	ships[id] = ShipDef.new(id, name, region, gph, cost, cross)
	ship_order.append(id)

static func _build_ships() -> void:
	# Temperate: region-locked starters (Cog, Caravel) then crossing hulls (Hulk+).
	_s("cog", "Cog", "temperate", 60.0, 100, false)
	_s("caravel", "Caravel", "temperate", 80.0, 150, false)
	_s("hulk", "Hulk", "temperate", 180.0, 500, true)
	_s("pinnace", "Pinnace", "temperate", 270.0, 750, true)
	_s("galleon", "Galleon", "temperate", 540.0, 4000, true)
	_s("clipper", "Clipper", "temperate", 800.0, 6000, true)
	_s("schooner", "Schooner", "temperate", 1620.0, 20000, true)
	_s("windjammer", "Windjammer", "temperate", 2500.0, 30000, true)
	# Tropical region-locked starters.
	_s("barque", "Barque", "tropical", 60.0, 100, false)
	_s("skiff", "Skiff", "tropical", 80.0, 150, false)

# ── custodians (prestige run-modifiers, gated by Reputation tier) ─────────────

static func _c(id: String, name: String, rep: int, effect: Dictionary, desc: String) -> void:
	custodians[id] = CustodianDef.new(id, name, rep, effect, desc)
	custodian_order.append(id)

static func _build_custodians() -> void:
	# Rep 1
	_c("cartographer", "Cartographer", 1, {"type": "start_cartography", "value": 30.0},
		"Start each run with 30 Cartography.")
	_c("scientist", "Scientist", 1, {"type": "start_creativity", "value": 200.0},
		"Start with a 200-Creativity head start.")
	_c("minion", "Minion", 1, {"type": "island_slots", "value": 2.0},
		"Keep 2 more islands than your limit allows.")
	_c("bannerman", "Bannerman", 1, {"type": "army_cap_bonus", "value": 50.0},
		"Send +50 units in every expedition.")
	# Rep 2
	_c("merchant", "Merchant", 2, {"type": "trade_mult", "value": 1.0},
		"Trade routes carry double the goods.")
	# Rep 3
	_c("inventor", "Inventor", 3, {"type": "creativity_mult", "value": 1.0},
		"All Creativity generation is doubled.")
	_c("navigator", "Navigator", 3, {"type": "discovery_speed", "value": -0.5},
		"Island discoveries are twice as fast.")
	# Rep 4
	_c("treasurer", "Treasurer", 4, {"type": "start_coin", "value": 10000.0},
		"Start with a stocked treasury (10,000 Coin).")
	_c("general", "General", 4, {"type": "army_cap_bonus", "value": 100.0},
		"Field a far larger army (+100 unit cap).")
	# Rep 8
	_c("berserk", "Berserk", 8, {"type": "battle_instant", "value": 1.0},
		"All battles finish instantly.")

# ── buildings & recipes ────────────────────────────────────────────────────────

static func _bld(b: BuildingDef) -> void:
	buildings[b.id] = b

static func _make(id: String, name: String, category: String, color: Color,
		size := Vector2i(2, 2)) -> BuildingDef:
	var b := BuildingDef.new(id, name, category)
	b.color = color
	b.size = size
	return b

static func _build_buildings() -> void:
	# ── storage / civic ──────────────────────────────────────────────────────
	var kontor := _make("kontor", "Kontor", "storage", Color("d8cdb5"), Vector2i(3, 3))
	kontor.needs_coast = true
	kontor.is_storage = true
	kontor.storage_range = 14
	kontor.sprite_path = "res://assets/art/buildings/warehouse.png"
	_bld(kontor)

	var warehouse := _make("warehouse", "Warehouse", "storage", Color("c9bda0"))
	warehouse.is_storage = true
	warehouse.storage_range = Constants.DEFAULT_STORAGE_RANGE
	warehouse.cost = {"wood": 20}
	warehouse.sprite_path = "res://assets/art/buildings/warehouse.png"
	_bld(warehouse)

	# ── houses (the population tiers) ─────────────────────────────────────────
	_bld(_house("pioneer_hut", "Pioneer's Hut", "pioneers", {"wood": 10}, Color("c08552")))
	_bld(_house("colonist_house", "Colonist's House", "colonists", {"plank": 20}, Color("c9985c")))
	_bld(_house("townsmen_house", "Townsmen's House", "townsmen",
		{"limestone": 40, "mortar": 20}, Color("c2b280")))
	_bld(_house("merchant_mansion", "Merchant's Mansion", "merchants",
		{"brick": 60, "mortar": 30}, Color("b06a4a")))
	_bld(_house("paragon_residence", "Paragon's Residence", "paragons",
		{"marble": 60, "tools": 30}, Color("e6e0d4")))

	# ── service buildings (produce a "service good"; CHOSEN-DEFAULT rates) ─────
	# Community is a Pioneer luxury → Tavern available from the start.
	_bld(_producer("well", "Well", "civic", Color("6fc8e0"), Vector2i(1, 1),
		"water", 5.0, 60.0, {}, "", "", {"wood": 10}, "res://assets/art/buildings/well.png"))
	_bld(_producer("tavern", "Tavern", "civic", Color("e09a4a"), Vector2i(2, 2),
		"community", 5.0, 60.0, {}, "", "", {"wood": 20, "coin": 50},
		"res://assets/art/buildings/tavern.png"))
	_bld(_producer("school", "School", "civic", Color("bb6bd9"), Vector2i(2, 2),
		"education", 5.0, 120.0, {}, "colonists", "", {"plank": 100, "coin": 80}))
	_bld(_producer("medicus", "Medicus", "civic", Color("e06a6a"), Vector2i(2, 2),
		"medical_care", 5.0, 120.0, {}, "townsmen", "", {"limestone": 100, "mortar": 50}))

	# ── raw extractors ────────────────────────────────────────────────────────
	_bld(_producer("fishery", "Fisherman's Hut", "food", Color("5a9fb5"), Vector2i(2, 2),
		"fish", 1.0, 90.0, {}, "", "coast", {"wood": 10},
		"res://assets/art/buildings/fishery.png"))
	_bld(_producer("lumberjack", "Lumberjack", "raw", Color("5a7d3a"), Vector2i(2, 2),
		"wood", 1.0, 40.0, {}, "", "forest", {"wood": 5},
		"res://assets/art/buildings/lumberjack.png"))
	_bld(_producer("apple_orchard", "Apple Orchard", "raw", Color("c0563f"), Vector2i(2, 2),
		"apple", 3.0, 720.0, {}, "", "grass", {"wood": 10},
		"res://assets/art/buildings/apple_orchard.png"))
	_bld(_producer("wheat_farm", "Wheat Farm", "raw", Color("d9bb4a"), Vector2i(2, 2),
		"wheat", 1.0, 120.0, {}, "colonists", "grass", {"wood": 10},
		"res://assets/art/buildings/wheat_field.png"))
	_bld(_producer("hop_farm", "Hop Farm", "raw", Color("8fae5d"), Vector2i(2, 2),
		"hops", 1.0, 120.0, {}, "townsmen", "grass", {"wood": 10}))
	_bld(_producer("piggery", "Piggery", "food", Color("e0a0a0"), Vector2i(2, 2),
		"pig", 1.0, 120.0, {}, "", "grass", {"wood": 10},
		"res://assets/art/buildings/piggery.png"))
	_bld(_producer("sheep_farm", "Sheep Farm", "raw", Color("d9c8a0"), Vector2i(2, 2),
		"yarn", 1.0, 240.0, {}, "colonists", "grass", {"wood": 10},
		"res://assets/art/buildings/sheep_farm.png"))
	_bld(_producer("cattle_ranch", "Cattle Ranch", "raw", Color("a07850"), Vector2i(2, 2),
		"cattle", 1.0, 240.0, {}, "colonists", "grass", {"wood": 10},
		"res://assets/art/buildings/cattle_ranch.png"))

	# ── mines (MOUNTAIN) ──────────────────────────────────────────────────────
	_bld(_producer("coal_mine", "Coal Mine", "raw", Color("3a3a3a"), Vector2i(2, 2),
		"coal", 1.0, 240.0, {}, "colonists", "mountain", {"plank": 20}))
	_bld(_producer("salt_mine", "Salt Mine", "raw", Color("e0d8d0"), Vector2i(2, 2),
		"rock_salt", 1.0, 240.0, {}, "townsmen", "mountain", {"plank": 20}))
	_bld(_producer("limestone_quarry", "Limestone Quarry", "raw", Color("cfc8b8"), Vector2i(2, 2),
		"limestone", 1.0, 180.0, {}, "colonists", "mountain", {"wood": 20}))
	_bld(_producer("iron_mine", "Iron Mine", "raw", Color("8a7a6a"), Vector2i(2, 2),
		"iron_ore", 1.0, 240.0, {}, "merchants", "mountain", {"plank": 20}))
	_bld(_producer("marble_quarry", "Marble Quarry", "raw", Color("eae6df"), Vector2i(2, 2),
		"marble", 1.0, 360.0, {}, "merchants", "mountain", {"plank": 40}))

	# ── processors (some need a straight river spot) ──────────────────────────
	_bld(_producer("sawmill", "Sawmill", "production", Color("c19a6b"), Vector2i(2, 2),
		"plank", 1.0, 30.0, {"wood": 1}, "", "river", {"wood": 10},
		"res://assets/art/buildings/sawmill.png"))
	_bld(_producer("cider_maker", "Cider Maker", "food", Color("e0a93a"), Vector2i(2, 2),
		"cider", 1.0, 60.0, {"apple": 1}, "", "", {"wood": 15},
		"res://assets/art/buildings/cider_maker.png"))
	_bld(_producer("sausage_maker", "Sausage Maker", "food", Color("c4564a"), Vector2i(2, 2),
		"sausage", 1.0, 120.0, {"pig": 1}, "", "", {"wood": 15},
		"res://assets/art/buildings/sausage_maker.png"))
	_bld(_producer("flour_mill", "Flour Mill", "production", Color("efe7c8"), Vector2i(2, 2),
		"flour", 1.0, 120.0, {"wheat": 2}, "colonists", "river", {"wood": 20},
		"res://assets/art/buildings/windmill.png"))
	_bld(_producer("bakery", "Bakery", "food", Color("d9a85a"), Vector2i(2, 2),
		"bread", 1.0, 240.0, {"flour": 1}, "colonists", "", {"wood": 20},
		"res://assets/art/buildings/bakery.png"))
	_bld(_producer("weaver", "Weaver", "production", Color("9a6fb0"), Vector2i(2, 2),
		"fabric", 1.0, 240.0, {"yarn": 2}, "colonists", "", {"wood": 20},
		"res://assets/art/buildings/weaver.png"))
	_bld(_producer("potashery", "Potashery", "production", Color("b8b0a0"), Vector2i(2, 2),
		"potash", 1.0, 120.0, {"wood": 2}, "colonists", "", {"wood": 20}))
	_bld(_producer("tallow_maker", "Tallow Maker", "production", Color("efe0a8"), Vector2i(2, 2),
		"tallow", 1.0, 120.0, {"cattle": 1}, "colonists", "", {"wood": 20}))
	_bld(_producer("soap_boiler", "Soap Boiler", "production", Color("e8e0f0"), Vector2i(2, 2),
		"soap", 1.0, 240.0, {"tallow": 1, "potash": 1}, "colonists", "", {"wood": 25}))
	_bld(_producer("furriery", "Furriery", "production", Color("b08858"), Vector2i(2, 2),
		"hide", 1.0, 120.0, {"cattle": 1}, "townsmen", "", {"wood": 20}))
	_bld(_producer("salt_works", "Salt Works", "production", Color("f4f0ec"), Vector2i(2, 2),
		"salt", 2.0, 720.0, {"coal": 1, "rock_salt": 1}, "townsmen", "", {"wood": 20}))
	_bld(_producer("tannery", "Tannery", "production", Color("8a5a30"), Vector2i(2, 2),
		"leather", 3.0, 1080.0, {"salt": 1, "hide": 3}, "townsmen", "river", {"plank": 30}))
	_bld(_producer("malthouse", "Malthouse", "production", Color("c9a24a"), Vector2i(2, 2),
		"malt", 1.0, 120.0, {"wheat": 2}, "townsmen", "", {"wood": 20}))
	_bld(_producer("brewery", "Brewery", "food", Color("d8a23a"), Vector2i(2, 2),
		"beer", 2.0, 240.0, {"hops": 3, "malt": 1}, "townsmen", "", {"plank": 25}))
	_bld(_producer("kiln", "Lime Kiln", "production", Color("b0a890"), Vector2i(2, 2),
		"mortar", 1.0, 120.0, {"limestone": 1}, "colonists", "", {"wood": 20}))
	# Clay Pit feeds the Brickworks (→ brick → Merchant's Mansion). Without it the
	# whole urban progression would soft-lock at Townsmen.
	_bld(_producer("clay_pit", "Clay Pit", "raw", Color("b5651d"), Vector2i(2, 2),
		"clay", 1.0, 120.0, {}, "townsmen", "", {"wood": 20}))
	_bld(_producer("brickworks", "Brickworks", "production", Color("b14a3a"), Vector2i(2, 2),
		"brick", 1.0, 120.0, {"clay": 1}, "townsmen", "", {"wood": 20}))
	_bld(_producer("iron_smelter", "Iron Smelter", "production", Color("9aa0a8"), Vector2i(2, 2),
		"iron_ingot", 2.0, 960.0, {"coal": 1, "iron_ore": 2}, "merchants", "", {"plank": 30}))
	_bld(_producer("toolmaker", "Toolmaker", "production", Color("7a8088"), Vector2i(2, 2),
		"tools", 4.0, 960.0, {"coal": 1, "iron_ingot": 2}, "merchants", "", {"plank": 30}))

	# ── copper line (Colonist metal → swords; → Cauldron that unblocks Merchants) ─
	_bld(_producer("copper_mine", "Copper Mine", "raw", Color("b87333"), Vector2i(2, 2),
		"copper_ore", 1.0, 240.0, {}, "colonists", "mountain", {"plank": 20}))
	_bld(_producer("copper_smelter", "Copper Smelter", "production", Color("d98a4a"), Vector2i(2, 2),
		"copper_ingot", 2.0, 720.0, {"coal": 1, "copper_ore": 2}, "colonists", "", {"plank": 25}))
	_bld(_producer("cauldron_foundry", "Cauldron Foundry", "production", Color("5a5a5a"), Vector2i(2, 2),
		"cauldron", 1.0, 480.0, {"copper_ingot": 1}, "townsmen", "", {"plank": 30}))
	# ── gold line (Merchant jewellery) ────────────────────────────────────────
	_bld(_producer("gold_mine", "Gold Mine", "raw", Color("d4af37"), Vector2i(2, 2),
		"gold_ore", 1.0, 360.0, {}, "merchants", "mountain", {"plank": 30}))
	_bld(_producer("gold_smelter", "Gold Smelter", "production", Color("f2c94c"), Vector2i(2, 2),
		"gold_ingot", 1.0, 600.0, {"coal": 1, "gold_ore": 2}, "merchants", "", {"plank": 30}))
	_bld(_producer("goldsmith", "Goldsmith", "production", Color("f2c94c"), Vector2i(2, 2),
		"gold_jewelry", 1.0, 720.0, {"gold_ingot": 1}, "merchants", "", {"brick": 30}))
	# ── Townsmen/Merchant luxuries (some need tropical imports: sugar/coffee) ───
	_bld(_producer("jam_maker", "Jam Maker", "food", Color("c0392b"), Vector2i(2, 2),
		"jam", 1.0, 240.0, {"apple": 2, "sugar": 1}, "townsmen", "", {"wood": 25}))
	_bld(_producer("hatter", "Hatter", "production", Color("34495e"), Vector2i(2, 2),
		"hat", 1.0, 480.0, {"fabric": 1, "leather": 1}, "merchants", "", {"brick": 30}))
	_bld(_producer("patisserie", "Patisserie", "food", Color("e6b35a"), Vector2i(2, 2),
		"pastry", 1.0, 360.0, {"flour": 1, "sugar": 1}, "merchants", "", {"brick": 30}))
	_bld(_producer("caviary", "Caviar House", "food", Color("2c2c2c"), Vector2i(2, 2),
		"caviar", 1.0, 720.0, {"fish": 2, "salt": 1}, "merchants", "coast", {"plank": 30}))
	_bld(_producer("perfumery", "Perfumery", "production", Color("e784c4"), Vector2i(2, 2),
		"perfume", 1.0, 600.0, {"tallow": 1, "sugar": 1}, "merchants", "", {"brick": 30}))
	_bld(_producer("pipe_maker", "Pipe Maker", "production", Color("8d6e63"), Vector2i(2, 2),
		"tobacco_pipe", 1.0, 480.0, {"tobacco": 1, "wood": 1}, "merchants", "", {"brick": 30}))
	# ── Paragon luxuries (top of the cascade) ─────────────────────────────────
	_bld(_producer("paper_mill", "Paper Mill", "production", Color("f4f0e6"), Vector2i(2, 2),
		"paper", 2.0, 240.0, {"wood": 2}, "merchants", "river", {"plank": 30}))
	_bld(_producer("vineyard", "Vineyard", "raw", Color("6b3fa0"), Vector2i(2, 2),
		"grape", 1.0, 360.0, {}, "merchants", "grass", {"wood": 20}, "", "temperate"))
	_bld(_producer("cobbler", "Cobbler", "production", Color("8a5a30"), Vector2i(2, 2),
		"shoe", 1.0, 600.0, {"leather": 1, "fabric": 1}, "paragons", "", {"marble": 20}))
	_bld(_producer("optician", "Optician", "production", Color("b0c4de"), Vector2i(2, 2),
		"glasses", 1.0, 720.0, {"copper_ingot": 1, "coal": 1}, "paragons", "", {"marble": 20}))
	_bld(_producer("printing_press", "Printing Press", "production", Color("6b4423"), Vector2i(2, 2),
		"book", 1.0, 600.0, {"paper": 2}, "paragons", "", {"marble": 20}))
	_bld(_producer("chocolatier", "Chocolatier", "food", Color("5b3a29"), Vector2i(2, 2),
		"chocolate_candy", 1.0, 600.0, {"cacao": 1, "sugar": 1}, "paragons", "", {"marble": 20}))
	_bld(_producer("couturier", "Couturier", "production", Color("7d3c98"), Vector2i(2, 2),
		"noble_garment", 1.0, 900.0, {"fabric": 2, "perfume": 1}, "paragons", "", {"marble": 30}))
	_bld(_producer("winery", "Winery", "food", Color("722f37"), Vector2i(2, 2),
		"wine", 1.0, 720.0, {"grape": 2}, "paragons", "", {"marble": 20}))

	# ── tropical plantations (region-gated; their goods are imported to temperate) ─
	var plantation := "res://assets/art/buildings/plantation.png"
	_bld(_producer("coffee_plantation", "Coffee Plantation", "raw", Color("6f4e37"), Vector2i(2, 2),
		"coffee", 1.0, 300.0, {}, "townsmen", "grass", {"wood": 15}, plantation, "tropical"))
	_bld(_producer("sugar_plantation", "Sugar Plantation", "raw", Color("f0ead8"), Vector2i(2, 2),
		"sugar", 1.0, 240.0, {}, "townsmen", "grass", {"wood": 15}, plantation, "tropical"))
	_bld(_producer("cacao_plantation", "Cacao Plantation", "raw", Color("6f4e37"), Vector2i(2, 2),
		"cacao", 1.0, 360.0, {}, "merchants", "grass", {"wood": 15}, plantation, "tropical"))
	_bld(_producer("tobacco_plantation", "Tobacco Plantation", "raw", Color("8a7b3a"), Vector2i(2, 2),
		"tobacco", 1.0, 360.0, {}, "merchants", "grass", {"wood": 15}, plantation, "tropical"))

	# ── weapon smiths (feed the training buildings; recipes per spec recruiting) ─
	_bld(_producer("bowyer", "Bowyer", "military", Color("9a7b4f"), Vector2i(2, 2),
		"bow", 1.0, 240.0, {"wood": 3, "yarn": 2}, "colonists", "",
		{"wood": 20}, "res://assets/art/buildings/bowyer.png"))  # 3 Wood + 2 Fiber → Bow /4m
	_bld(_producer("weaponsmith", "Weaponsmith", "military", Color("d98a4a"), Vector2i(2, 2),
		"copper_sword", 1.0, 240.0, {"copper_ingot": 1}, "colonists", "",
		{"plank": 25}, "res://assets/art/buildings/weaponsmith.png"))
	_bld(_producer("armory", "Armory", "military", Color("c0c4cc"), Vector2i(2, 2),
		"iron_sword", 1.0, 300.0, {"iron_ingot": 1}, "merchants", "", {"plank": 30}))
	_bld(_producer("cannon_foundry", "Cannon Foundry", "military", Color("4a4a4a"), Vector2i(2, 2),
		"cannon", 1.0, 480.0, {"tools": 1, "coal": 1}, "merchants", "river",
		{"plank": 40}, "res://assets/art/buildings/cannon_foundry.png"))

	# ── training grounds (Militia + a weapon → a trained unit; cycles per spec) ─
	_bld(_producer("archery_range", "Archery Range", "military", Color("8fae5d"), Vector2i(2, 2),
		"archer", 1.0, 300.0, {"militia": 1, "bow": 1}, "colonists", "",
		{"wood": 20}, "res://assets/art/buildings/archery_range.png"))  # 1 Militia + 1 Bow /5m
	_bld(_producer("barracks", "Barracks", "military", Color("a05a3a"), Vector2i(2, 2),
		"footsoldier", 1.0, 600.0, {"militia": 2, "copper_sword": 1}, "colonists", "",
		{"plank": 25, "coin": 50}, "res://assets/art/buildings/barracks.png"))  # 2 Mil + Copper Sword /10m
	_bld(_producer("knight_school", "Knight Barracks", "military", Color("d0d4dc"), Vector2i(2, 2),
		"knight", 1.0, 1200.0, {"militia": 4, "iron_sword": 1}, "merchants", "",
		{"brick": 40, "coin": 200}, "res://assets/art/buildings/knight_school.png"))  # 4 Mil + Iron Sword /20m
	_bld(_producer("cannoneer_school", "Cannoneer's School", "military", Color("5a5a5a"), Vector2i(2, 2),
		"cannoneer", 1.0, 1800.0, {"militia": 6, "cannon": 1}, "paragons", "",
		{"marble": 40, "tools": 20}, "res://assets/art/buildings/cannoneer_school.png"))  # 6 Mil + Cannon /30m

	# ── naval (shipyard enables ships + inter-island trade routes) ─────────────
	var shipyard := _make("shipyard", "Shipyard", "naval", Color("8a6a45"), Vector2i(3, 3))
	shipyard.needs_coast = true
	shipyard.is_shipyard = true
	shipyard.tier_unlock = "colonists"
	shipyard.cost = {"plank": 60, "coin": 150}
	shipyard.sprite_path = "res://assets/art/buildings/shipyard.png"
	_bld(shipyard)

	# ── the Palace (prestige): Foundation + 5 Favor-fuelled stages → Reputation ─
	var palace := _make("palace", "Palace", "civic", Color("e6d8b0"), Vector2i(3, 3))
	palace.is_palace = true
	palace.tier_unlock = "paragons"
	palace.cost = {"coin": 2000, "plank": 300, "tools": 200}  # Foundation cost (scaled)
	palace.sprite_path = "res://assets/art/buildings/palace.png"
	_bld(palace)

## House factory. A house type appears in the build menu once its tier is reached;
## the first higher resident arrives by upgrading the tier below in place.
static func _house(id: String, name: String, tier_id: String, cost: Dictionary,
		color: Color) -> BuildingDef:
	var b := _make(id, name, "house", color, Vector2i(2, 2))
	b.is_house = true
	b.house_tier = tier_id
	b.tier_unlock = tier_id
	b.cost = cost
	# Distinct sprite per tier (cottage → house → townhouse → mansion → residence).
	# The renderer falls back to `color` if a file is missing.
	var house_sprite: String = {
		"pioneers": "house", "colonists": "colonist_house", "townsmen": "townsmen_house",
		"merchants": "merchant_mansion", "paragons": "paragon_residence",
	}.get(tier_id, "house")
	b.sprite_path = "res://assets/art/buildings/%s.png" % house_sprite
	return b

## Producer/consumer factory. terrain_tag: "" any-land | "grass" | "forest" |
## "mountain" | "river" | "coast" | "beach".
static func _producer(id: String, name: String, category: String, color: Color, size: Vector2i,
		output: String, qty: float, time: float, inputs: Dictionary,
		tier_unlock: String, terrain_tag: String, cost: Dictionary,
		sprite := "", region := "") -> BuildingDef:
	var b := _make(id, name, category, color, size)
	b.recipe = RecipeDef.new(output, qty, time, inputs)
	b.tier_unlock = tier_unlock
	b.cost = cost
	b.sprite_path = sprite
	b.region = region
	match terrain_tag:
		"grass": b.terrain_req = T.GRASS
		"forest": b.terrain_req = T.FOREST
		"mountain": b.terrain_req = T.MOUNTAIN
		"river": b.terrain_req = T.RIVER
		"beach": b.terrain_req = T.BEACH
		"coast":
			b.terrain_req = BuildingDef.ANY_LAND
			b.needs_coast = true
		_:
			b.terrain_req = BuildingDef.ANY_LAND
	return b
