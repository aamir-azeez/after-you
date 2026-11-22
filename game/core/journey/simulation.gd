class_name AfterYouJourneySimulation
extends "res://core/physical/runtime.gd"
## A separate sealed ruleset. Published simulation6 never selects this facade.
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const BeamField = preload("res://core/beam_field.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const Swings = preload("res://core/physical/swings.gd")
const CURRENT_SIMULATION_VERSION := 7
const COMFORT_VERSION := 8
## Comfort rules under a new number, as in the cooperative ruleset. Only a
## definition that declares it ("simulation_version": 9) plays it, and it then
## plays nothing else; 7 and 8 stay exactly as published.
const COMFORT_ALIAS_VERSION := 9
## Tide rules: comfort rules (8 and 9) where nothing stays open because it once
## was. A crossing whose gate stops holding stays walkable for the
## definition's "closing_ticks", then shuts; a spirit standing on a shut
## crossing then drowns and the turn ends there. A completed stage keeps no
## routes for the next one. Only a definition that pins 10 plays them.
## A stepping stone its water leaves standing too tall (stage_catalog.gd
## tall_stones) drowns no one: a spirit on it as it shuts stays up there, one
## that walks off it or onto it falls, and the turn ends as a drowning does.
const TIDE_RULES_VERSION := 10
## Open controls (core/physical/open_controls.gd): the comfort rules (9) with
## open controls are 12, the tide rules (10) with open controls 13. Only a
## definition that pins one plays it; every other number keeps owner rules
## exactly as published.
const OPEN_TIDE_RULES_VERSION := OpenControls.OPEN_TIDE_RULES_VERSION
const TIDE_RULES := OpenControls.TIDE_RULES
const OPEN_RULES := OpenControls.OPEN_RULES
## What a drowned, fallen or dropped turn says is runtime.gd's DROWNED_YOU,
## DROWNED_FRIEND, FELL_YOU, FELL_FRIEND, DROPPED_YOU and DROPPED_FRIEND.
## A turn that would end with a spirit left high on a stone.
const LEFT_HIGH := "A pip is stuck up on the stones."
## A turn that would end with a spirit on a closing crossing.
const ON_CLOSING := "Step off the crossing before it shuts."
var _entry_latches: Dictionary = {}
## Tide rules: route id -> the tick its crossing shuts, while it closes.
var _closing: Dictionary = {}
## Tide rules: slot -> where that spirit stood, left high on a stone, as the
## last tick ended. (Who drowned or fell is runtime.gd's _drowned, with
## "fell": true when it fell off a stone left high instead.)
var _high: Dictionary = {}
var _ready_branch := ""
## The pieces rules' carried items and currents (core/physical/carried_items.gd),
## set at reset: whether they play, the items in order, the crossings that
## need both hands and each item's last leg ("control=value": it takes no
## other leg on that wheel value until the wheel turns or a pip handles it).
var _carrying := false
var _item_order: Array = []
var _hands: Dictionary = {}
var _legs_taken: Dictionary = {}
## The pieces rules' throws (carried_items.gd), set at reset: the stage's throws by
## id, and each item in flight: {"throw": its id, "from": {x, z, height},
## "left": ticks}.
var _throws: Dictionary = {}
var _flights: Dictionary = {}
var _optics: Dictionary = {"segments":[],"signals":{}}
## Fixed once a reset sets the level and stage (_reset_mechanics): every
## bridge and stair in order, and each gate's route with its condition (null
## when it has none, which always holds). _refresh_routes runs three times a
## tick, so it reads these instead of building them again.
var _route_defs: Array = []
var _gate_plan: Array = []
## The pieces rules (core/physical/pieces_rules.gd), fixed at reset: the stage's
## platforms as [platform, [stop bridges], whether it is a lift], every stop id
## with its platform's place in that list, the sinking stones, and each pip's
## surface as the tick began (who stepped onto a stone last).
var _platforms: Array = []
var _stops: Dictionary = {}
## The pieces rules: each deck still on its way to the stop its platform
## stands at, by platform id: {"from": [x, z, height] cm where it set off,
## "done": ticks travelled, "ticks": the whole way} (PiecesRules.deck_ticks).
## A deck at its stop has none.
var _decks: Dictionary = {}
var _sinking: Array = []
var _surfaces_before: Dictionary = {}
## The pieces rules' swings (core/physical/swings.gd), set at reset: the
## stage's swings in order, each one's beat counter by id (world state), and
## whether its brake held this tick (for the screen).
var _swing_plan: Array = []
var _swing_counts: Dictionary = {}
var _swing_braked: Dictionary = {}

func _init() -> void:
	simulation_version = CURRENT_SIMULATION_VERSION

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", rules_version: int = 0, chain: Array = []) -> bool:
	if rules_version == 0:
		rules_version = _record_version(prior_a) if current_role == "b" else _checkpoint_version(checkpoint, definition)
	if not rules_allowed(definition, rules_version) or (current_role == "b" and prior_a.get("simulation_version") != rules_version):
		error = "Unsupported recording version."
		return false
	simulation_version = rules_version
	return super.reset(definition, stage_id, checkpoint, prior_a, current_role, rules_version, chain)

func _schema_version() -> int:
	return CURRENT_SIMULATION_VERSION

func _new_simulation() -> RefCounted:
	return AfterYouJourneySimulation.new()

func _proof_engine() -> RefCounted:
	return _proof(simulation_version)

static func _proof(version: int = CURRENT_SIMULATION_VERSION) -> RefCounted:
	return Proof.new(Catalog, AfterYouJourneySimulation, version, CURRENT_SIMULATION_VERSION)

static func rules_allowed(definition: Dictionary, rules_version: int) -> bool:
	var pinned := pinned_rules(definition)
	return (rules_version == pinned if pinned > 0 else rules_version in [CURRENT_SIMULATION_VERSION, COMFORT_VERSION]) and turn_limits_valid(definition, rules_version)

static func pinned_rules(definition: Dictionary) -> int:
	var declared: Variant = definition.get("simulation_version")
	return int(declared) if (declared is int or declared is float) and int(declared) >= COMFORT_ALIAS_VERSION else 0

static func _record_version(record: Dictionary) -> int:
	# JSON numbers arrive as floats.
	var declared: Variant = record.get("simulation_version")
	if declared is int or declared is float:
		if declared == COMFORT_VERSION: return COMFORT_VERSION
		if declared == COMFORT_ALIAS_VERSION: return COMFORT_ALIAS_VERSION
		if declared == TIDE_RULES_VERSION: return TIDE_RULES_VERSION
		if declared == OPEN_RULES_VERSION: return OPEN_RULES_VERSION
		if declared == OPEN_TIDE_RULES_VERSION: return OPEN_TIDE_RULES_VERSION
		if declared == OpenControls.OPEN_TURNS_RULES_VERSION: return OpenControls.OPEN_TURNS_RULES_VERSION
		if declared == OpenControls.OPEN_TURNS_TIDE_RULES_VERSION: return OpenControls.OPEN_TURNS_TIDE_RULES_VERSION
		if declared == OpenControls.PIECES_RULES_VERSION: return OpenControls.PIECES_RULES_VERSION
	return CURRENT_SIMULATION_VERSION

static func _checkpoint_version(checkpoint: Dictionary, definition: Dictionary = {}) -> int:
	var proof: Variant = checkpoint.get("proof", {})
	if proof is Dictionary and proof.get("a", {}) is Dictionary and not proof.get("a", {}).is_empty(): return _record_version(proof.a)
	# Open turns nest a stage's turns as a list (open_turns.gd).
	if proof is Dictionary and proof.get("turns") is Array and not proof.turns.is_empty() and proof.turns[0] is Dictionary: return _record_version(proof.turns[0])
	var pinned := pinned_rules(definition)
	return pinned if pinned > 0 else CURRENT_SIMULATION_VERSION

func _reset_mechanics() -> void:
	_reset_items()
	_route_defs = level.get("bridges", []) + level.get("stairs", [])
	_gate_plan = []
	for gate: Dictionary in stage.get("gates", []):
		var when: Dictionary = gate.get("when", {})
		_gate_plan.append([gate.route_id, null if when.is_empty() else when])
	_entry_latches = {}
	_closing = {}
	_drowned = {}
	_high = {}
	_ready_branch = ""
	_optics = {"segments":[],"signals":{}}
	_platforms = []
	_stops = {}
	_decks = {}
	_sinking = []
	_surfaces_before = {}
	_swing_plan = []
	_swing_counts = {}
	_swing_braked = {}
	if _pieces_rules():
		_swing_plan = stage.get("swings", [])
		for swing: Dictionary in _swing_plan: _swing_counts[str(swing.id)] = 0
		var bridges: Dictionary = {}
		for bridge: Dictionary in level.get("bridges", []): bridges[bridge.id] = bridge
		for platform: Dictionary in stage.get("platforms", []):
			var stops: Array = []
			for id: Variant in platform.stops:
				stops.append(bridges[str(id)])
				_stops[str(id)] = _platforms.size()
			_platforms.append([platform, stops, stops.all(func(stop: Dictionary) -> bool: return stop.rect_cm == stops[0].rect_cm)])
		for id: Variant in stage.get("sinking", []): _sinking.append(str(id))

## The pieces rules: each pip's surface as the tick began (who stepped onto a
## stone last), and each travelling deck a tick further along.
func _before_moves() -> void:
	if not _pieces_rules(): return
	_surfaces_before = {"p0": str(_players.p0.surface_id), "p1": str(_players.p1.surface_id)}
	for id: String in _decks.keys():
		_decks[id].done = int(_decks[id].done) + 1
		if int(_decks[id].done) >= int(_decks[id].ticks): _decks.erase(id)

func _advance_source() -> void:
	super._advance_source()
	# A evolves independently. Copy only its declared controls, never B's local
	# selector, shutter, entry latches, or future changed source ownership.
	# Open controls: copy a control only on a tick the memory turned it.
	var open := _open_controls()
	for control: Dictionary in stage.get("controls", []):
		if open:
			if _source_toggles.controls.has(control.id): _mechanisms.controls[control.id] = _source._mechanisms.controls[control.id]
		elif control.owner_slot == first_player_slot:
			_mechanisms.controls[control.id] = _source._mechanisms.controls[control.id]
	_ready_branch = _source._ready_branch

func _refresh_routes() -> void:
	_refresh_optics()
	var was: Dictionary = _routes.duplicate() if _closes_slowly() else {}
	for route: Dictionary in _route_defs:
		_routes[route.id] = route.id in _mechanisms.latched_bridges or bool(_entry_latches.get(route.id, false))
	var open := _open_controls()
	for gate: Array in _gate_plan:
		_routes[gate[0]] = bool(_routes.get(gate[0], false)) or gate[1] == null or Seven.predicate(gate[1], stage, _players, _mechanisms, _optics.signals, open)
	if not _platforms.is_empty(): _move_platforms(was)
	if _closes_slowly(): _close_slowly(was)

## The pieces rules: each platform stands at the one stop whose gate holds,
## or where it stood when none or several do (its first stop at the start).
## When it moves, every pip on the old stop rides along to the same spot on
## the new one, both pips alike, and so does every item put down on it, while
## the deck sets off from wherever it is (_decks).
func _move_platforms(was: Dictionary) -> void:
	for entry: Array in _platforms:
		var stops: Array = entry[1]
		var holding: Array = stops.filter(func(stop: Dictionary) -> bool: return bool(_routes.get(stop.id, false)))
		var before: Dictionary = {}
		for stop: Dictionary in stops:
			if bool(was.get(stop.id, false)): before = stop
		var at: Dictionary = holding[0] if holding.size() == 1 else before if not before.is_empty() else holding[0] if not holding.is_empty() else stops[0]
		for stop: Dictionary in stops: _routes[stop.id] = stop.id == at.id
		if before.is_empty() or before.id == at.id: continue
		var from := _deck_now(entry, before)
		var ticks := PiecesRules.deck_ticks(from, _corner(at), bool(entry[2]))
		if ticks > 0: _decks[str(entry[0].id)] = {"from": from, "done": 0, "ticks": ticks}
		else: _decks.erase(str(entry[0].id))
		var rode := false
		for slot: String in ["p0", "p1"]:
			if str(_players[slot].surface_id) != str(before.id): continue
			_players[slot] = _shifted(_players[slot], before, at)
			rode = true
		for id: String in _item_order:
			var item: Dictionary = _mechanisms.items[id]
			if not str(item.holder).is_empty() or str(item.surface_id) != str(before.id): continue
			_mechanisms.items[id] = _shifted(item, before, at)
			rode = true
		if rode: _events.append("rode:" + str(entry[0].id))

## Where the deck of platform `entry` stands now, [x, z, height] cm of its
## corner: on its way to stop `at` (the stop it stands at), or there.
func _deck_now(entry: Array, at: Dictionary) -> Array:
	var deck: Dictionary = _decks.get(str(entry[0].id), {})
	return _corner(at) if deck.is_empty() else PiecesRules.deck_at(deck.from, _corner(at), int(deck.done), int(deck.ticks))

static func _corner(stop: Dictionary) -> Array:
	return [int(stop.rect_cm[0]), int(stop.rect_cm[1]), int(stop.height_cm)]

## The pieces rules: a pip steps between a platform's stop and anything else
## only while the deck stands within a step (Navigation.STEP_CM, as at any
## ledge) of the stop and of the floor it steps from or to, measured from
## where the deck is this tick. So riders stay on until it gets there, and no
## pip boards a deck still on its way, the live pip and the friend's replay
## alike.
func _may_step(previous: Dictionary, position: Dictionary) -> bool:
	var left := str(previous.surface_id)
	var reached := str(position.surface_id)
	if _platforms.is_empty() or left == reached: return true
	return _deck_meets(left, int(position.height)) and _deck_meets(reached, int(previous.height))

## Whether `surface`, when it is a platform's stop, has its deck there, within a
## step of `height`.
func _deck_meets(surface: String, height: int) -> bool:
	if not _stops.has(surface): return true
	var entry: Array = _platforms[int(_stops[surface])]
	var stop: Dictionary = entry[1].filter(func(each: Dictionary) -> bool: return str(each.id) == surface)[0]
	var deck := _deck_now(entry, stop)
	var corner := _corner(stop)
	return absi(int(deck[0]) - int(corner[0])) <= Navigation.STEP_CM and absi(int(deck[1]) - int(corner[1])) <= Navigation.STEP_CM and absi(int(deck[2]) - height) <= Navigation.STEP_CM

## `player` (a pip, or an item resting loose) moved from platform stop `from`
## to the same spot on stop `to`.
static func _shifted(player: Dictionary, from: Dictionary, to: Dictionary) -> Dictionary:
	var moved := player.duplicate()
	moved.x = int(player.x) - int(from.rect_cm[0]) + int(to.rect_cm[0])
	moved.z = int(player.z) - int(from.rect_cm[1]) + int(to.rect_cm[1])
	moved.height = int(to.height_cm)
	moved.surface_id = str(to.id)
	return moved

func _tide_rules() -> bool:
	return simulation_version in TIDE_RULES

func _open_controls() -> bool:
	return simulation_version in OPEN_RULES

func _pieces_rules() -> bool:
	return PiecesRules.on(simulation_version)

## Whether a crossing whose gate lets go keeps its floor a while first: the
## tide rules, and every open turns level (runtime.gd CLOSING_GRACE_TICKS).
func _closes_slowly() -> bool:
	return _tide_rules() or _open_turns()

## How long a closing crossing keeps its floor: under open turns the one
## shared grace, else the definition's "closing_ticks".
func _grace_ticks() -> int:
	return CLOSING_GRACE_TICKS if _open_turns() else int(level.get("closing_ticks", 0))

## A crossing that was open and whose gate no longer holds keeps its floor
## until _grace_ticks() after the tick it started closing, then shuts; the
## worlds flash its edges meanwhile (kit/closing_warning.gd, from the
## snapshot's route_progress.closing). Holding again in the meantime, it
## simply stays open.
func _close_slowly(was: Dictionary) -> void:
	for id: String in _routes:
		# The pieces rules: a platform's stop is wherever the platform stands, at once.
		if _stops.has(id): continue
		if _routes[id]:
			_closing.erase(id)
		elif _closing.has(id):
			if tick < int(_closing[id]): _routes[id] = true
			else: _closing.erase(id)
		elif bool(was.get(id, false)) and _grace_ticks() > 0:
			_closing[id] = tick + _grace_ticks()
			_routes[id] = true
			_events.append("closing:" + id)

## Tide rules: a spirit standing on a crossing that is now shut drowns, the
## player's own or the memory's, and the turn ends. On a stone left high it
## stays up there; walking off it, or onto it, it falls where it stood, and
## the turn ends the same way. The pieces rules first: a carrier on a
## both-hands crossing drops its item (_drop_on_hands).
func _check_hazards() -> void:
	if not _swing_plan.is_empty(): _advance_swings()
	if _carrying and not _hands.is_empty() and _drowned.is_empty(): _drop_on_hands()
	if not _tide_rules() or not _drowned.is_empty(): return
	for slot: String in ["p0", "p1"]:
		var surface := str(_players[slot].surface_id)
		var stood: Dictionary = _high.get(slot, {})
		if not _walked(slot) or not (_left_high(surface) or (not stood.is_empty() and _left_high(str(stood.surface_id)))): continue
		if not stood.is_empty(): _players[slot] = stood
		_drowned = {"slot": slot, "route": str(_players[slot].surface_id), "tick": tick, "fell": true}
		finished = true
		_events.append("fell:" + slot)
		return
	_high = {}
	for slot: String in ["p0", "p1"]:
		var surface := str(_players[slot].surface_id)
		if _left_high(surface):
			_high[slot] = _players[slot].duplicate()
		elif _routes.has(surface) and not bool(_routes[surface]):
			_drowned = {"slot": slot, "route": surface, "tick": tick}
			finished = true
			_events.append("drowned:" + slot)
			return
	# The pieces rules: a sinking stone holds one pip. The one that stepped on last
	# pushes it under (the live pip when both stepped on this tick).
	var stone := str(_players.p0.surface_id)
	if stone in _sinking and stone == str(_players.p1.surface_id):
		var slot := active_slot
		if str(_surfaces_before.get(active_slot, "")) == stone and str(_surfaces_before.get(memory_slot, "")) != stone: slot = memory_slot
		_drowned = {"slot": slot, "route": stone, "tick": tick}
		finished = true
		_events.append("sank:" + stone)
		_events.append("drowned:" + slot)
		return
	# The pieces rules: a swing across its lane knocks off a pip standing in it, p0 first.
	for swing: Dictionary in _swing_plan:
		if not Swings.sweeping(swing, int(_swing_counts[str(swing.id)])): continue
		for slot: String in ["p0", "p1"]:
			if not Swings.in_lane(swing, _players[slot]): continue
			_drowned = {"slot": slot, "route": str(swing.lane.surface_id), "tick": tick, "swing": str(swing.id)}
			finished = true
			_events.append("knocked:" + str(swing.id))
			_events.append("drowned:" + slot)
			return

## The pieces rules: each swing's beat moves on a tick, unless its brake holds
## while it hangs back (core/physical/swings.gd). Says when one starts to creak
## and when it swings.
func _advance_swings() -> void:
	for swing: Dictionary in _swing_plan:
		var id := str(swing.id)
		var braked: bool = swing.has("brake") and Seven.predicate(swing.brake, stage, _players, _mechanisms, _optics.signals, _open_controls())
		var count := int(_swing_counts[id])
		var next := Swings.next_count(swing, count, braked)
		_swing_counts[id] = next
		_swing_braked[id] = braked
		if next == count: continue
		var at := Swings.phase(swing, next)
		var sweep_from := int(swing.period_ticks) - int(swing.sweep_ticks)
		if at == sweep_from: _events.append("swing:" + id)
		elif int(swing.warn_ticks) > 0 and at == sweep_from - int(swing.warn_ticks): _events.append("swing_creak:" + id)

## Tide rules: whether crossing `id` is a stepping stone shut and left standing
## too tall by its water.
func _left_high(id: String) -> bool:
	return _routes.has(id) and not bool(_routes[id]) and Catalog.left_high(level, id, _mechanisms.controls)

## Open turns: a pip on a stepping stone its water left standing too tall
## stays up there as the stone shuts (_check_hazards decides what follows),
## instead of stepping back or falling (runtime.gd _keep_footing).
func _stands_fast(slot: String) -> bool:
	return _tide_rules() and _left_high(str(_players[slot].surface_id))

## Whether `slot` walks this tick: the live pip by its input, the friend's by
## its recorded one (a step _move would take): on open turns the friend's
## replay from the hand-off, before them the memory's own turn.
func _walked(slot: String) -> bool:
	var frame: Variant = null
	if slot == active_slot: frame = _actions.back() if not _actions.is_empty() else null
	elif role == "b" and _open_turns(): frame = _friend_frame()
	elif role == "b" and tick < _prior_frames.size(): frame = quantize_input(_prior_frames[tick])
	if not frame is Dictionary: return false
	var direction := Vector2(float(frame.x), float(frame.z)).limit_length(100.0)
	return Vector2i(roundi(direction.x * MOVE_PER_TICK / 100.0), roundi(direction.y * MOVE_PER_TICK / 100.0)) != Vector2i.ZERO

func _keeps_routes_at_completion() -> bool:
	return not _tide_rules()

## Tide rules: a turn never ends with a spirit on a crossing that is still
## closing. The first turn cannot be saved then, and the second runs on until
## the crossing shuts (and the spirit drowns) or holds again, so every saved
## end has both spirits on open floor.
func _on_closing() -> bool:
	return _closes_slowly() and (_closing.has(str(_players.p0.surface_id)) or _closing.has(str(_players.p1.surface_id)))

func _may_complete() -> bool:
	# The pieces rules: never while an item flies, so a checkpoint never holds one.
	return not _on_closing() and _high.is_empty() and _source_holds() and _flights.is_empty()

## Open turns: a turn never passes with a spirit on a closing crossing, left
## high or drowned.
func _may_pass() -> bool:
	return not _on_closing() and _high.is_empty() and _drowned.is_empty()

## Open turns: the goal holds for a pip only while the goal's light holds.
func _at_goal(slot: String) -> bool:
	return super._at_goal(slot) and Seven.predicate(stage.goal_policy.get("when", {}), stage, _players, _mechanisms, _optics.signals, _open_controls())

## Open controls: the live pip may undo the first turn's part (a selector its
## readiness needs, the pad its choice stands on), so a stage completes only
## while that part still holds on the live state, as the server's checkpoint
## asks. Owner rules copy the memory's controls, so it always holds there.
## Open turns have no such part: both pips at the goal is the finish.
func _source_holds() -> bool:
	if not _open_controls() or _open_turns(): return true
	var policy: Dictionary = stage.source_policy
	if policy.kind == "choice_pad": return not Seven.choice(stage, _players, true).is_empty()
	if policy.kind in ["route_endpoint", "signal_route"]:
		return Seven.predicate(policy.get("when", {}), stage, _players, _mechanisms, _optics.signals, true) and (not policy.has("endpoint") or Seven.near(_players[first_player_slot], policy.endpoint))
	return true

func _refresh_optics() -> void:
	if not stage.has("optical_field"):
		_optics={"segments":[],"signals":{}}
		return
	var overrides: Dictionary={}
	for control: Dictionary in stage.get("controls",[]):
		if control.kind=="mirror": overrides[control.id]={"orientation":str(_mechanisms.controls[control.id])}
	_optics=BeamField.evaluate(stage.optical_field,overrides)
	if not _optics.valid: error=str(_optics.error)

## `slot`: the pip that walked; open turns latch for either pip in every turn.
func _after_move(slot: String = "") -> void:
	if slot.is_empty(): slot = active_slot
	if role != "b" and not _open_turns(): return
	var player: Dictionary = _players[slot]
	var point := Vector2i(player.x, player.z)
	var diagonal := int(ceil(float(PLAYER_RADIUS)*0.707107))
	var samples := [Vector2i.ZERO,Vector2i(PLAYER_RADIUS,0),Vector2i(-PLAYER_RADIUS,0),Vector2i(0,PLAYER_RADIUS),Vector2i(0,-PLAYER_RADIUS),Vector2i(diagonal,diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,-diagonal)]
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if route.id not in stage.get("entry_latch_routes", []) or not bool(_routes.get(route.id, false)) or not Navigation._owns(route, slot): continue
		for offset: Vector2i in samples:
			var sample := point+offset
			if not Navigation.inside(sample,route.rect_cm): continue
			var height: int = Navigation.stair_height(route,sample) if route.has("axis") else int(route.height_cm)
			if absi(height-int(player.height)) <= PLAYER_RADIUS+1:
				_entry_latches[route.id] = true
				break

func _context_for(slot: String) -> Dictionary:
	if level.is_empty(): return _action("", "", false, "")
	for control: Dictionary in stage.get("controls", []):
		if (_open_controls() or control.owner_slot == slot) and Seven.near(_players[slot],control):
			return _action("selector", "Turn mirror" if control.kind=="mirror" else "Turn switch", true, control.id)
	var inherited := super._context_for(slot)
	if inherited.id == "ring" and level.id == "long-way-home": inherited.label = "Light window"
	if inherited.id == "ring" and level.id == "conservatory": inherited.label = "Light garden"
	# Stage one of the harbour keeps its bell; only the second stage is a lantern.
	if inherited.id == "ring" and level.id == "turn-of-the-tide" and stage.id == "slack-water": inherited.label = "Light lantern"
	if inherited.id == "ring" and not Seven.predicate(stage.goal_policy.get("when", {}),stage,_players,_mechanisms,_optics.signals,_open_controls()):
		inherited.enabled = false
	if _carrying and str(inherited.id).is_empty(): return _item_action(slot)
	return inherited

func _objective_display() -> Dictionary:
	var value := super._objective_display()
	if role == "b" and level.id == "long-way-home": value.label = "Window"
	if role == "b" and level.id == "conservatory": value.label = "Garden light"
	if role == "b" and level.id == "turn-of-the-tide" and stage.id == "slack-water": value.label = "Lantern"
	# Open turns have no bell to ring: a bell goal shows no card, and its beacon marks the place.
	if role == "b" and _open_turns() and value.get("label") == "Bell": return {}
	return value

## Snapshot text only. A harbour hold that began too late to leave the partner
## their budget says so, instead of the generic "keep the crossing ready".
func commit_reason() -> String:
	var lost := _lost_reason()
	if not lost.is_empty(): return lost
	if _on_closing(): return ON_CLOSING
	if not _high.is_empty(): return LEFT_HIGH
	if level.get("id", "") == "turn-of-the-tide" and error.is_empty() and role == "a" and not can_commit() and not _ready_branch.is_empty() and _hold_start >= 0 and _hold_start + source_budget_ticks() >= receiver_deadline():
		return "Try again with more time left for your partner."
	return super.commit_reason()

func _interact(slot: String = "") -> void:
	if slot.is_empty(): slot = active_slot
	var action := _context_for(slot)
	if _carrying and action.id in CarriedItems.ACTS:
		_item_act(action, slot)
		return
	if action.id != "selector":
		super._interact(slot)
		return
	if not action.enabled: return
	var control := _entity(stage.controls, str(action.target_id))
	var values: Array = control.values
	var index := values.find(_mechanisms.controls[control.id])
	_mechanisms.controls[control.id] = values[(index+1)%values.size()]
	_events.append("selector:"+control.id)

func _update_source_readiness() -> void:
	var policy: Dictionary=stage.source_policy
	var branch := ""
	if policy.kind in ["route_endpoint","signal_route"]:
		var endpoint_ok:=not policy.has("endpoint") or Seven.near(_players[first_player_slot],policy.endpoint)
		if Seven.predicate(policy.when,stage,_players,_mechanisms,_optics.signals,_open_controls()) and endpoint_ok: branch="endpoint"
	elif policy.kind == "choice_pad":
		var selected := Seven.choice(stage,_players,_open_controls())
		if not selected.is_empty(): branch=str(selected.id)
	if branch.is_empty():
		_hold_start=-1
		_hold_ticks=0
	elif _ready_branch != branch or _hold_start<0:
		_hold_start=tick
		_hold_ticks=1
	else:
		_hold_ticks+=1
	_ready_branch=branch

func source_budget_ticks() -> int:
	if level.is_empty(): return MAX_TICKS
	var selected: Dictionary=stage
	if stage.source_policy.kind=="choice_pad":
		selected=Seven.choice(stage,_players,_open_controls())
		if selected.is_empty(): return MAX_TICKS
	var point:=Vector2i(_checkpoint.players[_other(first_player_slot)].x,_checkpoint.players[_other(first_player_slot)].z)
	var budget:=int(selected.get("receiver_action_ticks",0))+40+(90 if _comfort_rules() else 0)
	for coords: Array in selected.receiver_route_cm:
		var next:=Vector2i(coords[0],coords[1])
		budget+=ceili(float(absi(next.x-point.x))/MOVE_PER_TICK)+ceili(float(absi(next.y-point.y))/MOVE_PER_TICK)
		point=next
	return budget

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick==0 or not _drowned.is_empty() or _on_closing() or not _high.is_empty(): return false
	if role=="b": return complete
	# Open turns: a first turn may end at any time (runtime.gd can_commit).
	return _open_turns() or _source_ready()

func _source_ready() -> bool:
	return not _ready_branch.is_empty() and _hold_start>=0 and _hold_start+source_budget_ticks()<receiver_deadline()

func snapshot() -> Dictionary:
	var value:=super.snapshot()
	if not level.is_empty():
		value["controls"]=_mechanisms.controls.duplicate()
		value.route_progress["entered_routes"]=_sorted_latches()
		value["source_branch"]=_ready_branch
		value["optics"]=_optics.duplicate(true)
		if _closes_slowly():
			# Ticks left before each closing crossing shuts, and who drowned.
			var closing: Dictionary = {}
			for id: String in _closing: closing[id] = int(_closing[id]) - tick
			value.route_progress["closing"]=closing
			value["drowned"]=_drowned.duplicate()
		# The pieces rules: where each swing is in its beat.
		if not _swing_plan.is_empty():
			var swings: Dictionary = {}
			for swing: Dictionary in _swing_plan: swings[str(swing.id)] = Swings.view(swing, int(_swing_counts[str(swing.id)]), bool(_swing_braked.get(str(swing.id), false)))
			value["swings"]=swings
		# The pieces rules: what each pip carries on its back.
		if _carrying:
			for slot: String in value.players: value.players[slot]["carrying"]=CarriedItems.held_by(_mechanisms.items,slot)
	return value

func _state_body() -> Dictionary:
	var value:=super._state_body()
	value["entered_routes"]=_sorted_latches()
	value["source_branch"]=_ready_branch
	if _tide_rules():
		value["closing"]=_closing.duplicate()
		value["drowned"]=_drowned.duplicate()
	# Open turns off the tide: only while something closes, so other hashes stay.
	elif not _closing.is_empty(): value["closing"]=_closing.duplicate()
	# The pieces rules: a stage with throws hashes what is in flight, and one
	# with a deck on its way hashes the deck.
	if not _throws.is_empty(): value["flights"]=_flights.duplicate(true)
	# The pieces rules: a stage with swings hashes each beat counter.
	if not _swing_plan.is_empty(): value["swings"]=_swing_counts.duplicate()
	if not _decks.is_empty(): value["decks"]=_decks.duplicate(true)
	return value

## Open turns: the journey's own world values (runtime.gd save_world): entry
## latches, the closing crossings as ticks left, who drowned or fell, who
## stands left high on a stone (tide rules only), each item's last leg, what
## flies and each deck on its way (none while every deck stands at its stop,
## as before decks travelled). The ready branch, holds and surfaces are a
## first turn's own part or a tick's, so they stay out.
func _save_extra(world: Dictionary) -> void:
	world["entry_latches"] = _sorted_latches()
	var closing: Dictionary = {}
	for id: String in _closing: closing[id] = int(_closing[id]) - tick
	world["closing"] = closing
	world["drowned"] = _drowned.duplicate()
	if _tide_rules(): world["high"] = _high.duplicate(true)
	world["legs_taken"] = _legs_taken.duplicate()
	world["flights"] = _flights.duplicate(true)
	# Only a stage with swings, so every other world hashes as before.
	if not _swing_plan.is_empty(): world["swings"] = _swing_counts.duplicate()
	if not _decks.is_empty(): world["decks"] = _decks.duplicate(true)

func _load_extra(world: Dictionary) -> void:
	_entry_latches = {}
	for id: Variant in world.entry_latches: _entry_latches[str(id)] = true
	_closing = {}
	for id: Variant in world.closing: _closing[str(id)] = int(world.closing[id]) + tick
	_drowned = world.drowned.duplicate()
	_high = world.get("high", {}).duplicate(true)
	_legs_taken = world.legs_taken.duplicate()
	_flights = world.flights.duplicate(true)
	for id: Variant in world.get("swings", {}): _swing_counts[str(id)] = int(world.swings[id])
	_decks = world.get("decks", {}).duplicate(true)

func _sorted_latches() -> Array:
	var result:=_entry_latches.keys()
	result.sort()
	return result

## `chain`: open turns only, the stage's turns before `prior_a`, oldest first.
static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}, chain: Array = []) -> Dictionary:
	return _proof(_record_version(record)).verify_recording(definition,record,checkpoint,prior_a,chain)

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	return _proof(_record_version(record)).recording_error(definition,record,checkpoint)

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return _proof(_checkpoint_version(checkpoint,definition)).verify_checkpoint(definition,checkpoint)

