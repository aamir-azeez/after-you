extends Node
## Presentation-only sound. Consume events once per simulation step, never snapshot.

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
# always differ by at least STEP_MIN_MOVE.
const STEP_DETUNE := 1.0
const STEP_MIN_MOVE := 0.3
# Successive meetups inside the window climb the phrase, then wrap.
const REUNION_STEPS := [0, 2, 4, 7]
const REUNION_DB := -8.0
const REUNION_JITTER_DB := 0.75
const REUNION_PHRASE_MS := 6000
const NO_STEP := 1000

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
# Private generator: variation never reads or advances the global RNG.
var variation := RandomNumberGenerator.new()
var last_steps := {}
var last_step_detune := 0.0
var reunion_index := -1
var reunion_at := 0

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

func consume_events(events: Array, live_play: bool) -> void:
	if backgrounded:
		return
	for event in events:
		var key := str(event)
		if sound_enabled and CLIPS.has(key) and not voices.is_empty():
			var voice: AudioStreamPlayer = voices[next_voice]
			voice.stream = CLIPS[key]
			var step := _cue_step(key)
			voice.pitch_scale = semitones_to_pitch(step)
			var range_db: Vector2 = MISS_DB_RANGE if key == "seed_missed" else Vector2(-CUE_JITTER_DB, CUE_JITTER_DB)
			voice.volume_db = CUE_DB + variation.randf_range(range_db.x, range_db.y)
			voice.play()
			next_voice = (next_voice + 1) % voices.size()
		if live_play and haptics_enabled:
			if event == "seed_caught":
				_emit_haptic(35)
			elif event == "island_bloomed":
				_emit_haptic(85)

static func semitones_to_pitch(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)

## Picks a scale step for the cue, never the one this clip used last.
func _cue_step(key: String) -> int:
	var steps: Array = CUE_STEPS.get(key, [0])
	var family: String = CLIPS[key].resource_path
	var previous: int = last_steps.get(family, NO_STEP)
	var choices: Array = steps.filter(func(step): return step != previous)
	if choices.is_empty():
		choices = steps
	var step: int = choices[variation.randi_range(0, choices.size() - 1)]
	last_steps[family] = step
	return step

func _emit_haptic(duration_ms: int) -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(duration_ms)

func play_footstep() -> void:
	if not sound_enabled or backgrounded or step_voices.is_empty():
		return
	var voice := step_voices[next_step % step_voices.size()]
	voice.stream=FOOTSTEPS[next_step % FOOTSTEPS.size()]
	# Move around a circle of width 2*STEP_DETUNE, skipping an arc around the
	# previous detune, so neighbours never share a pitch.
	var span := 2.0 * STEP_DETUNE
	var moved := last_step_detune + STEP_DETUNE + variation.randf_range(STEP_MIN_MOVE, span - STEP_MIN_MOVE)
	last_step_detune = fposmod(moved, span) - STEP_DETUNE
	voice.pitch_scale = semitones_to_pitch(last_step_detune)
	voice.volume_db = STEP_DB + variation.randf_range(-STEP_JITTER_DB, STEP_JITTER_DB)
	voice.play()
	next_step+=1

func _stop_effects() -> void:
	stop_reunion()
	for voice in voices:
		voice.stop()
	for voice in step_voices:
		voice.stop()

func play_reunion() -> void:
	if not sound_enabled or backgrounded or not is_instance_valid(reunion_voice): return
	var now := _now_msec()
	if reunion_index >= 0 and now - reunion_at <= REUNION_PHRASE_MS:
		reunion_index = (reunion_index + 1) % REUNION_STEPS.size()
	else:
		# A fresh phrase starts low enough to climb, on a different note.
		var starts: Array = range(REUNION_STEPS.size() - 1).filter(func(index): return index != reunion_index)
		reunion_index = starts[variation.randi_range(0, starts.size() - 1)]
	reunion_at = now
	reunion_voice.pitch_scale = semitones_to_pitch(REUNION_STEPS[reunion_index])
	reunion_voice.volume_db = REUNION_DB + variation.randf_range(-REUNION_JITTER_DB, REUNION_JITTER_DB)
	reunion_voice.play()

func _now_msec() -> int:
	return Time.get_ticks_msec()

func stop_reunion() -> void:
	if is_instance_valid(reunion_voice): reunion_voice.stop()

func _update_ambience() -> void:
	if not is_instance_valid(ambience):
		return
	if not sound_enabled or backgrounded:
		ambience.stop()
	elif not ambience.playing:
		ambience.play()
