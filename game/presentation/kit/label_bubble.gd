extends Node3D
## World kit: a speech bubble that names a lever, switch or pad. One rounded
## body with a tail floats over the control and points down at it; inside sit
## one pill per value, so a selector reads as a single choice with the current
## value filled and the others dimmed. A single word (a pad's name) uses the
## same bubble with no pill. Values are passed raw ("low", "stowed") and shown
## upper-cased.
##
##   var bubble := LabelBubble.create(terrain, lever_top, ["rose", "moss"], "rose")
##   bubble.set_selected("moss")      # every frame is fine: colours only
##   bubble.highlight(1, rose_colour) # by index, with the chosen pill's own fill
##   bubble.set_lift(0.6)             # rise clear of a spirit standing behind it
##   bubble.set_bob(true)             # gentle idle bob, off by default
##
## The tail's tip never leaves its anchor. A lift or the bob moves the body,
## pills and letters; the tail stretches (and leans, when its tip lies beyond
## the body's straight edge) so its tip stays on the anchor on the fixed
## journey view plane. A tail never grows past MAX_TAIL: a lift that would
## need more is cut short.
##
## The node sits at its parent's origin, so every piece keeps parent-space
## positions. `labels` holds one Label3D per value; each carries meta "backing",
## its pill: a MeshInstance3D with its own QuadMesh and StandardMaterial3D,
## because worlds may resize, recolour or restyle a single pill (Turn of the
## Tide re-lays its pills, Long Way Home tints the lamp's chosen pill).
##
## Shared once for every bubble: the body shader, its four material variants,
## the unit body quad, the pill texture and the font. Nothing is allocated per
## frame; a highlight only changes colours, the body swaps between cached materials,
## and the body refits only when its pills move or resize. Each body tells the
## shared shader its own tail stretch through one per-instance uniform, sent
## only when it changes.

const NUNITO = preload("res://assets/fonts/nunito.ttf")
## Letters stay at 30 px: worlds that restyle pills scale pixel_size from it.
const FONT_SIZE := 30
const PIXEL_SIZE := 0.0092
const INK := Color("21403a")
## The chosen value: a deep teal pill with cream letters.
const ACTIVE_FILL := Color("2c6458")
const ACTIVE_INK := Color("fff6e2")
const DIM := 0.42
const CLEAR := Color(1, 1, 1, 0)
## The body: warm cream for dark letters, deep teal for light ones.
const FILL := Color("fff6e2")
const EDGE := Color("b98d5f")
const DARK_FILL := Color("1b4740")
const DARK_EDGE := Color("e9edd6")
const PILL_HEIGHT := 0.36
const PILL_PAD := 0.12
const GAP := 0.04
const PAD := Vector2(0.07, 0.07)
const TAIL := 0.18
const EDGE_WIDTH := 0.028
const RADIUS := 0.20
## Pills sit this far nearer the camera than the body, letters twice as far,
## so the layers never share a depth. Draw order is body (priority 0, writes
## depth so scenery behind never shows through), pills (1), letters (2), the
## same layer as spirits' badges, which never test depth.
const NUDGE := 0.03
## The journey worlds' camera offset, used to lay out pills before a camera
## exists (see cooperative_world._frame_camera).
const VIEW := Vector3(3, 13, 10)
## The body's z scale carries the tail's sideways offset (the quad is flat,
## so z scale is otherwise unused): scale.z = TAIL_CODE + offset in metres.
const TAIL_CODE := 8.0
const BOB_HEIGHT := 0.035
const BOB_SPEED := 2.1
## The longest a tail may grow (metres on screen), settled length included:
## room for the highest lift any chapter asks for (Turn of the Tide climbs its
## tide bubble about 2.4 m over a spirit and its gauges, a 1.7 m tail).
const MAX_TAIL := 2.0
## The per-instance shader uniform: how much longer than TAIL the tail is
## drawn, so its tip reaches the anchor wherever the body stands.
const STRETCH := &"tail_stretch"

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_always%s;
uniform vec4 fill : source_color;
uniform vec4 edge : source_color;
uniform float edge_width = 0.028;
uniform float radius = 0.2;
uniform float tail = 0.18;
uniform float tail_code = 8.0;
instance uniform float tail_stretch = 0.0;
varying vec2 local;
varying vec2 size;
varying float tail_x;
varying float tail_length;

