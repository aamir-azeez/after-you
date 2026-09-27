extends SceneTree
const Simulation=preload("res://core/journey/simulation.gd")
const Six=preload("res://core/cooperative/simulation.gd")
const Catalog=preload("res://core/journey/stage_catalog.gd")
const Witness=preload("res://tests/journey_witness.gd")
const Walk=preload("res://tests/cooperative_witness.gd")
const Canonical=preload("res://core/v2/canonical.gd")
var checks:=0
var failures:=0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var accepted: Array=[]
	for key: String in ["long-way-home","conservatory"]:
		var evidence:=Witness.chapter(key)
		_check(evidence.error.is_empty(),key+" real input route: "+evidence.error)
		if not evidence.error.is_empty(): continue
		_pairs(evidence)
		_maximum_envelope(evidence)
		_latest_sources(evidence)
		_tamper(evidence)
		accepted.append(evidence)
		if key=="long-way-home": _home(evidence)
		else: _light(evidence)
	if accepted.size()==2: _workers(accepted)
	if failures==0 and accepted.size()==2 and "--write-fixtures" in OS.get_cmdline_user_args():
		for evidence: Dictionary in accepted: _write(evidence)
	print("JOURNEY7: %d checks, %d failures" %[checks,failures])
	quit(1 if failures else 0)

func _pairs(evidence: Dictionary) -> void:
	var definition: Dictionary=evidence.definition
	for index in range(2):
		var previous: Dictionary=evidence.checkpoints[index]
		var pair: Dictionary=evidence.pairs[index]
		var checkpoint: Dictionary=evidence.checkpoints[index+1]
		_check(pair.a.schema_version==7 and pair.a.simulation_version==7 and pair.a.player_slot==("p0" if index==0 else "p1"),"Explicit simulation7 and reversed physical source role")
		_check(pair.a.duration_ticks<650 and pair.b.duration_ticks<650,"Normal witness leaves practical margin")
		for role: String in ["a","b"]:
			var record: Dictionary=pair[role]
			var prior: Dictionary=pair.a if role=="b" else {}
			var verified:=Simulation.verify_recording(definition,_json(record),_json(previous),_json(prior))
			_check(verified.valid,"Independent native replay "+record.stage_id+"/"+role)
			var replay:=Simulation.new()
			replay.reset(definition,record.stage_id,previous,prior,role)
			var frames:=Simulation.expand_recording_inputs(record)
			for frame: Dictionary in frames.slice(0,frames.size()/2): replay.step(frame)
			var draft:=replay.export_recording()
			var resumed:=Simulation.new()
			resumed.reset(definition,record.stage_id,previous,prior,role)
			for frame: Dictionary in Simulation.expand_recording_inputs(draft): resumed.step(frame)
			_check(replay.state_hash()==resumed.state_hash(),"Mid-turn reconstruction includes local control ownership")
			for frame: Dictionary in frames.slice(frames.size()/2): resumed.step(frame)
			_check(Canonical.same(resumed.export_recording(),record),"Exact recording after resume")
			_bound(record,49152,"record")
		var derived:=Simulation.derive_checkpoint(definition,_json(previous),_json(pair.a),_json(pair.b))
		_check(derived.valid and Canonical.same(derived.checkpoint,checkpoint),"Full native proof derives exactly")
		_check(Simulation.verify_checkpoint(definition,_json(checkpoint)).valid,"Recursive two-pair proof verifies")
		_check(not Six.verify_checkpoint(definition,checkpoint).valid,"Simulation6 cannot admit7 catalog/proof")
		_bound(checkpoint,229376,"checkpoint")
		_bound({"schema_version":2,"recording":pair.b,"checkpoint":checkpoint},327680,"turn packet")
		print("Journey stage %s A=%d B=%d ticks" %[definition.stages[index].id,pair.a.duration_ticks,pair.b.duration_ticks])

