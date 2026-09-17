extends "res://presentation/island_world.gd"
## The Lighthouse's view only. Every beam endpoint and gate state comes from
## the simulation; no collider, interaction or chapter progression lives here.

const BEAM_HEIGHT := 1.12
const LIGHT_COLOR := Color("ffe4a5")
const SLEEP_COLOR := Color("536979")
const StageCatalog = preload("res://core/lighthouse/stage_catalog.gd")
var _deck: Node3D
var _mirror_pivot: Node3D
var _source_lens: MeshInstance3D
var _receiver_lens: MeshInstance3D
var _pad_ring: MeshInstance3D
var _bell: MeshInstance3D
var _bell_ring: MeshInstance3D
var _court_light: OmniLight3D
var _beam_roots: Array[Node3D] = []
var _cable: Array[MeshInstance3D] = []
var _badges: Dictionary = {}
var _mirror_target := -PI / 4.0
var _wake := false
var _view_center := Vector3(-3.8, 0.1, 0)
var _view_size := 7.5
var _decks: Dictionary = {}
var _mirror_nodes: Dictionary = {}
var _source_nodes: Dictionary = {}
var _receiver_nodes: Dictionary = {}
var _receiver_cables: Dictionary = {}
var _prop_nodes: Dictionary = {}
var _socket_nodes: Dictionary = {}
var _history_root: Node3D
var _latched_bridge_ids: Array = []
var _memory_markers: Dictionary = {}
var _selector_nodes: Dictionary = {}
var _frame_points: Array[Vector3] = []
var _hold_pad_nodes: Dictionary = {}
var _beacon: Dictionary = {}

func _ready() -> void:
	super._ready()
	for child: Node in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("111e32")
			child.environment.ambient_light_color = Color("b0c9df")
			child.environment.ambient_light_energy = 0.42
		elif child is DirectionalLight3D:
			child.light_color = Color("c4d9ef") if child.shadow_enabled else Color("859cba")
			child.light_energy = 0.72 if child.shadow_enabled else 0.28
	for index in range(motes.size()):
		motes[index].visible = index < 10
		(motes[index].material_override as StandardMaterial3D).albedo_color = Color("8aabc0")
	_frame_camera()

func load_level(definition: Dictionary) -> void:
	current_level = definition.duplicate(true)
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "BorrowedLightShore"
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	bridge_parts.clear()
	flowers.clear()
	_beam_roots.clear()
	_cable.clear()
	_badges.clear()
	_decks.clear()
	_mirror_nodes.clear()
	_source_nodes.clear()
	_receiver_nodes.clear()
	_receiver_cables.clear()
	_prop_nodes.clear()
	_socket_nodes.clear()
	_history_root = null
	_latched_bridge_ids.clear()
	_memory_markers.clear()
	_selector_nodes.clear()
	_frame_points.clear()
	_hold_pad_nodes.clear()
	_beacon.clear()
	plate = null
	_pad_ring = null
	_bell = null
	_bell_ring = null
	_court_light = null
	seed = null
	garden = null
	landing_marker = null
	lift = null
	gate_plate = null
	lift_guides.clear()
	home_view = false
	bloomed = false
	_wake = false
	for island: Dictionary in definition.islands:
		_shore(island, Color("526f79") if island.id == "harbour" else Color("59687d"))
	for bridge_definition: Dictionary in definition.bridges:
		_build_bridge(bridge_definition)
	for emitter: Dictionary in definition.optics.emitters:
		_build_source(definition.get("plate", {}), emitter)
	var controls: Array = definition.get("controls", [definition.mirror_control] if definition.has("mirror_control") else [])
	for control: Dictionary in controls:
		if control.get("kind", "mirror") == "mirror":
			_build_mirror(control)
		elif control.get("kind", "") == "selector":
			_build_selector(control)
	for receiver: Dictionary in definition.optics.receivers:
		_build_receiver(receiver)
	for pad: Dictionary in definition.get("hold_pads", []):
		_build_hold_pad(pad)
	if definition.get("goal_policy", {}).get("kind", "") == "activate_receivers":
		_build_beacon(definition.goal, definition.optics.receivers)
	elif definition.has("goal"):
		_build_bell(definition.goal)
	for socket: Dictionary in definition.get("sockets", []):
		_build_socket(socket)
	for prop: Dictionary in definition.get("props", []):
		_build_prop(prop)
	# A fixed surface cable, distinct from an optical ray, shows why this
	# receiver controls this bridge. It never extends across the closed gap.
	for receiver: Dictionary in definition.optics.receivers:
		_build_receiver_cable(receiver, definition.bridges)
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else Color("a6dce0"))
		# Later-stage positions are supplied by the verified checkpoint in
		# present(), rather than invented starting coordinates in the view.
		spirit.position = point(definition.starts[slot]) if definition.has("starts") else Vector3.ZERO
		spirit.visible = definition.has("starts")
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = spirit.position
		var badge := Label3D.new()
		var font := FontVariation.new()
		font.base_font = preload("res://assets/fonts/nunito.ttf")
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
		badge.font = font
		badge.font_size = 36
		badge.pixel_size = 0.005
		badge.position.y = 1.45
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.modulate = Color("e7eff2")
		badge.outline_modulate = Color("102133")
		badge.outline_size = 8
		spirit.add_child(badge)
		_badges[slot] = badge
	if definition.stage_id == "borrowed-light":
		_view_center = Vector3(-3.8, 0.1, 0)
		_view_size = 7.5
	else:
		var bounds: Array = definition.islands[0].rect_cm.duplicate()
		for island: Dictionary in definition.islands:
			bounds[0] = mini(bounds[0], island.rect_cm[0])
			bounds[1] = mini(bounds[1], island.rect_cm[1])
			bounds[2] = maxi(bounds[2], island.rect_cm[2])
			bounds[3] = maxi(bounds[3], island.rect_cm[3])
		_view_center = point([(bounds[0] + bounds[2]) / 2.0, (bounds[1] + bounds[3]) / 2.0])
		_view_size = maxf(7.5, float(bounds[3] - bounds[1]) / 100.0 * 0.85 + 3.0)
	for island: Dictionary in definition.islands:
		var bounds: Array = island.rect_cm
		for x in [bounds[0], bounds[2]]:
			for z in [bounds[1], bounds[3]]:
				for height in [-1.65, 1.65]:
					_frame_points.append(Vector3(float(x) / 100.0, height, float(z) / 100.0))
	_frame_camera()

