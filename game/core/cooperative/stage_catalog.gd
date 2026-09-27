extends RefCounted
## Bounded physical chapters; all positions and walking heights use integer cm.
const Canonical = preload("res://core/v2/canonical.gd")
const HouseCatalog = preload("res://core/cooperative/house_catalog.gd")
const KEYS := ["high-and-low@1", "rolling-home@1", "a-house-for-two@1"]

static func definition(key: String = "high-and-low") -> Dictionary:
	match key:
		"high-and-low", "high-and-low@1": return _high_and_low()
		"rolling-home", "rolling-home@1": return _rolling_home()
		"a-house-for-two", "a-house-for-two@1": return HouseCatalog.definition()
	return {}

static func known(value: Dictionary) -> bool:
	var expected := definition(str(value.get("id", "")))
	return not expected.is_empty() and Canonical.same(value, expected)

static func stage_definition(level: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in level.get("stages", []):
		if stage.id != stage_id: continue
		var result := level.duplicate(true)
		result.erase("stages")
		result.merge(stage, true)
		result.id=level.id
		result["stage_id"]=stage.id
		result["stage_version"]=stage.version
		return result
	return {}

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	var players: Dictionary={}
	for slot: String in ["p0", "p1"]:
		var coords: Array=level.starts[slot]
		players[slot]={"x":coords[0],"z":coords[1],"height":0,"surface_id":str(level.islands[0].id)}
	var props: Dictionary={}
	for prop: Dictionary in level.get("props", []):
		props[prop.id]={"status":"free","holder_slot":"","socket_id":"","x":prop.position_cm[0],"z":prop.position_cm[1],"height":0,"surface_id":prop.surface_id}
	var checkpoint := {"schema_version":6,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"stage_index":0,"completed_stage_id":"","next_stage_id":level.stages[0].id,"players":players,
		"mechanisms":{"latched_bridges":[],"props":props,"levers":{}},"previous_checkpoint_hash":"","a_recording_hash":"","b_recording_hash":"","proof":{}}
	checkpoint["checkpoint_hash"]=checkpoint_hash(checkpoint)
	return checkpoint

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	var body := checkpoint.duplicate(true)
	body.erase("proof")
	body.erase("checkpoint_hash")
	return Canonical.digest(body)

static func _high_and_low() -> Dictionary:
	return {"schema_version":6,"simulation_version":6,"id":"high-and-low","version":1,"title":"High and Low","premium":false,
		"starts":{"p0":[-528,-128],"p1":[-288,0]},"props":[],
		"islands":[_island("shore",[-640,-240,-240,240],0),_island("loft",[-80,-240,320,240],160),_island("lower-ledge",[128,-96,576,192],0),_island("garden",[736,-176,1088,176],0)],
		"stairs":[{"id":"blue-stair","rect_cm":[-240,-48,-80,48],"axis":"x","from_surface":"shore","to_surface":"loft","from_height_cm":0,"to_height_cm":160,"owner_slot":"p1"}],
		"bridges":[_bridge("lower-causeway",[-240,96,128,192],"shore","lower-ledge","p0"),_bridge("red-passage",[576,-48,736,48],"lower-ledge","garden","p0")],
		"drops":[{"id":"loft-hole","rect_cm":[216,24,264,72],"surface_id":"loft","destination_surface":"lower-ledge","height_cm":0,"requires_lever":"loft-lever"}],
		"stages":[{
			"id":"upper-path","version":1,"first_player_slot":"p0","kind":"hold_switch","levers":[_goal("shore-lever",[-544,112],"shore","p0")],"ball_pads":[],
			"pressure_pads":[_pad("lower-switch",[-448,-128],"shore","p0")],
			"gates":[{"route_id":"blue-stair","pad_id":"lower-switch","lever_id":"shore-lever","ball_pad_id":""}],
			"source_policy":{"kind":"hold_switch","pad_id":"lower-switch","lever_id":"shore-lever","minimum_hold_ticks":15},
			"goal_policy":{"kind":"ring"},"goal":_goal("loft-bell",[160,-128],"loft","p1"),
			"receiver_route_cm":[[-288,0],[160,0],[160,-128]],"receiver_action_ticks":1,
			"hint_a":"Help your partner reach the loft.",
			"hint_b":"Reach the bell above."
		},{
			"id":"down-and-around","version":1,"first_player_slot":"p1","kind":"hold_switch","ball_pads":[],
			"levers":[_goal("loft-lever",[240,-128],"loft","p1")],
			"pressure_pads":[_pad("lower-ledge-switch",[448,48],"lower-ledge","p1")],
			"gates":[{"route_id":"lower-causeway","pad_id":"lower-ledge-switch","lever_id":"loft-lever","ball_pad_id":""},{"route_id":"red-passage","pad_id":"lower-ledge-switch","lever_id":"loft-lever","ball_pad_id":""}],
			"source_policy":{"kind":"hold_switch","pad_id":"lower-ledge-switch","lever_id":"loft-lever","minimum_hold_ticks":15},
			"goal_policy":{"kind":"ring"},"goal":_goal("garden-bell",[912,0],"garden","p0"),
			"receiver_route_cm":[[-448,144],[448,144],[448,0],[912,0]],"receiver_action_ticks":1,
			"hint_a":"Open a way through the lower islands.",
			"hint_b":"Reach the garden bell."
		}]}

static func _rolling_home() -> Dictionary:
	return {"schema_version":6,"simulation_version":6,"id":"rolling-home","version":1,"title":"Rolling Home","premium":true,
		"starts":{"p0":[-528,0],"p1":[-528,144]},"stairs":[],"drops":[],
		"obstacles":[{"id":"garden-bed","rect_cm":[656,-64,816,64],"surface_id":"far-bank"}],
		"access_zones":[{"id":"upper-lane","rect_cm":[656,64,816,208],"surface_id":"far-bank","owner_slot":"p1"},{"id":"lower-lane","rect_cm":[656,-208,816,-64],"surface_id":"far-bank","owner_slot":"p0"}],
		"islands":[_island("shore",[-640,-208,-240,208],0),_island("middle",[-80,-208,400,208],0),_island("far-bank",[560,-208,960,208],0),_island("home",[1120,-208,1520,208],0)],
		"bridges":[_bridge("shore-middle",[-240,-56,-80,56],"shore","middle"),_bridge("middle-far",[400,-56,560,56],"middle","far-bank"),_bridge("far-home",[960,-56,1120,56],"far-bank","home")],
		"props":[{"id":"round-ball","kind":"ball","position_cm":[-464,0],"surface_id":"shore","radius_cm":20}],
		"stages":[{
			"id":"weight-of-a-friend","version":1,"first_player_slot":"p0","kind":"weight_switch","levers":[_goal("middle-lever",[192,112],"middle","p1")],"pressure_pads":[],
			"ball_pads":[{"id":"heavy-pad","position_cm":[-304,96],"surface_id":"shore","radius_cm":36,"prop_id":"round-ball"}],
			"gates":[{"route_id":"shore-middle","pad_id":"","lever_id":"","ball_pad_id":"heavy-pad"},{"route_id":"middle-far","pad_id":"","lever_id":"middle-lever","ball_pad_id":"heavy-pad"}],
			"source_policy":{"kind":"weight_switch","ball_pad_id":"heavy-pad","prop_id":"round-ball","minimum_hold_ticks":15},
			"goal_policy":{"kind":"ring"},"goal":_goal("far-bell",[896,96],"far-bank","p1"),
			"receiver_route_cm":[[-400,0],[192,0],[192,112],[192,0],[608,0],[608,128],[896,128],[896,96]],"receiver_action_ticks":2,
			"hint_a":"Help your partner cross with the ball's weight.",
			"hint_b":"Find what keeps both crossings open."
		},{
			"id":"bring-it-home","version":1,"first_player_slot":"p1","kind":"offer_ball","pressure_pads":[],"ball_pads":[],
			"levers":[_goal("home-lever",[896,96],"far-bank","p1"),_goal("route-lever",[240,128],"middle","p0")],
			"gates":[{"route_id":"far-home","pad_id":"","lever_id":"home-lever","second_lever_id":"route-lever","ball_pad_id":""}],
			"source_policy":{"kind":"offer_ball","prop_id":"round-ball","lever_id":"home-lever","release_socket_id":"handoff-mark"},
			"handoff":{"id":"handoff-mark","position_cm":[240,0],"surface_id":"middle","radius_cm":36,"owner_slot":"p1"},
			"goal_policy":{"kind":"ball_home","prop_id":"round-ball","socket_id":"home-cradle"},
			"goal":{"id":"home-cradle","position_cm":[1376,0],"surface_id":"home","radius_cm":36,"owner_slot":"p0"},
			"receiver_route_cm":[[208,0],[208,128],[240,128],[208,128],[208,0],[608,0],[608,-128],[864,-128],[864,0],[1376,0]],"receiver_action_ticks":2,
			"hint_a":"Bring the ball back for your partner.",
			"hint_b":"Roll the ball home."
		}]}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":height}

static func _bridge(id: String, rect: Array, from: String, to: String, owner: String="") -> Dictionary:
	return {"id":id,"rect_cm":rect,"from_surface":from,"to_surface":to,"height_cm":0,"owner_slot":owner}

static func _pad(id: String, at: Array, surface: String, owner: String) -> Dictionary:
	return {"id":id,"position_cm":at,"surface_id":surface,"radius_cm":32,"owner_slot":owner}

static func _goal(id: String, at: Array, surface: String, owner: String) -> Dictionary:
	return {"id":id,"position_cm":at,"surface_id":surface,"radius_cm":28,"owner_slot":owner}
