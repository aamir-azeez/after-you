class_name AfterYouStageCatalog
extends RefCounted

const Canonical = preload("res://core/v2/canonical.gd")

static func relay_isles() -> Dictionary:
	return {
		"schema_version": 2, "simulation_version": 2, "version": 2,
		"id": "relay-isles", "title": "The Relay Isles", "premium": false,
		"islands": [
			{"id": "west", "rect_cm": [-720, -220, -260, 220], "height_cm": 0},
			{"id": "relay", "rect_cm": [-140, -180, 220, 180], "height_cm": 0},
			{"id": "east", "rect_cm": [340, -220, 780, 220], "height_cm": 0}],
		"bridges": [
			{"id": "west-relay", "rect_cm": [-260, -65, -140, 65], "from_surface": "west", "to_surface": "relay", "plate_id": "west-control"},
			{"id": "relay-east", "rect_cm": [220, -65, 340, 65], "from_surface": "relay", "to_surface": "east", "plate_id": "relay-control"}],
		"plates": [
			{"id": "west-control", "position_cm": [-400, 0], "radius_cm": 40},
			{"id": "relay-control", "position_cm": [100, 0], "radius_cm": 40}],
		"sockets": [
			{"id": "relay-socket", "kind": "relay", "position_cm": [40, 0], "radius_cm": 30, "surface_id": "relay"},
			{"id": "garden", "kind": "garden", "position_cm": [620, 120], "radius_cm": 55, "surface_id": "east"}],
		"starts": {"p0": [-480, 100], "p1": [-320, -120]},
		"stages": [
			{"id": "relay", "version": 2, "first_player_slot": "p0", "plate_id": "west-control", "bridge_id": "west-relay", "landing_cm": [-10, 0], "landing_surface": "relay", "flight_ticks": 90, "destination": "relay-socket", "goal_action": "place_relay", "hint_a": "Hold the west plate and throw to the middle island.", "hint_b": "Catch the seed, then place it in the relay socket."},
			{"id": "garden", "version": 2, "first_player_slot": "p1", "plate_id": "relay-control", "bridge_id": "relay-east", "landing_cm": [420, 0], "landing_surface": "east", "flight_ticks": 120, "destination": "garden", "goal_action": "plant", "hint_a": "Take the seed from the relay. Hold the next plate and throw.", "hint_b": "Follow both bridges, catch the seed and plant it."}],
		"catch_radius": 100, "seed_wait_ticks": 180
	}

static func initial_checkpoint(definition: Dictionary = {}) -> Dictionary:
	var level: Dictionary = relay_isles() if definition.is_empty() else definition
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x": int(level.starts[slot][0]), "z": int(level.starts[slot][1]), "surface_id": "west"}
	var result := {
		"schema_version": 2, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "stage_index": 0,
		"completed_stage_id": "", "next_stage_id": str(level.stages[0].id),
		"players": players, "latched_bridges": [],
		"seed": {"status": "held", "owner": "p0", "socket_id": ""},
		"previous_checkpoint_hash": "", "a_recording_hash": "", "b_recording_hash": "",
		"proof": {}
	}
	result["checkpoint_hash"] = checkpoint_hash(result)
	return result

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	var state := checkpoint.duplicate(true)
	state.erase("checkpoint_hash")
	state.erase("proof")
	return Canonical.digest(state)
