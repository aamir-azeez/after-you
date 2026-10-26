extends RefCounted
## What an outfit (services/outfit.gd) puts on one SpiritVisual, and how it
## comes off again. SpiritVisual.wear() makes one; nothing else does.
##
## Each worn item's art script (its descriptor's "art", in
## presentation/pip_wear/) has one function, `static func wear(look) -> void`,
## and changes the pip only through this object, so every change is undone
## exactly by undress():
## - attach(parent, node): adds a node under one of the pip's parts (head,
##   upper body, torso, a foot, the leaf). It moves with that part in every
##   pose (idle, walk, doze, wake), because the pip only ever moves its parts.
## - mesh(parent, mesh, material, frame): attach() for a mesh.
## - swap_mesh(part, mesh) and set_material(part, material): the torso, a foot
##   or the leaf drawn with another mesh or material. A swapped mesh must keep
##   the part's pivot as its origin (spirit_meshes.gd: the torso's centre, the
##   foot's centre, the leaf's stalk), because the pip moves and scales the
##   part's node, never its mesh. The head is never swapped or recoloured
##   this way: its material draws the eyes and cheeks.
## - set_face(shader, extra): the head's own colours from a variant of the
##   face shader (spirit_face.gdshaderinc); the eyes and cheeks stay drawn by
##   the shared body of that shader.
## - animate(step): step(seconds) poses the item's moving parts. It runs at the
##   idle card rate (ANIMATION_HZ) of the pip's own clock, so a replay, a still
##   snapshot and a live preview show the same thing at the same moment; under
##   Reduce motion it holds the first pose.
## Everything is presentation only: no collision shape, simulation value,
## recording or hash ever reads it.
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Outfit = preload("res://services/outfit.gd")
const SpiritFace = preload("res://presentation/spirit_face.gd")
const Look = preload("res://presentation/spirit_look.gd")

## The idle card rate (island_world.gd IDLE_CARD_HZ; test_pip_outfit pins it).
const ANIMATION_HZ := 12.0

## The pip being dressed (a SpiritVisual).
var spirit: Node3D
## What it wears (services/outfit.gd).
var outfit: Dictionary
## Metres the leaf sits higher (SpiritVisual reads it).
var leaf_lift := 0.0
var _nodes: Array[Node] = []
var _undo: Array[Callable] = []
var _steps: Array[Callable] = []
var _clock := 0.0
var _tick := -1

## Dresses `target` in `worn`, a clean outfit (services/outfit.gd).
static func dress(target: Node3D, worn: Dictionary) -> RefCounted:
	var made: RefCounted = load("res://presentation/pip_outfit.gd").new(target, worn)
	for id: String in Outfit.items(worn):
		var path := Catalog.art(id)
		if path.is_empty() or not ResourceLoader.exists(path): continue
		made.apply_art(load(path))
	made.leaf_lift = Outfit.leaf_lift(worn)
	made._pose(0.0)
	return made

func _init(target: Node3D, worn: Dictionary) -> void:
	spirit = target
	outfit = worn.duplicate()

## Runs one art script on the pip (dress() runs each worn item's).
func apply_art(art: Script) -> void:
	art.call("wear", self)

## The colour of the pip's body.
func body_color() -> Color:
	return spirit.face_art.body

# --- For art scripts -----------------------------------------------------

func head() -> Node3D:
	return spirit.head

func upper_body() -> Node3D:
	return spirit.upper_body

func torso() -> MeshInstance3D:
	return spirit.torso

func feet() -> Array[Node3D]:
	return spirit.feet

## A foot's mesh (each foot node holds one).
func foot_mesh(foot: Node3D) -> MeshInstance3D:
	return foot.get_child(0) as MeshInstance3D

func leaf() -> MeshInstance3D:
	return spirit.sprout

## The leaf's resting place in the upper body's space, for kit follow().
func leaf_rest() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0, 0, Look.LEAF_LEAN)), Look.LEAF_PIVOT)

## Adds `node` under `parent` (one of the pip's parts, or a node attached
## before); it goes with undress().
func attach(parent: Node3D, node: Node3D) -> Node3D:
	parent.add_child(node)
	_nodes.append(node)
	return node

func mesh(parent: Node3D, shape: Mesh, material: Material, frame: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Wear"
	node.mesh = shape
	node.material_override = material
	node.transform = frame
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attach(parent, node)
	return node

## Draws `part` (the torso, a foot's mesh or the leaf) with `shape`.
func swap_mesh(part: MeshInstance3D, shape: Mesh) -> void:
	if not _may_change(part): return
	var before := part.mesh
	part.mesh = shape
	_undo.append(func() -> void: if is_instance_valid(part): part.mesh = before)

## Draws `part` (the torso, a foot's mesh or the leaf) with `material`.
func set_material(part: GeometryInstance3D, material: Material) -> void:
	if not _may_change(part): return
	var before := part.material_override
	part.material_override = material
	_undo.append(func() -> void: if is_instance_valid(part): part.material_override = before)

## Draws the head's colours with `shader`, a variant of the face shader.
func set_face(shader: Shader, extra: Dictionary = {}) -> void:
	var face: SpiritFace = spirit.face_art
	face.set_shader(shader, extra)
	_undo.append(func() -> void: face.set_shader(SpiritFace.SHADER))

## Sets one of the face variant's own parameters (from an animate() step).
func set_face_parameter(key: StringName, value: Variant) -> void:
	spirit.face_art.material.set_shader_parameter(key, value)

func animate(step: Callable) -> void:
	_steps.append(step)

func _may_change(part: GeometryInstance3D) -> bool:
	if part == spirit.head:
		push_error("A cosmetic never replaces the head: its material draws the face.")
		return false
	return true

# --- For SpiritVisual ----------------------------------------------------

## Advances the item's moving parts with the pip's clock.
func advance(delta: float, reduced: bool) -> void:
	if _steps.is_empty(): return
	if reduced:
		_pose(0.0)
		return
	_clock += maxf(delta, 0.0)
	_pose(_clock)

func _pose(seconds: float) -> void:
	var tick := floori(seconds * ANIMATION_HZ)
	if tick == _tick: return
	_tick = tick
	for step: Callable in _steps: step.call(float(tick) / ANIMATION_HZ)

## The nodes this outfit added (tests).
func nodes() -> Array[Node]:
	return _nodes.duplicate()

## Takes everything off: added nodes are freed at once, and every
## swapped mesh, material and face goes back.
func undress() -> void:
	for index in range(_nodes.size() - 1, -1, -1):
		var node := _nodes[index]
		if not is_instance_valid(node): continue
		var parent := node.get_parent()
		if parent != null: parent.remove_child(node)
		node.free()
	_nodes.clear()
	for index in range(_undo.size() - 1, -1, -1): _undo[index].call()
	_undo.clear()
	_steps.clear()
