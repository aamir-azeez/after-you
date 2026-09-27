extends "res://presentation/cooperative_world.gd"
## A cutaway house built on the shared physical world and snapshot presentation.
## The walls, windows and furniture never participate in movement or recording.
const TIMBER := Color("ad8c67")
const PLASTER := Color("e2d6b6")
const FRAME := Color("80664e")
const GLASS := Color("729b95")
var _house_windows: Dictionary = {}
var _house_memories: Node3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_house_windows.clear()
	super.show_stage(stage)
	terrain.name = "HouseRooms"
	_update_house_windows()

func _has_completion_garden(stage_id: String) -> bool:
	return stage_id == "the-room-below"

func _uses_lower_cutaway() -> bool: return true
func _uses_scrolling_camera() -> bool: return true

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not _completion_view: return super._should_cutaway(raised,state)
	# The receiver can finish in the sunroom while their partner remains below
	# the loft. Keep both spirits visible during the shared celebration.
	for player: Dictionary in state.players.values():
		if _below_raised(raised,player): return true
	return false

func _gate_link_color(mechanism: Dictionary) -> Color:
	match str(mechanism.id):
		"entry-weight": return Color("e5b773")
		"stair-weight": return Color("84b6cc")
		"sunroom-weight": return Color("8cc59a")
	return CREAM

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	super._build_physical_pad(pad,heavy)
	_route_symbol(str(pad.id),_at(pad)+Vector3(0,0.035,0.54),terrain)

func _build_gate_links(view: Dictionary) -> void:
	super._build_gate_links(view)
	for gate: Dictionary in view.get("gates",[]):
		var pad := str(gate.get("ball_pad_id",""))
		if pad.is_empty(): continue
		for route: Dictionary in view.bridges+view.get("stairs",[]):
			if route.id != gate.route_id: continue
			var r: Array = route.rect_cm
			_route_symbol(pad,point([r[0]-24,(r[1]+r[3])*0.5])+Vector3(0,0.035,0),terrain)

func _route_symbol(id: String, at: Vector3, parent: Node3D) -> void:
	var count := 1 if id == "entry-weight" else 2 if id == "stair-weight" else 3
	var color := _gate_link_color({"id":id})
	for index in range(count):
		box(Vector3(0.09,0.025,0.20),color,at+Vector3((index-(count-1)*0.5)*0.14,0,0),parent)

func present_history(checkpoint: Dictionary) -> void:
	super.present_history(checkpoint)
	if is_instance_valid(_house_memories):
		_house_memories.get_parent().remove_child(_house_memories)
		_house_memories.queue_free()
	_house_memories = Node3D.new()
	_house_memories.name = "RememberedHouseRoutes"
	terrain.add_child(_house_memories)
	var shown_index := 0
	for index in range(chapter_definition.stages.size()):
		if chapter_definition.stages[index].id == displayed_stage_id: shown_index = index
	for index in range(mini(int(checkpoint.get("stage_index",0)),shown_index)):
		for pad: Dictionary in chapter_definition.stages[index].get("ball_pads",[]):
			var at := _at(pad)
			ring(float(pad.radius_cm)/100.0,Color("8f8a72"),at+Vector3(0,0.025,0),_house_memories)
			_route_symbol(str(pad.id),at+Vector3(0,0.035,0.54),_house_memories)
	for route: Dictionary in chapter_definition.bridges+chapter_definition.get("stairs",[]):
		if route.id not in _latched_bridge_ids: continue
		var r: Array = route.rect_cm
		var at := point([r[0]+12,r[3]+16])
		# A small fixed bracket replaces the idea of another live weight.
		box(Vector3(0.24,0.06,0.18),TIMBER,at+Vector3(0,0.03,0),_house_memories)
		box(Vector3(0.045,0.10,0.22),CREAM,at+Vector3(0,0.06,0),_house_memories)

