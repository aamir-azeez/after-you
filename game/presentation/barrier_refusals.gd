extends RefCounted
## Where a spirit's recorded input meets a barrier, tick by tick: the step its
## stick asks for is refused by a rule the world shows as a barrier
## (presentation/kit/route_barriers.gd: an owner gate, a stair gate, a zone
## edge) and holds it back, or it stands at (or presses) a control its friend
## owns. Each screen that steps a chapter turn keeps one, starts it with the
## turn (begin) and runs every stepped tick through annotate() before the
## tick's sounds are worked out, and shows and sounds the snapshot it returns,
## which carries:
##   "refused": [{slot, kind, id, push (unit Vector2, into the barrier)}], the
##     first tick a barrier holds the spirit back (and again every REPEAT_TICKS
##     while it goes on), and
##   "locked": [{slot, kind: &"lock", id}], a pip arriving at or pressing a
##     control it may not work.
## The world wiggles that barrier and bumps the spirit; the sound map plays a
## rattle or a clunk (services/chapter_sound_map.gd), named by the barrier, so
## a push sounds the same live, as the memory, on a retry and in a replay.
## A step cut at a drop instead (water, a gap, a ledge down, the map's edge:
## drop_off()) is a "refused" event of kind RouteBarriers.EDGE, id the floor
## the pip stands on: the spirit teeters (SpiritVisual.play_teeter) with a
## small pop, and nothing wiggles. It never holds input up: the engine already
## stopped the step, and the pip walks on along the edge or away mid-wobble.
## A wall, a higher floor, a prop or a ball that will not move is neither.
##
## Held back means the engine cut at least half of the step the stick asked
## for (it slides a spirit along an edge it walks into, so a slanted push still
## moves it a little): a push straight or slanted into a gate bumps on the tick
## it meets it, while a spirit walking along an edge, brushing it, does not.
## The bump looks for the barrier along the part of the step that was cut.
##
## A memory's push is judged against the second turn's open crossings, which
## match its own turn's for owners and zones (their rules never change); a
## stair the second pip opened or kept shut can differ, so the tests compare
## owner and zone pushes only. A closed stair is no barrier in a chapter whose
## descriptor says its world draws closed stairs itself ("stair_gates": false), and a pip whose part is done (the engine
## stops moving it) pushes nothing.
##
## Presentation only. It reads the snapshots, the stage's data and the input
## each spirit's engine was given: the live spirit's from the tick, the
## memory's from its recording (expanded once a turn). Both go through the
## engine's own quantizing, so live play and a replay decide alike. Nothing
## here feeds the simulation, a recording or a checkpoint.
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
## A spirit held back by barriers bumps again after this many ticks (1 s).
const REPEAT_TICKS := 30
## Once it goes more than this many ticks (0.2 s) without being held back (it
## let go or walked off), its next bump comes at once.
const RELEASE_TICKS := 6
## A spirit held at a drop teeters again only after this many ticks (2 s), so
## leaning on the stick at the water wobbles now and then, not all the time.
const TEETER_REPEAT_TICKS := 60
const STILL := {"x": 0, "z": 0, "action": false}

var _definition: Dictionary = {}
var _stage_id := ""
var _view: Dictionary = {}
var _layout: Dictionary = {}
## The memory's input per tick (quantized), its slot ("" in a first turn) and,
## on carry-over turns, the tick of the memory's turn this one started at
## (its hand-off, core/physical/open_turns.gd): the memory's own clock runs that
## far ahead of the turn's.
var _memory_frames: Array = []
var _memory_slot := ""
var _memory_from := 0
## Whether a closed stair counts as a barrier (the descriptor's "stair_gates").
var _stair_gates := true
## Each spirit's position after the last tick: slot -> Vector2i (cm).
var _last: Dictionary = {}
## Each spirit's last bump or teeter: slot -> {tick (the bump's), held (the
## last tick a barrier or a drop held it back), edge (a teeter)}.
var _pushing: Dictionary = {}
## Who stands at each owned control now: control id -> slot.
var _at_lock: Dictionary = {}
## Whether each spirit held its press last tick: slot -> bool.
var _held: Dictionary = {}

