extends Node3D
## Keepsakes standing on the Home islands. A view of earned descriptors, never an
## award source. Each catalog place has a fixed slot (home_keepsake_slots.gd).
## A place becomes its real keepsake once it is finished solo and with a friend
## (solo only where no together version exists), with a little planting at its
## foot. Until then its slot holds a faint outline with two marks, a person for
## solo and two people for together, that light up as each is done. Outlines show
## only for chapters with progress and the next few untouched ones; the rest of
## the slots stay empty, so the island fills in as the journey goes on. Later
## chapters stand on a small keepsake garden island that appears when needed.
##
## Built once when Home opens. set_items() rebuilds only the slots whose state
## changed. Earned props share meshes and materials through the world kit. Each
## outline is one cached merged mesh, and all outlines share two transparent
## materials (untouched, and half done).
const Visual = preload("res://presentation/keepsake_visual.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Slots = preload("res://presentation/home_keepsake_slots.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Props = preload("res://presentation/kit/props.gd")
const SOLO_ICON = preload("res://assets/ui/social/user.svg")
const TOGETHER_ICON = preload("res://assets/ui/social/users.svg")
const GHOST := Color(0.29, 0.48, 0.43, 0.42)
const GHOST_HALF := Color(0.29, 0.48, 0.43, 0.62)
const SOLO_LIT := Color("f4c38d")
const TOGETHER_LIT := Color("91d6c6")
const MARK_DIM := Color(0.93, 0.95, 0.86, 0.42)
const HIGHLIGHT := Color("f6efd2")
const MARK_SIZE := 0.26
const GARDEN_GRASS := Color("a6c9a0")
const ROOT := Color("456b59")
## Planting at the foot of a finished keepsake, alternating by slot.
const PLANTING := ["flowers", "bush", "tuft"]
## Small dressing on the keepsake garden's edges: [kind, x, z, size].
const GARDEN_DRESSING := [["bush", 1.0, -7.15, 0.8], ["flowers", -5.6, -6.62, 0.7], ["tuft", -2.68, -5.55, 0.9], ["flowers", -1.62, -7.55, 0.6], ["tuft", 0.48, -7.55, 0.8], ["bush", -4.78, -7.55, 0.55]]
## Marks sit at the slot's front edge, toward the Home camera.
const CAMERA_FLAT := Vector3(0.5547, 0, 0.8321)
## Taps pick the nearest slot within this many viewport pixels.
const PICK_RADIUS := 30.0
static var _ghost_materials: Dictionary = {}
static var _outline_meshes: Dictionary = {}
static var _mark_materials: Dictionary = {}
static var _mark_mesh: QuadMesh
var _world: Node3D
var _order: Array[String] = []
var _places: Dictionary = {}
var _earned: Dictionary = {}
var _slots: Dictionary = {}
## Slots shown now (finished, started or next), in browsing order.
var _shown: Array[String] = []
var _garden: Node3D
var _highlight: MeshInstance3D
var selected_index := 0
## Slot builds since configure(), for tests that prove unchanged state rebuilds nothing.
var builds := 0

## Progress of one place: "none", "solo", "friend" or "complete".
static func state_of(place: Dictionary, earned: Dictionary) -> String:
	var solo: bool = earned.get("solo", false) == true
	var friend: bool = earned.get("friend", false) == true and place.get("friend_available", true)
	if solo and (friend or not place.get("friend_available", true)): return "complete"
	if solo: return "solo"
	if friend: return "friend"
	return "none"

func configure(world: Node3D, items: Array[Dictionary]) -> void:
	_world = world
	name = "HomeKeepsakes"
	_order.clear()
	_places.clear()
	for id: String in Slots.ids():
		var place := Catalog.by_id(id)
		if place.is_empty(): continue
		_order.append(id)
		_places[id] = place
	_highlight = Primitives.mesh_node(Primitives.ring_mesh(0.46), Primitives.shared_material(HIGHLIGHT, 0.6, HIGHLIGHT, 0.6), Vector3(0, 0.06, 0), self)
	_highlight.name = "SelectedSlot"
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply(items, false)

func set_items(items: Array[Dictionary]) -> void:
	_apply(items, true)

func _apply(items: Array[Dictionary], follow_progress: bool) -> void:
	var earned := {}
	for item: Dictionary in items:
		var id := str(item.get("id", ""))
		if _places.has(id): earned[id] = {"solo": item.get("solo", false) == true, "friend": item.get("friend", false) == true}
	var states := {}
	for id: String in _order: states[id] = state_of(_places[id], earned.get(id, {}))
	var shown := shown_ids(_order, _places, states)
	var selected_id := "" if _shown.is_empty() else _shown[selected_index]
	var advanced := ""
	for id: String in _order:
		var state: String = states[id] if shown.has(id) else "hidden"
		var slot: Dictionary = _slots.get(id, {})
		if slot.get("state", "") == state: continue
		if follow_progress and _rank(state) > _rank(str(slot.get("state", "hidden"))): advanced = id
		_build(id, state)
	_earned = earned
	_shown.assign(_order.filter(func(id: String) -> bool: return shown.has(id)))
	_update_garden()
	if not advanced.is_empty(): selected_id = advanced
	selected_index = _shown.find(selected_id) if _shown.has(selected_id) else _first_unfinished()
	_show_selected()

static func _rank(state: String) -> int:
	return {"hidden": -1, "none": 0, "solo": 1, "friend": 1, "complete": 2}.get(state, 0)

## A chapter's places show together; each original island counts as its own.
static func _chapter(place: Dictionary) -> String:
	return str(place.id) if str(place.chapter_key).is_empty() else str(place.chapter_key)

## Places to show: every chapter with any progress, plus the next
## Slots.NEXT_CHAPTERS untouched chapters in slot order.
static func shown_ids(order: Array[String], places: Dictionary, states: Dictionary) -> Dictionary:
	var chapters := {}
	for id: String in order:
		if states[id] != "none": chapters[_chapter(places[id])] = true
	var next := 0
	for id: String in order:
		var chapter := _chapter(places[id])
		if chapters.has(chapter): continue
		if next >= Slots.NEXT_CHAPTERS: break
		chapters[chapter] = true
		next += 1
	var result := {}
	for id: String in order:
		if chapters.has(_chapter(places[id])): result[id] = true
	return result

func _build(id: String, state: String) -> void:
	var previous: Dictionary = _slots.get(id, {})
	if previous.has("node"):
		var old: Node3D = previous.node
		remove_child(old)
		old.queue_free()
	if state == "hidden":
		_slots[id] = {"state": state}
		return
	builds += 1
	var place: Dictionary = _places[id]
	var placed := Slots.transform(id)
	var slot := Node3D.new()
	slot.name = "Slot_" + id.replace("/", "_").replace("-", "_")
	slot.position = placed.origin
	slot.set_meta("keepsake_id", id)
	slot.set_meta("state", state)
	add_child(slot)
	if state == "complete":
		var prop := Visual.create(_world, place, place.friend_available)
		prop.name = "Keepsake"
		prop.transform = Transform3D(placed.basis, Vector3.ZERO)
		prop.set_meta("variant", "friend" if place.friend_available else "solo")
		Primitives.share_static(prop)
		slot.add_child(prop)
		# A little planting behind and to the left, so the garden looks tended.
		var kind: String = PLANTING[_order.find(id) % PLANTING.size()]
		var planting := Props.build({"kind": kind, "at": [-48, -30], "size": 0.6}, slot, 0.0, false)
		planting.name = "Planting"
		Primitives.share_static(planting)
	else:
		# One merged mesh and one draw per outline, however many parts the keepsake has.
		var outline := Primitives.mesh_node(_outline_mesh(place), _ghost_material(state != "none"), Vector3.ZERO, slot)
		outline.name = "Outline"
		outline.basis = placed.basis
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_marks(slot, state, place.friend_available)
	_slots[id] = {"node": slot, "state": state}

## The keepsake's solo model merged into one mesh, built once per app session.
## Glow quads are left out, so an outline is only the shape.
func _outline_mesh(place: Dictionary) -> ArrayMesh:
	var key := str(place.stage_id)
	var cached: ArrayMesh = _outline_meshes.get(key)
	if cached != null: return cached
	var model := Visual.create(_world, place, false)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var shape := part.mesh as PrimitiveMesh
		if shape == null or part.name == "SeedGlow": continue
		var relative := part.transform
		var parent := part.get_parent()
		while parent != model:
			relative = (parent as Node3D).transform * relative
			parent = parent.get_parent()
		var arrays := shape.get_mesh_arrays()
		var base := vertices.size()
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: vertices.append(relative * vertex)
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if order.is_empty(): order = PackedInt32Array(range((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		for index: int in order: indices.append(base + index)
	model.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	cached = ArrayMesh.new()
	if not vertices.is_empty(): cached.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_outline_meshes[key] = cached
	return cached

## A person mark for solo and, where a together version exists, a two-person mark.
func _add_marks(slot: Node3D, state: String, friend_available: bool) -> void:
	var across := Vector3(CAMERA_FLAT.z, 0, -CAMERA_FLAT.x)
	var front := CAMERA_FLAT * 0.38 + Vector3(0, 0.17, 0)
	var marks := [["SoloMark", "solo", state == "solo"]]
	if friend_available: marks.append(["TogetherMark", "together", state == "friend"])
	for index in range(marks.size()):
		var offset := 0.0 if marks.size() == 1 else (index - 0.5) * (MARK_SIZE + 0.03)
		var mark := Primitives.mesh_node(_mark_quad(), _mark_material(marks[index][1], marks[index][2]), front + across * offset, slot)
		mark.name = marks[index][0]
		mark.set_meta("lit", marks[index][2])
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _ghost_material(half: bool) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _ghost_materials.get(half)
	if cached != null: return cached
	cached = StandardMaterial3D.new()
	cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A depth pre-pass keeps each outline one even veil where its parts overlap.
	cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	cached.albedo_color = GHOST_HALF if half else GHOST
	_ghost_materials[half] = cached
	return cached

static func _mark_quad() -> QuadMesh:
	if _mark_mesh == null:
		_mark_mesh = QuadMesh.new()
		_mark_mesh.size = Vector2.ONE * MARK_SIZE
	return _mark_mesh

static func _mark_material(kind: String, lit: bool) -> StandardMaterial3D:
	var key := kind + (":lit" if lit else ":dim")
	var cached: StandardMaterial3D = _mark_materials.get(key)
	if cached != null: return cached
	cached = StandardMaterial3D.new()
	cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cached.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cached.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cached.albedo_texture = _badge(SOLO_ICON if kind == "solo" else TOGETHER_ICON)
	cached.albedo_color = (SOLO_LIT if kind == "solo" else TOGETHER_LIT) if lit else MARK_DIM
	_mark_materials[key] = cached
	return cached

## A round badge with the icon drawn dark on it, so a mark still reads as a dot
## of colour when small. Built once per icon; falls back to the bare icon when
## the renderer cannot read texture pixels (headless runs).
static func _badge(icon: Texture2D) -> Texture2D:
	var source := icon.get_image() if icon != null else null
	if source == null or source.is_empty(): return icon
	source = source.duplicate()
	if source.is_compressed() and source.decompress() != OK: return icon
	source.convert(Image.FORMAT_RGBA8)
	var size := 64
	var inner := 40
	source.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
	var badge := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var ink := Color("17423f")
	var middle := (size - 1) * 0.5
	var start := (size - inner) / 2
	for y in range(size):
		for x in range(size):
			var edge := clampf(size * 0.5 - Vector2(x - middle, y - middle).length(), 0.0, 1.0)
			var pixel := Color(1, 1, 1, edge)
			var u := x - start
			var v := y - start
			if u >= 0 and v >= 0 and u < inner and v < inner:
				pixel = pixel.lerp(Color(ink, edge), source.get_pixel(u, v).a)
			badge.set_pixel(x, y, pixel)
	badge.generate_mipmaps()
	return ImageTexture.create_from_image(badge)

func selected_item() -> Dictionary:
	if _shown.is_empty(): return {}
	var id := _shown[selected_index]
	var item: Dictionary = _places[id].duplicate(true)
	var earned: Dictionary = _earned.get(id, {})
	item.solo = earned.get("solo", false) == true
	item.friend = earned.get("friend", false) == true and item.friend_available
	item.state = state_of(_places[id], earned)
	return item

func select_offset(offset: int) -> void:
	if _shown.is_empty(): return
	selected_index = posmod(selected_index + offset, _shown.size())
	_show_selected()

func select_id(id: String) -> bool:
	var index := _shown.find(id)
	if index < 0: return false
	selected_index = index
	_show_selected()
	return true

## The nearest slot to a viewport point, or "" when none is within reach.
func pick(camera: Camera3D, point: Vector2, radius: float = PICK_RADIUS) -> String:
	var best := ""
	var best_distance := radius
	for id: String in _shown:
		var slot: Node3D = _slots[id].node
		var anchor := slot.to_global(Vector3(0, 0.22, 0))
		if camera.is_position_behind(anchor): continue
		var distance := camera.unproject_position(anchor).distance_to(point)
		if distance <= best_distance:
			best = id
			best_distance = distance
	return best

func slot_node(id: String) -> Node3D:
	return _slots.get(id, {}).get("node")

## Every slotted place, shown or not.
func slot_ids() -> Array[String]:
	return _order.duplicate()

## The places shown now, in browsing order.
func shown_slot_ids() -> Array[String]:
	return _shown.duplicate()

func garden() -> Node3D:
	return _garden

func _first_unfinished() -> int:
	for index in range(_shown.size()):
		if _slots[_shown[index]].state != "complete": return index
	return 0

func _show_selected() -> void:
	if not is_instance_valid(_highlight): return
	_highlight.visible = not _shown.is_empty()
	if _shown.is_empty(): return
	_highlight.position = Slots.transform(_shown[selected_index]).origin + Vector3(0, 0.05, 0)

## The keepsake garden island appears once one of its slots is shown.
func _update_garden() -> void:
	var needed := _shown.any(func(id: String) -> bool: return Slots.in_garden(id))
	if needed and not is_instance_valid(_garden): _build_garden()
	if is_instance_valid(_garden): _garden.visible = needed

func _build_garden() -> void:
	_garden = Node3D.new()
	_garden.name = "KeepsakeGarden"
	add_child(_garden)
	var rect := Slots.garden_rect()
	var middle := rect.get_center()
	# The same faceted landform as the Home islands, moved under this view so
	# leaving Home removes it with the keepsakes.
	if _world.has_method("_island_shell") and is_instance_valid(_world.terrain):
		var terrain: Node3D = _world.terrain
		var before := terrain.get_child_count()
		_world._island_shell(middle.x, middle.y, rect.size.x, rect.size.y, GARDEN_GRASS)
		for child: Node in terrain.get_children().slice(before): child.reparent(_garden, true)
	for i in range(5):
		var root := Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.025, 0.7 + i * 0.07, 0.025), Primitives.shared_material(ROOT), Vector3(middle.x + sin(i * 2.8) * (rect.size.x / 2 - 0.2), -1.35, middle.y + cos(i) * rect.size.y / 2), _garden)
		root.rotation.z = sin(i) * 0.3
	for dressing: Array in GARDEN_DRESSING:
		var prop := Props.build({"kind": dressing[0], "at": [dressing[1] * 100.0, dressing[2] * 100.0], "size": dressing[3]}, _garden, 0.0, false)
		Primitives.share_static(prop)
