extends "res://presentation/kit/pieces/piece.gd"
## World kit: a stage's goal, in one of its styles (content/dressing/
## prop_styles.gd "goal"; content/dressing/piece_styles.gd picks which). Each
## keeps the goal's exact centre and radius: a low disc under a ring the size
## of the goal, and the ornament above it.
##
##   "bell": the kit bell (bell.gd) hung between two stone posts under a
##       beam; it rings once as the goal lights.
##   "harbour_lantern": a tall harbour lantern on a mole stone well north of
##       the standing point, so a spirit lighting it never hides its head
##       from the follow camera.
##   "crest": a low lit garden crest, a round lamp in the ring; nothing tall
##       stands where the completion garden grows round it.
##   "window": an openable window in a timber frame north of the ring
##       (presentation/house_window.gd); lit, its shutters swing open.
##   "walled_window": the window set in a short plaster wall, so it never
##       stands free inside a room.
##   "planter": the garden planter a seed is planted in (kit/pieces/socket.gd
##       planter()), its soil wide enough for both pads; the soil glows as
##       the goal lights. The world names its root for the socket, so a
##       planting finds the soil right under it (plant_animation.gd soil()).
##
## Every style stands two pads on its disc side by side (kit/pieces/pad.gd),
## the first pip's west and the second's east, each in its pip's colour: the
## goal needs both pips. A pad presses down and glows while its own pip stands
## on it (present_pips), live or a memory; standing on one always counts as at
## the goal, since each lies wholly inside the goal's radius (pad_offset,
## pad_radius). The goal lights, and a bell rings, only once the stage is done
## with both there (lit()), never as one pip arrives. Anything else the goal
## waits for (an item carried, a lantern lit) stands as a token between the
## pads, lit while it is met (kit/goal_needs.gd, add_needs).
##
## The handles the world lights (lighthouse_world present): `bell` (the
## lantern, the lamp or the window pane), `ring`, and `light`, an omni light
## the world brightens, stood in the parent's space beside the goal. A window
## style also keeps `window` for house_window.gd present.
const WindowVisual = preload("res://presentation/house_window.gd")
const Look = preload("res://presentation/kit/look.gd")
const Bell = preload("res://presentation/kit/pieces/bell.gd")
const Models = preload("res://presentation/kit/models.gd")
const PadKit = preload("res://presentation/kit/pieces/pad.gd")
const GoalNeeds = preload("res://presentation/kit/goal_needs.gd")
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")
## The goal's pads: each one's radius and its centre's distance from the
## goal's centre, as shares of the goal's radius. Together under 1, so a pip
## anywhere on a pad stands at the goal; far enough out to clear a crest's lamp.
const PAD_SHARE := 0.3
const PAD_OUT := 0.5
const PAD_SLOTS := ["p0", "p1"]
## Where a pip counts as on its pad: this far past its radius, this far above
## or below the goal's floor (m).
const PAD_SLACK := 0.02
const PAD_HEIGHT := 0.3
## The planter style's drum: lower than a socket planter's (socket.gd
## PLANTER), so its pads' rims, on the soil, stay low enough to stand in.
const PLANTER_DRUM := 0.04
## The top of each style's disc (the bell frame's step). Its pads stand
## PAD_SINK into it, so a pad's rim stays low enough to stand in (kit/
## prop_rules.gd STEP_ON) and a pressed board's top stays above the disc.
## A planter's is its soil's top (PLANTER_DRUM + 0.0325).
const DISC_TOPS := {"bell": 0.065, "harbour_lantern": 0.05, "crest": 0.044, "window": 0.0475, "walled_window": 0.0475, "planter": PLANTER_DRUM + 0.0325}
const PAD_SINK := 0.02
## The bell style's frame, modelled in Blender (tools/blender/models/bell_frame.py).
const FRAME := "res://assets/models/bell_frame.glb"
## Half the frame's width across its posts (its widest, x).
const BELL_FRAME_HALF := 0.55
## The harbour lantern style's post (tools/blender/models/harbour_more.py).
const HARBOUR := "res://assets/models/harbour_more.glb"
## A lit goal's light, before the look's lamp scale (kit/look.gd lamp_energy).
const LIGHT_ENERGY := 1.2
const STYLES := ["bell", "harbour_lantern", "crest", "window", "walled_window", "planter"]
## Styles whose cradle carries its owner's mark (kit/owner_mark.gd): the ones a
## spirit lights from in front, where the mark stands clear of the ornament.
const MARKED := ["harbour_lantern", "window", "walled_window"]
## Root node names, one per style.
const NAMES := {"bell": "CourtBell", "harbour_lantern": "HarbourLanternGoal", "crest": "GardenLightCrest", "window": "ArrivalWindowGoal", "walled_window": "ArrivalWindowGoal", "planter": "GardenPlanter"}
const BELL_LIGHT := Color("ffd9a2")
const SLATE := Color("6b8984")
## The plaster wall's plane, just behind the window's frame.
const WALL_Z := -0.49

