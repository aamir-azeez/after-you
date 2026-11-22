extends "res://presentation/kit/pieces/piece.gd"
## World kit: a stage's goal, in one of its styles (content/dressing/
## prop_styles.gd "goal"; content/dressing/piece_styles.gd picks which). Each
## keeps the goal's exact centre and radius: a low disc under a ring the size
## of the goal, the split plate on it, and the ornament above it.
##
##   "bell": the kit bell (bell.gd) hung between two stone posts under a
##       beam; it rings once as the goal lights.
##   "harbour_lantern": a tall harbour lantern on a mole stone well north of
##       the standing point, so a spirit lighting it never hides its head
##       from the follow camera.
##   "crest": a low lit garden crest, a round lamp at the plate's back edge;
##       nothing tall stands where the completion garden grows round it.
##   "window": an openable window in a timber frame north of the ring
##       (presentation/house_window.gd); lit, its shutters swing open.
##   "walled_window": the window set in a short plaster wall, so it never
##       stands free inside a room.
##   "planter": the garden planter a seed is planted in (kit/pieces/socket.gd
##       planter()), its soil wide enough for the plate; the soil glows as
##       the goal lights. The world names its root for the socket, so a
##       planting finds the soil right under it (plant_animation.gd soil()).
##
## Every style stands one plate on its base: a squircle (kit/squircle.gd, a soft
## rounded square) split down its middle into two pads, the first pip's west
## half and the second's east, each its own board in its pip's colour whose
## outer edge follows the curve and whose inner edge meets the other at the
## centre line, with its own outline of the same shape: the goal needs both
## pips. The base is one slightly larger squircle slab under both (a planter
## keeps its round pot) and the ring that lights with the goal follows its
## edge. A half's hit test (PadKit.covers) is its drawn shape. A goal of
## GROWN_FROM or more has each half a regular pad board (kit/pieces/pad.gd
## board_half); smaller, older ones keep the square plate of 1.6 x the radius.
## A half presses down and glows while its own pip stands over it
## (present_pips), live or a memory, the board rule every pad keeps. The goal
## lights, and a
## bell rings, only once the stage is done with both there (lit()), never as
## one pip arrives. Anything else the goal waits for (an item carried, a
## lantern lit) shows as a big token on a sign over the goal's stand, facing
## the camera (kit/goal_needs.gd, add_needs; NEED_SIGNS says where). While a
## pip stands on the plate and the goal is not lit, whatever is still missing
## (the empty half, an unmet token) blinks red with the closing warning's beat
## (present_missing); an unmet token stays plain otherwise.
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
const Primitives = preload("res://presentation/kit/primitives.gd")
const Squircle = preload("res://presentation/kit/squircle.gd")
const GoalNeeds = preload("res://presentation/kit/goal_needs.gd")
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")
const ClosingWarning = preload("res://presentation/kit/closing_warning.gd")
## A goal whose radius is at least this (m) has the grown plate: two regular
## pad boards side by side, the whole squircle inside the goal's counted
## circle. Smaller goals (every level published before) keep the square plate
## of 1.6 x the radius, now a squircle too.
const GROWN_FROM := 0.6
## How far the base slab reaches past the plate's squircle (m), and its
## thickness's top rim colour.
const BASE_RIM := 0.04
## The ring's bar and its height over the base's top (m).
const RING_BAR := 0.025
const RING_HEIGHT := 0.012
## The plate's halves, west then east.
const PAD_SLOTS := ["p0", "p1"]
## Where a pip counts as on its half: this far past its edges, this far above
## or below the goal's floor (m).
const PAD_SLACK := 0.02
const PAD_HEIGHT := 0.3
## How far the disc (a planter's soil) reaches past the plate's corners (m).
const BASE_PAST := 0.005
## The crest's lamp at the plate's back edge: its radius and how far it stands
## over the plate (m).
const CREST_LAMP := 0.075
const CREST_OVER := 0.012
## The planter style's drum: lower than a socket planter's (socket.gd
## PLANTER), so its pads' rims, on the soil, stay low enough to stand in.
const PLANTER_DRUM := 0.04
## The planter's drum rim round its soil (m).
const PLANTER_RIM := 0.04
## The top of each style's disc (the bell frame's step). Its pads stand
## PAD_SINK into it, so a pad's rim stays low enough to stand in (kit/
## prop_rules.gd STEP_ON) and a pressed board's top stays above the disc.
## A planter's is its soil's top (PLANTER_DRUM + 0.0325).
const DISC_TOPS := {"bell": 0.065, "harbour_lantern": 0.05, "crest": 0.044, "window": 0.0475, "walled_window": 0.0475, "planter": PLANTER_DRUM + 0.0325}
const PAD_SINK := 0.02
## Where each style's need sign hangs (its centre, goal space) and whether it
## needs a post of its own: over the tallest part (the bell's beam, the
## lantern's roof, the window's frame), or on a short post behind a crest or
## planter, whose own parts are low. Far above a pip's head (kit/prop_rules.gd
## STEP_HEAD) and behind the plate, so the camera sees it over the goal.
const NEED_SIGNS := {
	"bell": {"at": Vector3(0, 2.05, -0.12), "post": false},
	"harbour_lantern": {"at": Vector3(0, 2.6, -0.85), "post": false},
	"window": {"at": Vector3(0, 1.85, -0.44), "post": false},
	"walled_window": {"at": Vector3(0, 1.85, -0.44), "post": false},
	"crest": {"at": Vector3(0, 1.45, -0.45), "post": true},
	"planter": {"at": Vector3(0, 1.45, -0.45), "post": true},
}
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
## The plate's halves by slot (kit/pieces/pad.gd).
var pads: Dictionary = {}
## What else the goal waits for (kit/goal_needs.gd), a token each.
var needs := GoalNeeds.new()
var _radius := 0.0
## Whether the goal shows lit (set_lit).
var _lit := false
## Whether the plate shows something missing (present_missing).
var _missing := false

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
	_lit = on
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

