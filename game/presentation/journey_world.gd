extends "res://presentation/cooperative_world.gd"
## View adapter for the sealed simulation7 snapshot. The physical renderer and
## Lighthouse optical geometry remain shared; this file adds no game state.
var _journey_switches: Dictionary = {}
var _journey_handles: Dictionary = {}
var _waiting_ring: MeshInstance3D
var _remembered: Node3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_journey_switches.clear()
	_journey_handles.clear()
	_waiting_ring = null
	super.show_stage(stage)
	var endpoint: Dictionary = stage.get("source_policy", {}).get("endpoint", {})
	if not endpoint.is_empty():
		var at := _at(endpoint)
		_waiting_ring = ring(float(endpoint.radius_cm)/100.0,CREAM,at+Vector3(0,0.018,0),terrain)
		_waiting_ring.name = "SourceWaitingRegion"
		_ownership_mark(str(endpoint.owner_slot),at+Vector3(0,0.025,0),terrain)

func _configure_shared_view(view: Dictionary) -> void:
	# The renderer receives a detached stage view. Native optical dictionaries
	# and their exact canonical keys never gain presentation-only metadata.
	view["optics"] = view.get("optical_field", {"emitters":[],"receivers":[]}).duplicate(true)
	for slot: String in view.starts:
		if view.starts[slot] is Dictionary: view.starts[slot] = view.starts[slot].position_cm.duplicate()

func _beam_height() -> float: return 2.4
func _uses_lower_cutaway() -> bool: return true
func _uses_scrolling_camera() -> bool: return true

func _control_base_height(entity: Dictionary) -> float:
	if entity.has("surface_id"): return _surface_height(str(entity.surface_id))
	var position: Array = entity.position_cm
	var height := 0.0
	for island: Dictionary in chapter_definition.islands:
		var rect: Array = island.rect_cm
		if position[0] >= rect[0] and position[0] <= rect[2] and position[1] >= rect[1] and position[1] <= rect[3]:
			height = maxf(height,float(island.get("height_cm",0))/100.0)
	return height

func _build_mirror(control: Dictionary) -> void:
	super._build_mirror(control)
	# The optical face stays on the common ray plane. A hand wheel at the
	# authored interaction position shows that a ground player can turn it.
	var at := _at(control)
	var hand := Node3D.new()
	hand.name = "MirrorHandControl_"+str(control.id)
	hand.position = at+Vector3(0,0.54,0.10)
	terrain.add_child(hand)
	var wheel := ring(0.14,GOLD if control.owner_slot == "p0" else TEAL,Vector3.ZERO,hand)
	wheel.rotation.x = PI/2.0
	box(Vector3(0.035,0.26,0.035),CREAM,Vector3.ZERO,hand)
	_journey_handles[control.id] = hand
	_ownership_mark(str(control.owner_slot),at+Vector3(0,0.025,0.35),terrain)

func _build_selector(control: Dictionary) -> void:
	_build_lever(control)
	var labels: Array[Label3D] = []
	var at := _at(control)
	for index in range(control.values.size()):
		var offset := (float(index)-float(control.values.size()-1)*0.5)*1.28
		var label := _world_label(str(control.values[index]).to_upper(),at+Vector3(offset,0.13,0.64),terrain)
		labels.append(label)
	_journey_switches[control.id] = {"values":control.values.duplicate(),"labels":labels}
	_physical_levers[control.id].name = "RouteSwitch_"+str(control.id)

