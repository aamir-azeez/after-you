extends SceneTree
## One chapter's own rules suite: the definition is the key's own and its family
## catalog knows it, it plays only the rules its definition pins (9 or later), every stage plays through with real
## inputs (its witness), and every recording and checkpoint verifies on its own.
## With --write-fixtures it also writes the definition, the checkpoints and the
## recorded pairs where its family keeps them (golden_support.gd
## fixture_prefixes), which the manifest and integration suites read.
##
## A chapter's suite (tests/test_<chapter>.gd) extends this file and declares
## Witness, its witness script (chapter_witness.gd).
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const Golden = preload("res://tests/golden_support.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var witness: RefCounted = get_script().get_script_constant_map().Witness.new()
	var key: String = witness.key()
	var level := Registry.definition(key)
	var family := Families.row(str(Index.data(key).get("family", "")))
	_check("%s@%d" % [level.get("id"), int(level.get("version", 0))] == key, "The definition is %s's own" % key)
	var pinned := int(level.get("simulation_version", 0))
	_check(pinned >= 9 and Registry.supported_rules(key).map(func(rules: Variant) -> int: return int(rules)) == [pinned], "%s plays rules %d and no other" % [key, pinned])
	_check(not family.is_empty() and load(family.initial[0]).known(level), "The family catalog knows the definition, so proofs accept it")
	var evidence: Dictionary = witness.chapter()
	_check(evidence.error.is_empty(), "Every stage plays through with real inputs: " + str(evidence.error))
	if evidence.error.is_empty():
		_verify(key, level, evidence)
		if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args(): _write_fixtures(key, level, evidence)
	print("%s: %d checks, %d failures" % [key.to_upper(), checks, failures])
	quit(1 if failures else 0)

## Each recording verifies against its starting checkpoint through JSON, and
## each derived checkpoint verifies on its own.
func _verify(key: String, level: Dictionary, evidence: Dictionary) -> void:
	var simulation: Script = Registry.simulation_script(key)
	_check(evidence.pairs.size() == level.stages.size(), "One recorded pair per stage")
	for index in range(evidence.pairs.size()):
		var pair: Dictionary = evidence.pairs[index]
		var previous: Dictionary = evidence.checkpoints[index]
		for role: String in ["a", "b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			var verdict: Dictionary = simulation.verify_recording(level, _json(pair[role]), _json(previous), _json(prior))
			_check(verdict.valid and int(pair[role].simulation_version) == int(level.simulation_version), "Recording verifies on rules %d: %s/%s %s" % [int(level.simulation_version), level.stages[index].id, role, verdict.get("error", "")])
		_check(simulation.verify_checkpoint(level, _json(evidence.checkpoints[index + 1])).valid, "Checkpoint verifies: " + str(level.stages[index].id))

func _write_fixtures(key: String, level: Dictionary, evidence: Dictionary) -> void:
	var names := Golden.fixture_prefixes(key)
	_write(names.chapter + "definition", level)
	_write(names.chapter + "initial-checkpoint", evidence.checkpoints[0])
	_write(names.chapter + "final-checkpoint", evidence.checkpoints[-1])
	for index in range(evidence.pairs.size()):
		var id: String = level.stages[index].id
		_write(names.stages + id + "-a", evidence.pairs[index].a)
		_write(names.stages + id + "-b", evidence.pairs[index].b)
		_write(names.stages + id + "-checkpoint", evidence.checkpoints[index + 1])

func _write(name: String, value: Dictionary) -> void:
	var path := "res://tests/fixtures/%s.json" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Fixture is writable: " + path)
	if file == null: return
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.close()
	print("FIXTURE WRITTEN " + path)

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
