extends SceneTree
## A resting spirit's idle motion (presentation/spirit_idle.gd through
## spirit_visual.gd): breath, leaf sway and a glance. Bounded,
## closed-form in the spirit's own clock (the same pose at any frame rate),
## silent, allocation-free, never on upper_body (carried props hang from it),
## and gone under Reduce motion, which leaves exactly the old still pose. Also
## the card-frame path (island_world.advance_idle): only spirits move, at most
## IDLE_CARD_HZ times a second, so a calm screen that draws on change stays
## calm.

const Spirit = preload("res://presentation/spirit_visual.gd")
const Idle = preload("res://presentation/spirit_idle.gd")
const World = preload("res://presentation/island_world.gd")
const Levels = preload("res://core/levels.gd")
const Simulation = preload("res://core/simulation.gd")
const Preview = preload("res://relay_preview.gd")
const Frames = preload("res://services/frame_policy.gd")

const EPSILON := 0.00001
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_math()
	_test_bounds_and_body()
	_test_frame_rate_independence()
	_test_roles()
	_test_reduced_motion()
	_test_silence_and_allocation()
	_test_glance_with_partner()
	_test_reset()
	_test_pose_api()
	await _test_card_frames()
	print("AFTER YOU SPIRIT IDLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _spirit(role: String, partner: bool) -> Node3D:
	var spirit: Node3D = Spirit.new()
	root.add_child(spirit)
	spirit.set_expression_role(role)
	spirit.set_partner_offset(Vector3(1.0, 0, 0.4), partner)
	return spirit

func _idle(spirit: Node3D, frames: int, delta: float = 1.0 / 60.0) -> void:
	for _frame in range(frames): spirit.advance_motion(Vector3.ZERO, delta, false)

## Every node the idle layer writes, as one array.
func _pose(spirit: Node3D) -> Array:
	return [spirit.torso.scale, spirit.head.position, spirit.head.rotation, spirit.face.position, spirit.face.rotation, spirit.sprout.position, spirit.sprout.rotation, spirit.eyes[0].position, spirit.eyes[1].position, spirit.eyes[0].scale]

func _poses_match(a: Array, b: Array, tolerance: float) -> bool:
	for index in range(a.size()):
		if (a[index] - b[index]).length() > tolerance: return false
	return true

func _test_math() -> void:
	var breath_top := 0.0
	var leaf_top := 0.0
	var glance_top := 0.0
	var early := 0.0
	var sides := {}
	for step in range(0, 6000):
		var t := step * 0.01
		for phase: float in [0.0, 1.73]:
			breath_top = maxf(breath_top, absf(Idle.breath(t, phase)))
			leaf_top = maxf(leaf_top, absf(Idle.leaf(t, phase)))
			var g := Idle.glance(t, phase)
			glance_top = maxf(glance_top, absf(g))
			if t < Idle.GLANCE_FIRST: early = maxf(early, absf(g))
			if absf(g) > 0.99: sides[signf(g)] = true
	_check(breath_top <= 1.0 and breath_top > 0.99, "Breath stays within -1..1 and reaches it")
	_check(leaf_top <= Idle.LEAF_SWAY + EPSILON and leaf_top > Idle.LEAF_SWAY * 0.99, "Leaf sway stays within its roll")
	_check(glance_top <= 1.0 and early == 0.0, "No glance before %.0f s, and none past full turn" % Idle.GLANCE_FIRST)
	_check(sides.has(1.0) and sides.has(-1.0), "Glances alternate sides")
	# A glance turns, holds and turns back without a jump.
	var biggest_jump := 0.0
	for step in range(1, 60000):
		biggest_jump = maxf(biggest_jump, absf(Idle.glance(step * 0.001, 1.73) - Idle.glance((step - 1) * 0.001, 1.73)))
	_check(biggest_jump < 0.01, "A glance eases in and out with no jump (largest step %.4f per ms)" % biggest_jump)

func _test_bounds_and_body() -> void:
	for partner: bool in [false, true]:
		var spirit := _spirit("b", partner)
		var body_still := true
		var anchors_still := true
		var torso_ok := true
		var head_ok := true
		var leaf_ok := true
		var yaw_top := 0.0
		var lift_top := 0.0
		var eye_reach := 0.0
		_idle(spirit, 120)
		var anchor: Vector3 = spirit.carry_anchor_position()
		var photo: float = spirit.photo_anchor_height()
		var lean: Vector3 = spirit.upper_body.rotation
		for _frame in range(1200):
			_idle(spirit, 1)
			var scale: Vector3 = spirit.torso.scale / Spirit.TORSO_SCALE
			torso_ok = torso_ok and absf(scale.x - 1.0) <= Idle.BREATH_TORSO.x + EPSILON and absf(scale.y - 1.0) <= Idle.BREATH_TORSO.y + EPSILON and absf(scale.z - scale.x) < EPSILON
			var lift: float = spirit.head.position.y - Spirit.HEAD_CENTER.y
			lift_top = maxf(lift_top, absf(lift))
			head_ok = head_ok and spirit.face.position == spirit.head.position and spirit.face.rotation == spirit.head.rotation and spirit.head.position.x == 0.0 and spirit.head.position.z == 0.0
			yaw_top = maxf(yaw_top, absf(spirit.head.rotation.y))
			eye_reach = maxf(eye_reach, absf(spirit.eyes[0].position.x + 0.115))
			leaf_ok = leaf_ok and absf(spirit.sprout.rotation.y - spirit.head.rotation.y) < EPSILON
			body_still = body_still and spirit.upper_body.position == Vector3.ZERO and spirit.upper_body.scale == Vector3.ONE and absf(spirit.upper_body.rotation.z) <= 0.018
			if not partner: body_still = body_still and spirit.upper_body.rotation == Vector3.ZERO
			# With a partner the existing lean (upper_body) moves them; alone nothing may.
			if not partner: anchors_still = anchors_still and spirit.carry_anchor_position() == anchor and spirit.photo_anchor_height() == photo
		var label := "with a partner" if partner else "alone"
		_check(torso_ok, "Breath swells the torso within its bounds, %s" % label)
		_check(lift_top <= Idle.BREATH_HEAD_LIFT + EPSILON and lift_top > Idle.BREATH_HEAD_LIFT * 0.9, "The head rides the breath by %.3f m, %s" % [Idle.BREATH_HEAD_LIFT, label])
		_check(head_ok, "Face moves and turns exactly with the head, %s" % label)
		_check(leaf_ok, "The sprout turns with the head, %s" % label)
		_check(yaw_top <= Idle.GLANCE_YAW + EPSILON and yaw_top > Idle.GLANCE_YAW * 0.99, "The spirit glances aside by up to %.2f rad, %s" % [Idle.GLANCE_YAW, label])
		_check(eye_reach <= 0.018 + EPSILON, "A glance never takes the eyes past their reach, %s" % label)
		_check(body_still, "Idle never bobs, squashes or (alone) leans upper_body, %s" % label)
		if not partner: _check(anchors_still, "Alone, carry and photo anchors stay exactly put through idle")
		if not partner: _check(spirit.upper_body.rotation == lean, "Alone, upper_body stays exactly neutral")
		spirit.free()
	# The sprout's sway: at rest, its roll minus the head tilt is the leaf.
	var spirit := _spirit("a", true)
	var sway_top := 0.0
	for _frame in range(600):
		_idle(spirit, 1)
		sway_top = maxf(sway_top, absf(spirit.sprout.rotation.z + 0.5 - spirit.head.rotation.z))
	_check(sway_top <= Idle.LEAF_SWAY + EPSILON and sway_top > Idle.LEAF_SWAY * 0.8, "The leaf sways on top of the head's tilt (%.3f rad)" % sway_top)
	spirit.free()

func _test_frame_rate_independence() -> void:
	# 13 s: the "a" spirit is mid-glance, the "b" spirit is not.
	for role: String in ["a", "b"]:
		var poses: Array = []
		for pattern: Array in [[1.0 / 30.0], [1.0 / 60.0], [1.0 / 45.0, 1.0 / 90.0], [1.0 / 120.0]]:
			var spirit := _spirit(role, false)
			var t := 0.0
			var index := 0
			while t < 13.0 - 0.0000001:
				var step: float = pattern[index % pattern.size()]
				spirit.advance_motion(Vector3.ZERO, step, false)
				t += step
				index += 1
			poses.append(_pose(spirit))
			if role == "a" and pattern.size() == 1 and pattern[0] == 1.0 / 60.0:
				_check(absf(spirit.head.rotation.y) > Idle.GLANCE_YAW * 0.9, "The rate check catches the 'a' spirit mid-glance")
			spirit.free()
		var same := true
		for other in range(1, poses.size()): same = same and _poses_match(poses[0], poses[other], 0.0001)
		_check(same, "Role %s reaches the same idle pose at 30, 60, 120 and uneven frame rates" % role)

func _test_roles() -> void:
	var first := _spirit("a", false)
	var twin := _spirit("p0", false)
	var second := _spirit("b", false)
	_idle(first, 400)
	_idle(twin, 400)
	_idle(second, 400)
	_check(_poses_match(_pose(first), _pose(twin), 0.0), "Equivalent roles breathe in exactly the same step")
	_check(not _poses_match(_pose(first), _pose(second), 0.0005), "The two spirits breathe out of step")
	first.free()
	twin.free()
	second.free()

func _test_reduced_motion() -> void:
	var spirit := _spirit("a", false)
	_idle(spirit, 13 * 60)
	_check(spirit.head.rotation.y != 0.0, "Before Reduce motion the spirit is mid-glance")
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, true)
	_check(spirit.torso.scale == Spirit.TORSO_SCALE and spirit.head.position == Spirit.HEAD_CENTER and spirit.face.position == Spirit.HEAD_CENTER, "Reduce motion stops the breath at once, exactly at the built pose")
	_check(spirit.head.rotation == Vector3.ZERO and spirit.face.rotation == Vector3.ZERO, "Reduce motion stops glance and tilt at once")
	_check(spirit.sprout.position == Spirit.SPROUT_REST and spirit.sprout.rotation == Vector3(0, 0, -0.5), "Reduce motion stops the leaf exactly at its built pose")
	_check(spirit.eyes[0].position == Vector3(-0.115, 0.02, 0.289) and spirit.eyes[1].position == Vector3(0.115, 0.02, 0.289) and spirit.eyes[0].scale == Vector3.ONE, "Reduce motion centres the eyes and stops blinking")
	var still := _pose(spirit)
	for _frame in range(600): spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, true)
	_check(_poses_match(still, _pose(spirit), 0.0), "Under Reduce motion nothing moves at all")
	# A fresh spirit under Reduce motion: the same exact pose.
	var fresh := _spirit("b", true)
	fresh.advance_motion(Vector3.ZERO, 1.0 / 60.0, true)
	_check(_poses_match(still, _pose(fresh), 0.0), "Every spirit holds the same still pose under Reduce motion")
	spirit.free()
	fresh.free()