## Half the plate's depth under a goal in `goal_style`, `radius_m` across (m):
## the legacy plate is square, 0.8 x the radius (a pad board the goal's size,
## kit/pieces/pad.gd board_half; a planter's stays on its soil, inside its
## drum); a grown plate (GROWN_FROM) is a regular pad board deep.
static func plate_half(radius_m: float, goal_style: String = "") -> float:
	return plate_extent(radius_m, goal_style).y

## The plate's whole squircle, half extents (x across both halves, z deep; m).
static func plate_extent(radius_m: float, goal_style: String = "") -> Vector2:
	var room := radius_m - (PLANTER_RIM + BASE_PAST if goal_style == "planter" else 0.0)
	if radius_m >= GROWN_FROM:
		# Two squares side by side, as big as the room's circle allows.
		var unit := Vector2(2.0, 1.0)
		var scale := room / _reach(unit)
		return unit * scale
	var half := PadKit.board_half(radius_m)
	if goal_style == "planter": half = minf(half, room / sqrt(2.0))
	return Vector2(half, half)

## How far from its centre a squircle of half extents `half` reaches (m).
static func _reach(half: Vector2) -> float:
	var reach := 0.0
	for point: Vector2 in Squircle.outline(half): reach = maxf(reach, point.length())
	return reach

## Half `slot`'s centre from the goal's centre (m, on the floor), for a goal
## `radius_m` across: the first pip's west, the second's east.
static func pad_offset(slot: String, radius_m: float, goal_style: String = "") -> Vector3:
	return Vector3((-1.0 if slot == "p0" else 1.0) * plate_extent(radius_m, goal_style).x * 0.5, 0, 0)

## Each half's bounding half extents (x, z; m).
static func pad_half(radius_m: float, goal_style: String = "") -> Vector2:
	var plate := plate_extent(radius_m, goal_style)
	return Vector2(plate.x * 0.5, plate.y)

## The base slab's squircle: past the plate by BASE_RIM (a planter has its
## round soil and drum instead).
static func base_extent(radius_m: float, goal_style: String = "") -> Vector2:
	return plate_extent(radius_m, goal_style) + Vector2.ONE * BASE_RIM

## The radius of the goal's base, a planter's soil: the base squircle's reach.
static func base_radius(radius_m: float, goal_style: String = "") -> float:
	if goal_style == "planter": return radius_m - PLANTER_RIM
	return maxf(radius_m, _reach(base_extent(radius_m, goal_style)))

