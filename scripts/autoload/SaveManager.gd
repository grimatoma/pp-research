class_name SaveManager
extends RefCounted
## JSON save/load for the run. A single versioned blob; mismatched versions are
## discarded rather than migrated (same policy as the puzzleDrag2 reference).
## Offline catch-up is applied inside Sim.from_dict() using the saved timestamp.

const SAVE_PATH := "user://pioneer_isles_save.json"
const META_PATH := "user://pioneer_isles_meta.json"  ## prestige meta, survives New Game+
const SAVE_VERSION := 1

static func save(sim: WorldSim) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: cannot open %s (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "state": sim.to_dict()}))
	f.close()
	return true

## Loads into the given WorldSim. Returns true if a valid save was applied.
static func load_into(sim: WorldSim) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	if int(parsed.get("version", -1)) != SAVE_VERSION:
		return false
	var state: Variant = parsed.get("state", {})
	if not (state is Dictionary):
		return false
	sim.from_dict(state)
	return true

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func clear() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(SAVE_PATH.get_file())

# ── prestige meta (Reputation total; persists across runs / New Game+) ───────────

static func load_reputation() -> int:
	if not FileAccess.file_exists(META_PATH):
		return 0
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return int(parsed.get("reputation", 0))
	return 0

static func save_reputation(total: int) -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"reputation": total}))
		f.close()
