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
const PadChecks = preload("res://tests/pad_checks.gd")
const Goal = preload("res://presentation/kit/pieces/goal.gd")
const Lift = preload("res://presentation/kit/pieces/lift.gd")
const Pulley = preload("res://presentation/kit/pieces/pulley.gd")
const BridgeKit = preload("res://presentation/kit/pieces/bridge.gd")
const TautBridge = preload("res://presentation/kit/pieces/taut_bridge.gd")
const ClosingWarning = preload("res://presentation/kit/closing_warning.gd")
const Raft = preload("res://presentation/kit/pieces/raft.gd")
const Swing = preload("res://presentation/kit/pieces/swing.gd")
const CarriedItem = preload("res://presentation/kit/pieces/carried_item.gd")
const Socket = preload("res://presentation/kit/pieces/socket.gd")
const Motion = preload("res://presentation/kit/motion.gd")
## Frames (at 60 a second) that outlast any arrival's overshoot.
const SETTLE_FRAMES := int(Motion.ARRIVAL_SECONDS * 60.0) + 2
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
	_check_goal_pads(holder)
	_check_arrivals(holder)
	_check_swings(holder)
	_check_taut(holder)
	_check_closing_fade(holder)
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
	var dressed := DressingCatalog.resolve({"lever": "bolt", "picks": {"lever": "brass"}, "theme": "harbour"})
	_check(PieceStyles.style("lever", "chain", pinned, dressed) == "winch", "A pin wins")
	_check(PieceStyles.style("lever", "other", pinned, dressed) == "bolt", "The dressing's own field comes next")
	_check(PieceStyles.style("lever", "other", {}, DressingCatalog.resolve({"picks": {"lever": "winch"}, "theme": "harbour"})) == "winch", "Then the dressing's picks")
	_check(PieceStyles.style("pad", "step", {}, DressingCatalog.resolve({"theme": "harbour"})) == str(Themes.THEMES.harbour.picks.pad), "Then the theme's picks")
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
		_check(PadChecks.outline_fits(piece) and piece.at == AT and is_equal_approx(piece.radius, 0.32), "Pad %s's outline is drawn at its radius: a board's square, a pan's round" % style)
	_check(Styles.DEFAULT_PICKS.pad == Pad.DEFAULT_STYLE and Pad.DEFAULT_STYLE == "board", "Every pad is the board that presses down unless a block names a crank board or a pan")
	_check(Pad.build("pan", AT, 0.36, holder, {"heavy": true}).style == "board", "A ball pad is always a board")
	# The board's top never sinks to the floor, even at the bottom of a press's
	# dip, so a pad never vanishes under a pip (owner, 2026-11-21).
	_check(Pad.BOARD_TOP - Pad.BOARD_SINK - Pad.DIP * 1.05 > 0.0, "A pressed board's top stays above the floor")
	for style: String in Styles.SLOTS.goal:
		var piece: RefCounted = Goal.build(style, AT, 0.28, holder)
		_check(piece.style == style and piece.bell is MeshInstance3D and piece.ring is MeshInstance3D and piece.light.get_parent() == holder and piece.root.is_ancestor_of(piece.bell), "Goal %s keeps its bell, ring and light" % style)
		_check(is_equal_approx((piece.ring.mesh as TorusMesh).outer_radius, 0.28 + 0.025) and piece.root.position == AT, "Goal %s rings the goal's exact spot" % style)
		_check(is_zero_approx(piece.light.light_energy), "Goal %s is built unlit" % style)
	for style: String in Styles.SLOTS.lift:
		var piece: RefCounted = Lift.build(style, Rect2(-1.0, -0.9, 2.0, 1.8), 0.0, 1.6, holder, {"drive": Vector3(-3.0, 0, -1.3)})
		_check(piece.style == style and piece.root.get_parent() == holder and piece.moving_parts().has(piece.root) and _meshes(piece.root) > 0, "Lift %s builds its deck and keeps it moving" % style)
		piece.set_height(0.8)
		_check(is_equal_approx(piece.root.position.y, 0.8), "Lift %s's deck stands at the shown height" % style)
	_check(Lift.build("teapot", Rect2(0, 0, 1, 1), 0.0, 1.0, holder).style == "plain", "An unknown lift style builds plain")
	_check(Lever.build("teapot", AT, holder).style == "plain" and Selector.build("teapot", AT, holder).style == "plain" and Pad.build("teapot", AT, 0.3, holder).style == "board" and Goal.build("teapot", AT, 0.3, holder).style == "bell", "An unknown style builds the default")
	for style: String in Styles.SLOTS.pulley:
		var post: RefCounted = Pulley.build(style, AT, holder)
		_check(post.style == style and post.root.get_parent() == holder and post.root.position == AT and post.weight.get_parent() == post.root and is_equal_approx(post.weight.position.y, Pulley.REST_Y), "Pulley %s stands on its spot, its weight hung" % style)
		var rope: MeshInstance3D = post.moving_parts()[0]
		for laid: bool in [true, false]:
			post.weight.position.y = Pulley.REST_Y - (0.7 if laid else 0.0)
			post.set_laid(laid)
			_check(is_equal_approx(rope.position.y - rope.scale.y * 0.5, post.weight.position.y + post._hang) and rope.position.y + rope.scale.y * 0.5 <= post.anchor_lift() + 0.001, "Pulley %s's rope runs from its wheel to its weight (laid %s)" % [style, laid])
			var glass: MeshInstance3D = post._glass
			if glass != null: _check((glass.material_override as StandardMaterial3D).emission_enabled == laid, "Pulley %s's lantern glows only while laid" % style)
	_check(Pulley.build("teapot", AT, holder).style == Pulley.STYLES[0] and Pulley.build("lantern_hook", AT, holder)._glass != null and Pulley.build("little_roof", AT, holder)._glass == null, "An unknown pulley builds the first style; only the lantern has a glass")
	# A hanger lays its coil only wholly on a floor by its foot: a roomy floor, then one whose edge runs too close.
	var roomy: Array[Rect2] = [Rect2(-2.0, -2.0, 1.95, 2.5)]
	var narrow: Array[Rect2] = [Rect2(-2.0, -2.0, 1.95, 2.1)]
	var coils := func(ground: Array[Rect2]) -> Array: return Pulley.build("theme_hanger", AT, holder, ground).root.find_children("Coil*", "", false, false)
	_check(coils.call(roomy).size() == Pulley.COIL_RINGS.size() and coils.call(narrow).is_empty() and coils.call([] as Array[Rect2]).is_empty(), "A hanger lays its rope coil only where a floor at its foot holds it clear of the edges")
	# A wall built later in front of the coil (toward the camera) takes it away; one behind it does not.
	var kept := func(wall: AABB) -> int:
		var post: RefCounted = Pulley.build("theme_hanger", AT, holder, roomy)
		post.drop_unseen([wall] as Array[AABB])
		return post.root.find_children("Coil*", "", false, false).size()
	var spot := AT + Vector3(Pulley.COIL_AT.x, 0, Pulley.COIL_AT.y)
	_check(kept.call(AABB(spot + Vector3(-1.0, 0, 0.25), Vector3(2.0, 0.6, 0.1))) == 0 and kept.call(AABB(spot + Vector3(-1.0, 0, -0.45), Vector3(2.0, 0.6, 0.1))) == Pulley.COIL_RINGS.size(), "A wall in front hides a hanger's coil and leaves it out; a wall behind keeps it")