void vertex() {
	size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	tail_x = length(MODEL_MATRIX[2].xyz) - tail_code;
	tail_length = max(tail + tail_stretch, 0.0);
	// The quad spans the body and the tail below it, down to the tip and wide
	// enough for a tip that lies beyond the body's side.
	float top = (size.y - tail) * 0.5;
	float half_width = max(size.x * 0.5, abs(tail_x) + 0.02);
	local = vec2(VERTEX.x * 2.0 * half_width, mix(-top - tail_length - 0.02, top, VERTEX.y + 0.5));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX = vec3(local, 0.0);
}

float round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed distance to the triangle a, b, c.
float triangle(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a;
	vec2 e1 = c - b;
	vec2 e2 = a - c;
	vec2 v0 = p - a;
	vec2 v1 = p - b;
	vec2 v2 = p - c;
	vec2 q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(q0, q0), s * (v0.x * e0.y - v0.y * e0.x)), vec2(dot(q1, q1), s * (v1.x * e1.y - v1.y * e1.x))), vec2(dot(q2, q2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

void fragment() {
	vec2 half_body = vec2(size.x, size.y - tail) * 0.5;
	float corner = min(radius, half_body.y);
	float body = round_box(local, half_body, corner);
	float reach = max(half_body.x - corner - tail * 0.62, 0.0);
	// The tip lands exactly on the anchor; only the root keeps to the body's
	// straight edge, so the tail leans when its tip lies beyond that edge.
	vec2 tip = vec2(tail_x, -half_body.y - tail_length);
	float root_x = clamp(tail_x, -reach, reach);
	float root_y = -half_body.y + 0.04;
	float tip_d = triangle(local, tip, vec2(root_x - tail * 0.62, root_y), vec2(root_x + tail * 0.62, root_y));
	float k = 0.05;
	float h = clamp(0.5 + 0.5 * (tip_d - body) / k, 0.0, 1.0);
	float d = mix(tip_d, body, h) - k * h * (1.0 - h);
	float w = max(fwidth(d), 0.0005);
	float inside = 1.0 - smoothstep(-w, w, d);
	if (inside < 0.02) discard;
	float core = 1.0 - smoothstep(-edge_width - w, -edge_width + w, d);
	vec4 color = mix(edge, fill, core);
	ALBEDO = color.rgb;
	ALPHA = color.a * inside;
}
"""

static var _font: FontVariation
static var _pill_texture: ImageTexture
static var _body_mesh: QuadMesh
static var _shaders: Dictionary = {}
static var _bodies: Dictionary = {}

const SCRIPT_PATH := "res://presentation/kit/label_bubble.gd"

var labels: Array[Label3D] = []
## The raw values, in label order.
var values: Array = []
var body: MeshInstance3D
## Where the tail points, in parent space.
var anchor := Vector3.ZERO
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _forward := Vector3.FORWARD
## How far the body is raised to clear a spirit (metres); the tail stretches.
var lift := 0.0
var _bob := false
var _bob_time := 0.0
## The tail stretch last sent to the shader (its default is 0).
var _stretch := 0.0

## A new bubble under parent with its tail's tip at anchor_at (parent space).
## options are raw values; selected is a raw value or an index (null: none
## chosen yet). shift: see build().
static func create(parent: Node3D, anchor_at: Vector3, options: Array, selected: Variant = null, shift: float = 0.0) -> Node3D:
	var bubble: Node3D = load(SCRIPT_PATH).new()
	bubble.build(parent, anchor_at, options, shift)
	if selected != null: bubble.set_selected(selected)
	return bubble

## Builds the bubble under parent with its tail's tip at `at` (parent space).
## options: one entry for a plain name, two or more for a selector's choices.
## shift moves the body sideways on screen (metres) while the tail keeps
## pointing at `at`, to clear a nearby prop.
func build(parent: Node3D, at: Vector3, options: Array, shift: float = 0.0) -> void:
	name = "LabelBubble"
	anchor = at
	values = options.duplicate()
	var shown: Array[String] = []
	for value: Variant in options: shown.append(str(value).to_upper())
	parent.add_child(self)
	_axes_from(VIEW)
	var font := shared_font()
	var widths: Array[float] = []
	var total := -GAP
	for text: String in shown:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x * PIXEL_SIZE + PILL_PAD * 2.0
		widths.append(width)
		total += width + GAP
	var body_height := PILL_HEIGHT + PAD.y * 2.0
	# The tail must still reach its anchor from inside the body's straight edge.
	var reach := maxf((total + PAD.x * 2.0) * 0.5 - minf(RADIUS, body_height * 0.5) - TAIL * 0.62 - 0.02, 0.0)
	shift = clampf(shift, -reach, reach)
	# Lifted straight up until the tail's tip lands on the anchor on screen.
	var center := at + Vector3(0, (body_height * 0.5 + TAIL) / maxf(_up.y, 0.2), 0) + _right * shift
	body = MeshInstance3D.new()
	body.name = "BubbleBody"
	body.mesh = _shared_body_mesh()
	body.material_override = body_material(false, false)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's bounds hold the settled tail; a stretched one reaches further.
	body.extra_cull_margin = MAX_TAIL
	body.position = center
	body.scale = Vector3(total + PAD.x * 2.0, body_height + TAIL, TAIL_CODE - shift)
	add_child(body)
	var x := -total * 0.5
	for index in range(shown.size()):
		var middle := center + _right * (x + widths[index] * 0.5)
		x += widths[index] + GAP
		var shape := QuadMesh.new()
		shape.size = Vector2(widths[index], PILL_HEIGHT)
		var pill := MeshInstance3D.new()
		pill.name = "BubblePill"
		pill.mesh = shape
		pill.material_override = _pill_material()
		pill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pill.extra_cull_margin = 1.0
		pill.position = middle - _forward * NUDGE
		add_child(pill)
		var label := Label3D.new()
		label.text = shown[index]
		label.font = font
		label.font_size = FONT_SIZE
		label.pixel_size = PIXEL_SIZE
		label.outline_size = 0
		label.modulate = INK
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.render_priority = 2
		label.outline_render_priority = 1
		label.extra_cull_margin = 1.0
		label.position = middle - _forward * NUDGE * 2.0
		label.set_meta("backing", pill)
		add_child(label)
		labels.append(label)
	highlight(-1)

## Fills the chosen value's pill with accent (cream letters) and dims the
## others; -1 shows every value plainly. Only colours change, and only when
## they differ.
func highlight(index: int, accent: Color = ACTIVE_FILL) -> void:
	for i in range(labels.size()):
		var label := labels[i]
		var chosen := i == index
		var ink := ACTIVE_INK if chosen else (INK if index < 0 else Color(INK, DIM))
		if label.modulate != ink: label.modulate = ink
		var plate := (label.get_meta("backing") as MeshInstance3D).material_override as StandardMaterial3D
		var color := accent if chosen else CLEAR
		if plate.albedo_color != color: plate.albedo_color = color

## Highlights a value by its raw value ("rose") or index; anything not found
## shows every value plainly.
func set_selected(value: Variant, accent: Color = ACTIVE_FILL) -> void:
	highlight(value if value is int else values.find(value), accent)

## Raises the body, pills and letters by `metres` to clear a spirit standing
## behind it on screen, while the tail stretches to keep its tip on the anchor;
## 0 settles it back over its control. A lift past max_lift() is cut to it.
func set_lift(metres: float) -> void:
	metres = minf(metres, max_lift())
	if is_equal_approx(metres, lift): return
	lift = metres
	position.y = lift + _bob_offset()
	_fit_tail()

## The highest lift whose tail, bob included, stays within MAX_TAIL.
func max_lift() -> float:
	if not is_instance_valid(body): return 0.0
	var settled := (body.position - anchor).dot(_up) - (body.scale.y - TAIL) * 0.5
	return maxf((MAX_TAIL - settled) / maxf(_up.y, 0.2) - BOB_HEIGHT, 0.0)

## The gentle idle bob: the body rises and falls a few centimetres; the tail's
## tip stays put.
func set_bob(enabled: bool) -> void:
	_bob = enabled
	_bob_time = absf(anchor.x)
	position.y = lift + _bob_offset()
	_fit_tail()

func _bob_offset() -> float:
	return sin(_bob_time * BOB_SPEED) * BOB_HEIGHT if _bob else 0.0

## Stretches the tail so its tip lands on the anchor on the fixed view plane,
## wherever the body now stands (lifted, bobbing or refitted around its
## pills). Sends the shader a new stretch only when it changed.
func _fit_tail() -> void:
	if not is_instance_valid(body): return
	var drop := (position + body.position - anchor).dot(_up)
	var stretch := drop - (body.scale.y - TAIL) * 0.5 - TAIL
	if absf(stretch - _stretch) < 0.0001: return
	_stretch = stretch
	body.set_instance_shader_parameter(STRETCH, stretch)

## The body's rectangle on screen with its settled tail's height below it
## (the box placement works with, as plane_rect); settled = as if not lifted.
func screen_rect(camera: Camera3D, settled: bool = false) -> Rect2:
	if not is_instance_valid(body) or camera.is_position_behind(body.global_position): return Rect2()
	var center := body.global_position
	if settled and get_parent() is Node3D: center -= global_position - (get_parent() as Node3D).global_position
	var metre := camera.get_viewport().get_visible_rect().size.y / maxf(camera.size, 0.01)
	var size := Vector2(body.scale.x, body.scale.y) * metre
	var at := camera.unproject_position(center)
	return Rect2(at.x - size.x * 0.5, at.y - size.y * 0.5 + TAIL * 0.5 * metre, size.x, size.y)

## Where the tail's tip lands on screen, as the shader draws it: on the anchor.
func tail_tip(camera: Camera3D) -> Vector2:
	var metre := camera.get_viewport().get_visible_rect().size.y / maxf(camera.size, 0.01)
	var at := camera.unproject_position(body.global_position)
	return at + Vector2((body.scale.z - TAIL_CODE) * metre, _tip_drop() * metre)

## A bubble's rectangle on the journey view plane, in metres: x along screen
## right, y down the screen (like pixels), from world positions alone, so it
## is the same on every platform and viewport. settled = as if not lifted.
## It is the box placement works with: the body and its settled tail's height
## below it (TAIL), moving with the body as it lifts. The stretched tail down
## to the anchor is in plane_span; the tip itself is plane_tail.
func plane_rect(settled: bool = false) -> Rect2:
	var center := body.global_position
	if settled and get_parent() is Node3D: center -= global_position - (get_parent() as Node3D).global_position
	var at := plane_point(center)
	return Rect2(at.x - body.scale.x * 0.5, at.y - body.scale.y * 0.5 + TAIL * 0.5, body.scale.x, body.scale.y)

## Where the tail's tip lands on the journey view plane, as the shader draws
## it: the anchor's point, however the body is lifted or bobbing.
func plane_tail() -> Vector2:
	return plane_point(body.global_position) + Vector2(body.scale.z - TAIL_CODE, _tip_drop())

## Everything the bubble covers on the view plane: plane_rect grown to hold
## the whole tail down to its tip, which stays on the anchor either way.
func plane_span(settled: bool = false) -> Rect2:
	return plane_rect(settled).expand(plane_tail())

## How far the tip lies below the body's centre on the view plane (metres).
func _tip_drop() -> float:
	return (body.scale.y - TAIL) * 0.5 + TAIL + _stretch

## A world point on the journey view plane (see plane_rect).
static func plane_point(world: Vector3) -> Vector2:
	var right := (-VIEW.normalized()).cross(Vector3.UP).normalized()
	return Vector2(world.dot(right), -world.dot(screen_up()))

## The journey camera's screen-up direction in world space.
static func screen_up() -> Vector3:
	var forward := -VIEW.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return right.cross(forward).normalized()

func _process(delta: float) -> void:
	if _bob:
		_bob_time += delta
		position.y = lift + _bob_offset()
	sync()

## Keeps the pills on one screen row and the body fitted around them, after
## any world has moved, resized or restyled pills. Cheap when nothing moved.
func sync() -> void:
	if labels.is_empty() or not is_instance_valid(body): return
	# The fixed journey view, never the live camera: placement must not depend
	# on the viewport, the platform or how many frames ran before framing.
	_axes_from(VIEW)
	var row := 0.0
	for label: Label3D in labels:
		row += (label.get_meta("backing") as Node3D).position.dot(_up)
	row /= float(labels.size())
	var origin: Vector3 = (labels[0].get_meta("backing") as Node3D).position
	var low := INF
	var high := -INF
	var tall := 0.0
	var depth := -INF
	for label: Label3D in labels:
		var pill: MeshInstance3D = label.get_meta("backing")
		_onto_row(pill, row)
		_onto_row(label, row)
		var size: Vector2 = (pill.mesh as QuadMesh).size * pill.scale.x
		var along := (pill.position - origin).dot(_right)
		low = minf(low, along - size.x * 0.5)
		high = maxf(high, along + size.x * 0.5)
		tall = maxf(tall, size.y)
		depth = maxf(depth, (pill.position - origin).dot(_forward))
	var center := origin + _right * ((low + high) * 0.5) + _forward * (depth + NUDGE)
	var tail_x := (anchor - center).dot(_right)
	var scale_wanted := Vector3(high - low + PAD.x * 2.0, tall + PAD.y * 2.0 + TAIL, TAIL_CODE + tail_x)
	if not body.position.is_equal_approx(center): body.position = center
	if not body.scale.is_equal_approx(scale_wanted): body.scale = scale_wanted
	if lift > max_lift(): set_lift(lift)
	_fit_tail()
	# Dark letters on every value (the chosen one may be cream on its pill)
	# take the cream body; a world that letters every value light, the teal.
	var light := true
	for label: Label3D in labels:
		if label.modulate.get_luminance() <= 0.55: light = false
	var material := body_material(light, labels[0].no_depth_test)
	if body.material_override != material: body.material_override = material

func _onto_row(node: Node3D, row: float) -> void:
	var off := row - node.position.dot(_up)
	if absf(off) > 0.002 and absf(_up.z) > 0.1: node.position.z += off / _up.z

func _axes_from(offset: Vector3) -> void:
	_forward = -offset.normalized()
	_right = _forward.cross(Vector3.UP).normalized()
	_up = _right.cross(_forward).normalized()

static func shared_font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = NUNITO
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800.0}
	return _font

## One of four shared body materials: cream or deep teal, and drawn over
## scenery or depth tested. Over-scenery bodies sit just under the
## pills of worlds that draw pills over scenery (render priority 3 and up).
static func body_material(light_text: bool, over: bool) -> ShaderMaterial:
	var key := int(light_text) * 2 + int(over)
	var cached: ShaderMaterial = _bodies.get(key)
	if cached != null: return cached
	var shader: Shader = _shaders.get(over)
	if shader == null:
		shader = Shader.new()
		# A Windows checkout may store this file with CRLF line ends; the shader
		# code is the same on every platform only with LF.
		shader.code = (SHADER % (", depth_test_disabled" if over else "")).replace("\r", "")
		_shaders[over] = shader
	cached = ShaderMaterial.new()
	cached.shader = shader
	cached.set_shader_parameter("fill", DARK_FILL if light_text else FILL)
	cached.set_shader_parameter("edge", DARK_EDGE if light_text else EDGE)
	cached.set_shader_parameter("edge_width", EDGE_WIDTH)
	cached.set_shader_parameter("radius", RADIUS)
	cached.set_shader_parameter("tail", TAIL)
	cached.set_shader_parameter("tail_code", TAIL_CODE)
	cached.render_priority = 2 if over else 0
	_bodies[key] = cached
	return cached

static func _shared_body_mesh() -> QuadMesh:
	if _body_mesh == null:
		_body_mesh = QuadMesh.new()
		_body_mesh.size = Vector2.ONE
	return _body_mesh

## A pill's own material over the shared rounded texture.
static func _pill_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = pill_texture()
	mat.albedo_color = CLEAR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.render_priority = 1
	return mat

## A white rounded pill with soft edges, built once.
static func pill_texture() -> ImageTexture:
	if _pill_texture != null: return _pill_texture
	var w := 192
	var h := 72
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var radius := float(h) * 0.5 - 1.0
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5 - float(w) * 0.5, float(y) + 0.5 - float(h) * 0.5)
			var q := Vector2(absf(p.x) - (float(w) * 0.5 - 1.0 - radius), absf(p.y) - (float(h) * 0.5 - 1.0 - radius))
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			image.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - d, 0.0, 1.0)))
	image.generate_mipmaps()
	_pill_texture = ImageTexture.create_from_image(image)
	return _pill_texture