## `passes`: open turns only, the stage's turns between `first` and `second`.
static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, passes: Array = []) -> Dictionary:
	return _proof(_record_version(first)).derive_checkpoint(definition,previous,first,second,passes)

# --- The pieces rules: carried items and currents (core/physical/carried_items.gd) ---

## Sets the items up for this stage: its item_starts over the checkpoint's.
func _reset_items() -> void:
	_carrying = CarriedItems.on(simulation_version) and CarriedItems.declared(level)
	_item_order = []
	_hands = {}
	_legs_taken = {}
	_throws = {}
	_flights = {}
	if not _carrying: return
	for thrown: Dictionary in stage.get("throws", []): _throws[str(thrown.id)] = thrown
	if not _mechanisms.get("items") is Dictionary: _mechanisms["items"] = CarriedItems.initial(level)
	var starts: Dictionary = stage.get("item_starts", {})
	for id: Variant in starts: _mechanisms.items[str(id)] = CarriedItems.placed(level, str(starts[id]))
	_item_order = _mechanisms.items.keys()
	_item_order.sort()
	_hands = CarriedItems.hands_routes(level)

## The pieces rules: a pip that steps onto a crossing needing both hands
## while it carries an item drops it, and the turn ends ("dropped" on the
## drowned record: the item's id), the live pip or the friend's replay, p0
## first. The item lands at the crossing's foot it stepped on from, loose on
## that floor (CarriedItems.dropped_at). Decided here, so live play, the
## friend's replay, memories and replays all agree.
func _drop_on_hands() -> void:
	for slot: String in ["p0", "p1"]:
		var route := str(_players[slot].surface_id)
		if not _hands.has(route): continue
		var id := CarriedItems.held_by(_mechanisms.items, slot)
		if id.is_empty(): continue
		_mechanisms.items[id] = CarriedItems.dropped_at(level, route, _players[slot], str(_surfaces_before.get(slot, "")))
		_drowned = {"slot": slot, "route": route, "tick": tick, "dropped": id}
		finished = true
		_events.append("dropped:" + slot)
		return

