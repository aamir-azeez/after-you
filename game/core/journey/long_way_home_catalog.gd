extends RefCounted
## Authored untimed route choices and the two-window homecoming.

static func definition() -> Dictionary:
	return {"schema_version":7,"simulation_version":7,"id":"long-way-home","version":1,"title":"Long Way Home","premium":true,
		"starts":{"p0":{"position_cm":[-528,64],"height_cm":0,"surface_id":"source-court"},"p1":{"position_cm":[-416,400],"height_cm":0,"surface_id":"partner-bank"}},"props":[],
		"islands":[_island("source-court",[-640,-352,-256,160],0),_island("partner-bank",[-640,224,-256,544],0),_island("selector-landing",[-64,-64,192,320],0),
			_island("upper-lane",[-64,-352,640,-160],160),_island("drop-landing",[512,-320,640,-160],0),_island("recovery-landing",[288,32,384,128],0),_island("garden",[384,-96,768,320],0),
			_island("service-landing",[864,-128,1024,64],96),_island("near-porch",[896,160,1024,288],0),_island("garden-walk",[704,384,1184,480],0),_island("home-room",[1120,-96,1504,320],0)],
		"stairs":[_stair("upper-stair",[-256,-288,-64,-192],"x","source-court","upper-lane",0,160,"p0"),
			_stair("recovery-stair",[288,-160,384,32],"z","upper-lane","recovery-landing",160,0,"p0"),
			_stair("service-up",[768,-64,864,32],"x","garden","service-landing",0,96,"p1"),
			_stair("service-down",[1024,-64,1120,32],"x","service-landing","home-room",96,0,"p1")],
		"bridges":[_bridge("court-landing",[-256,-48,-64,48],"source-court","selector-landing","p0"),
			_bridge("friend-crossing",[-256,224,-64,320],"partner-bank","selector-landing","p1"),
			_bridge("home-shortcut",[192,32,384,128],"selector-landing","garden"),
			_bridge("drop-garden",[528,-160,624,-96],"drop-landing","garden","p0"),
			_bridge("near-crossing",[768,176,896,272],"garden","near-porch","p0"),
			_bridge("porch-door",[1024,176,1120,272],"near-porch","home-room","p0"),
			_bridge("garden-arch",[704,320,768,384],"garden","garden-walk","p0"),
			_bridge("garden-door",[1120,320,1184,384],"garden-walk","home-room","p0")],
		"drops":[{"id":"garden-descent","rect_cm":[536,-264,584,-216],"surface_id":"upper-lane","destination_surface":"drop-landing","height_cm":0}],
		"stages":[_leave_a_path(),_welcome_home()]}

static func _leave_a_path() -> Dictionary:
	return {"id":"the-path-you-leave","version":1,"title":"The Path You Leave","first_player_slot":"p0","kind":"route_endpoint","levers":[],"pressure_pads":[],"ball_pads":[],
		"controls":[_selector("path-selector",[64,64],"selector-landing","p0",["home","friend"],"home"),_selector("return-selector",[128,224],"selector-landing","p1",["bank","garden"],"bank")],
		"gates":[{"route_id":"court-landing"},{"route_id":"upper-stair"},{"route_id":"recovery-stair"},{"route_id":"drop-garden"},
			{"route_id":"friend-crossing","when":{"all":[{"control_id":"path-selector","value":"friend"},{"control_id":"return-selector","value":"bank"}]}},
			{"route_id":"home-shortcut","when":{"any":[{"control_id":"path-selector","value":"home"},{"control_id":"return-selector","value":"garden"}]}}],
		"entry_latch_routes":["friend-crossing","home-shortcut"],
		"source_policy":{"kind":"route_endpoint","when":{"control_id":"path-selector","value":"friend"},"endpoint":_point("garden-wait",[640,32],"garden","p0",64)},
		"goal_policy":{"kind":"ring","when":{"control_id":"return-selector","value":"garden"}},"goal":_point("garden-window",[640,224],"garden","p1",28),
		"receiver_route_cm":[[-416,304],[-16,304],[128,224],[128,80],[512,80],[640,224]],"receiver_action_ticks":2,
		"hint_a":"Leave a trail for your partner and then go to the garden on your own.","hint_b":"Reach the garden."}

static func _welcome_home() -> Dictionary:
	var near: Dictionary={"id":"near","pad_id":"near-window","receiver_route_cm":[[704,224],[960,224],[1168,224],[1408,96]],"receiver_action_ticks":2}
	var garden: Dictionary={"id":"garden","pad_id":"garden-window","receiver_route_cm":[[736,288],[736,432],[1152,432],[1152,272],[1408,96]],"receiver_action_ticks":1}
	return {"id":"a-place-beside-you","version":1,"title":"A Place Beside You","first_player_slot":"p1","kind":"choice_pad","controls":[],"ball_pads":[],
		"levers":[_point("porch-shutter",[960,224],"near-porch","p0",28)],
		"pressure_pads":[_point("near-window",[1200,32],"home-room","p1",36),_point("garden-window",[1200,144],"home-room","p1",36)],
		"gates":[{"route_id":"service-up"},{"route_id":"service-down"},
			{"route_id":"near-crossing","when":{"pad_id":"near-window"}},
			{"route_id":"porch-door","when":{"all":[{"pad_id":"near-window"},{"lever_id":"porch-shutter"}]}},
			{"route_id":"garden-arch","when":{"pad_id":"garden-window"}},{"route_id":"garden-door","when":{"pad_id":"garden-window"}}],
		"entry_latch_routes":["near-crossing","porch-door","garden-arch","garden-door"],
		"source_policy":{"kind":"choice_pad","branches":[near,garden]},"goal_policy":{"kind":"ring"},"goal":_point("second-window",[1408,96],"home-room","p0",28),
		"receiver_route_cm":near.receiver_route_cm,"receiver_action_ticks":2,
		"hint_a":"Pick a window to greet your partner when they come home.","hint_b":"Follow the open path and light the second window."}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":height}

static func _bridge(id: String, rect: Array, from: String, to: String, owner: String="") -> Dictionary:
	return {"id":id,"rect_cm":rect,"from_surface":from,"to_surface":to,"height_cm":0,"owner_slot":owner}

static func _stair(id: String, rect: Array, axis: String, from: String, to: String, low: int, high: int, owner: String) -> Dictionary:
	return {"id":id,"rect_cm":rect,"axis":axis,"from_surface":from,"to_surface":to,"from_height_cm":low,"to_height_cm":high,"owner_slot":owner}

static func _point(id: String, position: Array, surface: String, owner: String, radius: int) -> Dictionary:
	return {"id":id,"position_cm":position,"surface_id":surface,"height_cm":0,"owner_slot":owner,"radius_cm":radius}

static func _selector(id: String, position: Array, surface: String, owner: String, values: Array, initial: String) -> Dictionary:
	var result:=_point(id,position,surface,owner,28)
	result.merge({"kind":"selector","values":values,"initial":initial})
	return result