func _home(evidence: Dictionary) -> void:
	var level: Dictionary=evidence.definition
	var initial: Dictionary=evidence.checkpoints[0]
	var source:=Witness.source(level,"the-path-you-leave",initial,"near",true,32)
	_check(source.can_commit(),"Wrong HOME trip recovers through actual owned stair and FRIEND escape")
	Walk.wait_ticks(source,80)
	var first: Dictionary=source.export_recording()
	var b:=Witness.receiver(level,"the-path-you-leave",initial,first,"near",0,16)
	_check(b.complete and b.snapshot().players.p0.surface_id=="garden" and b.snapshot().players.p1.surface_id=="garden","Fast receiver drains longer independent source to two real G endpoints")
	_check(b.tick==first.duration_ticks,"Fast B freezes its pose but drains every remaining independent source tick")
	_check(b.snapshot().mechanisms.controls["return-selector"]=="garden","Receiver selector survives every source tick")
	print("Home corrected route plus80 idle ticks A=%d B=%d" %[first.duration_ticks,b.tick])
	var derived:=Simulation.derive_checkpoint(level,initial,first,b.export_recording())
	_check(derived.valid,"Off-centre corrected source and receiver form accepted prefix")
	if derived.valid:
		for branch: String in ["near","garden"]:
			var second_source:=Witness.source(level,"a-place-beside-you",derived.checkpoint,branch)
			_check(second_source.can_commit() and second_source.snapshot().players.p1.surface_id=="home-room","Source walks G-to-H service route and holds "+branch+" pad")
			var second_b:=Witness.receiver(level,"a-place-beside-you",derived.checkpoint,second_source.export_recording(),branch)
			_check(second_b.complete and second_b.snapshot().players.p0.surface_id=="home-room" and second_b.snapshot().players.p1.surface_id=="home-room","Both final approaches meet inside actual H: "+branch)
			print("Home branch %s from off-centre prefix A=%d B=%d" %[branch,second_source.tick,second_b.tick])
	# The slower receiver operates its own selector after A's final frame.
	var late:=Witness.receiver(level,"the-path-you-leave",initial,evidence.pairs[0].a,"near",int(evidence.pairs[0].a.duration_ticks)+30)
	_check(late.complete and late.snapshot().mechanisms.controls["return-selector"]=="garden","Late receiver control survives frozen source tail")
	# HOME can transiently let B enter the garden, but cannot replace B's own choice.
	var changing:=Simulation.new()
	changing.reset(level,"the-path-you-leave",initial)
	for point: Array in [[-320,0],[64,0],[64,64]]: Walk.walk(changing,point)
	Walk.tap(changing); Walk.wait_ticks(changing,120)
	Walk.tap(changing); Walk.wait_ticks(changing,160)
	Walk.tap(changing)
	for point: Array in [[64,0],[-320,0],[-320,-240],[480,-240],[560,-240],[560,32],[640,32]]: Walk.walk(changing,point)
	_check(changing.can_commit(),"Accepted source can correct a transient HOME detour without hidden timing charge")
	var probe:=Simulation.new()
	probe.reset(level,"the-path-you-leave",initial,changing.export_recording(),"b")
	for point: Array in [[-416,272],[-16,272],[128,80],[512,80],[640,80],[640,224]]: Walk.walk(probe,point)
	_check(probe.context_action().id=="ring" and not probe.context_action().enabled,"Transient HOME never bypasses receiver garden-selector contribution")

