extends RefCounted
## A resting spirit's motion (spirit_visual.gd), as closed-form functions of
## the spirit's own clock and role phase: the same pose at the same second at
## any frame rate, and in every replay of a turn. No randomness, no wall
## clock, no signals, no nodes.
##
## Each pose fills one Frame of offsets from the spirit's built pose, which
## SpiritVisual._apply_pose adds on top of its gait and expression. A new pose
## (say a doze) is a sampler next to _rest() plus a name in sample().
##
## Rest never moves upper_body: carried seeds, lenses and the photo strip hang
## from it (carry_anchor_position, photo_anchor_height).

const REST := &"rest"
## Done with its part and waiting for its friend's memory: eyes shut, head
## low, slow deep breaths, leaning on its goal when one is near.
const DOZE := &"doze"

## Breath: torso swells a little, head rides it.
const BREATH_RATE := 1.75
const BREATH_TORSO := Vector3(0.012,0.018,0.012)
const BREATH_HEAD_LIFT := 0.004
## Leaf sway on the sprout (radians of roll). Within the doze droop and the
## wake jolt, so the leaf sinks no deeper into the head than they take it.
const LEAF_RATE := 1.3
const LEAF_SWAY := 0.15
## Glance: a short look to one side, sides alternating, once per period. None
## starts before GLANCE_FIRST seconds. With a partner in view it comes on top
## of the eyes' attention (SpiritVisual), so with the partner off to one side
## one glance turns away and comes back, the next turns toward the partner.
const GLANCE_PERIOD := 7.0
const GLANCE_AT := 5.5
const GLANCE_FIRST := 5.0
const GLANCE_YAW := 0.22
const GLANCE_TURN := 0.35
const GLANCE_HOLD := 0.8
## The eyes lead the head into a glance by this much.
const GLANCE_EYE_LEAD := 0.08
const GLANCE_LOOK := 0.6
## Doze: slower, deeper breaths; the head sinks, the leaf droops, the body
## settles and leans on the goal ("toward") or nods forward without one.
const DOZE_BREATH_RATE := 1.05
const DOZE_BREATH_TORSO := Vector3(0.02,0.032,0.02)
const DOZE_HEAD_SINK := 0.035
const DOZE_HEAD_BREATH := 0.007
const DOZE_LEAF_DROOP := 0.32
const DOZE_SETTLE := 0.045
const DOZE_LEAN := 0.17
const DOZE_NOD := 0.07
const DOZE_NOD_SWAY := 0.025
## The startled wake (SpiritVisual.play_wake): a hop with wide eyes and a
## jolt of the leaf, over WAKE_DURATION seconds; the hop peaks early.
const WAKE_DURATION := 0.75
const WAKE_HOP := 0.17
const WAKE_HOP_END := 0.5
const WAKE_EYES := 0.38
const WAKE_LEAF := 0.45

## Offsets from the built pose. Every field at its cleared value means the
## pose adds nothing.
class Frame:
	## Multiplies the torso's built scale.
	var torso_scale := Vector3.ONE
	## Lifts head, face and sprout (metres).
	var head_lift := 0.0
	## Turns head, face and sprout about the head's centre (radians).
	var head_yaw := 0.0
	## Added to the eyes' look (-1..1 each way).
	var look := Vector2.ZERO
	## Added to the sprout's roll (radians).
	var sprout_roll := 0.0
	## 0 open, 1 shut.
	var eyes_closed := 0.0
	## Added to upper_body.rotation. Never set by rest.
	var body_lean := Vector3.ZERO
	## Lowers upper_body (metres); negative lifts it. Never set by rest.
	var body_drop := 0.0
	## Widens the open eyes (0 none, 1 double height). Never set by rest.
	var eyes_wide := 0.0

	func clear() -> void:
		torso_scale = Vector3.ONE
		head_lift = 0.0
		head_yaw = 0.0
		look = Vector2.ZERO
		sprout_roll = 0.0
		eyes_closed = 0.0
		body_lean = Vector3.ZERO
		body_drop = 0.0
		eyes_wide = 0.0

	## Scales every offset by weight (0 = nothing, 1 = full).
	func scale_by(weight: float) -> void:
		torso_scale = Vector3.ONE + (torso_scale - Vector3.ONE) * weight
		head_lift *= weight
		head_yaw *= weight
		look *= weight
		sprout_roll *= weight
		eyes_closed *= weight
		body_lean *= weight
		body_drop *= weight
		eyes_wide *= weight

	## This frame becomes a + (b - a) * weight.
	func blend(a: Frame, b: Frame, weight: float) -> void:
		torso_scale = a.torso_scale.lerp(b.torso_scale, weight)
		head_lift = lerpf(a.head_lift, b.head_lift, weight)
		head_yaw = lerpf(a.head_yaw, b.head_yaw, weight)
		look = a.look.lerp(b.look, weight)
		sprout_roll = lerpf(a.sprout_roll, b.sprout_roll, weight)
		eyes_closed = lerpf(a.eyes_closed, b.eyes_closed, weight)
		body_lean = a.body_lean.lerp(b.body_lean, weight)
		body_drop = lerpf(a.body_drop, b.body_drop, weight)
		eyes_wide = lerpf(a.eyes_wide, b.eyes_wide, weight)

	## Adds another frame's offsets to this one.
	func add(other: Frame) -> void:
		torso_scale += other.torso_scale - Vector3.ONE
		head_lift += other.head_lift
		head_yaw += other.head_yaw
		look += other.look
		sprout_roll += other.sprout_roll
		eyes_closed = clampf(eyes_closed + other.eyes_closed, 0.0, 1.0)
		body_lean += other.body_lean
		body_drop += other.body_drop
		eyes_wide += other.eyes_wide

