class_name AfterYouBorrowedLight
extends RefCounted
## Schema-3 Lighthouse stage engine; the filename/class preserve the first prototype API.
## Only the first five stages are authored. No online protocol or full chapter claim.
## Schema/simulation 3 never reinterprets Relay's version 2 recordings.
## Sources are replayed in their own simulation before copying their exact pose;
## the later player's mirror/bridge changes cannot change the ghost's route.

const Catalog = preload("res://core/lighthouse/stage_catalog.gd")
const Beam = preload("res://core/beam_field.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TICK_RATE := 30
const MAX_TICKS := 600
const SPEED := 8
const RADIUS := 12
const MIN_HOLD_TICKS := 15
const RECORD_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "stage_id", "stage_version", "definition_hash", "role", "player_slot", "tick_rate", "duration_ticks", "actions", "replay_checks", "completed", "final_state_hash", "source_recording_hash", "recording_hash"]

var role := "a"
var tick := 0
var finished := false
var complete := false
var error := ""
var _loaded := false
var _level: Dictionary = {}
var _definition_hash := ""
var _players: Dictionary = {}
var _checkpoint: Dictionary = {}
var _stage_id := "borrowed-light"
var _first_slot := "p0"
var _second_slot := "p1"
var _mirrors: Dictionary = {}
var _bridges: Dictionary = {}
var _props: Dictionary = {}
var _source: AfterYouBorrowedLight
var _prior: Dictionary = {}
var _prior_inputs: Array = []
var _mirror := "backslash"
var _power := false
var _bridge := false
var _first_power_tick := -1
var _hold_ticks := 0
var _hold_broken := false
var _bridge_entered := false
var _crossed := false
var _objective := false
var _action_held := false
var _actions: Array = []
var _checks: Array = []
var _optics: Dictionary = {}
var _events: Array = []
var _message := ""
var _selectors: Dictionary = {}
var _sequence: Dictionary = {}
var _attempt_latches: Dictionary = {}
var _route_progress := 0
var _handoff: Dictionary = {}

static func definition(stage_id: String = "borrowed-light") -> Dictionary:
	return Catalog.definition(stage_id)

func reset(current_role: String = "a", prior_a: Dictionary = {}, completed_pairs: Array = []) -> bool:
	_loaded = false
	error = ""
	_source = null
	var checked := checkpoint_from_pairs(completed_pairs)
	if not checked.valid:
		error = checked.error
		return false
	var checkpoint: Dictionary = checked.checkpoint
	if int(checkpoint.stage_index) >= Catalog.STAGE_IDS.size():
		error = "The next Lighthouse stage is not available yet."
		return false
	error = _checkpoint_requirements(definition(Catalog.STAGE_IDS[int(checkpoint.stage_index)]), checkpoint)
	if not error.is_empty():
		return false
	if current_role not in ["a", "b"]:
		error = "Unknown contribution role."
		return false
	if current_role == "a" and not prior_a.is_empty():
		error = "The first contribution cannot depend on an earlier turn."
		return false
	if current_role == "b":
		var first := _verify_at_checkpoint(prior_a, {}, checkpoint)
		if not first.valid or prior_a.get("role") != "a" or not first.get("snapshot", {}).get("can_commit", false):
			error = "A verified, steady light contribution is required."
			return false
	_reset_trusted(current_role, prior_a, checkpoint)
	return true

func _reset_trusted(current_role: String, prior_a: Dictionary, checkpoint: Dictionary) -> void:
	_checkpoint = checkpoint.duplicate(true)
	_stage_id = Catalog.STAGE_IDS[int(checkpoint.stage_index)]
	_level = definition(_stage_id)
	_definition_hash = Canonical.digest(_level)
	_first_slot = _level.first_player_slot
	_second_slot = "p1" if _first_slot == "p0" else "p0"
	role = current_role
	_prior = prior_a.duplicate(true)
	_prior_inputs = expand_recording_inputs(prior_a)
	_players = checkpoint.players.duplicate(true)
	_source = null
	if role == "b":
		_source = AfterYouBorrowedLight.new()
		_source._reset_trusted("a", {}, checkpoint)
	tick = 0
	finished = false
	complete = false
	error = ""
	_mirrors = {}
	for item: Dictionary in _level.optics.mirrors:
		_mirrors[item.id] = checkpoint.mechanisms.mirrors.get(item.id, item.orientation)
	_selectors = {}
	for control: Dictionary in Catalog.controls(_stage_id):
		if control.kind == "selector":
			_selectors[control.id] = 0
	_sequence = {"phase": "off", "first_tick": -1, "first_ticks": 0, "second_tick": -1, "second_ticks": 0, "broken": false}
	_attempt_latches = {}
	_route_progress = 0
	_handoff = {"authority": "source", "release_tick": -1, "release_state_hash": "", "claim_tick": -1}
	_props = {}
	for item: Dictionary in _level.get("props", []):
		_props[item.id] = {"status": "pedestal", "holder_slot": "", "socket_id": "", "x": item.position_cm[0], "z": item.position_cm[1], "surface_id": item.surface_id}
		if checkpoint.mechanisms.props.has(item.id):
			_props[item.id] = checkpoint.mechanisms.props[item.id].duplicate(true)
	_bridges = {}
	for item: Dictionary in _level.bridges:
		_bridges[item.id] = item.id in checkpoint.mechanisms.latched_bridges
	_mirror = "backslash"
	_first_power_tick = -1
	_hold_ticks = 0
	_hold_broken = false
	_bridge_entered = false
	_crossed = false
	_objective = false
	_power = false
	_bridge = false
	_action_held = false
	_actions = []
	_checks = []
	_events = []
	_message = _level["hint_" + role]
	_loaded = true
	_refresh_optics()

