extends Node2D
## Root scene: builds the camera, the IslandView, and the HUD, and wires them to the
## Game.sim autoload. Owns camera pan/zoom (middle-drag + wheel + WASD). Left/right
## mouse are reserved for the IslandView (place / select / cancel).

const TILE := Constants.TILE_PX
const PAN_SPEED := 600.0

var _cam: Camera2D
var _island_view: Node2D
var _hud: CanvasLayer
var _panning := false

func _ready() -> void:
	_island_view = (load("res://scenes/IslandView.gd") as GDScript).new()
	add_child(_island_view)

	# Ambient animated settlers walking the settlement (cosmetic).
	add_child((load("res://scenes/SettlerLayer.gd") as GDScript).new())

	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	var isl := Game.sim.active_island()
	if isl != null:
		_cam.position = Vector2(isl.width, isl.height) * TILE * 0.5
	_cam.zoom = Vector2(0.7, 0.7)

	_hud = (load("res://scenes/HUD.gd") as GDScript).new()
	add_child(_hud)
	_hud.bind_island(_island_view)

	if "--capture" in OS.get_cmdline_args() or "--capture" in OS.get_cmdline_user_args():
		_run_capture.call_deferred()

# ── headless-ish screenshot harness (run windowed with `-- --capture`) ──────────

func _run_capture() -> void:
	_build_demo_layout()
	Game.sim.advance(400.0)
	_island_view._rebake()
	_frame_island()
	# Let ambient settlers spawn and walk a little before the shot.
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://docs/screenshot.png"
	if img.save_png(path) == OK:
		print("CAPTURE_OK ", ProjectSettings.globalize_path(path))
	else:
		print("CAPTURE_FAIL")
	get_tree().quit()

## Auto-place a demo settlement near the Kontor — also a placement smoke test on a
## real generated island.
func _build_demo_layout() -> void:
	var isl := Game.sim.active_island()
	isl.stockpile = {"wood": 800.0, "plank": 400.0}
	Game.sim.currencies["coin"] = 3000.0
	Game.sim.unlocked_tiers = ["pioneers", "colonists", "townsmen", "merchants"]
	var plan := [
		"fishery", "well", "tavern", "lumberjack", "lumberjack", "sawmill",
		"apple_orchard", "cider_maker", "piggery", "sausage_maker",
		"wheat_farm", "flour_mill", "bakery", "sheep_farm", "weaver", "cattle_ranch",
		"pioneer_hut", "pioneer_hut", "colonist_house", "colonist_house", "townsmen_house",
	]
	for id in plan:
		var def := Database.building(id)
		var spot := _find_spot(def)
		if spot != Vector2i(-9999, -9999):
			Game.sim.try_place(def, spot)
	# Seed needs so houses show population for the shot.
	isl.stockpile["fish"] = 500.0
	isl.stockpile["water"] = 500.0
	for pb in isl.buildings:
		if Database.building(pb.building_id).is_house:
			pb.residents = 6
	Game.sim._recompute_connectivity(isl)
	var conn := 0
	for pb in isl.buildings:
		if pb.connected:
			conn += 1
	print("DEMO_CONNECTIVITY ", conn, "/", isl.buildings.size(), " connected")

func _find_spot(def: BuildingDef) -> Vector2i:
	var isl := Game.sim.active_island()
	# Spiral out from the Kontor so demo buildings stay within its storage range.
	var c := Vector2i(isl.width / 2, isl.height / 2)
	for pb in isl.buildings:
		if pb.building_id == "kontor":
			c = pb.origin
			break
	for radius in range(0, max(isl.width, isl.height)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var o := c + Vector2i(dx, dy)
				if isl.can_place(def, o).ok:
					return o
	return Vector2i(-9999, -9999)

func _frame_island() -> void:
	var isl := Game.sim.active_island()
	if isl == null:
		return
	# Centre on the average of placed buildings so the settlement fills the shot.
	var sum := Vector2.ZERO
	var n := 0
	for pb in isl.buildings:
		var def := Database.building(pb.building_id)
		sum += (Vector2(pb.origin) + Vector2(def.size) * 0.5) * TILE
		n += 1
	_cam.position = sum / n if n > 0 else Vector2(isl.width, isl.height) * TILE * 0.5
	_cam.zoom = Vector2(0.9, 0.9)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.1)
	elif event is InputEventMouseMotion and _panning:
		_cam.position -= event.relative / _cam.zoom

func _zoom_at(factor: float) -> void:
	var z: float = clampf(_cam.zoom.x * factor, 0.3, 2.5)
	_cam.zoom = Vector2(z, z)

func _process(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"))
	if dir != Vector2.ZERO:
		_cam.position += dir * PAN_SPEED * delta / _cam.zoom.x
