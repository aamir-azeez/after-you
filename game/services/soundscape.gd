extends Node
## Presentation-only sound. Consume events once per simulation step, never snapshot.
## In a recorded turn, pitch and gain derive from the event identity
## (chapter, stage, cause, kind, ordinal). Home meetups stay random.

const PlatformSupport = preload("res://services/platform_support.gd")
const CLIPS := {
	"bridge_opened": preload("res://assets/audio/bridge.wav"),
	"garden_opened": preload("res://assets/audio/ready.wav"),
	"lift_ready": preload("res://assets/audio/ready.wav"),
	"seed_thrown": preload("res://assets/audio/throw.wav"),
	"seed_landed": preload("res://assets/audio/land.wav"),
	"seed_missed": preload("res://assets/audio/miss.wav"),
	"seed_caught": preload("res://assets/audio/catch.wav"),
	"island_bloomed": preload("res://assets/audio/bloom.wav"),
	# Cues for mechanisms, reusing the clips above at their own pitches.
	"bell_rung": preload("res://assets/audio/ready.wav"),
	"lever_pulled": preload("res://assets/audio/catch.wav"),
	"switch_set": preload("res://assets/audio/catch.wav"),
	"handoff_offered": preload("res://assets/audio/throw.wav"),
}
# Each cue's pitch slides smoothly within its range, in semitones; tonal
# cues sit around the C-major ambience bed and favour upward shifts that
# small phone speakers still reproduce. A miss never rises above its source
# pitch, and a catch never falls below it.
const CUE_RANGES := {
	"bridge_opened": Vector2(0.0, 5.0),
	"garden_opened": Vector2(-3.0, 2.0),
	"lift_ready": Vector2(-3.0, 2.0),
	"seed_thrown": Vector2(-2.0, 4.0),
	"seed_landed": Vector2(0.0, 7.0),
	"seed_missed": Vector2(-3.0, 0.0),
	"seed_caught": Vector2(0.0, 5.0),
	"island_bloomed": Vector2(0.0, 7.0),
	"bell_rung": Vector2(4.0, 9.0),
	"lever_pulled": Vector2(-5.0, -2.0),
	"switch_set": Vector2(2.0, 5.0),
	"handoff_offered": Vector2(-2.0, 2.0),
}
# A cause's consecutive cues on one clip are at least this far apart.
const CUE_MIN_MOVE := 0.5
const CUE_DB := -8.0
const CUE_JITTER_DB := 1.0
const MISS_DB_RANGE := Vector2(-1.0, 0.0)
const STEP_DB := -23.0
const STEP_JITTER_DB := 1.5
# Footstep detune in semitones: +/-1.0 is about +/-6%; consecutive contacts
# of one spirit always differ by at least STEP_MIN_MOVE.
const STEP_DETUNE := 1.0
const STEP_MIN_MOVE := 0.3
# Each meetup slides to a pitch at least REUNION_MIN_MOVE from the last one.
const REUNION_RANGE := Vector2(-2.0, 7.0)
const REUNION_MIN_MOVE := 1.5
const REUNION_DB := -8.0
const REUNION_JITTER_DB := 0.75
## No previous pitch yet: every pitch in the range is allowed.
const NO_PITCH := INF
## Chapter name for the earlier islands, which have no registry key.
const ISLANDS_CHAPTER := "earlier-islands"
## Events caused by the first spirit (the replayed memory) and by the second.
## Any other event belongs to the live role.
const FIRST_SPIRIT_EVENTS := ["seed_taken", "seed_thrown", "seed_landed", "seed_missed", "garden_opened", "lift_ready", "handoff_offer"]
const SECOND_SPIRIT_EVENTS := ["seed_caught", "island_bloomed", "garden_bloomed", "relay_filled", "stage_complete", "lift_boarded", "lift_arrived", "loft_opened", "bell", "handoff_claim", "beacon_lit", "court_activated"]
## Levers, mirrors, routes and the carried lens can be used by either spirit,
## and their events do not name one, so they keep the live role. A switch is
## named by the switch itself, like a bridge.

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
var reunion_pitch := NO_PITCH
# The turn whose events are playing, and its per-spirit identity state.
var turn_chapter := ""
var turn_stage := ""
var last_steps := {}
var _ordinals := {}
var _step_detunes := {}
var _turn_reunion := NO_PITCH
var _sources: Array = []
var _hold := PackedInt32Array()
## Cues a turn held back (presentation/memory_wait.gd): each keeps the pitch
## and gain it got on its own tick and sounds when released.
var _held_cues: Array[Dictionary] = []

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
	_turn_reunion = NO_PITCH
	_held_cues.clear()

