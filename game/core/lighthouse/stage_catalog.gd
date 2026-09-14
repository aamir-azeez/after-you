extends RefCounted
## Authored Lighthouse stages. Unimplemented chapter stages are not selectable.

const STAGE_IDS := ["borrowed-light", "missing-piece", "two-promises", "after-the-first-bell", "what-carried-you"]

static func definition(stage_id: String = "borrowed-light") -> Dictionary:
	if stage_id == "borrowed-light":
		return _borrowed_light()
	if stage_id == "missing-piece":
		return _missing_piece()
	if stage_id == "two-promises":
		return _two_promises()
	if stage_id == "after-the-first-bell":
		return _after_the_first_bell()
	if stage_id == "what-carried-you":
		return _what_carried_you()
	return {}

static func _borrowed_light() -> Dictionary:
	return {
		"schema_version": 3, "simulation_version": 3, "id": "sleeping-lighthouse", "version": 1,
		"title": "Borrowed Light", "stage_id": "borrowed-light", "stage_version": 1,
		"first_player_slot": "p0", "starts": {"p0": [-760, -100], "p1": [-520, 80]},
		"islands": [{"id": "harbour", "rect_cm": [-850, -180, -450, 180], "height_cm": 0}, {"id": "court", "rect_cm": [-250, -130, 150, 130], "height_cm": 0}],
		"bridges": [{"id": "harbour-court", "rect_cm": [-450, -50, -250, 50], "from_surface": "harbour", "to_surface": "court", "receiver_id": "harbour-receiver"}],
		"plate": {"id": "source-pad", "position_cm": [-700, -100], "radius_cm": 32, "owner_slot": "p0", "emitter_id": "harbour-light"},
		"mirror_control": {"id": "harbour-mirror", "position_cm": [-560, -100], "radius_cm": 36, "owner_slot": "p1"},
		"goal": {"id": "court-bell", "position_cm": [-160, 0], "radius_cm": 30, "surface_id": "court"},
		# The axis-aligned receiver witness starts at p1, visits the mirror, then
		# the bridge centre line and bell. It is a conservative source budget,
		# not a general path solver. Tests execute this route with real controls.
		"receiver_route_cm": [[-520, 80], [-560, 80], [-560, -100], [-560, 0], [-160, 0]],
		"hint_a": "Stand on the light pad. Keep it shining, then finish your recording.",
		"hint_b": "Turn the mirror toward the receiver. Cross the lit bridge and ring the Court bell.",
		"optics": {"schema_version": 1, "bounds_cm": [-900, -240, 250, 240],
			"emitters": [{"id": "harbour-light", "position_cm": [-690, -100], "direction": "east", "enabled": false}],
			"mirrors": [{"id": "harbour-mirror", "position_cm": [-560, -100], "orientation": "backslash", "enabled": true}],
			"receivers": [{"id": "harbour-receiver", "position_cm": [-560, -160], "enabled": true}], "blockers": []}
	}