## A handle snaps; a machine stands inside its lever's reach, its anchor puts
## a bubble's tail on its top, and a pull eases over PULL_SECONDS to the pose
## a snapped pull shows (so a replay agrees) and comes back as built.
func _check_machines(holder: Node3D) -> void:
	_check(is_equal_approx(Lever.KNOB_REACH, JourneyWorld.KNOB.y + JourneyWorld.KNOB_RADIUS), "A machine's tail point is journey_world's knob point")
	for style: String in Lever.HANDLES:
		var handle: RefCounted = Lever.build(style, AT, holder)
		handle.set_pulled(true)
		_check(handle.moving() and is_equal_approx(handle.anchor.rotation.z, -Lever.TILT), "A %s handle snaps over when pulled, then settles" % style)
		var deepest := 0.0
		for frame in range(SETTLE_FRAMES):
			handle.advance(1.0 / 60.0)
			deepest = minf(deepest, handle.anchor.rotation.z + Lever.TILT)
		var thrown: RefCounted = Lever.build(style, AT, holder)
		thrown.set_pulled(true, true)
		_check(not handle.moving() and _pose(handle.root) == _pose(thrown.root) and deepest < -0.5 * Lever.HANDLE_OVER, "A thrown %s handle swings past its stop and rests exactly pulled (%.3f)" % [style, deepest])
		handle.set_value(1)
		_check(is_equal_approx(handle.anchor.rotation.z, Lever.TILT), "A %s selector handle stands back for any value but the first" % style)
		handle.set_value(0, true)
		_check(not handle.moving() and is_equal_approx(handle.anchor.rotation.z, -Lever.TILT), "A %s handle thrown at once (a seek, reduced motion) never swings" % style)
	for style: String in Lever.MACHINES:
		var look: RefCounted = Lever.build(style, AT, holder)
		var built := _pose(look.root)
		var top := _top(look.root)
		_check(_inside(look.root, Lever.EAST_SIDE), "The %s stays inside its lever's reach" % style)
		var tail: float = look.anchor.position.y + Lever.KNOB_REACH - look.root.position.y
		_check(absf(tail - top) < 0.03, "The %s's anchor puts a bubble's tail on its top (%.3f, %.3f)" % [style, tail, top])
		look.set_pulled(true)
		_check(look.moving() and look.shown() == 0.0, "A pull eases from where the %s stands" % style)
		for frame in range(int(ceil(Lever.PULL_SECONDS * 60.0)) + 1 + SETTLE_FRAMES): look.advance(1.0 / 60.0)
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
	for frame in range(60 + SETTLE_FRAMES): valve.advance(1.0 / 60.0)
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
## comes up, a window opens, a bell rings once (never on an immediate
## light, which a seek, a retry and a replay snap to); put out, all of it goes
## back.
func _check_goal_light(holder: Node3D) -> void:
	for style: String in Styles.SLOTS.goal:
		var goal: RefCounted = Goal.build(style, AT, 0.28, holder)
		goal.set_lit(true)
		var shutters: Array = goal.window.get("shutters", [])
		_check((goal.ring.material_override as StandardMaterial3D).emission_enabled and (goal.bell.material_override as StandardMaterial3D).emission_enabled and goal.light.light_energy > 0.0 and goal.bell.get_meta("lit"), "Goal %s lights" % style)
		_check(shutters.all(func(shutter: Node3D) -> bool: return not is_zero_approx(shutter.rotation.y)), "Goal %s opens any shutters it has" % style)
		if goal.chime != null:
			var swing: Node3D = goal.chime.swing
			_check(goal.moving() and goal.moving_parts().has(swing), "Goal %s rings as it lights, and keeps its swing whole" % style)
			goal.advance(Goal.Bell.STRIKE)
			_check(swing.rotation.x > 0.1, "Goal %s's bell swings out by its strike" % style)
			goal.set_lit(true)
			_check(goal.moving(), "Goal %s rings on while it stays lit" % style)
			goal.advance(Goal.Bell.RING_TIME)
			_check(not goal.moving() and is_zero_approx(swing.rotation.x), "Goal %s's bell comes back to rest" % style)
		goal.set_lit(false)
		_check(not (goal.ring.material_override as StandardMaterial3D).emission_enabled and is_zero_approx(goal.light.light_energy) and not goal.bell.get_meta("lit"), "Goal %s goes out" % style)
		goal.set_lit(true, true)
		_check(not goal.moving(), "Goal %s lit at once (a seek) stays still" % style)

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
## Arrivals (Motion.arrival through piece.gd): a crossing gate thudding shut
## runs past its stop and settles back to exactly where a snap puts it, and
## with reduced motion it never passes its stop; a raft, a lift and a pressed
## pad do the same, each resting exactly as before.
func _check_arrivals(holder: Node3D) -> void:
	var crossing := {"id": "gate", "rect_cm": [0, 0, 120, 60], "height_cm": 40}
	for reduced: bool in [false, true]:
		var gate: RefCounted = BridgeKit.build(crossing, holder)
		gate.reduced_motion = reduced
		gate.set_open(true, true)
		var open := _pose(gate.root)
		var snapped: RefCounted = BridgeKit.build(crossing, holder)
		snapped.set_open(false, true)
		gate.set_open(false)
		var rest: float = snapped.root.position.y
		var lowest := INF
		var frames := 0
		while gate.moving() and frames < 600:
			gate.advance(1.0 / 60.0)
			lowest = minf(lowest, gate.root.position.y)
			frames += 1
		var past := rest - lowest
		var settled: bool = frames < 600 and not gate.moving() and gate.root.position.y == rest and _pose(gate.root) == _pose(snapped.root)
		if reduced: _check(settled and past <= 0.0, "With reduced motion a shutting gate stops at its rest and never passes it (%.4f)" % past)
		else: _check(settled and past > 0.5 * BridgeKit.OVER and past < 2.0 * BridgeKit.OVER, "A shutting gate thuds past its rest (%.4f m) and settles exactly where a snap puts it" % past)
		gate.set_open(true, true)
		_check(_pose(gate.root) == open and not gate.moving(), "An immediate open puts the gate back as it was")
		gate.root.free()
		snapped.root.free()
	var stops: Array[Vector3] = [Vector3(0, 0.3, 0), Vector3(1.5, 0.3, 0)]
	var raft: RefCounted = Raft.build("logs", stops, Vector2(0.8, 0.8), holder)
	raft.set_value(1)
	var furthest := 0.0
	for frame in range(120 + SETTLE_FRAMES):
		raft.advance(1.0 / 60.0)
		furthest = maxf(furthest, raft.root.position.x)
	_check(not raft.moving() and raft.root.position == stops[1] and furthest > stops[1].x, "A raft drifts past its stop (%.3f) and rests exactly on it" % furthest)
	var lift: RefCounted = Lift.build("plain", Rect2(0, 0, 1, 1), 0.0, 1.0, holder)
	lift.set_height(1.0)
	lift.arrive(1.0)
	var highest := 0.0
	while lift.moving():
		lift.advance(1.0 / 60.0)
		highest = maxf(highest, lift.root.position.y)
	_check(lift.root.position.y == 1.0 and highest > 1.0 and highest - 1.0 <= 1.5 * Lift.OVER, "A lift bobs a little past its stop (%.4f) and rests exactly on it" % highest)
	for style: String in Pad.STYLES:
		var pad: RefCounted = Pad.build(style, AT, 0.3, holder)
		var still: RefCounted = Pad.build(style, AT, 0.3, holder)
		still.set_held(true, true)
		pad.set_held(true)
		var dipped := 0.0
		var rest: float = pad._dish.position.y
		while pad.moving():
			pad.advance(1.0 / 60.0)
			dipped = minf(dipped, pad._dish.position.y - rest)
		_check(dipped < -0.5 * Pad.DIP and _pose(pad.root) == _pose(still.root), "A pressed %s pad dips (%.4f) and springs back to exactly its held place" % [style, dipped])
		pad.set_held(false)
		pad.set_held(true, true)
		_check(not pad.moving(), "A %s pad held at once never dips" % style)

