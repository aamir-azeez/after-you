extends SceneTree
## Real inputs cover versioned comfort rules; published fixtures remain immutable.
const Relay = preload("res://core/v2/simulation_v2.gd")
const RelayCatalog = preload("res://core/v2/stage_catalog.gd")
const Physical = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Storage = preload("res://services/local_save.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []
var exported: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_relay_recovery()
	var rolling := _physical_chapter("rolling-home")
	_physical_chapter("high-and-low")
	_physical_chapter("a-house-for-two")
	_physical_chapter("conservatory")
	_physical_chapter("long-way-home")
	_physical_hold_recovery()
	if not rolling.is_empty(): _offer_and_overlap(rolling)
	_retained_journal()
	_retained_contact()
	_caps()
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://tests/fixtures/comfort8")
		var destination := "res://tests/fixtures/comfort8/recordings.json"
		_check(not FileAccess.file_exists(destination),"New version8 fixture never overwrites existing evidence")
		if failures == 0:
			var out := FileAccess.open(destination, FileAccess.WRITE)
			out.store_string(JSON.stringify(exported,"\t")+"\n")
			out.close()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU COMFORT RULES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _relay_recovery() -> void:
	var level := RelayCatalog.relay_isles()
	var start := RelayCatalog.initial_checkpoint(level)
	var old := Relay.new()
	_check(old.reset(level,"relay",start),"Unspecified direct Relay reset still chooses published2")
	_move(old,[-400,0]); _tap(old); _move(old,[-400,80]); _move(old,[-400,0])
	_check(not old.can_commit(),"Published2 retains its exact irreversible off-plate rule")
	var a := Relay.new()
	_check(a.reset(level,"relay",start,{},"a",8),"Fresh Relay8 uses unchanged authored definition and checkpoint")
	_move(a,[-400,0]); _wait(a,10)
	var earned: int = a._capacity_ticks
	_move(a,[-400,80]); _wait(a,25)
	_check(a._capacity_ticks >= earned and a._capacity_ticks < earned+15,"Leaving the plate pauses earned hold instead of resetting or charging off-pad")
	_move(a,[-400,0]); _tap(a); _wait(a,55)
	_move(a,[-400,80]); _wait(a,30); _move(a,[-400,0])
	_check(a.can_commit(),"Off/on remains recoverable both before and after the throw")
	var first: Dictionary = a.export_recording()
	_check(Relay.verify_recording(level,first,start).valid,"Recovered source independently replays as8")
	var crossing := Relay.new()
	_check(crossing.reset(level,"relay",start,first,"b",8),"Receiver gets exact independent source")
	_move(crossing,[-320,0]); _move(crossing,[-200,0])
	var opened := false
	for _tick in range(250):
		crossing.step({})
		if crossing._source != null and not crossing._source._on_plate("p0","west-control") and crossing.tick > 60:
			opened = bool(crossing.snapshot().bridges["west-relay"])
			break
	_check(opened,"An actually entered bridge stays open through A's off-plate interval")
	_move(crossing,[-10,0])
	_check(crossing.snapshot().players.p1.x >= -10,"Receiver escapes an entered crossing without changing source input")
	var b := Relay.new()
	b.reset(level,"relay",start,first,"b",8)
	_wait(b,660); _move(b,[-320,0]); _move(b,[-10,0]); _move(b,[40,0]); _tap(b)
	_check(b.complete and b.tick > 600 and b.tick < 900,"Late receiver catches the waiting seed and finishes during the extra10 seconds")
	_check(b.snapshot().players.p0.x == a.snapshot().players.p0.x and b.snapshot().players.p0.z == a.snapshot().players.p0.z,"B's extra time never moves A's accepted final pose")
	var second: Dictionary = b.export_recording()
	var pair := Relay.derive_checkpoint(level,start,first,second)
	_check(pair.valid,"Long B recording and recovered source produce a native checkpoint")
	if pair.valid:
		exported["relay"] = {"a":first,"b":second,"checkpoint":pair.checkpoint,"pairs":[{"a":first,"b":second}],"checkpoints":[start,pair.checkpoint]}
		var garden_a := Relay.new()
		garden_a.reset(level,"garden",pair.checkpoint,{},"a",8)
		_play(garden_a,Relay.expand_recording_inputs(_fixture("v2/garden-a")))
		_wait(garden_a,15)
		_check(garden_a.can_commit(),"Relay8 reversed source completes its real second-stage seed route")
		var garden_b := Relay.new()
		garden_b.reset(level,"garden",pair.checkpoint,garden_a.export_recording(),"b",8)
		_play(garden_b,Relay.expand_recording_inputs(_fixture("v2/garden-b")))
		_check(garden_b._objective_done,"Relay8 second receiver performs the actual garden action")
		# The added source hold outlasts this unchanged receiver route; drain only that accepted tail.
		while not garden_b.finished and garden_b.tick < garden_a.tick: garden_b.step({})
		_check(garden_b.complete,"Relay8 second receiver reaches its actual garden")
		var final := Relay.derive_checkpoint(level,pair.checkpoint,garden_a.export_recording(),garden_b.export_recording())
		_check(final.valid,"Both Relay8 pairs verify as an exact native proof")
		if final.valid:
			exported.relay.pairs.append({"a":garden_a.export_recording(),"b":garden_b.export_recording()})
			exported.relay.checkpoints.append(final.checkpoint)
	var deadline := Relay.new()
	deadline.reset(level,"relay",start,first,"b",8)
	_wait(deadline,900)
	_check(deadline.finished and deadline.tick == 900 and deadline.export_recording().replay_checks.size() == 30,"B deadline and replay-check bounds cover the entire grace window")
	_check(Relay.verify_recording(level,deadline.export_recording(),start,first).valid,"A full-length incomplete B draft is replayable without truncation")
	var old_first := _fixture("v2/relay-a")
	_check(Relay.verify_recording(level,old_first,start).valid,"Released Relay2 source recording remains exact")
	_check(not Relay.new().reset(level,"relay",start,old_first,"b",8),"Version8 cannot reinterpret a retained2 source")

func _physical_chapter(key: String) -> Dictionary:
	var chapter_key := key+"@1"
	var engine: Script = Registry.simulation_script(chapter_key)
	var level := Registry.definition(chapter_key)
	var checkpoint := Registry.initial_checkpoint(chapter_key)
	var directory := "journey/" if Registry.is_journey(chapter_key) else "cooperative/"
	var result := {"checkpoints":[checkpoint],"pairs":[]}
	for stage: Dictionary in level.stages:
		var a: RefCounted = engine.new()
		_check(a.reset(level,stage.id,checkpoint,{},"a",8),"Physical8 source starts: "+stage.id)
		_play(a,Physical.expand_recording_inputs(_fixture(directory+stage.id+"-a")))
		_check(a.can_commit(),"Actual source route remains viable under8: "+stage.id)
		if not a.can_commit(): return {}
		var first: Dictionary = a.export_recording()
		var b: RefCounted = engine.new()
		_check(b.reset(level,stage.id,checkpoint,first,"b",8),"Physical8 receiver starts: "+stage.id)
		_play(b,Physical.expand_recording_inputs(_fixture(directory+stage.id+"-b")))
		_check(b.complete,"Actual receiver route completes under8: "+stage.id)
		if not b.complete: return {}
		var second: Dictionary = b.export_recording()
		var derived: Dictionary = engine.derive_checkpoint(level,checkpoint,first,second)
		_check(derived.valid,"New physical pair independently verifies: "+stage.id)
		if not derived.valid: return {}
		result.pairs.append({"a":first,"b":second})
		checkpoint = derived.checkpoint
		result.checkpoints.append(checkpoint)
	_check(engine.verify_checkpoint(level,checkpoint).valid,"All8 recursive proof remains bounded and exact: "+key)
	exported[key] = result
	return result

func _physical_hold_recovery() -> void:
	var level := Catalog.definition("high-and-low")
	var initial := Catalog.initial_checkpoint(level)
	var a := Physical.new()
	a.reset(level,"upper-path",initial,{},"a",8)
	_play(a,Physical.expand_recording_inputs(_fixture("cooperative/upper-path-a")))
	_wait(a,55)
	var before: int = a.snapshot().source_hold_ticks
	_move(a,[-448,0]); _wait(a,30)
	_check(a.snapshot().source_hold_ticks >= before and not a.can_commit(),"Physical earned hold is preserved off-pad but cannot save while route is closed")
	_move(a,[-448,-128])
	_check(a.can_commit(),"Physical source can return and save cumulative contribution")
	var first: Dictionary = a.export_recording()
	var b := Physical.new()
	b.reset(level,"upper-path",initial,first,"b",8)
	_move(b,[-160,0])
	var retained := false
	for _tick in range(250):
		b.step({})
		if not bool(b._source.snapshot().hold_pads["lower-switch"]) and b.tick > 100:
			retained = bool(b.snapshot().bridges["blue-stair"])
			break
	_check(retained,"An entered stair remains supported through A's off-pad interval")
	_move(b,[160,0]); _move(b,[160,-128]); _tap(b)
	while not b.finished and b.tick < int(first.duration_ticks): b.step({})
	_check(b.complete,"Entered stair recovery still completes with independently replayed A")
	var late := Physical.new()
	late.reset(level,"upper-path",initial,first,"b",8)
	_wait(late,960); _move(late,[160,0]); _move(late,[160,-128]); _tap(late)
	_check(late.complete and late.tick > 900 and late.tick < 1200,"Physical receiver can finish beyond the former900-tick deadline")
	_check(Physical.verify_recording(level,late.export_recording(),initial,first).valid,"Extended physical recording verifies without clipping its inputs or checks")

func _offer_and_overlap(rolling: Dictionary) -> void:
	var level := Catalog.definition("rolling-home")
	var checkpoint: Dictionary = rolling.checkpoints[1]
	var source := Physical.new()
	source.reset(level,"bring-it-home",checkpoint,{},"a",8)
	# The released route's first tap pulls the home lever. Deliberately omit it.
	var frames := Physical.expand_recording_inputs(_fixture("cooperative/bring-it-home-a"))
	_play(source,frames.slice(2,frames.size()-2))
	_check(source.snapshot().props["round-ball"].controller_slot == "p1","Role-reversed A contact colors the actual p1 controller")
	exported["controller_states"] = {"p1_contact":source.snapshot()}
	_play(source,frames.slice(frames.size()-2))
	_check(source.snapshot().props["round-ball"].status == "offered","Leave ball works before pulling the home lever")
	_check(not source.can_commit(),"Offering alone cannot accept an impossible partner route")
	var offered: Dictionary = source.snapshot().props["round-ball"]
	_check(offered.x == 240 and offered.z == 0,"Explicit handoff legally snaps to its exact current marker")
	_move(source,[208,-80]); _move(source,[352,-80]); _move(source,[352,0]); _move(source,[608,0]); _move(source,[608,128]); _move(source,[896,128]); _move(source,[896,96]); _tap(source)
	_check(source.can_commit(),"Source can operate the route lever after offering and then save")
	if not source.can_commit(): return
	var first: Dictionary = source.export_recording()
	_check(Physical.verify_recording(level,first,checkpoint).valid,"Offer-before-lever is independently replayed")
	var b := Physical.new()
	b.reset(level,"bring-it-home",checkpoint,first,"b",8)
	# Cross the narrow shore bridge at z=0, then step aside on the wide middle
	# island before waiting exactly at the future offer marker.
	_move(b,[-352,64]); _move(b,[-352,0]); _move(b,[160,0]); _move(b,[160,-80]); _move(b,[240,-80]); _move(b,[240,0])
	print("COMFORT8 OVERLAP waiting: ", JSON.stringify({"tick":b.tick,"player":b.snapshot().players.p0,"ball":b.snapshot().props["round-ball"],"offer_tick":source.snapshot().offer_tick}))
	for _tick in range(900):
		if b.finished or b.snapshot().props["round-ball"].status == "offered": break
		b.step({})
	var player: Dictionary = b.snapshot().players.p0
	var ball: Dictionary = b.snapshot().props["round-ball"]
	print("COMFORT8 OVERLAP arrival: ", JSON.stringify({"tick":b.tick,"player":player,"ball":ball,"context":b.context_action()}))
	_check(player.x == ball.x and player.z == ball.z,"Real waiting B is overlapped by the independently arriving source ball")
	_tap(b)
	_check(b.snapshot().props["round-ball"].status == "claimed","Overlap still allows the explicit ownership handoff")
	var before := Canonical.digest(b._mechanisms.props["round-ball"])
	_move(b,[208,0])
	_check(b.snapshot().players.p0.x == 208 and Canonical.digest(b._mechanisms.props["round-ball"]) == before,"Live player escapes penetration while ball and A remain fixed")
	_check(b.snapshot().props["round-ball"].controller_slot == "p0","B contact identifies actual controller")
	exported.controller_states["b_contact"] = b.snapshot()
	_move(b,[208,-64])
	_check(b.snapshot().props["round-ball"].controller_slot == "","Walking away makes the ball visually available")
	exported.controller_states["b_away"] = b.snapshot()
	_move(b,[208,0]); b.step({"move_x":1.0})
	_check(b.snapshot().props["round-ball"].controller_slot == "p0" and b.snapshot().props["round-ball"].x > 240,"B re-engages and pushes after walking away")
	exported.controller_states["b_recontact"] = b.snapshot()
	var a := Physical.new()
	a.reset(level,"weight-of-a-friend",Catalog.initial_checkpoint(level),{},"a",8)
	_move(a,[-496,0]); a.step({"move_x":1.0})
	_check(a.snapshot().props["round-ball"].controller_slot == "p0","A's real push colors the free ball by controller rather than active viewer")
	exported.controller_states["a_contact"] = a.snapshot()
	_move(a,[-520,0]); _wait(a,2)
	_check(a.snapshot().props["round-ball"].controller_slot == "","A leaving contact releases only the visual control cue")
	exported.controller_states["a_away"] = a.snapshot()
	# Same-floor visible tolerance is center-within-ring; it cannot target a
	# different surface and snapping checks the entire footprint/path.
	_move(a,[-336,0]); _move(a,[-336,-48]); _move(a,[-304,-48]); _move(a,[-304,40])
	_check(a.snapshot().hold_pads["heavy-pad"],"Ball center inside visible ring activates the weight pad without pixel-perfect containment")
	var false_target: Dictionary = a.stage.ball_pads[0].duplicate(true)
	false_target.surface_id = "home"
	_check(not a._ball_at(false_target,"round-ball"),"Tolerance cannot claim a marker on another floor")

func _retained_journal() -> void:
	var path := "user://comfort-retained-"+str(Time.get_ticks_usec())+".json"
	paths.append(path)
	var level := Catalog.definition("rolling-home")
	var first := _fixture("cooperative/weight-of-a-friend-a")
	var second := _fixture("cooperative/weight-of-a-friend-b")
	var checkpoint := _fixture("cooperative/weight-of-a-friend-checkpoint")
	var old_source := Physical.new()
	_check(old_source.reset(level,"bring-it-home",checkpoint),"Old completed6 checkpoint selects6 for the next direct turn")
	var inputs := Physical.expand_recording_inputs(_fixture("cooperative/bring-it-home-a"))
	_play(old_source,inputs.slice(0,40))
	var draft: Dictionary = old_source.export_recording()
	var envelope := Storage.defaults()
	envelope["relay"] = {"schema_version":6,"simulation_version":6,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"pairs":[{"a":first,"b":second}],"a":{},"draft":draft}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope)); file.close()
	var bytes := FileAccess.get_sha256(path)
	var journal := Journey.new(path,null,Registry.ROLLING_HOME)
	journal.load_data()
	_check(not journal.read_only and FileAccess.get_sha256(path) == bytes,"Cold old6 journal and pending draft load without rewriting bytes")
	var live: RefCounted = journal.create_live_simulation(true)
	_check(live != null and live.simulation_version == 6,"Old stage1 checkpoint resumes stage2 under6, never8")
	if live != null:
		_play(live,Physical.expand_recording_inputs(journal.draft()))
		_check(live.state_hash() == old_source.state_hash(),"Old pending draft reconstructs every original state byte")
		_play(live,inputs.slice(40))
		_check(Canonical.same(live.export_recording(),_fixture("cooperative/bring-it-home-a")),"Old continuation produces the entire published source recording exactly")
	var fresh_path := "user://comfort-fresh-"+str(Time.get_ticks_usec())+".json"
	paths.append(fresh_path)
	var fresh := Journey.new(fresh_path,null,Registry.ROLLING_HOME)
	fresh.load_data()
	var new_live: RefCounted = fresh.create_live_simulation()
	_check(new_live != null and new_live.simulation_version == 8,"A genuinely fresh local chapter selects8")
	if new_live != null:
		new_live.step({})
		_check(fresh.save_live_draft(new_live),"Fresh8 draft saves through the real registered journal engine")
	_check(not Physical.new().reset(level,"bring-it-home",checkpoint,{},"a",8),"Mixed6→8 proof chains are rejected rather than migrated")

