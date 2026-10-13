extends Node3D
## Keepsakes standing on the Home islands. A view of earned descriptors, never an
## award source. Each catalog place has a fixed slot, size and finished look in
## home_keepsake_slots.gd. Every solo or together completion shows:
##   nothing done   a faint outline with dim solo and together marks
##   solo only      the keepsake in gold with the lit solo mark
##   together only  the keepsake in the friend's teal with the lit together mark
##   both           the together keepsake raised on the shared upgrade: a
##                  stone plinth, a gold rim and a few sparkles, with planting
## A solo-only place (the Sleeping Lighthouse) is finished once done solo.
## Outlines show only for chapters with progress and the next untouched one, so
## the island fills in as the journey goes on. The free chapters stand on the
## right island; the rest on a keepsake terrace that appears when needed.
##
## Built once when Home opens. set_items() rebuilds only the slots whose state
## changed. Keepsakes and the upgrade share meshes and materials through the
## world kit, one material per colour, so each state is a tint, not new
## materials. Each outline is one cached merged mesh, and all outlines share
## one transparent material.
const Visual = preload("res://presentation/keepsake_visual.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Slots = preload("res://presentation/home_keepsake_slots.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Props = preload("res://presentation/kit/props.gd")
const SOLO_ICON = preload("res://assets/ui/social/user.svg")
const TOGETHER_ICON = preload("res://assets/ui/social/users.svg")
const GHOST := Color(0.29, 0.48, 0.43, 0.42)
const SOLO_LIT := Color("f4c38d")
const TOGETHER_LIT := Color("91d6c6")
const MARK_DIM := Color(0.93, 0.95, 0.86, 0.42)
const HIGHLIGHT := Color("f6efd2")
const MARK_SIZE := 0.3
const STONE := Color("ddd5bb")
const RIM := Color("efba73")
const SPARKLE := Color("fff3d0")
const GARDEN_GRASS := Color("a6c9a0")
const ROOT := Color("456b59")
## Planting at the foot of a finished keepsake, alternating by slot.
const PLANTING := ["flowers", "bush", "tuft"]
## Dressing on each Home-only island, in its own flat coordinates: [kind, x, z, size].
const ISLAND_DRESSING := {
	"behind_left": [["tree", -1.75, -2.7, 0.9], ["flowers", 0.0, -1.9, 0.8], ["bush", 1.75, 0.9, 0.8], ["flowers", -1.7, 1.0, 0.7], ["tuft", 0.1, 3.5, 1.0], ["bush", 1.8, 3.4, 0.6]],
	"behind_right": [["tree", 1.75, -2.4, 0.95], ["bush", 0.0, -1.9, 0.8], ["flowers", -1.75, 1.0, 0.8], ["tuft", 1.75, 1.05, 1.0], ["flowers", 0.0, 2.3, 0.6], ["bush", -1.8, 3.45, 0.6]],
	"beside_right": [["flowers", 0.0, -2.45, 0.8], ["tuft", 0.0, 0.0, 1.0], ["bush", 0.05, 2.45, 0.7], ["flowers", 1.6, 2.55, 0.5]],
}
## The flower bed in the middle of the right island's ring: [kind, x, z, size].
const RING_DRESSING := [["flowers", 3.35, 0.35, 1.3], ["bush", 3.05, 0.05, 0.7], ["tuft", 3.7, 0.6, 1.0]]
const PLANK := Color("c4b090")
const POST := Color("8b7964")
## Marks sit at the slot's front edge, toward the Home camera.
const CAMERA_FLAT := Vector3(0.5547, 0, 0.8321)
## Taps pick the nearest slot within this many viewport pixels.
const PICK_RADIUS := 30.0
## Explore crossings follow one rule for every bridge Home draws: the Home
## bridge over the gap and each keepsake island's plank bridge. A spot on a
## crossing carries the spirit only while the crossing is open (a keepsake
## island's bridge is closed while its island is hidden) and the plank under it
## is drawn at deck height, so a lowered or rising deck is never walked on. The
## last CROSSING_PAD at each end lies on land.
const CROSSING_PAD := 0.4
## A plank carries the spirit once it is within this of its deck height.
const DECK_TOLERANCE := 0.05
## The keepsake islands' plank bridges are built at this height and never lower.
const PLANK_DECK_Y := -0.06
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
var _islands: Dictionary = {}
## Explore ground: the two Home island floors, inset from their edges.
var _floors: Array[Rect2] = []
## Every crossing, built once: "inverse" maps a point into its frame (walking
## toward -z from z = 0), "half" is its half width, "length" its span, "planks"
## its planks from the start, "deck" their raised height, "island" its
## keepsake island ("" for the Home bridge), "lowers" whether its deck can be
## drawn down.
var _crossings: Array[Dictionary] = []
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
	_build_ground()
	_highlight = Primitives.mesh_node(Primitives.ring_mesh(0.62), Primitives.shared_material(HIGHLIGHT, 0.6, HIGHLIGHT, 0.6), Vector3(0, 0.06, 0), self)
	_highlight.name = "SelectedSlot"
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bed := Node3D.new()
	bed.name = "RingBed"
	add_child(bed)
	for dressing: Array in RING_DRESSING:
		Primitives.share_static(Props.build({"kind": dressing[0], "at": [dressing[1] * 100.0, dressing[2] * 100.0], "size": dressing[3]}, bed, 0.0, false))
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
	_update_islands()
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
	var size := Slots.scale_of(id)
	var slot := Node3D.new()
	slot.name = "Slot_" + id.replace("/", "_").replace("-", "_")
	slot.position = placed.origin
	slot.set_meta("keepsake_id", id)
	slot.set_meta("state", state)
	add_child(slot)
	if state == "none":
		# One merged mesh and one draw per outline, however many parts the keepsake has.
		var outline := Primitives.mesh_node(_outline_mesh(place), _ghost_material(), Vector3.ZERO, slot)
		outline.name = "Outline"
		outline.basis = placed.basis
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_marks(slot, state, place.friend_available, size)
		_slots[id] = {"node": slot, "state": state}
		return
	var complete := state == "complete"
	var together: bool = state == "friend" or (complete and place.friend_available)
	var prop := Visual.create(_world, place, together)
	prop.name = "Keepsake"
	prop.set_meta("variant", "friend" if together else "solo")
	var lift := 0.0
	if complete:
		var treatment := Slots.upgrade(id)
		var upgrade := _upgrade(treatment)
		upgrade.transform = Transform3D(placed.basis, Vector3.ZERO)
		slot.add_child(upgrade)
		lift = float(treatment.height) * size
		# A little planting behind and to the left, so the place looks tended.
		var kind: String = PLANTING[_order.find(id) % PLANTING.size()]
		var planting := Props.build({"kind": kind, "at": [-62.0 * size, -40.0 * size], "size": 0.55 * size}, slot, 0.0, false)
		planting.name = "Planting"
		Primitives.share_static(planting)
	else:
		_add_marks(slot, state, place.friend_available, size)
	prop.transform = Transform3D(placed.basis, Vector3(0, lift, 0))
	Primitives.share_static(prop)
	slot.add_child(prop)
	_slots[id] = {"node": slot, "state": state}

## The finished treatment, in the keepsake's own units: a stone plinth with a
## gold rim and a few sparkles. Every part is a cached mesh and material.
func _upgrade(treatment: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Upgrade"
	var radius := float(treatment.plinth)
	var height := float(treatment.height)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", radius, height, radius * 0.92), Primitives.shared_material(STONE), Vector3(0, height / 2.0, 0), root).name = "Plinth"
	var rim := Primitives.mesh_node(Primitives.ring_mesh(radius), Primitives.shared_material(RIM, 0.45, RIM, 0.35), Vector3(0, height * 0.55, 0), root)
	rim.name = "Rim"
	for index in range(int(treatment.sparkles)):
		var angle := -0.9 + index * 1.15
		var sparkle := Primitives.mesh_node(Primitives.shared_mesh("sphere", 0.045), Primitives.shared_material(SPARKLE, 0.3, SPARKLE, 1.2), Vector3(cos(angle) * radius * 0.85, 0.42 + 0.22 * index, sin(angle) * radius * 0.5), root)
		sparkle.name = "Sparkle"
		sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Primitives.share_static(root)
	return root

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

## Marks in front of a keepsake: both dim (solo only for a solo-only place)
## while nothing is done, then just the lit mark for the variant that is done.
func _add_marks(slot: Node3D, state: String, friend_available: bool, size: float) -> void:
	var across := Vector3(CAMERA_FLAT.z, 0, -CAMERA_FLAT.x)
	var front := CAMERA_FLAT * 0.5 * size + Vector3(0, 0.17 * size, 0)
	var marks := []
	if state in ["none", "solo"]: marks.append(["SoloMark", "solo", state == "solo"])
	if state in ["none", "friend"] and friend_available: marks.append(["TogetherMark", "together", state == "friend"])
	for index in range(marks.size()):
		var offset := 0.0 if marks.size() == 1 else (index - 0.5) * (MARK_SIZE + 0.03) * size
		var mark := Primitives.mesh_node(_mark_quad(), _mark_material(marks[index][1], marks[index][2]), front + across * offset, slot)
		mark.name = marks[index][0]
		mark.scale = Vector3.ONE * size
		mark.set_meta("lit", marks[index][2])
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _ghost_material() -> StandardMaterial3D:
	var cached: StandardMaterial3D = _ghost_materials.get("ghost")
	if cached != null: return cached
	cached = StandardMaterial3D.new()
	cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A depth pre-pass keeps each outline one even veil where its parts overlap.
	cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	cached.albedo_color = GHOST
	_ghost_materials["ghost"] = cached
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
		var anchor := slot.to_global(Vector3(0, 0.3 * Slots.scale_of(id), 0))
		if camera.is_position_behind(anchor): continue
		var distance := camera.unproject_position(anchor).distance_to(point)
		if distance <= best_distance:
			best = id
			best_distance = distance
	return best

## The Home island floors and the Home bridge, from the level the world shows.
## The bridge's planks are the world's own, so its deck is read as drawn.
func _build_ground() -> void:
	var level: Dictionary = _world.current_level
	var bounds: Array = level.get("bounds", [-560, -290, 560, 290])
	var gap: Array = level.get("gap", [-100, 100])
	var bridge: Dictionary = level.get("bridge", {"z": 0, "width": 180})
	_floors.assign([
		Rect2(float(bounds[0]) / 100.0, float(bounds[1]) / 100.0, float(gap[0] - bounds[0]) / 100.0, float(bounds[3] - bounds[1]) / 100.0).grow(-0.25),
		Rect2(float(gap[1]) / 100.0, float(bounds[1]) / 100.0, float(bounds[2] - gap[1]) / 100.0, float(bounds[3] - bounds[1]) / 100.0).grow(-0.25)])
	var start := Vector3(float(gap[0]) / 100.0, 0.0, float(bridge.get("z", 0)) / 100.0)
	var planks: Array = _world.bridge_parts if "bridge_parts" in _world else []
	var deck: float = _world.BRIDGE_RAISED_Y if "home_bridge_raised" in _world else -0.10
	_crossings.append({"inverse": Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), start).affine_inverse(),
		"half": float(bridge.get("width", 180)) / 200.0 - 0.2, "length": float(gap[1] - gap[0]) / 100.0,
		"planks": planks, "deck": deck, "island": "", "lowers": true})

