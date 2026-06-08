extends Node2D
## Renders the active island (baked Wang terrain + decorations + building sprites)
## and turns mouse input into placement / selection. Reads Game.sim; never owns
## game state. Emits `building_selected` for the HUD's inspector panel.

const TILE := Constants.TILE_PX

signal building_selected(pb: PlacedBuilding)
signal camp_selected(camp: OrcCamp)
signal hover_changed(cell: Vector2i, valid: bool)
signal build_selection_cleared()

var _terrain_sprite: Sprite2D
var _build_id := ""              ## currently-armed build menu selection ("" = none)
var _hover := Vector2i(-1, -1)
var _hover_valid := false
var _sprites: Dictionary = {}    ## building_id/decoration -> Texture2D (cached, may be null)
var _selected: PlacedBuilding = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain_sprite = Sprite2D.new()
	_terrain_sprite.centered = false
	_terrain_sprite.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	_terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain_sprite.z_index = -10
	add_child(_terrain_sprite)
	_rebake()
	Game.sim.building_placed.connect(func(_i, _c): _on_world_changed())
	Game.sim.building_removed.connect(func(_c): _on_world_changed())

func _on_world_changed() -> void:
	queue_redraw()

func _rebake() -> void:
	var isl := Game.sim.active_island()
	if isl != null:
		_terrain_sprite.texture = TerrainRenderer.bake(isl)
	queue_redraw()

# ── art loading (decorations / building sprites; tolerant of missing files) ─────

func _tex(path: String) -> Texture2D:
	if _sprites.has(path):
		return _sprites[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_sprites[path] = t
	return t

# ── input ──────────────────────────────────────────────────────────────────────

func set_build_selection(id: String) -> void:
	_build_id = id
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _cell_at(get_global_mouse_position())
		if c != _hover:
			_hover = c
			_update_hover_valid()
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_cell_at(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _build_id != "":
				set_build_selection("")
				build_selection_cleared.emit()
			else:
				_select(null)

func _cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / TILE), floori(world.y / TILE))

func _update_hover_valid() -> void:
	if _build_id == "":
		_hover_valid = false
		return
	var isl := Game.sim.active_island()
	var def := Database.building(_build_id)
	if isl == null or def == null:
		_hover_valid = false
		return
	_hover_valid = isl.can_place(def, _hover).ok and Game.sim.can_afford(def)
	hover_changed.emit(_hover, _hover_valid)

func _on_click(cell: Vector2i) -> void:
	var isl := Game.sim.active_island()
	if isl == null:
		return
	if _build_id != "":
		var def := Database.building(_build_id)
		var res := Game.sim.try_place(def, cell)
		if not res.ok:
			Game.sim.notify.emit(res.reason, "warn")
		else:
			_rebake()
		_update_hover_valid()
	else:
		# Uncleared Orc camp → open the military view; otherwise select a building.
		var camp := isl.camp_at(cell)
		if camp != null and not camp.cleared:
			_select(null)
			camp_selected.emit(camp)
		else:
			_select(isl.building_at(cell))

func _select(pb: PlacedBuilding) -> void:
	_selected = pb
	building_selected.emit(pb)
	queue_redraw()

# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var isl := Game.sim.active_island()
	if isl == null:
		return
	_draw_decorations(isl)
	_draw_buildings(isl)
	_draw_camps(isl)
	_draw_selection(isl)
	_draw_preview(isl)

func _draw_camps(isl: Island) -> void:
	var camp_tex := _tex("res://assets/art/buildings/orc_camp.png")
	var font := ThemeDB.fallback_font
	for camp in isl.camps:
		if camp.cleared:
			continue
		var rect := Rect2(Vector2(camp.origin) * TILE, Vector2(camp.size) * TILE)
		if camp_tex != null:
			draw_texture_rect(camp_tex, rect, false)
		else:
			draw_rect(rect.grow(-2), Color("5a2a2a"))
			draw_rect(rect.grow(-2), Color("d03030"), false, 2.0)
		# A small banner with the defender count and a warchief skull marker.
		var count := 0
		for uid in camp.full_army():
			count += int(camp.full_army()[uid])
		var label := ("☠ %d" % count) if camp.boss != "" else str(count)
		var bw: float = rect.size.x
		draw_rect(Rect2(rect.position + Vector2(0, -14), Vector2(bw, 14)), Color(0.5, 0.1, 0.1, 0.85))
		draw_string(font, rect.position + Vector2(4, -3), label,
			HORIZONTAL_ALIGNMENT_LEFT, bw - 4, 11, Color("ffe0e0"))

func _draw_decorations(isl: Island) -> void:
	var tree := _tex("res://assets/art/terrain/tree.png")
	var rock := _tex("res://assets/art/terrain/rock.png")
	for y in isl.height:
		for x in isl.width:
			var t := isl.get_terrain(Vector2i(x, y))
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			match t:
				Constants.Terrain.FOREST:
					if tree != null:
						draw_texture_rect(tree, r, false)
					else:
						draw_circle(r.get_center(), TILE * 0.34, Color("2f6b2c"))
				Constants.Terrain.MOUNTAIN:
					if rock != null:
						draw_texture_rect(rock, r, false)
					else:
						draw_rect(r.grow(-4), Color("8a8273"))
				Constants.Terrain.RIVER:
					draw_rect(r, Color(0.29, 0.64, 0.77, 0.85))

func _draw_buildings(isl: Island) -> void:
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		if def == null:
			continue
		var rect := Rect2(pb.origin * TILE, def.size * TILE)
		var tex := _tex(def.sprite_path) if def.sprite_path != "" else null
		if tex != null:
			draw_texture_rect(tex, rect, false)
		else:
			draw_rect(rect.grow(-2), def.color)
			draw_rect(rect.grow(-2), Color(0, 0, 0, 0.4), false, 2.0)
		# Disconnected indicator (no storage in range).
		if not pb.connected and not def.is_storage:
			draw_rect(rect, Color(0.9, 0.2, 0.2, 0.28))
		# Resident pips for houses.
		if def.is_house and pb.residents > 0:
			var tier := Database.tier(pb.tier_id)
			var frac := float(pb.residents) / float(tier.max_residents) if tier else 0.0
			var bar := Rect2(rect.position + Vector2(2, rect.size.y - 5),
				Vector2((rect.size.x - 4) * frac, 3))
			draw_rect(bar, Color("ffd34a"))

func _draw_selection(_isl: Island) -> void:
	if _selected == null:
		return
	var def := Database.building(_selected.building_id)
	if def == null:
		return
	var rect := Rect2(_selected.origin * TILE, def.size * TILE)
	draw_rect(rect.grow(1), Color("ffffff"), false, 2.0)

func _draw_preview(isl: Island) -> void:
	if _build_id == "" or not isl.in_bounds(_hover):
		return
	var def := Database.building(_build_id)
	if def == null:
		return
	var rect := Rect2(_hover * TILE, def.size * TILE)
	var col := Color(0.3, 0.9, 0.4, 0.4) if _hover_valid else Color(0.9, 0.3, 0.3, 0.4)
	draw_rect(rect, col)
	draw_rect(rect, col.lightened(0.2), false, 2.0)