func _world_label(value: String, at: Vector3, parent: Node3D) -> Label3D:
	var label := Label3D.new()
	label.text = value
	var font := FontVariation.new()
	font.base_font = preload("res://assets/fonts/nunito.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):700.0}
	label.font = font
	label.font_size = 30
	label.pixel_size = 0.008
	label.outline_size = 3
	label.outline_modulate = Color("102133")
	label.modulate = CREAM
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	parent.add_child(label)
	var plate_shape := QuadMesh.new()
	plate_shape.size = Vector2(maxf(0.72,float(value.length())*0.14)+0.15,0.30)
	var backing := mesh_node(plate_shape,Color("173d36"),at,parent)
	var material := backing.material_override as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.render_priority = -1
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.set_meta("backing",backing)
	return label

func _build_gate_links(view: Dictionary) -> void:
	# Only draw a cable where a mechanism and its route share a real floor.
	# Distant relationships use matching crests, never a false path over void.
	for gate: Dictionary in view.get("gates",[]):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges+view.get("stairs",[]):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var references := _predicate_references(gate.get("when",{}))
		var r: Array = route.rect_cm
		var end := point([r[0]-18,(r[1]+r[3])*0.5])+Vector3(0,float(route.get("from_height_cm",0))/100.0+0.025,0)
		for id: String in references:
			var entity: Dictionary = {}
			for item: Dictionary in view.get("controls",[])+view.get("levers",[])+view.get("pressure_pads",[])+view.optics.receivers:
				if item.id == id: entity = item
			if entity.is_empty(): continue
			var start := point(entity.position_cm)+Vector3(0,_control_base_height(entity)+0.025,0)
			var color := _route_color(id)
			_route_crest(id,start+Vector3(0.33,0.01,0),color,terrain)
			_route_crest(id,end,color,terrain)
			if _shares_floor(start,end):
				var elbow := Vector3(end.x,start.y,start.z)
				if start.distance_to(elbow)>0.01: _bar_between(start,elbow,0.016,color.darkened(0.25),terrain)
				if elbow.distance_to(end)>0.01: _bar_between(elbow,end,0.016,color.darkened(0.25),terrain)

func _predicate_references(predicate: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in ["control_id","signal_id","pad_id","lever_id"]:
		if predicate.has(key): result.append(str(predicate[key]))
	for key: String in ["all","any"]:
		for child: Dictionary in predicate.get(key,[]):
			for id: String in _predicate_references(child):
				if id not in result: result.append(id)
	return result

func _route_color(id: String) -> Color:
	return GOLD if id in ["path-selector","high-light","crossing-light","near-window"] else TEAL

func _route_crest(id: String, at: Vector3, color: Color, parent: Node3D) -> void:
	var count := 1 if id in ["path-selector","high-light","crossing-light","near-window"] else 2
	for index in range(count):
		box(Vector3(0.07,0.014,0.18),color,at+Vector3((float(index)-float(count-1)*0.5)*0.12,0,0),parent)

func _shares_floor(a: Vector3, b: Vector3) -> bool:
	if absf(a.y-b.y)>0.05: return false
	for island: Dictionary in chapter_definition.islands:
		var r: Array = island.rect_cm
		if a.x*100>=r[0] and a.x*100<=r[2] and a.z*100>=r[1] and a.z*100<=r[3] and b.x*100>=r[0] and b.x*100<=r[2] and b.z*100>=r[1] and b.z*100<=r[3]: return true
	return false

func present_history(checkpoint: Dictionary) -> void:
	super.present_history(checkpoint)
	if is_instance_valid(_remembered):
		_remembered.get_parent().remove_child(_remembered)
		_remembered.queue_free()
	_remembered = Node3D.new()
	_remembered.name = "RememberedJourneyRoutes"
	terrain.add_child(_remembered)
	for route: Dictionary in chapter_definition.bridges:
		if route.id not in _latched_bridge_ids: continue
		var r: Array = route.rect_cm
		var at := point([r[0]+12,r[3]-12])+Vector3(0,0.02,0)
		box(Vector3(0.20,0.035,0.14),CREAM,at,_remembered)
		box(Vector3(0.04,0.035,0.20),GOLD,at+Vector3(0,0.02,0),_remembered)

func present(state: Dictionary, immediate: bool = false) -> void:
	var visual := state.duplicate(true)
	visual["mirrors"] = state.get("controls",{}).duplicate()
	visual["emitter_powered"] = not state.get("optics",{}).get("segments",[]).is_empty()
	visual.get_or_add("route_progress",{})["kept_bridges"] = state.get("route_progress",{}).get("entered_routes",[]).duplicate()
	super.present(visual,immediate)
	for id: String in _journey_handles:
		_journey_handles[id].rotation.z = PI/4.0 if state.get("controls",{}).get(id,"backslash") == "slash" else -PI/4.0
	for id: String in _journey_switches:
		var switch: Dictionary = _journey_switches[id]
		var chosen: int = switch.values.find(state.get("controls",{}).get(id,""))
		_physical_levers[id].rotation.z = -0.60 if chosen == 0 else 0.60
		for index in range(switch.labels.size()):
			var label: Label3D = switch.labels[index]
			label.modulate = Color("18352f") if index == chosen else CREAM
			label.outline_modulate = GOLD if index == chosen else Color("102133")
			var backing: MeshInstance3D = label.get_meta("backing")
			(backing.material_override as StandardMaterial3D).albedo_color = GOLD if index == chosen else Color("173d36")
	if is_instance_valid(_waiting_ring): _glow(_waiting_ring,CREAM,0.6 if state.get("can_commit",false) else 0.0)

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not _completion_view: return super._should_cutaway(raised,state)
	for player: Dictionary in state.players.values():
		if _below_raised(raised,player): return true
	return false

func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view: target.z = clampf(actors[_active_player].position.z,-1.1,2.0)
	target.y = 0.45
	return target
