extends Node
## Plays an ending scene (services/ending_scene.gd) in a chapter world with
## its real pips, their animations and the world's camera, then hands all of it
## back. While it plays it owns the world: the world's own frame (pips easing
## to the snapshot, its camera, pan and zoom) is paused, and every frame here
## puts the pips, camera and props where the timeline says for this moment, so
## the scene is the same at any frame rate. Its placeholder props are built
## when it starts and freed when it ends, so nothing of it exists while a world
## is built, folded or fingerprinted.
##
## A tap skips to the end when `skippable`; otherwise taps are held so nothing
## under the scene is pressed. finished(watched) comes once: true when the
## scene reached its end (played or skipped), false when stop() cut it short.
## The caller presents its snapshot again afterwards.
const EndingScene = preload("res://services/ending_scene.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const Models = preload("res://presentation/kit/models.gd")
const SafeArea = preload("res://presentation/safe_area.gd")

signal finished(watched: bool)

var skippable := false
var reduced_motion := false
## A soundscape (services/soundscape.gd) for the scene's fixed cues, or null.
var soundscape: Node
## The caption's font, or the theme's.
var caption_font: Font
var t := 0.0
var compiled: Dictionary = {}
var slots: Dictionary = {}
var playing := false

var _world: Node3D
var _root: Node3D
var _props: Dictionary = {}
var _materials: Dictionary = {}
var _layer: Control
var _caption: Label
## The screen layer's letterbox bars and colour wash (EndingScene "bars", "tint").
var _bars: Array[ColorRect] = []
var _tint: ColorRect
## How much of the screen's height each bar covers when fully in.
const BAR_SHARE := 0.1
const BAR_COLOR := Color(0.03, 0.04, 0.05)
var _held: Dictionary = {}
var _faces: Dictionary = {}
## The role badges ("You", "Waiting") hidden while the scene plays.
var _badges: Array[Node3D] = []

## Starts `data` in `world`, cast from `snapshot` (the final one shown), with
## its tap catcher and caption in `overlay` (a full-screen Control) when given.
## False, changing nothing, when the world has no pips to cast.
func start(world: Node3D, data: Dictionary, snapshot: Dictionary, overlay: Control = null) -> bool:
	if playing or not is_instance_valid(world) or not EndingScene.check(data).is_empty(): return false
	slots = EndingScene.cast(data, snapshot)
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	if not actors.has(slots.carrier) or not actors.has(slots.other): return false
	_world = world
	var camera: Camera3D = world.get("camera")
	var exploration: Node = world.get("camera_exploration")
	if is_instance_valid(exploration):
		exploration.reset_view()
		_held.manual = exploration.manual
		exploration.manual = true
	_held.processing = world.is_processing()
	world.set_process(false)
	for slot: String in [slots.carrier, slots.other]:
		for badge: Node in (actors[slot] as Node).find_children("*", "Label3D", true, false):
			if badge.has_meta("replay_role_badge") and (badge as Node3D).visible:
				(badge as Node3D).visible = false
				_badges.append(badge)
	if is_instance_valid(camera):
		_held.camera = {"transform": camera.transform, "size": camera.size, "h_offset": camera.h_offset, "v_offset": camera.v_offset, "keep_aspect": camera.keep_aspect, "projection": camera.projection}
	var at := {"carrier": _local(actors[slots.carrier]), "other": _local(actors[slots.other])}
	at.origin = (at.carrier + at.other) * 0.5
	var origin := str(data.get("origin", "pips"))
	if origin != "pips" and world.has_method("ending_anchor"):
		var anchor: Variant = world.call("ending_anchor", origin)
		if anchor is Vector3: at.origin = anchor
	at.camera = camera.position - ViewFit.CAMERA_FROM if is_instance_valid(camera) else at.origin
	at.camera_size = camera.size if is_instance_valid(camera) else 10.0
	var view := world.get_viewport().get_visible_rect().size
	if view.y > 0.0: at.aspect = view.x / view.y
	compiled = EndingScene.compile(data, at)
	_build_props(data.get("props", {}))
	if overlay != null: _build_layer(overlay)
	t = 0.0
	playing = true
	_fire(-1.0, 0.0)
	_apply(EndingScene.state(compiled, 0.0), 0.0, true)
	return true

func duration() -> float:
	return float(compiled.get("duration", 0.0))

## A frame moves the scene on by at most this (seconds), so a hitch or the app
## coming back never jumps a must-watch scene to its end unseen.
const LONGEST_FRAME := 0.1

func _process(delta: float) -> void:
	if playing: advance(minf(delta, LONGEST_FRAME))

## Moves the scene on by `delta` seconds (the frame's, or a test's).
func advance(delta: float) -> void:
	if not playing or delta <= 0.0: return
	var before := t
	t = minf(t + delta, duration())
	_fire(before, t)
	_apply(EndingScene.state(compiled, t), delta, false)
	if t >= duration(): _end(true)

## Jumps to the end when the scene may be skipped. True when it did.
func skip() -> bool:
	if not playing or not skippable: return false
	t = duration()
	_apply(EndingScene.state(compiled, t), 0.0, true)
	_end(true)
	return true

## Ends the scene where it is (Back, the app leaving): not watched.
func stop() -> void:
	if playing: _end(false)

## Leaving the tree mid-scene (the screen closing) hands the world back too,
## quietly: nothing is left to draw a card on.
func _exit_tree() -> void:
	if playing: _end(false, false)

func _local(node: Node3D) -> Vector3:
	return _world.to_local(node.global_position)

func _fire(from: float, to: float) -> void:
	for event: Dictionary in EndingScene.events_between(compiled, from, to):
		if event.kind == "sound":
			if is_instance_valid(soundscape) and soundscape.has_method("play_fixed_cue"): soundscape.play_fixed_cue(event.cue, event.variant)
			continue
		var actor: Node3D = _world.actors[slots[event.who]]
		match str(event.kind):
			"hop": actor.play_hop(float(event.time))
			"wake": actor.play_wake(reduced_motion)
			"bump": actor.play_bump(reduced_motion)
			"cheer": actor.set_celebration(true, false, reduced_motion)

func _apply(now: Dictionary, delta: float, immediate: bool) -> void:
	for role: String in EndingScene.ROLES:
		var actor: Node3D = _world.actors[slots[role]]
		var shown: Dictionary = now.actors[role]
		var target: Vector3 = shown.position
		var before := _local(actor)
		actor.global_position = _world.to_global(target)
		if shown.facing != null: actor.facing_target = float(shown.facing)
		var face: StringName = shown.face
		if _faces.get(role, &"") != face:
			_faces[role] = face
			actor.set_expression(SpiritLook.NORMAL if face == &"" else face, immediate)
		actor.set_pose(shown.rest, {}, immediate)
		actor.set_ride_pose(0.0, Vector3.ZERO if reduced_motion else shown.lean)
		if immediate: actor.reset_motion()
		elif delta > 0.0: actor.advance_motion(Vector3.ZERO if shown.carried else target - before, delta, reduced_motion)
	if _world.has_method("update_spirit_attention"): _world.update_spirit_attention()
	var camera: Camera3D = _world.get("camera")
	if is_instance_valid(camera):
		var center: Vector3 = now.camera.center
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.position = center + Basis(Vector3.UP, deg_to_rad(float(now.camera.get("orbit", 0.0)))) * ViewFit.CAMERA_FROM
		camera.look_at(_world.to_global(center))
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.size = ViewFit.viewport(float(now.camera.size), _world)
		# A shake sways the view like a big change's, and its settings turn it off.
		var sway: Vector2 = now.camera.get("shake", Vector2.ZERO) * camera.size
		if sway != Vector2.ZERO and not reduced_motion and _world.get("big_change_shake") != false: camera.position += camera.basis.x * sway.x + camera.basis.y * sway.y
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	for id: String in _props:
		var prop: Dictionary = now.props[id]
		var node: Node3D = _props[id]
		node.visible = prop.shown and float(prop.alpha) > 0.0
		node.position = prop.position
		node.rotation.y = float(node.get_meta("yaw", 0.0)) + float(prop.spin)
		if _materials.has(id): (_materials[id] as StandardMaterial3D).albedo_color.a = clampf(float(prop.alpha), 0.0, 1.0)
	var screen: Dictionary = now.get("screen", {})
	if is_instance_valid(_tint):
		var wash: Color = screen.get("tint", Color.BLACK)
		_tint.color = Color(wash.r, wash.g, wash.b, clampf(float(screen.get("tint_alpha", 0.0)), 0.0, 1.0))
		_tint.visible = _tint.color.a > 0.001
	var bars := clampf(float(screen.get("bars", 0.0)), 0.0, 1.0) * BAR_SHARE
	if _bars.size() == 2:
		_bars[0].anchor_bottom = bars
		_bars[1].anchor_top = 1.0 - bars
		for bar: ColorRect in _bars: bar.visible = bars > 0.0001
	if is_instance_valid(_caption):
		_caption.text = str(now.caption)
		_caption.visible = not _caption.text.is_empty()

func _build_props(specs: Dictionary) -> void:
	_root = Node3D.new()
	_root.name = "EndingScene"
	# Named and marked, so nothing of it is ever folded into the scenery.
	_root.set_meta("ending_scene", true)
	_world.add_child(_root)
	for id: String in specs:
		var spec: Dictionary = specs[id]
		if str(spec.shape) == "model":
			_props[id] = _model_prop(id, spec)
			continue
		var size: Array = spec.size
		var mesh: Mesh
		match str(spec.shape):
			"box": mesh = Primitives.box_mesh(Vector3(float(size[0]), float(size[1]), float(size[2])))
			"sphere": mesh = Primitives.sphere_mesh(float(size[0]))
			"cylinder": mesh = Primitives.cylinder_mesh(float(size[0]), float(size[1]))
			"cone": mesh = Primitives.cylinder_mesh(float(size[0]), float(size[1]), 0.0)
		var material := Primitives.fresh_material(Color(str(spec.get("color", "ffffff"))))
		if float(spec.get("glow", 0.0)) > 0.0:
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_energy_multiplier = float(spec.glow)
		if _fades(id, spec):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_materials[id] = material
		var node := Primitives.mesh_node(mesh, material, Vector3.ZERO, _root)
		node.name = id
		node.set_meta("ending_prop", id)
		var turn: Array = spec.get("rot", [0, 0, 0])
		node.rotation_degrees = Vector3(float(turn[0]), float(turn[1]), float(turn[2]))
		node.set_meta("yaw", node.rotation.y)
		_props[id] = node

## A model prop (EndingScene: shape "model"): the part as one painted mesh,
## its own see-through copy of the palette look when it fades.
func _model_prop(id: String, spec: Dictionary) -> Node3D:
	var colors: Dictionary = {}
	for slot: String in spec.get("colors", {}): colors[slot] = Color(str(spec.colors[slot]))
	var node := Models.moving(str(spec.model), str(spec.part), colors, _root, false)
	node.name = id
	node.set_meta("ending_prop", id)
	node.scale = Vector3.ONE * float(spec.get("scale", 1.0))
	if _fades(id, spec):
		var material := (node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.remove_meta(Primitives.SHARED_META)
		node.material_override = material
		_materials[id] = material
	var turn: Array = spec.get("rot", [0, 0, 0])
	node.rotation_degrees = Vector3(float(turn[0]), float(turn[1]), float(turn[2]))
	node.set_meta("yaw", node.rotation.y)
	return node

func _fades(id: String, spec: Dictionary) -> bool:
	if float(spec.get("alpha", 1.0)) < 1.0: return true
	return not compiled.props[id].alphas.is_empty()

func _build_layer(overlay: Control) -> void:
	_layer = Control.new()
	_layer.name = "EndingScene"
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.gui_input.connect(_tapped)
	overlay.add_child(_layer)
	overlay.visible = true
	# Under the caption: the colour wash, then the bars over it.
	_tint = ColorRect.new()
	_tint.name = "Tint"
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	_layer.add_child(_tint)
	SafeArea.bleed(_tint)
	for edge: String in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = edge + "Bar"
		bar.color = BAR_COLOR
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if edge == "Top" else 1.0
		bar.anchor_bottom = 0.0 if edge == "Top" else 1.0
		bar.visible = false
		_layer.add_child(bar)
		_bars.append(bar)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -120.0
	_caption.offset_bottom = -48.0
	_caption.add_theme_font_size_override("font_size", 44)
	if caption_font != null: _caption.add_theme_font_override("font", caption_font)
	_caption.add_theme_color_override("font_color", ControlTheme.CREAM)
	_caption.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.12, 0.85))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_layer.add_child(_caption)

