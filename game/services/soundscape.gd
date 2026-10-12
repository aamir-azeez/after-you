extends Node
## Presentation-only sound. Consume events once per simulation step, never snapshot.
## In a recorded turn, pitch and gain derive from the event identity
## (chapter, stage, cause, kind, ordinal). Home meetups stay random.

const CLIPS := {
	"bridge_opened": preload("res://assets/audio/bridge.wav"),
	"garden_opened": preload("res://assets/audio/ready.wav"),
	"lift_ready": preload("res://assets/audio/ready.wav"),
	"seed_thrown": preload("res://assets/audio/throw.wav"),
	"seed_landed": preload("res://assets/audio/land.wav"),
	"seed_missed": preload("res://assets/audio/miss.wav"),
	"seed_caught": preload("res://assets/audio/catch.wav"),
	"island_bloomed": preload("res://assets/audio/bloom.wav"),
}
# Semitone offsets per cue. Tonal cues stay inside the C-major ambience bed;
# glides favour upward shifts that small phone speakers still reproduce.
# Miss never rises above its source pitch, and catch never falls below it.
const CUE_STEPS := {
	"bridge_opened": [0, 2, 5],
	"garden_opened": [-3, 0, 2],
	"lift_ready": [-3, 0, 2],
	"seed_thrown": [-2, 0, 2, 4],
	"seed_landed": [0, 2, 4, 7],
	"seed_missed": [-3, -2, 0],
	"seed_caught": [0, 1, 3, 5],
	"island_bloomed": [0, 5, 7],
}
const CUE_DB := -8.0
const CUE_JITTER_DB := 1.0
const MISS_DB_RANGE := Vector2(-1.0, 0.0)
const STEP_DB := -23.0
const STEP_JITTER_DB := 1.5
# Footstep detune in semitones: +/-1.0 is about +/-6%; consecutive contacts
# of one spirit always differ by at least STEP_MIN_MOVE.
const STEP_DETUNE := 1.0
const STEP_MIN_MOVE := 0.3
# Each meetup picks a note other than the one it played last.
const REUNION_STEPS := [-2, 0, 2, 4, 7]
const REUNION_DB := -8.0
const REUNION_JITTER_DB := 0.75
const NO_STEP := 1000
## Chapter name for the earlier islands, which have no registry key.
const ISLANDS_CHAPTER := "earlier-islands"
## Events caused by the first spirit (the replayed memory) and by the second.
## Any other event belongs to the live role.
const FIRST_SPIRIT_EVENTS := ["seed_taken", "seed_thrown", "seed_landed", "seed_missed", "garden_opened", "lift_ready", "handoff_offer"]
const SECOND_SPIRIT_EVENTS := ["seed_caught", "island_bloomed", "garden_bloomed", "relay_filled", "stage_complete", "lift_boarded", "lift_arrived", "loft_opened", "bell", "handoff_claim"]

var sound_enabled := true
var haptics_enabled := true
var backgrounded := false
var ambience: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
const FOOTSTEPS := [preload("res://assets/audio/footstep-1.wav"),preload("res://assets/audio/footstep-2.wav")]
const REUNION := preload("res://assets/audio/reunion.wav")
var step_voices: Array[AudioStreamPlayer] = []
var next_step := 0
var reunion_voice: AudioStreamPlayer
# Private generator for Home meetups only; never reads or advances the global RNG.
var variation := RandomNumberGenerator.new()
var reunion_index := -1
# The turn whose events are playing, and its per-spirit identity state.
var turn_chapter := ""
var turn_stage := ""
var last_steps := {}
var _ordinals := {}
var _step_detunes := {}
var _turn_reunion := -1
var _sources: Array = []

func _init() -> void:
	variation.randomize()