## What an item offers `slot`'s pip here: hand over, put down or pick up.
func _item_action(slot: String) -> Dictionary:
	var player: Dictionary = _players[slot]
	var other := _other(slot)
	var items: Dictionary = _mechanisms.items
	var mine := CarriedItems.held_by(items, slot)
	if not mine.is_empty():
		if not _throws.is_empty() and not CarriedItems.throw_at(stage, player).is_empty(): return _action("throw", CarriedItems.LABELS.throw, true, mine)
		if CarriedItems.held_by(items, other).is_empty() and CarriedItems.can_hand(level, _hands, player, _players[other], _routes): return _action("give", CarriedItems.LABELS.give, true, mine)
		if not CarriedItems.lay(level, player, _standing_stops()).is_empty(): return _action("put", CarriedItems.LABELS.put, true, mine)
		return _action("", "", false, "")
	if _hands.has(str(player.surface_id)): return _action("", "", false, "")
	for id: String in _item_order:
		if CarriedItems.carriable(CarriedItems.item(level, id)) and CarriedItems.can_pick(player, items[id], level): return _action("take", CarriedItems.LABELS.take, true, id)
	return _action("", "", false, "")

## `slot`'s press on an item, the live pip's or the friend's replay's.
func _item_act(action: Dictionary, slot: String) -> void:
	var id := str(action.target_id)
	match str(action.id):
		"take": _take(id, slot)
		"put": _put(id, _players[slot])
		"give": _give(id, _other(slot))
		"throw": _throw(id, slot)

