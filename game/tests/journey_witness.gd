extends RefCounted
## Real input routes for private simulation7 feasibility. No state injection.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")

static func chapter(key: String, branch: String="near") -> Dictionary:
	var level:=Catalog.definition(key)
	var checkpoint:=Catalog.initial_checkpoint(level)
	var result: Dictionary={"definition":level,"checkpoints":[checkpoint],"pairs":[],"error":""}
	for stage: Dictionary in level.stages:
		var a:=source(level,stage.id,checkpoint,branch)
		if not a.error.is_empty() or not a.can_commit():
			result.error="Source failed "+stage.id+": "+a.error+" "+a.commit_reason()+" "+str(a.snapshot().get("players",{}))
			return result
		var first: Dictionary=a.export_recording()
		var b:=receiver(level,stage.id,checkpoint,first,branch)
		if not b.error.is_empty() or not b.complete:
			result.error="Receiver failed "+stage.id+": "+b.error+" "+b.commit_reason()+" "+str(b.snapshot().get("players",{}))
			return result
		var second: Dictionary=b.export_recording()
		var derived:=Simulation.derive_checkpoint(level,checkpoint,first,second)
		if not derived.valid:
			result.error="Proof failed "+stage.id+": "+str(derived.get("error",""))
			return result
		result.pairs.append({"a":first,"b":second})
		checkpoint=derived.checkpoint
		result.checkpoints.append(checkpoint)
	return result

static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary, branch: String="near", wrong_home: bool=false, endpoint_offset: int=0) -> RefCounted:
	var sim:=Simulation.new()
	if not sim.reset(level,stage_id,checkpoint): return sim
	match stage_id:
		"the-path-you-leave":
			_route(sim,[[-320,0],[64,0],[64,64]])
			if wrong_home:
				_route(sim,[[128,80],[640,80],[640,32],[352,80],[352,-240],[-320,-240],[-320,0],[64,0],[64,64]])
			Walk.tap(sim)
			_route(sim,[[64,0],[-320,0],[-320,-240],[480,-240],[560,-240],[560,32],[640+endpoint_offset,32]])
		"a-place-beside-you":
			# Starts at the actual accepted G pose, climbs the owned service route,
			# crosses its96cm-high landing, descends into H, then chooses a pad.
			_route(sim,[[704,224],[704,-16],[1168,-16],[1200,-16],[1200,32 if branch=="near" else 144]])
		"a-light-above":
			Walk.walk(sim,[-416,128]); Walk.tap(sim)
			Walk.walk(sim,[-416,-352]); Walk.tap(sim)
			if endpoint_offset!=0: Walk.walk(sim,[-416+endpoint_offset,-352])
		"the-way-light-returns":
			_route(sim,[[592,160],[592,-64]])
			Walk.tap(sim)
			Walk.walk(sim,[656+endpoint_offset,0])
	return sim

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, branch: String="near", delay: int=0, goal_offset: int=0) -> RefCounted:
	var sim:=Simulation.new()
	if not sim.reset(level,stage_id,checkpoint,first,"b"): return sim
	Walk.wait_ticks(sim,delay)
	match stage_id:
		"the-path-you-leave":
			_route(sim,[[-416,272],[-16,272],[128,224]])
			Walk.tap(sim)
			_route(sim,[[128,80],[512,80],[640,80],[640,224+goal_offset]])
			Walk.tap(sim)
		"a-place-beside-you":
			if branch=="near":
				_route(sim,[[704,224],[960,224]])
				Walk.tap(sim)
				_route(sim,[[1168,224],[1408,224],[1408,96]])
			else:
				_route(sim,[[736,288],[736,432],[1152,432],[1152,272],[1408,272],[1408,96]])
			Walk.tap(sim)
		"a-light-above":
			_route(sim,[[-208,-256],[384,-256],[384,-192]])
			Walk.tap(sim)
			_route(sim,[[416,-192],[416,-240],[416,16],[752,16],[752,160+goal_offset]])
			Walk.tap(sim)
		"the-way-light-returns":
			_route(sim,[[-304,208],[384,208],[352,64]])
			Walk.tap(sim)
			_route(sim,[[0,64],[0,0]])
			Walk.tap(sim)
			_route(sim,[[0,64],[384,64],[384,16],[752,16],[752,64]])
			Walk.tap(sim)
	# The receiver may reach its goal before the independently recorded source.
	# Drain real fixed ticks; don't accept a checkpoint from an unfinished ghost.
	for _tick in range(Simulation.MAX_TICKS):
		if sim.finished or not sim.snapshot().get("objective_done",false): break
		sim.step({})
	return sim

static func _route(sim: RefCounted, points: Array) -> void:
	for point: Array in points: Walk.walk(sim,point)