## A turn starts at `state` (the engine's tick-zero snapshot) of chapter
## `chapter_key`, after `prior` (the memory's recording; none in a first
## turn). Chapters with no floors and crossings are left alone.
func begin(chapter_key: String, definition: Dictionary, state: Dictionary, prior: Variant) -> void:
	_definition = {}
	_view = {}
	_layout = {}
	_stage_id = ""
	_memory_frames = []
	_memory_slot = ""
	_memory_from = 0
	_last.clear()
	_pushing.clear()
	_at_lock.clear()
	_held.clear()
	if not (Registry.is_cooperative(chapter_key) or Registry.is_journey(chapter_key)) or not state.has("players"): return
	_definition = definition
	_stair_gates = bool(Index.data(chapter_key).get("stair_gates", true))
	_stage(str(state.get("stage_id", "")))
	if str(state.get("role", "")) == "b" and prior is Dictionary:
		# The friend's pip: under open turns either pip may be the live one, so the
		# memory is the other pip, whoever played the stage's first turn.
		var active := str(state.get("active_slot", ""))
		_memory_slot = str(prior.get("player_slot", "")) if str(prior.get("player_slot", "")) not in ["", active] else ("p1" if active == "p0" else "p0") if not active.is_empty() else str(state.get("first_player_slot", ""))
		_memory_from = maxi(0, int(state.get("handoff_tick", 0)))
		for input: Dictionary in Runtime.expand_recording_inputs(prior): _memory_frames.append(Runtime.quantize_input(input))
	_remember(state)
	for lock: Dictionary in _layout.get("locks", []):
		var who := RouteBarriers.locked_by(lock, state.players)
		if not who.is_empty(): _at_lock[lock.id] = who

func _stage(stage_id: String) -> void:
	_stage_id = stage_id
	_view = CooperativeCatalog.stage_definition(_definition, stage_id)
	_layout = RouteBarriers.layout(_view) if not _view.is_empty() else {}

## `state` (the snapshot the engine returned for `input`) with this tick's
## "refused" and "locked": `state` itself when there are none, else a shallow
## copy that adds them. It only reads `state`, which the engine (or a replay)
## may keep. The caller then works out its sounds from it and shows it.
func annotate(state: Dictionary, input: Dictionary = {}) -> Dictionary:
	if _view.is_empty() or not state.get("players") is Dictionary: return state
	if str(state.get("stage_id", "")) != _stage_id: _stage(str(state.get("stage_id", "")))
	var tick := int(state.get("tick", 0))
	var frames := {str(state.get("active_slot", "")): Runtime.quantize_input(input)}
	if not _memory_slot.is_empty():
		var at := tick - 1 + _memory_from
		frames[_memory_slot] = _memory_frames[at] if at >= 0 and at < _memory_frames.size() else STILL
	var players: Dictionary = state.players
	var refused: Array = []
	for slot: String in frames:
		var done: bool = slot == str(state.get("active_slot", "")) and bool(state.get("objective_done", false))
		var event := {} if done else _refused(slot, frames[slot], players.get(slot), state, tick)
		if not event.is_empty(): refused.append(event)
	var locked: Array = []
	for lock: Dictionary in _layout.get("locks", []):
		var who := RouteBarriers.locked_by(lock, players)
		if who.is_empty():
			_at_lock.erase(lock.id)
			continue
		var frame: Dictionary = frames.get(who, STILL)
		var pressed := bool(frame.action) and not bool(_held.get(who, false))
		if _at_lock.get(lock.id, "") != who or pressed: locked.append({"slot": who, "kind": RouteBarriers.LOCK, "id": lock.id})
		_at_lock[lock.id] = who
	for slot: String in frames: _held[slot] = bool(frames[slot].action)
	_remember(state)
	if refused.is_empty() and locked.is_empty(): return state
	var shown := state.duplicate()
	if not refused.is_empty(): shown["refused"] = refused
	if not locked.is_empty(): shown["locked"] = locked
	return shown

