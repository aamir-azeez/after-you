extends "res://presentation/journey_world.gd"
## Open glass ribs and tiled floors outline a conservatory without covering
## the optical plane, the real stair openings, or the recoverable hatch.
const CONSERVATORY_FRAME := Color("789f98")
const CONSERVATORY_TILE := Color("8caaa1")
var _optical_fixtures: Array[Node3D] = []

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id","")) == displayed_stage_id: return
	_optical_fixtures.clear()
	await super.show_stage(stage)
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
	# Seams, glass and frames follow the floor as drawn (drawn_rect).
	var r := drawn_rect(island)
	var width := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var middle := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	surface.name = "Conservatory_"+str(island.id)
	if _ground_style(str(island.id)) == "deck":
		_build_balcony(island, surface)
		return
	# Floor seams avoid the genuine open hatch; no decorative tile closes it,
	# and each stays on the floor as drawn, clear of its trims.
	# Laid out over the walkable rectangle, clear of the trims round a hatch.
	var shape := drawn_pieces(island)
	var edges := WalkReach.outline(shape)
	var a: Array = island.rect_cm
	for x in range(int(a[0])+64,int(a[2]),64):
		for z in range(int(a[1])+64,int(a[3]),64):
			var on_floor := shape.any(func(piece: Array) -> bool: return x>int(piece[0]) and x<int(piece[2]) and z>int(piece[1]) and z<int(piece[3]))
			var by_edge := edges.any(func(edge: Array) -> bool: return absf((float(z) if edge[3] else float(x)) - float(edge[1])) < 8.0 and (float(x) if edge[3] else float(z)) > float(edge[0][0]) - 8.0 and (float(x) if edge[3] else float(z)) < float(edge[0][1]) + 8.0)
			var in_hatch := not on_floor or by_edge
			for drop: Dictionary in current_level.get("drops",[]):
				var hole: Array = drop.rect_cm
				if drop.surface_id == island.id and x>=hole[0]-8 and x<=hole[2]+8 and z>=hole[1]-8 and z<=hole[3]+8: in_hatch = true
			# Clear of the tile style's own seam lines (6 mm) where they cross.
			if not in_hatch: box(Vector3(0.06,0.006,0.06),Color("c0cbb6"),Vector3(float(x)/100,0.0095,float(z)/100),surface)
	if island.id not in ["court","gallery","mirror-room"]: return
	# Its posts' faces clear of the floor's trim along that edge (kit/surfaces.gd).
	var rear_z := float(r[1])/100.0+0.036
	var wall_height := 1.45
	# The glass wall and its gable stop where a raised floor stands over the
	# rear edge (the mirror room's east end under the recovery landing), so
	# the frame meets that floor's side instead of running into it.
	var span := _rear_wall_span(island)
	var wall_width := float(span[1]-span[0])/100.0
	var wall_middle := float(span[0]+span[1])/200.0
	var last_post := int(span[0])
	for x in range(int(span[0])+8,int(span[1]),96):
		last_post = x
		box(Vector3(0.045,wall_height,0.045),CONSERVATORY_FRAME,Vector3(float(x)/100,wall_height/2,rear_z),surface)
		if x+88<span[1]:
			var glass := box(Vector3(0.84,0.85,0.014),Color(0.52,0.77,0.72,0.18),Vector3(float(x+44)/100,0.74,rear_z),surface)
			glass.name = "ConservatoryGlass"
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if span[1]<r[2] and int(span[1])-last_post>30: box(Vector3(0.045,wall_height,0.045),CONSERVATORY_FRAME,Vector3(float(span[1])/100-0.03,wall_height/2,rear_z),surface)
	box(Vector3(wall_width,0.05,0.05),CONSERVATORY_FRAME,Vector3(wall_middle,wall_height,rear_z),surface)
	box(Vector3(wall_width,0.07,0.06),CONSERVATORY_FRAME,Vector3(wall_middle,0.20,rear_z),surface)
	# Roof ends form a glasshouse profile while the whole front and roof stay
	# open. Rafters hug the rear border and never masquerade as walkable lanes.
	var peak := Vector3(wall_middle,wall_height+0.62*wall_width/width,rear_z-0.03)
	_bar_between(Vector3(float(span[0])/100,wall_height,rear_z),peak,0.045,CONSERVATORY_FRAME,surface)
	_bar_between(peak,Vector3(float(span[1])/100,wall_height,rear_z),0.045,CONSERVATORY_FRAME,surface)
	for side: int in [-1,1]:
		# On the floor's trim (kit/surfaces.gd), its faces clear of the trim's,
		# and its top clear of a stair's tread over it.
		box(Vector3(0.03,0.15,depth-0.01),CONSERVATORY_FRAME,middle+Vector3(side*(width/2-0.03),0.075,0),surface)

