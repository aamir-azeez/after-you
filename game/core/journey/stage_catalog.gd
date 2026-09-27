extends RefCounted
## Pinned authored chapters for the separate simulation7 ruleset.
const Canonical = preload("res://core/v2/canonical.gd")
const Home = preload("res://core/journey/long_way_home_catalog.gd")
const Conservatory = preload("res://core/journey/conservatory_catalog.gd")
const KEYS := ["conservatory@1","long-way-home@1"]

static func definition(key: String = "long-way-home") -> Dictionary:
	if key in ["long-way-home", "long-way-home@1"]: return Home.definition()
	if key in ["conservatory", "conservatory@1"]: return Conservatory.definition()
	return {}

static func known(value: Dictionary) -> bool:
	var expected:=definition(str(value.get("id","")))
	return not expected.is_empty() and Canonical.same(value,expected)

static func stage_definition(level: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in level.get("stages",[]):
		if stage.id!=stage_id: continue
		var result:=level.duplicate(true)
		result.erase("stages")
		result.merge(stage,true)
		result.id=level.id
		result["stage_id"]=stage.id
		result["stage_version"]=stage.version
		return result
	return {}

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	var players: Dictionary={}
	for slot: String in ["p0","p1"]:
		var start: Dictionary=level.starts[slot]
		players[slot]={"x":start.position_cm[0],"z":start.position_cm[1],"height":int(start.height_cm),"surface_id":str(start.surface_id)}
	var controls: Dictionary={}
	for stage: Dictionary in level.stages:
		for control: Dictionary in stage.get("controls",[]): controls[control.id]=str(control.initial)
	var checkpoint: Dictionary={"schema_version":7,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"stage_index":0,
		"completed_stage_id":"","next_stage_id":level.stages[0].id,"players":players,"mechanisms":{"latched_bridges":[],"props":{},"levers":{},"controls":controls},
		"previous_checkpoint_hash":"","a_recording_hash":"","b_recording_hash":"","proof":{}}
	checkpoint["checkpoint_hash"]=checkpoint_hash(checkpoint)
	return checkpoint

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	var body:=checkpoint.duplicate(true)
	body.erase("proof")
	body.erase("checkpoint_hash")
	return Canonical.digest(body)
