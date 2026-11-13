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
## - hide_leaf(): the pip's leaf, and whatever hangs from it, hides while the
##   item is worn (a cap that brings its own stem and leaf).
## - lift_seed(metres, with_leaf): a carried seed sits `metres` higher while
##   the item is worn (a tall cap), plus the leaf's lift with `with_leaf` (a
##   big leaf that rises with it); the largest ask wins. The seed's place is
##   presentation only, as everything here is.
## - travel(step): step(look, at, delta, reduced) on every frame of the pip's
##   motion, `at` its feet's global position (a trail drops marks along it);
##   on_reset(step): step(look) when the pip is placed (a replay seek, a
##   reset), not walked. A step returns at once when it has nothing to do.
## - hide_while_carrying(node): the node hides while the pip carries a real
##   object (a seed, the Lighthouse lens), so a little extra never looks like
##   one or crowds it.
## - place(): where the pip is drawn (WORLD, STUDIO, STAGE, WARDROBE), for an
##   item that shows only in some places; root(): the pip's own node, which
##   moves but never turns (a ring under its feet).
## - animate(step): step(look, seconds) poses the item's moving parts (look is
##   this object, passed in so a step never holds it). It runs at the
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

## Where a pip is drawn (SpiritVisual.place): a world it walks in (chapters,
## Home: the default), a picture of a pip (lists, chips, Settings), a room or
## result page's pip (STAGE) and the Wardrobe's pips.
const WORLD := &"world"
const STUDIO := &"studio"
const STAGE := &"stage"
const WARDROBE := &"wardrobe"
const PLACES: Array[StringName] = [WORLD, STUDIO, STAGE, WARDROBE]

## The pip being dressed (a SpiritVisual).
var spirit: Node3D
## What it wears (services/outfit.gd).
var outfit: Dictionary
## Metres the leaf sits higher (SpiritVisual reads it).
var leaf_lift := 0.0
## Metres a carried seed sits higher (SpiritVisual reads it), worked out in
## dress() from the art scripts' lift_seed() asks.
var seed_lift := 0.0
var _seed_own := 0.0
var _seed_with_leaf := 0.0
var _seed_follows_leaf := false
var _nodes: Array[Node] = []
var _undo: Array[Callable] = []
var _steps: Array[Callable] = []
var _travels: Array[Callable] = []
var _resets: Array[Callable] = []
var _carry_hidden: Array[Node3D] = []
var _carrying := false
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
	made.seed_lift = maxf(made._seed_own, made._seed_with_leaf + made.leaf_lift if made._seed_follows_leaf else 0.0)
	made._carrying = not bool(target.get("carrying_seed"))
	made.carrying(bool(target.get("carrying_seed")))
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

## The pip's own node: it moves but never turns or bobs.
func root() -> Node3D:
	return spirit

## Where the pip is drawn (WORLD, STUDIO, STAGE, WARDROBE).
func place() -> StringName:
	return spirit.place

## 0 for the first player's pip ("a", "p0"), 1 for the other's: a seed both
## phones agree on.
func slot_seed() -> int:
	return 0 if str(spirit.get("_expression_role")) in ["", "a", "p0"] else 1

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

## Hides the pip's leaf (and what hangs from it) while the item is worn.
func hide_leaf() -> void:
	var leaf: MeshInstance3D = spirit.sprout
	if not leaf.visible: return
	leaf.visible = false
	_undo.append(func() -> void: if is_instance_valid(leaf): leaf.visible = true)

## Asks for a carried seed to sit `metres` higher, plus the leaf's lift with `with_leaf`.
func lift_seed(metres: float, with_leaf: bool = false) -> void:
	if with_leaf:
		_seed_follows_leaf = true
		_seed_with_leaf = maxf(_seed_with_leaf, metres)
	else: _seed_own = maxf(_seed_own, metres)

func animate(step: Callable) -> void:
	_steps.append(step)

func travel(step: Callable) -> void:
	_travels.append(step)

func on_reset(step: Callable) -> void:
	_resets.append(step)

func hide_while_carrying(node: Node3D) -> void:
	_carry_hidden.append(node)
	node.visible = not _carrying

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

## Whether any worn item follows the pip's travel (SpiritVisual asks before
## working out where its feet are).
func follows_travel() -> bool:
	return not _travels.is_empty()

## One frame of the pip's motion, its feet at `at` (global).
func travel_to(at: Vector3, delta: float, reduced: bool) -> void:
	for step: Callable in _travels: step.call(self, at, delta, reduced)

## The pip was placed, not walked.
func reset() -> void:
	for step: Callable in _resets: step.call(self)

## Whether the pip carries a real object now; acts only on a change.
func carrying(held: bool) -> void:
	if held == _carrying: return
	_carrying = held
	for node: Node3D in _carry_hidden:
		if is_instance_valid(node): node.visible = not held

func _pose(seconds: float) -> void:
	# A hair over, so a clock summed from many small steps lands on its tick.
	var tick := floori(seconds * ANIMATION_HZ + 0.0001)
	if tick == _tick: return
	_tick = tick
	for step: Callable in _steps: step.call(self, float(tick) / ANIMATION_HZ)

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
	_travels.clear()
	_resets.clear()
	_carry_hidden.clear()
