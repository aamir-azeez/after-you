extends "res://presentation/journey_world.gd"
## A visible return route ending in an open-front house. Choice pads prepare
## one greeting window; the partner lights the complementary second window.
const WindowVisual = preload("res://presentation/house_window.gd")
const HOME_TIMBER := Color("ad8c67")
const HOME_FRAME := Color("80664e")
const HOME_PLASTER := Color("e2d6b6")
var _greeting_window: Dictionary = {}
var _arrival_window: Dictionary = {}
var _greeting_light: OmniLight3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id","")) == displayed_stage_id: return
	_greeting_window.clear()
	_arrival_window.clear()
	super.show_stage(stage)
	terrain.name = "LongWayHome"

func _has_completion_garden(stage_id: String) -> bool:
	return stage_id == "a-place-beside-you"

func _completion_garden_position(_goal: Dictionary) -> Vector3:
	return Vector3(13.25,0,2.54)

func _completion_garden_scale_vector() -> Vector3:
	return Vector3(0.70,0.75,0.28)

func _shore(island: Dictionary, color: Color) -> void:
	super._shore(island,HOME_TIMBER if island.id == "home-room" else Color("739982") if island.id in ["garden","garden-walk"] else color)

func _surface_built(island: Dictionary, surface: Node3D) -> void:
	surface.name = "Homeward_"+str(island.id)
	if island.id != "home-room": return
	var r: Array = island.rect_cm
	var width := float(r[2]-r[0])/100.0
	var depth := float(r[3]-r[1])/100.0
	var middle := point([(r[0]+r[2])*0.5,(r[1]+r[3])*0.5])
	for x in range(int(r[0])+36,int(r[2]),36):
		box(Vector3(0.012,0.008,depth),HOME_FRAME,Vector3(float(x)/100,0.006,middle.z),surface)
	# Low sides never imply blocking a porch or garden doorway. Only the
	# back has a taller open frame, leaving both entrances and pads visible.
	box(Vector3(width,0.44,0.10),HOME_PLASTER,Vector3(middle.x,0.22,float(r[1])/100),surface)
	for side: int in [-1,1]:
		box(Vector3(0.055,0.10,depth),HOME_FRAME,middle+Vector3(side*width/2,0.05,0),surface)
	var peak := Vector3(middle.x,2.05,float(r[1])/100)
	_bar_between(Vector3(float(r[0])/100,1.32,float(r[1])/100),peak,0.065,HOME_FRAME,surface)
	_bar_between(peak,Vector3(float(r[2])/100,1.32,float(r[1])/100),0.065,HOME_FRAME,surface)
	_greeting_window = WindowVisual.build(self,surface,Vector3(12.00,0,-0.64),0.88,HOME_FRAME,Color("729b95"),CREAM)
	_greeting_window.pane.name = "GreetingWindow"
	_greeting_light = OmniLight3D.new()
	_greeting_light.position = Vector3(12.00,0.82,-0.30)
	_greeting_light.light_color = GOLD
	_greeting_light.light_energy = 0.0
	_greeting_light.omni_range = 3.0
	surface.add_child(_greeting_light)

func _build_bell(goal: Dictionary) -> void:
	# Keep the exact native goal centre/radius; only the ornament above the
	# same action marker changes from a bell to an openable window.
	var cradle := Node3D.new()
	cradle.name = "ArrivalWindowGoal"
	cradle.position = point(goal.position_cm)
	terrain.add_child(cradle)
	cylinder(float(goal.radius_cm)/100.0,0.045,Color("748e87"),Vector3(0,0.025,0),cradle)
	_bell_ring = ring(float(goal.radius_cm)/100.0,CREAM,Vector3(0,0.06,0),cradle)
	_arrival_window = WindowVisual.build(self,cradle,Vector3(0,0,-0.44),0.80,HOME_FRAME,Color("729b95"),CREAM)
	_bell = _arrival_window.pane
	_bell.name = "SecondWindow"
	for side: int in [-1,1]: box(Vector3(0.08,0.42,0.08),HOME_FRAME,Vector3(side*0.42,0.21,-0.44),cradle)
	_court_light = OmniLight3D.new()
	_court_light.light_color = GOLD
	_court_light.light_energy = 0.0
	_court_light.omni_range = 4.0
	_court_light.position = cradle.position+Vector3(0,1.0,-0.20)
	terrain.add_child(_court_light)
	_ownership_mark(str(goal.owner_slot),cradle.position+Vector3(0,0.025,0.42),terrain)

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	super._build_physical_pad(pad,heavy)
	if pad.id not in ["near-window","garden-window"]: return
	var at := _at(pad)
	_route_crest(str(pad.id),at+Vector3(0.50,0.025,0),_route_color(str(pad.id)),terrain)
	_world_label("PORCH" if pad.id == "near-window" else "GARDEN",at+Vector3(0.20,0.12,-0.49),terrain)
	# Both pads visibly feed the same first window. They select a route, not
	# extra windows or another completion objective.
	var end := Vector3(12.00,0.02,-0.30)
	var elbow := Vector3(11.50,0.02,at.z)
	_bar_between(at+Vector3(0,0.02,0),elbow,0.016,TEAL.darkened(0.2),terrain)
	_bar_between(elbow,Vector3(elbow.x,0.02,end.z),0.016,TEAL.darkened(0.2),terrain)
	_bar_between(Vector3(elbow.x,0.02,end.z),end,0.016,TEAL.darkened(0.2),terrain)

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state,immediate)
	if not _arrival_window.is_empty(): WindowVisual.present(self,_arrival_window,bool(state.get("objective_done",false)),GOLD)
	if _greeting_window.is_empty(): return
	var lit: bool = bool(state.get("hold_pads",{}).get("near-window",false)) or bool(state.get("hold_pads",{}).get("garden-window",false))
	WindowVisual.present(self,_greeting_window,lit,GOLD)
	_greeting_light.light_energy = 0.65 if lit else 0.0
	_greeting_window.pane.set_meta("lit",lit)
	_arrival_window.pane.set_meta("lit",bool(state.get("objective_done",false)))
