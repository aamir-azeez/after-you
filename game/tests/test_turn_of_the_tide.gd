extends SceneTree
## turn-of-the-tide@1 under its pinned rules 9: the definition, the registry
## row, the LOW history and its three stage-2 ways with real inputs, the
## latest receiver, and the native contract fixtures for the backend.
## HALF and HIGH ways: test_turn_of_the_tide_ways. Stage-1 hybrids and
## misplays: test_turn_of_the_tide_history. Commit, budget and latch limits:
## test_turn_of_the_tide_limits. Graph witnesses: test_turn_of_the_tide_reach.
##
## Tick figures from an independent axis-walk model are upper bounds and are
## asserted as such; exact figures (budgets, presses) are asserted exactly.
##
## Fixtures change with the definition. Regenerate them, then review the diff:
##   $env:AFTER_YOU_WRITE_FIXTURES = "<absolute path to game/tests/fixtures/journey>"
##   run-godot-suites-isolated.ps1 ... -Suites turn_of_the_tide
##   Remove-Item Env:AFTER_YOU_WRITE_FIXTURES
## (AFTER_YOU_WRITE_FIXTURES=1 writes to res://tests/fixtures/journey/.)
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const DIRECTORY := "res://tests/fixtures/journey/"
const WRITE_ENV := "AFTER_YOU_WRITE_FIXTURES"
const RULES := 9
## Ticks the latest receiver waits at the kept boom before draining.
const LINGER := 60
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}
var exported: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	_definition()
	_registry()
	var first := _stage_one()
	if not first.is_empty():
		_ways(first.checkpoint)
		_latest(first.checkpoint)
	_fixtures()
	for line: String in mismatches: print("MODEL MISMATCH " + line)
	print("TURN OF THE TIDE: %d checks, %d failures, %d model mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

func _definition() -> void:
	_check(not level.is_empty() and Catalog.known(level) and level.id == "turn-of-the-tide" and level.version == 1, "A known version 1 definition")
	_check(level.schema_version == 7 and level.simulation_version == 9 and not level.premium, "Schema 7, pinned to rules 9, free")
	_check(level.stages.size() == 2 and level.stages[0].id == Witness.SET and level.stages[1].id == Witness.SLACK, "Two stages: set-the-tide then slack-water")
	_check(level.stages[0].first_player_slot == "p0" and level.stages[1].first_player_slot == "p1", "The roles swap between the stages")
	_check(level.islands.size() == 20 and level.stairs.size() == 10 and level.bridges.size() == 26, "20 islands, 10 stairs, 26 bridges")
	_check(Canonical.same(initial.mechanisms.controls, {"tide":"low","winch":"stowed","lock":"west","chamber":"half","basin":"shut"}) and initial.mechanisms.levers.is_empty(), "The checkpoint starts at low tide, stowed winch, west lock, half chamber, shut sea and no levers")
	for id: String in ["tide", "lock"]:
		_check(Canonical.same(_control(0, id), _control(1, id)), "The repeated %s entry is identical in both stages" % id)
	_check(Simulation.pinned_rules(level) == RULES and Simulation.rules_allowed(level, 9) and not Simulation.rules_allowed(level, 8) and not Simulation.rules_allowed(level, 7), "The definition plays rules 9 and nothing else")
	for rules: int in [7, 8]:
		_check(not Simulation.new().reset(level, Witness.SET, initial, {}, "a", rules), "A rules %d turn is refused" % rules)
	_check(Canonical.same(Catalog.definition("turn-of-the-tide"), level) and Catalog.KEYS.has(Witness.KEY), "The bare id and the key name the same catalog entry")
	var reset := Simulation.new()
	_check(reset.reset(level, Witness.SET, initial, {}, "a") and reset.simulation_version == RULES, "A fresh turn falls back to the pinned rules")

func _registry() -> void:
	var key: String = Registry.TURN_OF_THE_TIDE
	_check(key == Witness.KEY and key in Registry.keys() and Registry.keys()[-1] == key, "The chapter is registered last")
	_check(key not in Registry.UNRELEASED and key in Registry.offered_keys() and Registry.offered_keys()[-1] == key and Registry.offered_key(key) == key, "The chapter is offered")
	# Solo lists free chapters first in registry order, so the tide follows the well.
	var free: Array[String] = []
	for offered: String in Registry.offered_keys():
		if not Registry.descriptor(offered).premium: free.append(offered)
	_check(free.find(key) == free.find(Registry.WISHING_WELL) + 1 and free[-1] == key, "Among the free chapters it comes straight after The Wishing Well")
	_check(Registry.is_journey(key) and Registry.is_cooperative(key) and Registry.simulation_script(key) == Simulation, "It plays on the journey facade")
	_check(Registry.supported_rules(key) == [9] and Registry.preferred_rules(key) == 9, "The registry supports exactly rules 9")
	var descriptor := Registry.descriptor(key)
	_check(not descriptor.premium and descriptor.simulation_version == 9 and descriptor.recording_version == 7 and descriptor.stage_count == 2, "Free, rules 9, schema 7 recordings, two stages")
	_check(descriptor.local_path == "user://turn-of-the-tide-journey-v1.json" and descriptor.definition_hash == Canonical.digest(level), "Its own journal and the exact definition hash")
	_check(descriptor.title == level.title and not str(descriptor.summary).is_empty() and not str(descriptor.completion_text).is_empty(), "Its own title, summary and completion, not the Rolling Home fallback")
	_check(descriptor.summary != Registry.descriptor(Registry.ROLLING_HOME).summary, "The descriptor does not fall through to the Rolling Home summary")
	_check(Registry.resolve(descriptor) == key and Canonical.same(Registry.initial_checkpoint(key), initial), "The descriptor resolves and the registry starts from the catalog checkpoint")
	_check(Registry.solo_scene(key) == "res://turn_of_the_tide.tscn", "The solo scene path")
	for stage: Dictionary in level.stages:
		var shown := Registry.stage_presentation(key, stage)
		_check(shown.title == stage.title and shown.hint_a == stage.hint_a and shown.hint_b == stage.hint_b, "Stage presentation for " + stage.id)

func _stage_one() -> Dictionary:
	var probe := func(name: String, sim: RefCounted) -> void:
		if name == "bell":
			_check(sim.context_action().label == "Ring bell" and sim.snapshot().objective_display.label == "Bell", "Stage one keeps the bell labels")
	var b_ops: Array = Witness.b_routes()["low"].duplicate()
	b_ops.insert(b_ops.size() - 1, ["?", "bell"])
	var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()["low"], b_ops, true, probe)
	_check(pair.error.is_empty(), "Stage one LOW pair derives: " + str(pair.error))
	if not pair.error.is_empty(): return {}
	var a: RefCounted = pair.a_sim
	var b: RefCounted = pair.b_sim
	_check(a.source_budget_ticks() == Witness.MODEL_STAGE_ONE.budget.low and a._hold_start <= Witness.MODEL_STAGE_ONE.deadline.low and a.receiver_deadline() == 1200, "Low branch budget 460, held before its deadline 739")
	_check(pair.a.simulation_version == RULES and pair.a.level_version == 1 and pair.a.stage_version == 1 and pair.b.simulation_version == RULES, "Both turns record rules 9, level 1, stage 1")
	_upper("stage 1 low A ticks", pair.a.duration_ticks, Witness.MODEL_STAGE_ONE.a_ticks.low)
	_upper("stage 1 low B real ticks", Witness.active_ticks(b), Witness.MODEL_STAGE_ONE.b_real.low)
	_check(b.tick <= a._hold_start + a.source_budget_ticks(), "B finishes inside the budget it was promised")
	var cp: Dictionary = pair.checkpoint
	_check(cp.players.p0.surface_id == "wheel-step" and cp.players.p1.surface_id == "r-terrace", "A waits on the wheel step; B rang from the rock terrace")
	_check(cp.mechanisms.controls.tide == "low" and cp.mechanisms.controls.winch == "slip" and cp.mechanisms.levers.get("sluice", false), "LOW history: low tide, winch on SLIP, sluice on")
	for route: String in ["wheel-step", "sand-1", "slipway"]:
		_check(route in cp.mechanisms.latched_bridges, "LOW history keeps " + route)
	print("TIDE stage1 low A=%d ready=%d budget=%d B=%d B-real=%d" % [pair.a.duration_ticks, a._hold_start, a.source_budget_ticks(), pair.b.duration_ticks, Witness.active_ticks(b)])
	exported["set-the-tide"] = pair
	return pair