func _shore(island: Dictionary, _color: Color) -> void:
	var room := Node3D.new()
	room.name = "HouseRoom_" + str(island.id)
	room.position.y = float(island.get("height_cm",0))/100.0
	room.set_meta("bounds", island.rect_cm.duplicate())
	terrain.add_child(room)
	if room.position.y > 0.5: _upper_islands.append(room)
	var r: Array = island.rect_cm
	var pieces: Array = [r]
	for drop: Dictionary in current_level.get("drops", []):
		if drop.surface_id != island.id: continue
		var h: Array = drop.rect_cm
		pieces = [[r[0],r[1],h[0],r[3]], [h[2],r[1],r[2],r[3]], [h[0],r[1],h[2],h[1]], [h[0],h[3],h[2],r[3]]]
	for piece: Array in pieces:
		if piece[2] <= piece[0] or piece[3] <= piece[1]: continue
		var width := float(piece[2]-piece[0])/100.0
		var depth := float(piece[3]-piece[1])/100.0
		var at := point([(piece[0]+piece[2])*0.5,(piece[1]+piece[3])*0.5])
		box(Vector3(width,0.28,depth),TIMBER,at+Vector3(0,-0.14,0),room)
		for x in range(int(piece[0])+36,int(piece[2]),36):
			box(Vector3(0.012,0.008,depth),FRAME,Vector3(float(x)/100.0,0.004,at.z),room)
	# The front stays entirely open. Low side skirting outlines the rooms
	# without suggesting a solid wall across a traversable threshold.
	var width := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var middle := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	for side: int in [-1,1]:
		box(Vector3(0.06,0.12,depth),FRAME,middle+Vector3(side*width*0.5,0.06,0),room)
	var rear := Vector3(middle.x,0,float(r[1])/100.0)
	var window_width := minf(1.12,width*0.45)
	var pier := (width-window_width)*0.5
	box(Vector3(width,0.44,0.12),PLASTER,rear+Vector3(0,0.22,0),room)
	for side: int in [-1,1]:
		box(Vector3(pier,1.28,0.12),PLASTER,rear+Vector3(side*(window_width+pier)*0.5,0.64,0),room)
	box(Vector3(window_width,0.14,0.12),PLASTER,rear+Vector3(0,1.21,0),room)
	var pane := box(Vector3(window_width-0.12,0.60,0.025),GLASS,rear+Vector3(0,0.80,0.035),room)
	box(Vector3(window_width+0.10,0.065,0.24),FRAME,rear+Vector3(0,0.45,0.03),room)
	for side: int in [-1,1]:
		box(Vector3(0.055,0.70,0.08),FRAME,rear+Vector3(side*window_width*0.5,0.80,0.06),room)
	box(Vector3(window_width,0.055,0.08),FRAME,rear+Vector3(0,1.15,0.06),room)
	box(Vector3(0.04,0.66,0.04),FRAME,rear+Vector3(0,0.80,0.06),room)
	var shutters: Array[Node3D] = []
	for side: int in [-1,1]:
		var shutter := Node3D.new()
		shutter.position = rear+Vector3(side*window_width*0.5,0.80,0.10)
		shutter.set_meta("side",side)
		room.add_child(shutter)
		box(Vector3(window_width*0.46,0.64,0.065),Color("628c7a"),Vector3(-side*window_width*0.23,0,0),shutter)
		for y in [-0.18,0.18]:
			box(Vector3(window_width*0.40,0.045,0.028),CREAM,Vector3(-side*window_width*0.23,y,0.04),shutter)
		shutters.append(shutter)
	_house_windows[island.id] = {"pane":pane,"shutters":shutters}
	# Open roof rafters supply a house silhouette without covering the puzzle.
	var peak := rear+Vector3(0,1.95,-0.03)
	_bar_between(rear+Vector3(-width*0.52,1.28,-0.03),peak,0.065,FRAME,room)
	_bar_between(peak,rear+Vector3(width*0.52,1.28,-0.03),0.065,FRAME,room)

func _build_obstacle(obstacle: Dictionary) -> void:
	# The bench footprint comes from the authored collision rectangle, so its
	# visible edges and the ball route always agree.
	var r: Array = obstacle.rect_cm
	var width := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var at := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	at.y = _surface_height(str(obstacle.surface_id))
	box(Vector3(width,0.09,depth),FRAME,at+Vector3(0,0.58,0),terrain)
	for x: int in [-1,1]:
		for z: int in [-1,1]:
			box(Vector3(0.10,0.55,0.10),FRAME,at+Vector3(x*(width*0.5-0.08),0.28,z*(depth*0.5-0.08)),terrain)
	box(Vector3(width-0.12,0.08,depth-0.12),TIMBER,at+Vector3(0,0.20,0),terrain)
	box(Vector3(0.20,0.10,0.16),GOLD,at+Vector3(0.12,0.67,-0.12),terrain)
	box(Vector3(0.32,0.025,0.20),CREAM,at+Vector3(-0.17,0.64,0.12),terrain)

func _build_bridge(definition: Dictionary) -> void:
	super._build_bridge(definition)
	var r: Array = definition.rect_cm
	var length := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var at := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	# Long gaps read as connecting corridors; their retractable floors and
	# existing pulley weights still show the exact open/closed simulation state.
	for side: int in [-1,1]:
		box(Vector3(length,0.16,0.09),PLASTER,at+Vector3(0,0.08,side*(depth*0.5+0.06)),terrain)
		box(Vector3(0.09,1.45,0.09),FRAME,at+Vector3(length*0.5,0.725,side*(depth*0.5+0.06)),terrain)
	box(Vector3(0.10,0.09,depth+0.20),FRAME,at+Vector3(length*0.5,1.45,0),terrain)

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state,immediate)
	_update_house_windows()

func _update_house_windows() -> void:
	for id: String in _house_windows:
		var warm := id == "foyer" or (id in ["workshop","loft"] and (displayed_stage_id == "the-room-below" or _completion_view)) or (id == "sunroom" and displayed_stage_id == "the-room-below" and _completion_view)
		var window: Dictionary = _house_windows[id]
		_glow(window.pane,GOLD,0.65 if warm else 0.0)
		for shutter: Node3D in window.shutters:
			shutter.rotation.y = -float(shutter.get_meta("side"))*2.25 if warm else 0.0