## A held crossing's deck is pulled taut (kit/pieces/taut_bridge.gd), along
## either axis: shut, it hangs slack, its middle plank its slack() under the
## banks and level, the planks toward the ends higher and tilted to the curve,
## and its long rail drawn as bent lengths along it; opening, the sag eases out
## over SECONDS, bows up a little past level and settles, after which every
## part stands exactly as laid and the rail is whole again; shutting sags it
## back; a part laid later is found; an immediate call or reduce motion snaps.
func _check_taut(holder: Node3D) -> void:
	for across_x: bool in [true, false]:
		var deck := Node3D.new()
		deck.position = Vector3(2.0, 0.0, -1.0)
		holder.add_child(deck)
		var planks: Array[MeshInstance3D] = []
		for index in range(8):
			var along := -0.875 + 0.25 * float(index)
			planks.append(Parts.box(Vector3(0.24, 0.1, 1.0) if across_x else Vector3(1.0, 0.1, 0.24), Parts.TIMBER, Vector3(along, -0.05, 0.0) if across_x else Vector3(0.0, -0.05, along), deck))
		var rail := Parts.box(Vector3(2.0, 0.03, 0.03) if across_x else Vector3(0.03, 0.03, 2.0), Parts.CREAM, Vector3(0.0, 0.5, 0.45) if across_x else Vector3(0.45, 0.5, 0.0), deck)
		var rests: Array = planks.map(func(plank: MeshInstance3D) -> Transform3D: return plank.transform)
		var piece: RefCounted = TautBridge.build(deck, across_x, -1.0, 1.0)
		var where := "along x" if across_x else "along z"
		var middle: MeshInstance3D = planks[4]
		var end: MeshInstance3D = planks[0]
		var lengths: Array = (piece.root as Node3D).get_children()
		var lowest := func() -> float: return lengths.map(func(length: Node3D) -> float: return length.position.y).min()
		piece.set_open(false, true)
		var tilt: float = absf(end.basis.get_euler().z if across_x else end.basis.get_euler().x)
		_check(deck.visible and absf(middle.position.y - (-0.05 - piece.slack() * 0.984375)) < 0.01 and end.position.y > middle.position.y + 0.2 and tilt > 0.2 and absf(middle.basis.get_euler().length()) < 0.3, "Shut %s: the deck hangs slack, its middle under the banks (%.2f m) and its end planks higher and tilted to the curve" % [where, middle.position.y])
		_check(not rail.visible and lengths.size() == TautBridge.BENDS and lengths.all(func(length: Node3D) -> bool: return length.visible) and lowest.call() < 0.5 - piece.slack() * 0.8, "Shut %s: its rail bends along the curve in short lengths" % where)
		piece.set_open(true)
		var frames := 0
		var halfway := false
		var bowed := false
		while piece.moving() and frames < 600:
			piece.advance(1.0 / 60.0)
			frames += 1
			if frames == int(TautBridge.SECONDS * 30.0): halfway = middle.position.y < -0.1 and middle.position.y > -0.05 - piece.slack() + 0.05
			if middle.position.y > -0.05 + 0.005: bowed = true
		var laid := range(8).all(func(index: int) -> bool: return planks[index].transform == rests[index])
		_check(halfway and bowed and absf(frames - (TautBridge.SECONDS + Motion.ARRIVAL_SECONDS) * 60.0) <= 2.0, "Opening %s: the sag eases out over %.1f s and the deck bows past level and settles (%d frames)" % [where, TautBridge.SECONDS, frames])
		_check(laid and rail.visible and lengths.all(func(length: Node3D) -> bool: return not length.visible), "Open %s: every part stands exactly as laid and the rail is whole" % where)
		piece.set_open(false)
		piece.advance(TautBridge.SECONDS * 0.5)
		_check(piece.moving() and middle.position.y < -0.1 and not rail.visible, "Shutting %s: the deck sags back down" % where)
		piece.set_open(true, true)
		var rope := Parts.box(Vector3(2.0, 0.02, 0.02) if across_x else Vector3(0.02, 0.02, 2.0), Parts.CREAM, Vector3(0.0, 0.5, -0.45) if across_x else Vector3(-0.45, 0.5, 0.0), deck)
		piece.set_open(false, true)
		_check(not rope.visible and (piece.root as Node3D).get_child_count() > lengths.size(), "A rope laid on the deck %s later bends with it too" % where)
		piece.reduced_motion = true
		piece.set_open(true)
		_check(not piece.moving() and range(8).all(func(index: int) -> bool: return planks[index].transform == rests[index]), "With reduce motion %s, the deck is pulled taut at once" % where)
		deck.free()