func _ways(start: Dictionary) -> void:
	var probe := func(name: String, sim: RefCounted) -> void:
		if name == "lantern":
			_check(sim.context_action().id == "ring" and sim.context_action().label == "Light lantern" and sim.snapshot().objective_display.label == "Lantern", "Stage two shows the lantern labels")
	for way: String in ["boom", "sea-lock", "punt"]:
		var p0_ops: Array = Witness.p0_way("low", way)
		p0_ops.insert(p0_ops.size() - 1, ["?", "lantern"])
		var pair := Witness.pair(level, Witness.SLACK, start, Witness.p1_home("low") + Witness.p1_way("low", way), p0_ops, true, probe)
		_check(pair.error.is_empty(), "LOW %s pair derives: %s" % [way, pair.error])
		if not pair.error.is_empty(): continue
		for item: Array in Witness.cell_checks("low", way, pair): _check(item[0], item[1])
		for item: Array in Witness.cell_ticks("low", way, pair): _upper(item[0], item[1], item[2])
		print("TIDE LOW %s p1=%d ready=%d budget=%d p0=%d p0-real=%d presses p1=%d p0=%d" % [way, pair.a.duration_ticks, pair.a_sim._hold_start, pair.a_sim.source_budget_ticks(), pair.b.duration_ticks, Witness.active_ticks(pair.b_sim), Witness.count_presses(pair.a_sim), Witness.count_presses(pair.b_sim)])
		exported[way] = pair
	if exported.has("sea-lock"):
		_check(Simulation.verify_checkpoint(level, Witness.json(exported["sea-lock"].checkpoint)).valid, "The final recursive proof verifies after a JSON round trip")

