class_name AfterYouFirstStepsCatalog
extends RefCounted
## Immutable chapter. All coordinates and walking heights are integer centimetres.

const Canonical = preload("res://core/v2/canonical.gd")
const DEFINITION = {
	"schema_version": 4,
	"simulation_version": 4,
	"id": "first-steps",
	"version": 1,
	"title": "First Steps",
	"premium": false,
	"handoff_grace_ticks": 60,
	"islands": [
		{
			"id": "shore",
			"rect_cm": [
				-600,
				-240,
				-120,
				240
			],
			"height_cm": 0
		},
		{
			"id": "loft",
			"rect_cm": [
				80,
				-240,
				500,
				240
			],
			"height_cm": 160
		}
	],
	"lift": {
		"id": "little-lift",
		"rect_cm": [
			-120,
			-90,
			80,
			90
		],
		"from_surface": "shore",
		"to_surface": "loft",
		"bottom_height_cm": 0,
		"top_height_cm": 160,
		"rise_ticks": 60,
		"boarding_cm": [
			-20,
			0
		]
	},
	"controls": [
		{
			"id": "lift-power",
			"position_cm": [
				-300,
				-130
			],
			"radius_cm": 36,
			"surface_id": "shore"
		},
		{
			"id": "throw-mark",
			"position_cm": [
				140,
				-90
			],
			"radius_cm": 30,
			"surface_id": "loft"
		},
		{
			"id": "garden-control",
			"position_cm": [
				360,
				110
			],
			"radius_cm": 36,
			"surface_id": "loft"
		}
	],
	"sockets": [
		{
			"id": "seed-pedestal",
			"kind": "pedestal",
			"position_cm": [
				230,
				-90
			],
			"surface_id": "loft",
			"radius_cm": 36,
			"seed_height_cm": 205
		},
		{
			"id": "garden",
			"kind": "garden",
			"position_cm": [
				-300,
				130
			],
			"surface_id": "shore",
			"radius_cm": 48,
			"seed_height_cm": 35
		}
	],
	"goals": [
		{
			"id": "loft-bell",
			"position_cm": [
				230,
				0
			],
			"radius_cm": 36,
			"surface_id": "loft"
		}
	],
	"starts": {
		"p0": [
			-420,
			-130
		],
		"p1": [
			-230,
			0
		]
	},
	"stages": [
		{
			"id": "a-little-lift",
			"version": 1,
			"first_player_slot": "p0",
			"goal_action": "open_loft",
			"power_control": "lift-power",
			"goal_id": "loft-bell",
			"minimum_power_ticks": 6,
			"receiver_route_cm": [
				[
					-230,
					0
				],
				[
					-20,
					0
				],
				[
					230,
					0
				]
			],
			"hint_a": "Stand on the power pad. Keep it glowing, then finish your recording.",
			"hint_b": "Step onto the low lift. Ride up, walk to the bell and ring it."
		},
		{
			"id": "a-place-to-grow",
			"version": 1,
			"first_player_slot": "p1",
			"goal_action": "plant",
			"pedestal_id": "seed-pedestal",
			"throw_control": "throw-mark",
			"garden_control": "garden-control",
			"destination": "garden",
			"landing_cm": [
				-340,
				0
			],
			"landing_surface": "shore",
			"flight_ticks": 90,
			"hint_a": "Take the seed upstairs. Throw from the marked edge, then open the garden with the other pad.",
			"hint_b": "Catch the seed at the lower ring. Bring it to the garden and plant when the leaves open."
		}
	],
	"catch_radius": 90,
	"seed_wait_ticks": 180
}
const INITIAL = {
	"schema_version": 4,
	"level_id": "first-steps",
	"level_version": 1,
	"definition_hash": "72ddc480e0f493c983fb012ce7bfa20a9cb1984ef7263d236c11509a527df85b",
	"stage_index": 0,
	"completed_stage_id": "",
	"next_stage_id": "a-little-lift",
	"players": {
		"p0": {
			"x": -420,
			"z": -130,
			"height": 0,
			"surface_id": "shore"
		},
		"p1": {
			"x": -230,
			"z": 0,
			"height": 0,
			"surface_id": "shore"
		}
	},
	"mechanisms": {
		"lift": {
			"height_cm": 0,
			"phase": "lower",
			"progress_ticks": 0,
			"boarded_slot": ""
		},
		"garden_open": false,
		"loft_open": false
	},
	"seed": {
		"status": "pedestal",
		"owner": "",
		"socket_id": "seed-pedestal",
		"x": 230,
		"z": -90,
		"height": 205
	},
	"previous_checkpoint_hash": "",
	"a_recording_hash": "",
	"b_recording_hash": "",
	"proof": {},
	"checkpoint_hash": "b12ac49480a223783c2d276f7b44e7dcfadcbc5deb86b1483a0e9df1e218fbbd"
}

static func definition() -> Dictionary:
	return DEFINITION.duplicate(true)

static func initial_checkpoint() -> Dictionary:
	return INITIAL.duplicate(true)

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	var body := checkpoint.duplicate(true)
	body.erase("checkpoint_hash")
	body.erase("proof")
	return Canonical.digest(body)