var bell: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var window: Dictionary = {}
## The bell style's bell (kit/pieces/bell.gd); null for the other styles.
var chime: RefCounted
## The goal's pads by slot (kit/pieces/pad.gd).
var pads: Dictionary = {}
## What else the goal waits for (kit/goal_needs.gd), a token each.
var needs := GoalNeeds.new()
var _radius := 0.0

## A goal in `style` at `at` (parent space, on its floor) under `parent`,
## `radius_m` across.
static func build(goal_style: String, at: Vector3, radius_m: float, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/goal.gd").new()
	piece._make(goal_style if goal_style in STYLES else "bell", at, radius_m, parent)
	return piece

## Lights the goal once the stage's objective is done (the snapshot's
## objective_done), or puts it out: its ring and ornament glow and its light
## comes up; a window glows gold and swings its shutters open; a bell rings
## once as it lights, unless immediate (a seek, a retry, reduced motion).
func set_lit(on: bool, immediate: bool = false) -> void:
	Parts.glow(ring, Parts.LIGHT, 1.0 if on else 0.0)
	if window.is_empty(): Parts.glow(bell, Parts.LIGHT, 0.65 if on else 0.0)
	else: WindowVisual.present(window, on, Parts.GOLD)
	light.light_energy = Look.lamp_energy(LIGHT_ENERGY) if on else 0.0
	bell.set_meta("lit", on)
	if chime != null: chime.set_rung(on, immediate)

## Whether a goal shows lit in `state`: its stage done (objective_done) and
## over (complete), so it lights and rings once, with both pips there.
static func lit(state: Dictionary) -> bool:
	return bool(state.get("objective_done", false)) and bool(state.get("complete", state.get("objective_done", false)))

## Pad `slot`'s centre from the goal's centre (m, on the floor), for a goal
## `radius_m` across: the first pip's west, the second's east.
static func pad_offset(slot: String, radius_m: float) -> Vector3:
	return Vector3((-1.0 if slot == "p0" else 1.0) * radius_m * PAD_OUT, 0, 0)

static func pad_radius(radius_m: float) -> float:
	return radius_m * PAD_SHARE

## Presses each pad whose own pip stands on it in `players` (the snapshot's,
## cm, in the parent's space), and lights its rim.
func present_pips(players: Dictionary, immediate: bool = false) -> void:
	for slot: String in pads:
		var pad: RefCounted = pads[slot]
		var player: Variant = players.get(slot)
		var on := false
		if player is Dictionary:
			var spot: Vector3 = root.position + pad.at
			var at := Vector3(float(player.get("x", 0)), float(player.get("height", 0)), float(player.get("z", 0))) / 100.0
			on = absf(at.y - root.position.y) <= PAD_HEIGHT and Vector2(at.x - spot.x, at.z - spot.z).length() <= pad.radius + PAD_SLACK
		if on == pad.held() and not immediate: continue
		pad.set_held(on, immediate)
		Parts.glow(pad.rim, Parts.LIGHT, 1.0 if on else 0.0)

## Puts a token for each need of `stage`'s goal (kit/goal_needs.gd);
## `item_style` (Callable(id) -> String) names a carried item's style.
func add_needs(stage: Dictionary, item_style: Callable) -> void:
	needs.build(stage, root, _radius, float(DISC_TOPS[style]), item_style)

## Each pad as the world's pad_spots() lists it: {id ("goal:<slot>"), at
## (the parent's space), radius, held}.
func pad_spots() -> Array:
	var spots: Array = []
	for slot: String in pads:
		var pad: RefCounted = pads[slot]
		spots.append({"id": "goal:" + slot, "at": root.position + Vector3(pad.at.x, 0, pad.at.z), "radius": pad.radius, "held": pad.held()})
	return spots

func moving() -> bool:
	if chime != null and chime.moving(): return true
	for pad: RefCounted in pads.values():
		if pad.moving(): return true
	return false

func advance(delta: float) -> void:
	if chime != null: chime.advance(delta)
	for pad: RefCounted in pads.values():
		if pad.moving(): pad.advance(delta)

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [bell, ring]
	for shutter: Node3D in window.get("shutters", []): parts.append(shutter)
	if chime != null: parts.append_array(chime.moving_parts())
	for pad: RefCounted in pads.values(): parts.append_array(pad.moving_parts())
	parts.append_array(needs.moving_parts())
	return parts

## How far from its centre a goal in `goal_style`, `radius_m` across, is
## drawn on its floor (metres): the bell's frame is wider than most rings.
static func drawn_radius(goal_style: String, radius_m: float) -> float:
	return maxf(radius_m, BELL_FRAME_HALF) if goal_style == "bell" else radius_m

func _make(goal_style: String, at: Vector3, radius_m: float, parent: Node3D) -> void:
	style = goal_style
	_radius = radius_m
	_root(NAMES[goal_style], at, parent)
	anchor = root
	match goal_style:
		"harbour_lantern": _make_lantern(radius_m)
		"crest": _make_crest(radius_m)
		"window", "walled_window": _make_window(radius_m)
		"planter": _make_planter(radius_m)
		_: _make_bell(radius_m)
	parent.add_child(light)
	for slot: String in PAD_SLOTS:
		pads[slot] = PadKit.build(PadKit.DEFAULT_STYLE, pad_offset(slot, radius_m) + Vector3(0, float(DISC_TOPS[goal_style]) - PAD_SINK, 0), pad_radius(radius_m), root, {"owner": slot, "id": "goal-" + slot, "shadow": false})

## The goal's light, off, at `offset` from the goal in the parent's space.
func _light(color: Color, reach: float, offset: Vector3) -> void:
	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = reach
	light.position = root.position + offset

func _make_bell(radius_m: float) -> void:
	# The step, beam and posts (assets/models/bell_frame.glb), the right post the
	# left one turned round; the ring stays a kit ring, lit with the goal.
	Models.still(FRAME, "bell_frame", {"step": Color("697b8e"), "beam": Color("b4a381"), "trim": Color("9e9180")}, root)
	var post_colors := {"stone": Parts.STONE, "post": Color("9e9180"), "beam": Color("b4a381")}
	var left := Models.still(FRAME, "bell_post", post_colors, root)
	Models.still(FRAME, "bell_post", post_colors, root).transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-left.position.x, 0, left.position.z))
	ring = Parts.ring(radius_m, Color("a2b3c0"), Vector3(0, 0.07, 0), root)
	# Between the posts, under the beam, clear of a pip standing on the ring.
	chime = Bell.build(root, Vector3(0, 1.46, -0.12), Vector2(0.76, 0.52))
	bell = chime.body
	_light(BELL_LIGHT, 4.0, Vector3(0, 1.6, 0))

