extends SceneTree
## Every speech bubble (presentation/kit/label_bubble.gd) in every chapter keeps
## its tail's tip on its anchor, on the fixed journey view plane: settled,
## raised clear of a spirit by the journey lift and any world's own climbing,
## lifted by hand, and bobbing. The tip is rebuilt from what the body shader is
## given (the body's place, its scale code, its per-instance tail stretch and
## the material's tail), so a lift that carries the tail away fails here. No
## tail grows past the kit's cap, and every selector's bubble points at its own
## lever's knob. Each chapter world is built once and steps through its stages.
const Registry = preload("res://services/chapter_registry.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const JourneySimulation = preload("res://core/journey/simulation.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
## How far a drawn tip may sit from its anchor on the view plane (metres).
const EPSILON := 0.003
const DELTA := 1.0 / 60.0
## Where a spirit stands relative to a bubble's anchor to push it up: on the
## control, behind it (higher on screen) and behind to one side.
const SPOTS: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, -0.6), Vector3(0.45, 0, -0.35)]
var checks := 0
var failures := 0
var _lifted := 0
var _staged := 0
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
	_check(built >= 4 and _staged >= 5 and _lifted > 0, "Every chapter with bubbles is built, and spirits really lift some bubbles (%d chapters, %d stages with bubbles, %d lifted)" % [built, _staged, _lifted])
	print("Highest lift %.2f m, longest tail %.2f m (cap %.2f m)" % [_highest, _longest, LabelBubble.MAX_TAIL])
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
			_check(world._bubbles.has(bubble), "%s: %s takes part in the journey lift" % [label, _name(bubble)])
		_anchors(world, label)
		_tips(bubbles, label + ", settled")
		# Spirits by every bubble's control: the journey lift (and Tide's gauge
		# climbing) raises bubbles; their tails stay on their controls.
		var slot := str(state.active_slot)
		for bubble: LabelBubble in bubbles:
			for spot: Vector3 in SPOTS:
				var at := bubble.anchor + spot
				var near: Dictionary = state.duplicate()
				near.players = state.players.duplicate(true)
				var player: Dictionary = near.players[slot]
				player.x = int(roundf(at.x * 100.0))
				player.z = int(roundf(at.z * 100.0))
				player.height = int(roundf(world._control_base_height({"position_cm": [player.x, player.z]}) * 100.0))
				world.present(near, true)
				_frames(world, 2)
				for other: LabelBubble in bubbles:
					if other.lift > 0.0: _lifted += 1
					_check(other.lift < other.max_lift() - 0.001, "%s: the cap leaves room for the %s bubble's lift over a spirit at %s (%.2f m)" % [label, _name(other), _name(bubble), other.lift])
					_highest = maxf(_highest, other.lift)
				_tips(bubbles, "%s, a spirit at %s %s" % [label, _name(bubble), spot])
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
				bubble._process(step)
				_tips([bubble], "%s, bobbing" % label)
			bubble.set_bob(false)
			bubble.set_lift(0.0)
			_tips([bubble], "%s, settled again" % label)
	viewport.free()

## Selector bubbles point at their own lever's knob (journey_world's
## _selector_anchor: the lever's foot plus LEVER_TOP; the pivot stands 0.2 m up).
func _anchors(world: Node3D, label: String) -> void:
	for id: String in world._journey_switches:
		var bubble: LabelBubble = world._journey_switches[id].bubble
		var knob: Vector3 = (world._physical_levers[id] as Node3D).position + Vector3(0, JourneyWorld.LEVER_TOP.y - 0.2, 0)
		_check(bubble.anchor.is_equal_approx(knob), "%s: the %s bubble points at its lever's knob (anchor %s, knob %s)" % [label, id, bubble.anchor, knob])

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

func _bubbles_in(node: Node) -> Array[LabelBubble]:
	var found: Array[LabelBubble] = []
	if node is LabelBubble and not node.is_queued_for_deletion(): found.append(node)
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
