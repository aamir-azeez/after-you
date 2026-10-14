extends "res://presentation/long_way_home_world.gd"
## Version 2 finale props: the hall lamp, the porch shutter and the garden gate,
## all on version 1's house, with its walled window and outside garden.
const LAMP_COLORS := {"off": Color("4a4038"), "shut": Color("4a4038"), "rose": Color("e8607e"), "moss": Color("6fae3c")}
var _lamps: Dictionary = {}
var _shutter: Node3D
var _arch_lantern: MeshInstance3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id","")) == displayed_stage_id: return
	_lamps.clear()
	_shutter = null
	_arch_lantern = null
	await super.show_stage(stage)
	if stage.id == "a-place-beside-you":
		_garden_arch()

func _build_selector(control: Dictionary) -> void:
	super._build_selector(control)
	match str(control.id):
		"hall-lamp": _lamp_post(control, _at(control)+Vector3(0.42,0,-0.14), 1.05)
		"walk-gate": _gate_arch(control)
		"porch-shutter": _porch_shutter(control)

## The hall lamp's globe stands just right of its switch; the bubble floats
## left of it so the globe stays in view.
func _selector_bubble_shift(control: Dictionary) -> float:
	return -1.3 if str(control.id) == "hall-lamp" else 0.0

## A post with a glass globe that shows the selector's colour.
func _lamp_post(control: Dictionary, base: Vector3, height: float) -> void:
	cylinder(0.11,0.06,POST,base+Vector3(0,0.03,0),terrain)
	cylinder(0.035,height,POST,base+Vector3(0,height*0.5,0),terrain)
	box(Vector3(0.26,0.04,0.26),POST,base+Vector3(0,height+0.02,0),terrain)
	var globe := sphere(0.20,LAMP_COLORS.off,base+Vector3(0,height+0.24,0),terrain)
	globe.name = "Lamp_"+str(control.id)
	box(Vector3(0.22,0.035,0.22),POST,base+Vector3(0,height+0.46,0),terrain)
	_lamps[control.id] = globe

## An open timber arch over the walk; its lantern shows the gate's colour.
func _gate_arch(control: Dictionary) -> void:
	var at := _at(control)
	var x := at.x+0.62
	for z: float in [3.88,4.76]:
		box(Vector3(0.09,1.30,0.09),POST,Vector3(x,0.65,z),terrain)
	box(Vector3(0.12,0.08,1.06),POST,Vector3(x,1.32,4.32),terrain)
	for z: float in [3.98,4.66]:
		var arc := box(Vector3(0.08,0.06,0.30),Color("8fb57a"),Vector3(x,1.40,z),terrain)
		arc.rotation.x = 0.35 if z < 4.3 else -0.35
	var lantern := sphere(0.12,LAMP_COLORS.shut,Vector3(x,1.12,4.32),terrain)
	lantern.name = "Lamp_"+str(control.id)
	_lamps[control.id] = lantern

## A shutter board beside the porch door that slides between its two marks.
func _porch_shutter(control: Dictionary) -> void:
	var at := _at(control)+Vector3(0.40,0,-0.42)
	for side: int in [-1,1]:
		box(Vector3(0.06,1.10,0.06),POST,at+Vector3(side*0.22,0.55,0),terrain)
	box(Vector3(0.50,0.05,0.08),POST,at+Vector3(0,1.12,0),terrain)
	_shutter = Node3D.new()
	_shutter.name = "PorchShutterBoard"
	_shutter.position = at
	terrain.add_child(_shutter)
	box(Vector3(0.38,0.40,0.04),Color("628c7a"),Vector3.ZERO,_shutter)
	for y: float in [-0.10,0.10]:
		box(Vector3(0.32,0.035,0.02),CREAM,Vector3(0,y,0.025),_shutter)

## The arch B walks through carries the hall lamp's colour, so the lamp can be
## read from the garden side as well as from the landing.
func _garden_arch() -> void:
	# Doorway posts stand on the walk's edge, either side of the arch's opening.
	var middle := Vector3(7.36,0,3.88)
	for x: float in [7.08,7.64]:
		box(Vector3(0.08,1.34,0.08),POST,Vector3(x,0.67,middle.z),terrain)
	box(Vector3(0.70,0.08,0.12),POST,Vector3(middle.x,1.36,middle.z),terrain)
	box(Vector3(0.02,0.16,0.02),POST,Vector3(middle.x,1.24,middle.z),terrain)
	_arch_lantern = sphere(0.15,LAMP_COLORS.off,Vector3(middle.x,1.06,middle.z),terrain)
	_arch_lantern.name = "ArchLantern"

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state,immediate)
	var controls: Dictionary = state.get("controls",{})
	for id: String in _lamps:
		_light(_lamps[id],str(controls.get(id,"off")))
		# A chosen colour shows on its own plate rather than the usual gold.
		var value := str(controls.get(id,"off"))
		if _journey_switches.has(id) and value in ["rose","moss"]:
			var label: Label3D = _journey_switches[id].labels[_journey_switches[id].values.find(value)]
			(label.get_meta("backing").material_override as StandardMaterial3D).albedo_color = LAMP_COLORS[value]
	if is_instance_valid(_arch_lantern): _light(_arch_lantern,str(controls.get("hall-lamp","off")))
	if is_instance_valid(_shutter):
		var down := str(controls.get("porch-shutter","up")) == "down"
		_shutter.position.y = _surface_height("near-porch")+(0.30 if down else 0.86)
		_shutter.set_meta("down",down)

func _light(globe: MeshInstance3D, value: String) -> void:
	var color: Color = LAMP_COLORS.get(value,LAMP_COLORS.off)
	(globe.material_override as StandardMaterial3D).albedo_color = color
	_glow(globe,color,0.9 if value in ["rose","moss"] else 0.0)
	globe.set_meta("value",value)