func _make_lantern(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.05, SLATE, Vector3(0, 0.025, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	var base := Vector3(0, 0, -0.85)
	# The plinth, pole, frame and roof (assets/models/harbour_more.glb); the panes
	# and the lit lantern stay kit parts.
	Models.still(HARBOUR, "harbour_lantern", {"stone": Parts.STONE, "pole": Parts.TIMBER.darkened(0.2), "frame": Parts.TIMBER.darkened(0.25), "brass": Parts.BRASS}, root).position = base
	var head := base + Vector3(0, 1.78, 0)
	for side: Vector3 in [Vector3(0, 0, 0.16), Vector3(0, 0, -0.16), Vector3(0.16, 0, 0), Vector3(-0.16, 0, 0)]:
		var pane := Parts.box(Vector3(0.012 if side.x != 0.0 else 0.30, 0.40, 0.012 if side.z != 0.0 else 0.30), Color(1.0, 0.92, 0.72, 0.42), head + side, root)
		pane.name = "LanternPane"
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bell = Parts.sphere(0.10, Color("e6c98a"), head, root)
	bell.name = "HarbourLantern"
	_light(Parts.LIGHT, 4.5, head + Vector3(0, 0, 0.2))

## Low enough to stay clear of the completion bed's discs around it; a round
## lamp, since a gold diamond would read as the first spirit's mark.
func _make_crest(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.044, SLATE, Vector3(0, 0.022, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	bell = Parts.cylinder(0.075, 0.022, Parts.LIGHT, Vector3(0, 0.07, 0), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 0.8, 0))

func _make_window(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.045, Color("748e87"), Vector3(0, 0.025, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	window = WindowVisual.build(root, Vector3(0, 0, -0.44), 0.80, Parts.HOME_FRAME, Parts.GLASS, Parts.CREAM)
	bell = window.pane
	bell.name = "SecondWindow"
	for side: int in [-1, 1]: Parts.box(Vector3(0.08, 0.42, 0.08), Parts.HOME_FRAME, Vector3(float(side) * 0.42, 0.21, -0.44), root)
	if style == "walled_window":
		for side: int in [-1, 1]: Parts.box(Vector3(0.46, 1.36, 0.07), Parts.HOME_PLASTER, Vector3(float(side) * 0.68, 0.68, WALL_Z), root)
		# Just under the sill and the posts, never level with either.
		Parts.box(Vector3(0.90, 0.415, 0.07), Parts.HOME_PLASTER, Vector3(0, 0.2075, WALL_Z), root)
		Parts.box(Vector3(0.90, 0.18, 0.07), Parts.HOME_PLASTER, Vector3(0, 1.27, WALL_Z), root)
		Parts.box(Vector3(1.86, 0.07, 0.12), Parts.HOME_FRAME, Vector3(0, 1.39, WALL_Z), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 1.0, -0.20))

## The planter's soil reaches past the pads' outer edges (PAD_OUT + PAD_SHARE),
## inside its drum; its ring lies over the drum's rim, where a garden's does.
func _make_planter(radius_m: float) -> void:
	bell = SocketKit.planter(root, radius_m, minf(radius_m * (PAD_OUT + PAD_SHARE) + 0.01, radius_m - 0.04), PLANTER_DRUM)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, PLANTER_DRUM + 0.03, 0), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 0.8, 0))