## A closing crossing (kit/closing_warning.gd) fades whole, every mesh the
## world's closing_parts() names: solid as its warning starts and as it shuts,
## out to FADED and back every BLINK * 2 ticks, a steady STEADY under Reduce
## motion, and every mesh back to its own transparency once it is held again.
func _check_closing_fade(holder: Node3D) -> void:
	var host := GDScript.new()
	host.source_code = "extends Node3D
var reduced_motion := false
var parts: Array = []
func closing_parts(_id: String) -> Array:
	return parts
"
	host.reload()
	var world := Node3D.new()
	world.set_script(host)
	holder.add_child(world)
	var deck := Node3D.new()
	world.add_child(deck)
	var plank := Parts.box(Vector3.ONE * 0.2, Parts.TIMBER, Vector3.ZERO, deck)
	var rope := Parts.box(Vector3.ONE * 0.1, Parts.CREAM, Vector3.UP, deck)
	rope.transparency = 0.3
	world.set("parts", [deck])
	var warning: RefCounted = ClosingWarning.new(world)
	var seen: Array = []
	for ticks: int in [25, 24, 23, 22, 21, 20, 15, 10, 5, 1, 0]:
		warning.show({"bar": ticks})
		seen.append(plank.transparency)
	_check(seen[0] == 0.0 and seen[1] > 0.0 and is_equal_approx(seen[6], ClosingWarning.FADED) and is_zero_approx(seen[7]) and is_equal_approx(seen[8], ClosingWarning.FADED) and is_zero_approx(seen[10]), "A closing crossing fades from solid, out to %.1f and back each blink, and is solid as it shuts (%s)" % [ClosingWarning.FADED, seen])
	_check(rope.transparency >= 0.3, "A mesh already see-through never comes back more solid while its crossing warns")
	warning.show({})
	_check(plank.transparency == 0.0 and is_equal_approx(rope.transparency, 0.3), "Held again, every mesh goes back to its own transparency")
	world.set("reduced_motion", true)
	warning.show({"bar": 15})
	var steady := plank.transparency
	warning.show({"bar": 10})
	_check(steady == ClosingWarning.STEADY and plank.transparency == ClosingWarning.STEADY, "Under Reduce motion a closing crossing holds a steady half fade")
	world.free()