func _light(evidence: Dictionary) -> void:
	var level: Dictionary=evidence.definition
	var initial: Dictionary=evidence.checkpoints[0]
	var a:=Simulation.new()
	a.reset(level,"a-light-above",initial)
	_check(a.snapshot().optics.signals["low-warm"] and not a.can_commit(),"Wrong lower destination is visibly lit and not ready")
	Walk.walk(a,[-416,128]); Walk.tap(a)
	_check(not a.snapshot().optics.signals["high-light"],"One corrected bend alone does not complete the network")
	Walk.walk(a,[-416,-352]); Walk.tap(a)
	_check(a.can_commit() and a.snapshot().optics.signals["high-light"],"Two corrections preserve third bend and light high receiver")
	Walk.walk(a,[-224,-352]); Walk.tap(a)
	_check(not a.can_commit() and not a.snapshot().optics.signals["high-light"],"Blindly toggling preserved third bend breaks readiness")
	Walk.tap(a)
	_check(a.can_commit(),"Wrong source alignment is locally recoverable")
	Walk.walk(a,[-192,-256])
	_check(a.can_commit(),"Legitimate source endpoint beside the stair preserves readiness")
	# Extend a valid source after setup to exercise B-owned optics during A.
	Walk.wait_ticks(a,240)
	var first:=a.export_recording()
	var b:=Witness.receiver(level,"a-light-above",initial,first)
	_check(b.complete and b.snapshot().mechanisms.controls["garden-return"]=="slash" and b.snapshot().optics.signals["high-light"],"Receiver optics survive live independent source and preserve its signal")
	var late:=Witness.receiver(level,"a-light-above",initial,evidence.pairs[0].a,"near",int(evidence.pairs[0].a.duration_ticks)+30)
	_check(late.complete and late.snapshot().optics.signals["garden-light"],"Receiver optics after final source tick remain authoritative")
	var recovery:=Simulation.new()
	recovery.reset(level,"a-light-above",initial,evidence.pairs[0].a,"b")
	for point: Array in [[-208,-256],[384,-256],[384,-192],[416,-192],[416,-240]]: Walk.walk(recovery,point)
	_check(recovery.snapshot().players.p1.surface_id=="lower-room" and not recovery.snapshot().bridges["garden-door"],"Premature hatch descent is safe but cannot skip the garden light")
	for point: Array in [[352,-240],[352,-48],[80,-48],[80,-352],[384,-352]]: Walk.walk(recovery,point)
	_check(recovery.snapshot().players.p1.surface_id=="gallery" and recovery.snapshot().players.p1.height==160,"Recovery stair returns to gallery through actual navigation")
	Walk.tap(recovery)
	_check(not recovery.snapshot().optics.signals["east-warm"] and recovery.snapshot().optics.signals["high-light"],"Wrong local mirror changes only its circuit")
	Walk.tap(recovery)
	Walk.walk(recovery,[384,-192]); Walk.tap(recovery)
	for point: Array in [[416,-192],[416,-240],[416,16],[752,16],[752,160]]: Walk.walk(recovery,point)
	Walk.tap(recovery)
	_check(recovery.complete,"Premature descent and wrong local alignment recover in the same real turn")
	print("Conservatory premature-drop recovery B=%d" %recovery.tick)
	var second:=Witness.source(level,"the-way-light-returns",evidence.checkpoints[1])
	_check(second.can_commit(),"Reversed source prepares crossing while in marked garden")
	Walk.wait_ticks(second,500)
	var final_b:=Witness.receiver(level,"the-way-light-returns",evidence.checkpoints[1],second.export_recording())
	_check(final_b.complete and final_b.snapshot().mechanisms.controls["final-mirror"]=="slash","Reversed physical ownership preserves B mirror during extended A replay")
	var edge:=Witness.source(level,"the-way-light-returns",evidence.checkpoints[1])
	Walk.walk(edge,[560,64])
	_check(edge.can_commit(),"Off-centre source at garden doorway boundary is admissible")
	var edge_b:=Witness.receiver(level,"the-way-light-returns",evidence.checkpoints[1],edge.export_recording())
	_check(edge_b.complete,"Receiver crosses from actual carried pose beside off-centre garden source")
	Walk.walk(second,[800,240])
	_check(not second.can_commit() and second.snapshot().optics.signals["crossing-light"],"Light alone cannot accept source outside final garden waiting region")
	# Before the far-side shutter, the final mirror is separated by real gaps.
	var room:=Simulation.new()
	room.reset(level,"the-way-light-returns",evidence.checkpoints[1],evidence.pairs[1].a,"b")
	_check(not room.snapshot().optics.signals["second-light"] and not room.snapshot().optics.signals["crossing-light"] and room.snapshot().optics.signals["room-warm"],"Wrong source ray cannot accidentally light complementary receiver")
	_check(not room.walkable_at(-128,64) and not room.snapshot().bridges["court-return"] and not room.snapshot().bridges["room-return"],"Real gap separates final mirror room from spawn-side court")
	Walk.walk(room,[-208,64])
	for _tick in range(40): room.step({"move_x":1.0})
	_check(room.snapshot().players.p0.x<=-172 and room.context_action().id!="selector","Native body cannot reach the final mirror before far shutter")
	_check(evidence.checkpoints[2].mechanisms.controls["final-mirror"]=="slash" and evidence.checkpoints[2].mechanisms.levers["return-shutter"],"Final accepted pair retains distinct shutter and mirror contributions")

