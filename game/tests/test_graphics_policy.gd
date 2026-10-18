extends SceneTree

const Policy = preload("res://services/graphics_policy.gd")
const Storage = preload("res://services/local_save.gd")
const Island = preload("res://presentation/island_world.gd")
const Lighthouse = preload("res://presentation/lighthouse_world.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Look = preload("res://presentation/kit/look.gd")
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
	_policy()
	_settings()
	_frame_rate_migration()
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
		var definition: Dictionary = {} if name in ["island", "lighthouse"] else Registry.definition(name)
		var before := Canonical.digest(definition)
		if not definition.is_empty(): world.load_level(definition)
		# A chapter's look (content/dressing) is authored lighting too.
		var energy: float = world.sun.light_energy
		var lanterns: Array = world.find_children("*", "OmniLight3D", true, false).filter(func(light: OmniLight3D) -> bool: return light.has_meta("lantern"))
		_check(lanterns.is_empty() != (name == Registry.WISHING_WELL), name + ": only the Wishing Well has lantern light pools")
		var color: Color = world.sun.light_color
		for quality: String in ["low", "high", "balanced", "low", "balanced"]:
			Policy.apply(world, {"graphics_quality": quality})
			_check(is_equal_approx(viewport.scaling_3d_scale, 1.0), name + ": every quality draws a 720-line view at full scale")
			_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and viewport.size == Vector2i(1280, 720), "UI viewport size stays unchanged")
			_check(viewport.msaa_3d == (Viewport.MSAA_2X if quality == "high" else Viewport.MSAA_DISABLED), name + ": only High enables 2x MSAA")
			_check(not world.sun.shadow_enabled, name + ": no quality runs the sun's shadow pass")
			_check(_visible_motes(world) == (ceili(authored * 0.25) if quality == "low" else authored), name + ": toggles restore exactly the authored mote count")
			var flies: Array = world.get("_fireflies") if world.get("_fireflies") != null else []
			_check(flies.all(func(fly: MeshInstance3D) -> bool: return fly.visible == (quality != "low")), name + ": fireflies show on every quality but Low")
			_check(world.sun.light_energy == energy and world.sun.light_color == color, name + ": quality does not darken authored lighting")
			_check(_fill_matches(world, quality), name + ": only Low trades the bounce light for a little more ambient")
			_check(lanterns.all(func(light: OmniLight3D) -> bool: return light.visible == (quality != "low")), name + ": lantern light pools show on every quality but Low")
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
	_quality_before_load(viewport)
	_check(Engine.physics_ticks_per_second == original_ticks and Engine.max_fps == original_fps, "Graphics never change simulation or frame-rate limits")
	viewport.queue_free()
	await process_frame
	print("GRAPHICS POLICY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The bounce light shows, and the ambient carries none of its fill, on every
## quality but Low.
func _fill_matches(world: Node3D, quality: String) -> bool:
	var look := Look.preset(world.get("_look"))
	var fill: DirectionalLight3D = world.find_children("*", "DirectionalLight3D", false, false).filter(func(light: DirectionalLight3D) -> bool: return light != world.sun)[0]
	var env: Environment = (world.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
	var extra: float = look.bounce_energy * Look.FILL_TO_AMBIENT if quality == "low" else 0.0
	return fill.visible == (quality != "low") and is_equal_approx(env.ambient_light_energy, look.ambient_energy * Look.AMBIENT_GAIN + extra)

## The game's order: the quality is applied before the chapter loads, and the
## chapter's own look keeps Low's lighting and lantern cuts.
func _quality_before_load(viewport: SubViewport) -> void:
	for key: String in [Registry.WISHING_WELL, Registry.TURN_OF_THE_TIDE]:
		var world: Node3D = Registry.world_script(key).new()
		viewport.add_child(world)
		world.set_process(false)
		Policy.apply(world, {"graphics_quality": "low"})
		world.load_level(Registry.definition(key))
		_check(_fill_matches(world, "low"), key + ": a chapter loaded on Low keeps its look without the bounce light")
		var lit: Array = world.find_children("*", "OmniLight3D", true, false).filter(func(light: OmniLight3D) -> bool: return light.has_meta("lantern") and light.visible)
		_check(lit.is_empty(), key + ": lanterns built on Low cast no light")
		viewport.remove_child(world)
		world.free()

func _visible_motes(world: Node3D) -> int:
	var count := 0
	for mote: MeshInstance3D in world.motes:
		if mote.visible: count += 1
	return count

func _policy() -> void:
	# The 3D picture is at most 1080 lines tall on Low and Balanced alike, so Low
	# never draws smaller and stretches; High and smaller screens keep their own scale.
	for row: Array in [["low", 0, 1.0], ["low", 720, 1.0], ["low", 1080, 1.0], ["low", 1440, 0.75], ["balanced", 0, 1.0], ["balanced", 1080, 1.0], ["balanced", 1440, 0.75], ["high", 1440, 1.0], ["high", 2160, 1.0]]:
		_check(is_equal_approx(Policy.render_scale(row[0], row[1]), row[2]), "%s on a %d-line screen draws 3D at %.3f" % row)
	var window_sized := SubViewport.new()
	window_sized.size = Vector2i(3120, 1440)
	Policy.apply_viewport(window_sized, "balanced")
	_check(is_equal_approx(window_sized.scaling_3d_scale, 0.75), "A 1440-line view draws Balanced 3D at 1080 lines")
	for short_side: int in [480, 720, 1080, 1440, 2160]:
		_check(Policy.render_scale("low", short_side) == Policy.render_scale("balanced", short_side), "Low draws 3D at Balanced's scale on a %d-line screen" % short_side)
	# Low only leaves effects out; Balanced and High keep every one.
	for quality: String in Policy.QUALITIES:
		var keeps := quality != "low"
		_check(Policy.motion_trails(quality) == keeps and Policy.fireflies(quality) == keeps and Policy.detail_dressing(quality) == keeps and Policy.fill_light(quality) == keeps and Policy.lantern_lights(quality) == keeps, quality + ": effect cuts belong to Low alone")
		_check(Policy.mote_count(32, quality) == (8 if quality == "low" else 32), quality + ": mote count")
	window_sized.free()

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

## The frame rate replaced the Unlimited switch. An older save's switch carries
## over, wrong types fall back to 60, every write keeps the switch for older
## builds, and a switch an older build changed later wins on the next load.
func _frame_rate_migration() -> void:
	_check(Storage.defaults().settings.frame_rate == "60" and Storage.defaults().settings.unlimited_frame_rate == false, "A new save plays at 60")
	_check(Policy.play_fps("30") == 30 and Policy.play_fps("60") == 60 and Policy.play_fps("unlimited") == 0, "Each choice has its play rate")
	for invalid: Variant in [null, 30, 60.0, true, [], {}, "", "120", "Unlimited"]:
		_check(Policy.frame_rate({"frame_rate": invalid}) == "60", "A saved frame rate of %s reads as 60" % str(invalid))
	var path := "user://graphics-frame-rate-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	# [saved frame_rate (absent when null), saved unlimited_frame_rate (absent when null), loaded frame_rate]
	var cases: Array = [
		[null, null, "60"],
		[null, false, "60"],
		[null, true, "unlimited"],
		[null, "x", "60"],
		[null, 1, "60"],
		["30", false, "30"],
		["30", null, "30"],
		["30", true, "unlimited"],
		["unlimited", true, "unlimited"],
		["unlimited", false, "60"],
		["unlimited", "yes", "unlimited"],
		["60", true, "unlimited"],
		[30, null, "60"],
		[30, true, "unlimited"],
		["fast", false, "60"],
		[{}, [], "60"],
	]
	for row: Array in cases:
		var save := Storage.defaults()
		save.completed = {"first-light": true}
		save.settings.erase("frame_rate")
		save.settings.erase("unlimited_frame_rate")
		if row[0] != null: save.settings.frame_rate = row[0]
		if row[1] != null: save.settings.unlimited_frame_rate = row[1]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(save))
		file.close()
		var loaded := Storage.new(path)
		loaded.load_data()
		var label := "frame_rate %s, unlimited %s" % [str(row[0]), str(row[1])]
		_check(loaded.data.settings.frame_rate == row[2] and loaded.data.settings.unlimited_frame_rate == (row[2] == "unlimited"), "%s loads as %s" % [label, row[2]])
		_check(loaded.data.completed == save.completed, "%s keeps progress" % label)
	var saved := Storage.new(path)
	saved.load_data()
	for rate: String in Policy.FRAME_RATES:
		var settings: Dictionary = saved.data.settings.duplicate(true)
		settings.frame_rate = rate
		# A stale switch in memory never overrides the new choice on write.
		settings.unlimited_frame_rate = rate != "unlimited"
		_check(saved.update_values({"settings": settings}), "Frame rate %s saves" % rate)
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(disk is Dictionary and disk.settings.frame_rate == rate and disk.settings.unlimited_frame_rate == (rate == "unlimited"), "Frame rate %s is written with the older builds' switch to match" % rate)
		var reloaded := Storage.new(path)
		reloaded.load_data()
		_check(reloaded.data.settings.frame_rate == rate, "Frame rate %s survives a reload" % rate)
	var invalid: Dictionary = saved.data.settings.duplicate(true)
	invalid.frame_rate = 120
	_check(saved.update_values({"settings": invalid}) and saved.data.settings.frame_rate == "60" and not saved.data.settings.unlimited_frame_rate, "Write normalization cannot keep an invalid frame rate")
	_check(Storage.default_settings_envelope_valid({"frame_rate": "60"}) and not Storage.default_settings_envelope_valid({"frame_rate": "30"}), "Chapter envelopes may hold only the default frame rate")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