func step(input: Dictionary = {}) -> Dictionary:
	if not _loaded or finished or not error.is_empty():
		return snapshot()
	if not _valid_input(input):
		error = "Unsupported control input."
		return snapshot()
	var frame := _quantize(input)
	_append_frame(frame)
	_events = []
	if role == "a":
		_move(_first_slot, frame)
		if _stage_id == "borrowed-light":
			_update_source_hold()
	else:
		if tick < _prior_inputs.size():
			_source.step(_prior_inputs[tick])
		_players[_first_slot] = _source._players[_first_slot].duplicate()
		_power = _source._power
		_first_power_tick = _source._first_power_tick
		_hold_ticks = _source._hold_ticks
		_hold_broken = _source._hold_broken
		for control: Dictionary in Catalog.controls(_stage_id):
			if control.owner_slot == _first_slot:
				_mirrors[control.optical_id] = _source._mirrors[control.optical_id]
				if control.kind == "selector":
					_selectors[control.id] = _source._selectors[control.id]
		if _ordered_windows():
			_sequence = _source._sequence.duplicate(true)
		if _handoff_stage():
			_adopt_source_prop()
	_refresh_optics()
	if role == "b":
		_move(_second_slot, frame)
	var pressed: bool = bool(frame.action) and not _action_held
	_action_held = bool(frame.action)
	if pressed:
		_interact()
	_refresh_optics()
	if role == "a" and _stage_id != "borrowed-light":
		if _ordered_windows():
			_update_sequence()
		elif _handoff_stage():
			_power = _prop_fitted({"prop_id": _level.source_policy.prop_id, "socket_id": _level.source_policy.initial_socket_id})
		else:
			_update_receiver_hold()
	_update_carried_props()
	_update_receiver_goal()
	tick += 1
	if role == "b" and _objective and tick >= int(_prior.duration_ticks):
		complete = true
		finished = true
		_events.append("stage_complete")
		_message = "The Court remembers your light. Preview, then save this contribution." if _stage_id == "borrowed-light" else "The lens is home. Preview, then save this contribution."
		_message = _level.get("completion_message", _message)
	if tick >= MAX_TICKS:
		finished = true
		_events.append("turn_finished")
	if tick % TICK_RATE == 0 or finished:
		_checks.append({"tick": tick, "state_hash": state_hash()})
	return snapshot()

func _update_source_hold() -> void:
	var was_powered := _power
	_power = _near(_players.p0, _level.plate.position_cm, _level.plate.radius_cm)
	if _power:
		if _first_power_tick < 0:
			_first_power_tick = tick + 1
			_events.append("emitter_on")
		_hold_ticks += 1
	elif _first_power_tick >= 0:
		_hold_broken = true
		if was_powered:
			_events.append("emitter_off")

func _refresh_optics() -> void:
	var overrides: Dictionary = {}
	for control: Dictionary in Catalog.controls(_stage_id):
		if control.kind == "selector":
			var selection: int = _selectors[control.id]
			_mirrors[control.optical_id] = control.orientations[selection]
			overrides[control.emitter_id] = {"enabled": selection > 0}
	for id: String in _mirrors:
		overrides[id] = {"orientation": _mirrors[id]}
	if _stage_id == "borrowed-light":
		overrides["harbour-light"] = {"enabled": _power}
	for supply: Dictionary in _level.get("emitter_sources", []):
		overrides[supply.emitter_id] = {"enabled": _prop_fitted(supply)}
	_optics = Beam.evaluate(_level.optics, overrides)
	if not _optics.valid:
		error = "The authored optical field is invalid."
		_bridge = false
		return
	for item: Dictionary in _level.bridges:
		var was_open: bool = _bridges.get(item.id, false)
		var latched: bool = item.id in _checkpoint.mechanisms.latched_bridges
		var lit: bool = bool(_optics.signals.get(item.receiver_id, false)) or (item.has("prop_gate") and _prop_fitted(item.prop_gate))
		# Ordered crossings earn their own footprint latches. The stage objective
		# never blanket-opens future routes, even after its bell is activated.
		if _ordered_windows():
			_bridges[item.id] = latched or lit or bool(_attempt_latches.get(item.id, false))
		else:
			_bridges[item.id] = latched or lit or _objective
		if was_open != _bridges[item.id]:
			_events.append("bridge_open" if _bridges[item.id] else "bridge_closed")
	var controls := Catalog.controls(_stage_id)
	_mirror = _mirrors[controls[0].optical_id] if not controls.is_empty() else ""
	_bridge = _bridges[_level.bridges[-1].id]

func _update_receiver_hold() -> void:
	_power = bool(_optics.signals[_level.source_policy.receiver_id])
	if _power:
		if _first_power_tick < 0:
			_first_power_tick = tick + 1
			_events.append("source_aligned")
		_hold_ticks += 1
	elif _first_power_tick >= 0:
		_hold_broken = true

func _ordered_windows() -> bool:
	return _level.get("source_policy", {}).get("kind") == "ordered_windows"

func _handoff_stage() -> bool:
	return _level.get("source_policy", {}).get("kind") == "offer_prop"

func _adopt_source_prop() -> void:
	# The source engine is independently replayed from the verified prefix. It
	# supplies the canonical prop until its one physical release. Once B claims
	# it, later source frames must never respawn or move B's carried/fitted lens.
	if _handoff.authority == "receiver":
		return
	var id: String = _level.source_policy.prop_id
	if _source._handoff.authority == "source":
		_props[id] = _source._props[id].duplicate(true)
		_handoff = _source._handoff.duplicate(true)
	elif int(_handoff.release_tick) < 0:
		_props[id] = _source._props[id].duplicate(true)
		_handoff = _source._handoff.duplicate(true)
		_events.append("lens_available")

