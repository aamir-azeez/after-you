extends RefCounted
## World kit: how a stage's new pieces (rules 16, core/physical/pieces_rules.gd)
## look, all read from the stage plan, so a level author writes nothing for
## them. cooperative_world hosts one per stage (the journey worlds' base):
##   - each crossing's deck in its "deck" style (kit/pieces/deck.gd): a crank
##     bridge's rope, sinking stones (the default for a stage's "sinking"
##     crossings), the path behind a waterfall, with the falls' water hung over
##     it while it is shut; "plank" leaves the world's own deck;
##   - each moving platform as one piece riding between its stops, whose own
##     decks stay empty: a lift (kit/pieces/lift.gd, "lift" style) where its
##     stops share a rectangle at two heights, else a raft (kit/pieces/raft.gd,
##     "raft" style); it eases to the stop the snapshot opens, and whatever
##     stands or rests on its stop rides its deck (ride);
##   - each one way stair as a pull-up rope ladder (kit/pieces/rope_ladder.gd,
##     "ladder" style), hung while a pip is at its foot or on it, rolled up at
##     its head otherwise, or as a wheel ride ("wheel"), turning while open;
##   - water in a weight lift's pan while a lantern its lift reads burns (the
##     lantern pump fills the pan);
##   - the fog round lantern levers (kit/fog.gd, the dressing's "fog" pick),
##     and the thick fog over the whole stage when the dressing's look has a
##     cover (kit/fog_cover.gd), thinned round every control and opened for
##     good where the stage's pips have walked (kit/turn_paths.gd).
## The lantern lever, the weight pans, the boards and the rope wheel are ordinary lever, pad
## and selector styles the world builds itself.
## Presentation only: nothing here feeds the simulation.
const Deck = preload("res://presentation/kit/pieces/deck.gd")
const Raft = preload("res://presentation/kit/pieces/raft.gd")
const Lift = preload("res://presentation/kit/pieces/lift.gd")
const RopeLadder = preload("res://presentation/kit/pieces/rope_ladder.gd")
const Fog = preload("res://presentation/kit/fog.gd")
const FogCover = preload("res://presentation/kit/fog_cover.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const FallsCurtain = preload("res://presentation/kit/pieces/falls_curtain.gd")
## The water in a filled pan.
const PAN_WATER := Color("7fa7b0")
## A lift's ride, metres a second.
const LIFT_RATE := 0.8
## How many times faster a platform eases while it carries a pip that has
## already stepped off it (ride_off).
const HURRY := 4.0
## How near a stair's foot (m) a pip lets its ladder down.
const FOOT_REACH := 0.8

var _world: Node3D
var _view: Dictionary
## Stop crossing id -> true; stones id -> true.
var _stops: Dictionary = {}
var _stones: Dictionary = {}
## [{"piece", "stops": [ids], "heights": [m], "anchors": [the piece's root
## at each stop], "half": the deck's half size (m), "lift": bool, "shown": m, "target": m, "at": the stop it
## goes to, "hurry": bool (ride_off)}]
var _platforms: Array = []
## Stair id -> {"piece", "rect" (m), "foot" (m)}.
var _ladders: Dictionary = {}
## Path id -> the falls' water hung over it while shut.
var _curtains: Dictionary = {}
## Rope bridge id -> its slats wound in, shown while shut.
var _wound: Dictionary = {}
## [{"node", "lever"}]: water in a pan while its lantern burns.
var _fills: Array = []
var fog: RefCounted
var cover: RefCounted

func _init(world: Node3D, view: Dictionary) -> void:
	_world = world
	_view = view
	for platform: Dictionary in view.get("platforms", []):
		for id: Variant in platform.get("stops", []): _stops[str(id)] = true
	for id: Variant in view.get("sinking", []): _stones[str(id)] = true

## The deck style of crossing `id`: "" for a platform's stop (the platform
## piece draws it), else its "deck" pick, sinking stones by default.
func deck_style(id: String) -> String:
	if _stops.has(id): return ""
	var style: String = _world._piece_style("deck", id)
	return "stones" if style == "plank" and _stones.has(id) else style

## Whether this kit lays crossing `definition`'s deck (the world lays plank).
func lays(definition: Dictionary) -> bool:
	return deck_style(str(definition.id)) != "plank"

func lay_deck(definition: Dictionary, deck: Node3D, width: float, depth: float, across_x: bool, low: float, high: float) -> void:
	var style := deck_style(str(definition.id))
	if not style.is_empty(): Deck.lay(style, deck, width, depth, across_x, low, high)
	if style == "falls_path":
		# The rock lip over the path and the falls' water pouring off it, shown
		# while the path is shut (kit/pieces/falls_curtain.gd).
		# Beside the deck at the deck's own height, so whatever lifts the deck lifts it.
		_curtains[str(definition.id)] = FallsCurtain.build(_rect(definition.rect_cm), deck.position.y, deck.get_parent() as Node3D)
	elif style == "rope":
		# The posts stand for good; shut, the slats lie wound in at the gap's end.
		_wound[str(definition.id)] = Deck.rope_ends(deck.get_parent() as Node3D, deck.position, width, depth, across_x, low, high)

## A one way stair's ladder, in place of the world's treads.
func build_ladder(stair: Dictionary) -> void:
	var rect := _rect(stair.rect_cm)
	var foot := float(stair.from_height_cm) / 100.0
	var head := float(stair.to_height_cm) / 100.0
	var rising := head >= foot
	var piece: RefCounted = RopeLadder.build(_world._piece_style("ladder", str(stair.id)), rect, minf(foot, head), maxf(foot, head), str(stair.axis) == "x", rising, _world.terrain)
	var foot_at := rect.get_center()
	var half := (rect.size.x if str(stair.axis) == "x" else rect.size.y) * 0.5 * (-1.0 if rising else 1.0)
	if str(stair.axis) == "x": foot_at.x += half
	else: foot_at.y += half
	_ladders[str(stair.id)] = {"piece": piece, "rect": rect, "foot": foot_at, "low": minf(foot, head), "high": maxf(foot, head), "wheel": piece.style == "wheel"}

## The platforms and the fog, once the stage's crossings and levers stand.
func build(lantern_spots: Dictionary) -> void:
	var bridges: Dictionary = {}
	for bridge: Dictionary in _view.get("bridges", []): bridges[str(bridge.id)] = bridge
	for platform: Dictionary in _view.get("platforms", []):
		var stops: Array = Array(platform.stops).map(func(id: Variant) -> Dictionary: return bridges[str(id)])
		var rect := _rect(stops[0].rect_cm)
		var heights: Array = stops.map(func(stop: Dictionary) -> float: return float(stop.get("height_cm", 0)) / 100.0)
		var lift: bool = stops.all(func(stop: Dictionary) -> bool: return stop.rect_cm == stops[0].rect_cm)
		var anchors: Array = []
		for index in range(stops.size()): anchors.append(Vector3(_rect(stops[index].rect_cm).get_center().x, heights[index], _rect(stops[index].rect_cm).get_center().y))
		var entry := {"stops": Array(platform.stops).map(func(id: Variant) -> String: return str(id)), "heights": heights, "anchors": anchors, "half": rect.size / 2.0, "lift": lift, "shown": heights[0], "target": heights[0], "at": 0, "hurry": false}
		if lift:
			entry.piece = Lift.build(_world._piece_style("lift", str(platform.id)), rect, heights.min(), heights.max(), _world.terrain, _drive(platform))
			entry.piece.set_height(heights[0])
			_fill_pans(platform, lantern_spots)
		else:
			var centres: Array[Vector3] = []
			centres.assign(anchors)
			entry.piece = Raft.build(_world._piece_style("raft", str(platform.id)), centres, rect.size, _world.terrain)
		_platforms.append(entry)
	fog = Fog.build(str(_world.dressing.get("fog", "mist")) if not _world.dressing.is_empty() else "mist", _view, lantern_spots, _world.terrain)
	var spots: Array = []
	for field: String in ["levers", "controls", "pressure_pads", "ball_pads"]:
		for spot: Dictionary in _view.get(field, []):
			if not lantern_spots.has(str(spot.get("id", ""))): spots.append([_world.terrain.to_global(_world._at(spot)), float(spot.get("radius_cm", 28)) / 100.0])
	if _view.has("goal") and _view.goal.has("position_cm"): spots.append([_world.terrain.to_global(_world._at(_view.goal)), float(_view.goal.get("radius_cm", 40)) / 100.0])
	var lanterns: Dictionary = {}
	for id: String in lantern_spots: lanterns[id] = _world.terrain.to_global(lantern_spots[id])
	cover = FogCover.build(str(_world.dressing.get("look", "")), _view.get("islands", []), spots, lanterns, _world.terrain)

## Each snapshot: platforms toward their open stop, ladders hung or rolled,
## the fog cleared round lit lanterns.
func present(state: Dictionary, immediate: bool) -> void:
	var routes: Dictionary = state.get("bridges", {})
	for entry: Dictionary in _platforms:
		var index: int = entry.stops.find_custom(func(id: String) -> bool: return bool(routes.get(id, false)))
		if index < 0: continue
		if index != int(entry.at) or immediate: entry.hurry = false
		entry.at = index
		if entry.lift:
			entry.target = float(entry.heights[index])
			if immediate:
				entry.shown = entry.target
				entry.piece.set_height(entry.shown)
				entry.piece.arrive(0.0)
		else: entry.piece.set_value(index, immediate)
	for id: String in _curtains: _curtains[id].visible = not bool(routes.get(id, false))
	for id: String in _wound: _wound[id].visible = not bool(routes.get(id, false))
	for fill: Dictionary in _fills: fill.node.visible = bool(state.get("levers", {}).get(fill.lever, false))
	for id: String in _ladders:
		var ladder: Dictionary = _ladders[id]
		if ladder.wheel:
			ladder.piece.set_turning(bool(routes.get(id, false)) and not immediate)
			continue
		var hung := false
		for player: Variant in state.get("players", {}).values():
			if not player is Dictionary: continue
			var at := Vector2(float(player.x), float(player.z)) / 100.0
			var height := float(player.get("height", 0)) / 100.0
			if str(player.get("surface_id", "")) == id or (at.distance_to(ladder.foot) < FOOT_REACH and height < float(ladder.low) + 0.2): hung = true
		ladder.piece.set_pulled(not hung, immediate)
	if fog != null: fog.present(state.get("levers", {}))

func moving() -> bool:
	if _ladders.values().any(func(ladder: Dictionary) -> bool: return ladder.piece.moving()): return true
	return _platforms.any(func(entry: Dictionary) -> bool: return entry.piece.moving() or (entry.lift and float(entry.shown) != float(entry.target)))

## The one rider rule: the deck under stop `surface` as [its piece's root,
## how far that root stands from its place at the stop], or [] off a platform.
## The simulation moves a platform and all on it to its new stop in one tick
## (core/journey/simulation.gd _move_platforms); its deck eases there. So a pip,
## the live one or a memory, and an item resting on the stop are drawn that
## far from their snapshot place, moved with the root as it goes (the world's
## _carry and _advance_carriers), and an item on a pip's back rides with the pip.
func ride(surface: String) -> Array:
	if not _stops.has(surface): return []
	for entry: Dictionary in _platforms:
		var index: int = entry.stops.find(surface)
		if index >= 0: return [entry.piece.root, (entry.piece.root as Node3D).position - (entry.anchors[index] as Vector3)]
	return []

## A pip that stepped off the deck `root` (ride's) onto a floor while that deck
## is still on its way, as the simulation lets it: it waits on the deck until
## the deck reaches the stop it goes to, and the deck hurries there (HURRY), so
## the pip never hops the rest of the way nor walks through the floor's edge.
## [root, how far the root stands from that stop, the deck's half size (m)],
## or [] once the deck is there.
func ride_off(root: Node3D) -> Array:
	for entry: Dictionary in _platforms:
		if entry.piece.root != root: continue
		var anchor: Vector3 = entry.anchors[int(entry.at)]
		var away: bool = float(entry.shown) != float(entry.target) if entry.lift else not root.position.is_equal_approx(anchor)
		if not away: return []
		entry.hurry = true
		return [root, root.position - anchor, entry.half]
	return []

func advance(delta: float) -> void:
	for ladder: Dictionary in _ladders.values():
		if ladder.piece.moving(): ladder.piece.advance(delta)
	for entry: Dictionary in _platforms:
		var pace: float = HURRY if entry.hurry else 1.0
		if not entry.lift:
			if entry.piece.moving(): entry.piece.advance(delta * pace)
			if entry.piece.root.position.is_equal_approx(entry.anchors[int(entry.at)]): entry.hurry = false
		elif float(entry.shown) != float(entry.target):
			var was := float(entry.shown)
			entry.shown = move_toward(was, float(entry.target), maxf(delta, 0.0) * LIFT_RATE * pace)
			entry.piece.set_height(entry.shown)
			if float(entry.shown) == float(entry.target):
				entry.hurry = false
				entry.piece.arrive(float(entry.target) - was)
		elif entry.piece.moving(): entry.piece.advance(delta)

## The fog's slow drift at `seconds` on the world's clock (each frame unless
## motion is reduced).
func drift(seconds: float) -> void:
	if fog != null: fog.drift(seconds)
	if cover != null: cover.drift(seconds)

## The cover's clear pocket round the played pip's spirit (global m), each frame.
func follow(at: Vector3) -> void:
	if cover != null: cover.follow(at)

## The cover opened for good where the stage's pips have been (kit/turn_paths.gd):
## all of it (a new turn, a rebuilt cover), or what the turn just added.
func show_paths(paths: RefCounted) -> void:
	if cover != null: cover.show_paths(paths)

func paths_changed(change: Dictionary) -> void:
	if cover != null: cover.paths_changed(change)

## Each frame (world clock `seconds`): the cover's mask in bounded steps.
func advance_cover(delta: float, seconds: float) -> void:
	if cover != null: cover.advance(delta, seconds)

func set_quality(quality: String) -> void:
	if cover != null: cover.set_quality(quality)
## Every node that moves or changes after the build, kept whole by the static fold.
func moving_nodes() -> Array:
	var nodes: Array = []
	for entry: Dictionary in _platforms: nodes.append_array(entry.piece.moving_parts())
	for ladder: Dictionary in _ladders.values(): nodes.append_array(ladder.piece.moving_parts())
	if fog != null: nodes.append(fog.node)
	if cover != null: nodes.append(cover.node)
	nodes.append_array(_curtains.values())
	nodes.append_array(_wound.values())
	for fill: Dictionary in _fills: nodes.append(fill.node)
	return nodes

## A lift whose rising gate reads a lantern lever (the lantern pump fills the
## pan): water in each pan the same gate reads, shown while that lantern burns.
func _fill_pans(platform: Dictionary, lantern_spots: Dictionary) -> void:
	var high := str(platform.stops[platform.stops.size() - 1])
	for gate: Dictionary in _view.get("gates", []):
		if str(gate.route_id) != high: continue
		var found := {"pads": [], "levers": []}
		_terms(gate.get("when", {}), found, false)
		for lever: String in found.levers:
			if not lantern_spots.has(lever): continue
			for pad: Dictionary in _view.get("pressure_pads", []):
				if str(pad.id) not in found.pads: continue
				var water := MeshInstance3D.new()
				water.name = "PanWater_" + str(pad.id)
				var disc := CylinderMesh.new()
				disc.top_radius = float(pad.radius_cm) / 100.0 * 0.85
				disc.bottom_radius = disc.top_radius
				disc.height = 0.02
				var wet := StandardMaterial3D.new()
				wet.albedo_color = PAN_WATER
				disc.material = wet
				water.mesh = disc
				water.position = _world._at(pad) + Vector3(0, 0.1, 0)
				water.visible = false
				_world.terrain.add_child(water)
				_fills.append({"node": water, "lever": lever})

## A lift's options: its winch rope runs to the first pad its rising gate
## wants held (the power spot), when it has one.
func _drive(platform: Dictionary) -> Dictionary:
	var high := str(platform.stops[platform.stops.size() - 1])
	for gate: Dictionary in _view.get("gates", []):
		if str(gate.route_id) != high: continue
		var found := {"pads": [], "levers": []}
		_terms(gate.get("when", {}), found, false)
		for pad: Dictionary in _view.get("pressure_pads", []):
			if str(pad.id) in found.pads: return {"drive": _world._at(pad)}
	return {}

## The pads a gate wants held and the levers it wants on (not under a "not").
static func _terms(when: Dictionary, found: Dictionary, negated: bool) -> void:
	for key: String in ["all", "any"]:
		for child: Variant in when.get(key, []):
			if child is Dictionary: _terms(child, found, negated)
	if when.get("not") is Dictionary: _terms(when["not"], found, not negated)
	if negated: return
	if when.has("pad_id"): found.pads.append(str(when.pad_id))
	if when.has("lever_id"): found.levers.append(str(when.lever_id))

static func _rect(cm: Array) -> Rect2:
	return Rect2(float(cm[0]) / 100.0, float(cm[1]) / 100.0, float(int(cm[2]) - int(cm[0])) / 100.0, float(int(cm[3]) - int(cm[1])) / 100.0)
