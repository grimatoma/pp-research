class_name RecipeDef
extends RefCounted
## A single production recipe: consume `inputs` and emit `output_qty` of `output`
## every `iteration_time` seconds. Mirrors the data-mined ElQDuck calculator fields
## (CONSUME_PER_ITERATION / PRODUCE_PER_ITERATION / ITERATION_TIME). Single output,
## no byproducts — confirmed by the spec.

var inputs: Dictionary        ## good_id (String) -> amount consumed per iteration (float)
var output: String            ## produced good_id ("" = pure consumer, e.g. a house)
var output_qty: float         ## units produced per iteration
var iteration_time: float     ## real seconds per production iteration

func _init(p_output := "", p_output_qty := 1.0, p_iteration_time := 1.0, p_inputs := {}) -> void:
	output = p_output
	output_qty = p_output_qty
	iteration_time = p_iteration_time
	inputs = p_inputs.duplicate()

## Production rate of the output good in units per second (ignoring input starvation).
func output_per_second() -> float:
	if iteration_time <= 0.0:
		return 0.0
	return output_qty / iteration_time

## Consumption rate of one input good in units per second at full throughput.
func input_per_second(good_id: String) -> float:
	if iteration_time <= 0.0 or not inputs.has(good_id):
		return 0.0
	return float(inputs[good_id]) / iteration_time
