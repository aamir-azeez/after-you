extends RefCounted
## Test-only stand-in for core/journey/turn_of_the_tide_catalog.gd, so the
## harbour world can be built and checked before the chapter is registered.
## Geometry, markers, gates and policies follow the chapter design; titles and
## hints are placeholders. Replace every use with the real catalog once it lands.

const KEY := "turn-of-the-tide@1"

static func definition() -> Dictionary:
	return {"schema_version":7,"simulation_version":9,"id":"turn-of-the-tide","version":1,"title":"Turn of the Tide","premium":false,
		"starts":{"p0":{"position_cm":[-320,288],"height_cm":0,"surface_id":"w-beach"},"p1":{"position_cm":[-320,416],"height_cm":0,"surface_id":"w-beach"}},"props":[],
		"islands":[_island("mole-beach",[-960,224,-704,480],0),_island("mole-terrace",[-960,-128,-704,128],48),_island("mole-quay",[-960,-480,-704,-224],96),
			_island("sea-chamber",[-640,-96,-576,96],48),
			_island("w-beach",[-512,224,-128,480],0),_island("w-terrace",[-512,-128,-128,128],48),_island("w-quay",[-512,-480,-128,-224],96),
			_island("m-beach",[0,224,192,480],0),_island("m-terrace",[0,-128,384,128],48),_island("m-quay",[0,-480,384,-224],96),
			_island("aq-feeder",[288,128,352,320],48),_island("aq-span",[288,256,672,320],48),
			_island("e-beach",[576,224,1152,480],0),_island("e-terrace-west",[576,-128,768,128],48),_island("lock-chamber",[832,-96,928,96],48),
			_island("e-terrace-east",[992,-128,1152,128],48),_island("e-quay",[576,-480,1152,-224],96),
			_island("r-beach",[1344,224,1728,480],0),_island("r-terrace",[1344,-128,1728,128],48),_island("r-quay",[1344,-480,1728,-224],96)],
		"stairs":[_stair("w-steps-low",[-224,128,-128,224],"w-terrace","w-beach",48,0),_stair("w-steps-high",[-224,-224,-128,-128],"w-quay","w-terrace",96,48),
			_stair("mill-steps",[48,128,144,224],"m-terrace","m-beach",48,0),_stair("mill-ladder",[48,-224,144,-128],"m-quay","m-terrace",96,48,"p0"),
			_stair("east-steps",[672,-224,768,-128],"e-quay","e-terrace-west",96,48),_stair("boathouse-steps",[640,128,736,224],"e-terrace-west","e-beach",48,0,"p1"),
			_stair("rock-steps-low",[1392,128,1488,224],"r-terrace","r-beach",48,0),_stair("rock-steps-high",[1392,-224,1488,-128],"r-quay","r-terrace",96,48),
			_stair("mole-steps",[-912,-224,-816,-128],"mole-quay","mole-terrace",96,48),_stair("mole-slip",[-912,128,-816,224],"mole-terrace","mole-beach",48,0)],
		"bridges":[_bridge("sand-1",[-128,288,0,416],"w-beach","m-beach",0),_bridge("stones-1",[-128,-64,0,64],"w-terrace","m-terrace",48),
			_bridge("jetty-1",[-128,-416,0,-288],"w-quay","m-quay",96),_bridge("stones-2",[384,-64,576,64],"m-terrace","e-terrace-west",48),
			_bridge("jetty-2",[384,-416,576,-288],"m-quay","e-quay",96),_bridge("lock-west",[768,-64,832,64],"e-terrace-west","lock-chamber",48),
			_bridge("lock-east",[928,-64,992,64],"lock-chamber","e-terrace-east",48),_bridge("slipway",[1152,288,1344,416],"e-beach","r-beach",0),
			_bridge("stones-3",[1152,-64,1344,64],"e-terrace-east","r-terrace",48),_bridge("jetty-3",[1152,-416,1344,-288],"e-quay","r-quay",96),
			_bridge("quay-step",[32,-544,96,-480],"m-quay","quay-step",96,"p0"),_bridge("wheel-step",[160,-544,224,-480],"m-quay","wheel-step",96,"p0"),
			_bridge("bollard-step",[288,-544,352,-480],"m-quay","bollard-step",96,"p0"),
			_bridge("towpath",[192,368,576,448],"m-beach","e-beach",0),_bridge("boom-jetty",[-704,-416,-512,-288],"w-quay","mole-quay",96,"p0"),
			_bridge("sea-gate-in",[-576,-64,-512,64],"w-terrace","sea-chamber",48,"p0"),_bridge("sea-gate-out",[-704,-64,-640,64],"sea-chamber","mole-terrace",48,"p0"),
			_bridge("punt-ferry",[-704,288,-512,416],"w-beach","mole-beach",0,"p0"),_bridge("race-stage",[192,-192,256,-128],"m-terrace","race-stage",48,"p0"),
			_bridge("punt-catwalk",[-512,-192,-456,-128],"w-terrace","punt-catwalk",48,"p1"),_bridge("punt-post",[-440,-192,-384,-128],"w-terrace","punt-post",48,"p1"),
			_bridge("gate-catwalk",[-368,-192,-312,-128],"w-terrace","gate-catwalk",48,"p1"),_bridge("gate-post",[-296,-192,-240,-128],"w-terrace","gate-post",48,"p1"),
			_bridge("boom-catwalk",[-368,128,-312,192],"w-terrace","boom-catwalk",48,"p1"),_bridge("boom-post",[-296,128,-240,192],"w-terrace","boom-post",48,"p1")],
		"drops":[{"id":"spout","rect_cm":[600,268,648,308],"surface_id":"aq-span","destination_surface":"e-beach","height_cm":0,"requires_lever":"sluice"}],
		"access_zones":[{"id":"spout-lip","rect_cm":[552,256,672,320],"surface_id":"aq-span","owner_slot":"p1"}],
		"stages":[_set_the_tide(),_slack_water()]}