## Every goal stands two pads, one per pip in its colour, wholly inside the
## goal. One pip at the goal presses only its own pad and nothing rings; with
## both there both press, and the goal lights and its bell rings once, as
## the stage is done.
func _check_goal_pads(holder: Node3D) -> void:
	for style: String in Styles.SLOTS.goal:
		var goal: RefCounted = Goal.build(style, Vector3.ZERO, 0.48, holder)
		_check(goal.pads.size() == 2 and goal.moving_parts().has(goal.pads.p0.rim), "Goal %s stands two pads and keeps them moving" % style)
		for slot: String in Goal.PAD_SLOTS:
			var pad: RefCounted = goal.pads[slot]
			# The two halves tile one plate a pad board the goal's size, west then east.
			var west := -1.0 if slot == "p0" else 1.0
			var tiles: bool = pad.half_size.is_equal_approx(Goal.pad_half(0.48, style)) and (style == "planter" or is_equal_approx(pad.half_size.y, Pad.board_half(0.48))) and is_equal_approx(pad.at.x, west * pad.half_size.x) and is_zero_approx(pad.at.z)
			_check(tiles and (pad.rim.material_override as StandardMaterial3D).albedo_color == Parts.owner_color(slot), "Goal %s's %s half is its own half of the plate in its pip's colour" % [style, slot])
			_check(Vector2(pad.half_size.x * 2.0, pad.half_size.y).length() <= Goal.base_radius(0.48, style) and Goal.drawn_radius(style, 0.48) >= Goal.outer_radius(style, 0.48), "Goal %s's plate lies on its disc (a planter's soil), inside what it draws" % style)
			_check(pad.at.y + Pad.BOARD_TOP - Pad.BOARD_SINK - Pad.DIP * 1.05 > float(Goal.DISC_TOPS[style]), "Goal %s's %s pad, pressed, stays above the goal's disc" % [style, slot])
			_check(PadChecks.outline_fits(pad), "Goal %s's %s half draws its own square-cornered outline" % [style, slot])
	_check(PadChecks.outline_fits(Pad.build("board", AT, 0.06, holder)) and PadChecks.outline_fits(Pad.build("board", AT, 0.4, holder, {"size": Vector2(0.3, 0.6)})), "A small board and a long one draw their outlines inside their edges")
	var goal: RefCounted = Goal.build("bell", Vector3.ZERO, 0.48, holder)
	var on_pad := func(slot: String) -> Dictionary:
		var at: Vector3 = goal.pads[slot].at * 100.0
		return {"x": at.x, "z": at.z, "height": 0}
	var away := {"x": 400, "z": 0, "height": 0}
	var rang := 0
	var one := {"players": {"p0": on_pad.call("p0"), "p1": away}, "objective_done": false, "complete": false}
	var both := {"players": {"p0": on_pad.call("p0"), "p1": on_pad.call("p1")}, "objective_done": true, "complete": true}
	for index in range(5):
		var state: Dictionary = one if index < 2 else both
		var was: bool = goal.chime.swing.get_meta("rung", false)
		goal.set_lit(Goal.lit(state))
		goal.present_pips(state.players)
		if goal.chime.swing.get_meta("rung", false) and not was: rang += 1
		if index < 2: _check(goal.pads.p0.held() and not goal.pads.p1.held() and not goal.chime.swing.get_meta("rung", false) and is_zero_approx(goal.light.light_energy), "One pip at the goal presses its own pad and nothing rings")
	_check(goal.pads.p0.held() and goal.pads.p1.held() and rang == 1, "Both pips at the goal press both pads and the bell rings once (%d)" % rang)
	_check(not Goal.lit({"objective_done": true, "complete": false}), "Both there before the stage is done: the goal waits to light")
	# What else the goal waits for: a token per need, dim until it is met.
	var needy: RefCounted = Goal.build("bell", Vector3.ZERO, 0.48, holder)
	needy.add_needs({"goal_policy": {"kind": "ring", "when": {"all": [{"item_id": "pipsport", "carried": true}, {"lever_id": "lamp"}]}}}, func(_id: String) -> String: return "pipsport")
	_check(needy.needs.needs.size() == 2 and Goal.GoalNeeds.icon({"item_id": "x"}) == "item" and Goal.GoalNeeds.icon({"lever_id": "x"}) == "lamp" and Goal.GoalNeeds.icon({"teapot": 1}) == Goal.GoalNeeds.DEFAULT_ICON, "A goal stands a token per need, each kind with its icon and a new kind with the default")
	var waiting := {"players": {}, "mechanisms": {"items": {"pipsport": {"holder": "", "spot": "post"}}, "levers": {"lamp": false}, "controls": {}}}
	needy.needs.present(waiting)
	var dim: bool = needy.needs.needs.all(func(need: Dictionary) -> bool: return not (need.disc.material_override as StandardMaterial3D).emission_enabled)
	_check(dim and not needy.needs.all_met(), "An unmet need's token stands dim")
	var met := {"players": {}, "mechanisms": {"items": {"pipsport": {"holder": "p1", "spot": ""}}, "levers": {"lamp": true}, "controls": {}}}
	needy.needs.present(met)
	var bright: bool = needy.needs.needs.all(func(need: Dictionary) -> bool: return (need.disc.material_override as StandardMaterial3D).emission_enabled)
	_check(bright and needy.needs.all_met() and needy.moving_parts().has(needy.needs.needs[0].disc), "Meeting a need lights its token")
	var finished := {"players": {"p0": on_pad.call("p0"), "p1": on_pad.call("p1")}, "objective_done": true, "complete": true}
	needy.present_pips(finished.players)
	needy.set_lit(Goal.lit(finished))
	_check(needy.pads.p0.held() and needy.pads.p1.held() and needy.needs.all_met() and needy.light.light_energy > 0.0, "Both pads pressed and every need lit: the goal lights as the stage is done")
	var on_other := {"players": {"p0": on_pad.call("p1"), "p1": away}}
	goal.present_pips(on_other.players, true)
	_check(not goal.pads.p0.held() and not goal.pads.p1.held(), "A pip on its friend's pad presses neither")
	_check_goal_missing(holder)