## Whether `pose` has a sampler here.
static func has_pose(pose: StringName) -> bool:
	return pose == REST or pose == DOZE

## Fills `out` for `pose` at spirit time t. `still` (Reduce motion): the
## pose's still frame, which for rest is nothing. `context` carries pose
## parameters the spirit worked out this frame.
static func sample(pose: StringName, t: float, phase: float, still: bool, context: Dictionary, out: Frame) -> void:
	out.clear()
	match pose:
		REST: _rest(t, phase, still, out)
		DOZE: _doze(t, phase, still, context, out)

static func _rest(t: float, phase: float, still: bool, out: Frame) -> void:
	if still: return
	var b := breath(t, phase)
	out.torso_scale = Vector3.ONE + BREATH_TORSO * b
	out.head_lift = BREATH_HEAD_LIFT * b
	out.sprout_roll = leaf(t, phase)
	out.head_yaw = glance(t, phase) * GLANCE_YAW
	out.look = Vector2(glance(t + GLANCE_EYE_LEAD, phase) * GLANCE_LOOK, 0.0)

## -1..1, about a 3.6 s period, a little out of step between the two roles.
static func breath(t: float, phase: float) -> float:
	return sin(t * BREATH_RATE + phase * 1.3)

## Sprout roll in radians.
static func leaf(t: float, phase: float) -> float:
	return sin(t * LEAF_RATE + phase * 2.1) * LEAF_SWAY

## -1..1: how far into a glance (sign = side). Zero outside a glance window
## and for any window that starts before GLANCE_FIRST.
static func glance(t: float, phase: float) -> float:
	var shifted := t + phase * 2.3
	var into := fposmod(shifted, GLANCE_PERIOD) - GLANCE_AT
	if into < 0.0: return 0.0
	if t - into < GLANCE_FIRST: return 0.0
	var amount := smoothstep(0.0, GLANCE_TURN, into) * (1.0 - smoothstep(GLANCE_TURN + GLANCE_HOLD, GLANCE_TURN * 2.0 + GLANCE_HOLD, into))
	var side := 1.0 if posmod(floori(shifted / GLANCE_PERIOD), 2) == 0 else -1.0
	return amount * side

## Eyes shut and the body settled. Reduce motion keeps the posture still, at
## the middle of a breath.
static func _doze(t: float, phase: float, still: bool, context: Dictionary, out: Frame) -> void:
	var b := 0.0 if still else sin(t * DOZE_BREATH_RATE + phase * 1.3)
	out.eyes_closed = 1.0
	out.torso_scale = Vector3.ONE + DOZE_BREATH_TORSO * b
	out.head_lift = -DOZE_HEAD_SINK + DOZE_HEAD_BREATH * b
	out.sprout_roll = DOZE_LEAF_DROOP
	out.body_drop = DOZE_SETTLE
	# "toward" is the goal in the facing pivot's space: positive X pitch
	# leans +Z, negative Z roll leans +X.
	var toward: Variant = context.get("toward")
	var across := Vector2(toward.x, toward.z) if toward is Vector3 else Vector2.ZERO
	if across.length_squared() > 0.0001:
		var lean := across.normalized() * DOZE_LEAN
		out.body_lean = Vector3(lean.y, 0.0, -lean.x)
	else:
		out.body_lean = Vector3(DOZE_NOD + DOZE_NOD_SWAY * b, 0.0, 0.0)

## The startled wake at `age` seconds: a quick hop, eyes wide, the leaf
## jolting. Nothing under Reduce motion, where the eyes simply open.
static func wake(age: float, still: bool, out: Frame) -> void:
	out.clear()
	if still or age < 0.0 or age >= WAKE_DURATION: return
	var p := age / WAKE_DURATION
	out.body_drop = -WAKE_HOP * sin(clampf(p / WAKE_HOP_END, 0.0, 1.0) * PI)
	out.eyes_wide = WAKE_EYES * sin(p * PI)
	out.sprout_roll = WAKE_LEAF * sin(p * TAU * 1.5) * (1.0 - p)