## A plank balcony over a lower room (a raised floor in the "deck" style): it
## stands on the level's solid posts (its obstacles, drawn as posts by the
## dressing), with a stringer each side. When its back comes within 60 cm of
## the room's back wall, a ledger on the wall's frame carries it and a fern
## trough fills the gap;
## otherwise a rail closes it. Rails close its open sides and flower boxes
## hang off its outer rail. The frame stands on the room below, so it stays
## solid while the cutaway fades the deck for a pip underneath. The world
## builds it, not the dressing: it stands over the room's walkable floor,
## where dressing props may not.
func _build_balcony(island: Dictionary, surface: Node3D) -> void:
	var below := _floor_below(island)
	if below.is_empty(): return
	var r: Array = island.rect_cm
	var room: Node3D = _surface_nodes.get(str(below.id), terrain)
	# The deck's own beams (kit/surfaces.gd, 16 cm deep under its planks) stay
	# solid in the cutaway with the posts and stringers.
	for child: Node in surface.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and is_equal_approx((child.mesh as BoxMesh).size.y,0.16) and child.position.y<-0.3: child.set_meta(Cutaway.KEEP,true)
	var lit := bool(dressing.get("lit", true))
	# The deck's planks are 20 cm deep; the frame reaches up to them.
	var under := int(island.height_cm)-20
	var mid_z := int(r[1]+r[3])/2
	for x: int in [int(r[0])+4,int(r[2])-4]:
		_balcony_piece({"kind":"wall","from":[x,r[1]],"to":[x,r[3]],"height":12,"thickness":8,"y":under-22,"color":"7a5c40"},room,lit)
	var wall_z := int(below.rect_cm[1])
	var tucked: bool = int(r[1])-wall_z<=60
	if tucked:
		_balcony_piece({"kind":"wall","from":[r[0],wall_z+18],"to":[r[2],wall_z+18],"height":12,"thickness":8,"y":under-12,"color":"7a5c40"},room,lit)
		var trough_z0 := wall_z+17
		var trough_z1 := int(r[1])-7
		_balcony_piece({"kind":"planter","at":[(int(r[0])+int(r[2]))/2,(trough_z0+trough_z1)/2],"y":under,"width":int(r[2]-r[0]),"depth":trough_z1-trough_z0,"size":1.1},room,lit)
	var corners := [[int(r[2])+2,int(r[1])],[int(r[2])+2,int(r[3])+2],[int(r[0])-2,int(r[3])+2],[int(r[0])-2,int(r[1])]]
	for side in range(4 if not tucked else 3):
		_balcony_piece({"kind":"fence","from":corners[side],"to":corners[(side+1)%4],"size":1.45},surface,lit)
	for z: int in [(int(r[1])+mid_z)/2,(mid_z+int(r[3]))/2]:
		_balcony_piece({"kind":"planter","at":[int(r[2])+14,z],"rot":90,"y":-4,"width":60,"depth":14,"size":0.7},surface,lit)

## One kit prop as a piece of the world's balcony: built like dressing, but
## not counted as dressing (the lint counts those by their dressing_kind).
func _balcony_piece(spec: Dictionary, parent: Node3D, lit: bool) -> void:
	var piece := Props.build(spec, parent, 0.0, lit)
	piece.remove_meta("dressing_kind")
	piece.name = "Balcony_"+str(spec.kind)

## The floor this one stands over: the lower island holding its middle.
func _floor_below(island: Dictionary) -> Dictionary:
	var r: Array = island.rect_cm
	var at := Vector2(float(r[0]+r[2])*0.5,float(r[1]+r[3])*0.5)
	for other: Dictionary in current_level.get("islands",[]):
		var o: Array = other.rect_cm
		if other.id != island.id and int(other.get("height_cm",0))<int(island.get("height_cm",0)) and at.x>o[0] and at.x<o[2] and at.y>o[1] and at.y<o[3]: return other
	return {}

## The drawn rear edge's [x0, x1] in cm, cut back (with a 6 cm gap for its
## lip) at any floor standing at least 50 cm above this one over that edge.
func _rear_wall_span(island: Dictionary) -> Array:
	var r: Array = island.rect_cm
	var drawn := drawn_rect(island)
	var span := [int(drawn[0]),int(drawn[2])]
	for other: Dictionary in current_level.get("islands",[]):
		var o: Array = other.rect_cm
		if other.id == island.id or int(other.get("height_cm",0))<int(island.get("height_cm",0))+50: continue
		if o[1]>r[1] or o[3]<r[1] or o[2]<=span[0] or o[0]>=span[1]: continue
		if o[0]>span[0] and o[2]>=span[1]: span[1] = int(o[0])-6
		elif o[2]<span[1] and o[0]<=span[0]: span[0] = int(o[2])+6
	return span

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
		var transparency := BaseMaterial3D.TRANSPARENCY_ALPHA if alpha<0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
		# A kit material is shared by every mesh of its look: change a copy.
		if material.albedo_color.a != alpha or material.transparency != transparency:
			material = Primitives.own_material(node)
			material.albedo_color.a = alpha
			material.transparency = transparency
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