func _maximum_envelope(evidence: Dictionary) -> void:
	# Conservative structural upper bound, not a native acceptance fixture:
	# every record has900 distinct full actions and31 full replay checks.
	var checkpoint: Dictionary=evidence.checkpoints[0].duplicate(true)
	var final_b: Dictionary={}
	for index in range(2):
		var first:=_max_record(evidence.pairs[index].a,checkpoint,{})
		var second:=_max_record(evidence.pairs[index].b,checkpoint,first)
		var next: Dictionary=evidence.checkpoints[index+1].duplicate(true)
		next.previous_checkpoint_hash=checkpoint.checkpoint_hash
		next.a_recording_hash=first.recording_hash
		next.b_recording_hash=second.recording_hash
		next.proof={"checkpoint":checkpoint,"a":first,"b":second}
		next.checkpoint_hash=Catalog.checkpoint_hash(next)
		_bound(first,49152,"max source record")
		_bound(second,49152,"max receiver record")
		_bound(next,229376,"max recursive checkpoint")
		checkpoint=next
		final_b=second
	var packet: Dictionary={"schema_version":2,"recording":final_b,"checkpoint":checkpoint}
	_bound(packet,327680,"max four-record request")
	print("Journey max envelope "+evidence.definition.id+": record="+str(_metrics(final_b))+" checkpoint="+str(_metrics(checkpoint))+" request="+str(_metrics(packet)))

func _latest_sources(evidence: Dictionary) -> void:
	for index in range(2):
		var stage_id: String=evidence.definition.stages[index].id
		var branches: Array=["near","garden"] if stage_id=="a-place-beside-you" else ["near"]
		for branch: String in branches:
			var previous: Dictionary=evidence.checkpoints[index]
			var base:=Witness.source(evidence.definition,stage_id,previous,branch)
			var delay:=899-int(base.source_budget_ticks())-int(base._hold_start)
			_check(base.can_commit() and delay>=0,"Base source has usable admission budget: "+stage_id+"/"+branch)
			if delay<0: continue
			var frames:=Simulation.expand_recording_inputs(base.export_recording())
			var delayed:=Simulation.new()
			delayed.reset(evidence.definition,stage_id,previous)
			Walk.wait_ticks(delayed,delay)
			for frame: Dictionary in frames: delayed.step(frame)
			_check(delayed.can_commit() and delayed._hold_start+delayed.source_budget_ticks()==899,"Latest admitted stable opening is proven by real inputs")
			if not delayed.can_commit(): continue
			var b:=Witness.receiver(evidence.definition,stage_id,previous,delayed.export_recording(),branch)
			_check(b.complete and b.tick<=900,"Receiver can finish from carried pose at latest admitted opening: "+stage_id+"/"+branch)
			var too_late:=Simulation.new()
			too_late.reset(evidence.definition,stage_id,previous)
			Walk.wait_ticks(too_late,delay+1)
			for frame: Dictionary in frames: too_late.step(frame)
			_check(not too_late.can_commit(),"One-tick-later stable opening is rejected instead of promising an unsupported budget")
			print("Journey latest %s/%s A=%d ready=%d budget=%d B=%d" %[stage_id,branch,delayed.tick,delayed._hold_start,delayed.source_budget_ticks(),b.tick])