func _tapped(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed: skip()

func _end(watched: bool, tell: bool = true) -> void:
	playing = false
	for role: String in EndingScene.ROLES:
		var actor: Node3D = _world.actors.get(slots[role])
		if not is_instance_valid(actor): continue
		actor.end_ride()
		actor.set_expression(SpiritLook.NORMAL, true)
		actor.set_pose(SpiritIdle.REST, {}, true)
	var camera: Camera3D = _world.get("camera")
	if is_instance_valid(camera) and _held.has("camera"):
		var kept: Dictionary = _held.camera
		camera.projection = kept.projection
		camera.transform = kept.transform
		camera.size = kept.size
		camera.h_offset = kept.h_offset
		camera.v_offset = kept.v_offset
		camera.keep_aspect = kept.keep_aspect
	var exploration: Node = _world.get("camera_exploration")
	if is_instance_valid(exploration) and _held.has("manual"): exploration.manual = _held.manual
	_world.set_process(bool(_held.get("processing", true)))
	for badge: Node3D in _badges:
		if is_instance_valid(badge): badge.visible = true
	_badges.clear()
	if is_instance_valid(_root): _root.queue_free()
	if is_instance_valid(_layer): _layer.queue_free()
	_props.clear()
	_materials.clear()
	_held.clear()
	_faces.clear()
	if tell: finished.emit(watched)