func _test_silence_and_allocation() -> void:
	for partner: bool in [false, true]:
		var spirit := _spirit("b", partner)
		var signals := [0]
		spirit.stepped.connect(func() -> void: signals[0] += 1)
		spirit.reunion_started.connect(func() -> void: signals[0] += 1)
		_idle(spirit, 60)
		var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
		var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var resources := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
		_idle(spirit, 1200)
		_check(signals[0] == 0, "Idle motion emits no step or reunion signal (%s)" % ("with a partner" if partner else "alone"))
		_check(Performance.get_monitor(Performance.OBJECT_COUNT) == objects and Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes and Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT) == resources, "Idle frames make no objects, nodes or resources")
		spirit.free()

## With a partner off to one side, glances still alternate on the clock: one
## turns away and comes back to the partner, the next turns toward it.
func _test_glance_with_partner() -> void:
	var spirit := _spirit("a", false)
	_idle(spirit, 13 * 60)
	_check(absf(spirit.head.rotation.y) > Idle.GLANCE_YAW * 0.9, "Alone at 13 s the spirit is glancing")
	_check(absf(spirit.eyes[0].position.x + 0.115) > 0.005, "The eyes lead into the glance")
	var yaw: float = spirit.head.rotation.y
	spirit.set_partner_offset(Vector3(1.2, 0, 0), true)
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_check(absf(spirit.head.rotation.y - yaw) < 0.01, "A partner coming into view lets the glance carry on")
	spirit.free()
	# The partner on the spirit's +X side: full attention puts the eyes 18 mm over.
	var reach := -0.115 + 0.018
	spirit = _spirit("a", false)
	spirit.set_partner_offset(Vector3(1.2, 0, 0), true)
	_idle(spirit, 13 * 60)
	_check(spirit.head.rotation.y < -Idle.GLANCE_YAW * 0.9, "At 13 s the spirit glances away from its partner")
	_check(spirit.eyes[0].position.x < reach - 0.005, "The eyes leave the partner with the glance")
	_idle(spirit, 90)
	_check(spirit.head.rotation.y == 0.0, "After the glance the head is straight again")
	_check(absf(spirit.eyes[0].position.x - reach) < 0.0001, "After the glance the eyes are back on the partner")
	_idle(spirit, 330)
	_check(spirit.head.rotation.y > Idle.GLANCE_YAW * 0.9, "At 20 s the next glance turns toward the partner")
	_check(absf(spirit.eyes[0].position.x - reach) < 0.0001, "Glancing toward the partner turns the head; the eyes stay at their reach")
	spirit.free()

