extends Node
## Compiles the GL programs the chapters draw, once, offscreen, while Home is
## idle, so the first open of a chapter after an install or an update, and the
## lamps and faded floors its replays reach, never compile a program in a frame.
##
## GL Compatibility compiles a material's program the first time it is drawn,
## for each way it is lit, on the main thread, and keeps the result in
## user://shader_cache. Here a small SubViewport that nothing displays draws one
## quad per StandardMaterial3D feature key the chapters use (MATERIALS, lamps
## lit and unlit and floors faded by the cutaway included), every Label3D key
## (LABELS) and every world ShaderMaterial (shaders()): beside an omni light and
## out of its reach, under the chapters' environment, sun and bounce light.
## Each costs a compile that would otherwise land in a chapter's frames, so the
## list holds only what the chapters draw, and one is drawn a frame.
##
## - Each compile holds the main thread, so it starts only once idle() has
##   held with no touch, click or key for IDLE_SECONDS. Any input, leaving
##   Home or stop() (a chapter opening) frees the viewport at once and never
##   waits; a later idle Home goes on from where it stopped.
## - Skipped when this install already warmed this engine, driver, look and
##   key set (STAMP_PATH, outside the backup plan), and for the rest of the
##   run once done. Headless runs (tests, tools) never warm.
## - Presentation only: nothing joins a chapter world, and no simulation,
##   save or replay reads it. tests/test_gl_warmup_coverage.gd fails when a
##   chapter draws a key missing here.
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const SpiritFace = preload("res://presentation/spirit_face.gd")
const ObjectMotionTrail = preload("res://presentation/object_motion_trail.gd")
const SeedMotionTrail = preload("res://presentation/seed_motion_trail.gd")
const BallRotationBlur = preload("res://presentation/ball_rotation_blur.gd")

const IDLE_SECONDS := 1.0
const STAMP_PATH := "user://gl-warmup-v1.json"
const VIEW_SIZE := Vector2i(64, 64)
## Integer and switch properties of BaseMaterial3D that are shader inputs or
## counts, not part of the generated program.
const NOT_KEYS := ["heightmap_min_layers", "heightmap_max_layers", "particles_anim_h_frames", "particles_anim_v_frames", "stencil_reference"]
## The Label3D properties its generated material is made from.
const LABEL_KEYS := ["billboard", "shaded", "double_sided", "no_depth_test", "fixed_size", "alpha_cut", "alpha_antialiasing_mode", "texture_filter"]

## Every StandardMaterial3D feature key the chapters draw: the properties that
## differ from a new StandardMaterial3D (textures as true). Kept by
## tests/test_gl_warmup_coverage.gd.
const MATERIALS: Array[Dictionary] = [
	{},
	{"emission_enabled": true},
	{"transparency": BaseMaterial3D.TRANSPARENCY_ALPHA},
	{"emission_enabled": true, "transparency": BaseMaterial3D.TRANSPARENCY_ALPHA},
	{"shading_mode": BaseMaterial3D.SHADING_MODE_UNSHADED, "transparency": BaseMaterial3D.TRANSPARENCY_ALPHA},
	{"albedo_texture": true, "billboard_mode": BaseMaterial3D.BILLBOARD_ENABLED, "shading_mode": BaseMaterial3D.SHADING_MODE_UNSHADED, "transparency": BaseMaterial3D.TRANSPARENCY_ALPHA},
	{"billboard_keep_scale": true, "billboard_mode": BaseMaterial3D.BILLBOARD_ENABLED, "cull_mode": BaseMaterial3D.CULL_DISABLED, "shading_mode": BaseMaterial3D.SHADING_MODE_UNSHADED},
	{"vertex_color_use_as_albedo": true},
	{"cull_mode": BaseMaterial3D.CULL_DISABLED, "vertex_color_use_as_albedo": true},
	{"cull_mode": BaseMaterial3D.CULL_DISABLED, "transparency": BaseMaterial3D.TRANSPARENCY_ALPHA, "vertex_color_use_as_albedo": true},
]
## Which listed keys each chapter draws: "m" indices into MATERIALS, "s" into
## shaders(), "l" into LABELS. Kept by tests/test_gl_warmup_coverage.gd.
const CHAPTERS := {
	"first-steps@1": {"m": [0, 1, 2, 5, 6, 8], "s": [0, 4], "l": [2]},
	"relay-isles@2": {"m": [0, 1, 2, 5, 6, 8], "s": [0, 4], "l": [2]},
	"high-and-low@1": {"m": [0, 1, 2, 6, 8], "s": [0], "l": [2]},
	"rolling-home@1": {"m": [0, 1, 2, 6, 8], "s": [0], "l": [2]},
	"a-house-for-two@1": {"m": [0, 1, 2, 3, 6], "s": [0], "l": [2]},
	"conservatory@1": {"m": [0, 1, 2, 3, 6, 8, 9], "s": [0], "l": [2]},
	"the-wishing-well@1": {"m": [0, 1, 2, 6, 8], "s": [0], "l": [2]},
	"long-way-home@1": {"m": [0, 1, 2, 5, 6, 8], "s": [0, 1], "l": [0, 2]},
	"long-way-home@2": {"m": [0, 1, 2, 5, 6, 8], "s": [0, 1], "l": [0, 2]},
	"turn-of-the-tide@1": {"m": [0, 1, 2, 3, 4, 5, 6, 7], "s": [0, 1], "l": [0, 1, 2]},
	"sleeping-lighthouse@1": {"m": [0, 1, 2, 3, 6, 8], "s": [0], "l": [2]},
	"sleeping-lighthouse@2": {"m": [0, 1, 2, 3, 6, 8], "s": [0], "l": [2]},
}
## Every Label3D key the chapters draw ("msdf": the font draws from a distance field).
const LABELS: Array[Dictionary] = [
	{"billboard": BaseMaterial3D.BILLBOARD_ENABLED},
	{"billboard": BaseMaterial3D.BILLBOARD_ENABLED, "fixed_size": true},
	{"billboard": BaseMaterial3D.BILLBOARD_ENABLED, "fixed_size": true, "no_depth_test": true},
]

