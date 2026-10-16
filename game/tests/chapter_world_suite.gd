extends SceneTree
## One chapter opened through its own solo scene with a real journal: every
## stage and role builds the descriptor's world, plays its witness's recorded
## inputs through the chapter controls, stays committable and leaves the
## definition unchanged; the last turn completes the chapter.
##
## A chapter's world suite (tests/test_<chapter>_world.gd) extends this file and
## declares Witness, its witness script (chapter_witness.gd).
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var key := ""
var directory := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var witness: RefCounted = get_script().get_script_constant_map().Witness.new()
	key = witness.key()
	directory = "user://chapter-world-%s-%s" % [key.replace("@", "-"), Crypto.new().generate_random_bytes(8).hex_encode()]
	DirAccess.make_dir_recursive_absolute(directory)
	var evidence: Dictionary = witness.chapter()
	_check(evidence.error.is_empty(), "Every stage plays through with real inputs: " + str(evidence.error))
	if evidence.error.is_empty():
		var level: Dictionary = evidence.definition
		for index in range(level.stages.size()):
			for role: String in ["a", "b"]:
				await _turn(level, evidence, index, role)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("%s WORLD: %d checks, %d failures" % [key.to_upper(), checks, failures])
	quit(1 if failures else 0)

func _turn(level: Dictionary, evidence: Dictionary, index: int, role: String) -> void:
	var id: String = level.stages[index].id
	var journal := Journey.new(directory.path_join("%s-%s.json" % [id, role]), null, key)
	journal.load_data()
	for earlier in range(index):
		for earlier_role: String in ["a", "b"]:
			_check(journal.accept_recording(evidence.pairs[earlier][earlier_role]), "Earlier recordings are accepted: " + journal.last_error)
	if role == "b": _check(journal.accept_recording(evidence.pairs[index].a), "The source turn is accepted before its receiver: " + journal.last_error)
	var screen: Node = load(Index.data(key).scene).instantiate()
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	_check(screen.chapter_key == key and screen.mode == "ready", "The solo scene opens %s ready to play: %s/%s" % [key, id, role])
	_check(is_instance_valid(screen.world) and screen.world.get_script() == Registry.world_script(key), "The scene builds the descriptor's world")
	if is_instance_valid(screen.world): screen.world.set_process(false)
	screen._begin()
	_check(screen.mode == "play", "The chapter controls start the turn: %s/%s" % [id, role])
	var definition_hash := Canonical.digest(level)
	for frame: Dictionary in Registry.simulation_script(key).expand_recording_inputs(evidence.pairs[index][role]):
		screen.advance_input(frame)
	_check(screen.sim.can_commit(), "The recorded inputs stay committable through the controls: %s/%s" % [id, role])
	_check(Canonical.digest(screen.sim.level) == definition_hash, "Presentation never changes the definition")
	if role == "b" and index == level.stages.size() - 1: _check(screen.sim.complete, "The last turn completes the chapter")
	root.remove_child(screen)
	screen.free()
	await process_frame

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
