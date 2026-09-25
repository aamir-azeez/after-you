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

func _ready() -> void:
	reunion_voice=AudioStreamPlayer.new()
	reunion_voice.stream=REUNION
	reunion_voice.volume_db=-8.0
	add_child(reunion_voice)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		voice.volume_db=-23.0
		add_child(voice)
		step_voices.append(voice)
	for i in range(5):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -8.0
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
		if sound_enabled and CLIPS.has(str(event)) and not voices.is_empty():
			var voice: AudioStreamPlayer = voices[next_voice]
			voice.stream = CLIPS[str(event)]
			voice.play()
			next_voice = (next_voice + 1) % voices.size()
		if live_play and haptics_enabled:
			if event == "seed_caught":
				_emit_haptic(35)
			elif event == "island_bloomed":
				_emit_haptic(85)

func _emit_haptic(duration_ms: int) -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(duration_ms)

func play_footstep() -> void:
	if not sound_enabled or backgrounded or step_voices.is_empty():
		return
	var voice := step_voices[next_step % step_voices.size()]
	voice.stream=FOOTSTEPS[next_step % FOOTSTEPS.size()]
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