## Where the warm-up marks this install; tests point it elsewhere.
static var stamp_path := STAMP_PATH
## Done for this run, how far an interrupted run got, and its order.
static var _done := false
static var _next := 0
static var _order: Array = []

## True while the player is idle at Home; set by the owner.
var idle: Callable
## The saved settings now, for the look the chapters draw with.
var settings: Callable
## The chapter the player most likely opens next (a registry key, or ""); its
## programs are warmed first. Set by the owner.
var next_chapter: Callable
var enabled := DisplayServer.get_name() != "headless"
var idle_seconds := IDLE_SECONDS
var _idle_for := 0.0
var _view: SubViewport
var _items: Array = []
var _lit: MeshInstance3D
var _unlit: MeshInstance3D
var _label_lit: Label3D
var _label_unlit: Label3D
## The item shown and whether a frame has drawn it since.
var _shown := -1
var _drawn := false

## Whether this run still has programs to warm.
static func pending() -> bool:
	return not _done

## True while the warm-up draws.
func running() -> bool:
	return is_instance_valid(_view)

## Stops drawing now; a later idle Home goes on from the next item.
func stop() -> void:
	_idle_for = 0.0
	_close()

func _exit_tree() -> void:
	_close()

## Any touch, click or key: the player is not idle.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask == 0: return
	_idle_for = 0.0
	if running(): stop()

func _process(delta: float) -> void:
	if not enabled or _done: return
	if not idle.is_valid() or not idle.call():
		if running(): stop()
		_idle_for = 0.0
		return
	if not running():
		_idle_for += delta
		if _idle_for >= idle_seconds: _open()
		return
	if _shown >= 0 and not _drawn: return
	if _shown >= 0: _next = _shown + 1
	if _next >= _items.size():
		_finish()
		return
	_show(_next)

func _on_drawn() -> void:
	if _shown >= 0: _drawn = true

# --- Keys: one function for the warm-up and its coverage test ---

## A StandardMaterial3D's feature key: its own switch, mode and texture
## properties that differ from a new one.
static func material_key(material: BaseMaterial3D) -> Dictionary:
	var fresh := StandardMaterial3D.new()
	var key: Dictionary = {}
	for property: Dictionary in ClassDB.class_get_property_list("BaseMaterial3D", true):
		var name := str(property.name)
		if property.usage & PROPERTY_USAGE_STORAGE == 0 or name in NOT_KEYS: continue
		if property.type == TYPE_OBJECT:
			if material.get(name) != null: key[name] = true
		elif property.type in [TYPE_BOOL, TYPE_INT] and material.get(name) != fresh.get(name):
			key[name] = material.get(name)
	return key

## A Label3D's key: the properties its material is made from that differ from
## a new Label3D, and whether its font draws from a distance field.
static func label_key(label: Label3D) -> Dictionary:
	var fresh := Label3D.new()
	var key: Dictionary = {}
	for name: String in LABEL_KEYS:
		if label.get(name) != fresh.get(name): key[name] = label.get(name)
	fresh.free()
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	while font is FontVariation and (font as FontVariation).base_font != null: font = (font as FontVariation).base_font
	if font != null and font.get("multichannel_signed_distance_field") == true: key["msdf"] = true
	return key

## What the warm-up draws, in order: ["m", index] into MATERIALS, ["s", index]
## into shaders(), ["l", index] into LABELS. The chapter `first` draws comes
## first (CHAPTERS), then everything else in list order.
static func order(first: String) -> Array:
	var result: Array = []
	var chosen: Dictionary = CHAPTERS.get(first, {})
	for kind: String in ["m", "s", "l"]:
		for index: int in chosen.get(kind, []): result.append([kind, index])
	var counts := {"m": MATERIALS.size(), "s": shaders().size(), "l": LABELS.size()}
	for kind: String in ["m", "s", "l"]:
		for index in range(counts[kind]):
			if [kind, index] not in result: result.append([kind, index])
	return result

