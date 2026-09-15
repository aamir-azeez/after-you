extends SceneTree
## Persistent preference and real prompt presentation; no camera/provider access.
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Preview = preload("res://relay_preview.gd")
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const Fakes = preload("res://tests/test_reaction_photos.gd")

class Session:
	extends "res://tests/test_reaction_photos.gd".PhotoSession
	var remembered := 0
	func remember_photo_receipt(_receipt: Dictionary) -> bool:
		remembered += 1
		return true

var checks := 0
var failures := 0
var continued := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _continued() -> void:
	continued += 1

func _run() -> void:
	var path := "user://photo-preferences-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Save.new(path)
	# Existing saves without the setting opt into prompts, with all other data kept.
	storage.data.settings.erase("photo_prompts")
	storage.data.settings.sound = false
	_check(storage.flush(), "Write an older settings envelope")
	storage.load_data()
	_check(storage.data.settings.photo_prompts == true and storage.data.settings.sound == false, "Old saves gain the prompt default without replacing other choices")
	var app := Main.new()
	app.saves = storage
	var preview := Preview.new()
	preview.settings = storage.data.settings.duplicate(true)
	preview.save_photo_prompt_preference = app._save_photo_prompt_preference
	var host := Fakes.Host.new()
	root.add_child(host)
	var session := Session.new()
	var controller := Fakes.PhotoController.new()
	var camera := Fakes.Capture.new()
	var flow := Flow.new()
	flow.controller_override = controller
	flow.capture_override = camera
	flow.prompts_enabled = preview._photo_prompts_enabled
	flow.save_prompt_preference = preview._save_photo_prompts
	flow.configure(host, session)
	host.add_child(flow)
	var receipt := {"room_id": Fakes.ROOM, "turn_id": "t0-0-a", "recording_hash": Fakes.HASH, "idempotency_key": Fakes.KEY}
	await flow.offer(receipt, _continued, true)
	_check(flow.active and host.has_button("Optional camera photo"), "Enabled preference offers a photo after the accepted contribution")
	var toggle := host.card.get_node("PhotoPromptOptOut") as CheckBox
	_check(not toggle.button_pressed, "Prompt checkbox starts unchecked")
	toggle.button_pressed = true
	var reloaded := Save.new(path)
	reloaded.load_data()
	_check(not reloaded.data.settings.photo_prompts and not preview._photo_prompts_enabled(), "Don't ask again persists immediately and updates the active scene")
	_check(not reloaded.data.settings.sound, "Saving camera preference preserves another setting")
	flow._continue()
	var remembered := session.remembered
	var offered_generation := host.card.get_instance_id()
	await flow.offer(receipt, _continued, true)
	_check(not flow.active and continued == 2 and host.card.get_instance_id() == offered_generation, "Disabled prompts continue without creating another modal")
	_check(session.remembered == remembered + 1 and not controller.bound and camera.count == 0, "Skipped prompt retains an editing hint without opening camera or receipt HTTP")
	await flow.offer(receipt, _continued)
	_check(flow.active and host.has_button("Optional camera photo"), "Manual photo access remains available with prompts disabled")
	toggle = host.card.get_node("PhotoPromptOptOut") as CheckBox
	_check(toggle.button_pressed, "Manual photo card reflects the saved opt-out")
	storage.read_only = true
	toggle.button_pressed = false
	_check(toggle.button_pressed and not preview._photo_prompts_enabled(), "Failed preference write restores checkbox and active preference")
	_check(not (host.card.get_node("PhotoPromptPreferenceStatus") as Label).text.is_empty(), "Failed preference write has a visible explanation")
	storage.read_only = false
	toggle.button_pressed = false
	reloaded.load_data()
	_check(reloaded.data.settings.photo_prompts and preview._photo_prompts_enabled(), "Prompts can be re-enabled and survive a fresh read")
	flow._continue()
	await flow.offer(receipt, _continued, true)
	_check(flow.active, "Re-enabled preference offers the next accepted turn")
	flow._continue()
	_check(controller.uploads == 0 and controller.deletes == 0 and camera.count == 0, "Preference changes never capture or mutate a shared image")
	host.queue_free()
	app.free()
	preview.free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("After You photo preferences: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
