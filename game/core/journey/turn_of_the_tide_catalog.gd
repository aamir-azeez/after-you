extends RefCounted
## Two waters: the harbour tide and the outer sea.
## Day 1: A turns the mill's tide wheel and waits on a step beside it; the tide
## they leave decides which tier B crosses to ring the harbour bell.
## Day 2: the roles swap. p1 walks home under the frozen tide, makes two
## moorings fast (the shut-sea ones before the sea first turns, the gate bar at
## slack water) and sets the outer sea to the way's mark; p0 fetches the way's
## pin, key or line on the mill side, takes the tides in order across the one
## harbour-mouth way that sea opens and lights the lantern.
## Titles, hints and selector words are hashed; PlayerCopy shows the same
## title, stage titles and hints, with the summary and completion line.
## Turns run longer than the published 30 and 40 seconds: 90 seconds for the
## first turn of each stage, 100 for the partner (runtime.gd turn_ticks).

static func definition() -> Dictionary:
	return {"schema_version":7,"simulation_version":9,"id":"turn-of-the-tide","version":1,"title":"Turn of the Tide","premium":false,"turn_limits":{"a_ticks":2700,"b_ticks":3000},
		"starts":{"p0":{"position_cm":[-320,288],"height_cm":0,"surface_id":"w-beach"},"p1":{"position_cm":[-320,416],"height_cm":0,"surface_id":"w-beach"}},"props":[],
		"islands":[_island("mole-beach",[-960,224,-704,480],0),_island("mole-terrace",[-960,-128,-704,128],48),_island("mole-quay",[-960,-480,-704,-224],96),
			_island("sea-chamber",[-640,-96,-576,96],48),
			_island("w-beach",[-512,224,-128,480],0),_island("w-terrace",[-512,-128,-128,128],48),_island("w-quay",[-512,-480,-128,-224],96),
			_island("m-beach",[0,224,192,480],0),_island("m-terrace",[0,-128,384,128],48),_island("m-quay",[0,-480,384,-224],96),
			_island("aq-feeder",[288,128,352,320],48),_island("aq-span",[288,256,672,320],48),
			_island("e-beach",[576,224,1152,480],0),_island("e-terrace-west",[576,-128,768,128],48),_island("lock-chamber",[832,-96,928,96],48),
			_island("e-terrace-east",[992,-128,1152,128],48),_island("e-quay",[576,-480,1152,-224],96),
			_island("r-beach",[1344,224,1728,480],0),_island("r-terrace",[1344,-128,1728,128],48),_island("r-quay",[1344,-480,1728,-224],96)],
		"stairs":[_stair("w-steps-low",[-224,128,-128,224],"w-terrace","w-beach",48,0),
			_stair("w-steps-high",[-224,-224,-128,-128],"w-quay","w-terrace",96,48),
			_stair("mill-steps",[48,128,144,224],"m-terrace","m-beach",48,0),
			_stair("mill-ladder",[48,-224,144,-128],"m-quay","m-terrace",96,48,"p0"),
			_stair("east-steps",[672,-224,768,-128],"e-quay","e-terrace-west",96,48),
			_stair("boathouse-steps",[640,128,736,224],"e-terrace-west","e-beach",48,0,"p1"),
			_stair("rock-steps-low",[1392,128,1488,224],"r-terrace","r-beach",48,0),
			_stair("rock-steps-high",[1392,-224,1488,-128],"r-quay","r-terrace",96,48),
			_stair("mole-steps",[-912,-224,-816,-128],"mole-quay","mole-terrace",96,48),
			_stair("mole-slip",[-912,128,-816,224],"mole-terrace","mole-beach",48,0)],
		"bridges":[_bridge("sand-1",[-128,288,0,416],"w-beach","m-beach",0),
			_bridge("stones-1",[-128,-64,0,64],"w-terrace","m-terrace",48),
			_bridge("jetty-1",[-128,-416,0,-288],"w-quay","m-quay",96),
			_bridge("stones-2",[384,-64,576,64],"m-terrace","e-terrace-west",48),
			_bridge("jetty-2",[384,-416,576,-288],"m-quay","e-quay",96),
			_bridge("lock-west",[768,-64,832,64],"e-terrace-west","lock-chamber",48),
			_bridge("lock-east",[928,-64,992,64],"lock-chamber","e-terrace-east",48),
			_bridge("slipway",[1152,288,1344,416],"e-beach","r-beach",0),
			_bridge("stones-3",[1152,-64,1344,64],"e-terrace-east","r-terrace",48),
			_bridge("jetty-3",[1152,-416,1344,-288],"e-quay","r-quay",96),
			_bridge("quay-step",[32,-544,96,-480],"m-quay","quay-step",96,"p0"),
			_bridge("wheel-step",[160,-544,224,-480],"m-quay","wheel-step",96,"p0"),
			_bridge("bollard-step",[288,-544,352,-480],"m-quay","bollard-step",96,"p0"),
			_bridge("towpath",[192,368,576,448],"m-beach","e-beach",0),
			_bridge("boom-jetty",[-704,-416,-512,-288],"w-quay","mole-quay",96,"p0"),
			_bridge("sea-gate-in",[-576,-64,-512,64],"w-terrace","sea-chamber",48,"p0"),
			_bridge("sea-gate-out",[-704,-64,-640,64],"sea-chamber","mole-terrace",48,"p0"),
			_bridge("punt-ferry",[-704,288,-512,416],"w-beach","mole-beach",0,"p0"),
			_bridge("race-stage",[192,-192,256,-128],"m-terrace","race-stage",48,"p0"),
			_bridge("bar-catwalk",[-512,-192,-456,-128],"w-terrace","bar-catwalk",48,"p1"),
			_bridge("punt-post",[-440,-192,-384,-128],"w-terrace","punt-post",48,"p1"),
			_bridge("gate-catwalk",[-368,-192,-312,-128],"w-terrace","gate-catwalk",48,"p1"),
			_bridge("gate-post",[-296,-192,-240,-128],"w-terrace","gate-post",48,"p1"),
			_bridge("boom-post",[-296,128,-240,192],"w-terrace","boom-post",48,"p1"),
			_bridge("beach-catwalk",[-200,480,-144,544],"w-beach","beach-catwalk",0,"p1"),
			_bridge("quay-catwalk",[-200,-544,-144,-480],"w-quay","quay-catwalk",96,"p1")],
		"drops":[{"id":"spout","rect_cm":[600,268,648,308],"surface_id":"aq-span","destination_surface":"e-beach","height_cm":0,"requires_lever":"sluice"}],
		"access_zones":[{"id":"spout-lip","rect_cm":[552,256,672,320],"surface_id":"aq-span","owner_slot":"p1"}],
		"stages":[_set_the_tide(),_slack_water()]}