## While a pip stands on the goal's plate and the goal is not lit, what is
## still missing (the empty half, an unmet need's token) blinks red on the
## closing warning's beat, steady under Reduce motion; done or nobody on the
## plate, no red.
func _check_goal_missing(holder: Node3D) -> void:
	var goal: RefCounted = Goal.build("crest", Vector3.ZERO, 0.28, holder)
	goal.add_needs({"goal_policy": {"kind": "ring", "when": {"item_id": "pipsport", "carried": true}}}, func(_id: String) -> String: return "pipsport")
	var token: MeshInstance3D = goal.needs.needs[0].disc
	var red := func(node: MeshInstance3D) -> float:
		var look := node.material_override as StandardMaterial3D
		return look.emission_energy_multiplier if look.emission_enabled and look.emission == Parts.MISSING else 0.0
	var at := func(slot: String) -> Dictionary:
		var spot: Vector3 = goal.pads[slot].at * 100.0
		return {"x": spot.x + 3.0, "z": spot.z - 20.0, "height": 0}
	var away := {"x": 400, "z": 0, "height": 0}
	var waiting := {"items": {"pipsport": {"holder": "", "spot": "post"}}, "levers": {}, "controls": {}}
	var alone := {"tick": 0, "players": {"p0": at.call("p0"), "p1": away}, "mechanisms": waiting}
	goal.set_lit(false)
	goal.present(alone, false, false)
	var lit: float = red.call(goal.pads.p1.rim)
	_check(goal.missing() and lit > 0.0 and red.call(token) == lit and red.call(goal.pads.p0.rim) == 0.0 and goal.pads.p0.held(), "One pip on its half: the empty half and the unmet token blink red, its own half lit")
	alone.tick = Goal.ClosingWarning.BLINK
	goal.present(alone, false, false)
	_check(red.call(goal.pads.p1.rim) > 0.0 and red.call(goal.pads.p1.rim) < lit and red.call(token) < lit, "They blink on the closing warning's beat")
	goal.present(alone, false, true)
	_check(is_equal_approx(red.call(goal.pads.p1.rim), Goal.MISSING_STEADY) and is_equal_approx(red.call(token), Goal.MISSING_STEADY), "Reduce motion holds the red steady")
	var both := {"tick": 0, "players": {"p0": at.call("p0"), "p1": at.call("p1")}, "mechanisms": waiting}
	goal.present(both, false, false)
	_check(red.call(goal.pads.p1.rim) == 0.0 and red.call(token) > 0.0, "Its pip there, a half stops blinking; the token still waits")
	var carried := {"tick": 0, "players": {"p0": at.call("p0"), "p1": at.call("p1")}, "mechanisms": {"items": {"pipsport": {"holder": "p1", "spot": ""}}, "levers": {}, "controls": {}}, "objective_done": true, "complete": true}
	goal.set_lit(Goal.lit(carried))
	goal.present(carried, false, false)
	_check(not goal.missing() and red.call(goal.pads.p0.rim) == 0.0 and red.call(goal.pads.p1.rim) == 0.0 and red.call(token) == 0.0 and goal.needs.all_met(), "All done: nothing blinks red")
	goal.set_lit(false)
	goal.present({"tick": 0, "players": {"p0": away, "p1": away}, "mechanisms": waiting}, false, false)
	_check(not goal.missing() and red.call(goal.pads.p1.rim) == 0.0 and red.call(token) == 0.0, "Nobody on the plate: no red")
	# The token stands big on the plate's middle line at its front edge, clear of
	# where a pip stands in the middle of its half.
	var spot: Vector3 = token.position
	var clear := Vector2(spot.x - goal.pads.p0.at.x, spot.z).length() >= Goal.GoalNeeds.TOKEN + 0.12
	_check(Goal.GoalNeeds.TOKEN >= 0.1 and is_zero_approx(spot.x) and is_equal_approx(spot.z, Goal.plate_half(0.28)) and clear and Goal.drawn_radius("crest", 0.28, 2) >= Goal.GoalNeeds.reach(Goal.plate_half(0.28), 2), "The need token stands big at the plate's front edge, clear of the pips' spots")