func _update_sequence() -> void:
	var ids: Array = _level.source_policy.receiver_ids
	var phase := "first" if _optics.signals.get(ids[0], false) else ("second" if _optics.signals.get(ids[1], false) else "off")
	_sequence.phase = phase
	_power = phase != "off"
	if phase == "first":
		if _sequence.second_tick >= 0:
			_sequence.broken = true
		if _sequence.first_tick < 0:
			_sequence.first_tick = tick + 1
		_sequence.first_ticks += 1
	elif phase == "second":
		if _sequence.first_tick < 0:
			_sequence.broken = true
		if _sequence.second_tick < 0:
			_sequence.second_tick = tick + 1
		_sequence.second_ticks += 1
	elif _sequence.first_tick >= 0:
		_sequence.broken = true
	_first_power_tick = _sequence.first_tick
	_hold_ticks = int(_sequence.first_ticks) + int(_sequence.second_ticks)
	_hold_broken = _sequence.broken

func _update_carried_props() -> void:
	for id: String in _props:
		var prop: Dictionary = _props[id]
		if prop.status == "carried":
			var holder: Dictionary = _players[prop.holder_slot]
			prop.x = holder.x
			prop.z = holder.z
			prop.surface_id = holder.surface_id

func _prop_fitted(requirement: Dictionary) -> bool:
	var prop: Dictionary = _props.get(requirement.get("prop_id", ""), {})
	return prop.get("status") == "fitted" and prop.get("holder_slot") == "" and prop.get("socket_id") == requirement.get("socket_id")

func _update_receiver_goal() -> void:
	if role != "b" or _objective or _level.get("goal_policy", {}).get("kind") != "all_receivers":
		return
	for id: String in _level.goal_policy.receiver_ids:
		if not _optics.signals.get(id, false):
			return
	# This latch records an actual simultaneous optical state, without imposing
	# an extra wait timer. Source verification already protects the first path.
	_objective = true
	_events.append("receivers_joined")
	_message = "Both promises are lit. The full earlier recording will finish before review."

func _interact() -> void:
	var action := context_action()
	if not action.enabled:
		_message = _level["hint_" + role]
		return
	if action.id == "rotate":
		_mirrors[action.target_id] = "slash" if _mirrors[action.target_id] == "backslash" else "backslash"
		_events.append("mirror_rotated")
		_message = "Follow the light to its receiver."
	elif action.id == "select_path":
		for control: Dictionary in Catalog.controls(_stage_id):
			if control.id == action.target_id:
				_selectors[control.id] = (int(_selectors[control.id]) + 1) % control.states.size()
				_events.append("route_selected")
				_message = "The selector records when each path shines."
				break
	elif action.id == "activate":
		_objective = true
		_events.append("court_activated")
		_message = "The Court is lit. The full earlier recording will finish before review."
	elif action.id == "anchor":
		_objective = true
		_events.append("tower_anchored")
		_message = "Both crossings are kept. The full earlier recording will finish before review."
	elif action.id == "take":
		var prop: Dictionary = _props[action.target_id]
		prop.status = "carried"
		prop.holder_slot = _active_slot()
		if _handoff_stage():
			prop.socket_id = ""
			if role == "b":
				_handoff.authority = "receiver"
				_handoff.claim_tick = tick + 1
		_events.append("lens_taken")
		_message = "Carry the lens back to its matching cradle."
		if _handoff_stage():
			_message = "Leave the lens on Rest Rock's matching perch." if role == "a" else "Carry this same lens to the tower projector."
	elif action.id == "offer":
		var prop: Dictionary = _props[_level.source_policy.prop_id]
		var perch := _socket(action.target_id)
		prop.merge({"status": "offered", "holder_slot": "", "socket_id": perch.id, "x": perch.position_cm[0], "z": perch.position_cm[1], "surface_id": perch.surface_id}, true)
		_handoff.authority = "offered"
		_handoff.release_tick = tick + 1
		_handoff.release_state_hash = Canonical.digest(prop)
		_events.append("lens_offered")
		_message = "Your partner can take the lens from this moment onward."
	elif action.id == "fit":
		var prop: Dictionary = _props[_level.goal_policy.prop_id]
		var socket: Dictionary = _socket(action.target_id)
		prop.status = "fitted"
		prop.holder_slot = ""
		prop.socket_id = socket.id
		prop.x = socket.position_cm[0]
		prop.z = socket.position_cm[1]
		prop.surface_id = socket.surface_id
		_objective = true
		_events.append("lens_fitted")
		_message = "The cradle is complete. The full earlier recording will finish before review."

func _active_slot() -> String:
	return _first_slot if role == "a" else _second_slot

func _socket(id: String) -> Dictionary:
	for item: Dictionary in _level.get("sockets", []):
		if item.id == id:
			return item
	return {}

func context_action() -> Dictionary:
	var none := {"id": "none", "label": "Hold the light" if role == "a" and _stage_id == "borrowed-light" else "Action", "enabled": false, "target_id": ""}
	if not _loaded or finished or not error.is_empty():
		return none
	var slot := _active_slot()
	var player: Dictionary = _players[slot]
	for control: Dictionary in Catalog.controls(_stage_id):
		if _near(player, control.position_cm, control.radius_cm):
			if control.owner_slot != slot:
				return {"id": "reserved", "label": "Partner's selector" if control.kind == "selector" else "Partner's mirror", "enabled": false, "target_id": control.id}
			if control.kind == "selector":
				return {"id": "select_path", "label": control.labels[_selectors[control.id]], "enabled": true, "target_id": control.id}
			return {"id": "rotate", "label": "Rotate mirror", "enabled": true, "target_id": control.optical_id}
	if _stage_id == "borrowed-light":
		if role == "b" and _near(player, _level.goal.position_cm, _level.goal.radius_cm):
			return {"id": "activate", "label": "Ring Court bell", "enabled": _crossed and _bridge and player.surface_id == "court" and not _objective, "target_id": "court-bell"}
		return none
	if _handoff_stage():
		return _handoff_action(player, none)
	if _level.goal_policy.kind == "ordered_crossing":
		if role == "b" and _near(player, _level.goal.position_cm, _level.goal.radius_cm):
			return {"id": "anchor", "label": "Ring tower bell", "enabled": _route_progress == 4 and player.surface_id == _level.goal.surface_id and not _objective, "target_id": _level.goal.id}
		return none
	if _level.goal_policy.kind != "fit_prop":
		return none
	for item: Dictionary in _level.get("props", []):
		var prop: Dictionary = _props[item.id]
		if item.owner_slot == slot and prop.status == "pedestal" and player.surface_id == item.surface_id and _near(player, [prop.x, prop.z], item.radius_cm):
			return {"id": "take", "label": "Take lens", "enabled": true, "target_id": item.id}
	for item: Dictionary in _level.get("sockets", []):
		if item.owner_slot == slot and player.surface_id == item.surface_id and _near(player, item.position_cm, item.radius_cm):
			var prop: Dictionary = _props[item.prop_id]
			return {"id": "fit", "label": "Fit lens", "enabled": prop.status == "carried" and prop.holder_slot == slot and _bridge and not _objective, "target_id": item.id}
	return none

