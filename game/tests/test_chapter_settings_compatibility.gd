extends SceneTree
## Old inert chapter envelopes remain readable when app preference defaults grow.
const Storage = preload("res://services/local_save.gd")
const Relay = preload("res://services/relay_journey.gd")
const Lighthouse = preload("res://services/lighthouse_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OLD_SETTINGS := {"sound":true,"haptics":true,"reduced_motion":false,"assistance":true,"left_handed":false}
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _run() -> void:
	_predicate()
	for chapter: String in [Registry.FIRST_STEPS,Registry.RELAY,"lighthouse"]:
		_chapter(chapter)
	for path: String in paths:
		for suffix: String in ["",".tmp",".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("Chapter default-settings compatibility: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _predicate() -> void:
	var old_before:=Canonical.digest(OLD_SETTINGS)
	_check(Storage.default_settings_envelope_valid(OLD_SETTINGS),"The exact original five-key default settings remain supported")
	_check(Storage.default_settings_envelope_valid(Storage.defaults().settings),"Current default settings remain supported")
	_check(Storage.defaults().settings.share_online_status == true and Storage.default_settings_envelope_valid({"share_online_status": true}), "Presence defaults remain compatible with inert chapter envelopes")
	_check(not Storage.default_settings_envelope_valid({"share_online_status": false}), "A changed UI preference cannot bypass chapter-envelope validation")
	_check(Storage.default_settings_envelope_valid({}) and Storage.default_settings_envelope_valid({"sound":true}),"Missing inert defaults are permitted without inventing another format version")
	for invalid: Variant in [null,[],true,{"future_preference":true},{"sound":false},{"photo_prompts":false},{"sound":1},{"sound":"true"}]:
		_check(not Storage.default_settings_envelope_valid(invalid),"Unknown, nondefault or wrongly typed settings cannot pass the envelope guard")
	_check(Canonical.digest(OLD_SETTINGS)==old_before,"Default-settings validation does not mutate the supplied dictionary")

func _new_journey(chapter: String, path: String) -> RefCounted:
	return Lighthouse.new(path) if chapter=="lighthouse" else Relay.new(path,null,chapter)

func _fixture(path: String) -> Dictionary:
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(value is Dictionary,"Known regression fixture parses")
	return value if value is Dictionary else {}

func _contributions(chapter: String) -> Array[Dictionary]:
	if chapter=="lighthouse":
		var history:=_fixture("res://tests/fixtures/lighthouse/first-two-v3.json")
		return [history.pairs[0].a,history.pairs[0].b,history.pairs[1].a]
	var folder:="res://tests/fixtures/first_steps/" if chapter==Registry.FIRST_STEPS else "res://tests/fixtures/v2/"
	var first:="a-little-lift" if chapter==Registry.FIRST_STEPS else "relay"
	var second:="a-place-to-grow" if chapter==Registry.FIRST_STEPS else "garden"
	return [_fixture(folder+first+"-a.json"),_fixture(folder+first+"-b.json"),_fixture(folder+second+"-a.json")]

func _write(path: String, value: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	_check(file!=null,"The test's isolated journal can be written")
	if file!=null:
		file.store_string(JSON.stringify(value))
		file.close()

func _bytes(path: String) -> Array[PackedByteArray]:
	return [FileAccess.get_file_as_bytes(path),FileAccess.get_file_as_bytes(path+".backup")]

func _chapter(chapter: String) -> void:
	var path:="user://chapter-settings-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	paths.append(path)
	var contributions:=_contributions(chapter)
	var journal:=_new_journey(chapter,path)
	journal.load_data()
	_check(not journal.read_only and journal.accept_recording(contributions[0]) and journal.accept_recording(contributions[1]) and journal.save_draft(contributions[2]),chapter+": actual verifier writes a completed pair and next-stage draft")
	if journal.read_only or journal.pairs().size()!=1 or journal.draft().is_empty(): return
	var checkpoint: Dictionary=journal.checkpoint()
	var pairs: Array=journal.pairs()
	var draft: Dictionary=journal.draft()
	var stage: String=journal.stage_id()
	var primary: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var backup: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path+".backup"))
	var state_key:="lighthouse" if chapter=="lighthouse" else "relay"
	# The retained native code10 save has these exact five defaults. Preserve
	# genuine recorded evidence and distinct durable generations in both files.
	primary.settings=OLD_SETTINGS.duplicate(true)
	backup.settings=OLD_SETTINGS.duplicate(true)
	_write(path,primary)
	_write(path+".backup",backup)
	var before:=_bytes(path)
	journal=_new_journey(chapter,path)
	journal.load_data()
	_check(not journal.read_only and journal.stage_id()==stage and journal.role()=="a",chapter+": old primary and backup load into the same next contribution")
	_check(Canonical.same(journal.pairs(),pairs) and Canonical.same(journal.checkpoint(),checkpoint) and Canonical.same(journal.draft(),draft),chapter+": full replay preserves exact accepted proof, checkpoint and draft")
	_check(_bytes(path)==before and not FileAccess.file_exists(path+".tmp"),chapter+": loading does not migrate, normalize or rewrite either old generation")
	_check(journal.create_live_simulation()!=null,chapter+": retained checkpoint can create its supported live rehearsal")
	_check(_bytes(path)==before,chapter+": preparing controls still does not change the stored evidence")
	# A newer valid backup must retain the established generation-selection
	# behavior, rather than making primary-only compatibility work by accident.
	var newer_backup:=primary.duplicate(true)
	newer_backup.generation=int(primary.generation)+1
	_write(path+".backup",newer_backup)
	before=_bytes(path)
	journal=_new_journey(chapter,path)
	journal.load_data()
	_check(not journal.read_only and journal._storage.loaded_from==path+".backup" and Canonical.same(journal.draft(),draft),chapter+": newest old-format backup is selected and replay-verified")
	_check(_bytes(path)==before,chapter+": selecting the newer backup preserves both files byte-for-byte")
	# Settings absent was already accepted. A known-default subset must have
	# the same harmless meaning, without accepting an unknown UI preference.
	var subset:=primary.duplicate(true)
	subset.settings={"sound":true}
	_write(path,subset)
	_write(path+".backup",backup)
	before=_bytes(path)
	journal=_new_journey(chapter,path)
	journal.load_data()
	_check(not journal.read_only and Canonical.same(journal.draft(),draft) and _bytes(path)==before,chapter+": a known-default subset retains proof and bytes")
	for invalid: Dictionary in [{"future_preference":true},{"sound":false}]:
		var rejected:=backup.duplicate(true)
		rejected.settings=invalid
		_write(path,primary)
		_write(path+".backup",rejected)
		before=_bytes(path)
		journal=_new_journey(chapter,path)
		journal.load_data()
		_check(journal.read_only and journal.last_error.contains("unsupported format"),chapter+": unknown/nondefault backup settings still hold the whole journal")
		_check(_bytes(path)==before,chapter+": rejected backup and valid primary are both retained unchanged")
	var tampered:=primary.duplicate(true)
	tampered[state_key].pairs[0].a.recording_hash="f".repeat(64)
	_write(path,tampered)
	_write(path+".backup",backup)
	before=_bytes(path)
	journal=_new_journey(chapter,path)
	journal.load_data()
	_check(journal.read_only and journal.last_error.contains("could not be verified"),chapter+": compatible settings never bypass exact recording verification")
	_check(_bytes(path)==before,chapter+": failed proof preserves every original generation")
