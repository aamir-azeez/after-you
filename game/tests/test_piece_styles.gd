extends SceneTree
## Piece styles (content/dressing/piece_styles.gd) and the piece kits
## (presentation/kit/pieces/). A piece's behaviour is its block's and its
## engine's, proved once per block in test_stage_blocks.gd; here each style is
## built once, and the resolver's order, the machines' motion and each kit's
## handles are checked, so a new level restyles its pieces without retesting
## its puzzles.
const PieceStyles = preload("res://content/dressing/piece_styles.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Themes = preload("res://content/dressing/themes.gd")
const DressingCatalog = preload("res://content/dressing/catalog.gd")
const Index = preload("res://content/chapters/index.gd")
const Lever = preload("res://presentation/kit/pieces/lever.gd")
const Selector = preload("res://presentation/kit/pieces/selector.gd")
const Pad = preload("res://presentation/kit/pieces/pad.gd")
const Goal = preload("res://presentation/kit/pieces/goal.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
const AT := Vector3(1, 0.5, 2)
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_resolver()
	_check_published()
	var holder := Node3D.new()
	root.add_child(holder)
	_check_every_style(holder)
	_check_machines(holder)
	_check_valve(holder)
	_check_selector_props(holder)
	_check_goal_light(holder)
	holder.free()
	print("PIECE STYLES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A pin, then the dressing's field, its picks, its theme's picks, then the
## plain default; a name the slot does not offer is passed over.
func _check_resolver() -> void:
	for slot: String in PieceStyles.SLOTS:
		_check(slot in Styles.LOOK_SLOTS and Styles.has_style(slot, str(Styles.DEFAULT_PICKS[slot])), "Piece slot %s is a look slot with a default style" % slot)
		for theme: String in Themes.THEMES: _check(Styles.has_style(slot, str(Themes.THEMES[theme].picks.get(slot, ""))), "Theme %s picks a %s style" % [theme, slot])
	var pinned := {PieceStyles.PINS: {"chain": "winch", "wheel": "winch"}}
	var dressed := {"lever": "bolt", "picks": {"lever": "brass"}, "theme": "harbour"}
	_check(PieceStyles.style("lever", "chain", pinned, dressed) == "winch", "A pin wins")
	_check(PieceStyles.style("lever", "other", pinned, dressed) == "bolt", "The dressing's own field comes next")
	_check(PieceStyles.style("lever", "other", {}, {"picks": {"lever": "winch"}, "theme": "harbour"}) == "winch", "Then the dressing's picks")
	_check(PieceStyles.style("pad", "step", {}, {"theme": "harbour"}) == str(Themes.THEMES.harbour.picks.pad), "Then the theme's picks")
	_check(PieceStyles.style("goal", "bell", {}, {}) == "bell" and PieceStyles.style("lever", "x", {}, {}) == "plain", "Then the plain default")
	_check(PieceStyles.style("selector", "wheel", pinned, {}) == "plain", "A pin the slot does not offer falls through")
	_check(PieceStyles.control_slot({"kind": "selector"}) == "selector" and PieceStyles.control_slot({}) == "lever", "A control fills the selector or the lever slot")
	_check(PieceStyles.problems({PieceStyles.PINS: {"a": "winch", "b": "teapot"}}) == ["No piece style teapot for b"], "An unknown pin is named")
	# A resolved dressing carries each piece slot's pick, as every look slot.
	var resolved := DressingCatalog.resolve({"theme": "harbour"})
	for slot: String in PieceStyles.SLOTS: _check(str(resolved.get(slot, "")) == str(Themes.THEMES.harbour.picks[slot]), "A themed dressing carries its %s pick" % slot)

## Every chapter's pins name real styles, and its dressing's piece fields too.
func _check_published() -> void:
	for key: String in Index.keys():
		_check(PieceStyles.problems(Index.data(key)).is_empty(), "%s pins real piece styles: %s" % [key, PieceStyles.problems(Index.data(key))])
		var dressing := DressingCatalog.for_key(key)
		for slot: String in PieceStyles.SLOTS:
			if dressing.has(slot): _check(Styles.has_style(slot, str(dressing[slot])), "%s's dressing picks a real %s style" % [key, slot])

## One build per style: it stands on its spot under the parent, keeps the
## handles its world reads, and a name its kit does not know builds plain.
func _check_every_style(holder: Node3D) -> void:
	for style: String in Styles.SLOTS.lever:
		var piece: RefCounted = Lever.build(style, AT, holder, {"owner": "p1"})
		_check(piece.style == style and piece.root.get_parent() == holder and piece.root.position == AT and piece.anchor.get_parent() == holder, "Lever %s stands on its spot" % style)
		_check(not piece.moving_parts().is_empty() and _meshes(piece.root) > 0, "Lever %s builds and keeps its moving parts" % style)
	for style: String in Styles.SLOTS.selector:
		var piece: RefCounted = Selector.build(style, AT, holder, {"owner": "p0", "values": ["off", "rose", "moss"], "marks": [0, 1, 2], "id": "s"})
		_check(piece.style == style and piece.root.get_parent() == holder and piece.anchor.get_parent() == holder, "Selector %s stands on its spot" % style)
		_check(not piece.moving_parts().is_empty() and _meshes(piece.root) > 0, "Selector %s builds and keeps its moving parts" % style)
	for style: String in Styles.SLOTS.pad:
		var piece: RefCounted = Pad.build(style, AT, 0.32, holder, {"owner": "p0", "id": "step"})
		_check(piece.style == style and piece.rim is MeshInstance3D and piece.moving_parts().has(piece.rim), "Pad %s keeps the rim its world lights" % style)
		_check((piece.spot != null) == (style == "stand_spot"), "Only a stand spot pad keeps a stand spot")
		var ring := piece.rim.mesh as TorusMesh
		_check(is_equal_approx(ring.outer_radius, 0.32) if style == "stand_spot" else is_equal_approx(ring.outer_radius, 0.32 + 0.025), "Pad %s's rim is drawn at its radius" % style)
	_check(Pad.build("stand_spot", AT, 0.36, holder, {"heavy": true}).style == "plain", "A ball pad is always plain")
	for style: String in Styles.SLOTS.goal:
		var piece: RefCounted = Goal.build(style, AT, 0.28, holder)
		_check(piece.style == style and piece.bell is MeshInstance3D and piece.ring is MeshInstance3D and piece.light.get_parent() == holder and piece.bell.get_parent() == piece.root, "Goal %s keeps its bell, ring and light" % style)
		_check(is_equal_approx((piece.ring.mesh as TorusMesh).outer_radius, 0.28 + 0.025) and piece.root.position == AT, "Goal %s rings the goal's exact spot" % style)
		_check(is_zero_approx(piece.light.light_energy), "Goal %s is built unlit" % style)
	_check(Lever.build("teapot", AT, holder).style == "plain" and Selector.build("teapot", AT, holder).style == "plain" and Pad.build("teapot", AT, 0.3, holder).style == "plain" and Goal.build("teapot", AT, 0.3, holder).style == "bell", "An unknown style builds the default")

## A handle snaps; a machine stands inside its lever's reach, its anchor puts
## a bubble's tail on its top, and a pull eases over PULL_SECONDS to the pose
## a snapped pull shows (so a replay agrees) and comes back as built.
func _check_machines(holder: Node3D) -> void:
	_check(is_equal_approx(Lever.KNOB_REACH, JourneyWorld.KNOB.y + JourneyWorld.KNOB_RADIUS), "A machine's tail point is journey_world's knob point")
	for style: String in Lever.HANDLES:
		var handle: RefCounted = Lever.build(style, AT, holder)
		handle.set_pulled(true)
		_check(not handle.moving() and is_equal_approx(handle.anchor.rotation.z, -Lever.TILT), "A %s handle snaps over when pulled" % style)
		handle.set_value(1)
		_check(is_equal_approx(handle.anchor.rotation.z, Lever.TILT), "A %s selector handle stands back for any value but the first" % style)
	for style: String in Lever.MACHINES:
		var look: RefCounted = Lever.build(style, AT, holder)
		var built := _pose(look.root)
		var top := _top(look.root)
		_check(_inside(look.root, Lever.EAST_SIDE), "The %s stays inside its lever's reach" % style)
		var tail: float = look.anchor.position.y + Lever.KNOB_REACH - look.root.position.y
		_check(absf(tail - top) < 0.03, "The %s's anchor puts a bubble's tail on its top (%.3f, %.3f)" % [style, tail, top])
		look.set_pulled(true)
		_check(look.moving() and look.shown() == 0.0, "A pull eases from where the %s stands" % style)
		for frame in range(int(ceil(Lever.PULL_SECONDS * 60.0)) + 1): look.advance(1.0 / 60.0)
		var eased := _pose(look.root)
		_check(not look.moving() and look.shown() == 1.0 and eased != built, "The %s's pull plays out and rests pulled" % style)
		var snapped: RefCounted = Lever.build(style, AT, holder)
		snapped.set_pulled(true, true)
		_check(_pose(snapped.root) == eased and _inside(snapped.root, Lever.EAST_SIDE), "An eased and a snapped %s pull end in the same pose, inside its reach" % style)
		look.set_pulled(false, true)
		_check(_pose(look.root) == built, "Let go, the %s is back as it was built" % style)

## A valve: a dial mark per value, its arrow eased or snapped to the same turn,
## its first value snapped, its sign spot up behind it.
func _check_valve(holder: Node3D) -> void:
	var valve: RefCounted = Selector.build("valve", AT, holder, {"owner": "p0", "marks": [0, 1, 2, 3]})
	_check(_inside(valve.root, Selector.REACH), "The valve stays inside its selector's reach")
	var pointer: MeshInstance3D = valve.wheel().find_child("WheelPointer", false, false)
	var wheel_top: float = (valve.root.global_transform.affine_inverse() * pointer.global_transform * pointer.get_aabb()).end.y
	_check(absf(valve.anchor.position.y + Lever.KNOB_REACH - valve.root.position.y - wheel_top) < 0.03, "The valve's anchor puts a bubble's tail on its wheel")
	var ticks: Array = valve.root.find_children("*", "MeshInstance3D", false, false).filter(func(node: Node) -> bool: return ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == Parts.MARK)
	_check(ticks.size() == 0 + 1 + 2 + 3 + 1, "The dial marks a bar for the first value and one, two, three bands for the rest (%d)" % ticks.size())
	valve.set_value(1)
	_check(not valve.moving() and is_equal_approx(valve.wheel().rotation.y, Selector.value_angle(1, 4)), "A valve's first value snaps, never sweeping in")
	valve.set_value(3)
	_check(valve.moving(), "A later value eases")
	for frame in range(60): valve.advance(1.0 / 60.0)
	var snapped: RefCounted = Selector.build("valve", AT, holder, {"marks": [0, 1, 2, 3]})
	snapped.set_value(0)
	snapped.set_value(3, true)
	_check(not valve.moving() and is_equal_approx(valve.wheel().rotation.y, -Selector.VALVE_SWEEP) and _pose(snapped.root) == _pose(valve.root), "The valve's arrow turns to the last value, eased or snapped alike")
	valve.set_pulled(true, true)
	_check(is_equal_approx(valve.wheel().rotation.y, -Selector.VALVE_SWEEP), "A pull leaves a valve as it is")
	var sign: Vector3 = valve.sign_point() - valve.root.position
	_check(sign.y > wheel_top and sign.z < -0.1, "The valve's sign stands up behind it, over its wheel")

## A lamp shows its value's colour, lit, and goes dark for a value it has no
## colour for; a shutter slides down for "down" and up otherwise.
func _check_selector_props(holder: Node3D) -> void:
	for style: String in ["lamp_post", "gate_arch"]:
		var lamp: RefCounted = Selector.build(style, AT, holder, {"values": ["off", "rose", "moss"], "id": "hall"})
		lamp.set_value(1)
		var mat := lamp.lamp().material_override as StandardMaterial3D
		_check(lamp.lamp().name == "Lamp_hall" and mat.albedo_color == Selector.LAMP_COLORS.rose and mat.emission_enabled and lamp.lamp().get_meta("value") == "rose", "A %s lights its value's colour" % style)
		lamp.set_value(0)
		mat = lamp.lamp().material_override as StandardMaterial3D
		_check(mat.albedo_color == Selector.LAMP_COLORS.off and not mat.emission_enabled, "A %s goes dark at a value with no colour" % style)
		_check(is_equal_approx(lamp.anchor.rotation.z, -Lever.TILT), "A %s's lever shows the first value like a plain one" % style)
	var shutter: RefCounted = Selector.build("shutter", AT, holder, {"values": ["up", "down"]})
	var board: Node3D = shutter.root.find_child("PorchShutterBoard", false, false)
	shutter.set_value(1)
	var down := board.position.y
	shutter.set_value(0)
	_check(board.get_meta("down") == false and is_equal_approx(down, Selector.SHUTTER_DOWN) and is_equal_approx(board.position.y, Selector.SHUTTER_UP), "The shutter slides down and back up with its value")

## A goal lights once its stage is done: ring and ornament glow, its light
## comes up, a window opens; put out, all of it goes back.
func _check_goal_light(holder: Node3D) -> void:
	for style: String in Styles.SLOTS.goal:
		var goal: RefCounted = Goal.build(style, AT, 0.28, holder)
		goal.set_lit(true)
		var shutters: Array = goal.window.get("shutters", [])
		_check((goal.ring.material_override as StandardMaterial3D).emission_enabled and (goal.bell.material_override as StandardMaterial3D).emission_enabled and goal.light.light_energy > 0.0 and goal.bell.get_meta("lit"), "Goal %s lights" % style)
		_check(shutters.all(func(shutter: Node3D) -> bool: return not is_zero_approx(shutter.rotation.y)), "Goal %s opens any shutters it has" % style)
		goal.set_lit(false)
		_check(not (goal.ring.material_override as StandardMaterial3D).emission_enabled and is_zero_approx(goal.light.light_energy) and not goal.bell.get_meta("lit"), "Goal %s goes out" % style)

func _meshes(node: Node) -> int:
	return node.find_children("*", "MeshInstance3D", true, false).size()

## Every mesh under `node` inside the 28 cm reach of its spot, east no further
## than `east`, and nothing below its floor.
func _inside(node: Node3D, east: float) -> bool:
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = node.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		if box.position.x < -Lever.REACH - 0.001 or box.end.x > east + 0.001 or absf(box.position.z) > Lever.REACH or absf(box.end.z) > Lever.REACH or box.position.y < -0.001: return false
	return true

func _top(node: Node3D) -> float:
	var top := -INF
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (node.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()).end.y)
	return top

## Every mesh's transform under `node`, rounded to 0.1 mm.
func _pose(node: Node3D) -> Array:
	var pose: Array = []
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = (mesh as MeshInstance3D).global_transform
		for v: Vector3 in [t.basis.x, t.basis.y, t.basis.z, t.origin]: pose.append(Vector3i((v * 10000.0).round()))
	return pose