## True where an explore walk may stand: on a Home island, a shown keepsake
## island, or a crossing that carries the spirit there, and not inside a keepsake.
func walkable(point: Vector3) -> bool:
	var at := Vector2(point.x, point.z)
	for id: String in _shown:
		var reach := 0.32 * Slots.scale_of(id)
		if at.distance_to(Vector2(_slots[id].node.position.x, _slots[id].node.position.z)) < reach: return false
	for rect: Rect2 in _floors:
		if rect.has_point(at): return true
	for name: String in _islands:
		var root: Node3D = _islands[name]
		if root.visible and Slots.island_rect(name).grow(-0.25).has_point(Slots.island_local(name, point)): return true
	for crossing: Dictionary in _crossings:
		if _carries(crossing, point): return true
	return false

## A crossing is open unless its keepsake island is hidden.
func _crossing_open(crossing: Dictionary) -> bool:
	var island: String = crossing.island
	return island.is_empty() or (_islands.has(island) and (_islands[island] as Node3D).visible)

## How far along the crossing `point` is, or NAN when it is off to one side
## (beyond the half width grown by `reach`).
func _along(crossing: Dictionary, point: Vector3, reach: float) -> float:
	var local: Vector3 = crossing.inverse * point
	return -local.z if absf(local.x) <= float(crossing.half) + reach else NAN

