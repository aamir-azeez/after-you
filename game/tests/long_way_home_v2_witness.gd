extends RefCounted
## Real input routes for long-way-home@2. No state injection.
## "w" walks x then z, "t" taps the action, "n" waits, "?" calls the probe.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const KEY := "long-way-home@2"
const PATH := "the-path-you-leave"
const PLACE := "a-place-beside-you"

const S1A := [["w",[-320,0]],["w",[64,0]],["w",[64,64]],["t"],["w",[64,0]],["w",[-320,0]],["w",[-320,-240]],["w",[480,-240]],["w",[560,-240]],["w",[560,32]],["w",[640,32]]]
const S1B := [["w",[-416,272]],["w",[-16,272]],["w",[128,224]],["t"],["w",[128,80]],["w",[512,80]],["w",[640,80]],["w",[640,224]],["t"]]
# Stage one ends off-centre: A detours through HOME first and stops 32 cm east,
# then idles; B rings 16 cm south of the window centre.
const S1A_OFF := [["w",[-320,0]],["w",[64,0]],["w",[64,64]],["w",[128,80]],["w",[640,80]],["w",[640,32]],["w",[352,80]],["w",[352,-240]],["w",[-320,-240]],["w",[-320,0]],["w",[64,0]],["w",[64,64]],["t"],["w",[64,0]],["w",[-320,0]],["w",[-320,-240]],["w",[480,-240]],["w",[560,-240]],["w",[560,32]],["w",[672,32]],["n",80]]
const S1B_OFF := [["w",[-416,272]],["w",[-16,272]],["w",[128,224]],["t"],["w",[128,80]],["w",[512,80]],["w",[640,80]],["w",[640,240]],["t"]]

const A_WAYS := {
	# W1: hold the porch window with the lamp off.
	"w1": [["w",[704,224]],["w",[704,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,32]]],
	# W2: light the lamp (one tap rose, two taps moss), then wait at the garden window.
	"w2-rose": [["w",[704,224]],["w",[704,-16]],["w",[944,-16]],["w",[944,-96]],["t"],["w",[944,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,144]]],
	"w2-moss": [["w",[704,224]],["w",[704,-16]],["w",[944,-16]],["w",[944,-96]],["t"],["t"],["w",[944,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,144]]],
	# W3: light the lamp rose and hold the porch window.
	"w3": [["w",[704,224]],["w",[704,-16]],["w",[944,-16]],["w",[944,-96]],["t"],["w",[944,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,32]]],
}

const B_WAYS := {
	# Lower the shutter, touch the open door so it stays, raise it again, go in.
	"porch": [["w",[704,224]],["w",[960,224]],["t"],["w",[1016,224]],["w",[960,224]],["t"],["w",[1168,224]],["w",[1408,224]],["w",[1408,96]],["t"]],
	# Walk in with the shutter down, find the window dark, go back and raise it.
	"porch-naive": [["w",[704,224]],["w",[960,224]],["t"],["w",[1168,224]],["w",[1408,224]],["w",[1408,96]],["?","dark"],["t"],["w",[1408,224]],["w",[960,224]],["t"],["w",[1168,224]],["w",[1408,224]],["w",[1408,96]],["t"]],
	"garden-rose": [["w",[736,32]],["w",[736,288]],["w",[736,448]],["w",[800,448]],["t"],["w",[1152,448]],["w",[1152,272]],["w",[1408,272]],["w",[1408,96]],["t"]],
	"garden-moss": [["w",[736,32]],["w",[736,288]],["w",[736,448]],["w",[800,448]],["t"],["t"],["w",[1152,448]],["w",[1152,272]],["w",[1408,272]],["w",[1408,96]],["t"]],
	# Rose against a moss lamp: the far door stays shut; walk back and fix it.
	"garden-wrong": [["w",[736,32]],["w",[736,288]],["w",[736,448]],["w",[800,448]],["t"],["w",[1152,448]],["?","shut"],["w",[800,448]],["t"],["w",[1152,448]],["w",[1152,272]],["w",[1408,272]],["w",[1408,96]],["t"]],
}

## Way name -> [A route, B route].
const WAYS := {
	"w1": ["w1","porch"],
	"w1-naive": ["w1","porch-naive"],
	"w2-rose": ["w2-rose","garden-rose"],
	"w2-moss": ["w2-moss","garden-moss"],
	"w2-wrong": ["w2-moss","garden-wrong"],
	"w3-porch": ["w3","porch"],
	"w3-garden": ["w3","garden-rose"],
}

static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary, ops: Array, rules: int, delay: int = 0) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level,stage_id,checkpoint,{},"a",rules): return sim
	Walk.wait_ticks(sim,delay)
	play(sim,ops)
	return sim

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, ops: Array, rules: int, probe: Callable = Callable()) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level,stage_id,checkpoint,first,"b",rules): return sim
	play(sim,ops,probe)
	# A fast receiver still waits out the recorded source.
	for _tick in range(Simulation.MAX_TICKS+300):
		if sim.finished or not sim._objective: break
		sim.step({})
	return sim

static func play(sim: RefCounted, ops: Array, probe: Callable = Callable()) -> void:
	for op: Array in ops:
		if sim.finished or not sim.error.is_empty(): return
		match str(op[0]):
			"w": walk(sim,op[1])
			"t": Walk.tap(sim)
			"n": Walk.wait_ticks(sim,int(op[1]))
			"?": if probe.is_valid(): probe.call(str(op[1]),sim)

## Same inputs as cooperative_witness.walk; reads the live pose directly.
static func walk(sim: RefCounted, destination: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		for _tick in range(Simulation.MAX_TICKS):
			if sim.finished or not sim.error.is_empty(): return
			var distance := int(destination[index]) - int(sim._players[sim.active_slot][axis])
			if absi(distance) <= 1: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / 8.0, -1.0, 1.0)
			sim.step(input)