static func _missing_piece() -> Dictionary:
	return {
		"schema_version": 3, "simulation_version": 3, "id": "sleeping-lighthouse", "version": 1,
		"title": "The Missing Piece", "stage_id": "missing-piece", "stage_version": 1,
		"first_player_slot": "p1",
		"islands": [{"id": "harbour", "rect_cm": [-850,-180,-450,180], "height_cm": 0}, {"id": "court", "rect_cm": [-250,-130,150,130], "height_cm": 0}, {"id": "north", "rect_cm": [-250,-500,150,-240], "height_cm": 0}],
		"bridges": [{"id": "harbour-court", "rect_cm": [-450,-50,-250,50], "from_surface": "harbour", "to_surface": "court", "receiver_id": ""}, {"id": "court-north", "rect_cm": [-100,-240,0,-130], "from_surface": "court", "to_surface": "north", "receiver_id": "north-receiver"}],
		"controls": [{"id": "court-mirror", "kind": "mirror", "position_cm": [-80,0], "radius_cm": 36, "owner_slot": "p1", "optical_id": "court-mirror"}],
		"props": [{"id": "portable-lens", "position_cm": [40,-360], "radius_cm": 32, "surface_id": "north", "owner_slot": "p0", "socket_id": "court-cradle"}],
		"sockets": [{"id": "court-cradle", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "prop_id": "portable-lens", "owner_slot": "p0"}],
		"source_policy": {"kind": "steady_receiver", "receiver_id": "north-receiver"},
		"goal_policy": {"kind": "fit_prop", "prop_id": "portable-lens", "socket_id": "court-cradle"},
		# The first waypoint is the exact checkpoint endpoint, supplied locally.
		# Both trips cross the bridge centre line; two actions and seam allowance
		# are included by the engine. This is an authored witness, not a solver.
		"receiver_route_cm": [[-728,0],[-48,0],[-48,-360],[40,-360],[-48,-360],[-48,60],[40,60]],
		"hint_a": "Turn the Court mirror toward North. Leave the path lit for your partner.",
		"hint_b": "Follow the lit bridge. Take the lens, then fit it into the matching Court cradle.",
		"optics": {"schema_version": 1, "bounds_cm": [-900,-560,250,240],
			"emitters": [{"id": "court-light", "position_cm": [-200,0], "direction": "east", "enabled": true}],
			"mirrors": [{"id": "court-mirror", "position_cm": [-80,0], "orientation": "backslash", "enabled": true}],
			"receivers": [{"id": "north-receiver", "position_cm": [-80,-300], "enabled": true}], "blockers": []}
	}

static func _two_promises() -> Dictionary:
	return {
		"schema_version": 3, "simulation_version": 3, "id": "sleeping-lighthouse", "version": 1,
		"title": "Two Promises", "stage_id": "two-promises", "stage_version": 1,
		"first_player_slot": "p0",
		"islands": [{"id": "harbour", "rect_cm": [-850,-180,-450,180], "height_cm": 0}, {"id": "court", "rect_cm": [-250,-130,150,130], "height_cm": 0}, {"id": "north", "rect_cm": [-250,-500,150,-240], "height_cm": 0}, {"id": "south", "rect_cm": [-250,240,150,500], "height_cm": 0}],
		"bridges": [{"id": "harbour-court", "rect_cm": [-450,-50,-250,50], "from_surface": "harbour", "to_surface": "court", "receiver_id": ""}, {"id": "court-north", "rect_cm": [-100,-240,0,-130], "from_surface": "court", "to_surface": "north", "receiver_id": ""}, {"id": "court-south", "rect_cm": [-100,130,0,240], "from_surface": "court", "to_surface": "south", "receiver_id": "", "prop_gate": {"prop_id": "portable-lens", "socket_id": "court-cradle"}}],
		"controls": [{"id": "upper-mirror", "kind": "mirror", "position_cm": [-80,60], "radius_cm": 36, "owner_slot": "p0", "optical_id": "upper-mirror"}, {"id": "south-mirror", "kind": "mirror", "position_cm": [56,350], "radius_cm": 36, "owner_slot": "p1", "optical_id": "south-mirror"}],
		# The lens is carried state, not a new collectible. This stage cannot be
		# started without replaying the pair that fitted this exact prop/socket.
		"props": [{"id": "portable-lens", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "owner_slot": "p0", "socket_id": "court-cradle"}],
		"sockets": [{"id": "court-cradle", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "prop_id": "portable-lens", "owner_slot": "p0"}],
		"required_props": [{"prop_id": "portable-lens", "socket_id": "court-cradle"}],
		"emitter_sources": [{"emitter_id": "lens-upper", "prop_id": "portable-lens", "socket_id": "court-cradle"}, {"emitter_id": "lens-lower", "prop_id": "portable-lens", "socket_id": "court-cradle"}],
		"source_policy": {"kind": "steady_receiver", "receiver_id": "north-promise", "early_hint": "Align the upper mirror earlier so your partner can reach the South control.", "unlit_hint": "Turn the upper mirror toward the North receiver.", "broken_hint": "The North promise was interrupted. Leave the upper mirror aligned through Finish.", "steady_hint": "Leave the North promise steady for a moment before finishing."},
		"goal_policy": {"kind": "all_receivers", "receiver_ids": ["north-promise", "south-promise"], "checkpoint_flag": "east-selector-powered"},
		# Receiver approaches are authored on permanent/remembered surfaces and
		# instantiated from its actual inherited coordinates, never a reset spawn.
		"receiver_route_entries": {"harbour": {"align_axis": "z", "align_cm": 0, "join_cm": [-48,0]}, "harbour-court": {"align_axis": "z", "align_cm": 0, "join_cm": [-48,0]}, "court": {"align_axis": "x", "align_cm": -48}, "court-north": {"align_axis": "x", "align_cm": -48}, "north": {"align_axis": "x", "align_cm": -48}},
		"receiver_route_cm": [[-48,350],[56,350]], "receiver_action_ticks": 1,
		"hint_a": "The fitted lens has two paths. Turn the upper mirror toward North and leave that promise lit.",
		"hint_b": "Your friend's North light is kept. Cross the safe South bridge and align the other mirror so both symbols shine.",
		"completion_message": "Two promises, kept together. Preview, then save this contribution.",
		"optics": {"schema_version": 1, "bounds_cm": [-900,-560,250,560],
			"emitters": [{"id": "lens-upper", "position_cm": [24,60], "direction": "west", "enabled": false}, {"id": "lens-lower", "position_cm": [56,60], "direction": "south", "enabled": false}],
			"mirrors": [{"id": "upper-mirror", "position_cm": [-80,60], "orientation": "slash", "enabled": true}, {"id": "south-mirror", "position_cm": [56,350], "orientation": "slash", "enabled": true}],
			"receivers": [{"id": "north-promise", "position_cm": [-80,-360], "enabled": true}, {"id": "south-promise", "position_cm": [120,350], "enabled": true}], "blockers": []}
	}