func _handoff_action(player: Dictionary, none: Dictionary) -> Dictionary:
	var id: String = _level.source_policy.prop_id
	var prop: Dictionary = _props[id]
	if role == "a":
		if _handoff.authority != "source":
			return none
		var cradle := _socket(_level.source_policy.initial_socket_id)
		if prop.status == "fitted" and prop.socket_id == cradle.id and player.surface_id == cradle.surface_id and _near(player, cradle.position_cm, cradle.radius_cm):
			return {"id": "take", "label": "Take lens", "enabled": true, "target_id": id}
		var perch := _socket(_level.source_policy.release_socket_id)
		if prop.status == "carried" and prop.holder_slot == _first_slot and player.surface_id == perch.surface_id and _near(player, perch.position_cm, perch.radius_cm):
			return {"id": "offer", "label": "Leave lens", "enabled": true, "target_id": perch.id}
		return none
	if _handoff.authority == "source":
		if player.surface_id == prop.surface_id and _near(player, [prop.x,prop.z], 32):
			return {"id": "reserved", "label": "Partner's lens", "enabled": false, "target_id": id}
		return none
	if _handoff.authority == "offered" and prop.status == "offered" and player.surface_id == prop.surface_id and _near(player, [prop.x,prop.z], 28):
		return {"id": "take", "label": "Take lens", "enabled": true, "target_id": id}
	var projector := _socket(_level.goal_policy.socket_id)
	if _handoff.authority == "receiver" and prop.status == "carried" and prop.holder_slot == _second_slot and player.surface_id == projector.surface_id and _near(player, projector.position_cm, projector.radius_cm):
		return {"id": "fit", "label": "Fit projector", "enabled": not _objective, "target_id": projector.id}
	return none

func can_commit() -> bool:
	if not _loaded or not error.is_empty() or tick == 0:
		return false
	if role == "b":
		return complete
	if _handoff_stage():
		return _handoff.authority == "offered" and int(_handoff.release_tick) + source_budget_ticks() <= MAX_TICKS
	if _ordered_windows():
		var budgets := sequence_budget_ticks()
		return not _sequence.broken and _sequence.phase == "second" and _sequence.first_ticks >= budgets[0] and _sequence.second_ticks >= budgets[1]
	return _power and not _hold_broken and _hold_ticks >= MIN_HOLD_TICKS and _first_power_tick + source_budget_ticks() <= MAX_TICKS

func commit_reason() -> String:
	if not error.is_empty():
		return error
	if not _loaded:
		return "No stage is loaded."
	if can_commit():
		return ""
	if role == "b":
		return _level.hint_b
	if _handoff_stage():
		if _handoff.authority != "offered":
			return "Take the Court lens and leave it on the Rest Rock perch before finishing."
		return "Leave the lens earlier so your partner has time to reach it and fit the projector."
	if _ordered_windows():
		if _sequence.broken:
			return "The route sequence restarted or went dark. Rehearse one first path, then one second path."
		var budgets := sequence_budget_ticks()
		if _sequence.first_tick < 0:
			return "Use the South selector to light the first path."
		if _sequence.first_ticks < budgets[0]:
			return "Keep the first path lit long enough for your partner to reach safe Rest Rock."
		if _sequence.second_tick < 0:
			return "The first path is ready. Select the second path before finishing."
		return "Keep the second path lit long enough to reach the tower bell."
	if _hold_broken:
		if _level.get("source_policy", {}).has("broken_hint"):
			return _level.source_policy.broken_hint
		return "The light pad was released. Rehearse again and keep it held through Finish." if _stage_id == "borrowed-light" else "The North light was interrupted. Rehearse again and leave its mirror aligned."
	if _first_power_tick < 0:
		if _level.get("source_policy", {}).has("unlit_hint"):
			return _level.source_policy.unlit_hint
		return "Stand on the light pad to power the emitter." if _stage_id == "borrowed-light" else "Turn the Court mirror toward the North receiver."
	if _first_power_tick + source_budget_ticks() > MAX_TICKS:
		if _level.get("source_policy", {}).has("early_hint"):
			return _level.source_policy.early_hint
		return "Reach the pad earlier so your partner has time to turn the mirror and cross." if _stage_id == "borrowed-light" else "Align the mirror earlier so your partner can fetch and return the lens."
	if _level.get("source_policy", {}).has("steady_hint"):
		return _level.source_policy.steady_hint
	return "Keep the light steady for a moment, then finish while holding the pad." if _stage_id == "borrowed-light" else "Leave the North light steady for a moment before finishing."