## How far the goal's base reaches on its floor (m): its base, a planter's
## drum round its soil.
static func outer_radius(goal_style: String, radius_m: float) -> float:
	return radius_m if goal_style == "planter" else base_radius(radius_m)

## Whether a snapshot player (cm) stands over the half `pad` of this goal.
func _over(pad: RefCounted, player: Variant) -> bool:
	if not player is Dictionary: return false
	var at := Vector3(float(player.get("x", 0)), float(player.get("height", 0)), float(player.get("z", 0))) / 100.0
	return PadKit.covers(root.position + Vector3(pad.at.x, 0, pad.at.z), pad.radius, pad.half_size, at, PAD_SLACK, PAD_HEIGHT, pad.shape)

## Presses each half its own pip stands over in `players` (the snapshot's,
## cm, in the parent's space), and lights its outline.
func present_pips(players: Dictionary, immediate: bool = false) -> void:
	for slot: String in pads:
		var pad: RefCounted = pads[slot]
		var on := _over(pad, players.get(slot))
		if on == pad.held() and not immediate: continue
		pad.set_held(on, immediate)
		if not _missing: Parts.glow(pad.rim, Parts.LIGHT, 1.0 if on else 0.0)

## Each snapshot: the halves (present_pips), the need tokens, and what is
## still missing (present_missing). set_lit goes first.
func present(state: Dictionary, immediate: bool, reduced: bool) -> void:
	present_pips(state.get("players", {}), immediate)
	needs.present(state)
	present_missing(state, reduced)

## While a pip stands on the plate and the goal is not lit, what is still
## missing blinks Parts.MISSING with the closing warning's beat on the
## snapshot's tick (kit/closing_warning.gd; steady under Reduce motion): a
## half its pip is not on, and each need's token not met. Off at once when
## that part is done or nobody is on the plate. From the snapshot alone, so
## live play, a memory and the friend's screen blink alike.
func present_missing(state: Dictionary, reduced: bool) -> void:
	var players: Dictionary = state.get("players", {})
	var anyone := false
	for pad: RefCounted in pads.values():
		for player: Variant in players.values(): anyone = anyone or _over(pad, player)
	_missing = anyone and not _lit
	var beat := int(state.get("tick", 0)) % (ClosingWarning.BLINK * 2) < ClosingWarning.BLINK
	var energy := ClosingWarning.STEADY if reduced else (ClosingWarning.LIT if beat else ClosingWarning.DIM)
	for pad: RefCounted in pads.values():
		if _missing and not pad.held(): Parts.glow(pad.rim, Parts.MISSING, energy)
		else: Parts.glow(pad.rim, Parts.LIGHT, 1.0 if pad.held() else 0.0)
	for need: Dictionary in needs.needs:
		if _missing and not bool(need.met): Parts.glow(need.disc, Parts.MISSING, energy)
		else: Parts.glow(need.disc, Parts.LIGHT, 1.0 if bool(need.met) else 0.0)

## Whether the plate shows something missing.
func missing() -> bool:
	return _missing

## Puts a token for each need of `stage`'s goal (kit/goal_needs.gd);
## `item_style` (Callable(id) -> String) names a carried item's style.
func add_needs(stage: Dictionary, item_style: Callable) -> void:
	needs.build(stage, root, NEED_SIGNS[style].at, NEED_SIGNS[style].post, item_style)

## The plate's top over the goal's floor while free (m).
func _plate_top() -> float:
	return float(DISC_TOPS[style]) - PAD_SINK + PadKit.BOARD_TOP

## Each half as the world's pad_spots() lists it: {id ("goal:<slot>"), at
## (the parent's space), radius, half (its half extents), held}.
func pad_spots() -> Array:
	var spots: Array = []
	for slot: String in pads:
		var pad: RefCounted = pads[slot]
		spots.append({"id": "goal:" + slot, "at": root.position + Vector3(pad.at.x, 0, pad.at.z), "radius": pad.radius, "half": pad.half_size, "shape": pad.shape, "held": pad.held()})
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

