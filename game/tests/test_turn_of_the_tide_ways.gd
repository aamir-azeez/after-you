extends SceneTree
## turn-of-the-tide@1: the HALF and HIGH histories and each of their three
## stage-2 ways, played with real inputs under rules 9 and derived through
## the full proof. The LOW history and the fixtures: test_turn_of_the_tide.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	for history: String in ["half", "high"]:
		var first := _history(history)
		if first.is_empty(): continue
		for way: String in ["boom", "sea-lock", "punt"]:
			var pair := Witness.pair(level, Witness.SLACK, first.checkpoint, Witness.p1_home(history) + Witness.p1_way(history, way), Witness.p0_way(history, way), true)
			_check(pair.error.is_empty(), "%s %s pair derives: %s" % [history, way, pair.error])
			if not pair.error.is_empty(): continue
			for item: Array in Witness.cell_checks(history, way, pair): _check(item[0], item[1])
			for item: Array in Witness.cell_ticks(history, way, pair): _upper(item[0], item[1], item[2])
			print("TIDE %s %s p1=%d ready=%d budget=%d p0=%d p0-real=%d presses p1=%d p0=%d" % [history.to_upper(), way, pair.a.duration_ticks, pair.a_sim._hold_start, pair.a_sim.source_budget_ticks(), pair.b.duration_ticks, Witness.active_ticks(pair.b_sim), Witness.count_presses(pair.a_sim), Witness.count_presses(pair.b_sim)])
	for line: String in mismatches: print("PORT MISMATCH " + line)
	print("TURN OF THE TIDE WAYS: %d checks, %d failures, %d port mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

func _history(history: String) -> Dictionary:
	var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[history], Witness.b_routes()[history], true)
	_check(pair.error.is_empty(), "Stage one %s pair derives: %s" % [history, pair.error])
	if not pair.error.is_empty(): return {}
	var a: RefCounted = pair.a_sim
	_check(a._ready_branch == history and a.source_budget_ticks() == Witness.PORT_STAGE_ONE.budget[history] and a._hold_start <= Witness.PORT_STAGE_ONE.deadline[history], "Stage one %s: budget %d, held by tick %d" % [history, Witness.PORT_STAGE_ONE.budget[history], Witness.PORT_STAGE_ONE.deadline[history]])
	_upper("stage 1 %s A ticks" % history, pair.a.duration_ticks, Witness.PORT_STAGE_ONE.a_ticks[history])
	_upper("stage 1 %s B real ticks" % history, Witness.active_ticks(pair.b_sim), Witness.PORT_STAGE_ONE.b_real[history])
	var cp: Dictionary = pair.checkpoint
	var step: String = {"half": "quay-step", "high": "bollard-step"}[history]
	_check(cp.players.p0.surface_id == step and step in cp.mechanisms.latched_bridges and cp.mechanisms.controls.tide == history, "%s history: A on %s at %s water" % [history.to_upper(), step, history])
	if history == "half":
		_check(cp.mechanisms.controls.lock == "east" and cp.mechanisms.levers.get("sluice", false) and "stones-3" in cp.mechanisms.latched_bridges, "HALF history: lock east, sluice on, stones-3 kept")
	else:
		_check(cp.mechanisms.controls.lock == "west" and cp.mechanisms.levers.get("line", false) and "jetty-3" in cp.mechanisms.latched_bridges, "HIGH history: lock west, line on, jetty-3 kept with the bollard held")
	print("TIDE stage1 %s A=%d ready=%d budget=%d B=%d B-real=%d" % [history, pair.a.duration_ticks, a._hold_start, a.source_budget_ticks(), pair.b.duration_ticks, Witness.active_ticks(pair.b_sim)])
	return pair

## A port figure that bounds the native walk from above.
func _upper(label: String, native: int, port: int) -> void:
	print("PORT %s native=%d port=%d delta=%d" % [label, native, port, native - port])
	if native > port: mismatches.append("%s: native %d > port %d" % [label, native, port])
	_check(native <= port, "%s: native %d within the port bound %d" % [label, native, port])

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
