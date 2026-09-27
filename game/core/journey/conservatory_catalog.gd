extends RefCounted
## Authored light circuits and shared physical routes for Conservatory.

static func definition() -> Dictionary:
	return {"schema_version":7,"simulation_version":7,"id":"conservatory","version":1,"title":"Conservatory","premium":true,
		"starts":{"p0":{"position_cm":[-528,144],"height_cm":0,"surface_id":"court"},"p1":{"position_cm":[-208,-256],"height_cm":0,"surface_id":"court"}},"props":[],
		"islands":[_island("court",[-640,-448,-160,320],0),_island("gallery",[32,-448,672,-128],160),_island("recovery-landing",[32,-128,128,64],160),
			_island("lower-room",[320,-320,448,320],0),_island("garden",[544,-128,864,320],0),_island("mirror-room",[-96,-96,96,96],0)],
		"stairs":[_stair("high-stair",[-160,-304,32,-208],"court","gallery",0,160),_stair("recovery-stair",[128,-96,320,0],"recovery-landing","lower-room",160,0)],
		"bridges":[_bridge("garden-door",[448,-32,544,64],"lower-room","garden"),_bridge("lower-crossing",[-160,160,320,256],"court","lower-room","p0"),
			_bridge("court-return",[-160,16,-96,96],"court","mirror-room","p0"),_bridge("room-return",[96,16,320,96],"mirror-room","lower-room","p0")],
		"drops":[{"id":"gallery-hatch","rect_cm":[392,-264,440,-216],"surface_id":"gallery","destination_surface":"lower-room","height_cm":0}],
		"stages":[_first(),_second()]}

static func _first() -> Dictionary:
	var controls: Array=[_mirror("court-fork",[-416,128],"court","p0",0,"backslash"),_mirror("high-return",[-416,-352],"court","p0",0,"backslash"),
		_mirror("preserved-turn",[-224,-352],"court","p0",0,"backslash"),_mirror("gallery-fork",[384,-352],"gallery","p1",160,"backslash"),_mirror("garden-return",[384,-192],"gallery","p1",160,"backslash")]
	var field:=_field(controls,[_emitter("court-lamp",[-592,128],"east"),_emitter("gallery-lamp",[192,-352],"east")],
		[_receiver("high-light",[-224,-128]),_receiver("low-warm",[-416,288]),_receiver("garden-light",[192,-192]),_receiver("east-warm",[576,-192])])
	return {"id":"a-light-above","version":1,"title":"A Light Above","first_player_slot":"p0","kind":"signal_route","controls":controls,"optical_field":field,"levers":[],"pressure_pads":[],"ball_pads":[],
		"gates":[{"route_id":"high-stair","when":{"signal_id":"high-light"}},{"route_id":"recovery-stair"},{"route_id":"garden-door","when":{"signal_id":"garden-light"}}],
		"entry_latch_routes":["high-stair","garden-door"],"source_policy":{"kind":"signal_route","when":{"signal_id":"high-light"}},
		"goal_policy":{"kind":"ring","when":{"all":[{"signal_id":"high-light"},{"signal_id":"garden-light"}]}},"goal":_point("first-garden",[752,160],"garden","p1",28),
		"receiver_route_cm":[[-208,-256],[384,-256],[384,-192],[416,-192],[416,-240],[416,16],[752,16],[752,160]],"receiver_action_ticks":2,
		"hint_a":"Point the light at the top steps.","hint_b":"Reach the garden."}

static func _second() -> Dictionary:
	var controls: Array=[_mirror("lower-fork",[592,160],"garden","p1",0,"backslash"),_mirror("crossing-return",[592,-64],"garden","p1",0,"backslash"),_mirror("final-mirror",[0,0],"mirror-room","p0",0,"backslash")]
	var field:=_field(controls,[_emitter("garden-lamp",[784,160],"west"),_emitter("return-lamp",[-48,0],"east")],
		[_receiver("crossing-light",[784,-64]),_receiver("south-warm",[592,288]),_receiver("second-light",[0,-80]),_receiver("room-warm",[0,64])])
	return {"id":"the-way-light-returns","version":1,"title":"The Way Light Returns","first_player_slot":"p1","kind":"signal_route","controls":controls,"optical_field":field,"pressure_pads":[],"ball_pads":[],
		"levers":[_point("return-shutter",[352,64],"lower-room","p0",28)],
		"gates":[{"route_id":"lower-crossing","when":{"signal_id":"crossing-light"}},{"route_id":"court-return","when":{"lever_id":"return-shutter"}},{"route_id":"room-return","when":{"lever_id":"return-shutter"}}],
		"entry_latch_routes":["lower-crossing"],"source_policy":{"kind":"signal_route","when":{"signal_id":"crossing-light"},"endpoint":_point("garden-wait",[656,64],"garden","p1",96)},
		"goal_policy":{"kind":"ring","when":{"all":[{"signal_id":"crossing-light"},{"signal_id":"second-light"}]}},"goal":_point("two-lights",[752,64],"garden","p0",28),
		"receiver_route_cm":[[-304,208],[384,208],[352,64],[0,64],[0,0],[0,64],[384,64],[384,16],[752,16],[752,64]],"receiver_action_ticks":3,
		"hint_a":"Leave the lower crossing lit and wait in the garden.","hint_b":"Open the return shutter and bring both lights to the garden."}

static func _field(controls: Array, emitters: Array, receivers: Array) -> Dictionary:
	var mirrors: Array=[]
	for control: Dictionary in controls:
		mirrors.append({"id":control.id,"position_cm":control.position_cm.duplicate(),"enabled":true,"orientation":control.initial})
	return {"schema_version":1,"bounds_cm":[-704,-512,928,384],"emitters":emitters,"mirrors":mirrors,"receivers":receivers,"blockers":[]}

static func _mirror(id: String, position: Array, surface: String, owner: String, height: int, initial: String) -> Dictionary:
	var result:=_point(id,position,surface,owner,28)
	result.merge({"kind":"mirror","height_cm":height,"initial":initial,"values":["slash","backslash"]},true)
	return result

static func _emitter(id: String, position: Array, direction: String) -> Dictionary:
	return {"id":id,"position_cm":position,"enabled":true,"direction":direction}

static func _receiver(id: String, position: Array) -> Dictionary:
	return {"id":id,"position_cm":position,"enabled":true}

static func _point(id: String, position: Array, surface: String, owner: String, radius: int) -> Dictionary:
	return {"id":id,"position_cm":position,"surface_id":surface,"height_cm":0,"owner_slot":owner,"radius_cm":radius}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":height}

static func _bridge(id: String, rect: Array, from: String, to: String, owner: String="") -> Dictionary:
	return {"id":id,"rect_cm":rect,"height_cm":0,"from_surface":from,"to_surface":to,"owner_slot":owner}

static func _stair(id: String, rect: Array, from: String, to: String, low: int, high: int) -> Dictionary:
	return {"id":id,"rect_cm":rect,"axis":"x","from_surface":from,"to_surface":to,"from_height_cm":low,"to_height_cm":high,"owner_slot":"p1"}