func _pose(node: Node3D) -> Array:
	var pose: Array = []
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = (mesh as MeshInstance3D).global_transform
		for v: Vector3 in [t.basis.x, t.basis.y, t.basis.z, t.origin]: pose.append(Vector3i((v * 10000.0).round()))
	return pose

## Every swing style stands on its pivot with its jib turned to the lane, hangs
## back off the lane between beats (and while held), sweeps across and back
## within its beat, follows the snapshot's phase without running ahead of it,
## and snaps on an immediate call. The winch spot and the winch handle build.
func _check_swings(holder: Node3D) -> void:
	var swing := {"id": "crane", "pivot_cm": [200, 40], "lane": {"surface_id": "plank", "rect_cm": [150, 188, 250, 252]},
		"period_ticks": 90, "sweep_ticks": 30, "warn_ticks": 30, "offset_ticks": 0, "outcome": "drowned"}
	for style: String in Styles.SLOTS.swing:
		var piece: RefCounted = Swing.build(style, swing, 0.0, 0.0, holder)
		_check(piece.style == style and piece.root.get_parent() == holder and piece.root.position.is_equal_approx(Vector3(2.0, 0, 0.4)) and is_zero_approx(piece.root.rotation.y), "Swing %s stands on its pivot, its jib toward the lane" % style)
		_check(piece.moving_parts().has(piece.hanger) and piece.moving_parts().has(piece.shadow) and _meshes(piece.root) > 0, "Swing %s keeps its bucket and shadow moving" % style)
		var rest: Vector2 = piece.pose(0.0)
		_check(rest.x < 0.0 and is_zero_approx(rest.y), "Swing %s hangs back, its shadow off the lane, between beats" % style)
		_check(piece.pose(59.0).x < rest.x and piece.pose(59.0).y > 0.9, "Swing %s is drawn further back, its shadow grown, at the end of the warning" % style)
		_check(piece.pose(75.0).x > 0.5 and is_equal_approx(piece.pose(89.999).x, rest.x), "Swing %s sweeps out across the lane and back to hang back" % style)
		piece.set_beat({"phase": 10, "held": false}, true)
		for frame in range(60): piece.advance(1.0 / 60.0)
		_check(is_equal_approx(piece._shown, 10.0 + Swing.LEAD) and not piece.moving(), "Swing %s runs on at most LEAD ticks past the last snapshot" % style)
		piece.set_beat({"phase": 12, "held": false})
		_check(is_equal_approx(piece._shown, 11.5), "A nearby snapshot does not snap it")
		piece.set_beat({"phase": 40, "held": true})
		_check(is_equal_approx(piece._shown, 40.0), "A snapshot far off snaps it")
		piece.set_beat({"phase": 5, "held": true}, true)
		for frame in range(30): piece.advance(1.0 / 60.0)
		_check(is_equal_approx(piece._shown, 5.0) and not piece.moving(), "Held, it stays parked")
	_check(Swing.build("teapot", swing, 0.0, 0.0, holder).style == Swing.STYLES[0], "An unknown swing style builds the first")
	var spot := Node3D.new()
	holder.add_child(spot)
	Socket.item_spot("winch", spot, {"radius_cm": 30})
	_check(_meshes(spot) > 0 and is_equal_approx(Socket.rest_height("winch"), Socket.WINCH_AXLE), "The winch spot builds, its handle resting at the socket")
	var handle: RefCounted = CarriedItem.build("winch_handle", AT, holder, {"id": "handle"})
	_check(handle.style == "winch_handle" and _meshes(handle.root) > 0 and handle.radius > 0.1, "The winch handle builds")
