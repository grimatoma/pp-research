class_name PlacedBuilding
extends RefCounted
## A building instance placed on an island. Holds the runtime state the Sim mutates:
## production progress, resident count (houses), and connectivity/active flags.

var building_id: String
var origin: Vector2i           ## top-left tile of the footprint
var progress: float = 0.0      ## seconds accumulated toward the next production iteration
var residents: int = 0         ## houses only
var tier_id: String = ""       ## houses only — current population tier (cascades upward)
var connected: bool = false    ## within range of a storage building?
var active: bool = false       ## produced/consumed on the most recent tick (for UI)
var unmet_time: float = 0.0    ## seconds basics have gone unmet (drives emigration)
var satisfied_time: float = 0.0 ## seconds all needs met at max residents (drives upgrade)
var level: int = 0             ## upgrade stage (the Palace: 0 = Foundation … 5 = complete)

func _init(p_building_id := "", p_origin := Vector2i.ZERO) -> void:
	building_id = p_building_id
	origin = p_origin

func to_dict() -> Dictionary:
	return {
		"building_id": building_id,
		"origin": [origin.x, origin.y],
		"progress": progress,
		"residents": residents,
		"tier_id": tier_id,
		# Persist the hysteresis timers so a save/load mid-cycle resumes faithfully
		# (otherwise frequent autosaves would reset progress toward grow/emigrate).
		"unmet_time": unmet_time,
		"satisfied_time": satisfied_time,
		"level": level,
	}

static func from_dict(d: Dictionary) -> PlacedBuilding:
	var pb := PlacedBuilding.new()
	pb.building_id = String(d.get("building_id", ""))
	var o: Array = d.get("origin", [0, 0])
	pb.origin = Vector2i(int(o[0]), int(o[1]))
	pb.progress = float(d.get("progress", 0.0))
	pb.residents = int(d.get("residents", 0))
	pb.tier_id = String(d.get("tier_id", ""))
	pb.unmet_time = float(d.get("unmet_time", 0.0))
	pb.satisfied_time = float(d.get("satisfied_time", 0.0))
	pb.level = int(d.get("level", 0))
	return pb