func snapshot() -> Dictionary:
	if not _loaded:
		return {"error": error, "can_commit": false, "finished": false, "complete": false}
	var players := _players.duplicate(true)
	for slot: String in players:
		players[slot].merge({"height": 0, "ghost": role == "b" and slot == _first_slot})
	var result := {"schema_version": 3, "simulation_version": 3, "stage_id": _stage_id, "role": role,
		"active_slot": _active_slot(), "first_player_slot": _first_slot, "tick": tick,
		"time_seconds": float(tick) / TICK_RATE, "duration_ticks": MAX_TICKS, "complete": complete, "finished": finished,
		"can_commit": can_commit(), "commit_reason": commit_reason(), "error": error, "message": _message,
		"players": players, "bridges": _bridges.duplicate(true), "optics": _optics.duplicate(true),
		"mirror_orientation": _mirror, "emitter_powered": _power, "objective_done": _objective,
		"crossed_bridge": _crossed, "first_power_tick": _first_power_tick, "hold_ticks": _hold_ticks,
		"mirrors": _mirrors.duplicate(true), "props": _props.duplicate(true), "checkpoint_hash": _checkpoint.checkpoint_hash,
		"source_tick": _source.tick if role == "b" else tick, "events": _events.duplicate(), "context_action": context_action()}
	if _level.get("goal_policy", {}).get("kind") == "all_receivers":
		var signals: Dictionary = {}
		for id: String in _level.goal_policy.receiver_ids:
			signals[id] = bool(_optics.signals.get(id, false))
		result["receiver_goal"] = {"signals": signals, "unlocked": _objective, "flag_id": _level.goal_policy.checkpoint_flag}
	if _ordered_windows():
		result["sequence"] = _sequence.duplicate(true)
		result.sequence["required_ticks"] = sequence_budget_ticks()
		result["selectors"] = _selectors.duplicate(true)
		result["route_progress"] = {"step": _route_progress, "rest_reached": _route_progress >= 2, "tower_reached": _route_progress >= 4, "kept_bridges": _attempt_latches.keys()}
	if _handoff_stage():
		result["handoff"] = _handoff.duplicate(true)
		result.handoff.merge({"prop_id": _level.source_policy.prop_id, "source_slot": _first_slot, "receiver_slot": _second_slot})
	return result

func state_hash() -> String:
	var state := {"simulation_version": 3, "definition_hash": _definition_hash, "role": role, "tick": tick,
		"source_recording_hash": _prior.get("recording_hash", ""), "source_state_hash": _source.state_hash() if role == "b" else "",
		"players": _players, "mirror": _mirror, "power": _power, "bridge": _bridge,
		"first_power_tick": _first_power_tick, "hold_ticks": _hold_ticks, "hold_broken": _hold_broken,
		"bridge_entered": _bridge_entered, "crossed": _crossed, "objective": _objective, "held": _action_held,
		"complete": complete, "finished": finished}
	# The first prototype's definition and state serialization remain exact. Later
	# stages also bind their verified start and every portable/mechanism state.
	if _stage_id != "borrowed-light":
		state.merge({"checkpoint_hash": _checkpoint.checkpoint_hash, "mirrors": _mirrors, "bridges": _bridges, "props": _props})
	if _ordered_windows():
		state.merge({"selectors": _selectors, "sequence": _sequence, "attempt_latches": _attempt_latches, "route_progress": _route_progress})
	if _handoff_stage():
		state["handoff"] = _handoff
	return Canonical.digest(state)

func export_recording() -> Dictionary:
	if not _loaded or tick == 0 or not error.is_empty():
		return {}
	var checks := _checks.duplicate(true)
	if checks.is_empty() or int(checks[-1].tick) != tick:
		checks.append({"tick": tick, "state_hash": state_hash()})
	var record := {"schema_version": 3, "simulation_version": 3, "level_id": _level.id, "level_version": 1,
		"stage_id": _stage_id, "stage_version": 1, "definition_hash": _definition_hash, "role": role,
		"player_slot": _active_slot(), "tick_rate": TICK_RATE, "duration_ticks": tick,
		"actions": _actions.duplicate(true), "replay_checks": checks, "completed": complete, "final_state_hash": state_hash(),
		"source_recording_hash": _prior.get("recording_hash", "")}
	if _stage_id != "borrowed-light":
		record["checkpoint_hash"] = _checkpoint.checkpoint_hash
	record["recording_hash"] = recording_hash(record)
	return record

static func verify_recording(record: Dictionary, prior_a: Dictionary = {}, completed_pairs: Array = []) -> Dictionary:
	var checked := checkpoint_from_pairs(completed_pairs)
	if not checked.valid:
		return checked
	return _verify_at_checkpoint(record, prior_a, checked.checkpoint)

static func _verify_at_checkpoint(record: Dictionary, prior_a: Dictionary, checkpoint: Dictionary) -> Dictionary:
	var reason := _record_error(record)
	if not reason.is_empty():
		return _invalid(reason)
	var stage_index := int(checkpoint.stage_index)
	if stage_index >= Catalog.STAGE_IDS.size() or record.stage_id != Catalog.STAGE_IDS[stage_index]:
		return _invalid("The contribution does not start at this verified chapter checkpoint.")
	if stage_index > 0 and record.checkpoint_hash != checkpoint.checkpoint_hash:
		return _invalid("The earlier chapter pair changed.")
	reason = _checkpoint_requirements(definition(Catalog.STAGE_IDS[stage_index]), checkpoint)
	if not reason.is_empty():
		return _invalid(reason)
	if record.role == "b":
		if prior_a.get("role") != "a" or prior_a.get("recording_hash") != record.source_recording_hash:
			return _invalid("The exact earlier contribution changed.")
		var first := _verify_at_checkpoint(prior_a, {}, checkpoint)
		if not first.valid or not first.get("snapshot", {}).get("can_commit", false):
			return _invalid("The earlier light contribution is not viable.")
	elif not prior_a.is_empty():
		return _invalid("Unexpected source on a first contribution.")
	var replay := AfterYouBorrowedLight.new()
	replay._reset_trusted(record.role, prior_a, checkpoint)
	for input: Dictionary in expand_recording_inputs(record):
		if replay.finished:
			return _invalid("Inputs follow a completed contribution.")
		replay.step(input)
	if not Canonical.same(replay.export_recording(), record):
		return _invalid("The recording differs from its deterministic replay.")
	return {"valid": true, "error": "", "snapshot": replay.snapshot()}

