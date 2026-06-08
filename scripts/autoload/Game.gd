extends Node
## The one autoload: owns the live WorldSim, ticks it each frame, and handles
## save/load. Everything testable lives in WorldSim (a plain object); this node is
## just the engine glue (frame timing + persistence + app lifecycle).

var sim: WorldSim

const AUTOSAVE_INTERVAL := 20.0
var _autosave_accum := 0.0

func _ready() -> void:
	sim = WorldSim.new()
	if SaveManager.has_save() and SaveManager.load_into(sim):
		pass  # offline catch-up applied inside from_dict()
	else:
		sim.new_game(1337, [], SaveManager.load_reputation())
	# Persist earned Reputation to the meta layer (survives New Game+).
	sim.reputation_earned.connect(func(total): SaveManager.save_reputation(total))
	# Persist on quit / app backgrounding.
	get_tree().set_auto_accept_quit(false)

func _process(delta: float) -> void:
	if sim == null:
		return
	sim.advance(delta)
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		SaveManager.save(sim)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if sim != null:
			SaveManager.save(sim)
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()

## Start a brand-new run, discarding the current save. Resets the EXISTING WorldSim
## in place so HUD/IslandView signal connections (bound to this instance) stay valid.
## Permanent Reputation carries over from the meta layer.
func restart() -> void:
	SaveManager.clear()
	sim.reset(1337, [], SaveManager.load_reputation())

## Prestige New Game+: restart with the chosen Custodians active. Reputation persists.
func restart_with_custodians(custodians: Array) -> void:
	SaveManager.clear()
	sim.reset(1337, custodians, SaveManager.load_reputation())