func _retained_contact() -> void:
	var level := Catalog.definition("rolling-home")
	var old := Physical.new()
	old.reset(level,"weight-of-a-friend",Catalog.initial_checkpoint(level))
	_move(old,[-496,0]); old.step({"move_x":1.0})
	var record: Dictionary = old.export_recording()
	var shown: Dictionary = old.snapshot()
	_check(shown.props["round-ball"].controller_slot == "p0","Old6 native contact receives the same display-only ownership cue")
	_check(not shown.mechanisms.props["round-ball"].has("controller_slot") and Canonical.same(record,old.export_recording()),"Old display cue never enters persistent mechanisms or recording hashes")
	exported["old6_contact"] = shown
	_check(Physical.verify_recording(level,record,Catalog.initial_checkpoint(level)).valid,"Old6 contact recording replays with identical hashes")

func _caps() -> void:
	var level := RelayCatalog.relay_isles()
	var base := {"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":2,"recording_version":2,"premium":false}]}
	_check(Registry.supported_capabilities(base).chapters[0].simulation_version == 2,"Old server advertises old2; fresh requests cannot silently choose8")
	base.chapters[0]["supported_simulation_versions"] = [2,8]
	_check(Registry.supported_capabilities(base).chapters[0].simulation_version == 8,"New server explicitly negotiates8 while retaining2")

func _play(sim: RefCounted, frames: Array) -> void:
	for frame: Dictionary in frames:
		if sim.finished or not sim.error.is_empty(): break
		sim.step(frame)

func _move(sim: RefCounted, target: Array) -> void:
	for axis: String in ["x","z"]:
		for _tick in range(1200):
			if sim.finished or not sim.error.is_empty(): return
			var player: Dictionary = sim.snapshot().players[sim.active_slot]
			var distance := int(target[0 if axis == "x" else 1])-int(player[axis])
			if absi(distance) <= 1: break
			sim.step({"move_"+axis:clampf(float(distance)/8.0,-1.0,1.0)})

func _wait(sim: RefCounted, count: int) -> void:
	for _tick in range(count):
		if sim.finished: return
		sim.step({})

func _tap(sim: RefCounted) -> void:
	sim.step({}); sim.step({"interact":true})

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+name+".json"))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