func _tamper(evidence: Dictionary) -> void:
	var altered: Dictionary=evidence.checkpoints[2].duplicate(true)
	var key: String=altered.mechanisms.controls.keys()[0]
	altered.mechanisms.controls[key]="invented"
	altered.checkpoint_hash=Catalog.checkpoint_hash(altered)
	_check(not Simulation.verify_checkpoint(evidence.definition,altered).valid,"Rehashed checkpoint cannot invent a selector/mirror result")
	altered=evidence.checkpoints[2].duplicate(true)
	altered.mechanisms.latched_bridges.append("never-entered")
	altered.checkpoint_hash=Catalog.checkpoint_hash(altered)
	_check(not Simulation.verify_checkpoint(evidence.definition,altered).valid,"Rehashed checkpoint cannot invent an entry-latched route")
	var foreign: Dictionary=evidence.definition.duplicate(true)
	foreign.simulation_version=6
	_check(not Simulation.verify_checkpoint(foreign,evidence.checkpoints[2]).valid,"New facade rejects unknown catalog/version before selecting a runtime")

func _workers(evidence: Array) -> void:
	var threads: Array=[]
	for item: Dictionary in evidence:
		var worker:=Thread.new()
		var result:=worker.start(_worker_proof.bind(item.definition.duplicate(true),item.checkpoints[2].duplicate(true)))
		_check(result==OK,"Immutable native proof worker starts")
		if result==OK: threads.append(worker)
	var level:=Catalog.definition("long-way-home")
	var initial:=Catalog.initial_checkpoint(level)
	var live:=Simulation.new()
	live.reset(level,level.stages[0].id,initial)
	for _tick in range(120): live.step({})
	_check(Canonical.same(live.snapshot().mechanisms,initial.mechanisms),"Live mutable controls remain separate from concurrent proof engines")
	for worker: Thread in threads:
		var result: Variant=worker.wait_to_finish()
		_check(result is Dictionary and bool(result.get("valid",false)),"Different chapter profiles verify concurrently without shared mutable optics or selectors")

static func _worker_proof(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return Simulation.verify_checkpoint(definition,checkpoint)

func _max_record(original: Dictionary, checkpoint: Dictionary, source: Dictionary) -> Dictionary:
	var value:=original.duplicate(true)
	value.checkpoint_hash=checkpoint.checkpoint_hash
	value.duration_ticks=900
	value.actions=[]
	for index in range(900): value.actions.append({"ticks":1,"x":-100,"z":-100,"action":index%2==0})
	value.replay_checks=[]
	for index in range(1,32): value.replay_checks.append({"tick":index*29 if index<31 else 900,"state_hash":"a".repeat(64)})
	if not source.is_empty(): value.source_recording_hash=source.recording_hash
	value.recording_hash=Simulation.recording_hash(value)
	return value

func _write(evidence: Dictionary) -> void:
	var directory:="res://tests/fixtures/journey"
	DirAccess.make_dir_recursive_absolute(directory)
	_save(directory+"/"+evidence.definition.id+"-definition.json",evidence.definition)
	_save(directory+"/"+evidence.definition.id+"-initial-checkpoint.json",evidence.checkpoints[0])
	for index in range(2):
		var id: String=evidence.definition.stages[index].id
		_save(directory+"/"+id+"-a.json",evidence.pairs[index].a)
		_save(directory+"/"+id+"-b.json",evidence.pairs[index].b)
		_save(directory+"/"+id+"-checkpoint.json",evidence.checkpoints[index+1])
	_save(directory+"/"+evidence.definition.id+"-final-checkpoint.json",evidence.checkpoints[2])

func _save(path: String, value: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true)+"\n")

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _bound(value: Dictionary, limit: int, label: String) -> void:
	var measured:=_metrics(value)
	_check(measured.bytes<=limit and measured.nodes<=24000 and measured.depth<=16,label+" within retained byte/node/depth limits")

func _metrics(value: Dictionary) -> Dictionary:
	var stack: Array=[{"value":value,"depth":0}]
	var nodes:=0
	var depth:=0
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		nodes+=1
		depth=maxi(depth,int(entry.depth))
		if entry.value is Dictionary:
			for child: Variant in entry.value.values(): stack.append({"value":child,"depth":entry.depth+1})
		elif entry.value is Array:
			for child: Variant in entry.value: stack.append({"value":child,"depth":entry.depth+1})
	return {"bytes":JSON.stringify(value).to_utf8_buffer().size(),"nodes":nodes,"depth":depth}

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