func _refused(slot: String, frame: Dictionary, player: Variant, state: Dictionary, tick: int) -> Dictionary:
	if not player is Dictionary or not _last.has(slot): return {}
	var cut := held_back(frame, _last[slot], Vector2i(int(player.x), int(player.z)))
	if cut == Vector2i.ZERO: return {}
	var into := Vector2(cut).normalized()
	var found := RouteBarriers.refusal(_view, state.get("bridges", {}), player, slot, into, Runtime.PLAYER_RADIUS, Runtime.MOVE_PER_TICK)
	if not found.is_empty() and found.kind == RouteBarriers.STAIR and not _stair_gates: found = {}
	var edge := found.is_empty()
	if edge:
		if not drop_off(_view, state.get("bridges", {}), player, into, Runtime.PLAYER_RADIUS, Runtime.MOVE_PER_TICK): return {}
		found = {"kind": RouteBarriers.EDGE, "id": str(player.get("surface_id", ""))}
	var last: Variant = _pushing.get(slot)
	var repeat := TEETER_REPEAT_TICKS if edge else REPEAT_TICKS
	var bumped := last is Dictionary and bool(last.edge) == edge and tick - int(last.held) <= RELEASE_TICKS and tick - int(last.tick) < repeat
	if bumped:
		last.held = tick
		return {}
	_pushing[slot] = {"tick": tick, "held": tick, "edge": edge}
	return {"slot": slot, "kind": found.kind, "id": found.id, "push": into}

## Whether what stops a step from `player` (cm) along `push` (a unit Vector2)
## is a drop: walking out from the spirit's edge (its centre stops `radius`
## short of it) up to one `step` past, the first ground that is not its own
## floor's height is lower or none at all (water, a gap, a shut crossing, the
## map's edge). A higher floor, a stair going up or an obstacle on its floor
## there is a wall; ground at its height all the way (a prop, a ball) is
## neither. Reads only stage data and `routes` (the snapshot's open
## crossings), like RouteBarriers.refusal.
static func drop_off(view: Dictionary, routes: Dictionary, player: Dictionary, push: Vector2, radius: int, step: int) -> bool:
	var at := Vector2(float(player.x), float(player.z))
	var height := int(player.get("height", 0))
	for reach: int in [radius + 2, radius + int(step * 0.5), radius + step]:
		var point := Vector2i((at + push * float(reach)).round())
		var ground := _ground(view, routes, point, height, str(player.get("surface_id", "")))
		if ground == 0: continue
		return ground < 0
	return false

## At `point` (cm), against floor height `height`: 0 for ground at that
## height, 1 for higher ground or an obstacle on floor `surface` (a wall), -1
## for lower ground or none.
static func _ground(view: Dictionary, routes: Dictionary, point: Vector2i, height: int, surface: String) -> int:
	var found := -1
	for obstacle: Dictionary in view.get("obstacles", []):
		if str(obstacle.get("surface_id", "")) == surface and Navigation.inside(point, obstacle.rect_cm): return 1
	for island: Dictionary in view.get("islands", []):
		if Navigation.inside(point, island.rect_cm): found = maxi(found, _against(int(island.height_cm), height))
	for bridge: Dictionary in view.get("bridges", []):
		if bool(routes.get(str(bridge.id), false)) and Navigation.inside(point, bridge.rect_cm): found = maxi(found, _against(int(bridge.height_cm), height))
	for stair: Dictionary in view.get("stairs", []):
		if Navigation.inside(point, stair.rect_cm): found = maxi(found, _against(Navigation.stair_height(stair, point), height))
	return found

static func _against(ground: int, height: int) -> int:
	if absi(ground - height) <= 2: return 0
	return 1 if ground > height else -1

## The part (cm) of the step `frame` (quantized input) asked for that the
## engine cut, from `from` to `to` (a spirit's positions, cm), when it is at
## least half the step; else zero. The asked step is the engine's own
## (core/physical/runtime.gd _move), in whole centimetres. A spirit moved
## further than its step (carried, caught after a fall) was not held back.
static func held_back(frame: Dictionary, from: Vector2i, to: Vector2i) -> Vector2i:
	var direction := Vector2(float(frame.x), float(frame.z)).limit_length(100.0)
	var asked := Vector2i(roundi(direction.x * Runtime.MOVE_PER_TICK / 100.0), roundi(direction.y * Runtime.MOVE_PER_TICK / 100.0))
	if asked == Vector2i.ZERO or (to - from).length_squared() > asked.length_squared(): return Vector2i.ZERO
	var cut := asked - (to - from)
	return cut if 4 * cut.length_squared() >= asked.length_squared() else Vector2i.ZERO

func _remember(state: Dictionary) -> void:
	var players: Dictionary = state.get("players", {})
	for slot: Variant in players:
		var player: Variant = players[slot]
		if player is Dictionary and player.has("x"): _last[str(slot)] = Vector2i(int(player.x), int(player.z))