func resume_recording(record: Dictionary, prior_a: Dictionary = {}, completed_pairs: Array = []) -> bool:
	_loaded = false
	_source = null
	error = ""
	var checkpoint := checkpoint_from_pairs(completed_pairs)
	if not checkpoint.valid:
		error = checkpoint.error
		return false
	var checked := _verify_at_checkpoint(record, prior_a, checkpoint.checkpoint)
	if not checked.valid:
		error = checked.error
		return false
	_reset_trusted(record.role, prior_a, checkpoint.checkpoint)
	for input: Dictionary in expand_recording_inputs(record):
		step(input)
	# Reconstruction produces no presentation/audio events. State hashes do not
	# include ephemeral presentation events, and the next real step replaces them.
	_events = []
	return true

static func initial_checkpoint() -> Dictionary:
	var first := definition()
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x": first.starts[slot][0], "z": first.starts[slot][1], "surface_id": "harbour"}
	return _seal_checkpoint({"schema_version": 3, "simulation_version": 3, "level_id": first.id, "level_version": 1,
		"stage_index": 0, "players": players, "mechanisms": {"latched_bridges": [], "mirrors": {}, "props": {}},
		"previous_checkpoint_hash": "", "a_recording_hash": "", "b_recording_hash": ""})

static func checkpoint_from_pairs(completed_pairs: Array) -> Dictionary:
	# Evidence is linear and bounded; no recursive untrusted checkpoint/proof
	# object is imported. Every pair is replayed from its derived predecessor.
	if completed_pairs.size() > Catalog.STAGE_IDS.size():
		return _invalid("The chapter evidence exceeds the available authored stages.")
	var checkpoint := initial_checkpoint()
	for value: Variant in completed_pairs:
		if not value is Dictionary or not _keys(value, ["a", "b"]) or not value.a is Dictionary or not value.b is Dictionary:
			return _invalid("Expected an ordered chapter pair with only A and B recordings.")
		if value.a.get("role") != "a" or value.b.get("role") != "b":
			return _invalid("The chapter pair has reversed or missing roles.")
		var checked := _verify_at_checkpoint(value.b, value.a, checkpoint)
		if not checked.valid or not checked.get("snapshot", {}).get("complete", false):
			return _invalid("A chapter checkpoint requires a verified completed pair.")
		var state: Dictionary = checked.snapshot
		var players: Dictionary = {}
		for slot: String in ["p0", "p1"]:
			players[slot] = {"x": state.players[slot].x, "z": state.players[slot].z, "surface_id": state.players[slot].surface_id}
		var latched: Array = checkpoint.mechanisms.latched_bridges.duplicate()
		for bridge: Dictionary in definition(value.b.stage_id).bridges:
			if state.bridges[bridge.id] and bridge.id not in latched:
				latched.append(bridge.id)
		latched.sort()
		var mirrors: Dictionary = checkpoint.mechanisms.mirrors.duplicate(true)
		mirrors.merge(state.mirrors, true)
		var props: Dictionary = checkpoint.mechanisms.props.duplicate(true)
		props.merge(state.props, true)
		var mechanisms := {"latched_bridges": latched, "mirrors": mirrors, "props": props}
		var goal: Dictionary = definition(value.b.stage_id).get("goal_policy", {})
		if checkpoint.mechanisms.has("flags") or goal.has("checkpoint_flag"):
			var flags: Dictionary = checkpoint.mechanisms.get("flags", {}).duplicate(true)
			if goal.has("checkpoint_flag"):
				flags[goal.checkpoint_flag] = true
			mechanisms["flags"] = flags
		checkpoint = _seal_checkpoint({"schema_version": 3, "simulation_version": 3, "level_id": "sleeping-lighthouse", "level_version": 1,
			"stage_index": int(checkpoint.stage_index) + 1, "players": players,
			"mechanisms": mechanisms,
			"previous_checkpoint_hash": checkpoint.checkpoint_hash, "a_recording_hash": value.a.recording_hash, "b_recording_hash": value.b.recording_hash})
	return {"valid": true, "error": "", "checkpoint": checkpoint}

static func _checkpoint_requirements(stage: Dictionary, checkpoint: Dictionary) -> String:
	for required: Dictionary in stage.get("required_props", []):
		var prop: Dictionary = checkpoint.mechanisms.props.get(required.prop_id, {})
		if prop.get("status") != "fitted" or prop.get("holder_slot") != "" or prop.get("socket_id") != required.socket_id:
			return "This stage requires the lens fitted by the earlier verified pair."
	for flag: String in stage.get("required_flags", []):
		if checkpoint.mechanisms.get("flags", {}).get(flag) != true:
			return "This stage requires the receiver lock completed by the earlier verified pair."
	for bridge: String in stage.get("required_bridges", []):
		if bridge not in checkpoint.mechanisms.latched_bridges:
			return "This stage requires the remembered crossings completed by the earlier verified pair."
	return ""