## One identical entry, used by both stages (initial_checkpoint merges by id).
static func _tide() -> Dictionary:
	return _selector("tide",[192,-352],"m-quay",96,"p0",["low","half","high"],"low")

## One identical entry, used by both stages.
static func _lock() -> Dictionary:
	return _selector("lock",[880,48],"lock-chamber",48,"p1",["west","east"],"west")

static func _set_the_tide() -> Dictionary:
	var low: Dictionary={"id":"low","pad_id":"wheel-step-pad","receiver_route_cm":[[320,128],[1344,352],[1440,0]],"receiver_action_ticks":2}
	var half: Dictionary={"id":"half","pad_id":"quay-step-pad","receiver_route_cm":[[832,0],[880,48],[1440,0]],"receiver_action_ticks":4}
	var high: Dictionary={"id":"high","pad_id":"bollard-pad","receiver_route_cm":[[1344,-352],[1440,0]],"receiver_action_ticks":4}
	return {"id":"set-the-tide","version":1,"title":"Set the Tide","first_player_slot":"p0","kind":"choice_pad","ball_pads":[],
		"controls":[_tide(),_selector("winch",[624,-448],"e-quay",96,"p0",["stowed","slip"],"stowed"),_lock()],
		"levers":[_point("sluice",[704,96],"e-terrace-west",48,"p0",28),_point("line",[1088,-448],"e-quay",96,"p0",28),_point("gangway",[1104,-352],"e-quay",96,"p1",28)],
		"pressure_pads":[_point("wheel-step-pad",[192,-512],"wheel-step",96,"p0",20),_point("quay-step-pad",[64,-512],"quay-step",96,"p0",20),_point("bollard-pad",[320,-512],"bollard-step",96,"p0",20)],
		"gates":[{"route_id":"w-steps-low"},{"route_id":"w-steps-high"},{"route_id":"mill-steps"},{"route_id":"mill-ladder"},
			{"route_id":"east-steps"},{"route_id":"boathouse-steps"},{"route_id":"rock-steps-low"},{"route_id":"rock-steps-high"},
			{"route_id":"sand-1","when":{"control_id":"tide","value":"low"}},
			{"route_id":"stones-1","when":{"control_id":"tide","value":"half"}},
			{"route_id":"jetty-1","when":{"control_id":"tide","value":"high"}},
			{"route_id":"stones-2","when":{"control_id":"tide","value":"half"}},
			{"route_id":"jetty-2","when":{"control_id":"tide","value":"high"}},
			{"route_id":"slipway","when":{"all":[{"control_id":"tide","value":"low"},{"control_id":"winch","value":"slip"}]}},
			{"route_id":"stones-3","when":{"all":[{"control_id":"tide","value":"half"},{"lever_id":"sluice"}]}},
			{"route_id":"jetty-3","when":{"all":[{"control_id":"tide","value":"high"},{"pad_id":"bollard-pad"},{"lever_id":"gangway"}]}},
			{"route_id":"lock-west","when":{"control_id":"lock","value":"west"}},
			{"route_id":"lock-east","when":{"control_id":"lock","value":"east"}},
			{"route_id":"wheel-step","when":{"all":[{"control_id":"tide","value":"low"},{"control_id":"winch","value":"slip"},{"lever_id":"sluice"}]}},
			{"route_id":"quay-step","when":{"all":[{"control_id":"tide","value":"half"},{"lever_id":"sluice"}]}},
			{"route_id":"bollard-step","when":{"all":[{"control_id":"tide","value":"high"},{"lever_id":"line"}]}}],
		"entry_latch_routes":["sand-1","stones-1","jetty-1","stones-2","jetty-2","slipway","stones-3","jetty-3"],
		"source_policy":{"kind":"choice_pad","branches":[low,half,high]},
		"goal_policy":{"kind":"ring"},"goal":_point("harbour-bell",[1440,0],"r-terrace",48,"p1",28),
		"receiver_route_cm":high.receiver_route_cm,"receiver_action_ticks":4,
		"hint_a":"Turn the tide to open a way for your partner, then wait on a step by the wheel.",
		"hint_b":"Cross when the tide is right and ring the harbour bell."}