## How far from its centre a goal in `goal_style`, `radius_m` across, is drawn
## on its floor (metres): its disc past the plate's corners, a planter's drum;
## the bell's frame is wider than most. The need sign hangs overhead, above
## walkable height, so it adds nothing.
static func drawn_radius(goal_style: String, radius_m: float) -> float:
	var drawn := outer_radius(goal_style, radius_m)
	return maxf(drawn, BELL_FRAME_HALF) if goal_style == "bell" else drawn

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
		var whole := plate_extent(radius_m, goal_style)
		pads[slot] = PadKit.build(PadKit.DEFAULT_STYLE, pad_offset(slot, radius_m, goal_style) + Vector3(0, float(DISC_TOPS[goal_style]) - PAD_SINK, 0), pad_half(radius_m, goal_style).x, root, {"owner": slot, "id": "goal-" + slot, "shadow": false, "squircle": {"half": whole, "side": -1 if slot == "p0" else 1}})

## The goal's light, off, at `offset` from the goal in the parent's space.
func _light(color: Color, reach: float, offset: Vector3) -> void:
	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = reach
	light.position = root.position + offset

## The goal's one base: a squircle slab (kit/squircle.gd) a rim past the plate,
## `height` tall, so the plate, its base and the stand read as one piece.
func _base(radius_m: float, height: float, color: Color) -> void:
	var slab := Primitives.mesh_node(Squircle.slab(base_extent(radius_m, style), height), Primitives.shared_material(color), Vector3.ZERO, root)
	slab.name = "GoalBase"

## The goal's ring, lit with it: a squircle frame on the base's rim, `height`
## over the floor (a planter keeps its round ring on its drum).
func _ring(radius_m: float, color: Color, height: float) -> MeshInstance3D:
	var edge := base_extent(radius_m, style) - Vector2.ONE * (BASE_RIM * 0.25)
	var frame := Primitives.mesh_node(Squircle.frame(edge, RING_BAR, RING_HEIGHT), Primitives.shared_material(color), Vector3(0, height - RING_HEIGHT * 0.5, 0), root)
	frame.name = "GoalRing"
	return frame

func _make_bell(radius_m: float) -> void:
	# The step, beam and posts (assets/models/bell_frame.glb), the right post the
	# left one turned round; the ring stays a kit ring, lit with the goal.
	Models.still(FRAME, "bell_frame", {"step": Color("697b8e"), "beam": Color("b4a381"), "trim": Color("9e9180")}, root)
	var post_colors := {"stone": Parts.STONE, "post": Color("9e9180"), "beam": Color("b4a381")}
	var left := Models.still(FRAME, "bell_post", post_colors, root)
	Models.still(FRAME, "bell_post", post_colors, root).transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-left.position.x, 0, left.position.z))
	ring = _ring(radius_m, Color("a2b3c0"), 0.07)
	# Between the posts, under the beam, clear of a pip standing on the ring.
	chime = Bell.build(root, Vector3(0, 1.46, -0.12), Vector2(0.76, 0.52))
	bell = chime.body
	_light(BELL_LIGHT, 4.0, Vector3(0, 1.6, 0))

func _make_lantern(radius_m: float) -> void:
	_base(radius_m, 0.05, SLATE)
	ring = _ring(radius_m, Parts.CREAM, 0.06)
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
## lamp, since a gold diamond would read as the first spirit's mark, standing
## on the disc through the plate's seam at its back edge, just over the plate.
func _make_crest(radius_m: float) -> void:
	_base(radius_m, 0.044, SLATE)
	ring = _ring(radius_m, Parts.CREAM, 0.06)
	var lamp := float(DISC_TOPS.crest) - PAD_SINK + PadKit.BOARD_TOP + CREST_OVER - float(DISC_TOPS.crest)
	bell = Parts.cylinder(CREST_LAMP, lamp, Parts.LIGHT, Vector3(0, float(DISC_TOPS.crest) + lamp * 0.5, -plate_half(radius_m)), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 0.8, 0))

func _make_window(radius_m: float) -> void:
	_base(radius_m, 0.045, Color("748e87"))
	ring = _ring(radius_m, Parts.CREAM, 0.06)
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

## The planter's soil, inside its drum, reaches past the plate's corners
## (plate_half); its ring lies over the drum's rim, where a garden's does.
func _make_planter(radius_m: float) -> void:
	bell = SocketKit.planter(root, radius_m, base_radius(radius_m, "planter"), PLANTER_DRUM)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, PLANTER_DRUM + 0.03, 0), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 0.8, 0))