func _ready() -> void:
	reunion_voice=AudioStreamPlayer.new()
	reunion_voice.stream=REUNION
	reunion_voice.volume_db=REUNION_DB
	add_child(reunion_voice)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		voice.volume_db=STEP_DB
		add_child(voice)
		step_voices.append(voice)
	for i in range(5):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = CUE_DB
		add_child(voice)
		voices.append(voice)
	ambience = AudioStreamPlayer.new()
	var bed: AudioStreamWAV = preload("res://assets/audio/ambience.wav").duplicate()
	bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bed.loop_begin = 0
	# Imported WAVs may be QOA-compressed; encoded bytes are not PCM frames.
	bed.loop_end = roundi(bed.get_length() * bed.mix_rate)
	ambience.stream = bed
	ambience.volume_db = -12.0
	add_child(ambience)
	_update_ambience()

func configure(settings: Dictionary) -> void:
	sound_enabled = bool(settings.get("sound", true))
	haptics_enabled = bool(settings.get("haptics", true))
	if not sound_enabled:
		_stop_effects()
	_update_ambience()

func set_backgrounded(value: bool) -> void:
	backgrounded = value
	if value:
		_stop_effects()
	_update_ambience()

## Starts a recorded turn: call wherever its simulation resets to tick zero.
func begin_turn(chapter: String, stage: String) -> void:
	turn_chapter = chapter
	turn_stage = stage
	last_steps.clear()
	_ordinals.clear()
	_step_detunes.clear()
	_turn_reunion = -1

## Leaves recorded play, e.g. for Home, where meetups are random again.
func clear_turn() -> void:
	begin_turn("", "")

func in_turn() -> bool:
	return not turn_chapter.is_empty()

## "cause|event" for a simulation event. Bridges are keyed by the bridge itself.
static func event_source(event: String, live_role: String) -> String:
	if event.begins_with("bridge_open"): return event + "|" + event
	if event in FIRST_SPIRIT_EVENTS: return "a|" + event
	if event in SECOND_SPIRIT_EVENTS: return "b|" + event
	return live_role + "|" + event

## Plays one tick of a recorded turn; sources[i] comes from event_source.
func consume_turn_events(events: Array, sources: Array, live_play: bool) -> void:
	_sources = sources
	consume_events(events, live_play)
	_sources = []

## Counts events replayed silently (a resumed draft) so later cues keep their identity.
func note_turn_events(events: Array, sources: Array) -> void:
	for index in range(events.size()):
		if CLIPS.has(str(events[index])): _cue_variation(str(events[index]), _source_at(sources, index))

func consume_events(events: Array, live_play: bool) -> void:
	var sources := _sources
	for index in range(events.size()):
		var event: Variant = events[index]
		var key := str(event)
		if not CLIPS.has(key):
			continue
		# Identity advances even when muted, so unmuting keeps later pitches.
		var cue := _cue_variation(key, _source_at(sources, index))
		if backgrounded:
			continue
		if sound_enabled and not voices.is_empty():
			var voice: AudioStreamPlayer = voices[next_voice]
			voice.stream = CLIPS[key]
			voice.pitch_scale = semitones_to_pitch(cue.step)
			voice.volume_db = CUE_DB + float(cue.gain)
			voice.play()
			next_voice = (next_voice + 1) % voices.size()
		if live_play and haptics_enabled:
			if event == "seed_caught":
				_emit_haptic(35)
			elif event == "island_bloomed":
				_emit_haptic(85)

static func semitones_to_pitch(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)

## A stable 32-bit digest of an identity; the same on every install.
static func identity_hash(parts: Array) -> int:
	var text := PackedStringArray()
	for part: Variant in parts: text.append(str(part))
	return "|".join(text).md5_text().substr(0, 8).hex_to_int()

static func identity_unit(parts: Array) -> float:
	return float(identity_hash(parts)) / 4294967295.0

func _source_at(sources: Array, index: int) -> String:
	return str(sources[index]) if index < sources.size() else ""

func _next_ordinal(key: String) -> int:
	var ordinal: int = _ordinals.get(key, 0)
	_ordinals[key] = ordinal + 1
	return ordinal