func _take(id: String, slot: String) -> void:
	_mechanisms.items[id] = CarriedItems.held(slot)
	_legs_taken.erase(id)
	_events.append("item_taken:" + id)

func _give(id: String, slot: String) -> void:
	_mechanisms.items[id] = CarriedItems.held(slot)
	_legs_taken.erase(id)
	_events.append("item_given:" + id)

## Throws item `id` from `slot`'s hands, from the throw whose mark it stands in.
func _throw(id: String, slot: String) -> bool:
	var thrown := CarriedItems.throw_at(stage, _players[slot])
	if thrown.is_empty(): return false
	var from := {"x": int(_players[slot].x), "z": int(_players[slot].z), "height": int(_players[slot].height) + CarriedItems.THROW_LIFT_CM}
	_flights[id] = {"throw": str(thrown.id), "from": from, "left": int(thrown.flight_ticks)}
	_mechanisms.items[id] = CarriedItems.flying(from, from, 0, 1)
	_legs_taken.erase(id)
	_events.append("item_thrown:" + id)
	return true

## Each item in flight moves a tick along its arc; in its last ticks a pip
## with empty hands at the landing catches it (p0 first, so a catch is the
## same live or replayed), and at the end it lands at the landing spot.
func _advance_flights() -> void:
	for id: String in _item_order:
		if not _flights.has(id): continue
		var flight: Dictionary = _flights[id]
		var thrown: Dictionary = _throws[flight.throw]
		var landing := CarriedItems.spot(level, str(thrown.to))
		var duration := int(thrown.flight_ticks)
		flight.left = int(flight.left) - 1
		var to := {"x": int(landing.position_cm[0]), "z": int(landing.position_cm[1]), "height": int(landing.get("height_cm", 0))}
		_mechanisms.items[id] = CarriedItems.flying(flight.from, to, duration - int(flight.left), duration)
		if int(flight.left) <= CarriedItems.CATCH_WINDOW_TICKS:
			var catcher := ""
			for slot: String in SLOTS:
				if catcher.is_empty() and CarriedItems.held_by(_mechanisms.items, slot).is_empty() and CarriedItems.can_catch(_players[slot], landing, int(thrown.catch_cm)): catcher = slot
			if not catcher.is_empty():
				_mechanisms.items[id] = CarriedItems.held(catcher)
				_flights.erase(id)
				_events.append("item_caught:" + id)
				continue
		if int(flight.left) <= 0:
			_mechanisms.items[id] = CarriedItems.at_spot(landing)
			_flights.erase(id)
			_events.append("item_landed:" + id)

