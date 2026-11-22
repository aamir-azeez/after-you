extends SceneTree
## Fog Marsh's stamp desk (core/journey/fog_marsh_catalog.gd _desk), played live:
## a pip carrying the pipsport walks to the desk's ring (the band the game
## counts a put down in, kit/pieces/socket.gd desk()), sets it down there, and
## the goal's rules hold once the home lantern is lit; the desk is never
## counted anywhere the ring is not (anywhere short of it).
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/fog_marsh_catalog.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")
const Solid = preload("res://core/solid_footprint.gd")
const CHECKPOINT := "res://tests/fixtures/journey/catch-the-pipsport-checkpoint.json"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var definition: Dictionary = Catalog.definition()
	var checkpoint: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT))
	var desk := CarriedItems.spot(definition, "desk")
	var stage: Dictionary = definition.stages[2]
	_check(checkpoint is Dictionary and not desk.is_empty(), "The stage's start checkpoint and the desk spot exist")
	var ring := Vector2(desk.position_cm[0], desk.position_cm[1])
	_check(CarriedItems.wanted(stage, "desk") == "pipsport", "The goal wants the pipsport at the desk")
	var mid := (float(int(desk.solid.radius_cm) + Solid.BODY_CM) / 100.0 + SocketKit.reach(desk)) * 0.5
	_check(is_equal_approx(SocketKit.reach(desk), float(desk.radius_cm) / 100.0) and mid > float(desk.solid.radius_cm + Solid.BODY_CM) / 100.0 and mid < SocketKit.reach(desk), "The ring is drawn between the desk's body and its reach")
	_check(SocketKit.rest_height("desk") > 0.6 and SocketKit.drawn_radius("desk", desk) > mid, "An item rests on the desk's top and the ring reaches past its middle")
	# Standing on the drawn ring, a pip carrying the pipsport sets it down on the desk.
	var sim := _start(definition, checkpoint, [11272, 300])
	_go(sim, [int(ring.x + mid * 100.0), int(ring.y)])
	_check(sim.context_action().id == "put", "On the ring the pip may put the pipsport down (%s)" % str(sim.context_action()))
	_tap(sim)
	var rested: Dictionary = sim._mechanisms.items.pipsport
	_check(rested.holder == "" and rested.spot == "desk" and rested.surface_id == "office" and int(rested.height) == 192, "It rests at the desk on the office floor: %s" % [rested])
	_check(Seven.predicate({"item_id": "pipsport", "spot_id": "desk"}, stage, sim._players, sim._mechanisms), "The goal's desk term holds")
	var when: Dictionary = stage.goal_policy.when
	_check(not Seven.predicate(when, stage, sim._players, sim._mechanisms), "The goal still waits for the home lantern")
	_go(sim, [11440, 554])
	_tap(sim)
	_check(bool(sim._mechanisms.levers.get("home-lantern", false)) and Seven.predicate(when, stage, sim._players, sim._mechanisms), "With the lantern lit the goal's rules hold: %s" % [sim._mechanisms.levers])
	# Anywhere short of the ring it lies loose, and anywhere short of it counts for nothing.
	for at: Array in [[11272, 300], [11110, 620], [11450, 300]]:
		var other := _start(definition, checkpoint, at)
		_tap(other)
		_check(other._mechanisms.items.pipsport.spot != "desk", "Put down at %s it does not count at the desk" % [at])
	print("FOG MARSH DESK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A sim of the carry-it-home stage with the live pip (carrying the pipsport) put on the office floor at `at`.
func _start(definition: Dictionary, checkpoint: Dictionary, at: Array) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = int(definition.simulation_version)
	sim.packed_recordings = true
	sim._reset_trusted(definition, "carry-it-home", checkpoint, {}, "a", [])
	var player: Dictionary = sim._players[sim.active_slot]
	player.x = at[0]
	player.z = at[1]
	player.height = 192
	player.surface_id = "office"
	sim._mechanisms.items.pipsport = CarriedItems.held(str(sim.active_slot))
	return sim

func _go(sim: RefCounted, target: Array) -> void:
	for axis: String in ["z", "x"]:
		var stuck := 0
		for _step in range(400):
			var player: Dictionary = sim._players[sim.active_slot]
			var distance := int(target[0 if axis == "x" else 1]) - int(player[axis])
			if absi(distance) <= 1: break
			var before := Vector2i(int(player.x), int(player.z))
			sim.step({"move_" + axis: clampf(float(distance) / 8.0, -1.0, 1.0)})
			var after: Dictionary = sim._players[sim.active_slot]
			stuck = stuck + 1 if Vector2i(int(after.x), int(after.z)) == before else 0
			if stuck >= 3: break

func _tap(sim: RefCounted) -> void:
	sim.step({})
	sim.step({"interact": true})

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
