extends "res://presentation/journey_world.gd"
## Open glass ribs and tiled floors outline a conservatory without covering
## the optical plane, the real stair openings, or the recoverable hatch.
const CONSERVATORY_FRAME := Color("789f98")
const CONSERVATORY_TILE := Color("8caaa1")
var _optical_fixtures: Array[Node3D] = []

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id","")) == displayed_stage_id: return
	_optical_fixtures.clear()
	super.show_stage(stage)
	terrain.name = "ConservatoryRooms"

func _has_completion_garden(_stage_id: String) -> bool: return true

func _completion_garden_position(_goal: Dictionary) -> Vector3:
	return Vector3(7.10,0,2.50)

func _completion_garden_scale_vector() -> Vector3:
	# A wide shallow bed leaves the source's entire accepted waiting region
	# and both goal approaches open, including off-centre accepted endpoints.
	return Vector3(0.75,0.80,0.30)

func _shore(island: Dictionary, color: Color) -> void:
	super._shore(island,Color("789487") if island.id == "garden" else CONSERVATORY_TILE if island.id in ["court","gallery","mirror-room"] else color)

func _surface_built(island: Dictionary, surface: Node3D) -> void:
	var r: Array = island.rect_cm
	var width := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var middle := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	surface.name = "Conservatory_"+str(island.id)
	# Floor seams avoid the genuine open hatch; no decorative tile closes it.
	for x in range(int(r[0])+64,int(r[2]),64):
		for z in range(int(r[1])+64,int(r[3]),64):
			var in_hatch := false
			for drop: Dictionary in current_level.get("drops",[]):
				var hole: Array = drop.rect_cm
				if drop.surface_id == island.id and x>=hole[0]-8 and x<=hole[2]+8 and z>=hole[1]-8 and z<=hole[3]+8: in_hatch = true
			if not in_hatch: box(Vector3(0.06,0.006,0.06),Color("c0cbb6"),Vector3(float(x)/100,0.005,float(z)/100),surface)
	if island.id not in ["court","gallery","mirror-room"]: return
	var rear_z := float(r[1])/100.0+0.025
	var wall_height := 1.45
	for x in range(int(r[0])+8,int(r[2]),96):
		box(Vector3(0.045,wall_height,0.045),CONSERVATORY_FRAME,Vector3(float(x)/100,wall_height/2,rear_z),surface)
		if x+88<r[2]:
			var glass := box(Vector3(0.84,0.85,0.014),Color(0.52,0.77,0.72,0.18),Vector3(float(x+44)/100,0.74,rear_z),surface)
			glass.name = "ConservatoryGlass"
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box(Vector3(width,0.05,0.05),CONSERVATORY_FRAME,Vector3(middle.x,wall_height,rear_z),surface)
	box(Vector3(width,0.07,0.06),CONSERVATORY_FRAME,Vector3(middle.x,0.20,rear_z),surface)
	# Roof ends form a glasshouse profile while the whole front and roof stay
	# open. Rafters hug the rear border and never masquerade as walkable lanes.
	var peak := Vector3(middle.x,wall_height+0.62,rear_z-0.03)
	_bar_between(Vector3(float(r[0])/100,wall_height,rear_z),peak,0.045,CONSERVATORY_FRAME,surface)
	_bar_between(peak,Vector3(float(r[2])/100,wall_height,rear_z),0.045,CONSERVATORY_FRAME,surface)
	for side: int in [-1,1]:
		box(Vector3(0.035,0.16,depth),CONSERVATORY_FRAME,middle+Vector3(side*(width/2-0.02),0.08,0),surface)

func _build_receiver(receiver: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_receiver(receiver)
	_remember_fixtures(before)
	if str(receiver.id).ends_with("warm"):
		# A shallow rosette makes an unhelpful ray destination visibly distinct
		# from the matching route crests beside useful receivers.
		var at := point(receiver.position_cm)+Vector3(0,_control_base_height(receiver)+0.015,0)
		for index in range(4):
			var leaf := sphere(0.12,Color("73997f"),at+Vector3(sin(index*PI/2)*0.16,0,cos(index*PI/2)*0.16),terrain)
			leaf.scale = Vector3(1,0.16,1)

func _build_source(control: Dictionary, emitter: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_source(control,emitter)
	_remember_fixtures(before)

func _build_mirror(control: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_mirror(control)
	_remember_fixtures(before)

func _remember_fixtures(first: int) -> void:
	for index in range(first,terrain.get_child_count()):
		var child := terrain.get_child(index) as Node3D
		if is_instance_valid(child): _optical_fixtures.append(child)

func _build_bell(goal: Dictionary) -> void:
	# The exact goal marker becomes a low illuminated garden crest. A tall
	# bell directly at the accepted standing point concealed the celebration.
	var cradle := Node3D.new()
	cradle.name = "GardenLightCrest"
	cradle.position = point(goal.position_cm)
	terrain.add_child(cradle)
	cylinder(float(goal.radius_cm)/100.0,0.05,Color("6b8984"),Vector3(0,0.025,0),cradle)
	_bell_ring = ring(float(goal.radius_cm)/100.0,CREAM,Vector3(0,0.06,0),cradle)
	_bell = box(Vector3(0.14,0.022,0.14),GOLD,Vector3(0,0.07,0),cradle)
	_bell.rotation.y = PI/4.0
	_court_light = OmniLight3D.new()
	_court_light.light_color = GOLD
	_court_light.light_energy = 0.0
	_court_light.omni_range = 4.0
	_court_light.position = cradle.position+Vector3(0,0.8,0)
	terrain.add_child(_court_light)

func _set_cutaway(node: Node, faded: bool) -> void:
	# A glass pane restores its authored transparency after the player returns
	# upstairs. Shared opaque floors continue using the same cutaway behavior.
	if node is MeshInstance3D and node.material_override is StandardMaterial3D and not node.has_meta("glass_original_alpha"):
		node.set_meta("glass_original_alpha",node.material_override.albedo_color.a)
		node.set_meta("glass_original_shadow",node.cast_shadow)
	super._set_cutaway(node,faded)
	if not faded and node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var material := node.material_override as StandardMaterial3D
		var alpha := float(node.get_meta("glass_original_alpha",1.0))
		material.albedo_color.a = alpha
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha<0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
		node.cast_shadow = int(node.get_meta("glass_original_shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON))

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state,immediate)
	# Only a completed reunion can separate two overlapping projections. The
	# recorded poses, live movement, waiting replay and interaction markers stay
	# exact. Keep a maximum58cm visual adjustment inside the real garden floor.
	if _completion_view and displayed_stage_id == "the-way-light-returns":
		var source: Node3D = actors["p1"]
		var receiver: Node3D = actors["p0"]
		var original: Vector3 = actor_targets["p1"]
		var separation := (original-receiver.position).dot(camera.basis.x)
		if absf(separation)<0.58:
			var side := -1.0 if separation<=0 else 1.0
			var offset: Vector3 = camera.basis.x*side*minf(0.58,0.58-absf(separation))
			var shown := original+offset
			shown.x = clampf(shown.x,5.80,8.28)
			shown.z = clampf(shown.z,-0.92,2.84)
			source.position = shown
			actor_targets["p1"] = shown
	for fixture: Node3D in _optical_fixtures:
		var obscure := false
		if _completion_view:
			for actor: Node3D in actors.values():
				var delta := fixture.global_position-(actor.global_position+Vector3(0,0.7,0))
				if absf(delta.dot(camera.global_basis.x))<0.48 and absf(delta.dot(camera.global_basis.y))<1.3: obscure = true
		_set_cutaway(fixture,obscure)
