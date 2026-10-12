extends SceneTree
## long-way-home@2: the finale's three ways to win and their recoveries, with
## real inputs under its pinned rules 9, plus the backend contract fixtures.
## Refusals, latest openings and carried poses: test_long_way_home_v2_limits.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/long_way_home_v2_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const RULES := 9
const DIRECTORY := "res://tests/fixtures/journey/"
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var exported: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	_check(not level.is_empty() and Catalog.known(level) and level.version == 2 and level.simulation_version == 9, "@2 is a known version 2 definition pinned to rules 9")
	var first := _pair(Witness.PATH, initial, Witness.S1A, Witness.S1B, "stage one")
	if not first.is_empty():
		_check(first.a.duration_ticks == 332 and first.b.duration_ticks == 332, "Stage one plays exactly as in @1")
		exported["the-path-you-leave"] = first
		var start: Dictionary = first.checkpoint
		_ways(start)
		_latest(start, "w2-rose")
		_rules_eight_alias(start)
	_fixtures()
	print("LONG WAY HOME V2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _ways(start: Dictionary) -> void:
	var probe := func(name: String, sim: RefCounted) -> void:
		if name == "dark":
			_check(sim.context_action().id == "ring" and not sim.context_action().enabled, "With the shutter down the second window stays dark")
		elif name == "shut":
			_check(not sim.walkable_at(1152, 352) and not sim.snapshot().bridges["garden-door"], "A gate that does not match the lamp keeps the garden door shut")
	var ticks: Dictionary = {}
	for way: String in Witness.WAYS:
		var routes: Array = Witness.WAYS[way]
		var pair := _pair(Witness.PLACE, start, Witness.A_WAYS[routes[0]], Witness.B_WAYS[routes[1]], way, probe)
		if pair.is_empty(): continue
		ticks[way] = pair.b.duration_ticks
		var final: Dictionary = pair.checkpoint
		_check(Simulation.verify_checkpoint(level, _json(final)).valid, "Final recursive proof verifies after a JSON round trip: " + way)
		var latched: Array = final.mechanisms.latched_bridges
		var controls: Dictionary = final.mechanisms.controls
		if routes[1].begins_with("porch"):
			_check("near-crossing" in latched and "porch-door" in latched and controls["porch-shutter"] == "up", "The porch way keeps its door and ends with the shutter up: " + way)
		else:
			_check("garden-arch" in latched and "garden-door" in latched and controls["walk-gate"] == controls["hall-lamp"], "The garden way ends with the gate matching the lamp: " + way)
		_check(final.players.p0.surface_id == "home-room" and final.players.p1.surface_id == "home-room", "Both end inside the house: " + way)
		if way in ["w1", "w2-moss"]: exported[way] = pair
	if ticks.size() == Witness.WAYS.size():
		_check(ticks["w1-naive"] >= ticks["w1"] + 100, "Missing the shutter costs a real walk back")
		_check(ticks["w2-wrong"] >= ticks["w2-moss"] + 60, "A wrong gate colour costs a real walk back")
		_check(ticks["w1"] > 203 and ticks["w2-rose"] > 203, "Both clever finales are longer than the @1 porch branch")

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
		if derived.valid and way == "w2-rose": exported["latest"] = {"a": first, "b": second, "checkpoint": derived.checkpoint}
	var late := Witness.source(level, Witness.PLACE, start, Witness.A_WAYS[routes[0]], RULES, delay + 1)
	_check(not late.can_commit(), way + ": one tick later is refused")
	print("LWH2 latest %s A=%d ready=%d budget=%d B=%d" % [way, delayed.tick, delayed._hold_start, delayed.source_budget_ticks(), b.tick])

## Rules 9 is rules 8 under a new number: an unpinned copy played under rules 8
## from the same start reaches the same ticks, poses, controls and latches.
func _rules_eight_alias(start: Dictionary) -> void:
	var unpinned := level.duplicate(true)
	unpinned.simulation_version = 7
	for way: String in ["w1", "w2-wrong", "w3-garden"]:
		var routes: Array = Witness.WAYS[way]
		var results: Array = []
		for rules: int in [8, 9]:
			var definition: Dictionary = unpinned if rules == 8 else level
			var a := Simulation.new()
			a.simulation_version = rules
			a._reset_trusted(definition, Witness.PLACE, start, {}, "a")
			Witness.play(a, Witness.A_WAYS[routes[0]])
			var b := Simulation.new()
			b.simulation_version = rules
			b._reset_trusted(definition, Witness.PLACE, start, a.export_recording(), "b")
			Witness.play(b, Witness.B_WAYS[routes[1]])
			while not b.finished and b.snapshot().get("objective_done", false): b.step({})
			var shot: Dictionary = b.snapshot()
			results.append({"a": [a.tick, a._hold_start, a.source_budget_ticks(), a.can_commit()], "b": [b.tick, b.complete], "players": shot.players, "controls": shot.controls, "routes": shot.route_progress.entered_routes})
		_check(Canonical.same(results[0], results[1]), "Rules 9 plays exactly like rules 8: " + way)
	_check(not Simulation.new().reset(level, Witness.PATH, initial, {}, "a", 8) and not Simulation.new().reset(level, Witness.PATH, initial, {}, "a", 7), "@2 refuses rules 7 and 8 turns")

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

## Contract fixtures for the backend. Written only on request, then compared.
func _fixtures() -> void:
	var files: Dictionary = {"long-way-home-v2-definition": level, "long-way-home-v2-initial-checkpoint": initial}
	# Stage-id names follow the chapter fixture convention; the porch way is the default final.
	for name: Array in [["the-path-you-leave", "the-path-you-leave"], ["w1", "a-place-beside-you"], ["w2-moss", "garden"], ["latest", "latest"]]:
		if not exported.has(name[0]): continue
		for part: String in ["a", "b", "checkpoint"]:
			files["long-way-home-v2-%s-%s" % [name[1], part]] = exported[name[0]][part]
	if exported.has("w1"): files["long-way-home-v2-final-checkpoint"] = exported.w1.checkpoint
	_check(files.size() == 15, "Every contract fixture has evidence")
	var write: bool = "--write-fixtures" in OS.get_cmdline_user_args()
	for name: String in files:
		var path: String = DIRECTORY + name + ".json"
		if write and failures == 0:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify(files[name], "\t", true) + "\n")
			file.close()
		_check(Canonical.same(_json(files[name]), _load(path)), "Fixture matches fresh real-input evidence: " + name)

func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