static func _after_the_first_bell() -> Dictionary:
	return {
		"schema_version": 3, "simulation_version": 3, "id": "sleeping-lighthouse", "version": 1,
		"title": "After the First Bell", "stage_id": "after-the-first-bell", "stage_version": 1,
		"first_player_slot": "p1",
		"islands": [{"id": "harbour", "rect_cm": [-850,-180,-450,180], "height_cm": 0}, {"id": "court", "rect_cm": [-250,-130,150,130], "height_cm": 0}, {"id": "north", "rect_cm": [-250,-500,150,-240], "height_cm": 0}, {"id": "south", "rect_cm": [-250,240,150,500], "height_cm": 0}, {"id": "rest-rock", "rect_cm": [240,-100,340,100], "height_cm": 0}, {"id": "tower", "rect_cm": [450,-180,850,180], "height_cm": 0}],
		"bridges": [{"id": "harbour-court", "rect_cm": [-450,-50,-250,50], "from_surface": "harbour", "to_surface": "court", "receiver_id": ""}, {"id": "court-north", "rect_cm": [-100,-240,0,-130], "from_surface": "court", "to_surface": "north", "receiver_id": ""}, {"id": "court-south", "rect_cm": [-100,130,0,240], "from_surface": "court", "to_surface": "south", "receiver_id": ""}, {"id": "court-rest", "rect_cm": [150,-50,240,50], "from_surface": "court", "to_surface": "rest-rock", "receiver_id": "first-path", "latch_on_enter": true}, {"id": "rest-tower", "rect_cm": [340,-50,450,50], "from_surface": "rest-rock", "to_surface": "tower", "receiver_id": "second-path", "latch_on_enter": true}],
		"controls": [{"id": "south-selector", "kind": "selector", "position_cm": [56,350], "radius_cm": 36, "owner_slot": "p1", "optical_id": "south-selector", "states": ["off","first","second"], "labels": ["Light the first path", "Light the second path", "Restart the light sequence"], "emitter_id": "selector-light", "orientations": ["slash","slash","backslash"]}],
		"props": [{"id": "portable-lens", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "owner_slot": "p0", "socket_id": "court-cradle"}],
		"sockets": [{"id": "court-cradle", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "prop_id": "portable-lens", "owner_slot": "p0"}],
		"required_props": [{"prop_id": "portable-lens", "socket_id": "court-cradle"}],
		"required_flags": ["east-selector-powered"],
		"source_policy": {"kind": "ordered_windows", "selector_id": "south-selector", "receiver_ids": ["first-path","second-path"]},
		"goal_policy": {"kind": "ordered_crossing", "bridge_ids": ["court-rest","rest-tower"], "rest_surface": "rest-rock", "destination_surface": "tower", "checkpoint_flag": "tower-anchor-lit"},
		"goal": {"id": "tower-bell", "position_cm": [552,0], "radius_cm": 30, "surface_id": "tower"},
		# Each path window covers a real conservative receiver route plus a short
		# reaction margin. The first route begins at the verified physical endpoint;
		# no stage timer forces a fixed delay, and Rest Rock itself is always safe.
		"sequence_route_entries": {"harbour": {"axis": "z", "value": 0}, "harbour-court": {"axis": "z", "value": 0}, "court": {"axis": "z", "value": 0}, "court-north": {"axis": "x", "value": -48, "join_cm": [-48,0]}, "north": {"axis": "x", "value": -48, "join_cm": [-48,0]}, "court-south": {"axis": "x", "value": -48, "join_cm": [-48,0]}, "south": {"axis": "x", "value": -48, "join_cm": [-48,0]}},
		"sequence_routes_cm": [[[288,0]], [[288,0],[552,0]]], "sequence_margin_ticks": 18,
		"hint_a": "Light the first path long enough for your partner to reach Rest Rock, then light the second. Record both parts before finishing.",
		"hint_b": "Follow the first light to Rest Rock, then the second to the tower bell. A path keeps your footsteps once you enter it.",
		"completion_message": "The tower remembers the way you came. Preview, then save this contribution.",
		"optics": {"schema_version": 1, "bounds_cm": [-900,-560,900,560],
			"emitters": [{"id": "selector-light", "position_cm": [-120,350], "direction": "east", "enabled": false}],
			"mirrors": [{"id": "south-selector", "position_cm": [56,350], "orientation": "slash", "enabled": true}],
			"receivers": [{"id": "first-path", "position_cm": [56,250], "enabled": true}, {"id": "second-path", "position_cm": [56,470], "enabled": true}], "blockers": []}
	}

