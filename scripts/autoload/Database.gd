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
	_assert_cascade()

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
		"community", 5.0, 60.0, {}, "", "", {"wood": 20, "coin": 50}))
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
		"apple", 3.0, 720.0, {}, "", "grass", {"wood": 10}))
	_bld(_producer("wheat_farm", "Wheat Farm", "raw", Color("d9bb4a"), Vector2i(2, 2),
		"wheat", 1.0, 120.0, {}, "colonists", "grass", {"wood": 10},
		"res://assets/art/buildings/wheat_field.png"))
	_bld(_producer("hop_farm", "Hop Farm", "raw", Color("8fae5d"), Vector2i(2, 2),
		"hops", 1.0, 120.0, {}, "townsmen", "grass", {"wood": 10}))
	_bld(_producer("piggery", "Piggery", "food", Color("e0a0a0"), Vector2i(2, 2),
		"pig", 1.0, 120.0, {}, "", "grass", {"wood": 10}))
	_bld(_producer("sheep_farm", "Sheep Farm", "raw", Color("d9c8a0"), Vector2i(2, 2),
		"yarn", 1.0, 240.0, {}, "colonists", "grass", {"wood": 10}))
	_bld(_producer("cattle_ranch", "Cattle Ranch", "raw", Color("a07850"), Vector2i(2, 2),
		"cattle", 1.0, 240.0, {}, "colonists", "grass", {"wood": 10}))

	# ── mines (MOUNTAIN) ──────────────────────────────────────────────────────
	_bld(_producer("coal_mine", "Coal Mine", "raw", Color("3a3a3a"), Vector2i(2, 2),
		"coal", 1.0, 240.0, {}, "townsmen", "mountain", {"plank": 20}))
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
		"plank", 1.0, 30.0, {"wood": 1}, "", "river", {"wood": 10}))
	_bld(_producer("cider_maker", "Cider Maker", "food", Color("e0a93a"), Vector2i(2, 2),
		"cider", 1.0, 60.0, {"apple": 1}, "", "", {"wood": 15}))
	_bld(_producer("sausage_maker", "Sausage Maker", "food", Color("c4564a"), Vector2i(2, 2),
		"sausage", 1.0, 120.0, {"pig": 1}, "", "", {"wood": 15}))
	_bld(_producer("flour_mill", "Flour Mill", "production", Color("efe7c8"), Vector2i(2, 2),
		"flour", 1.0, 120.0, {"wheat": 2}, "colonists", "river", {"wood": 20},
		"res://assets/art/buildings/windmill.png"))
	_bld(_producer("bakery", "Bakery", "food", Color("d9a85a"), Vector2i(2, 2),
		"bread", 1.0, 240.0, {"flour": 1}, "colonists", "", {"wood": 20}))
	_bld(_producer("weaver", "Weaver", "production", Color("9a6fb0"), Vector2i(2, 2),
		"fabric", 1.0, 240.0, {"yarn": 2}, "colonists", "", {"wood": 20}))
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
	_bld(_producer("brickworks", "Brickworks", "production", Color("b14a3a"), Vector2i(2, 2),
		"brick", 1.0, 120.0, {"clay": 1}, "townsmen", "", {"wood": 20}))
	_bld(_producer("iron_smelter", "Iron Smelter", "production", Color("9aa0a8"), Vector2i(2, 2),
		"iron_ingot", 2.0, 960.0, {"coal": 1, "iron_ore": 2}, "merchants", "", {"plank": 30}))
	_bld(_producer("toolmaker", "Toolmaker", "production", Color("7a8088"), Vector2i(2, 2),
		"tools", 4.0, 960.0, {"coal": 1, "iron_ingot": 2}, "merchants", "", {"plank": 30}))

## House factory. A house type appears in the build menu once its tier is reached;
## the first higher resident arrives by upgrading the tier below in place.
static func _house(id: String, name: String, tier_id: String, cost: Dictionary,
		color: Color) -> BuildingDef:
	var b := _make(id, name, "house", color, Vector2i(2, 2))
	b.is_house = true
	b.house_tier = tier_id
	b.tier_unlock = tier_id
	b.cost = cost
	b.sprite_path = "res://assets/art/buildings/house.png"
	return b

## Producer/consumer factory. terrain_tag: "" any-land | "grass" | "forest" |
## "mountain" | "river" | "coast" | "beach".
static func _producer(id: String, name: String, category: String, color: Color, size: Vector2i,
		output: String, qty: float, time: float, inputs: Dictionary,
		tier_unlock: String, terrain_tag: String, cost: Dictionary,
		sprite := "") -> BuildingDef:
	var b := _make(id, name, category, color, size)
	b.recipe = RecipeDef.new(output, qty, time, inputs)
	b.tier_unlock = tier_unlock
	b.cost = cost
	b.sprite_path = sprite
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
