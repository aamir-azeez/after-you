extends SceneTree
## long-way-home@2 latest acceptable openings with real inputs under rules 9:
## each way's A turn delayed to the last admitted tick still leaves B a finish,
## and one tick later is refused.
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
		for way: String in ["w1", "w2-moss", "w3-porch", "w3-garden"]: _latest(first.checkpoint, way)
	print("LONG WAY HOME V2 LATEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _latest(start: Dictionary, way: String) -> void:
	var routes: Array = Witness.WAYS[way]
	var base := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS[routes[0]], RULES)
	var delay: int = base.receiver_deadline() - 1 - base.source_budget_ticks() - base._hold_start
	_check(base.can_commit() and delay >= 0 and base.receiver_deadline() == 1200, way + " has usable admission budget under rules 9")
	if delay < 0: return
	var delayed := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS[routes[0]], RULES, delay)
	_check(delayed.can_commit() and delayed._hold_start + delayed.source_budget_ticks() == delayed.receiver_deadline() - 1, way + ": the latest admitted opening is real")
	if not delayed.can_commit(): return
	var first: Dictionary = delayed.export_recording()
	var b := Witness.receiver(level, Witness.PLACE, start, first, Witness.B_WAYS[routes[1]], RULES)
	_check(b.complete and b.tick <= b.receiver_deadline(), way + ": the receiver still finishes from the latest opening")
	if b.complete:
		var second: Dictionary = b.export_recording()
		var derived := Simulation.derive_checkpoint(level, _json(start), _json(first), _json(second))
		_check(derived.valid and second.duration_ticks > 900, way + ": the latest pair, its receiver past 900 ticks, derives after a JSON round trip")
	var late := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS[routes[0]], RULES, delay + 1)
	_check(not late.can_commit(), way + ": one tick later is refused")
	print("LWH2 latest %s A=%d ready=%d budget=%d B=%d" % [way, delayed.tick, delayed._hold_start, delayed.source_budget_ticks(), b.tick])

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
