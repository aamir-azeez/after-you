extends RefCounted
## sleeping-lighthouse@2: the six authored Lighthouse stages as one chapter on
## the shared record and checkpoint format. Each stage embeds its native
## definition, so the chapter hash covers the content directly and the backend
## can read the structure it checks. The native catalog stays the source the
## engine plays; a test pins every embedded copy to it.
const Canonical = preload("res://core/v2/canonical.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const ID := "sleeping-lighthouse"
const VERSION := 2
const RULES := 11
const SCHEMA := 8

static func definition(_key: String = "") -> Dictionary:
	var stages: Array = []
	for stage_id: String in LightCatalog.STAGE_IDS:
		var native := LightCatalog.definition(stage_id)
		stages.append({"id": stage_id, "version": 1, "first_player_slot": native.first_player_slot, "native": native})
	var start := Native.initial_checkpoint()
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		var p: Dictionary = start.players[slot]
		players[slot] = {"x": int(p.x), "z": int(p.z), "height": 0, "surface_id": str(p.surface_id)}
	return {"schema_version": SCHEMA, "simulation_version": RULES, "id": ID, "version": VERSION, "title": "Sleeping Lighthouse",
		"premium": true, "start": {"players": players, "mechanisms": {"latched_bridges": [], "mirrors": {}, "props": {}, "flags": {}}},
		"stages": stages}

static func known(value: Dictionary) -> bool:
	return value.get("id") == ID and value.get("version") == VERSION and Canonical.same(value, definition())

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	var checkpoint := {"schema_version": SCHEMA, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level),
		"stage_index": 0, "completed_stage_id": "", "next_stage_id": level.stages[0].id, "players": level.start.players.duplicate(true),
		"mechanisms": level.start.mechanisms.duplicate(true), "previous_checkpoint_hash": "", "a_recording_hash": "", "b_recording_hash": "", "proof": {}}
	checkpoint["checkpoint_hash"] = checkpoint_hash(checkpoint)
	return checkpoint

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	var body := checkpoint.duplicate(true)
	body.erase("proof")
	body.erase("checkpoint_hash")
	return Canonical.digest(body)