static func _tide() -> Dictionary:
	return _selector("tide",[192,-352],"m-quay",96,"p0",["low","half","high"],"low")

static func _lock() -> Dictionary:
	return _selector("lock",[880,48],"lock-chamber",48,"p1",["west","east"],"west")

static func _is(control: String, value: String) -> Dictionary:
	return {"control_id":control,"value":value}

static func _matched(control: String) -> Dictionary:
	var ways: Array = []
	for value: String in ["low","half","high"]: ways.append({"all":[_is(control,value),_is("tide",value)]})
	return {"any":ways}

static func _set_the_tide() -> Dictionary:
	var low := {"id":"low","pad_id":"wheel-step-pad","receiver_route_cm":[[320,128],[1344,352],[1440,0]],"receiver_action_ticks":2}
	var half := {"id":"half","pad_id":"quay-step-pad","receiver_route_cm":[[832,0],[880,48],[1440,0]],"receiver_action_ticks":4}
	var high := {"id":"high","pad_id":"bollard-pad","receiver_route_cm":[[1344,-352],[1440,0]],"receiver_action_ticks":4}
	var gates: Array = []
	for id: String in ["w-steps-low","w-steps-high","mill-steps","mill-ladder","east-steps","boathouse-steps","rock-steps-low","rock-steps-high"]: gates.append({"route_id":id})
	gates.append_array([{"route_id":"sand-1","when":_is("tide","low")},{"route_id":"stones-1","when":_is("tide","half")},{"route_id":"jetty-1","when":_is("tide","high")},
		{"route_id":"stones-2","when":_is("tide","half")},{"route_id":"jetty-2","when":_is("tide","high")},
		{"route_id":"slipway","when":{"all":[_is("tide","low"),_is("winch","slip")]}},
		{"route_id":"stones-3","when":{"all":[_is("tide","half"),{"lever_id":"sluice"}]}},
		{"route_id":"jetty-3","when":{"all":[_is("tide","high"),{"pad_id":"bollard-pad"},{"lever_id":"gangway"}]}},
		{"route_id":"lock-west","when":_is("lock","west")},{"route_id":"lock-east","when":_is("lock","east")},
		{"route_id":"wheel-step","when":{"all":[_is("tide","low"),_is("winch","slip"),{"lever_id":"sluice"}]}},
		{"route_id":"quay-step","when":{"all":[_is("tide","half"),{"lever_id":"sluice"}]}},
		{"route_id":"bollard-step","when":{"all":[_is("tide","high"),{"lever_id":"line"}]}}])
	return {"id":"set-the-tide","version":1,"title":"Set the Tide","first_player_slot":"p0","kind":"choice_pad","ball_pads":[],
		"controls":[_tide(),_selector("winch",[624,-448],"e-quay",96,"p0",["stowed","slip"],"stowed"),_lock()],
		"levers":[_point("sluice",[704,96],"e-terrace-west",48,"p0",28),_point("line",[1088,-448],"e-quay",96,"p0",28),_point("gangway",[1104,-352],"e-quay",96,"p1",28)],
		"pressure_pads":[_point("wheel-step-pad",[192,-512],"wheel-step",96,"p0",20),_point("quay-step-pad",[64,-512],"quay-step",96,"p0",20),_point("bollard-pad",[320,-512],"bollard-step",96,"p0",20)],
		"gates":gates,
		"entry_latch_routes":["sand-1","stones-1","jetty-1","stones-2","jetty-2","slipway","stones-3","jetty-3"],
		"source_policy":{"kind":"choice_pad","branches":[low,half,high]},
		"goal_policy":{"kind":"ring"},"goal":_point("harbour-bell",[1440,0],"r-terrace",48,"p1",28),
		"receiver_route_cm":high.receiver_route_cm,"receiver_action_ticks":4,
		"hint_a":"Stub hint.","hint_b":"Stub hint."}

