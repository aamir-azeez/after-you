extends SceneTree
## Every speech bubble (presentation/kit/label_bubble.gd) in every chapter keeps
## its tail's tip on its anchor, on the fixed journey view plane: settled,
## raised or slid aside clear of a spirit by the journey placement and any
## world's own climbing, lifted by hand, and bobbing. The tip is rebuilt from
## what the body shader is given (the body's place, its scale code, its
## per-instance tail stretch and the material's tail), so a move that carries
## the tail away fails here. No tail grows past the kit's cap, and every
## selector's tail lands on the top of its own lever's knob, at every value,
## however the lever tilts.
##
## No tail is ever seen across a spirit. With a spirit on, behind and beside
## each control (on the control's own floor), every drawn tail triangle is
## tested against every spirit's head and torso, projected on the view plane
## (spheres as spirit_visual.gd builds them, so circles). Where they meet:
##   - a spirit standing no further than HIDES behind the tail's card hides
##     the tail there: this is asserted as the occlusion setup (the body is
##     depth tested, its tail is drawn on its anchor's upright card: the sink
##     and slope the shader gets match the anchor's real depth), not by pixels;
##   - otherwise the tail must not cross the spirit at all, except that where
##     the control itself lies over the spirit on screen, the tail's last
##     NEAR_TIP may run over it to reach the control.
## Each chapter world is built once and steps through its stages.
const Registry = preload("res://services/chapter_registry.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const JourneySimulation = preload("res://core/journey/simulation.gd")
## How far a drawn tip may sit from its anchor on the view plane (metres).
const EPSILON := 0.003
const DELTA := 1.0 / 60.0
## Where a spirit stands against a control (from a lever's foot or a pad's
## centre): on it, behind it (higher on screen), and behind to either side.
const SPOTS: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, -0.6), Vector3(0.45, 0, -0.35), Vector3(-0.45, 0, -0.35)]
## A spirit's head and torso (spirit_visual.gd): centre height over its feet
## and radius, metres.
const HEAD_AT := 0.57
const HEAD_RADIUS := 0.34
const TORSO_AT := 0.24
const TORSO_RADIUS := 0.29
## Where a control lies over a spirit on screen, how much of the tail next
## to its tip may run over the spirit (metres).
const NEAR_TIP := 0.4
## A spirit this close behind a tail's card (or in front of it) hides the
## tail where they meet: its head and torso are far deeper than this.
const HIDES := 0.12
## The journey view (presentation/kit/label_bubble.gd VIEW).
const VIEW := Vector3(3, 13, 10)
var checks := 0
var failures := 0
var _lifted := 0
var _leaned := 0
var _staged := 0
var _met := 0
var _hidden := 0
var _highest := 0.0
var _longest := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var built := 0
	for key: String in Registry.keys():
		if not _uses_bubbles(Registry.world_script(key)): continue
		if not _check(Registry.is_journey(key), "%s uses LabelBubble; teach this suite to build its world" % key): continue
		_chapter(key)
		built += 1
	_check(built >= 4 and _staged >= 5 and _lifted > 0 and _leaned > 0, "Every chapter with bubbles is built, and spirits really raise and push aside some bubbles (%d chapters, %d stages with bubbles, %d lifted, %d leaning)" % [built, _staged, _lifted, _leaned])
	_check(_met > 0 and _hidden > 0, "Some tails really run behind a spirit at their control (%d tails met a spirit, %d hidden by it)" % [_met, _hidden])
	print("Highest lift %.2f m, longest tail %.2f m (cap %.2f m); %d tails met a spirit, %d hidden behind one" % [_highest, _longest, LabelBubble.MAX_TAIL, _met, _hidden])
	print("LABEL BUBBLE TAILS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A world uses the bubble when its script, or any script it extends, names it.
static func _uses_bubbles(script: Script) -> bool:
	while script != null:
		if "label_bubble.gd" in script.source_code: return true
		script = script.get_base_script()
	return false

func _chapter(key: String) -> void:
	var level := Registry.definition(key)
	var checkpoint := Registry.initial_checkpoint(key)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	for stage: Dictionary in level.stages:
		var label := "%s %s" % [key, stage.id]
		world.show_stage(stage)
		world.present_history(checkpoint)
		var sim := JourneySimulation.new()
		var pinned := JourneySimulation.pinned_rules(level)
		if pinned > 0: sim.simulation_version = pinned
		sim._reset_trusted(level, str(stage.id), checkpoint, {}, "a")
		var state: Dictionary = sim.snapshot()
		world.present(state, true)
		_frames(world, 2)
		var bubbles := _bubbles_in(world)
		# Some stages (the conservatory's) name nothing.
		if bubbles.is_empty(): continue
		_staged += 1
		for bubble: LabelBubble in bubbles:
			_check(world._bubbles.has(bubble), "%s: %s takes part in the journey placement" % [label, _name(bubble)])
		_tips(bubbles, label + ", settled")
		_faces(world, bubbles, label + ", settled")
		_bob_on_world_clock(world, bubbles, label)
		_knobs(world, state, bubbles, label)
		# Spirits at every bubble's control: the journey placement (and Tide's
		# scenery climbing) raises bubbles or slides them aside; their tails stay
		# on their controls and are never seen across a spirit.
		var slot := str(state.active_slot)
		for bubble: LabelBubble in bubbles:
			var base := _foot(world, bubble)
			var floor_height: float = world._control_base_height({"position_cm": [int(roundf(base.x * 100.0)), int(roundf(base.z * 100.0))]})
			for spot: Vector3 in SPOTS:
				var at := base + spot
				var near: Dictionary = state.duplicate()
				near.players = state.players.duplicate(true)
				var player: Dictionary = near.players[slot]
				player.x = int(roundf(at.x * 100.0))
				player.z = int(roundf(at.z * 100.0))
				var height: float = world._control_base_height({"position_cm": [player.x, player.z]})
				# Only where a spirit can stand: the control's own floor.
				if absf(height - floor_height) > 0.05: continue
				player.height = int(roundf(height * 100.0))
				world.present(near, true)
				_frames(world, 2)
				for other: LabelBubble in bubbles:
					if other.lift > 0.0: _lifted += 1
					if absf(float(other.get("lean") if other.get("lean") != null else 0.0)) > 0.0: _leaned += 1
					_check(other.lift < other.max_lift() - 0.001, "%s: the cap leaves room for the %s bubble's lift over a spirit at %s (%.2f m)" % [label, _name(other), _name(bubble), other.lift])
					_highest = maxf(_highest, other.lift)
				var where := "%s, a spirit at %s %s" % [label, _name(bubble), spot]
				_tips(bubbles, where)
				_faces(world, bubbles, where)
		world.present(state, true)
		_frames(world, 2)
		# Lifted by hand, a little and far too far: the tip never leaves.
		for bubble: LabelBubble in bubbles:
			for metres: float in [0.37, 1.0, 40.0]:
				bubble.set_lift(metres)
				_check(bubble.lift <= metres + 0.0001 and (metres > 1.0 or is_equal_approx(bubble.lift, metres)), "%s: %s takes a lift of %.2f m, capped only past the longest tail (got %.2f)" % [label, _name(bubble), metres, bubble.lift])
				_tips([bubble], "%s, lifted %.2f m" % [label, metres])
			# Bobbing, at uneven frame times: the body bobs, the tip stays.
			bubble.set_lift(0.5)
			bubble.set_bob(true)
			for step: float in [0.013, 0.29, 0.61, 1.7, DELTA]:
				bubble.advance_bob(step)
				bubble._process(step)
				_tips([bubble], "%s, bobbing" % label)
			bubble.set_bob(false)
			bubble.set_lift(0.0)
			_tips([bubble], "%s, settled again" % label)
	viewport.free()

## Journey bubbles bob from the world's own frame: within BOB_HEIGHT of where
## they stand, tips on their anchors; a held world holds them still; Reduce
## motion settles them onto their lift, and turning it off brings the bob back.
## This suite's worlds run under Reduce motion (still bubbles place alike);
## here motion is on, and Reduce motion is back on at the end.
func _bob_on_world_clock(world: Node3D, bubbles: Array, label: String) -> void:
	for bubble: LabelBubble in bubbles:
		_check(not bubble.is_bobbing(), "%s: %s holds still under Reduce motion" % [label, _name(bubble)])
	world.reduced_motion = false
	_frames(world, 1)
	for bubble: LabelBubble in bubbles:
		_check(bubble.is_bobbing(), "%s: %s bobs in a journey world" % [label, _name(bubble)])
	var moved := false
	var bounded := true
	for _frame in range(24):
		_frames(world, 1)
		for bubble: LabelBubble in bubbles:
			var off := bubble.position - _settled(bubble)
			bounded = bounded and absf(off.y) <= LabelBubble.BOB_HEIGHT + 0.000001 and Vector2(off.x, off.z).length() < 0.000001
			moved = moved or absf(off.y) > 0.002
	_check(moved and bounded, "%s: bubbles bob on the world clock, within %.3f m" % [label, LabelBubble.BOB_HEIGHT])
	_tips(bubbles, label + ", bobbing with the world")
	world.set_process(false)
	var held: Array = []
	for bubble: LabelBubble in bubbles: held.append(bubble.position)
	_frames(world, 6)
	var still := true
	for index in range(bubbles.size()): still = still and (bubbles[index] as LabelBubble).position == held[index]
	_check(still, "%s: a held world holds its bubbles still" % label)
	# Reduce motion turned on over a card (the world held, its spirits on
	# advance_idle) settles the bubbles too.
	world.reduced_motion = true
	_check(world.advance_idle(0.2), "%s: a card frame moves its spirits" % label)
	var carded := true
	for bubble: LabelBubble in bubbles: carded = carded and not bubble.is_bobbing() and bubble.position.is_equal_approx(_settled(bubble))
	_check(carded, "%s: Reduce motion settles the bubbles over a card" % label)
	world.set_process(true)
	_frames(world, 1)
	var settled := true
	for bubble: LabelBubble in bubbles: settled = settled and not bubble.is_bobbing() and bubble.position.is_equal_approx(_settled(bubble))
	_check(settled, "%s: Reduce motion settles every bubble onto its lift" % label)
	_tips(bubbles, label + ", settled by Reduce motion")
	world.reduced_motion = false
	_frames(world, 1)
	var back := true
	for bubble: LabelBubble in bubbles: back = back and bubble.is_bobbing()
	_check(back, "%s: the bob comes back with motion" % label)
	world.reduced_motion = true
	_frames(world, 1)

func _settled(bubble: LabelBubble) -> Vector3:
	return bubble._right * bubble.lean + Vector3(0, bubble.lift, 0)

## Where a spirit stands to work a bubble's control: a lever's foot, or the
## anchor itself (a pad's centre).
func _foot(world: Node3D, bubble: LabelBubble) -> Vector3:
	for id: String in world._journey_switches:
		if world._journey_switches[id].bubble == bubble:
			var pivot: Node3D = world._physical_levers[id]
			return Vector3(pivot.position.x, 0, pivot.position.z)
	return bubble.anchor

## Every selector's tail lands on its own lever's knob, on its top, at every
## value the lever tilts to: the knob found as the lever's sphere.
func _knobs(world: Node3D, state: Dictionary, bubbles: Array, label: String) -> void:
	for id: String in world._journey_switches:
		var bubble: LabelBubble = world._journey_switches[id].bubble
		for value: String in world._journey_switches[id].values:
			var turned: Dictionary = state.duplicate()
			turned.controls = state.get("controls", {}).duplicate()
			turned.controls[id] = value
			world.present(turned, true)
			_frames(world, 2)
			var knob := _knob(world._physical_levers[id])
			if not _check(knob != null, "%s: the %s lever has a knob" % [label, id]): continue
			var top: Vector3 = world.terrain.to_local(knob.global_position) + Vector3(0, (knob.mesh as SphereMesh).radius * knob.global_basis.y.length(), 0)
			_check(bubble.anchor.distance_to(top) < 0.001, "%s: the %s tail lands on the top of its lever's knob at %s (anchor %s, knob top %s)" % [label, id, value, bubble.anchor, top])
			_tips(bubbles, "%s, %s at %s" % [label, id, value])
	world.present(state, true)
	_frames(world, 2)

func _knob(lever: Node3D) -> MeshInstance3D:
	for child: Node in lever.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh: return child
	return null

## Each bubble's drawn tip against its anchor, both on the view plane.
func _tips(bubbles: Array, label: String) -> void:
	for bubble: LabelBubble in bubbles:
		var target := LabelBubble.plane_point((bubble.get_parent() as Node3D).to_global(bubble.anchor))
		var drawn := _drawn_tip(bubble)
		var length := _tail_length(bubble)
		_longest = maxf(_longest, length)
		_check(drawn.distance_to(target) < EPSILON, "%s: the %s tail's tip lands on its anchor (lift %.2f, off by %.4f m)" % [label, _name(bubble), bubble.lift, drawn.distance_to(target)])
		_check(bubble.plane_tail().distance_to(drawn) < EPSILON, "%s: plane_tail reports the drawn tip of %s" % [label, _name(bubble)])
		_check(length <= LabelBubble.MAX_TAIL + 0.0001, "%s: the %s tail stays under the cap (%.2f m)" % [label, _name(bubble), length])
		var span := bubble.plane_span()
		_check(span.encloses(bubble.plane_rect()) and span.grow(0.0005).has_point(drawn), "%s: the %s span holds its body and its whole tail" % [label, _name(bubble)])

## No drawn tail is seen across a spirit's head or torso (see the top).
func _faces(world: Node3D, bubbles: Array, label: String) -> void:
	for bubble: LabelBubble in bubbles:
		var anchor := (bubble.get_parent() as Node3D).to_global(bubble.anchor)
		var tail := _drawn_triangle(bubble)
		var card := _on_card(bubble, anchor)
		_check(card, "%s: the %s tail is drawn on its anchor's card, depth tested, so a spirit at the control hides it" % [label, _name(bubble)])
		for slot: String in world.actors:
			var actor: Node3D = world.actors[slot]
			if not actor.is_visible_in_tree(): continue
			var feet := actor.global_position
			var head := LabelBubble.plane_point(feet + Vector3(0, HEAD_AT, 0))
			var torso := LabelBubble.plane_point(feet + Vector3(0, TORSO_AT, 0))
			var across_head := _meets_circle(tail, head, HEAD_RADIUS)
			var across_torso := _meets_circle(tail, torso, TORSO_RADIUS)
			if not across_head and not across_torso: continue
			_met += 1
			var behind := _behind_card(feet, anchor)
			if behind <= HIDES and card:
				_hidden += 1
				continue
			var tip: Vector2 = tail[2]
			var under := tip.distance_to(head) < HEAD_RADIUS or tip.distance_to(torso) < TORSO_RADIUS
			var worst := _farthest_over(tail, head, torso)
			var where := "%s: the %s tail (lift %.2f, lean %.2f)" % [label, _name(bubble), bubble.lift, float(bubble.get("lean") if bubble.get("lean") != null else 0.0)]
			_check(under and worst <= NEAR_TIP, "%s is seen across %s, %.2f m from its tip (%s; %.2f m behind its card)" % [where, slot, worst, "its control lies over the spirit" if under else "its control is clear of the spirit", behind])

## The occlusion setup: the body is depth tested and its tail is drawn on the
## upright card through its anchor (the tip's sink is the anchor's real depth
## behind the body, and the slope up the card is the journey view's).
func _on_card(bubble: LabelBubble, anchor: Vector3) -> bool:
	var material := bubble.body.material_override as ShaderMaterial
	var names: Dictionary = (LabelBubble as Script).get_script_constant_map()
	if material == null or not names.has("SINK") or "depth_test_disabled" in material.shader.code or not "tail_sink" in material.shader.code: return false
	var sink: Variant = bubble.body.get_instance_shader_parameter(names.SINK)
	var slope: Variant = material.get_shader_parameter("card_slope")
	var forward := -VIEW.normalized()
	var up := forward.cross(Vector3.UP).normalized().cross(forward).normalized()
	var mesh := bubble.body.mesh as QuadMesh
	return sink != null and slope != null and mesh != null and mesh.subdivide_depth == 2 and absf(float(sink) - (anchor - bubble.body.global_position).dot(forward)) < 0.002 and absf(float(slope) + forward.y / up.y) < 0.0001

## How far a point stands behind the upright card through anchor (world up and
## screen right), along the view, where both meet on screen.
static func _behind_card(point: Vector3, anchor: Vector3) -> float:
	var forward := -VIEW.normalized()
	var across := Vector3(forward.x, 0, forward.z).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var normal := across - right * across.dot(right)
	return (point - anchor).dot(normal) / forward.dot(normal)

## The drawn tail on the view plane, as the body shader draws it: its root's
## two corners on the body's straight edge (under the tip, or at that edge's
## end), and its tip.
func _drawn_triangle(bubble: LabelBubble) -> Array[Vector2]:
	var body: MeshInstance3D = bubble.body
	var material := body.material_override as ShaderMaterial
	var tail := float(material.get_shader_parameter("tail"))
	var radius := float(material.get_shader_parameter("radius"))
	var basis := body.global_transform.basis
	var half := Vector2(basis.x.length(), basis.y.length() - tail) * 0.5
	var reach := maxf(half.x - minf(radius, half.y) - tail * 0.62, 0.0)
	var offset := basis.z.length() - float(material.get_shader_parameter("tail_code"))
	var root := LabelBubble.plane_point(body.global_position) + Vector2(clampf(offset, -reach, reach), half.y - 0.04)
	return [root - Vector2(tail * 0.62, 0), root + Vector2(tail * 0.62, 0), _drawn_tip(bubble)]

## How far from the tip the tail runs over the spirit's head or torso (the
## farthest of a fine sampling of the triangle; 0 when it never does).
static func _farthest_over(corners: Array[Vector2], head: Vector2, torso: Vector2) -> float:
	var farthest := 0.0
	for i in range(41):
		for j in range(41 - i):
			var u := float(i) / 40.0
			var v := float(j) / 40.0
			var point := corners[0] * u + corners[1] * v + corners[2] * (1.0 - u - v)
			if point.distance_to(head) < HEAD_RADIUS or point.distance_to(torso) < TORSO_RADIUS:
				farthest = maxf(farthest, point.distance_to(corners[2]))
	return farthest

## Whether the triangle and the circle overlap.
static func _meets_circle(corners: Array[Vector2], center: Vector2, radius: float) -> bool:
	var a := corners[0]
	var b := corners[1]
	var c := corners[2]
	var d1 := (b - a).cross(center - a)
	var d2 := (c - b).cross(center - b)
	var d3 := (a - c).cross(center - c)
	if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0): return true
	for pair: Array in [[a, b], [b, c], [c, a]]:
		var from: Vector2 = pair[0]
		var to: Vector2 = pair[1]
		var t := clampf((center - from).dot(to - from) / maxf((to - from).length_squared(), 0.000001), 0.0, 1.0)
		if (from + (to - from) * t).distance_to(center) < radius: return true
	return false