func _carries(crossing: Dictionary, point: Vector3) -> bool:
	var along := _along(crossing, point, 0.0)
	var length: float = crossing.length
	if is_nan(along) or along < -CROSSING_PAD or along > length + CROSSING_PAD or not _crossing_open(crossing): return false
	if along <= 0.0 or along >= length: return true
	var planks: Array = crossing.planks
	if planks.is_empty(): return false
	var plank: Node3D = planks[mini(int(along / length * planks.size()), planks.size() - 1)]
	return is_instance_valid(plank) and plank.position.y >= float(crossing.deck) - DECK_TOLERANCE

## True while `point` is within `reach` of an open crossing whose deck can be
## drawn lowered, so Explore should raise it.
func near_lowering_crossing(point: Vector3, reach: float) -> bool:
	for crossing: Dictionary in _crossings:
		if not crossing.lowers or not _crossing_open(crossing): continue
		var along := _along(crossing, point, reach)
		if not is_nan(along) and along >= -CROSSING_PAD - reach and along <= float(crossing.length) + CROSSING_PAD + reach: return true
	return false

## The shown keepsake nearest a point, within reach times its size, or "".
func nearest(point: Vector3, reach: float) -> String:
	var best := ""
	var best_distance := INF
	for id: String in _shown:
		var origin: Vector3 = _slots[id].node.position
		var distance := Vector2(point.x, point.z).distance_to(Vector2(origin.x, origin.z))
		if distance <= reach * Slots.scale_of(id) + 0.3 and distance < best_distance:
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