## Leaves recorded play, e.g. for Home, where meetups are random again.
func clear_turn() -> void:
	begin_turn("", "")

func in_turn() -> bool:
	return not turn_chapter.is_empty()

## "cause|event" for a simulation event. Bridges are keyed by the bridge itself.
static func event_source(event: String, live_role: String) -> String:
	if event.begins_with("bridge_open") or event.begins_with("selector:"): return event + "|" + event
	if event in FIRST_SPIRIT_EVENTS: return "a|" + event
	if event in SECOND_SPIRIT_EVENTS: return "b|" + event
	return live_role + "|" + event

## Plays one tick of a recorded turn; sources[i] comes from event_source.
## Cues at the `hold` indices get their identity now but wait for
## release_held_cues().
func consume_turn_events(events: Array, sources: Array, live_play: bool, hold: PackedInt32Array = PackedInt32Array()) -> void:
	_sources = sources
	_hold = hold
	consume_events(events, live_play)
	_sources = []
	_hold = PackedInt32Array()

## Counts events replayed silently (a resumed draft) so later cues keep their
## identity. Cues at the `hold` indices are kept for release_held_cues().
func note_turn_events(events: Array, sources: Array, hold: PackedInt32Array = PackedInt32Array()) -> void:
	for index in range(events.size()):
		var key := str(events[index])
		if not CLIPS.has(key): continue
		var cue := _cue_variation(key, _source_at(sources, index))
		if index in hold: _held_cues.append({"key": key, "step": cue.step, "gain": cue.gain, "live": false})

## Sounds every held cue in the order it was held, at its own pitch.
func release_held_cues() -> int:
	var held := _held_cues.duplicate()
	_held_cues.clear()
	for cue: Dictionary in held: _play_cue(str(cue.key), float(cue.step), float(cue.gain), bool(cue.live))
	return held.size()

func drop_held_cues() -> void:
	_held_cues.clear()

func held_cue_count() -> int:
	return _held_cues.size()

func consume_events(events: Array, live_play: bool) -> void:
	var sources := _sources
	for index in range(events.size()):
		var event: Variant = events[index]
		var key := str(event)
		if not CLIPS.has(key):
			continue
		# Identity advances even when muted, so unmuting keeps later pitches.
		var cue := _cue_variation(key, _source_at(sources, index))
		if index in _hold:
			_held_cues.append({"key": key, "step": cue.step, "gain": cue.gain, "live": live_play})
			continue
		_play_cue(key, float(cue.step), float(cue.gain), live_play)

func _play_cue(key: String, step: float, gain: float, live_play: bool) -> void:
	if backgrounded:
		return
	if sound_enabled and not voices.is_empty():
		var voice: AudioStreamPlayer = voices[next_voice]
		voice.stream = CLIPS[key]
		voice.pitch_scale = semitones_to_pitch(step)
		voice.volume_db = CUE_DB + gain
		voice.play()
		next_voice = (next_voice + 1) % voices.size()
	if live_play and haptics_enabled:
		if key == "seed_caught":
			_emit_haptic(35)
		elif key == "island_bloomed":
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