## Supply the checkpoint already verified by the chapter coordinator. Archived
## mechanisms are landmarks only: they add no controls, beams or collision.
func present_history(checkpoint: Dictionary) -> void:
	_latched_bridge_ids.clear()
	if is_instance_valid(_history_root):
		terrain.remove_child(_history_root)
		_history_root.queue_free()
	_history_root = Node3D.new()
	_history_root.name = "RememberedMechanisms"
	terrain.add_child(_history_root)
	if checkpoint.get("level_id", "") != current_level.get("id", ""):
		return
	var stage_index := StageCatalog.STAGE_IDS.find(str(current_level.get("stage_id", "")))
	if stage_index <= 0 or int(checkpoint.get("stage_index", -1)) != stage_index:
		return
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {})
	_latched_bridge_ids = mechanisms.get("latched_bridges", []).duplicate()
	var remembered_mirrors: Dictionary = mechanisms.get("mirrors", {})
	var drawn: Dictionary = {}
	var occupied_controls: Array = []
	for control: Dictionary in StageCatalog.controls(str(current_level.stage_id)):
		occupied_controls.append(control.position_cm)
	for index in range(stage_index):
		var earlier: Dictionary = StageCatalog.definition(StageCatalog.STAGE_IDS[index])
		for control: Dictionary in StageCatalog.controls(StageCatalog.STAGE_IDS[index]):
			var id := str(control.get("optical_id", control.id))
			if _mirror_nodes.has(id) or drawn.has(id) or control.position_cm in occupied_controls or not remembered_mirrors.has(id):
				continue
			drawn[id] = true
			var at := point(control.position_cm)
			cylinder(0.055, BEAM_HEIGHT, Color("71818b"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), _history_root)
			var pivot := Node3D.new()
			pivot.position = at + Vector3(0, BEAM_HEIGHT, 0)
			pivot.rotation.y = PI / 4.0 if remembered_mirrors[id] == "slash" else -PI / 4.0
			_history_root.add_child(pivot)
			pivot.set_meta("mirror_id", id)
			pivot.set_meta("orientation", remembered_mirrors[id])
			box(Vector3(0.70, 0.54, 0.06), Color("8b8d82"), Vector3.ZERO, pivot)
			for side in [-1, 1]:
				box(Vector3(0.60, 0.44, 0.012), Color("789399"), Vector3(0, 0, side * 0.037), pivot)
		for emitter: Dictionary in earlier.optics.emitters:
			if _source_nodes.has(emitter.id) or drawn.has(emitter.id):
				continue
			drawn[emitter.id] = true
			var at := point(emitter.position_cm)
			cylinder(0.08, BEAM_HEIGHT, Color("71818b"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), _history_root)
			cylinder(0.19, 0.30, Color("b09e78"), at + Vector3(0, BEAM_HEIGHT, 0), _history_root)
			cylinder(0.22, 0.05, Color("8b8d82"), at + Vector3(0, BEAM_HEIGHT + 0.18, 0), _history_root)
		for receiver: Dictionary in earlier.optics.receivers:
			if _receiver_nodes.has(receiver.id) or drawn.has(receiver.id):
				continue
			drawn[receiver.id] = true
			var at := point(receiver.position_cm)
			cylinder(0.06, BEAM_HEIGHT, Color("71818b"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), _history_root)
			var disk := cylinder(0.22, 0.07, Color("8da2ac"), at + Vector3(0, BEAM_HEIGHT, 0), _history_root)
			disk.rotation.x = PI / 2.0
			var glass := box(Vector3(0.20, 0.20, 0.035), Color("899998"), at + Vector3(0, BEAM_HEIGHT, 0.052), _history_root)
			glass.rotation.z = PI / 4.0
		if earlier.has("plate"):
			var pad: Dictionary = earlier.plate
			if not drawn.has(pad.id):
				drawn[pad.id] = true
				cylinder(float(pad.radius_cm) / 100.0, 0.035, Color("7e8b83"), point(pad.position_cm) + Vector3(0, 0.018, 0), _history_root)
		if earlier.has("goal") and not current_level.has("goal"):
			var goal: Dictionary = earlier.goal
			if not drawn.has(goal.id):
				drawn[goal.id] = true
				# A rung bell rests below the new Court beam; the familiar location
				# remains marked without adding an apparent obstacle to its ray.
				var at := point(goal.position_cm)
				cylinder(0.34, 0.065, Color("697b8e"), at + Vector3(0, 0.033, 0), _history_root)
				var shape := CylinderMesh.new()
				shape.top_radius = 0.11
				shape.bottom_radius = 0.27
				shape.height = 0.42
				var bell := mesh_node(shape, Color("b29868"), at + Vector3(0, 0.29, 0), _history_root)
				_glow(bell, LIGHT_COLOR, 0.25)
	_history_root.set_meta("checkpoint_hash", checkpoint.get("checkpoint_hash", ""))