static func _slack_water() -> Dictionary:
	var boom: Dictionary={"id":"boom","pad_id":"boom-post-pad","receiver_route_cm":[[320,-512],[192,-352],[-512,-352],[192,-352],[-864,-128],[-832,0]],"receiver_action_ticks":26}
	var sea_lock: Dictionary={"id":"sea-lock","pad_id":"gate-post-pad","receiver_route_cm":[[64,-512],[192,-352],[-512,0],[192,-352],[-608,48],[-832,0]],"receiver_action_ticks":14}
	var punt: Dictionary={"id":"punt","pad_id":"punt-post-pad","receiver_route_cm":[[192,-352],[120,-128],[208,-144],[120,-128],[192,-352],[-704,352],[-864,128],[-832,0]],"receiver_action_ticks":10}
	return {"id":"slack-water","version":1,"title":"Slack Water","first_player_slot":"p1","kind":"choice_pad","ball_pads":[],
		"controls":[_tide(),_lock(),_selector("chamber",[-608,48],"sea-chamber",48,"p0",["low","half","high"],"half"),
			_selector("basin",[-312,-64],"w-terrace",48,"p1",["shut","low","half","high"],"shut")],
		"levers":[_point("boom-chain",[-172,512],"beach-catwalk",0,"p1",28),_point("punt-chain",[-172,-512],"quay-catwalk",96,"p1",28),
			_point("gate-bar",[-340,-160],"gate-catwalk",48,"p1",28),_point("sea-bar",[-484,-160],"bar-catwalk",48,"p1",28),
			_point("punt-line",[224,-160],"race-stage",48,"p0",28),_point("boom-pin",[320,-512],"bollard-step",96,"p0",28),
			_point("sea-key",[64,-512],"quay-step",96,"p0",28)],
		"pressure_pads":[_point("boom-post-pad",[-268,160],"boom-post",48,"p1",16),_point("gate-post-pad",[-268,-160],"gate-post",48,"p1",16),
			_point("punt-post-pad",[-412,-160],"punt-post",48,"p1",16)],
		"gates":[{"route_id":"w-steps-low"},{"route_id":"w-steps-high"},{"route_id":"mill-steps"},{"route_id":"mill-ladder"},
			{"route_id":"east-steps"},{"route_id":"boathouse-steps"},{"route_id":"rock-steps-low"},{"route_id":"rock-steps-high"},
			{"route_id":"mole-slip"},{"route_id":"towpath"},
			{"route_id":"sand-1","when":{"control_id":"tide","value":"low"}},
			{"route_id":"stones-1","when":{"control_id":"tide","value":"half"}},
			{"route_id":"jetty-1","when":{"control_id":"tide","value":"high"}},
			{"route_id":"stones-2","when":{"control_id":"tide","value":"half"}},
			{"route_id":"jetty-2","when":{"control_id":"tide","value":"high"}},
			{"route_id":"lock-west","when":{"control_id":"lock","value":"west"}},
			{"route_id":"lock-east","when":{"control_id":"lock","value":"east"}},
			{"route_id":"boom-jetty","when":{"all":[{"lever_id":"boom-chain"},{"lever_id":"gate-bar"},{"control_id":"basin","value":"half"},{"control_id":"tide","value":"high"}]}},
			{"route_id":"mole-steps","when":{"all":[{"control_id":"tide","value":"low"},{"lever_id":"boom-pin"}]}},
			{"route_id":"sea-gate-in","when":{"all":[{"lever_id":"gate-bar"},{"lever_id":"sea-bar"},_level_with_tide("chamber")]}},
			{"route_id":"sea-gate-out","when":{"all":[{"lever_id":"gate-bar"},{"lever_id":"sea-bar"},{"control_id":"basin","value":"low"},{"control_id":"chamber","value":"low"},{"control_id":"tide","value":"high"},{"lever_id":"sea-key"}]}},
			{"route_id":"race-stage","when":{"control_id":"tide","value":"low"}},
			{"route_id":"punt-ferry","when":{"all":[{"lever_id":"punt-chain"},{"lever_id":"sea-bar"},{"lever_id":"punt-line"},{"control_id":"basin","value":"high"},{"control_id":"tide","value":"half"}]}},
			{"route_id":"bollard-step","when":{"control_id":"tide","value":"half"}},
			{"route_id":"quay-step","when":{"control_id":"tide","value":"low"}},
			{"route_id":"gate-catwalk","when":_level_with_tide("basin")},
			{"route_id":"bar-catwalk","when":{"control_id":"basin","value":"shut"}},
			{"route_id":"beach-catwalk","when":{"control_id":"basin","value":"shut"}},
			{"route_id":"quay-catwalk","when":{"any":[{"control_id":"basin","value":"shut"},{"control_id":"basin","value":"low"},{"control_id":"basin","value":"half"}]}},
			{"route_id":"boom-post","when":{"all":[{"lever_id":"boom-chain"},{"lever_id":"gate-bar"},{"control_id":"basin","value":"half"}]}},
			{"route_id":"gate-post","when":{"all":[{"lever_id":"gate-bar"},{"lever_id":"sea-bar"},{"control_id":"basin","value":"low"}]}},
			{"route_id":"punt-post","when":{"all":[{"lever_id":"punt-chain"},{"lever_id":"sea-bar"},{"control_id":"basin","value":"high"}]}}],
		"entry_latch_routes":["sand-1","stones-1","jetty-1","stones-2","jetty-2","lock-west","lock-east","towpath","boom-jetty","mole-steps","sea-gate-in","sea-gate-out","race-stage","punt-ferry"],
		"source_policy":{"kind":"choice_pad","branches":[boom,sea_lock,punt]},
		"goal_policy":{"kind":"ring"},"goal":_point("harbour-lantern",[-832,0],"mole-terrace",48,"p0",28),
		"receiver_route_cm":sea_lock.receiver_route_cm,"receiver_action_ticks":14,
		"hint_a":"Some moorings only catch while the sea is shut, so do those first. Then turn the sea, moor the rest, set your post's mark and wait there.",
		"hint_b":"Fetch the pin, key or line at the mill. Any crossing stays open once you step onto it, so take the tides in the right order, then light the lantern."}