static func _seal_checkpoint(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["checkpoint_hash"] = Canonical.digest(value)
	return result

static func derive_stage_result(first: Dictionary, second: Dictionary, completed_pairs: Array = []) -> Dictionary:
	if first.get("role") != "a" or second.get("role") != "b":
		return _invalid("A stage result requires an ordered A/B pair.")
	var checked := verify_recording(second, first, completed_pairs)
	if not checked.valid or not checked.get("snapshot", {}).get("complete", false):
		return _invalid("The pair has not completed its Lighthouse stage.")
	var state: Dictionary = checked.snapshot
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x": state.players[slot].x, "z": state.players[slot].z, "surface_id": state.players[slot].surface_id}
	# Compatibility observation only. reset accepts pair evidence, never this
	# dictionary as an arbitrary checkpoint or caller-authored player state.
	return {"valid": true, "error": "", "result": {"schema_version": 3, "simulation_version": 3,
		"definition_hash": first.definition_hash, "completed_stage_id": first.stage_id, "players": players,
		"mechanisms": {"emitter_latched": true, "bridge_latched": true, "mirror_orientation": state.mirror_orientation},
		"a_recording_hash": first.recording_hash, "b_recording_hash": second.recording_hash}, "snapshot": state}

static func receiver_budget_ticks() -> int:
	var route: Array = definition().receiver_route_cm
	var ticks := 2 + 4 # Two interactions plus conservative seam/rounding allowance.
	for index in range(1, route.size()):
		for axis in [0, 1]:
			ticks += ceili(float(absi(int(route[index][axis]) - int(route[index - 1][axis]))) / SPEED)
	return ticks

func source_budget_ticks() -> int:
	if _stage_id == "borrowed-light":
		return receiver_budget_ticks()
	if _ordered_windows():
		var budgets := sequence_budget_ticks()
		return budgets[0] + budgets[1]
	var route: Array = _level.receiver_route_cm.duplicate(true)
	var start: Dictionary = _checkpoint.players[_second_slot]
	var ticks := 2 + 12 # Take, Fit, seams and quantized endpoint rounding.
	if _level.has("receiver_route_entries"):
		var entry: Dictionary = _level.receiver_route_entries.get(start.surface_id, {})
		if entry.is_empty():
			return MAX_TICKS + 1
		if entry.has("join_cm"):
			route.push_front(entry.join_cm)
		route.push_front([entry.align_cm, int(start.z)] if entry.align_axis == "x" else [int(start.x), entry.align_cm])
		route.push_front([int(start.x), int(start.z)])
		ticks = int(_level.receiver_action_ticks) + 12
	else:
		route[0] = [int(start.x), 0]
		route.push_front([int(start.x), int(start.z)])
	for index in range(1, route.size()):
		for axis in [0, 1]:
			ticks += ceili(float(absi(int(route[index][axis]) - int(route[index - 1][axis]))) / SPEED)
	return ticks

func sequence_budget_ticks() -> Array[int]:
	if not _ordered_windows():
		return []
	var start: Dictionary = _checkpoint.players[_second_slot]
	var entry: Dictionary = _level.sequence_route_entries.get(start.surface_id, {})
	if entry.is_empty():
		return [MAX_TICKS + 1, MAX_TICKS + 1]
	var route: Array = [[int(start.x), int(start.z)]]
	route.append([int(start.x), int(entry.value)] if entry.axis == "z" else [int(entry.value), int(start.z)])
	if entry.has("join_cm"):
		route.append(entry.join_cm)
	route.append_array(_level.sequence_routes_cm[0])
	return [_route_ticks(route) + int(_level.sequence_margin_ticks), _route_ticks(_level.sequence_routes_cm[1]) + int(_level.sequence_margin_ticks) + 1]

static func _route_ticks(route: Array) -> int:
	var total := 0
	for index in range(1, route.size()):
		for axis in [0, 1]:
			total += ceili(float(absi(int(route[index][axis]) - int(route[index - 1][axis]))) / SPEED)
	return total

func walkable_at(x: int, z: int, exclude_timed: bool = false) -> bool:
	if not _loaded:
		return false
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-RADIUS, -RADIUS), Vector2i(RADIUS, -RADIUS), Vector2i(-RADIUS, RADIUS), Vector2i(RADIUS, RADIUS), Vector2i(-RADIUS, 0), Vector2i(RADIUS, 0), Vector2i(0, -RADIUS), Vector2i(0, RADIUS)]:
		if _surface(Vector2i(x, z) + offset, exclude_timed).is_empty():
			return false
	return true

func _surface(point: Vector2i, exclude_timed: bool = false) -> String:
	for island: Dictionary in _level.islands:
		if _inside(point, island.rect_cm):
			return island.id
	for bridge: Dictionary in _level.bridges:
		if exclude_timed and bridge.get("latch_on_enter", false):
			continue
		if _bridges[bridge.id] and _inside(point, bridge.rect_cm):
			return bridge.id
	return ""

func _move(slot: String, frame: Dictionary) -> void:
	var origin := Vector2i(_players[slot].x, _players[slot].z)
	var speed := 6 if frame.x != 0 and frame.z != 0 else SPEED
	var delta := Vector2i(int(frame.x) * speed, int(frame.z) * speed)
	var destination := origin
	for change: Vector2i in [delta, Vector2i(delta.x, 0), Vector2i(0, delta.y)]:
		if _swept(origin, change, _ordered_windows() and slot == _first_slot):
			destination = origin + change
			break
	var previous_surface: String = _players[slot].surface_id
	var surface := _surface(destination)
	_players[slot] = {"x": destination.x, "z": destination.y, "surface_id": surface}
	if _ordered_windows() and slot == _second_slot:
		_update_route_progress(destination, surface)
	if _stage_id == "borrowed-light" and slot == _second_slot and _bridge:
		if previous_surface == "harbour" and surface == "harbour-court":
			_bridge_entered = true
		if _bridge_entered and previous_surface == "harbour-court" and surface == "court":
			_crossed = true
			_events.append("crossed_bridge")

func _update_route_progress(position: Vector2i, surface: String) -> void:
	var ids: Array = _level.goal_policy.bridge_ids
	for bridge: Dictionary in _level.bridges:
		if not bridge.get("latch_on_enter", false) or not _bridges[bridge.id] or _attempt_latches.has(bridge.id):
			continue
		# Latch on the first occupied footprint, including a corner over the gap
		# while the centre is still on Court. A selector switch cannot remove it.
		var touches := false
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(-RADIUS,-RADIUS), Vector2i(RADIUS,-RADIUS), Vector2i(-RADIUS,RADIUS), Vector2i(RADIUS,RADIUS)]:
			if _inside(position + offset, bridge.rect_cm):
				touches = true
				break
		if touches:
			_attempt_latches[bridge.id] = true
			_events.append("path_kept")
			if bridge.id == ids[0] and _route_progress == 0:
				_route_progress = 1
			elif bridge.id == ids[1] and _route_progress == 2:
				_route_progress = 3
	if surface == _level.goal_policy.rest_surface and _route_progress == 1:
		_route_progress = 2
		_events.append("rest_reached")
	if surface == _level.goal_policy.destination_surface and _route_progress == 3:
		_route_progress = 4
		_events.append("tower_reached")