func _test_reset() -> void:
	var spirit := _spirit("a", false)
	_idle(spirit, 13 * 60)
	spirit.reset_motion()
	_check(spirit.torso.scale == Spirit.TORSO_SCALE and spirit.head.position == Spirit.HEAD_CENTER and spirit.head.rotation == Vector3.ZERO and spirit.face.rotation == Vector3.ZERO, "A seek returns the head and torso to rest")
	_check(spirit.sprout.position == Spirit.SPROUT_REST and spirit.sprout.rotation == Vector3(0, 0, -0.5), "A seek returns the sprout to rest")
	# The same seconds after a seek give the same pose as from a fresh spirit.
	var fresh := _spirit("a", false)
	_idle(spirit, 200)
	_idle(fresh, 200)
	_check(_poses_match(_pose(spirit), _pose(fresh), 0.0), "Idle after a seek repeats exactly")
	spirit.free()
	fresh.free()

func _test_pose_api() -> void:
	var spirit := _spirit("a", true)
	_check(spirit.pose() == Idle.REST, "Spirits start in the rest pose")
	_idle(spirit, 100)
	var before := _pose(spirit)
	spirit.set_pose(Idle.REST)
	spirit.set_pose(Idle.REST, {}, true)
	_check(spirit._pose_blend == 1.0 and _poses_match(before, _pose(spirit), 0.0), "Asserting the current pose again changes nothing")
	spirit.set_pose(&"no-such-pose")
	_check(spirit.pose() == Idle.REST, "An unknown pose is refused")
	spirit.position = Vector3(2, 0, 1)
	spirit.set_pose(Idle.REST, {"toward": Vector3(2, 0, 3)})
	spirit.facing.rotation.y = PI * 0.5
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	var toward: Vector3 = spirit._pose_context.get("toward", Vector3.INF)
	_check(toward.is_equal_approx(spirit.facing.basis.inverse() * Vector3(0, 0, 2)), "A pose's world target reaches its sampler in the facing pivot's space")
	spirit.reset_motion()
	_check(spirit.pose() == Idle.REST and spirit._pose_blend == 1.0, "A seek keeps the pose at full strength")
	spirit.free()