## SLACK (control "basin") and CHAMBER_MATCH (control "chamber"): the control
## stands at the same water as the harbour tide. A fresh copy for each use.
static func _level_with_tide(control: String) -> Dictionary:
	var matches: Array = []
	for water: String in ["low","half","high"]:
		matches.append({"all":[{"control_id":control,"value":water},{"control_id":"tide","value":water}]})
	return {"any":matches}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":height}

static func _bridge(id: String, rect: Array, from: String, to: String, height: int, owner: String = "") -> Dictionary:
	return {"id":id,"rect_cm":rect,"from_surface":from,"to_surface":to,"height_cm":height,"owner_slot":owner}

## `low` is the height at the stair's smaller z and `high` at its larger z.
static func _stair(id: String, rect: Array, from: String, to: String, low: int, high: int, owner: String = "") -> Dictionary:
	return {"id":id,"rect_cm":rect,"axis":"z","from_surface":from,"to_surface":to,"from_height_cm":low,"to_height_cm":high,"owner_slot":owner}

static func _point(id: String, position: Array, surface: String, height: int, owner: String, radius: int) -> Dictionary:
	return {"id":id,"position_cm":position,"surface_id":surface,"height_cm":height,"owner_slot":owner,"radius_cm":radius}

static func _selector(id: String, position: Array, surface: String, height: int, owner: String, values: Array, initial: String) -> Dictionary:
	var result:=_point(id,position,surface,height,owner,28)
	result.merge({"kind":"selector","values":values,"initial":initial})
	return result