## A pitch in `span` (semitones, inclusive) at least `gap` from `previous`.
## `unit` in [0, 1] walks the allowed pitches evenly, low to high, so the
## same unit always gives the same pitch. If nothing is far enough from
## `previous`, the whole span is allowed.
static func spread_pitch(span: Vector2, previous: float, gap: float, unit: float) -> float:
	var below := maxf(0.0, minf(previous - gap, span.y) - span.x)
	var above_start := maxf(previous + gap, span.x)
	var above := maxf(0.0, span.y - above_start)
	if below + above <= 0.0:
		return lerpf(span.x, span.y, unit)
	var at := unit * (below + above)
	return span.x + at if below > 0.0 and at <= below else above_start + (at - below)

func _source_at(sources: Array, index: int) -> String:
	return str(sources[index]) if index < sources.size() else ""

func _next_ordinal(key: String) -> int:
	var ordinal: int = _ordinals.get(key, 0)
	_ordinals[key] = ordinal + 1
	return ordinal

## Pitch (semitones) and gain from the cue identity. Each cause keeps its
## consecutive cues on one clip apart; that state is never shared between
## the live player and the memory.
func _cue_variation(key: String, source: String) -> Dictionary:
	var cause := source.get_slice("|", 0)
	var kind := source.get_slice("|", 1) if source.contains("|") else key
	var id := [turn_chapter, turn_stage, cause, kind, key, _next_ordinal(cause + "|" + kind + "|" + key)]
	var chain: String = cause + "|" + CLIPS[key].resource_path
	var step := spread_pitch(CUE_RANGES.get(key, Vector2.ZERO), float(last_steps.get(chain, NO_PITCH)), CUE_MIN_MOVE, identity_unit(id + ["step"]))
	last_steps[chain] = step
	var range_db: Vector2 = MISS_DB_RANGE if key == "seed_missed" else Vector2(-CUE_JITTER_DB, CUE_JITTER_DB)
	return {"step": step, "gain": lerpf(range_db.x, range_db.y, identity_unit(id + ["gain"]))}

func _emit_haptic(duration_ms: int) -> void:
	if PlatformSupport.is_phone():
		Input.vibrate_handheld(duration_ms)

## One contact of a spirit's foot; `spirit` is its slot or role in this world.
func play_footstep(spirit: String = "") -> void:
	var ordinal := _next_ordinal(spirit + "|footstep")
	var id := [turn_chapter, turn_stage, spirit, "footstep", ordinal]
	# Neighbouring steps of one spirit never share a pitch.
	var detune := spread_pitch(Vector2(-STEP_DETUNE, STEP_DETUNE), float(_step_detunes.get(spirit, NO_PITCH)), STEP_MIN_MOVE, identity_unit(id + ["pitch"]))
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

## In a turn the n-th meetup plays a fixed pitch; on Home it is random. Either
## way it slides at least REUNION_MIN_MOVE away from the last meetup.
func play_reunion() -> void:
	var pitch := NO_PITCH
	var gain := 0.0
	if in_turn():
		var id := [turn_chapter, turn_stage, "", "reunion", _next_ordinal("|reunion")]
		pitch = spread_pitch(REUNION_RANGE, _turn_reunion, REUNION_MIN_MOVE, identity_unit(id + ["note"]))
		_turn_reunion = pitch
		gain = lerpf(-REUNION_JITTER_DB, REUNION_JITTER_DB, identity_unit(id + ["gain"]))
	if not sound_enabled or backgrounded or not is_instance_valid(reunion_voice): return
	if pitch == NO_PITCH:
		reunion_pitch = spread_pitch(REUNION_RANGE, reunion_pitch, REUNION_MIN_MOVE, variation.randf())
		pitch = reunion_pitch
		gain = variation.randf_range(-REUNION_JITTER_DB, REUNION_JITTER_DB)
	reunion_voice.pitch_scale = semitones_to_pitch(pitch)
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
