extends SceneTree
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/journey_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var exported: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var home := Catalog.definition("long-way-home")
	var initial := Catalog.initial_checkpoint(home)
	var middle := _fixture("the-path-you-leave-checkpoint")
	var source := Witness.source(home,"the-path-you-leave",initial,"near",true,32)
	var receiver := Witness.receiver(home,"the-path-you-leave",initial,source.export_recording(),"near",0,16)
	_accept("corrected-selector",home,initial,source,receiver)
	source = Witness.source(home,"a-place-beside-you",middle,"garden")
	receiver = Witness.receiver(home,"a-place-beside-you",middle,source.export_recording(),"garden")
	_accept("garden-ending",home,middle,source,receiver)
	_check(not receiver.snapshot().mechanisms.levers.has("porch-shutter"),"Garden ending needs no unused porch lever key")
	source = Witness.source(home,"a-place-beside-you",middle,"near")
	Walk.wait_ticks(source,240)
	Walk.walk(source,[1200,144])
	receiver = Witness.receiver(home,"a-place-beside-you",middle,source.export_recording(),"near")
	_accept("changed-window",home,middle,source,receiver)
	_check(receiver.snapshot().players.p1.z == 144 and receiver.snapshot().mechanisms.latched_bridges.has("porch-door") and receiver.snapshot().mechanisms.latched_bridges.has("garden-door"),"Earlier porch entry persists while final garden pad opens its different route")
	var light := Catalog.definition("conservatory")
	middle = _fixture("a-light-above-checkpoint")
	source = Witness.source(light,"the-way-light-returns",middle)
	receiver = Simulation.new()
	_check(receiver.reset(light,"the-way-light-returns",middle,source.export_recording(),"b"),"Corrected shutter receiver starts from native carried proof")
	Witness._route(receiver,[[-304,208],[384,208],[352,64]])
	Walk.tap(receiver)
	Witness._route(receiver,[[0,64],[0,0]])
	Walk.tap(receiver)
	Witness._route(receiver,[[0,64],[352,64]])
	Walk.tap(receiver)
	Witness._route(receiver,[[384,64],[384,16],[752,16],[752,64]])
	Walk.tap(receiver)
	_accept("closed-return-shutter",light,middle,source,receiver)
	_check(receiver.snapshot().mechanisms.levers.get("return-shutter") == false and not receiver.snapshot().mechanisms.latched_bridges.has("room-return"),"Closing the used shutter preserves success without inventing a persistent return route")
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
		var directory := "res://tests/fixtures/journey/validation"
		DirAccess.make_dir_recursive_absolute(directory)
		for key: String in exported:
			var file := FileAccess.open(directory.path_join(key+".json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(exported[key],"\t",true)+"\n")
	print("JOURNEY CORRECTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _accept(id: String, level: Dictionary, previous: Dictionary, source: RefCounted, receiver: RefCounted) -> void:
	_check(source.can_commit() and source.error.is_empty(),id+" uses an accepted real source")
	_check(receiver.complete and receiver.error.is_empty(),id+" completes by native inputs: "+receiver.error)
	if not receiver.complete: return
	var derived := Simulation.derive_checkpoint(level,previous,source.export_recording(),receiver.export_recording())
	_check(derived.valid and Simulation.verify_checkpoint(level,derived.get("checkpoint",{})).valid,id+" replay-verifies its full changed proof")
	if derived.valid:
		exported[id] = derived.checkpoint
		print("Correction %s A=%d B=%d" % [id,source.tick,receiver.tick])
		var path := "res://tests/fixtures/journey/validation/"+id+".json"
		if FileAccess.file_exists(path): _check(Canonical.same(derived.checkpoint,JSON.parse_string(FileAccess.get_file_as_string(path))),id+" remains byte-equivalent to the backend fixture")

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/"+name+".json"))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
