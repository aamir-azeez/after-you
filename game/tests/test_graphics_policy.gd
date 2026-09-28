extends SceneTree

const Policy = preload("res://services/graphics_policy.gd")
const Storage = preload("res://services/local_save.gd")
const Island = preload("res://presentation/island_world.gd")
const Lighthouse = preload("res://presentation/lighthouse_world.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_settings()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var original_ticks := Engine.physics_ticks_per_second
	var original_fps := Engine.max_fps
	for name: String in ["island", "lighthouse"] + Registry.keys():
		var script: Script = Island if name == "island" else Lighthouse if name == "lighthouse" else Registry.world_script(name)
		var world: Node3D = script.new()
		viewport.add_child(world)
		world.set_process(false)
		var authored := _visible_motes(world)
		_check(authored == (32 if name in ["island", Registry.RELAY, Registry.FIRST_STEPS] else 10), name + ": authored motes captured before policy")
		var energy: float = world.sun.light_energy
		var color: Color = world.sun.light_color
		var definition: Dictionary = {} if name in ["island", "lighthouse"] else Registry.definition(name)
		var before := Canonical.digest(definition)
		if not definition.is_empty(): world.load_level(definition)
		for quality: String in ["low", "high", "balanced", "low", "balanced"]:
			Policy.apply(world, {"graphics_quality": quality})
			_check(is_equal_approx(viewport.scaling_3d_scale, 0.75 if quality == "low" else 1.0), name + ": 3D scale follows selection")
			_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and viewport.size == Vector2i(1280, 720), "UI viewport size stays unchanged")
			_check(viewport.msaa_3d == (Viewport.MSAA_2X if quality == "high" else Viewport.MSAA_DISABLED), name + ": only High enables 2x MSAA")
			_check(world.sun.shadow_enabled == (quality != "low"), name + ": Low toggles only the authored sun shadows")
			_check(_visible_motes(world) == (ceili(authored * 0.25) if quality == "low" else authored), name + ": toggles restore exactly the authored mote count")
			_check(world.sun.light_energy == energy and world.sun.light_color == color, name + ": quality does not darken authored lighting")
		_check(Canonical.digest(definition) == before, name + ": graphics leave chapter data unchanged")
		Policy.apply(world, {"graphics_quality": "low"})
		var hidden: MeshInstance3D = world.motes[authored - 1]
		var hidden_position := hidden.position
		world._process(1.0 / 60.0)
		_check(not hidden.visible and hidden.position == hidden_position, name + ": hidden motes do no animation work")
		if not definition.is_empty():
			world.show_stage(definition.stages[-1])
			Policy.apply(world, {"graphics_quality": "high"})
			_check(_visible_motes(world) == authored, name + ": another stage cannot grow the authored mote set")
		viewport.remove_child(world)
		world.free()
	_check(Engine.physics_ticks_per_second == original_ticks and Engine.max_fps == original_fps, "Graphics never change simulation or frame-rate limits")
	viewport.queue_free()
	await process_frame
	print("GRAPHICS POLICY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _visible_motes(world: Node3D) -> int:
	var count := 0
	for mote: MeshInstance3D in world.motes:
		if mote.visible: count += 1
	return count

func _settings() -> void:
	_check(Storage.defaults().settings.graphics_quality == "balanced", "Existing visual quality remains the default")
	for invalid: Variant in [null, true, 1, [], {}, "ultra", "LOW"]:
		_check(Policy.normalize(invalid) == "balanced", "Invalid quality safely uses Balanced")
	var path := "user://graphics-policy-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var old := Storage.defaults()
	old.settings.erase("graphics_quality")
	old.completed = {"first-light": true}
	old.settings.sound = false
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var saved := Storage.new(path)
	saved.load_data()
	_check(saved.data.settings.graphics_quality == "balanced" and saved.data.completed == old.completed and not saved.data.settings.sound, "Old save keeps progress and preferences while adding Balanced")
	for quality: String in Policy.QUALITIES:
		var settings: Dictionary = saved.data.settings.duplicate(true)
		settings.graphics_quality = quality
		_check(saved.update_values({"settings": settings}), "Graphics selection saves")
		var loaded := Storage.new(path)
		loaded.load_data()
		_check(loaded.data.settings.graphics_quality == quality and loaded.data.completed == old.completed, "Graphics selection survives reload without changing progress")
	var invalid_settings: Dictionary = saved.data.settings.duplicate(true)
	invalid_settings.graphics_quality = 99
	_check(saved.update_values({"settings": invalid_settings}) and saved.data.settings.graphics_quality == "balanced", "Write normalization cannot retain an invalid quality")
	_check(Storage.default_settings_envelope_valid({"graphics_quality": "balanced"}) and not Storage.default_settings_envelope_valid({"graphics_quality": "low"}), "Inert chapter envelopes still accept only default preferences")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