## The tip as the body shader draws it: the body's centre on the view plane,
## then sideways by its scale code and down by half the body, the tail and the
## stretch.
func _drawn_tip(bubble: LabelBubble) -> Vector2:
	var body: MeshInstance3D = bubble.body
	var material := body.material_override as ShaderMaterial
	var tail := float(material.get_shader_parameter("tail"))
	var code := float(material.get_shader_parameter("tail_code"))
	var basis := body.global_transform.basis
	var down := (basis.y.length() - tail) * 0.5 + tail + _stretch(bubble)
	return LabelBubble.plane_point(body.global_position) + Vector2(basis.z.length() - code, down)

func _tail_length(bubble: LabelBubble) -> float:
	var material := bubble.body.material_override as ShaderMaterial
	return float(material.get_shader_parameter("tail")) + _stretch(bubble)

func _stretch(bubble: LabelBubble) -> float:
	var value: Variant = bubble.body.get_instance_shader_parameter(LabelBubble.STRETCH)
	return float(value) if value != null else 0.0

## Every bubble shown: a hidden one (a wait hint not saying anything) is
## neither drawn nor placed.
func _bubbles_in(node: Node) -> Array[LabelBubble]:
	var found: Array[LabelBubble] = []
	if node is LabelBubble and not node.is_queued_for_deletion() and (node as Node3D).visible: found.append(node)
	for child: Node in node.get_children(): found.append_array(_bubbles_in(child))
	return found

func _name(bubble: LabelBubble) -> String:
	return "/".join(bubble.labels.map(func(label: Label3D) -> String: return label.text))

## Engine frames, as the world fingerprint emulates them: _process(1/60) on
## each processing node in engine order.
func _frames(world: Node, count: int) -> void:
	for _frame in range(count):
		var found: Array = []
		_processing(world, found)
		var order: Array = []
		for index in range(found.size()): order.append([found[index].process_priority, index])
		order.sort()
		for item: Array in order:
			var node: Node = found[item[1]]
			if is_instance_valid(node) and not node.is_queued_for_deletion(): node._process(DELTA)

func _processing(node: Node, found: Array) -> void:
	if node.is_queued_for_deletion(): return
	if node.get_script() != null and node.has_method("_process") and node.is_processing() and node.can_process(): found.append(node)
	for child: Node in node.get_children(): _processing(child, found)

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value