## The ready and waiting cards hold the world and let only spirits breathe,
## a few times a second.
func _test_card_frames() -> void:
	var definition: Dictionary = Levels.get_level("first-light")
	var simulation := Simulation.new()
	var recording: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	_check(simulation.reset(definition, recording, "b"), "Card frames use a validated level")
	var world: Node3D = World.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view = false
	world.load_level(definition)
	world.present(simulation.snapshot(), true)
	var signals := [0]
	world.footstep.connect(func(_spirit: String) -> void: signals[0] += 1)
	world.reunion.connect(func() -> void: signals[0] += 1)
	var camera: Transform3D = world.camera.global_transform
	var motes: Array = []
	for mote: Node3D in world.motes: motes.append(mote.position)
	var actor: Node3D = world.actors.values()[0]
	var moved := 0
	var quiet_frames_still := true
	var last := _pose(actor)
	var clock_before: float = actor._expression_time
	# 3 s of a 30 fps calm screen.
	for _frame in range(90):
		var advanced: bool = world.advance_idle(1.0 / 30.0)
		var now := _pose(actor)
		if advanced: moved += 1
		elif not _poses_match(now, last, 0.0): quiet_frames_still = false
		last = now
	_check(moved >= 3 * 8 and moved <= 3 * int(World.IDLE_CARD_HZ), "A card moves its spirits %d times in 3 s (at most %d a second)" % [moved, int(World.IDLE_CARD_HZ)])
	_check(quiet_frames_still, "Between card steps nothing on the spirits changes, so nothing needs drawing")
	_check(absf(actor._expression_time - clock_before - 3.0) < 0.1, "The spirits' clock keeps real time across card steps")
	var world_still: bool = world.camera.global_transform == camera
	for index in range(motes.size()): world_still = world_still and world.motes[index].position == motes[index]
	_check(world_still, "A card step moves neither the camera nor the motes")
	_check(signals[0] == 0, "Card steps make no footstep or reunion sound")
	# Same pose as a world advanced every frame for the same time.
	var other: Node3D = World.new()
	root.add_child(other)
	other.set_process(false)
	other.home_view = false
	other.load_level(definition)
	other.present(simulation.snapshot(), true)
	for _frame in range(180):
		other.update_spirit_attention()
		for role: String in other.actors: other.actors[role].advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	var reference: Node3D = other.actors.values()[0]
	_check(absf(reference._expression_time - actor._expression_time) < EPSILON, "The reference ran the same seconds")
	_check(_poses_match(_pose(reference), _pose(actor), 0.0001), "Ten card steps a second reach the pose of sixty frames a second")
	world.reduced_motion = true
	_check(world.advance_idle(1.0), "Reduce motion turned on over a card settles its spirits once")
	_check(actor.torso.scale == Spirit.TORSO_SCALE and actor.head.rotation == Vector3.ZERO, "Reduce motion stills a card's spirits")
	var settled := _pose(actor)
	var quiet := true
	for _frame in range(90): quiet = quiet and not world.advance_idle(1.0 / 30.0)
	_check(quiet and _poses_match(settled, _pose(actor), 0.0), "After that, a card under Reduce motion writes nothing, so it draws nothing")
	world.reduced_motion = false
	_check(world.advance_idle(1.0), "Turning Reduce motion off lets the card breathe again")
	# Motion back on for a played stretch, then Reduce motion again on a card:
	# the card settles once more.
	world._process(1.0 / 60.0)
	world.reduced_motion = true
	world._process(1.0 / 60.0)
	_check(world.advance_idle(1.0) and not world.advance_idle(1.0), "A card after a played frame settles once again under Reduce motion")
	world.reduced_motion = false
	# Home owned by its stage: card frames leave its spirits to it.
	world.home_view = true
	world.home_presentation_owner = 1
	_check(not world.advance_idle(1.0), "Home's own stage drives Home's spirits")
	world.queue_free()
	other.queue_free()
	# The chapter screen stays calm on its cards.
	var preview: Node = Preview.new()
	for name: String in ["ready", "online_waiting"]:
		preview.mode = name
		_check(preview.frame_demand() == Frames.CALM, "Breathing spirits leave the %s card calm" % name)
	preview.free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
