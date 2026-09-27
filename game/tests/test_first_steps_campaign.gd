extends SceneTree
## Current-rule proof for the whole opening chapter; old sim4 fixtures stay frozen.
const Simulation = preload("res://core/first_steps/simulation.gd")
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var level := Catalog.definition()
	var initial := Catalog.initial_checkpoint()
	var lift_a := _fixture("cumulative-lift-a")
	var lift_b := _fixture("cumulative-lift-b")
	var lift := _fixture("cumulative-lift-checkpoint")
	var first := Simulation.derive_checkpoint(level,initial,lift_a,lift_b)
	_check(first.valid and Canonical.same(first.get("checkpoint",{}),lift), "Existing cumulative lift pair derives its unchanged checkpoint")
	_check(lift_a.simulation_version == 5 and lift_b.simulation_version == 5, "Both opening turns use current cumulative rules")
	if not first.valid:
		_finish()
		return
	var pin := {"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":5,"premium":false}
	_check(Protocol.pin_valid(pin), "The proof's chapter and rules match the native campaign registry")
	var source := Simulation.new()
	var source_ready := source.reset(level,"a-place-to-grow",lift,{},"a",5)
	_check(source_ready, "Role-swapped source starts from the actual cumulative checkpoint")
	if not source_ready:
		_finish()
		return
	for input: Dictionary in Simulation.expand_recording_inputs(_fixture("a-place-to-grow-a")): source.step(input)
	var garden_a := source.export_recording()
	_check(source.can_commit() and source.active_slot == "p1" and garden_a.simulation_version == 5, "Current native source performs the saved take/throw/garden route as the second physical player")
	_check(Simulation.verify_recording(level,garden_a,lift).valid, "Fresh source hashes and replay checks verify against sim5")
	var receiver := Simulation.new()
	var receiver_ready := receiver.reset(level,"a-place-to-grow",lift,garden_a,"b",5)
	_check(receiver_ready, "The first physical player receives the newly generated source")
	if not receiver_ready:
		_finish()
		return
	for input: Dictionary in Simulation.expand_recording_inputs(_fixture("a-place-to-grow-b")): receiver.step(input)
	var garden_b := receiver.export_recording()
	_check(receiver.complete and receiver.active_slot == "p0" and garden_b.simulation_version == 5, "Current receiver catches and plants from that precise source")
	_check(Simulation.verify_recording(level,garden_b,lift,garden_a).valid, "Receiver proof verifies with its exact generated source")
	var final := Simulation.derive_checkpoint(level,lift,garden_a,garden_b)
	_check(final.valid, "The complete current-rule chapter derives its native endpoint")
	if not final.valid:
		_finish()
		return
	var checkpoint: Dictionary = final.checkpoint
	_check(checkpoint.next_stage_id == "" and checkpoint.stage_index == 2, "Two accepted pairs finish the chapter")
	_check(Simulation.verify_checkpoint(level,checkpoint).valid, "Full nested current-rule proof independently replays")
	_check(Simulation.verify_checkpoint(level,_fixture("final-checkpoint")).valid, "Retained historical sim4 chapter still verifies")
	_check(Canonical.same(lift,_fixture("cumulative-lift-checkpoint")), "Continuation leaves its accepted initial checkpoint unchanged")
	var generated := {"a":garden_a,"b":garden_b,"checkpoint":checkpoint}
	var writing := "--write-fixtures" in OS.get_cmdline_user_args()
	for key: String in generated:
		var path := "res://tests/fixtures/first_steps/cumulative-garden-"+key+".json"
		if writing:
			_check(not FileAccess.file_exists(path), "New proof never overwrites existing fixture: "+key)
			if failures == 0 and not FileAccess.file_exists(path):
				var file := FileAccess.open(path,FileAccess.WRITE)
				_check(file != null, "New fixture file opens: "+key)
				if file != null:
					file.store_string(JSON.stringify(generated[key],"\t")+"\n")
					file.close()
		else:
			_check(FileAccess.file_exists(path) and Canonical.same(generated[key],_fixture("cumulative-garden-"+key)), "Frozen current-rule fixture equals independently regenerated gameplay: "+key)
	_finish()

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/"+name+".json"))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)

func _finish() -> void:
	print("First Steps campaign proof: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
