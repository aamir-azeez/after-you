extends SceneTree
## PipAvatar (presentation/kit/pip_avatar.gd) and the shared still renderer
## (presentation/kit/pip_snapshots.gd):
## - live mode is the real 3D pip and draws at the idle card rate, an animated
##   outfit included;
## - still mode has no view of its own, takes no input and never processes;
##   ten matching still pips cost one render; different pips draw one a frame;
##   a list of still pips makes no view per row; the cache keeps the newest 64;
##   a pip nobody waits for any more is skipped; the renderer frees itself
##   when idle;
## - `own` follows services/own_look.gd; a tall item pulls the view back;
## - the three screens' pips keep their names.
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const SettingsSpirit = preload("res://presentation/settings_spirit.gd")
const Chip = preload("res://presentation/display_name_chip.gd")
const Outfit = preload("res://services/outfit.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const Look = preload("res://presentation/spirit_look.gd")
const DT := 1.0 / 60.0

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	# The items are not released yet; these suites wear them all.
	Outfit.show_unreleased = true
	await _live()
	await _still_shares_one_render()
	await _still_one_a_frame()
	await _skips_and_idles()
	_lru()
	await _sites()
	print("PIP AVATAR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _add(pip: Control) -> Control:
	root.add_child(pip)
	pip.size = pip.custom_minimum_size
	return pip

func _draws(pip: Control, frames: int) -> int:
	var before: int = pip.drawn
	for frame in range(frames): pip._process(DT)
	return pip.drawn - before

func _live() -> void:
	var pip := _add(PipAvatar.new(false, PipAvatar.PEACH, PipAvatar.MIN_SIZE, false, true))
	await process_frame
	pip.set_process(false)
	_check(pip.get_class() == "TextureRect" and pip.find_child("SpiritView", true, false) is SubViewport and pip._spirit != null, "Live, it is the real 3D pip in its own view")
	_check(pip.mouse_filter == Control.MOUSE_FILTER_STOP and pip.turn != null, "and takes a drag")
	_check(pip._spirit.outfit().is_empty() and pip._spirit._wearing == null, "The player's own pip wears the default look, which adds nothing")
	var hz := int(IslandWorld.IDLE_CARD_HZ)
	var idle := _draws(pip, 60)
	_check(idle >= hz - 2 and idle <= hz + 1, "Still, it draws at the idle rate: %d in 1 s" % idle)
	var camera: Camera3D = pip._camera
	var near := camera.position.distance_to(Stage.LOOK_AT)
	pip.wear(Outfit.of("lighthouse_lamp", true))
	_check(pip._spirit.outfit() == {"hat": "lighthouse_lamp"}, "wear() dresses the live pip")
	_check(camera.position.distance_to(Stage.LOOK_AT) > near * 1.1, "A tall item pulls the view back a little")
	idle = _draws(pip, 60)
	_check(idle >= hz - 2 and idle <= hz + 1, "With a moving lamp it still draws at the idle rate: %d in 1 s" % idle)
	pip.wear({})
	_check(is_equal_approx(camera.position.distance_to(Stage.LOOK_AT), near), "Taken off, the view comes back")
	pip.queue_free()
	await process_frame

func _still(size: Vector2 = Vector2(42, 56), color: Color = Look.PEACH, outfit: Dictionary = {}) -> Control:
	var pip: Control = PipAvatar.new(false, color, size, true, false)
	pip.outfit = outfit
	return _add(pip)

func _views() -> int:
	return root.find_children("*", "SubViewport", true, false).size()

func _still_shares_one_render() -> void:
	Snapshots.release_cached()
	var before := Snapshots.renders
	var pips: Array[Control] = []
	for index in range(10): pips.append(_still())
	await _frames(1)
	for pip: Control in pips:
		_check(pip.find_child("SpiritView", true, false) == null and pip.mouse_filter == Control.MOUSE_FILTER_IGNORE and not pip.is_processing(), "A still pip has no view of its own, takes no input and does not run")
	await _frames(10)
	_check(Snapshots.renders - before == 1, "Ten matching still pips cost one render: %d" % (Snapshots.renders - before))
	var same := true
	for pip: Control in pips: same = same and pip.texture != null and pip.texture == pips[0].texture
	_check(same, "and all show the same texture")
	_check(pips[0].texture.get_size() == Vector2(84, 112), "drawn at twice the pip's size: %s" % pips[0].texture.get_size())
	_check(_views() <= 1, "Ten still pips share the one renderer's view: %d views" % _views())
	var later := _still()
	_check(later.texture == pips[0].texture and Snapshots.renders - before == 1, "A pip asked for again is answered from the cache at once")
	for pip: Control in pips: pip.queue_free()
	later.queue_free()
	await process_frame

func _still_one_a_frame() -> void:
	var before := Snapshots.renders
	var a := _still(Vector2(50, 60))
	var b := _still(Vector2(50, 60), Look.MINT)
	var c := _still(Vector2(50, 60), Look.PEACH, Outfit.of("daisy", true))
	var started: Array[int] = []
	for frame in range(24):
		await process_frame
		started.append(Snapshots.renders - before)
	var steps_ok := true
	for index in range(1, started.size()): steps_ok = steps_ok and started[index] - started[index - 1] <= 1
	_check(steps_ok and started.back() == 3, "Three different pips draw one a frame, three renders in all: %s" % [started])
	_check(a.texture != b.texture and b.texture != c.texture and c.texture != null, "Each different pip gets its own texture")
	for pip: Control in [a, b, c]: pip.queue_free()
	await process_frame

func _skips_and_idles() -> void:
	var before := Snapshots.renders
	var gone := _still(Vector2(30, 40))
	gone.free()
	await _frames(6)
	_check(Snapshots.renders == before and Snapshots.pending() == 0, "A pip freed before its render is skipped")
	var renderer: Node = Snapshots.renderer()
	_check(renderer != null, "The renderer is running")
	for frame in range(int(Snapshots.IDLE_SECONDS * 60.0) + 30):
		if not is_instance_valid(renderer) or renderer.is_queued_for_deletion(): break
		renderer._process(DT)
	await process_frame
	_check(not is_instance_valid(renderer) and Snapshots.renderer() == null, "With nothing to draw it frees itself and its view")
	_check(_views() == 0, "and leaves no view behind")
	var again := _still(Vector2(30, 40))
	await _frames(8)
	_check(again.texture != null and Snapshots.renders == before + 1, "A later pip starts a new renderer")
	again.queue_free()
	await process_frame

func _lru() -> void:
	Snapshots.release_cached()
	var drawn: Array[String] = []
	Snapshots.draw_with = func(spec: Dictionary) -> Texture2D:
		drawn.append(spec.key)
		return ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var renderer: Node = null
	var keep := func(_key: String, _texture: Texture2D) -> void: pass
	for index in range(70):
		Snapshots.request(Look.PEACH, {}, Vector2i(10 + index, 10), 0.0, keep)
	renderer = load(Snapshots.SCRIPT_PATH).new()
	for frame in range(80): renderer._process(DT)
	_check(drawn.size() == 70, "Each different pip is drawn once: %d" % drawn.size())
	_check(Snapshots.cached_count() == Snapshots.CACHE_SIZE, "The cache keeps the newest %d: %d" % [Snapshots.CACHE_SIZE, Snapshots.cached_count()])
	_check(Snapshots.request(Look.PEACH, {}, Vector2i(10, 10), 0.0, keep) == null, "The oldest is let go")
	_check(Snapshots.request(Look.PEACH, {}, Vector2i(79, 10), 0.0, keep) != null, "The newest is kept")
	renderer.free()
	Snapshots.draw_with = Callable()
	Snapshots.release_cached()

func _sites() -> void:
	var settings := _add(SettingsSpirit.new(false))
	await process_frame
	_check(settings.name == "SettingsSpirit" and settings.own and not settings.still and settings.find_child("SpiritView", true, false) != null, "Settings shows the player's own live pip")
	settings.queue_free()
	var chip: Control = Chip.new(false)
	root.add_child(chip)
	await _frames(8)
	_check(chip.preview.name == "DisplayNameChipPip" and chip.preview.own and chip.preview.still and chip.preview.texture != null, "The Friends chip shows the player's own still pip")
	chip.queue_free()
	await process_frame
