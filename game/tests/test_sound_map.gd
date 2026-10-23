extends SceneTree
## Event to sound: what each chapter's real controller passes to the soundscape
## for every simulation event, through the production advance_input path
## (relay_preview.gd for registry chapters, lighthouse_preview.gd for
## Lighthouse). The simulation, world, HUD and soundscape are stubs, so only
## the controller's mapping runs. "audible" says whether the soundscape has a
## clip for the cue; anything else is silent. Moving the mapping into data
## must leave tests/fixtures/golden/sound_map.json unchanged.
## See tests/golden_support.gd to regenerate after an intended change.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RelayPreview = preload("res://relay_preview.gd")
const LighthousePreview = preload("res://lighthouse_preview.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const Index = preload("res://content/chapters/index.gd")
const LeverLooks = preload("res://presentation/kit/lever_looks.gd")
const GOLDEN := "sound_map.json"
const LIGHTHOUSE := "sleeping-lighthouse@1"
## Every event name the engines under game/core append, with probes for the
## prefixed forms, plus an unknown name. Events seen in the replay golden are
## added at run time, so a real event can never be missing from the table.
const EVENTS := ["bell", "beacon_lit", "bridge_closed", "bridge_open", "bridge_opened", "bridge_opened:probe-route",
	"court_activated", "crossed_bridge", "drop", "emitter_off", "emitter_on", "garden_bloomed", "garden_opened",
	"handoff_claim", "handoff_offer", "island_bloomed", "lens_available", "lens_fitted", "lens_offered", "lens_taken",
	"lever", "lift_arrived", "lift_boarded", "lift_ready", "loft_opened", "mirror_rotated", "path_kept",
	"receivers_joined", "relay_filled", "rest_reached", "route_selected", "seed_caught", "seed_landed", "seed_missed",
	"seed_taken", "seed_thrown", "selector:probe-selector", "source_aligned", "stage_complete", "tower_anchored",
	"tower_reached", "turn_finished", "unknown-probe-event"]
var checks := 0
var failures := 0

class SoundRecorder extends Node:
	var calls: Array = []
	func consume_events(events: Array, live_play: bool) -> void:
		calls.append({"events": events.duplicate(), "live": live_play, "sources": []})
	## Controllers name who caused each cue so its pitch follows the event.
	func consume_turn_events(events: Array, sources: Array, live_play: bool) -> void:
		consume_events(events, live_play)
		calls[-1].sources = sources.duplicate()

class EventSim extends RefCounted:
	var events: Array = []
	var error := ""
	var tick := 1
	var finished := false
	func step(_input: Dictionary = {}) -> Dictionary:
		return snapshot()
	func snapshot() -> Dictionary:
		return {"tick": 1, "role": "a", "events": events.duplicate(), "finished": false, "complete": false, "can_commit": false,
			"duration_ticks": 900, "message": "", "context_action": {"id": "none", "label": "Action", "enabled": false, "target_id": ""}}
	func context_action() -> Dictionary:
		return {"id": "none", "label": "Action", "enabled": false, "target_id": ""}

class WorldStub extends Node3D:
	var presented := 0
	func present(_state: Dictionary, _immediate: bool = false) -> void:
		presented += 1

class ControlsStub extends CanvasLayer:
	var updates := 0
	func update_state(_title: String, _remaining: float, _state: Dictionary, _live: bool) -> void:
		updates += 1
	func show_tries(_tries: int) -> void: pass

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	var events := _events()
	var table: Dictionary = {}
	for key: String in Golden.GOLDEN_KEYS:
		table[key] = _chapter(key, events)
	table[LIGHTHOUSE] = _lighthouse(events)
	_check_known_fields()
	_check_look_cues()
	_check_look_identity()
	var result := Golden.check(GOLDEN, {"events": events, "chapters": table, "audible_cues": Soundscape.CLIPS.keys()})
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Event to sound mapping matches golden " + GOLDEN)
	print("SOUND MAP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## remember() tracks every field a snapshot has, but only some chapter
## families diff each one. A chapter that does not diff a field (here a
## physical chapter whose snapshot also carries controls) still plays the
## events for it, so a future snapshot field cannot silence its switches.
func _check_known_fields() -> void:
	var start := {"role": "a", "controls": {"probe": "up"}, "events": []}
	var seen := ChapterSoundMap.remember(start)
	var sounds := ChapterSoundMap.cues("high-and-low@1", {"role": "a", "controls": {"probe": "down"}, "events": ["selector:probe"]}, seen)
	_check(sounds.cues == ["switch_set"] and sounds.sources == ["selector:probe|selector:probe"], "A switch in a chapter that does not diff controls still sounds: " + str(sounds))

## A control drawn as a machine (descriptor "lever_looks") plays its look's
## cue in every chapter that names one, from the change (a selector from its
## event too), under the control's own identity; one with no look keeps the
## shared lever and switch cues.
func _check_look_cues() -> void:
	var kinds: Array = LeverLooks.LEVER_KINDS + LeverLooks.SELECTOR_KINDS
	_check(kinds.size() == SoundCues.LOOK_CUES.size() and kinds.all(func(kind): return SoundCues.LOOK_CUES.has(kind)), "Every lever look has its own cues and no cue names a look that does not exist")
	var looked := 0
	for key: String in Golden.GOLDEN_KEYS:
		var chapter := Index.data(key)
		var looks: Dictionary = chapter.get("lever_looks", {})
		if looks.is_empty() or not Registry.is_cooperative(key): continue
		for id: String in looks:
			var kind := str(looks[id])
			var pair: Array = SoundCues.LOOK_CUES[kind]
			looked += 1
			if kind in LeverLooks.LEVER_KINDS:
				var seen := ChapterSoundMap.remember({"role": "a", "levers": {id: false}, "events": []})
				var pulled := ChapterSoundMap.cues(key, {"role": "a", "levers": {id: true}, "events": ["lever"]}, seen)
				var let_go := ChapterSoundMap.cues(key, {"role": "b", "levers": {id: false}, "events": []}, seen)
				var source := "lever:%s|lever:%s" % [id, id]
				_check(pulled.cues == [pair[0]] and pulled.sources == [source], "A %s pulled plays its own cue under its own name: %s %s %s" % [kind, key, id, pulled])
				_check(let_go.cues == [pair[1]] and let_go.sources == [source], "A %s let go (here the memory's) plays its let-go cue: %s %s %s" % [kind, key, id, let_go])
			else:
				var water: Dictionary = chapter.get("water_levels", {})
				var levels: Array = water.get(id, ["one", "two"])
				var seen := ChapterSoundMap.remember({"role": "a", "controls": {id: levels[0]}, "events": []})
				var turned := ChapterSoundMap.cues(key, {"role": "a", "controls": {id: levels[1]}, "events": ["selector:" + id]}, seen)
				var expected: Array = [pair[0], "water_rise"] if water.has(id) else [pair[0]]
				_check(turned.cues == expected and turned.sources[0] == "selector:%s|selector:%s" % [id, id], "A %s turned plays its own cue, and its water still moves: %s %s %s" % [kind, key, id, turned])
				var event_only := ChapterSoundMap.cues(key, {"role": "b", "events": ["selector:" + id]})
				_check(event_only.cues == [pair[0]] and event_only.sources == turned.sources.slice(0, 1), "A %s heard from its event alone plays the same cue and identity: %s %s" % [kind, key, id])
	_check(looked > 0, "Some pinned chapter draws a control as a machine")
	# Turn of the Tide's sluice lever and slipway winch have no look.
	var plain_seen := ChapterSoundMap.remember({"role": "a", "levers": {"sluice": false}, "controls": {"winch": "stowed"}, "events": []})
	var plain := ChapterSoundMap.cues("turn-of-the-tide@1", {"role": "a", "levers": {"sluice": true}, "controls": {"winch": "slip"}, "events": []}, plain_seen)
	_check(plain.cues == ["lever_pulled", "switch_set"], "A control with no look keeps the shared lever and switch cues: " + str(plain))

## The same look cue under the same identity sounds the same stream, pitch and
## gain in two fresh soundscapes: live, as the memory, on a retry, in a replay.
func _check_look_identity() -> void:
	var names: Array = []
	for kind: String in SoundCues.LOOK_CUES:
		for cue: String in SoundCues.LOOK_CUES[kind]:
			if cue not in names: names.append(cue)
	var heard: Array = []
	for run in range(2):
		var sound: Node = Soundscape.new()
		root.add_child(sound)
		sound.configure({"sound": true, "haptics": false})
		sound.max_cues_per_frame = 0
		sound.variation.seed = 1 + run * 99
		sound.begin_turn("turn-of-the-tide@2", "slack-water")
		var trace: Array = []
		for cue: String in names:
			for ordinal in range(2):
				sound.consume_turn_events([cue], ["lever:probe|lever:probe"], run == 0)
				var voice: AudioStreamPlayer = sound.voices[(sound.next_voice + sound.voices.size() - 1) % sound.voices.size()]
				trace.append([cue, voice.stream, snappedf(voice.pitch_scale, 0.00001), snappedf(voice.volume_db, 0.0001)])
		heard.append(trace)
		sound.free()
	var own_clips := true
	for item: Array in heard[0]: own_clips = own_clips and item[1] == SoundCues.CUES[item[0]].clip and item[1] != SoundCues.CATCH
	_check(own_clips, "Each look cue plays its own clip, not the shared lever click")
	_check(heard[0] == heard[1], "The same look cue and identity give the same stream, pitch and gain in a fresh soundscape")
	_check(heard[0][0][2] != heard[0][1][2], "A look's next pull under the same name moves its pitch")

func _events() -> Array:
	var names: Dictionary = {}
	for event: String in EVENTS: names[event] = true
	for suite: String in ReplayGolden.SUITES:
		var path: String = Golden.GOLDEN_DIR + suite + ".json"
		var replay: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not _check(replay is Dictionary and replay.get("chapters") is Dictionary, "Replay golden lists the events real fixtures emit: " + path): continue
		for chapter: Variant in replay.chapters.values():
			for event: Variant in chapter.get("events", []):
				names[str(event)] = true
	var result := names.keys()
	result.sort()
	return result

func _chapter(key: String, events: Array) -> Dictionary:
	var preview := RelayPreview.new()
	var parts := _stubs(preview)
	preview.chapter_key = key
	preview.chapter = Registry.descriptor(key)
	preview.definition = Registry.definition(key)
	preview.checkpoint = Registry.initial_checkpoint(key)
	preview.role = "a"
	preview.mode = "play"
	preview.running = true
	preview.settings = {"sound": false, "haptics": false}
	var result := _map(preview, parts, events, key)
	_free(preview, parts)
	return result

func _lighthouse(events: Array) -> Dictionary:
	var preview := LighthousePreview.new()
	var parts := _stubs(preview)
	preview.stage = LightCatalog.definition(LightCatalog.STAGE_IDS[0])
	preview.checkpoint = {"stage_index": 0}
	preview.role = "a"
	preview.mode = "play"
	preview.running = true
	preview.backgrounded = false
	preview.settings = {"sound": false, "haptics": false}
	var result := _map(preview, parts, events, LIGHTHOUSE)
	_free(preview, parts)
	return result

func _stubs(preview: Node) -> Dictionary:
	var parts := {"sim": EventSim.new(), "sound": SoundRecorder.new(), "world": WorldStub.new(), "controls": ControlsStub.new()}
	preview.sim = parts.sim
	preview.soundscape = parts.sound
	preview.world = parts.world
	preview.controls = parts.controls
	return parts

## One tick per event, then every event in a single tick to pin order.
func _map(preview: Node, parts: Dictionary, events: Array, label: String) -> Dictionary:
	var single: Dictionary = {}
	for event: String in events:
		parts.sim.events = [event]
		var before: int = parts.sound.calls.size()
		preview.advance_input({})
		if not _check(parts.sound.calls.size() == before + 1, "Controller hands the soundscape one batch per tick: %s %s" % [label, event]): continue
		var call: Dictionary = parts.sound.calls[-1]
		_check(call.live, "Live play marks the batch as live: %s %s" % [label, event])
		_check(call.sources.size() == call.events.size(), "Every cue names the event that caused it: %s %s" % [label, event])
		single[event] = {"cues": call.events, "audible": _audible(call.events)}
	parts.sim.events = events.duplicate()
	var before_all: int = parts.sound.calls.size()
	preview.advance_input({})
	var together: Array = parts.sound.calls[-1].events if parts.sound.calls.size() == before_all + 1 else []
	_check(parts.world.presented == events.size() + 1, "Every tick still reaches the world: " + label)
	_check(parts.controls.updates == events.size() + 1, "Every tick still reaches the HUD: " + label)
	var expected_together: Array = []
	for event: String in events: expected_together.append_array(single.get(event, {}).get("cues", []))
	_check(together == expected_together, "A tick's events keep their order and map one by one: " + label)
	return {"single": single, "together": together}

func _audible(cues: Array) -> Array:
	var result: Array = []
	for cue: Variant in cues: result.append(Soundscape.CLIPS.has(str(cue)))
	return result

func _free(preview: Node, parts: Dictionary) -> void:
	for name: String in ["sound", "world", "controls"]:
		if is_instance_valid(parts[name]): parts[name].free()
	preview.free()