## A Home-only island's node once built, or null.
func island(name: String) -> Node3D:
	return _islands.get(name)

func _first_unfinished() -> int:
	for index in range(_shown.size()):
		if _slots[_shown[index]].state != "complete": return index
	return 0

func _show_selected() -> void:
	if not is_instance_valid(_highlight): return
	_highlight.visible = not _shown.is_empty()
	if _shown.is_empty(): return
	var id := _shown[selected_index]
	_highlight.position = Slots.transform(id).origin + Vector3(0, 0.05, 0)
	_highlight.scale = Vector3.ONE * Slots.scale_of(id)

## Each Home-only island appears once one of its keepsakes is shown.
func _update_islands() -> void:
	for name: String in Slots.ISLANDS:
		var needed := _shown.any(func(id: String) -> bool: return Slots.island_of(id) == name)
		if needed and not _islands.has(name): _islands[name] = _build_island(name)
		if _islands.has(name): (_islands[name] as Node3D).visible = needed

func _build_island(island: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Island_" + island
	add_child(root)
	var rect := Slots.island_rect(island)
	var land := Node3D.new()
	land.name = "Land"
	root.add_child(land)
	land.transform = Slots.island_transform(island)
	# The same faceted landform as the Home islands, moved under this view so
	# leaving Home removes it with the keepsakes.
	if _world.has_method("_island_shell") and is_instance_valid(_world.terrain):
		var terrain: Node3D = _world.terrain
		var before := terrain.get_child_count()
		_world._island_shell(0.0, 0.0, rect.size.x, rect.size.y, GARDEN_GRASS)
		for child: Node in terrain.get_children().slice(before): child.reparent(land, false)
	for i in range(maxi(3, roundi(rect.size.x / 2.0))):
		var hang := Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.025, 0.7 + (i % 5) * 0.07, 0.025), Primitives.shared_material(ROOT), Vector3(sin(i * 2.8) * (rect.size.x / 2 - 0.3), -1.35, cos(i) * rect.size.y / 2), land)
		hang.rotation.z = sin(i) * 0.3
	for dressing: Array in ISLAND_DRESSING.get(island, []):
		Primitives.share_static(Props.build({"kind": dressing[0], "at": [dressing[1] * 100.0, dressing[2] * 100.0], "size": dressing[3]}, land, 0.0, false))
	_build_bridge(island, root)
	return root

## A plank bridge from a Home island's edge along its direction until it
## reaches the island.
func _build_bridge(island: String, parent: Node3D) -> void:
	var spec: Array = Slots.ISLANDS[island].bridge
	var start := Vector3(float(spec[0][0]), 0.0, float(spec[0][1]))
	var toward := Vector3(float(spec[1][0]), 0.0, float(spec[1][1])).normalized()
	var rect := Slots.island_rect(island).grow(-0.1)
	var length := 0.0
	while length < 12.0 and not rect.has_point(Slots.island_local(island, start + toward * length)): length += 0.05
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	parent.add_child(bridge)
	bridge.transform = Transform3D(Basis.looking_at(toward, Vector3.UP), start)
	bridge.set_meta("length", length)
	var count := maxi(3, ceili(length / 0.34))
	var step := length / count
	var planks: Array = []
	for index in range(count):
		var plank := Primitives.mesh_node(Primitives.shared_mesh("box", 1.0, 0.1, step - 0.03), Primitives.shared_material(PLANK), Vector3(0, PLANK_DECK_Y, -(index + 0.5) * step), bridge)
		plank.name = "Plank"
		planks.append(plank)
	_crossings.append({"inverse": bridge.transform.affine_inverse(), "half": 0.4, "length": length, "planks": planks, "deck": PLANK_DECK_Y, "island": island, "lowers": false})
	for side: int in [-1, 1]:
		for index in range(0, count + 1, 2):
			Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.04, 0.38, 0.04), Primitives.shared_material(POST), Vector3(side * 0.44, 0.15, -index * step), bridge)