func _shore(island: Dictionary, color: Color) -> void:
	var bounds: Array = island.rect_cm
	var width := float(bounds[2] - bounds[0]) / 100.0
	var depth := float(bounds[3] - bounds[1]) / 100.0
	var center := point([(bounds[0] + bounds[2]) / 2.0, (bounds[1] + bounds[3]) / 2.0])
	# The visible top is exactly the authored walkable rectangle, at height 0.
	# The tapered lower rock is decorative and remains below the floor.
	box(Vector3(width, 0.20, depth), color, center + Vector3(0, -0.10, 0), terrain).name = str(island.id) + "Floor"
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for corner: Vector2 in corners:
		top.append(center + Vector3(corner.x * width * 0.48, -0.20, corner.y * depth * 0.48))
		bottom.append(center + Vector3(corner.x * width * 0.22, -1.45, corner.y * depth * 0.24))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in range(4):
		var next := (index + 1) % 4
		var face_color := color.darkened(0.18 + 0.035 * index)
		_shell_triangle(surface, top[index], bottom[index], bottom[next], face_color)
		_shell_triangle(surface, top[index], bottom[next], top[next], face_color)
		_shell_triangle(surface, bottom[index], center + Vector3(0, -1.62, 0), bottom[next], color.darkened(0.35))
	surface.generate_normals()
	var rock := mesh_node(surface.commit(), Color.WHITE, Vector3.ZERO, terrain)
	rock.name = str(island.id) + "LowerRock"
	(rock.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	(rock.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1, 1]:
		box(Vector3(width, 0.025, 0.035), color.lightened(0.12), center + Vector3(0, 0.005, side * (depth / 2.0 - 0.018)), terrain)
		box(Vector3(0.035, 0.025, depth), color.lightened(0.12), center + Vector3(side * (width / 2.0 - 0.018), 0.005, 0), terrain)
	# Only a few small stones at the outer corners; no invented obstacles or
	# extra stepping-stones through the real gap.
	for x_side in [-1, 1]:
		var stone := sphere(0.13, Color("85949c"), center + Vector3(x_side * (width / 2.0 - 0.25), 0.045, depth / 2.0 - 0.22), terrain)
		stone.scale = Vector3(1.4, 0.5, 0.9)

func _build_bridge(definition: Dictionary) -> void:
	var rect: Array = definition.rect_cm
	var width := float(rect[2] - rect[0]) / 100.0
	var depth := float(rect[3] - rect[1]) / 100.0
	_deck = Node3D.new()
	_deck.name = "ReceiverBridge"
	_deck.position = point([(rect[0] + rect[2]) / 2.0, (rect[1] + rect[3]) / 2.0])
	terrain.add_child(_deck)
	_decks[definition.id] = _deck
	var across_x := width >= depth
	for index in range(8):
		var length := width if across_x else depth
		var offset := -length / 2.0 + (index + 0.5) * length / 8.0
		var size := Vector3(width / 8.0, 0.10, depth) if across_x else Vector3(width, 0.10, depth / 8.0)
		var at := Vector3(offset, -0.05, 0) if across_x else Vector3(0, -0.05, offset)
		box(size, Color("bdc9c1"), at, _deck)
		var seam_size := Vector3(0.016, 0.005, depth - 0.06) if across_x else Vector3(width - 0.06, 0.005, 0.016)
		var seam_at := Vector3(offset + length / 16.0 - 0.012, 0.003, 0) if across_x else Vector3(0, 0.003, offset + length / 16.0 - 0.012)
		box(seam_size, Color("637886"), seam_at, _deck)
	for side in [-1, 1]:
		var trim_size := Vector3(width, 0.025, 0.035) if across_x else Vector3(0.035, 0.025, depth)
		var trim_at := Vector3(0, 0.015, side * (depth / 2.0 - 0.025)) if across_x else Vector3(side * (width / 2.0 - 0.025), 0.015, 0)
		var trim := box(trim_size, LIGHT_COLOR, trim_at, _deck)
		_glow(trim, LIGHT_COLOR, 0.65)
	var memories := Node3D.new()
	memories.name = "RememberedFootsteps"
	_deck.add_child(memories)
	for index in range(3):
		var along := ((float(index) + 0.5) / 3.0 - 0.5) * (width if across_x else depth)
		for side in [-1, 1]:
			var at := Vector3(along + side * 0.05, 0.011, side * 0.11) if across_x else Vector3(side * 0.11, 0.011, along + side * 0.05)
			var footprint := cylinder(0.038, 0.005, Color("a68c60"), at, memories)
			footprint.scale = Vector3(1.6, 1, 1) if across_x else Vector3(1, 1, 1.6)
	memories.visible = false
	_memory_markers[definition.id] = memories
	_deck.visible = false

func _build_source(control: Dictionary, emitter: Dictionary) -> void:
	if not control.is_empty():
		var base := point(control.position_cm)
		var radius := float(control.radius_cm) / 100.0
		plate = cylinder(radius, 0.065, Color("927e5a"), base + Vector3(0, 0.033, 0), terrain)
		plate.name = "EmitterPad"
		_pad_ring = ring(radius + 0.02, Color("bba775"), base + Vector3(0, 0.08, 0), terrain)
		box(Vector3(0.18, 0.018, 0.18), Color("ded2a7"), base + Vector3(0, 0.075, 0), terrain).rotation.y = PI / 4.0
	var at := point(emitter.position_cm)
	cylinder(0.08, BEAM_HEIGHT, Color("897c67"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), terrain)
	var lantern := cylinder(0.16, 0.30, Color("6c777c"), at + Vector3(0, BEAM_HEIGHT, 0), terrain)
	lantern.name = "HarbourEmitter"
	_source_lens = sphere(0.13, Color("706d5e"), at + Vector3(0.04, BEAM_HEIGHT, 0), terrain)
	_source_nodes[emitter.id] = _source_lens
	_glow(_source_lens, LIGHT_COLOR, 0.0)
	cylinder(0.20, 0.05, Color("ab966d"), at + Vector3(0, BEAM_HEIGHT + 0.18, 0), terrain)

func _build_mirror(control: Dictionary) -> void:
	var at := point(control.position_cm)
	cylinder(0.18, 0.07, Color("98a8ad"), at + Vector3(0, 0.035, 0), terrain)
	ring(float(control.radius_cm) / 100.0, Color("8caab9"), at + Vector3(0, 0.04, 0), terrain)
	cylinder(0.055, BEAM_HEIGHT, Color("819199"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), terrain)
	_mirror_pivot = Node3D.new()
	_mirror_pivot.name = "MirrorOrientation"
	_mirror_pivot.position = at + Vector3(0, BEAM_HEIGHT, 0)
	terrain.add_child(_mirror_pivot)
	_mirror_nodes[control.get("optical_id", control.id)] = _mirror_pivot
	box(Vector3(0.70, 0.54, 0.06), Color("c3ae78"), Vector3.ZERO, _mirror_pivot)
	for side in [-1, 1]:
		var glass := box(Vector3(0.62, 0.46, 0.012), Color("acd6e7"), Vector3(0, 0, side * 0.037), _mirror_pivot)
		_glow(glass, Color("7eadc3"), 0.25)
	_mirror_target = -PI / 4.0
	_mirror_pivot.rotation.y = _mirror_target
	# Discrete engraved arrows show two positions instead of implying free aim.
	for side in [-1, 1]:
		var arrow := box(Vector3(0.10, 0.02, 0.06), Color("d0dce2"), at + Vector3(side * 0.29, 0.06, 0.18), terrain)
		arrow.rotation.y = side * PI / 4.0

func _build_receiver(receiver: Dictionary) -> void:
	var at := point(receiver.position_cm)
	cylinder(0.06, BEAM_HEIGHT, Color("697a88"), at + Vector3(0, BEAM_HEIGHT / 2.0, 0), terrain)
	var disk := cylinder(0.22, 0.07, Color("8da2ac"), at + Vector3(0, BEAM_HEIGHT, 0), terrain)
	disk.rotation.x = PI / 2.0
	_receiver_lens = box(Vector3(0.20, 0.20, 0.035), Color("536579"), at + Vector3(0, BEAM_HEIGHT, 0.052), terrain)
	_receiver_lens.rotation.z = PI / 4.0
	_receiver_lens.name = "BridgeReceiver"
	_receiver_nodes[receiver.id] = _receiver_lens
	_glow(_receiver_lens, LIGHT_COLOR, 0.0)

func _build_selector(control: Dictionary) -> void:
	# The mirror still follows the exact optical orientation. Three engraved
	# positions distinguish this switch from an ordinary two-way mirror.
	_build_mirror(control)
	var at := point(control.position_cm)
	var dial := Node3D.new()
	dial.name = "PathSelector"
	dial.position = at
	terrain.add_child(dial)
	var dots: Array[MeshInstance3D] = []
	for index in range(control.states.size()):
		var x := (float(index) - float(control.states.size() - 1) / 2.0) * 0.30
		var marker := cylinder(0.10, 0.035, Color("738392"), Vector3(x, 0.055, 0.46), dial)
		dots.append(marker)
		# One and two raised bars remain readable without colour or sound.
		for bar in range(index):
			box(Vector3(0.025, 0.02, 0.105), Color("e7dfc7"), Vector3(x + (float(bar) - float(index - 1) / 2.0) * 0.055, 0.084, 0.46), dial)
	var pointer := box(Vector3(0.085, 0.03, 0.085), LIGHT_COLOR, Vector3(-0.30, 0.095, 0.64), dial)
	pointer.rotation.y = PI / 4.0
	_selector_nodes[control.id] = {"root": dial, "dots": dots, "pointer": pointer, "states": control.states.duplicate()}

func _build_bell(goal: Dictionary) -> void:
	var at := point(goal.position_cm)
	var cradle := Node3D.new()
	cradle.name = "CourtBell"
	cradle.position = at
	terrain.add_child(cradle)
	cylinder(0.34, 0.065, Color("697b8e"), Vector3(0, 0.033, 0), cradle)
	_bell_ring = ring(float(goal.radius_cm) / 100.0, Color("a2b3c0"), Vector3(0, 0.07, 0), cradle)
	for side in [-1, 1]:
		box(Vector3(0.10, 1.52, 0.13), Color("9e9180"), Vector3(side * 0.43, 0.76, -0.12), cradle)
	box(Vector3(0.98, 0.12, 0.18), Color("b4a381"), Vector3(0, 1.52, -0.12), cradle)
	var shape := CylinderMesh.new()
	shape.top_radius = 0.11
	shape.bottom_radius = 0.27
	shape.height = 0.42
	shape.radial_segments = 20
	_bell = mesh_node(shape, Color("b29868"), Vector3(0, 1.18, 0), cradle)
	_glow(_bell, LIGHT_COLOR, 0.0)
	ring(0.27, Color("c4ad7a"), Vector3(0, 0.97, 0), cradle)
	sphere(0.055, Color("dfc58c"), Vector3(0, 0.97, 0), cradle)
	_court_light = OmniLight3D.new()
	_court_light.light_color = Color("ffd9a2")
	_court_light.light_energy = 0.0
	_court_light.omni_range = 4.0
	_court_light.position = at + Vector3(0, 1.6, 0)
	terrain.add_child(_court_light)

func _build_receiver_cable(receiver: Dictionary, bridges: Array) -> void:
	var route: Array[Vector3] = []
	if current_level.stage_id == "borrowed-light":
		route = [Vector3(-5.6, 0.045, -1.6), Vector3(-4.75, 0.045, -1.6), Vector3(-4.75, 0.045, -0.47)]
	else:
		for bridge_definition: Dictionary in bridges:
			if bridge_definition.get("receiver_id", "") != receiver.id:
				continue
			var adjacent := false
			for island: Dictionary in current_level.islands:
				if island.id not in [bridge_definition.from_surface, bridge_definition.to_surface]: continue
				var floor: Array = island.rect_cm
				var receiver_at: Array = receiver.position_cm
				if receiver_at[0] >= floor[0] and receiver_at[0] <= floor[2] and receiver_at[1] >= floor[1] and receiver_at[1] <= floor[3]: adjacent = true
			# A distant selector can control another island, but its decorative
			# surface wire must not invent an unsupported rectangle over the void.
			if not adjacent: break
			var rect: Array = bridge_definition.rect_cm
			var at := point(receiver.position_cm) + Vector3(0, 0.045, 0)
			var edge := point([clampf(receiver.position_cm[0], rect[0], rect[2]), clampf(receiver.position_cm[1], rect[1], rect[3])]) + Vector3(0, 0.045, 0)
			route = [at, Vector3(edge.x, at.y, at.z), edge]
			break
	var cables: Array[MeshInstance3D] = []
	for index in range(1, route.size()):
		if route[index - 1].distance_to(route[index]) < 0.005:
			continue
		var cable := _bar_between(route[index - 1], route[index], 0.025, Color("718592"), terrain)
		cable.name = "ReceiverCable%d" % index
		cables.append(cable)
	if not route.is_empty():
		var relay := cylinder(0.12, 0.045, Color("bca778"), route[-1], terrain)
		relay.name = "BridgeSignal"
		cables.append(relay)
	_receiver_cables[receiver.id] = cables
	_cable.append_array(cables)

func _build_hold_pad(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	var radius := float(definition.radius_cm) / 100.0
	var base := cylinder(radius, 0.05, Color("70858d"), at + Vector3(0, 0.025, 0), terrain)
	base.name = "SourceHoldPad"
	var rim := ring(radius, Color("9fcbd0"), at + Vector3(0, 0.06, 0), terrain)
	# Two engraved footsteps show a standing action, distinct from a mirror.
	for side in [-1, 1]:
		var foot := cylinder(0.048, 0.008, Color("e0e7dd"), at + Vector3(side * 0.085, 0.056, 0), terrain)
		foot.scale = Vector3(0.8, 1.0, 1.7)
	_hold_pad_nodes[definition.id] = {"base": base, "rim": rim}

func _build_beacon(goal: Dictionary, receivers: Array) -> void:
	# The activation crest lies on its exact authored surface. The small open
	# lantern stays behind the receiver edge, clear of both mirror approaches.
	var at := point(goal.position_cm)
	var crest := Node3D.new()
	crest.name = "BeaconCrest"
	crest.position = at
	terrain.add_child(crest)
	cylinder(float(goal.radius_cm) / 100.0, 0.035, Color("778a94"), Vector3(0, 0.018, 0), crest)
	var rim := ring(float(goal.radius_cm) / 100.0, Color("d0c5a0"), Vector3(0, 0.05, 0), crest)
	var markers: Dictionary = {}
	var lantern_at := Vector3.ZERO
	for index in range(receivers.size()):
		var receiver: Dictionary = receivers[index]
		lantern_at += point(receiver.position_cm)
		var marker := box(Vector3(0.08, 0.02, 0.16), Color("94a7aa"), Vector3((float(index) - 0.5) * 0.18, 0.047, 0), crest)
		marker.rotation.y = PI / 4.0 if index == 0 else -PI / 4.0
		markers[receiver.id] = marker
	lantern_at = lantern_at / float(maxi(receivers.size(), 1)) + Vector3(0.42, 0, 0)
	var lantern := Node3D.new()
	lantern.name = "WelcomeLantern"
	lantern.position = lantern_at
	terrain.add_child(lantern)
	cylinder(0.26, 0.12, Color("859595"), Vector3(0, 0.06, 0), lantern)
	cylinder(0.13, 0.48, Color("9a9986"), Vector3(0, 0.35, 0), lantern)
	cylinder(0.29, 0.07, Color("c4b785"), Vector3(0, 0.63, 0), lantern)
	for side in [-1, 1]:
		box(Vector3(0.035, 0.61, 0.035), Color("b1ab8b"), Vector3(side * 0.20, 0.96, 0), lantern)
	var glass := sphere(0.19, Color("8ba7ad"), Vector3(0, 0.97, 0), lantern)
	glass.scale = Vector3(0.8, 1.35, 0.8)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.03
	roof.bottom_radius = 0.34
	roof.height = 0.22
	roof.radial_segments = 8
	mesh_node(roof, Color("b2a581"), Vector3(0, 1.40, 0), lantern)
	var halo := ring(0.50, LIGHT_COLOR, Vector3(0, 0.98, 0), lantern)
	halo.visible = false
	var glow := OmniLight3D.new()
	glow.light_color = LIGHT_COLOR
	glow.light_energy = 0.0
	glow.omni_range = 5.0
	glow.position = Vector3(0, 1.10, 0)
	lantern.add_child(glow)
	_beacon = {"crest": crest, "rim": rim, "signals": markers, "lantern": lantern, "glass": glass, "halo": halo, "light": glow}

func _present_beacon(state: Dictionary) -> void:
	for id: String in _hold_pad_nodes:
		var held: bool = state.get("hold_pads", {}).get(id, false)
		var pad: Dictionary = _hold_pad_nodes[id]
		(pad.base.material_override as StandardMaterial3D).albedo_color = Color("d2bf8a") if held else Color("70858d")
		_glow(pad.rim, LIGHT_COLOR, 0.9 if held else 0.0)
		pad.base.set_meta("occupied", held)
	if _beacon.is_empty(): return
	var state_beacon: Dictionary = state.get("beacon", {})
	var lit: bool = state_beacon.get("lit", false)
	for id: String in _beacon.signals:
		_glow(_beacon.signals[id], LIGHT_COLOR, 0.9 if state_beacon.get("signals", {}).get(id, false) else 0.0)
	_glow(_beacon.rim, LIGHT_COLOR, 1.0 if state_beacon.get("ready", false) else 0.0)
	_glow(_beacon.glass, LIGHT_COLOR, 1.8 if lit else 0.0)
	_beacon.halo.visible = lit
	_glow(_beacon.halo, LIGHT_COLOR, 0.65 if lit else 0.0)
	_beacon.light.light_energy = 1.6 if lit else 0.0
	_beacon.lantern.set_meta("lit", lit)

func _build_prop(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	cylinder(0.23, 0.20, Color("8995a5"), at + Vector3(0, 0.10, 0), terrain).name = "LensPedestal"
	var lens := Node3D.new()
	lens.name = "PortableLens"
	lens.position = at + Vector3(0, 0.44, 0)
	terrain.add_child(lens)
	var frame := ring(0.20, Color("d5b876"), Vector3.ZERO, lens)
	frame.rotation.x = PI / 2.0
	var glass := cylinder(0.18, 0.035, Color("99dfd9"), Vector3.ZERO, lens)
	glass.rotation.x = PI / 2.0
	_glow(glass, Color("99dfd9"), 0.55)
	# A matching three-notch frame distinguishes the lens and cradle without
	# relying on colour alone. It is never a second collectible on the ground.
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		box(Vector3(0.05, 0.07, 0.05), LIGHT_COLOR, Vector3(sin(angle) * 0.21, cos(angle) * 0.21, 0), lens)
	_prop_nodes[definition.id] = lens

func _build_socket(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	var cradle := Node3D.new()
	cradle.name = "LensCradle"
	cradle.position = at
	terrain.add_child(cradle)
	cylinder(0.31, 0.12, Color("728994"), Vector3(0, 0.06, 0), cradle)
	var marker := ring(float(definition.radius_cm) / 100.0, Color("b5c3b9"), Vector3(0, 0.075, 0), cradle)
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		box(Vector3(0.065, 0.12, 0.055), Color("d5b876"), Vector3(sin(angle) * 0.22, 0.45 + cos(angle) * 0.22, 0), cradle)
	_socket_nodes[definition.id] = marker

func _present_props(state: Dictionary, immediate: bool=false) -> void:
	var props: Dictionary = state.get("props", {})
	for actor: Node3D in actors.values():
		actor.carrying_seed=false
		actor.carried_radius=0.25
	for id: String in _prop_nodes:
		var lens: Node3D = _prop_nodes[id]
		if not props.has(id):
			lens.visible = false
			lens.set_meta("holder_slot", "")
			lens.set_meta("prop_status", "")
			continue
		var value: Dictionary = props[id]
		var previous_holder := str(lens.get_meta("holder_slot", ""))
		if not immediate and lens.get_meta("prop_status", "")=="carried" and value.status in ["offered","fitted"] and actors.has(previous_holder):
			actors[previous_holder].play_carry_release()
		if value.status=="carried" and actors.has(value.holder_slot):
			actors[value.holder_slot].carrying_seed=true
		lens.visible = value.status in ["pedestal", "carried", "offered", "fitted"]
		lens.set_meta("holder_slot", str(value.holder_slot) if value.status == "carried" else "")
		lens.set_meta("prop_status", str(value.status))
		lens.position = actors[value.holder_slot].position + actors[value.holder_slot].carry_anchor_position() if value.status == "carried" and actors.has(value.holder_slot) else point([value.x, value.z]) + Vector3(0, 0.44, 0)
	for id: String in _socket_nodes:
		var fitted := false
		for value: Dictionary in props.values():
			if value.status == "fitted" and value.socket_id == id:
				fitted = true
		_glow(_socket_nodes[id], LIGHT_COLOR, 1.0 if fitted else 0.0)

func present(state: Dictionary, immediate: bool = false) -> void:
	if not is_instance_valid(terrain) or not state.has("players"):
		return
	for slot: String in actors:
		var player: Dictionary = state.players[slot]
		actors[slot].visible = true
		actor_targets[slot] = Vector3(float(player.x) / 100.0, float(player.get("height", 0)) / 100.0, float(player.z) / 100.0)
		if immediate:
			actors[slot].position = actor_targets[slot]
			actors[slot].reset_motion()
		_badges[slot].text = "You" if slot == state.active_slot else "Memory" if player.get("ghost", false) else "Waiting"
	# Discrete orientation and beam redirect change together. Interpolating the
	# mirror would temporarily depict a reflection the simulation never made.
	for id: String in _decks:
		_decks[id].visible = bool(state.bridges.get(id, false))
		var kept_now: Array = state.get("route_progress", {}).get("kept_bridges", [])
		_memory_markers[id].visible = _decks[id].visible and (id in _latched_bridge_ids or id in kept_now)
	for id: String in _mirror_nodes:
		var orientation: String = state.get("mirrors", {}).get(id, state.mirror_orientation)
		_mirror_target = PI / 4.0 if orientation == "slash" else -PI / 4.0
		_mirror_nodes[id].rotation.y = _mirror_target
	for id: String in _selector_nodes:
		var selector: Dictionary = _selector_nodes[id]
		var index := int(state.get("selectors", {}).get(id, 0))
		selector.root.set_meta("selected_state", index)
		selector.pointer.position.x = (float(index) - float(selector.states.size() - 1) / 2.0) * 0.30
		for marker_index in range(selector.dots.size()):
			_glow(selector.dots[marker_index], LIGHT_COLOR, 0.8 if marker_index == index else 0.0)
	var powered: bool = state.emitter_powered
	if is_instance_valid(plate):
		(plate.material_override as StandardMaterial3D).albedo_color = Color("d4b876") if powered else Color("927e5a")
		_glow(_pad_ring, LIGHT_COLOR, 0.8 if powered else 0.0)
	for id: String in _source_nodes:
		var emitting := false
		for segment: Dictionary in state.optics.segments:
			if segment.get("emitter_id", "") == id:
				emitting = true
		_glow(_source_nodes[id], LIGHT_COLOR, 1.4 if emitting else 0.0)
	for id: String in _receiver_nodes:
		var received: bool = state.optics.signals.get(id, false)
		_glow(_receiver_nodes[id], LIGHT_COLOR, 1.2 if received else 0.0)
		for cable: MeshInstance3D in _receiver_cables.get(id, []):
			_glow(cable, LIGHT_COLOR if received else Color("718592"), 0.7 if received else 0.0)
	_present_props(state, immediate)
	_present_beacon(state)
	_wake = bool(state.objective_done)
	if is_instance_valid(_bell):
		_glow(_bell_ring, LIGHT_COLOR, 1.0 if _wake else 0.0)
		_glow(_bell, LIGHT_COLOR, 0.65 if _wake else 0.0)
		_court_light.light_energy = 1.2 if _wake else 0.0
	_present_beams(state.optics.segments)

func _present_beams(segments: Array) -> void:
	while _beam_roots.size() < segments.size():
		var root := Node3D.new()
		root.name = "OpticalSegment%d" % _beam_roots.size()
		terrain.add_child(root)
		var halo := box(Vector3(0.07, 0.07, 1), Color(1.0, 0.85, 0.57, 0.18), Vector3.ZERO, root)
		var core := box(Vector3(0.022, 0.022, 1), LIGHT_COLOR, Vector3.ZERO, root)
		_glow(halo, LIGHT_COLOR, 0.8)
		_glow(core, LIGHT_COLOR, 1.3)
		for side in [-1, 1]:
			var arrow := box(Vector3(0.026, 0.032, 0.15), LIGHT_COLOR, Vector3(side * 0.035, 0.015, 0.045), root)
			arrow.rotation.y = side * PI / 4.0
			_glow(arrow, LIGHT_COLOR, 1.0)
		_beam_roots.append(root)
	for index in range(_beam_roots.size()):
		var root: Node3D = _beam_roots[index]
		root.visible = index < segments.size()
		if not root.visible:
			continue
		var segment: Dictionary = segments[index]
		var from := point(segment.from_cm) + Vector3(0, BEAM_HEIGHT, 0)
		var to := point(segment.to_cm) + Vector3(0, BEAM_HEIGHT, 0)
		var length := from.distance_to(to)
		root.position = (from + to) / 2.0
		root.look_at(terrain.to_global(to), Vector3.UP)
		for child_index in [0, 1]:
			var child := root.get_child(child_index) as MeshInstance3D
			(child.mesh as BoxMesh).size.z = length
		for child_index in [2, 3]:
			root.get_child(child_index).visible = length >= 0.25
		root.set_meta("from_cm", segment.from_cm.duplicate())
		root.set_meta("to_cm", segment.to_cm.duplicate())

func _bar_between(from: Vector3, to: Vector3, width: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var bar := box(Vector3(width, width, from.distance_to(to)), color, (from + to) / 2.0, parent)
	bar.look_at(parent.to_global(to), Vector3.UP)
	return bar

func _glow(node: MeshInstance3D, color: Color, energy: float) -> void:
	var mat := node.material_override as StandardMaterial3D
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy

func _frame_camera() -> void:
	if not is_instance_valid(camera):
		return
	# A higher, less oblique view keeps the short mirror-to-receiver segment
	# visible behind the mirror face without moving either optical endpoint.
	camera.position = _view_center + Vector3(3, 13, 10)
	camera.look_at(to_global(_view_center))
	camera.size = _view_size
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	if _frame_points.is_empty(): return
	# Fit the whole authored world (including its height) inside the space
	# between title and touch controls. Depth alone cannot fit a wide chapter.
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner: Vector3 in _frame_points:
		var relative := corner - _view_center
		var projected := Vector2(relative.dot(camera.basis.x), relative.dot(camera.basis.y))
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	var viewport := get_viewport().get_visible_rect().size
	var aspect := maxf(viewport.x / maxf(viewport.y, 1.0), 1.0)
	var extent := maximum - minimum
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(extent.y / 0.66, extent.x / (aspect * 0.88))
	camera.h_offset = (minimum.x + maximum.x) / 2.0
	camera.v_offset = (minimum.y + maximum.y) / 2.0 - camera.size * 0.015

func _process(delta: float) -> void:
	super._process(delta)
	for lens: Node3D in _prop_nodes.values():
		var holder := str(lens.get_meta("holder_slot", ""))
		if actors.has(holder):
			lens.position = actors[holder].position + actors[holder].carry_anchor_position()
	_frame_camera()
