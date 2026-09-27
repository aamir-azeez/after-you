extends SceneTree
## Published simulation6 fixtures are the executable compatibility contract for
## the shared physical runtime. The exhaustive old/new comparison stays private.
const Simulation=preload("res://core/cooperative/simulation.gd")
const Catalog=preload("res://core/cooperative/stage_catalog.gd")
const Canonical=preload("res://core/v2/canonical.gd")
var checks:=0
var failures:=0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for key: String in ["high-and-low","rolling-home","a-house-for-two"]:
		_chapter(key)
	print("AFTER YOU PHYSICAL RUNTIME: %d checks, %d failures" %[checks,failures])
	quit(1 if failures else 0)

func _chapter(key: String) -> void:
	var level:=Catalog.definition(key)
	var checkpoint:=_fixture(key+"-initial-checkpoint")
	_check(Simulation.verify_checkpoint(level,checkpoint).valid,"Published initial checkpoint admitted: "+key)
	for stage: Dictionary in level.stages:
		var first:=_fixture(stage.id+"-a")
		var second:=_fixture(stage.id+"-b")
		for role: String in ["a","b"]:
			var record: Dictionary=first if role=="a" else second
			var prior: Dictionary={} if role=="a" else first
			var live:=Simulation.new()
			live.catch_assistance=bool(record.catch_assistance)
			_check(live.reset(level,stage.id,checkpoint,prior,role),"Published input replay starts: "+stage.id+"/"+role)
			_check(live.get_script()==Simulation,"Live instance retains public chapter facade identity")
			if role=="b": _check(live._source.get_script()==Simulation,"Source ghost uses the same sealed public facade")
			var expected_checks: Dictionary={}
			for check: Dictionary in record.replay_checks: expected_checks[int(check.tick)]=str(check.state_hash)
			for frame: Dictionary in Simulation.expand_recording_inputs(record):
				live.step(frame)
				if expected_checks.has(live.tick): _check(live.state_hash()==expected_checks[live.tick],"Retained intermediate deterministic hash: "+stage.id+"/"+role+"/"+str(live.tick))
			_check(Canonical.same(live.export_recording(),record),"Exact published recording and outcome shape retained")
			_check(Simulation.verify_recording(level,record,checkpoint,prior).valid,"Static verifier dispatches to matching facade")
		var derived:=Simulation.derive_checkpoint(level,checkpoint,first,second)
		_check(derived.valid,"Native pair derives a checkpoint through the shared proof helper")
		if not derived.valid: return
		checkpoint=derived.checkpoint
	_check(Canonical.same(checkpoint,_fixture(key+"-final-checkpoint")),"Published final checkpoint and complete recursive proof stay byte-identical")
	var altered:=checkpoint.duplicate(true)
	altered.mechanisms.levers["unearned-route"]=true
	altered.checkpoint_hash=Catalog.checkpoint_hash(altered)
	_check(not Simulation.verify_checkpoint(level,altered).valid,"Recomputed outer hash cannot forge a mechanism result")
	altered=checkpoint.duplicate(true)
	altered.stage_index=3
	altered.checkpoint_hash=Catalog.checkpoint_hash(altered)
	_check(not Simulation.verify_checkpoint(level,altered).valid,"Proof remains bounded to the authored two stages")
	var unknown:=level.duplicate(true)
	unknown.simulation_version=7
	_check(not Simulation.verify_checkpoint(unknown,checkpoint).valid,"Checkpoint metadata cannot select a later simulation/catalog")
	var foreign_record:=_fixture(level.stages[0].id+"-a")
	foreign_record.simulation_version=7
	foreign_record.recording_hash=Simulation.recording_hash(foreign_record)
	_check(Simulation.recording_error(level,foreign_record,_fixture(key+"-initial-checkpoint"))=="Unsupported recording version.","Version rejection remains exact before replay")

func _fixture(name: String) -> Dictionary:
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/"+name+".json"))
	return value if value is Dictionary else {}

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
