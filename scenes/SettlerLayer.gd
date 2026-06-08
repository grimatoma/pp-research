extends Node2D
## Ambient animated settlers that walk between the settlement's buildings and the
## Kontor — PP2's signature "settlers physically carry goods" life. Cosmetic only;
## reads building positions from Game.sim but never changes game state. The settler
## count scales with population.

const TILE := Constants.TILE_PX
const SPEED := 34.0
const ARRIVE := 5.0
const MAX_SETTLERS := 12
const FRAME_FPS := 8.0
const WALK_DIR := ["south", "east", "north", "west"]

var _frames: SpriteFrames
var _settlers: Array = []   ## [{spr: AnimatedSprite2D, target: Vector2}]
var _spawn_accum := 0.0

func _ready() -> void:
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frames = _build_frames()

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	var any := false
	for d in WALK_DIR:
		sf.add_animation(d)
		sf.set_animation_loop(d, true)
		sf.set_animation_speed(d, FRAME_FPS)
		for n in 6:
			var p := "res://assets/art/characters/walk/%s/%d.png" % [d, n]
			if ResourceLoader.exists(p):
				sf.add_frame(d, load(p))
				any = true
	return sf if any else null

func _process(delta: float) -> void:
	var isl: Island = Game.sim.active_island() if Game.sim else null
	if isl == null or _frames == null:
		return
	var want: int = clampi(Game.sim.total_population() / 5, 0, MAX_SETTLERS)
	_spawn_accum += delta
	if _settlers.size() < want and _spawn_accum > 0.6:
		_spawn_accum = 0.0
		_spawn_settler(isl)
	elif _settlers.size() > want and not _settlers.is_empty():
		var s = _settlers.pop_back()
		s.spr.queue_free()
	for s in _settlers:
		_step_settler(s, isl, delta)

func _spawn_settler(isl: Island) -> void:
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _frames
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = true
	var start := _random_building_pos(isl)
	spr.position = start
	add_child(spr)
	var s := {"spr": spr, "target": _pick_target(isl, start)}
	spr.play("south")
	_settlers.append(s)

func _step_settler(s: Dictionary, isl: Island, delta: float) -> void:
	var spr: AnimatedSprite2D = s.spr
	var to: Vector2 = s.target - spr.position
	if to.length() < ARRIVE:
		s.target = _pick_target(isl, spr.position)
		return
	var dir := to.normalized()
	spr.position += dir * SPEED * delta
	# Face the dominant movement axis.
	if absf(dir.x) > absf(dir.y):
		spr.play("east" if dir.x > 0 else "west")
		spr.flip_h = false
	else:
		spr.play("south" if dir.y > 0 else "north")

func _pick_target(isl: Island, _from: Vector2) -> Vector2:
	# 55% head to a storage building (hauling goods), else a random connected building.
	if randf() < 0.55:
		for pb in isl.buildings:
			var def := Database.building(pb.building_id)
			if def != null and def.is_storage:
				return _bld_center(def, pb)
	return _random_building_pos(isl)

func _random_building_pos(isl: Island) -> Vector2:
	var connected: Array = []
	for pb in isl.buildings:
		if pb.connected:
			connected.append(pb)
	if connected.is_empty():
		return Vector2(isl.width, isl.height) * TILE * 0.5
	var pb = connected[randi() % connected.size()]
	return _bld_center(Database.building(pb.building_id), pb)

func _bld_center(def: BuildingDef, pb: PlacedBuilding) -> Vector2:
	return (Vector2(pb.origin) + Vector2(def.size) * 0.5) * TILE