static func _what_carried_you() -> Dictionary:
	return {
		"schema_version": 3, "simulation_version": 3, "id": "sleeping-lighthouse", "version": 1,
		"title": "What Carried You Can Come With You", "stage_id": "what-carried-you", "stage_version": 1,
		"first_player_slot": "p0",
		"islands": [{"id": "harbour", "rect_cm": [-850,-180,-450,180], "height_cm": 0}, {"id": "court", "rect_cm": [-250,-130,150,130], "height_cm": 0}, {"id": "north", "rect_cm": [-250,-500,150,-240], "height_cm": 0}, {"id": "south", "rect_cm": [-250,240,150,500], "height_cm": 0}, {"id": "rest-rock", "rect_cm": [240,-100,340,100], "height_cm": 0}, {"id": "tower", "rect_cm": [450,-180,850,180], "height_cm": 0}],
		"bridges": [{"id": "harbour-court", "rect_cm": [-450,-50,-250,50], "from_surface": "harbour", "to_surface": "court", "receiver_id": ""}, {"id": "court-north", "rect_cm": [-100,-240,0,-130], "from_surface": "court", "to_surface": "north", "receiver_id": ""}, {"id": "court-south", "rect_cm": [-100,130,0,240], "from_surface": "court", "to_surface": "south", "receiver_id": ""}, {"id": "court-rest", "rect_cm": [150,-50,240,50], "from_surface": "court", "to_surface": "rest-rock", "receiver_id": ""}, {"id": "rest-tower", "rect_cm": [340,-50,450,50], "from_surface": "rest-rock", "to_surface": "tower", "receiver_id": ""}],
		"controls": [],
		"props": [{"id": "portable-lens", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "owner_slot": "p0", "socket_id": "court-cradle"}],
		"sockets": [{"id": "court-cradle", "position_cm": [40,60], "radius_cm": 32, "surface_id": "court", "prop_id": "portable-lens", "owner_slot": "p0"}, {"id": "rest-perch", "position_cm": [288,64], "radius_cm": 28, "surface_id": "rest-rock", "prop_id": "portable-lens", "owner_slot": "p0"}, {"id": "tower-projector", "position_cm": [650,0], "radius_cm": 30, "surface_id": "tower", "prop_id": "portable-lens", "owner_slot": "p1"}],
		"required_props": [{"prop_id": "portable-lens", "socket_id": "court-cradle"}],
		"required_flags": ["tower-anchor-lit"],
		"required_bridges": ["harbour-court","court-north","court-south","court-rest","rest-tower"],
		"source_policy": {"kind": "offer_prop", "prop_id": "portable-lens", "initial_socket_id": "court-cradle", "release_socket_id": "rest-perch"},
		"goal_policy": {"kind": "fit_handoff", "prop_id": "portable-lens", "socket_id": "tower-projector", "checkpoint_flag": "projector-loaded"},
		"emitter_sources": [{"emitter_id": "court-lens-light", "prop_id": "portable-lens", "socket_id": "court-cradle"}],
		"receiver_route_entries": {"harbour": {"align_axis": "z", "align_cm": 0}, "harbour-court": {"align_axis": "z", "align_cm": 0}, "court": {"align_axis": "z", "align_cm": 0}, "court-north": {"align_axis": "x", "align_cm": -48, "join_cm": [-48,0]}, "north": {"align_axis": "x", "align_cm": -48, "join_cm": [-48,0]}, "court-south": {"align_axis": "x", "align_cm": -48, "join_cm": [-48,0]}, "south": {"align_axis": "x", "align_cm": -48, "join_cm": [-48,0]}, "rest-rock": {"align_axis": "z", "align_cm": 0}, "tower": {"align_axis": "z", "align_cm": 0}},
		"receiver_route_cm": [[288,0],[288,64],[288,0],[650,0]], "receiver_action_ticks": 2,
		"hint_a": "The paths remember. Take the Court lens and leave it on the matching perch at Rest Rock for your partner.",
		"hint_b": "Meet your friend's recording at Rest Rock. Take the lens they leave, then fit it into the tower projector.",
		"completion_message": "What carried you has come with you. Preview, then save this contribution.",
		"optics": {"schema_version": 1, "bounds_cm": [-900,-560,900,560],
			"emitters": [{"id": "court-lens-light", "position_cm": [24,60], "direction": "west", "enabled": false}],
			"mirrors": [{"id": "upper-mirror", "position_cm": [-80,60], "orientation": "backslash", "enabled": true}],
			"receivers": [{"id": "remembered-north", "position_cm": [-80,-360], "enabled": true}], "blockers": []}
	}

static func controls(stage_id: String) -> Array:
	var stage := definition(stage_id)
	if stage_id == "borrowed-light":
		return [{"id": stage.mirror_control.id, "kind": "mirror", "position_cm": stage.mirror_control.position_cm, "radius_cm": stage.mirror_control.radius_cm, "owner_slot": stage.mirror_control.owner_slot, "optical_id": stage.mirror_control.id}]
	return stage.get("controls", []).duplicate(true)
