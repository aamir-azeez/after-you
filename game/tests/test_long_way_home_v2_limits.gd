extends SceneTree
## long-way-home@2 limits with real inputs under rules 9: setups that are not
## ready, routes that stay shut, switching ways and poses carried off-centre
## from stage one. Latest openings: test_long_way_home_v2_latest.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/long_way_home_v2_witness.gd")
const RULES := 9
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	var first := _pair(Witness.PATH, initial, Witness.S1A, Witness.S1B, "stage one")
	if not first.is_empty():
		var start: Dictionary = first.checkpoint
		_not_ready(start)
		_bypass(start)
		_switch_restarts(start)
	_off_centre()
	print("LONG WAY HOME V2 LIMITS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _not_ready(start: Dictionary) -> void:
	var seat := Witness.source(level, Witness.PLACE, start, [["w",[704,224]],["w",[704,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,144]],["n",20]], RULES)
	_check(seat.error.is_empty() and not seat.can_commit(), "The garden window without the lamp is not ready")
	var landing := Witness.source(level, Witness.PLACE, start, [["w",[704,224]],["w",[704,-16]],["w",[944,-16]],["w",[944,-96]],["t"],["n",20]], RULES)
	_check(landing.error.is_empty() and landing.snapshot().controls["hall-lamp"] == "rose" and not landing.can_commit(), "A lit lamp alone, away from the window seat, is not ready")
	var away := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS["w3"] + [["w",[1200,-16]],["w",[1168,-16]],["n",10]], RULES)
	_check(not away.can_commit(), "Leaving the window again is not ready")


func _bypass(start: Dictionary) -> void:
	var a := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS["w1"], RULES)
	var b := Witness.receiver(level, Witness.PLACE, start, a.export_recording(), [["w",[704,224]],["w",[960,224]]], RULES)
	_check(not b.walkable_at(1072, 224) and not b.snapshot().bridges["porch-door"], "Porch way: the door stays shut while the shutter is up")
	_check(not b.walkable_at(736, 352), "Porch way: the garden arch stays shut without a lamp")
	Witness.play(b, [["t"]])
	_check(b.snapshot().bridges["porch-door"], "Porch way: lowering the shutter opens the door")
	var a2 := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS["w2-rose"], RULES)
	var b2 := Witness.receiver(level, Witness.PLACE, start, a2.export_recording(), [["n",200]], RULES)
	_check(not b2.walkable_at(832, 224), "Garden way: the porch crossing stays shut")
	_check(b2.walkable_at(736, 352), "Garden way: the lit lamp opens the garden arch")
	_check(not b2.snapshot().bridges["garden-door"], "Garden way: the door waits for the matching gate")
	var a3 := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS["w3"], RULES)
	var b3 := Witness.receiver(level, Witness.PLACE, start, a3.export_recording(), [["n",200]], RULES)
	_check(b3.walkable_at(832, 224) and b3.walkable_at(736, 352), "Both ways: the porch crossing and the garden arch are both open")


func _switch_restarts(start: Dictionary) -> void:
	var a := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS["w2-rose"], RULES)
	_check(a.can_commit(), "Switch: the garden way is ready first")
	var first_ready: int = a._hold_start
	var gap := false
	for _i in range(40):
		a.step({"move_x": 0.0, "move_z": -1.0})
		gap = gap or a._hold_start < 0
		if int(a.snapshot().players.p1.z) <= 33: break
	_check(gap, "Walking from the seat to the porch window passes a not-ready gap")
	_check(a.can_commit() and a._hold_start > first_ready, "The porch window with the lamp lit starts a new ready interval")
	var both_ready: int = a._hold_start
	Witness.play(a, [["w",[1168,-16]],["w",[944,-16]],["w",[944,-96]],["t"],["t"],["w",[944,-16]],["w",[1168,-16]],["w",[1200,-16]],["w",[1200,32]]])
	_check(a.snapshot().controls["hall-lamp"] == "off" and a.can_commit() and a._hold_start > both_ready, "Turning the lamp off and holding the porch again restarts the budget clock")


func _off_centre() -> void:
	var a := Witness.source(level, Witness.PATH, initial, Witness.S1A_OFF, RULES)
	_check(a.can_commit(), "Off-centre stage one source commits")
	if not a.can_commit(): return
	var first: Dictionary = a.export_recording()
	var b := Witness.receiver(level, Witness.PATH, initial, first, Witness.S1B_OFF, RULES)
	var derived := Simulation.derive_checkpoint(level, initial, first, b.export_recording())
	_check(b.complete and derived.valid, "Off-centre stage one derives")
	if not derived.valid: return
	var start: Dictionary = derived.checkpoint
	_check(start.players.p1.x != 640 or start.players.p0.z != 224, "The carried poses really are off-centre")
	for way: String in ["w1", "w2-rose", "w3-garden"]:
		var routes: Array = Witness.WAYS[way]
		var pair := _pair(Witness.PLACE, start, Witness.A_WAYS[routes[0]], Witness.B_WAYS[routes[1]], way + " off-centre")
		_check(not pair.is_empty(), way + " completes from the off-centre carried poses")

func _pair(stage_id: String, checkpoint: Dictionary, a_ops: Array, b_ops: Array, label: String, probe: Callable = Callable()) -> Dictionary:
	var a := Witness.source(level, stage_id, checkpoint, a_ops, RULES)
	_check(a.error.is_empty() and a.can_commit(), "%s: A can commit (%s %s)" % [label, a.error, a.commit_reason()])
	if not a.can_commit(): return {}
	var first: Dictionary = a.export_recording()
	_check(first.simulation_version == RULES and first.level_version == 2 and first.stage_version == 1, label + ": A records rules 9, level 2, stage 1")
	var b := Witness.receiver(level, stage_id, checkpoint, first, b_ops, RULES, probe)
	_check(b.complete, "%s: B completes (%s)" % [label, b.error])
	if not b.complete: return {}
	var second: Dictionary = b.export_recording()
	var derived := Simulation.derive_checkpoint(level, _json(checkpoint), _json(first), _json(second))
	_check(derived.valid, label + ": the pair derives a checkpoint after a JSON round trip " + str(derived.get("error", "")))
	if not derived.valid: return {}
	print("LWH2 %s A=%d ready=%d budget=%d B=%d" % [label, first.duration_ticks, a._hold_start, a.source_budget_ticks(), second.duration_ticks])
	return {"a": first, "b": second, "checkpoint": derived.checkpoint}

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