static func _slack_water() -> Dictionary:
	var boom := {"id":"boom","pad_id":"boom-post-pad","receiver_route_cm":[[192,-352],[-512,-352],[192,-352],[-864,-128],[-832,0]],"receiver_action_ticks":8}
	var sea_lock := {"id":"sea-lock","pad_id":"gate-post-pad","receiver_route_cm":[[192,-352],[-512,0],[192,-352],[-608,48],[-832,0]],"receiver_action_ticks":12}
	var punt := {"id":"punt","pad_id":"punt-post-pad","receiver_route_cm":[[192,-352],[96,-128],[224,-160],[96,-128],[192,-352],[-704,352],[-864,128],[-832,0]],"receiver_action_ticks":10}
	var slack := {"any":[{"all":[_is("basin","low"),_is("tide","low")]},{"all":[_is("basin","half"),_is("tide","half")]},{"all":[_is("basin","high"),_is("tide","high")]}]}
	var gates: Array = []
	for id: String in ["w-steps-low","w-steps-high","mill-steps","mill-ladder","east-steps","boathouse-steps","rock-steps-low","rock-steps-high","mole-slip","towpath"]: gates.append({"route_id":id})
	gates.append_array([{"route_id":"sand-1","when":_is("tide","low")},{"route_id":"stones-1","when":_is("tide","half")},{"route_id":"jetty-1","when":_is("tide","high")},
		{"route_id":"stones-2","when":_is("tide","half")},{"route_id":"jetty-2","when":_is("tide","high")},
		{"route_id":"lock-west","when":_is("lock","west")},{"route_id":"lock-east","when":_is("lock","east")},
		{"route_id":"boom-jetty","when":{"all":[{"lever_id":"boom-chain"},_is("basin","high"),_is("tide","high")]}},
		{"route_id":"mole-steps","when":_is("tide","low")},
		{"route_id":"sea-gate-in","when":{"all":[{"lever_id":"gate-bar"},_matched("chamber")]}},
		{"route_id":"sea-gate-out","when":{"all":[{"lever_id":"gate-bar"},_is("basin","low"),_is("chamber","low"),_is("tide","high")]}},
		{"route_id":"race-stage","when":_is("tide","low")},
		{"route_id":"punt-ferry","when":{"all":[{"lever_id":"punt-chain"},{"lever_id":"punt-line"},_is("basin","half"),_is("tide","half")]}},
		{"route_id":"boom-catwalk","when":slack.duplicate(true)},{"route_id":"gate-catwalk","when":slack.duplicate(true)},{"route_id":"punt-catwalk","when":slack.duplicate(true)},
		{"route_id":"boom-post","when":{"all":[{"lever_id":"boom-chain"},_is("basin","high")]}},
		{"route_id":"gate-post","when":{"all":[{"lever_id":"gate-bar"},_is("basin","low")]}},
		{"route_id":"punt-post","when":{"all":[{"lever_id":"punt-chain"},_is("basin","half")]}}])
	return {"id":"slack-water","version":1,"title":"Slack Water","first_player_slot":"p1","kind":"choice_pad","ball_pads":[],
		"controls":[_tide(),_lock(),_selector("chamber",[-608,48],"sea-chamber",48,"p0",["low","half","high"],"half"),
			_selector("basin",[-312,-64],"w-terrace",48,"p1",["shut","low","half","high"],"shut")],
		"levers":[_point("boom-chain",[-340,160],"boom-catwalk",48,"p1",28),_point("gate-bar",[-340,-160],"gate-catwalk",48,"p1",28),
			_point("punt-chain",[-484,-160],"punt-catwalk",48,"p1",28),_point("punt-line",[224,-160],"race-stage",48,"p0",28)],
		"pressure_pads":[_point("boom-post-pad",[-268,160],"boom-post",48,"p1",16),_point("gate-post-pad",[-268,-160],"gate-post",48,"p1",16),
			_point("punt-post-pad",[-412,-160],"punt-post",48,"p1",16)],
		"gates":gates,
		"entry_latch_routes":["sand-1","stones-1","jetty-1","stones-2","jetty-2","lock-west","lock-east","towpath","boom-jetty","mole-steps","sea-gate-in","sea-gate-out","race-stage","punt-ferry"],
		"source_policy":{"kind":"choice_pad","branches":[boom,sea_lock,punt]},
		"goal_policy":{"kind":"ring"},"goal":_point("harbour-lantern",[-832,0],"mole-terrace",48,"p0",28),
		"receiver_route_cm":sea_lock.receiver_route_cm,"receiver_action_ticks":12,
		"hint_a":"Stub hint.","hint_b":"Stub hint."}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":height}

static func _bridge(id: String, rect: Array, from: String, to: String, height: int, owner: String = "") -> Dictionary:
	return {"id":id,"rect_cm":rect,"from_surface":from,"to_surface":to,"height_cm":height,"owner_slot":owner}

static func _stair(id: String, rect: Array, from: String, to: String, low: int, high: int, owner: String = "") -> Dictionary:
	return {"id":id,"rect_cm":rect,"axis":"z","from_surface":from,"to_surface":to,"from_height_cm":low,"to_height_cm":high,"owner_slot":owner}

static func _point(id: String, position: Array, surface: String, height: int, owner: String, radius: int) -> Dictionary:
	return {"id":id,"position_cm":position,"surface_id":surface,"height_cm":height,"owner_slot":owner,"radius_cm":radius}

static func _selector(id: String, position: Array, surface: String, height: int, owner: String, values: Array, initial: String) -> Dictionary:
	var result := _point(id,position,surface,height,owner,28)
	result.merge({"kind":"selector","values":values,"initial":initial})
	return result