## Step and gain from the cue identity. No repeat of the last step per cause
## and clip; that state is never shared between live player and memory.
func _cue_variation(key: String, source: String) -> Dictionary:
	var cause := source.get_slice("|", 0)
	var kind := source.get_slice("|", 1) if source.contains("|") else key
	var id := [turn_chapter, turn_stage, cause, kind, key, _next_ordinal(cause + "|" + kind + "|" + key)]
	var steps: Array = CUE_STEPS.get(key, [0])
	var chain: String = cause + "|" + CLIPS[key].resource_path
	var previous: int = last_steps.get(chain, NO_STEP)
	var choices: Array = steps.filter(func(step): return step != previous)
	if choices.is_empty():
		choices = steps
	var step: int = choices[identity_hash(id + ["step"]) % choices.size()]
	last_steps[chain] = step
	var range_db: Vector2 = MISS_DB_RANGE if key == "seed_missed" else Vector2(-CUE_JITTER_DB, CUE_JITTER_DB)
	return {"step": step, "gain": lerpf(range_db.x, range_db.y, identity_unit(id + ["gain"]))}

func _emit_haptic(duration_ms: int) -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(duration_ms)

## One contact of a spirit's foot; `spirit` is its slot or role in this world.
func play_footstep(spirit: String = "") -> void:
	var ordinal := _next_ordinal(spirit + "|footstep")
	var id := [turn_chapter, turn_stage, spirit, "footstep", ordinal]
	# Move around a circle of width 2*STEP_DETUNE, skipping an arc around this
	# spirit's previous detune, so its neighbouring steps never share a pitch.
	var span := 2.0 * STEP_DETUNE
	var moved: float = float(_step_detunes.get(spirit, 0.0)) + STEP_DETUNE + lerpf(STEP_MIN_MOVE, span - STEP_MIN_MOVE, identity_unit(id + ["pitch"]))
	var detune := fposmod(moved, span) - STEP_DETUNE
	_step_detunes[spirit] = detune
	if not sound_enabled or backgrounded or step_voices.is_empty():
		return
	var voice := step_voices[next_step % step_voices.size()]
	# Each spirit alternates its own two contacts; the second spirit starts on
	# the other one, so both stepping together still use both samples.
	voice.stream=FOOTSTEPS[(ordinal + (1 if spirit in ["p1", "b"] else 0)) % FOOTSTEPS.size()]
	voice.pitch_scale = semitones_to_pitch(detune)
	voice.volume_db = STEP_DB + lerpf(-STEP_JITTER_DB, STEP_JITTER_DB, identity_unit(id + ["gain"]))
	voice.play()
	next_step+=1

func _stop_effects() -> void:
	stop_reunion()
	for voice in voices:
		voice.stop()
	for voice in step_voices:
		voice.stop()

## In a turn the n-th meetup plays a fixed note; on Home it is random, never the last.
func play_reunion() -> void:
	var index := -1
	var gain := 0.0
	if in_turn():
		var id := [turn_chapter, turn_stage, "", "reunion", _next_ordinal("|reunion")]
		var turn_choices: Array = range(REUNION_STEPS.size()).filter(func(choice): return choice != _turn_reunion)
		index = turn_choices[identity_hash(id + ["note"]) % turn_choices.size()]
		_turn_reunion = index
		gain = lerpf(-REUNION_JITTER_DB, REUNION_JITTER_DB, identity_unit(id + ["gain"]))
	if not sound_enabled or backgrounded or not is_instance_valid(reunion_voice): return
	if index < 0:
		var choices: Array = range(REUNION_STEPS.size()).filter(func(choice): return choice != reunion_index)
		reunion_index = choices[variation.randi_range(0, choices.size() - 1)]
		index = reunion_index
		gain = variation.randf_range(-REUNION_JITTER_DB, REUNION_JITTER_DB)
	reunion_voice.pitch_scale = semitones_to_pitch(REUNION_STEPS[index])
	reunion_voice.volume_db = REUNION_DB + gain
	reunion_voice.play()

func stop_reunion() -> void:
	if is_instance_valid(reunion_voice): reunion_voice.stop()

func _update_ambience() -> void:
	if not is_instance_valid(ambience):
		return
	if not sound_enabled or backgrounded:
		ambience.stop()
	elif not ambience.playing:
		ambience.play()
