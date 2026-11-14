extends "res://presentation/long_way_home_world.gd"
## Version 2 finale props on version 1's house, with its walled window and
## outside garden. The hall lamp's post, the walk's gate arch and the porch
## shutter are their selectors' pinned styles (kit/pieces/selector.gd); the
## garden arch B walks through is this world's own.
var _arch_lantern: MeshInstance3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id","")) == displayed_stage_id: return
	_arch_lantern = null
	await super.show_stage(stage)
	if stage.id == "a-place-beside-you":
		_garden_arch()

## The hall lamp's globe stands just right of its switch; the bubble floats
## left of it so the globe stays in view.
func _selector_bubble_shift(control: Dictionary) -> float:
	return -1.3 if str(control.id) == "hall-lamp" else 0.0

## The arch B walks through carries the hall lamp's colour, so the lamp can be
## read from the garden side as well as from the landing.
func _garden_arch() -> void:
	# Doorway posts stand on the walk's edge, either side of the arch's opening.
	var middle := Vector3(7.36,0,3.88)
	for x: float in [7.08,7.64]:
		box(Vector3(0.08,1.34,0.08),POST,Vector3(x,0.67,middle.z),terrain)
	box(Vector3(0.70,0.08,0.12),POST,Vector3(middle.x,1.36,middle.z),terrain)
	box(Vector3(0.02,0.16,0.02),POST,Vector3(middle.x,1.24,middle.z),terrain)
	_arch_lantern = sphere(0.15,SelectorPiece.LAMP_COLORS.off,Vector3(middle.x,1.06,middle.z),terrain)
	_arch_lantern.name = "ArchLantern"

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state,immediate)
	var controls: Dictionary = state.get("controls",{})
	for id: String in _journey_switches:
		# A chosen colour shows on its own plate rather than the usual gold.
		var value := str(controls.get(id,"off"))
		if _lever_pieces[id].lamp() != null and value in ["rose","moss"]:
			var label: Label3D = _journey_switches[id].labels[_journey_switches[id].values.find(value)]
			(label.get_meta("backing").material_override as StandardMaterial3D).albedo_color = SelectorPiece.LAMP_COLORS[value]
	if is_instance_valid(_arch_lantern): SelectorPiece.light_lamp(_arch_lantern,str(controls.get("hall-lamp","off")))
