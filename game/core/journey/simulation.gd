class_name AfterYouJourneySimulation
extends "res://core/physical/runtime.gd"
## A separate sealed ruleset. Published simulation6 never selects this facade.
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const BeamField = preload("res://core/beam_field.gd")
const CURRENT_SIMULATION_VERSION := 7
var _entry_latches: Dictionary = {}
var _ready_branch := ""
var _optics: Dictionary = {"segments":[],"signals":{}}

func _init() -> void:
	simulation_version = CURRENT_SIMULATION_VERSION

func _schema_version() -> int:
	return CURRENT_SIMULATION_VERSION

func _new_simulation() -> RefCounted:
	return AfterYouJourneySimulation.new()

func _proof_engine() -> RefCounted:
	return _proof()

static func _proof() -> RefCounted:
	return Proof.new(Catalog, AfterYouJourneySimulation, CURRENT_SIMULATION_VERSION)

func _reset_mechanics() -> void:
	_entry_latches = {}
	_ready_branch = ""
	_optics = {"segments":[],"signals":{}}

func _advance_source() -> void:
	super._advance_source()
	# A evolves independently. Copy only its declared controls, never B's local
	# selector, shutter, entry latches, or future changed source ownership.
	for control: Dictionary in stage.get("controls", []):
		if control.owner_slot == first_player_slot:
			_mechanisms.controls[control.id] = _source._mechanisms.controls[control.id]
	_ready_branch = _source._ready_branch

func _refresh_routes() -> void:
	_refresh_optics()
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		_routes[route.id] = route.id in _mechanisms.latched_bridges or bool(_entry_latches.get(route.id, false))
	for gate: Dictionary in stage.get("gates", []):
		_routes[gate.route_id] = bool(_routes.get(gate.route_id, false)) or Seven.predicate(gate.get("when", {}), stage, _players, _mechanisms, _optics.signals)

func _refresh_optics() -> void:
	if not stage.has("optical_field"):
		_optics={"segments":[],"signals":{}}
		return
	var overrides: Dictionary={}
	for control: Dictionary in stage.get("controls",[]):
		if control.kind=="mirror": overrides[control.id]={"orientation":str(_mechanisms.controls[control.id])}
	_optics=BeamField.evaluate(stage.optical_field,overrides)
	if not _optics.valid: error=str(_optics.error)

func _after_move() -> void:
	if role != "b": return
	var player: Dictionary = _players[active_slot]
	var point := Vector2i(player.x, player.z)
	var diagonal := int(ceil(float(PLAYER_RADIUS)*0.707107))
	var samples := [Vector2i.ZERO,Vector2i(PLAYER_RADIUS,0),Vector2i(-PLAYER_RADIUS,0),Vector2i(0,PLAYER_RADIUS),Vector2i(0,-PLAYER_RADIUS),Vector2i(diagonal,diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,-diagonal)]
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if route.id not in stage.get("entry_latch_routes", []) or not bool(_routes.get(route.id, false)) or not Navigation._owns(route, active_slot): continue
		for offset: Vector2i in samples:
			var sample := point+offset
			if not Navigation.inside(sample,route.rect_cm): continue
			var height: int = Navigation.stair_height(route,sample) if route.has("axis") else int(route.height_cm)
			if absi(height-int(player.height)) <= PLAYER_RADIUS+1:
				_entry_latches[route.id] = true
				break

func context_action() -> Dictionary:
	if level.is_empty(): return _action("", "", false, "")
	for control: Dictionary in stage.get("controls", []):
		if control.owner_slot == active_slot and Seven.near(_players[active_slot],control):
			return _action("selector", "Turn mirror" if control.kind=="mirror" else "Turn switch", true, control.id)
	var inherited := super.context_action()
	if inherited.id == "ring" and level.id == "long-way-home": inherited.label = "Light window"
	if inherited.id == "ring" and level.id == "conservatory": inherited.label = "Light garden"
	if inherited.id == "ring" and not Seven.predicate(stage.goal_policy.get("when", {}),stage,_players,_mechanisms,_optics.signals):
		inherited.enabled = false
	return inherited

func _objective_display() -> Dictionary:
	var value := super._objective_display()
	if role == "b" and level.id == "long-way-home": value.label = "Window"
	if role == "b" and level.id == "conservatory": value.label = "Garden light"
	return value

func _interact() -> void:
	var action := context_action()
	if action.id != "selector":
		super._interact()
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
		if Seven.predicate(policy.when,stage,_players,_mechanisms,_optics.signals) and endpoint_ok: branch="endpoint"
	elif policy.kind == "choice_pad":
		var selected := Seven.choice(stage,_players)
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
		selected=Seven.choice(stage,_players)
		if selected.is_empty(): return MAX_TICKS
	var point:=Vector2i(_checkpoint.players[_other(first_player_slot)].x,_checkpoint.players[_other(first_player_slot)].z)
	var budget:=int(selected.get("receiver_action_ticks",0))+40
	for coords: Array in selected.receiver_route_cm:
		var next:=Vector2i(coords[0],coords[1])
		budget+=ceili(float(absi(next.x-point.x))/MOVE_PER_TICK)+ceili(float(absi(next.y-point.y))/MOVE_PER_TICK)
		point=next
	return budget

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick==0: return false
	if role=="b": return complete
	return not _ready_branch.is_empty() and _hold_start>=0 and _hold_start+source_budget_ticks()<MAX_TICKS

func snapshot() -> Dictionary:
	var value:=super.snapshot()
	if not level.is_empty():
		value["controls"]=_mechanisms.controls.duplicate()
		value.route_progress["entered_routes"]=_sorted_latches()
		value["source_branch"]=_ready_branch
		value["optics"]=_optics.duplicate(true)
	return value

func _state_body() -> Dictionary:
	var value:=super._state_body()
	value["entered_routes"]=_sorted_latches()
	value["source_branch"]=_ready_branch
	return value

func _sorted_latches() -> Array:
	var result:=_entry_latches.keys()
	result.sort()
	return result

static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	return _proof().verify_recording(definition,record,checkpoint,prior_a)

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	return _proof().recording_error(definition,record,checkpoint)

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return _proof().verify_checkpoint(definition,checkpoint)

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof().derive_checkpoint(definition,previous,first,second)