## The latest p1 commit for the boom after LOW, and a p0 who lingers at the
## boom and finishes past 900.
func _latest(start: Dictionary) -> void:
	var p1_ops: Array = Witness.p1_home("low") + Witness.p1_way("low", "boom")
	var base := Witness.source(level, Witness.SLACK, start, p1_ops, 0, Callable(), true)
	var delay: int = base.receiver_deadline() - 1 - base.source_budget_ticks() - base._hold_start
	_check(base.can_commit() and delay >= 0, "LOW boom has room to start later")
	if delay < 0: return
	var p0_ops: Array = Witness.p0_way("low", "boom")
	for index in range(p0_ops.size()):
		if str(p0_ops[index]) == str(["u", "route:boom-jetty"]):
			p0_ops.insert(index + 1, ["n", LINGER])
			break
	var pair := Witness.pair(level, Witness.SLACK, start, p1_ops, p0_ops, true, Callable(), delay)
	_check(pair.error.is_empty(), "The latest LOW boom pair derives: " + str(pair.error))
	if not pair.error.is_empty(): return
	var a: RefCounted = pair.a_sim
	_check(a._hold_start + a.source_budget_ticks() == a.receiver_deadline() - 1, "The latest admitted hold is real")
	_check(pair.b.duration_ticks > 900 and pair.b_sim.tick <= a._hold_start + a.source_budget_ticks(), "The lingering receiver finishes past 900 ticks and inside its budget (%d)" % pair.b.duration_ticks)
	var late := Witness.source(level, Witness.SLACK, start, p1_ops, delay + 1, Callable(), true)
	_check(not late.can_commit() and late.commit_reason() == "Try again with more time left for your partner.", "One tick later is refused with the soft-fail reason (%s)" % late.commit_reason())
	print("TIDE latest boom p1=%d ready=%d budget=%d p0=%d" % [pair.a.duration_ticks, a._hold_start, a.source_budget_ticks(), pair.b.duration_ticks])
	exported["latest"] = pair

## Contract fixtures for the backend: written only on request, then compared.
func _fixtures() -> void:
	# Stage files carry the stage id, as every version-1 chapter's do (the
	# chapter exit and presence suites load them by that name).
	var files: Dictionary = {"turn-of-the-tide-definition": level, "turn-of-the-tide-initial-checkpoint": initial}
	for name: Array in [["set-the-tide", "set-the-tide"], ["sea-lock", "slack-water"], ["boom", "slack-water-boom"], ["punt", "slack-water-punt"], ["latest", "slack-water-latest"]]:
		if not exported.has(name[0]): continue
		for part: String in ["a", "b", "checkpoint"]:
			files["%s-%s" % [name[1], part]] = exported[name[0]][part]
	if exported.has("sea-lock"): files["turn-of-the-tide-final-checkpoint"] = exported["sea-lock"].checkpoint
	_check(files.size() == 18, "Every contract fixture has evidence")
	var target := OS.get_environment(WRITE_ENV)
	for name: String in files:
		var path: String = DIRECTORY + name + ".json"
		if not target.is_empty() and failures == 0:
			var out := path if target == "1" else target.path_join(name + ".json")
			var file := FileAccess.open(out, FileAccess.WRITE)
			file.store_string(JSON.stringify(files[name], "\t", true) + "\n")
			file.close()
			print("WROTE " + out)
			continue
		_check(Canonical.same(Witness.json(files[name]), _load(path)), "Fixture matches fresh real-input evidence: " + name)

func _control(stage_index: int, id: String) -> Dictionary:
	for control: Dictionary in level.stages[stage_index].controls:
		if control.id == id: return control
	return {}

func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}

## A model figure that bounds the native walk from above.
func _upper(label: String, native: int, model: int) -> void:
	print("MODEL %s native=%d model=%d delta=%d" % [label, native, model, native - model])
	if native > model: mismatches.append("%s: native %d > model %d" % [label, native, model])
	_check(native <= model, "%s: native %d within the model bound %d" % [label, native, model])

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