## Every ShaderMaterial shader the worlds draw.
static func shaders() -> Array[Shader]:
	return [SpiritFace.SHADER, LabelBubble.body_material(false, false).shader, LabelBubble.body_material(false, true).shader, ObjectMotionTrail.SOFT_SHADER, SeedMotionTrail.PATH_SHADER, BallRotationBlur.SPIN_SHADER, BallRotationBlur.BAND_SHADER]

## A material with exactly that key (a small white texture for each texture).
static func material_for(key: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	for name: String in key:
		# Texture properties read null until set; switches and modes never do.
		material.set(name, _texture() if material.get(name) == null else key[name])
	return material

static var _white: ImageTexture
static func _texture() -> ImageTexture:
	if _white == null:
		var image := Image.create(4, 4, true, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		image.generate_mipmaps()
		_white = ImageTexture.create_from_image(image)
	return _white

# --- Drawing ---

func _open() -> void:
	if _stamp_matches():
		_done = true
		return
	# The order is kept for the whole run, so a resumed warm-up goes on
	# exactly where it stopped.
	if _order.is_empty(): _order = order(str(next_chapter.call()) if next_chapter.is_valid() else "")
	_items.clear()
	var shader_list := shaders()
	for entry: Array in _order:
		var kind: String = entry[0]
		var index: int = entry[1]
		if kind == "l":
			_items.append({"label": LABELS[index]})
			continue
		var material: Material = material_for(MATERIALS[index]) if kind == "m" else ShaderMaterial.new()
		if kind == "s": (material as ShaderMaterial).shader = shader_list[index]
		# Beside the lamp, then out of its reach: one program a frame.
		_items.append({"material": material, "lit": true})
		_items.append({"material": material, "lit": false})
	if _next >= _items.size():
		_finish()
		return
	var root := get_tree().root
	var quality := _quality()
	_view = SubViewport.new()
	_view.name = "GlWarmup"
	_view.size = VIEW_SIZE
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The live view's 3D buffer settings, so each program is the one it draws.
	_view.scaling_3d_mode = root.scaling_3d_mode
	_view.scaling_3d_scale = root.scaling_3d_scale
	_view.msaa_3d = root.msaa_3d
	add_child(_view)
	# The chapters' environment and lights (island_world._ready, kit/look.gd).
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	_view.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	_view.add_child(sun)
	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees = Vector3(28, 145, 0)
	bounce.visible = GraphicsPolicy.fill_light(quality)
	_view.add_child(bounce)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-2, 0.5, 0.5)
	lamp.omni_range = 1.5
	_view.add_child(lamp)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 0, 5)
	camera.current = true
	_view.add_child(camera)
	# One quad beside the lamp and one out of its reach.
	var quad := QuadMesh.new()
	_lit = _quad(quad, Vector3(-2, 0, 0))
	_unlit = _quad(quad, Vector3(2, 0, 0))
	_label_lit = _label(Vector3(-2, 0, 0.1))
	_label_unlit = _label(Vector3(2, 0, 0.1))
	_shown = -1
	_drawn = false
	RenderingServer.frame_post_draw.connect(_on_drawn)

func _quad(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.visible = false
	_view.add_child(node)
	return node

func _label(at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = "0"
	label.position = at
	label.visible = false
	_view.add_child(label)
	return label

func _show(index: int) -> void:
	var item: Dictionary = _items[index]
	var material: Material = item.get("material")
	for quad: MeshInstance3D in [_lit, _unlit]:
		quad.material_override = material
		quad.visible = material != null and bool(item.get("lit")) == (quad == _lit)
	for label: Label3D in [_label_lit, _label_unlit]:
		label.visible = item.has("label")
		if item.has("label"): _label_as(label, item.label)
	_shown = index
	_drawn = false

## Sets a label's key; its font is the bubbles' font, which draws from a
## distance field exactly when the key says so.
static func _label_as(label: Label3D, key: Dictionary) -> void:
	var fresh := Label3D.new()
	for name: String in LABEL_KEYS: label.set(name, key.get(name, fresh.get(name)))
	fresh.free()
	label.font = LabelBubble.shared_font()

func _finish() -> void:
	_done = true
	_close()
	var file := FileAccess.open(stamp_path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"stamp": _stamp()}))
	file.close()

func _close() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn): RenderingServer.frame_post_draw.disconnect(_on_drawn)
	if is_instance_valid(_view): _view.queue_free()
	_view = null
	_shown = -1
	_drawn = false

# --- Done once per engine, driver, look and key set ---

func _stamp() -> String:
	var root := get_tree().root
	var keys: Array = [MATERIALS, LABELS]
	for shader: Shader in shaders(): keys.append(shader.code.md5_text())
	return "|".join([Engine.get_version_info().string, RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(), str(OS.get_video_adapter_driver_info()), str(root.scaling_3d_scale), str(root.msaa_3d), str(GraphicsPolicy.fill_light(_quality())), str(keys.hash())])

func _quality() -> String:
	var saved: Variant = settings.call() if settings.is_valid() else {}
	return GraphicsPolicy.normalize(saved.get("graphics_quality") if saved is Dictionary else null)

func _stamp_matches() -> bool:
	if not FileAccess.file_exists(stamp_path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(stamp_path))
	return parsed is Dictionary and str(parsed.get("stamp", "")) == _stamp()
