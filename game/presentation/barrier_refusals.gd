extends RefCounted
## Where a spirit's recorded input meets a barrier, tick by tick: the step its
## stick asks for is refused by a rule the world shows as a barrier
## (presentation/kit/route_barriers.gd: an owner gate, a stair gate, a zone
## edge) and holds it back, or it stands at (or presses) a control its friend
## owns. Each screen that steps a chapter turn keeps one, starts it with the
## turn (begin) and runs every stepped tick through annotate() before the
## tick's sounds are worked out, so the snapshot carries:
##   "refused": [{slot, kind, id, push (unit Vector2, into the barrier)}], the
##     first tick a barrier holds the spirit back (and again every REPEAT_TICKS
##     while it goes on), and
##   "locked": [{slot, kind: &"lock", id}], a pip arriving at or pressing a
##     control it may not work.
## The world wiggles that barrier and bumps the spirit; the sound map plays a
## rattle or a clunk (services/chapter_sound_map.gd), named by the barrier, so
## a push sounds the same live, as the memory, on a retry and in a replay.
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
## A spirit held back by barriers bumps again after this many ticks (1 s).
const REPEAT_TICKS := 30
## Once it goes more than this many ticks (0.2 s) without being held back (it
## let go or walked off), its next bump comes at once.
const RELEASE_TICKS := 6
const STILL := {"x": 0, "z": 0, "action": false}

var _definition: Dictionary = {}
var _stage_id := ""
var _view: Dictionary = {}
var _layout: Dictionary = {}
## The memory's input per tick (quantized), and its slot ("" in a first turn).
var _memory_frames: Array = []
var _memory_slot := ""
## Whether a closed stair counts as a barrier (the descriptor's "stair_gates").
var _stair_gates := true
## Each spirit's position after the last tick: slot -> Vector2i (cm).
var _last: Dictionary = {}
## Each spirit's last bump: slot -> {tick (the bump's), held (the last tick a
## barrier held it back)}.
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
	_last.clear()
	_pushing.clear()
	_at_lock.clear()
	_held.clear()
	if not (Registry.is_cooperative(chapter_key) or Registry.is_journey(chapter_key)) or not state.has("players"): return
	_definition = definition
	_stair_gates = bool(Index.data(chapter_key).get("stair_gates", true))
	_stage(str(state.get("stage_id", "")))
	if str(state.get("role", "")) == "b" and prior is Dictionary:
		_memory_slot = str(state.get("first_player_slot", ""))
		for input: Dictionary in Runtime.expand_recording_inputs(prior): _memory_frames.append(Runtime.quantize_input(input))
	_remember(state)
	for lock: Dictionary in _layout.get("locks", []):
		var who := RouteBarriers.locked_by(lock, state.players)
		if not who.is_empty(): _at_lock[lock.id] = who

func _stage(stage_id: String) -> void:
	_stage_id = stage_id
	_view = CooperativeCatalog.stage_definition(_definition, stage_id)
	_layout = RouteBarriers.layout(_view) if not _view.is_empty() else {}

## Adds this tick's "refused" and "locked" to `state` (the snapshot the engine
## returned for `input`), in place. The caller then works out its sounds and
## shows it.
func annotate(state: Dictionary, input: Dictionary = {}) -> void:
	if _view.is_empty() or not state.get("players") is Dictionary: return
	if str(state.get("stage_id", "")) != _stage_id: _stage(str(state.get("stage_id", "")))
	var tick := int(state.get("tick", 0))
	var frames := {str(state.get("active_slot", "")): Runtime.quantize_input(input)}
	if not _memory_slot.is_empty():
		frames[_memory_slot] = _memory_frames[tick - 1] if tick - 1 >= 0 and tick - 1 < _memory_frames.size() else STILL
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
	if not refused.is_empty(): state["refused"] = refused
	if not locked.is_empty(): state["locked"] = locked

func _refused(slot: String, frame: Dictionary, player: Variant, state: Dictionary, tick: int) -> Dictionary:
	if not player is Dictionary or not _last.has(slot): return {}
	var cut := held_back(frame, _last[slot], Vector2i(int(player.x), int(player.z)))
	if cut == Vector2i.ZERO: return {}
	var into := Vector2(cut).normalized()
	var found := RouteBarriers.refusal(_view, state.get("bridges", {}), player, slot, into, Runtime.PLAYER_RADIUS, Runtime.MOVE_PER_TICK)
	if not found.is_empty() and found.kind == RouteBarriers.STAIR and not _stair_gates: found = {}
	if found.is_empty(): return {}
	var last: Variant = _pushing.get(slot)
	var bumped := last is Dictionary and tick - int(last.held) <= RELEASE_TICKS and tick - int(last.tick) < REPEAT_TICKS
	if bumped:
		last.held = tick
		return {}
	_pushing[slot] = {"tick": tick, "held": tick}
	return {"slot": slot, "kind": found.kind, "id": found.id, "push": into}

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