func _swept(origin: Vector2i, delta: Vector2i, exclude_timed: bool = false) -> bool:
	var count := maxi(absi(delta.x), absi(delta.y))
	for index in range(1, count + 1):
		var position := origin + Vector2i(delta.x * index / count, delta.y * index / count)
		if not walkable_at(position.x, position.y, exclude_timed):
			return false
	return true

func _append_frame(frame: Dictionary) -> void:
	if not _actions.is_empty() and _actions[-1].x == frame.x and _actions[-1].z == frame.z and _actions[-1].action == frame.action:
		_actions[-1].ticks += 1
	else:
		_actions.append({"ticks": 1, "x": frame.x, "z": frame.z, "action": frame.action})

static func expand_recording_inputs(record: Dictionary) -> Array:
	var inputs: Array = []
	# Only structurally checked records reach the simulation. This helper itself
	# is bounded and returns no frames for malformed actions used by a UI caller.
	if record.is_empty():
		return inputs
	if not _record_error(record).is_empty():
		return inputs
	for run: Dictionary in record.actions:
		for _i in range(int(run.ticks)):
			inputs.append({"move_x": int(run.x), "move_z": int(run.z), "interact": bool(run.action)})
	return inputs

static func recording_hash(record: Dictionary) -> String:
	var copy := record.duplicate(true)
	copy.erase("recording_hash")
	return Canonical.digest(copy)

static func _record_error(record: Dictionary) -> String:
	var keys := RECORD_KEYS.duplicate()
	if record.get("stage_id") in Catalog.STAGE_IDS and record.get("stage_id") != "borrowed-light":
		keys.append("checkpoint_hash")
	if not _keys(record, keys):
		return "Missing or unknown recording fields."
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version", "tick_rate", "duration_ticks"]:
		if not _integer(record[key]):
			return "Recording versions and durations must be integers."
	if record.schema_version != 3 or record.simulation_version != 3 or record.level_version != 1 or record.stage_version != 1 or record.tick_rate != TICK_RATE:
		return "Unsupported recording version."
	var stage := definition(str(record.stage_id))
	if stage.is_empty() or record.level_id != "sleeping-lighthouse" or record.definition_hash != Canonical.digest(stage):
		return "The recording belongs to another authored stage."
	if record.get("stage_id") != "borrowed-light" and not _hash(record.get("checkpoint_hash")):
		return "Missing checkpoint dependency."
	var first_slot: String = stage.first_player_slot
	var second_slot := "p1" if first_slot == "p0" else "p0"
	if record.role not in ["a", "b"] or record.player_slot != (first_slot if record.role == "a" else second_slot) or not record.completed is bool:
		return "Invalid contribution role or outcome."
	if record.duration_ticks < 1 or record.duration_ticks > MAX_TICKS or not _hash(record.final_state_hash) or not _hash(record.recording_hash):
		return "Invalid duration or state hashes."
	if (record.role == "a" and record.source_recording_hash != "") or (record.role == "b" and not _hash(record.source_recording_hash)):
		return "Invalid source dependency."
	if not record.actions is Array or record.actions.is_empty() or record.actions.size() > MAX_TICKS:
		return "Invalid action list."
	var total := 0
	for item: Variant in record.actions:
		if not item is Dictionary or not _keys(item, ["ticks", "x", "z", "action"]):
			return "Malformed action run."
		if not _integer(item.ticks) or item.ticks < 1 or item.ticks > MAX_TICKS or not _integer(item.x) or not _integer(item.z) or item.x < -1 or item.x > 1 or item.z < -1 or item.z > 1 or not item.action is bool:
			return "Invalid action values."
		total += int(item.ticks)
		if total > MAX_TICKS:
			return "Too many action ticks."
	if total != record.duration_ticks or not record.replay_checks is Array or record.replay_checks.is_empty() or record.replay_checks.size() > 21:
		return "Invalid replay duration or integrity checks."
	var last := 0
	for item: Variant in record.replay_checks:
		if not item is Dictionary or not _keys(item, ["tick", "state_hash"]) or not _integer(item.tick) or item.tick <= last or item.tick > total or not _hash(item.state_hash):
			return "Malformed replay integrity check."
		last = int(item.tick)
	if last != total or recording_hash(record) != record.recording_hash:
		return "Recording content hash mismatch."
	return ""

static func _valid_input(input: Dictionary) -> bool:
	for key: Variant in input:
		if key not in ["move_x", "move_z", "interact"]:
			return false
	for key: String in ["move_x", "move_z"]:
		var value: Variant = input.get(key, 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 1.0:
			return false
	return input.get("interact", false) is bool

static func _quantize(input: Dictionary) -> Dictionary:
	var x := float(input.get("move_x", 0))
	var z := float(input.get("move_z", 0))
	return {"x": signi(int(signf(x))) if absf(x) >= 0.25 else 0, "z": signi(int(signf(z))) if absf(z) >= 0.25 else 0, "action": bool(input.get("interact", false))}

static func _near(player: Dictionary, coords: Array, radius: int) -> bool:
	var dx := int(player.x) - int(coords[0])
	var dz := int(player.z) - int(coords[1])
	return dx * dx + dz * dz <= radius * radius

static func _inside(point: Vector2i, rect: Array) -> bool:
	return point.x >= rect[0] and point.y >= rect[1] and point.x <= rect[2] and point.y <= rect[3]

static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true

static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "error": reason}