## Puts item `id` down where `at` (a player) stands; false off an island or
## a platform's standing stop.
func _put(id: String, at: Dictionary) -> bool:
	var rest := CarriedItems.lay(level, at, _standing_stops())
	if rest.is_empty(): return false
	_mechanisms.items[id] = rest
	_legs_taken.erase(id)
	_events.append("item_put:" + id)
	return true

## The stops the stage's platforms stand at now, by id (an item may rest there).
func _standing_stops() -> Dictionary:
	var standing: Dictionary = {}
	for id: String in _stops:
		if bool(_routes.get(id, false)): standing[id] = true
	return standing

## The current: an item resting at a leg's start moves along it while its
## wheel shows the leg's value, `when` holds and `stop` does not; then it
## takes no other leg on that wheel value until the wheel turns or a pip
## handles it, so it moves one leg per turn of the wheel and never two a tick.
func _after_interact() -> void:
	if not _carrying: return
	if not _flights.is_empty(): _advance_flights()
	var legs: Array = stage.get("current_legs", [])
	for id: String in _item_order:
		var state: Dictionary = _mechanisms.items[id]
		if _legs_taken.has(id):
			var taken: PackedStringArray = str(_legs_taken[id]).split("=", true, 1)
			if str(_mechanisms.controls.get(taken[0], "")) != taken[1]: _legs_taken.erase(id)
		if legs.is_empty() or not str(state.holder).is_empty() or str(state.spot).is_empty(): continue
		for leg: Dictionary in legs:
			if str(leg.from) != str(state.spot): continue
			# A leg with no wheel goes while its `when` holds (a winding board).
			var turned := "%s=%s" % [leg.control_id, leg.value] if leg.has("control_id") else ""
			if not turned.is_empty() and (str(_mechanisms.controls.get(str(leg.control_id), "")) != str(leg.value) or str(_legs_taken.get(id, "")) == turned): continue
			if leg.has("when") and not Seven.predicate(leg.when, stage, _players, _mechanisms, _optics.signals, _open_controls()): continue
			if leg.has("stop") and Seven.predicate(leg.stop, stage, _players, _mechanisms, _optics.signals, _open_controls()): continue
			_mechanisms.items[id] = CarriedItems.at_spot(CarriedItems.spot(level, str(leg.to)))
			if not turned.is_empty(): _legs_taken[id] = turned
			_events.append("item_drifted:" + id)
			break